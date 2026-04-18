terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

variable "name_prefix"                       { type = string }
variable "texts_bucket"                      { type = string }
variable "audio_bucket"                      { type = string }
variable "audio_bucket_arn"                  { type = string }
variable "books_table"                       { type = string }
variable "books_table_arn"                   { type = string }
variable "cloudfront_key_pair_id"            { type = string }
variable "cloudfront_private_key_secret_arn" { type = string }
variable "cloudfront_audio_domain"           { type = string }
variable "package_path"                      { type = string }

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

resource "aws_iam_role" "api" {
  name               = "${var.name_prefix}-api"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "api" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
    resources = [var.books_table_arn, "${var.books_table_arn}/index/*"]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.cloudfront_private_key_secret_arn]
  }
}

resource "aws_iam_role_policy" "api" {
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

# ---------- Lambda ----------

resource "aws_lambda_function" "api" {
  function_name    = "${var.name_prefix}-api"
  role             = aws_iam_role.api.arn
  filename         = var.package_path
  source_code_hash = filebase64sha256(var.package_path)
  handler          = "api.handlers.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 512

  environment {
    variables = {
      BOOKS_TABLE                       = var.books_table
      AUDIO_BUCKET                      = var.audio_bucket
      CLOUDFRONT_AUDIO_DOMAIN           = var.cloudfront_audio_domain
      CLOUDFRONT_KEY_PAIR_ID            = var.cloudfront_key_pair_id
      CLOUDFRONT_PRIVATE_KEY_SECRET_ARN = var.cloudfront_private_key_secret_arn
      SIGNED_URL_TTL_SECONDS            = "3600"
    }
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = 14
}

# ---------- HTTP API ----------

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]    # tighten to CF SPA domain post-launch
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "any" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

output "api_endpoint" { value = aws_apigatewayv2_api.api.api_endpoint }
output "api_domain"   { value = replace(aws_apigatewayv2_api.api.api_endpoint, "https://", "") }
output "api_id"       { value = aws_apigatewayv2_api.api.id }
