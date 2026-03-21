output "app_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "nginx_repository_url" {
  value = aws_ecr_repository.nginx.repository_url
}
