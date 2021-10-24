variable "domains" {
  type = list(string)
}

variable "zone_id" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "service_role_name" {
  type = string
}

variable "cloudfront_origin_access_identity" {
  type = map(string)
  default = {
    s3_jxel_dev = "Allows CloudFront to Access S3"
  }
}
