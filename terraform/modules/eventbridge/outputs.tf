output "schedule_arn" {
  description = "EventBridge schedule ARN"
  value       = aws_scheduler_schedule.feeds_fetch.arn
}
