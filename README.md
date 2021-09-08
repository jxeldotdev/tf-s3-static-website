## s3-static-website-cloudfront

Basic Terraform module to deploy a static website using S3+Cloudfront.
CloudFlare is used for DNS.

## Resources

* CloudFront Distribution
* ACM Certificate
* S3 Bucket
* Cloudflare DNS Records

* IAM Policy
* IAM Role
* IAM User
* IAM Access Keys

## Required providers

| Name                                                                               | Version |
|------------------------------------------------------------------------------------|---------|
| [aws](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)           | 3.40.0  |
| [Cloudflare](https://registry.terraform.io/providers/cloudflare/cloudflare/latest) | 2.21.0  |
|                                                                                    |         |
