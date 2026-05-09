# terraform/outputs.tf

output "bucket_name" {
  value = aws_s3_bucket.cv_site.bucket
}

output "website_url" {
  value = "https://${var.domain_name}"
}