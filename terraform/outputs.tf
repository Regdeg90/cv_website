# terraform/outputs.tf

output "bucket_name" {
  value = aws_s3_bucket.cv_site.bucket
}

output "website_url" {
  value = "https://${var.domain_name}"
}

output "base_api_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}