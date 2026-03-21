variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (e.g. rate(1 hour))"
  type        = string
  default     = "rate(12 hours)"
}

variable "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  type        = string
}

variable "task_definition_arn" {
  description = "ECS task definition ARN to run (batch)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS task"
  type        = list(string)
}

variable "app_sg_id" {
  description = "Security group ID for app"
  type        = string
}
