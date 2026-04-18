terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

variable "name_prefix"     { type = string }
variable "raw_bucket"      { type = string }
variable "texts_bucket"    { type = string }
variable "books_table"     { type = string }
variable "books_table_arn" { type = string }
variable "package_path"    { type = string }

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------- IAM ----------

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest" {
  name               = "${var.name_prefix}-ingest"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.ingest.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "ingest" {
  statement {
    actions = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.raw_bucket}",
      "arn:aws:s3:::${var.raw_bucket}/*",
      "arn:aws:s3:::${var.texts_bucket}",
      "arn:aws:s3:::${var.texts_bucket}/*",
    ]
  }
  statement {
    actions = [
      "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
      "dynamodb:Query", "dynamodb:BatchWriteItem",
    ]
    resources = [
      var.books_table_arn,
      "${var.books_table_arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "ingest" {
  role   = aws_iam_role.ingest.id
  policy = data.aws_iam_policy_document.ingest.json
}

# ---------- Lambda ----------

resource "aws_lambda_function" "ingest" {
  function_name = "${var.name_prefix}-ingest"
  role          = aws_iam_role.ingest.arn
  filename      = var.package_path
  source_code_hash = filebase64sha256(var.package_path)
  handler       = "ingestion.handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 900   # 15 min — full Skyrim crawl
  memory_size   = 1024

  environment {
    variables = {
      RAW_BUCKET   = var.raw_bucket
      TEXTS_BUCKET = var.texts_bucket
      BOOKS_TABLE  = var.books_table
      USER_AGENT   = "tes-speak-ingest/0.1 (+https://github.com/your-org/the-elder-scrolls-speak)"
    }
  }
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 14
}

# Scheduled monthly refresh
resource "aws_cloudwatch_event_rule" "monthly" {
  name                = "${var.name_prefix}-ingest-monthly"
  schedule_expression = "cron(0 6 1 * ? *)"
}

resource "aws_cloudwatch_event_target" "monthly" {
  rule      = aws_cloudwatch_event_rule.monthly.name
  target_id = "ingest"
  arn       = aws_lambda_function.ingest.arn
  input     = jsonencode({ game = "skyrim" })
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly.arn
}

output "lambda_name" { value = aws_lambda_function.ingest.function_name }
output "lambda_arn"  { value = aws_lambda_function.ingest.arn }
