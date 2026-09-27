output "dashboard_name" {
  description = "Open this dashboard in the selected region's CloudWatch console."
  value       = aws_cloudwatch_dashboard.lab.dashboard_name
}

output "demo_alarm_name" {
  value = aws_cloudwatch_metric_alarm.demo_errors.alarm_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "metric_namespace" {
  value = local.namespace
}

output "saved_query_id" {
  value = aws_cloudwatch_query_definition.errors.id
}
