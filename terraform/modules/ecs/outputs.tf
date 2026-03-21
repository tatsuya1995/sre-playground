output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "app_task_definition_arn" {
  value = aws_ecs_task_definition.app.arn
}

output "worker_task_definition_arn" {
  value = aws_ecs_task_definition.worker.arn
}

output "batch_task_definition_arn" {
  value = aws_ecs_task_definition.batch.arn
}

output "cluster_arn" {
  value = aws_ecs_cluster.main.arn
}
