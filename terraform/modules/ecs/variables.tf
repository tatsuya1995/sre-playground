variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_sg_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "app_image" {
  type = string
}

variable "nginx_image" {
  type = string
}

variable "app_key" {
  type      = string
  sensitive = true
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password_secret_arn" {
  type = string
}

variable "redis_host" {
  type = string
}

variable "sqs_prefix" {
  type = string
}

variable "sqs_queue" {
  type    = string
  default = "articles"
}
