output "role_arn" {
  value = aws_iam_role.service_role.arn
}

output "user_arn" {
  value = module.service_user.iam_user_arn
}

output "user_access_key" {
  value = module.service_user.iam_access_key_id
}

output "user_secret_key" {
  value = module.service_user.iam_access_key_encrypted_secret
  sensitive = true
}

output "cloudfront_arn" {
  value = module.cdn.cloudfront_distribution_arn
  sensitive = true
}
