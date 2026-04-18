terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

variable "name_prefix" { type = string }

# ---------- S3 buckets ----------

resource "aws_s3_bucket" "raw"      { bucket = "${var.name_prefix}-raw" }
resource "aws_s3_bucket" "texts"    { bucket = "${var.name_prefix}-texts" }
resource "aws_s3_bucket" "audio"    { bucket = "${var.name_prefix}-audio" }
resource "aws_s3_bucket" "frontend" { bucket = "${var.name_prefix}-frontend" }

locals {
  buckets = {
    raw      = aws_s3_bucket.raw.id
    texts    = aws_s3_bucket.texts.id
    audio    = aws_s3_bucket.audio.id
    frontend = aws_s3_bucket.frontend.id
  }
}

resource "aws_s3_bucket_public_access_block" "all" {
  for_each                = local.buckets
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "all" {
  for_each = local.buckets
  bucket   = each.value
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "texts" {
  bucket = aws_s3_bucket.texts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    id     = "expire-raw-after-90d"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
  }
}

# ---------- DynamoDB ----------

resource "aws_dynamodb_table" "books" {
  name         = "${var.name_prefix}-books"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "book_id"

  attribute {
    name = "book_id"
    type = "S"
  }
  attribute {
    name = "game"
    type = "S"
  }
  attribute {
    name = "title"
    type = "S"
  }

  global_secondary_index {
    name            = "game-title-index"
    hash_key        = "game"
    range_key       = "title"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery { enabled = true }
}
