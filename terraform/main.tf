# terraform/main.tf

terraform {
  backend "s3" {}
}

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
  default_root_object = "index.html"

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

# Dynamo DB
resource "aws_dynamodb_table" "cv_stats" {
  name         = "${var.environment}-cv-stats"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = "cv-website"
  }
}

resource "aws_iam_policy" "dynamodb_access_cv_stats" {
  name = "${var.environment}-cv-dynamodb-cv-stats-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.cv_stats.arn
      }
    ]
  })
}


### API ###
resource "aws_apigatewayv2_api" "cv_api" {
  name          = "cv-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "view_counter" {
  api_id                 = aws_apigatewayv2_api.cv_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.view_counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "views" {
  api_id    = aws_apigatewayv2_api.cv_api.id
  route_key = "POST /views"

  target = "integrations/${aws_apigatewayv2_integration.view_counter.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.cv_api.id
  name        = "$default"
  auto_deploy = true
}



#### LAMDA FUNCTIONS ####
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.dynamodb_access_cv_stats.arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.view_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.cv_api.execution_arn}/*/*"
}

resource "aws_lambda_function" "view_counter" {
  function_name = "${var.environment}-view-counter"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  filename         = "../ui/lambda/view_counter/lambda.zip"
  source_code_hash = filebase64sha256("../ui/lambda/view_counter/lambda.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.cv_stats.name
    }
  }
}

### Subscription Infrastructure ###

resource "aws_sns_topic" "cv_updates" {
  name = "${var.environment}-cv-updates"
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.cv_updates.arn
    }
  }
}

resource "aws_iam_role_policy" "subscribe_lambda_sns" {
  name = "${var.environment}-subscribe-lambda-sns"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Subscribe"
        ]
        Resource = aws_sns_topic.cv_updates.arn
      }
    ]
  })
}
