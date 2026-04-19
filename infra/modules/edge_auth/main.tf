terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.60"
      configuration_aliases = [aws.us_east_1]
    }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

variable "name_prefix" { type = string }

# The edge function is just a tiny inline Node.js script. Generated and zipped
# at apply time so we don't keep a JS source tree in repo.
locals {
  edge_source = <<-EOT
    'use strict';
    // Replace this constant with a base64("user:pass") via your CI before publish.
    const EXPECTED = 'Basic ${base64encode("admin:CHANGE_ME")}';
    exports.handler = (event, _ctx, callback) => {
      const req = event.Records[0].cf.request;
      const headers = req.headers;
      if (headers.authorization && headers.authorization[0].value === EXPECTED) {
        return callback(null, req);
      }
      callback(null, {
        status: '401',
        statusDescription: 'Unauthorized',
        headers: {
          'www-authenticate': [{ key: 'WWW-Authenticate', value: 'Basic realm="tes-speak"' }],
        },
        body: 'Authentication required',
      });
    };
  EOT
}

data "archive_file" "edge" {
  type        = "zip"
  output_path = "${path.module}/edge.zip"
  source { content = local.edge_source, filename = "index.js" }
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "edge" {
  provider           = aws.us_east_1
  name               = "${var.name_prefix}-edge-auth"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  provider   = aws.us_east_1
  role       = aws_iam_role.edge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "edge" {
  provider         = aws.us_east_1
  function_name    = "${var.name_prefix}-edge-auth"
  role             = aws_iam_role.edge.arn
  filename         = data.archive_file.edge.output_path
  source_code_hash = data.archive_file.edge.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  publish          = true
  timeout          = 5
  memory_size      = 128
}

output "qualified_arn" { value = aws_lambda_function.edge.qualified_arn }
