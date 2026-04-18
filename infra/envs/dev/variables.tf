variable "region" {
  type    = string
  default = "us-east-1"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "github_owner" {
  type        = string
  description = "GitHub org/user that owns the repo (for OIDC trust)."
}

variable "github_repo" {
  type        = string
  description = "GitHub repo name (for OIDC trust)."
  default     = "the-elder-scrolls-speak"
}

variable "github_allowed_refs" {
  type        = list(string)
  description = "Git refs allowed to assume the GitHub Actions role."
  default = [
    "refs/heads/main",
    "refs/heads/claude/*",
    "refs/pull/*/merge",
  ]
}

variable "ingestion_package_path" {
  type        = string
  description = "Path to the prebuilt ingestion Lambda zip."
  default     = "../../../backend/dist/ingestion.zip"
}

variable "tts_package_path" {
  type        = string
  description = "Path to the prebuilt TTS Lambda zip."
  default     = "../../../backend/dist/tts.zip"
}

variable "api_package_path" {
  type        = string
  description = "Path to the prebuilt API Lambda zip."
  default     = "../../../backend/dist/api.zip"
}
