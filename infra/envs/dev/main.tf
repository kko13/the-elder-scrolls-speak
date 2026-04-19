terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Configure remote state via env vars / -backend-config:
  #   bucket         = tes-speak-tfstate-<account-id>
  #   key            = envs/dev/terraform.tfstate
  #   region         = us-east-1
  #   dynamodb_table = tes-speak-tflock
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "tes-speak"
      Env     = var.env
      Managed = "terraform"
    }
  }
}

# CloudFront + ACM cert for the SPA need us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "tes-speak"
      Env     = var.env
      Managed = "terraform"
    }
  }
}

locals {
  name_prefix = "tes-speak-${var.env}"
}

module "storage" {
  source      = "../../modules/storage"
  name_prefix = local.name_prefix
}

module "oidc" {
  source         = "../../modules/oidc"
  name_prefix    = local.name_prefix
  github_owner   = var.github_owner
  github_repo    = var.github_repo
  allowed_refs   = var.github_allowed_refs
  texts_bucket   = module.storage.texts_bucket_name
  audio_bucket   = module.storage.audio_bucket_name
  raw_bucket     = module.storage.raw_bucket_name
  frontend_bucket = module.storage.frontend_bucket_name
  books_table    = module.storage.books_table_name
}

module "ingestion" {
  source       = "../../modules/ingestion"
  name_prefix  = local.name_prefix
  raw_bucket   = module.storage.raw_bucket_name
  texts_bucket = module.storage.texts_bucket_name
  books_table  = module.storage.books_table_name
  books_table_arn = module.storage.books_table_arn
  package_path = var.ingestion_package_path
}

module "tts" {
  source             = "../../modules/tts"
  name_prefix        = local.name_prefix
  texts_bucket       = module.storage.texts_bucket_name
  audio_bucket       = module.storage.audio_bucket_name
  audio_bucket_arn   = module.storage.audio_bucket_arn
  books_table        = module.storage.books_table_name
  books_table_arn    = module.storage.books_table_arn
  books_stream_arn   = module.storage.books_stream_arn
  package_path       = var.tts_package_path
}

module "frontend" {
  source            = "../../modules/frontend"
  providers         = { aws.us_east_1 = aws.us_east_1 }
  name_prefix       = local.name_prefix
  frontend_bucket   = module.storage.frontend_bucket_name
  audio_bucket      = module.storage.audio_bucket_name
  audio_bucket_arn  = module.storage.audio_bucket_arn
  api_origin_domain = module.api.api_domain
}

module "api" {
  source           = "../../modules/api"
  name_prefix      = local.name_prefix
  texts_bucket     = module.storage.texts_bucket_name
  audio_bucket     = module.storage.audio_bucket_name
  audio_bucket_arn = module.storage.audio_bucket_arn
  books_table      = module.storage.books_table_name
  books_table_arn  = module.storage.books_table_arn
  cloudfront_key_pair_id = module.frontend.signing_key_pair_id
  cloudfront_private_key_secret_arn = module.frontend.signing_private_key_secret_arn
  cloudfront_audio_domain = module.frontend.audio_distribution_domain
  package_path     = var.api_package_path
}
