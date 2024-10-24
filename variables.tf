variable "github_user" {
  type        = string
  description = "GitHub user"
  default     = "linustannnn"
}

variable "github_token" {
  type        = string
  description = "GitHub token"
}

variable "github_webhook_secret" {
  type        = string
  description = "GitHub webhook secret"
}

variable "github_repo_allow_list" {
  type        = string
  description = "GitHub repo allow list"
  default     = "github.com/linustannnn/terraform-gce-atlantis"
}
