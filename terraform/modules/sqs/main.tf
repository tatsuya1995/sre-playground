# SQSキュー: Laravelのジョブキュー
resource "aws_sqs_queue" "main" {
  name                       = "${var.project}-${var.env}-${var.queue_name}"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400 # 1日

  tags = {
    Name = "${var.project}-${var.env}-${var.queue_name}"
  }
}
