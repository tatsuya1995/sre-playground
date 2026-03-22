variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password_secret_id" {
  type = string
}

variable "app_key" {
  type      = string
  sensitive = true
}

variable "sqs_queue" {
  type    = string
  default = "articles"
}

variable "github_repo" {
  description = "GitHub repository (e.g. owner/repo)"
  type        = string
}

variable "datadog_api_key_secret_id" {
  description = "Secrets Manager secret ID for Datadog API Key"
  type        = string
}
