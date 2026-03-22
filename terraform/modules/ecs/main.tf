# ECS クラスター
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.env}"
}

# CloudWatch Log Group: コンテナのログ保存先
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project}-${var.env}"
  retention_in_days = 7
}

# IAM: タスク実行ロール（ECRからイメージ取得・CloudWatchへのログ送信に必要）
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project}-${var.env}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets ManagerからDBパスワード・Datadog APIキーを取得する権限
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "secrets-manager-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.db_password_secret_arn, var.datadog_api_key_secret_arn]
    }]
  })
}

# IAM: タスクロール（コンテナ内からSQSにアクセスするために必要）
resource "aws_iam_role" "ecs_task" {
  name = "${var.project}-${var.env}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_sqs" {
  name = "sqs-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:*"]
      Resource = "*"
    }]
  })
}

# タスク定義: app（nginx + php-fpm）
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-${var.env}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = var.nginx_image
      essential = true
      portMappings = [{
        containerPort = 80
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "nginx"
        }
      }
    },
    {
      name      = "app"
      image     = var.app_image
      essential = true
      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "APP_KEY", value = var.app_key },
        { name = "DB_CONNECTION", value = "mysql" },
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_DATABASE", value = var.db_name },
        { name = "DB_USERNAME", value = var.db_username },
        { name = "REDIS_HOST", value = var.redis_host },
        { name = "CACHE_STORE", value = "redis" },
        { name = "SESSION_DRIVER", value = "redis" },
        { name = "QUEUE_CONNECTION", value = "sqs" },
        { name = "SQS_PREFIX", value = var.sqs_prefix },
        { name = "SQS_QUEUE", value = var.sqs_queue },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "DD_AGENT_HOST", value = "localhost" },
        { name = "DD_TRACE_AGENT_PORT", value = "8126" },
        { name = "DD_LOGS_INJECTION", value = "true" },
        { name = "DD_TRACE_LARAVEL_ENABLED", value = "true" },
      ]
      secrets = [
        { name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "app"
        }
      }
    },
    {
      name      = "datadog-agent"
      image     = "public.ecr.aws/datadog/agent:7"
      essential = false
      environment = [
        { name = "DD_SITE",                        value = "ap1.datadoghq.com" },
        { name = "ECS_FARGATE",                    value = "true" },
        { name = "DD_APM_ENABLED",                 value = "true" },
        { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC", value = "true" },
        { name = "DD_LOGS_ENABLED",                value = "false" },
        { name = "DD_PROCESS_AGENT_ENABLED",       value = "false" },
        { name = "DD_ENV",                         value = var.env },
        { name = "DD_SERVICE",                     value = "${var.project}-app" },
      ]
      secrets = [
        { name = "DD_API_KEY", valueFrom = var.datadog_api_key_secret_arn },
      ]
      portMappings = [
        { containerPort = 8126, protocol = "tcp" },
        { containerPort = 8125, protocol = "udp" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "datadog-agent"
        }
      }
    }
  ])
}

