# Terraform SRE Portfolio - Resource List

| category | resource_name | description |
| --- | --- | --- |
| network | aws_vpc | Primary VPC for the application |
| network | aws_internet_gateway | Internet access for public subnets |
| network | aws_subnet_public_1 | Public subnet AZ1 |
| network | aws_subnet_public_2 | Public subnet AZ2 |
| network | aws_subnet_private_1 | Private subnet AZ1 |
| network | aws_subnet_private_2 | Private subnet AZ2 |
| network | aws_route_table_public | Route table for public subnets |
| network | aws_route_table_private | Route table for private subnets |
| network | aws_route_table_association | Associations for subnets |
| network | aws_eip | Elastic IP for NAT Gateway |
| network | aws_nat_gateway | NAT Gateway for private subnet internet access |
| security | aws_security_group_alb | Security group for ALB |
| security | aws_security_group_ecs | Security group for ECS tasks |
| security | aws_security_group_aurora | Security group for Aurora DB |
| security | aws_security_group_redis | Security group for Redis |
| security | aws_security_group_rule | Ingress/Egress rules between services |
| load_balancer | aws_lb | Application Load Balancer |
| load_balancer | aws_lb_target_group | Target group for ECS service |
| load_balancer | aws_lb_listener | HTTP listener |
| load_balancer | aws_lb_listener_rule | Routing rule |
| ecs | aws_ecs_cluster | ECS cluster |
| ecs | aws_ecs_task_definition_web | Task definition for Laravel web service |
| ecs | aws_ecs_task_definition_worker | Task definition for worker |
| ecs | aws_ecs_service_web | ECS service for web |
| ecs | aws_ecs_service_worker | ECS service for worker |
| ecs | aws_appautoscaling_target | ECS autoscaling target |
| ecs | aws_appautoscaling_policy | ECS autoscaling policy |
| ecr | aws_ecr_repository | Container image repository |
| ecr | aws_ecr_lifecycle_policy | Image lifecycle policy |
| aurora | aws_rds_cluster | Aurora MySQL cluster |
| aurora | aws_rds_cluster_instance | Aurora instance |
| aurora | aws_db_subnet_group | DB subnet group |
| aurora | aws_rds_cluster_parameter_group | DB parameter group |
| redis | aws_elasticache_replication_group | Redis cluster |
| redis | aws_elasticache_subnet_group | Redis subnet group |
| redis | aws_elasticache_parameter_group | Redis parameter group |
| queue | aws_sqs_queue_main | Primary SQS queue |
| queue | aws_sqs_queue_dlq | Dead letter queue |
| queue | aws_sqs_queue_policy | Queue access policy |
| logs | aws_cloudwatch_log_group_web | Log group for web service |
| logs | aws_cloudwatch_log_group_worker | Log group for worker service |
| iam | aws_iam_role_task_execution | Task execution role |
| iam | aws_iam_role_task | Application task role |
| iam | aws_iam_policy_task | Task policy |
| iam | aws_iam_role_policy_attachment | Attach policies to roles |
| observability | datadog_monitor_ecs_cpu | Datadog monitor for ECS CPU |
| observability | datadog_monitor_aurora_cpu | Datadog monitor for Aurora CPU |
| observability | datadog_dashboard_service | Datadog dashboard |
