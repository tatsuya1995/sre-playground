# ALB本体: パブリックサブネットに配置してインターネットからのトラフィックを受ける
resource "aws_lb" "main" {
  name               = "${var.project}-${var.env}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
}

# ターゲットグループ: ALBがリクエストを転送する先（ECS app）
resource "aws_lb_target_group" "app" {
  name        = "${var.project}-${var.env}-app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

# HTTPリスナー: 80番ポートでリクエストを受けてターゲットグループに転送
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
