# terraform/main.tf

resource "aws_s3_bucket" "cv_site" {
  bucket = replace(var.domain_name, ".", "-")
}

resource "aws_s3_bucket_public_access_block" "cv_site" {
  bucket = aws_s3_bucket.cv_site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "cv_site" {
  name                              = "${var.domain_name}-oac"
  description                       = "OAC for CV website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "cv_site" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "cv_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cv_site.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cv_site" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cv_site.arn
  validation_record_fqdns = [for record in aws_route53_record.cv_cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "cv_site" {
  enabled             = true
  default_root_object = "CV.pdf"

  aliases = [var.domain_name]

  origin {
    domain_name              = aws_s3_bucket.cv_site.bucket_regional_domain_name
    origin_id                = "s3-cv-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.cv_site.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-cv-site"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cv_site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_s3_bucket_policy" "cv_site" {
  bucket = aws_s3_bucket.cv_site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.cv_site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cv_site.arn
          }
        }
      }
    ]
  })
}

resource "aws_route53_record" "cv_site" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cv_site.domain_name
    zone_id                = aws_cloudfront_distribution.cv_site.hosted_zone_id
    evaluate_target_health = false
  }
}