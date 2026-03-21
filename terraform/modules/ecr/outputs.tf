output "app_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "nginx_repository_url" {
  value = aws_ecr_repository.nginx.repository_url
}

output "repository_arns" {
  description = "ECR repository ARNs"
  value       = [aws_ecr_repository.app.arn, aws_ecr_repository.nginx.arn]
}
