output "alb_dns_name" {
  value = module.alb.dns_name
}

output "ecr_app_repository_url" {
  value = module.ecr.app_repository_url
}

output "ecr_nginx_repository_url" {
  value = module.ecr.nginx_repository_url
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_port" {
  value = module.rds.port
}

output "redis_endpoint" {
  value = module.redis.endpoint
}

output "redis_port" {
  value = module.redis.port
}
