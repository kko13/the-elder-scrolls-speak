terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.60"
      configuration_aliases = [aws.us_east_1]
    }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

variable "name_prefix"       { type = string }
variable "frontend_bucket"   { type = string }
variable "audio_bucket"      { type = string }
variable "audio_bucket_arn"  { type = string }
variable "api_origin_domain" { type = string }

data "aws_s3_bucket" "frontend" { bucket = var.frontend_bucket }
data "aws_s3_bucket" "audio"    { bucket = var.audio_bucket }

# ---------- Origin Access Control (OAC) ----------

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.name_prefix}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "audio" {
  name                              = "${var.name_prefix}-audio-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------- Signing key for audio ----------

resource "tls_private_key" "audio_signing" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_secretsmanager_secret" "audio_signing" {
  name = "${var.name_prefix}-audio-signing-key"
}

resource "aws_secretsmanager_secret_version" "audio_signing" {
  secret_id     = aws_secretsmanager_secret.audio_signing.id
  secret_string = tls_private_key.audio_signing.private_key_pem
}

resource "aws_cloudfront_public_key" "audio" {
  name        = "${var.name_prefix}-audio-pubkey"
  encoded_key = tls_private_key.audio_signing.public_key_pem
  comment     = "Used to verify signed URLs for audio bucket"
}

resource "aws_cloudfront_key_group" "audio" {
  name  = "${var.name_prefix}-audio-keygroup"
  items = [aws_cloudfront_public_key.audio.id]
}

# ---------- SPA distribution ----------

resource "aws_cloudfront_distribution" "spa" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.name_prefix} SPA"

  origin {
    domain_name              = data.aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "spa-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    domain_name = var.api_origin_domain
    origin_id   = "api"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "spa-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "api"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ---------- Audio distribution (signed URLs) ----------

resource "aws_cloudfront_distribution" "audio" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.name_prefix} audio (signed URLs)"

  origin {
    domain_name              = data.aws_s3_bucket.audio.bucket_regional_domain_name
    origin_id                = "audio-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.audio.id
  }

  default_cache_behavior {
    target_origin_id       = "audio-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    trusted_key_groups     = [aws_cloudfront_key_group.audio.id]
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ---------- Bucket policies (allow only the matching distribution) ----------

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.frontend_bucket}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.spa.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.frontend_bucket
  policy = data.aws_iam_policy_document.frontend_bucket.json
}

data "aws_iam_policy_document" "audio_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.audio_bucket_arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.audio.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "audio" {
  bucket = var.audio_bucket
  policy = data.aws_iam_policy_document.audio_bucket.json
}

output "spa_distribution_id"        { value = aws_cloudfront_distribution.spa.id }
output "spa_distribution_domain"    { value = aws_cloudfront_distribution.spa.domain_name }
output "audio_distribution_domain"  { value = aws_cloudfront_distribution.audio.domain_name }
output "signing_key_pair_id"        { value = aws_cloudfront_public_key.audio.id }
output "signing_private_key_secret_arn" { value = aws_secretsmanager_secret.audio_signing.arn }
