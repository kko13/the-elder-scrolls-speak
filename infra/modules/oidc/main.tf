terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

variable "name_prefix"     { type = string }
variable "github_owner"    { type = string }
variable "github_repo"     { type = string }
variable "allowed_refs"    { type = list(string) }
variable "raw_bucket"      { type = string }
variable "texts_bucket"    { type = string }
variable "audio_bucket"    { type = string }
variable "frontend_bucket" { type = string }
variable "books_table"     { type = string }

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# A single OIDC provider per AWS account; create only if absent in your account.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  subjects = [for ref in var.allowed_refs : "repo:${var.github_owner}/${var.github_repo}:ref:${ref}"]
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subjects
    }
  }
}

resource "aws_iam_role" "gha" {
  name               = "${var.name_prefix}-gha"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# Permissions: read-only most things; write to S3 for deploys/raw caching;
# invoke the ingestion Lambda; query Dynamo for smoke tests; CloudFront invalidations.
data "aws_iam_policy_document" "gha" {
  statement {
    sid     = "S3ReadWrite"
    effect  = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:ListBucket", "s3:GetBucketLocation",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.frontend_bucket}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.frontend_bucket}/*",
      "arn:${data.aws_partition.current.partition}:s3:::${var.raw_bucket}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.raw_bucket}/*",
      "arn:${data.aws_partition.current.partition}:s3:::${var.texts_bucket}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.texts_bucket}/*",
      "arn:${data.aws_partition.current.partition}:s3:::${var.audio_bucket}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.audio_bucket}/*",
    ]
  }

  statement {
    sid       = "DynamoQuery"
    effect    = "Allow"
    actions   = ["dynamodb:Query", "dynamodb:Scan", "dynamodb:GetItem"]
    resources = [
      "arn:${data.aws_partition.current.partition}:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.books_table}",
      "arn:${data.aws_partition.current.partition}:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.books_table}/index/*",
    ]
  }

  statement {
    sid       = "InvokeIngestion"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction", "lambda:UpdateFunctionCode", "lambda:GetFunction"]
    resources = ["arn:${data.aws_partition.current.partition}:lambda:*:${data.aws_caller_identity.current.account_id}:function:${var.name_prefix}-*"]
  }

  statement {
    sid       = "CloudFrontInvalidate"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetDistribution", "cloudfront:ListDistributions"]
    resources = ["*"]
  }

  # Terraform itself needs broad permissions; in real life split apply vs deploy
  # roles. For MVP a single role keeps things simple.
  statement {
    sid     = "TerraformBroad"
    effect  = "Allow"
    actions = [
      "iam:*", "s3:*", "dynamodb:*", "lambda:*", "apigateway:*",
      "cloudfront:*", "route53:*", "acm:*", "logs:*", "events:*",
      "sqs:*", "sns:*", "secretsmanager:*", "kms:*", "polly:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "gha" {
  role   = aws_iam_role.gha.id
  policy = data.aws_iam_policy_document.gha.json
}

output "role_arn" { value = aws_iam_role.gha.arn }