# タスク定義: worker（php-fpm で queue:work を実行）
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project}-${var.env}-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = var.app_image
      essential = true
      command   = ["php", "artisan", "queue:work", "sqs", "--sleep=3", "--tries=3"]
      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "APP_KEY", value = var.app_key },
        { name = "DB_CONNECTION", value = "mysql" },
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_DATABASE", value = var.db_name },
        { name = "DB_USERNAME", value = var.db_username },
        { name = "REDIS_HOST", value = var.redis_host },
        { name = "CACHE_STORE", value = "redis" },
        { name = "SESSION_DRIVER", value = "redis" },
        { name = "QUEUE_CONNECTION", value = "sqs" },
        { name = "SQS_PREFIX", value = var.sqs_prefix },
        { name = "SQS_QUEUE", value = var.sqs_queue },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "LOG_CHANNEL", value = "stderr" },
        { name = "DD_AGENT_HOST", value = "localhost" },
        { name = "DD_TRACE_AGENT_PORT", value = "8126" },
        { name = "DD_LOGS_INJECTION", value = "true" },
        { name = "DD_TRACE_LARAVEL_ENABLED", value = "true" },
        { name = "DD_TRACE_QUEUE_PROPAGATION_ENABLED", value = "true" },
      ]
      secrets = [
        { name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "worker"
        }
      }
    },
    {
      name      = "datadog-agent"
      image     = "public.ecr.aws/datadog/agent:7"
      essential = false
      environment = [
        { name = "DD_SITE",                        value = "ap1.datadoghq.com" },
        { name = "ECS_FARGATE",                    value = "true" },
        { name = "DD_APM_ENABLED",                 value = "true" },
        { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC", value = "true" },
        { name = "DD_LOGS_ENABLED",                value = "false" },
        { name = "DD_PROCESS_AGENT_ENABLED",       value = "false" },
        { name = "DD_ENV",                         value = var.env },
        { name = "DD_SERVICE",                     value = "${var.project}-worker" },
      ]
      secrets = [
        { name = "DD_API_KEY", valueFrom = var.datadog_api_key_secret_arn },
      ]
      portMappings = [
        { containerPort = 8126, protocol = "tcp" },
        { containerPort = 8125, protocol = "udp" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "datadog-agent"
        }
      }
    }
  ])
}

# タスク定義: batch（feeds:fetch を単発実行）
resource "aws_ecs_task_definition" "batch" {
  family                   = "${var.project}-${var.env}-batch"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.app_image
      essential = true
      command   = ["php", "artisan", "feeds:fetch"]
      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "APP_KEY", value = var.app_key },
        { name = "DB_CONNECTION", value = "mysql" },
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_DATABASE", value = var.db_name },
        { name = "DB_USERNAME", value = var.db_username },
        { name = "REDIS_HOST", value = var.redis_host },
        { name = "CACHE_STORE", value = "redis" },
        { name = "SESSION_DRIVER", value = "redis" },
        { name = "QUEUE_CONNECTION", value = "sqs" },
        { name = "SQS_PREFIX", value = var.sqs_prefix },
        { name = "SQS_QUEUE", value = var.sqs_queue },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "DD_AGENT_HOST", value = "localhost" },
        { name = "DD_TRACE_AGENT_PORT", value = "8126" },
        { name = "DD_LOGS_INJECTION", value = "true" },
        { name = "DD_TRACE_LARAVEL_ENABLED", value = "true" },
        { name = "DD_TRACE_CLI_ENABLED", value = "true" },
      ]
      secrets = [
        { name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "batch"
        }
      }
    },
    {
      name      = "datadog-agent"
      image     = "public.ecr.aws/datadog/agent:7"
      essential = false
      environment = [
        { name = "DD_SITE",                        value = "ap1.datadoghq.com" },
        { name = "ECS_FARGATE",                    value = "true" },
        { name = "DD_APM_ENABLED",                 value = "true" },
        { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC", value = "true" },
        { name = "DD_LOGS_ENABLED",                value = "false" },
        { name = "DD_PROCESS_AGENT_ENABLED",       value = "false" },
        { name = "DD_ENV",                         value = var.env },
        { name = "DD_SERVICE",                     value = "${var.project}-batch" },
      ]
      secrets = [
        { name = "DD_API_KEY", valueFrom = var.datadog_api_key_secret_arn },
      ]
      portMappings = [
        { containerPort = 8126, protocol = "tcp" },
        { containerPort = 8125, protocol = "udp" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "datadog-agent"
        }
      }
    }
  ])
}

# ECS Service: app（ALBと紐付け）
resource "aws_ecs_service" "app" {
  name            = "${var.project}-${var.env}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "nginx"
    container_port   = 80
  }
}

# ECS Service: worker（ALBなし・常時起動）
resource "aws_ecs_service" "worker" {
  name            = "${var.project}-${var.env}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_sg_id]
    assign_public_ip = false
  }
}
