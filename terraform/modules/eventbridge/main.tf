# EventBridge Scheduler: feeds:fetch バッチを定期実行する
resource "aws_scheduler_schedule" "feeds_fetch" {
  name                         = "${var.project}-${var.env}-feeds-fetch"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "Asia/Tokyo"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.ecs_cluster_arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = var.task_definition_arn
      launch_type         = "FARGATE"

      network_configuration {
        subnets          = var.private_subnet_ids
        security_groups  = [var.app_sg_id]
        assign_public_ip = false
      }
    }
  }
}

# IAMロール: EventBridge SchedulerがECSタスクを起動するために必要
resource "aws_iam_role" "scheduler" {
  name = "${var.project}-${var.env}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "ecs-run-task"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = var.task_definition_arn
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
      }
    ]
  })
}
