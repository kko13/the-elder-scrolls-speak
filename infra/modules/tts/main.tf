terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

variable "name_prefix"      { type = string }
variable "texts_bucket"     { type = string }
variable "audio_bucket"     { type = string }
variable "audio_bucket_arn" { type = string }
variable "books_table"      { type = string }
variable "books_table_arn"  { type = string }
variable "books_stream_arn" { type = string }
variable "package_path"     { type = string }

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

resource "aws_iam_role" "tts" {
  name               = "${var.name_prefix}-tts"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.tts.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "tts" {
  statement {
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${var.texts_bucket}/*",
      "${var.audio_bucket_arn}/*",
    ]
  }
  statement {
    actions   = ["s3:PutObject", "s3:GetObject", "s3:HeadObject"]
    resources = ["${var.audio_bucket_arn}/*"]
  }
  statement {
    actions = [
      "polly:StartSpeechSynthesisTask",
      "polly:GetSpeechSynthesisTask",
      "polly:ListSpeechSynthesisTasks",
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Query",
    ]
    resources = [var.books_table_arn, "${var.books_table_arn}/index/*"]
  }
  statement {
    actions = [
      "dynamodb:DescribeStream", "dynamodb:GetRecords",
      "dynamodb:GetShardIterator", "dynamodb:ListStreams",
    ]
    resources = [var.books_stream_arn]
  }
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.completion.arn]
  }
}

resource "aws_iam_role_policy" "tts" {
  role   = aws_iam_role.tts.id
  policy = data.aws_iam_policy_document.tts.json
}

# ---------- SNS for Polly task completion ----------

resource "aws_sns_topic" "completion" {
  name = "${var.name_prefix}-tts-complete"
}

# ---------- Lambdas ----------

# Submit: triggered by DDB stream, kicks off async Polly task
resource "aws_lambda_function" "submit" {
  function_name    = "${var.name_prefix}-tts-submit"
  role             = aws_iam_role.tts.arn
  filename         = var.package_path
  source_code_hash = filebase64sha256(var.package_path)
  handler          = "tts.handler.submit"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      TEXTS_BUCKET   = var.texts_bucket
      AUDIO_BUCKET   = var.audio_bucket
      BOOKS_TABLE    = var.books_table
      SNS_TOPIC_ARN  = aws_sns_topic.completion.arn
      DEFAULT_ENGINE = "long-form"
    }
  }
}

resource "aws_cloudwatch_log_group" "submit" {
  name              = "/aws/lambda/${aws_lambda_function.submit.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_event_source_mapping" "ddb" {
  event_source_arn  = var.books_stream_arn
  function_name     = aws_lambda_function.submit.arn
  starting_position = "LATEST"
  batch_size        = 10
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
      })
    }
  }
}

# Complete: triggered by SNS when Polly task finishes, writes audio_s3_key to DDB
resource "aws_lambda_function" "complete" {
  function_name    = "${var.name_prefix}-tts-complete"
  role             = aws_iam_role.tts.arn
  filename         = var.package_path
  source_code_hash = filebase64sha256(var.package_path)
  handler          = "tts.handler.complete"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      AUDIO_BUCKET = var.audio_bucket
      BOOKS_TABLE  = var.books_table
    }
  }
}

resource "aws_cloudwatch_log_group" "complete" {
  name              = "/aws/lambda/${aws_lambda_function.complete.function_name}"
  retention_in_days = 14
}

resource "aws_sns_topic_subscription" "complete" {
  topic_arn = aws_sns_topic.completion.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.complete.arn
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.complete.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.completion.arn
}

output "submit_lambda_name"   { value = aws_lambda_function.submit.function_name }
output "complete_lambda_name" { value = aws_lambda_function.complete.function_name }
output "completion_topic_arn" { value = aws_sns_topic.completion.arn }
