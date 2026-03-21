variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository (e.g. owner/repo)"
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs to allow push"
  type        = list(string)
}
