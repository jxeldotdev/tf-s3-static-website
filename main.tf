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
      response_page_path = "/index.html"
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

  depends_on = [aws_route53_record.cert_validation]
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.zone_id
}

resource "aws_route53_record" "domains" {
  for_each = toset(var.domains)

  name            = each.value
  records         = module.cdn.cloudfront_distribution_domain_name
  ttl             = 60
  type            = "CNAME"
  zone_id         = var.zone_id
}

resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name
  acl    = "public-read"
  /* Might need to be changed */
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
