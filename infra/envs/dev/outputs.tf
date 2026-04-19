output "frontend_bucket" {
  value = module.storage.frontend_bucket_name
}

output "frontend_distribution_id" {
  value = module.frontend.spa_distribution_id
}

output "frontend_distribution_domain" {
  value = module.frontend.spa_distribution_domain
}

output "audio_distribution_domain" {
  value = module.frontend.audio_distribution_domain
}

output "api_endpoint" {
  value = module.api.api_endpoint
}

output "books_table_name" {
  value = module.storage.books_table_name
}

output "ingestion_lambda_name" {
  value = module.ingestion.lambda_name
}

output "github_actions_role_arn" {
  value = module.oidc.role_arn
}
