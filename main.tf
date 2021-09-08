module "cdn" {
  source = "terraform-aws-modules/cloudfront/aws"

  aliases = var.domains

  comment             = "S3 Static site"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"
  retain_on_delete    = false
  wait_for_deployment = false
  default_root_object = "index.html"
  custom_error_response = {
    404 = {
      error_code         = 404
      response_code      = 404
      response_page_path = "/404.html"
    }
  }

  create_origin_access_identity = false

  // Required for hugo's paths to work properly
  origin = {
    s3_origin = {
      domain_name = aws_s3_bucket.site.website_endpoint
      custom_origin_config = {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "http-only"
        origin_ssl_protocols   = ["TLSv1"]
      }
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3_origin"
    viewer_protocol_policy = "allow-all"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true
    query_string    = true
  }

  viewer_certificate = {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }

  depends_on = [aws_acm_certificate.cert, aws_acm_certificate_validation.cert]
}

resource "aws_acm_certificate" "cert" {
  domain_name = element(var.domains, 0)
  // All elements in the list excluding the first
  subject_alternative_names = compact([for x in var.domains : x == element(var.domains, 0) ? "" : x])
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in cloudflare_record.validation : record.hostname]

  depends_on = [cloudflare_record.validation]
}

resource "cloudflare_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  name    = each.value.name
  value   = trimsuffix(each.value.record, ".")
  type    = each.value.type
  zone_id = var.zone_id

  depends_on = [aws_acm_certificate.cert]
}

resource "cloudflare_record" "website" {
  for_each = toset(var.domains)
  zone_id  = var.zone_id
  name     = each.key
  type     = "CNAME"
  value    = module.cdn.cloudfront_distribution_domain_name
}

resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name
  acl    = "public-read"
  website {
    index_document = "index.html"
    error_document = "404.html"
  }
}


data "aws_iam_policy_document" "site" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}


resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json

  depends_on = [module.cdn]
}

######################################
## Role used by CI / GitHub Actions ##
######################################

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "service_role" {
  name               = var.service_role_name
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "service_role" {
  role       = aws_iam_role.service_role.name
  policy_arn = module.service_role_policy.arn
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

// required for gh actions to assume role
data "aws_iam_policy_document" "tag_role" {
  statement {
    actions = ["sts:TagSession"]
    resources = ["*"]
  }
}

module "tag_role_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 3.0"

  name        = "AllowTagRoleOnAll"
  path        = "/"
  description = ""
  policy      = data.aws_iam_policy_document.tag_role.json
}

resource "aws_iam_group_policy_attachment" "tag_role_policy" {
  group      = module.service_role_group.group_name
  policy_arn = module.tag_role_policy.arn
}


data "aws_iam_policy_document" "service_role_permissions" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket", "s3:DeleteObject", "s3:PutObject"]
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
  }
  statement {
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
      "cloudfront:GetDistribution"
    ]
    resources = [module.cdn.cloudfront_distribution_arn]
  }
}

module "service_role_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 3.0"

  name        = var.service_role_name
  path        = "/"
  description = "Grants permissions to CI Service role to manage s3 bucket and invalidate cloudfront cache"
  policy      = data.aws_iam_policy_document.service_role_permissions.json

  depends_on = [module.cdn]
}

module "service_role_group" {
  source = "terraform-aws-modules/iam/aws//modules/iam-group-with-assumable-roles-policy"

  name            = var.service_role_group
  assumable_roles = [aws_iam_role.service_role.arn]
  group_users     = [module.service_user.iam_user_name]

  depends_on = [module.service_user, aws_iam_role.service_role]
}

module "service_user" {
  source = "terraform-aws-modules/iam/aws//modules/iam-user"

  name = var.service_user

  create_iam_user_login_profile = false
  create_iam_access_key         = true
  pgp_key                       = var.pgp_key
  force_destroy                 = true
}