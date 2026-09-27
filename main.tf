terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project = "cloudwatch-observability-lab"
      Purpose = "portfolio-demo"
    }
  }
}

locals {
  name      = "cloudwatch-observability-lab"
  namespace = "PortfolioLab/Demo"
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

# Delivery starts only after the recipient confirms the email subscription.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch may publish only from alarms in this AWS account.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_iam_policy_document" "alerts" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${local.name}-*"]
    }
  }
}
resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

# Default demo alarm: ten errors in one standard-resolution minute.
resource "aws_cloudwatch_metric_alarm" "demo_errors" {
  alarm_name          = "${local.name}-demo-errors"
  alarm_description   = "Portfolio demo: at least ten simulated errors in a minute."
  namespace           = local.namespace
  metric_name         = "ErrorCount"
  dimensions          = { App = "demo" }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Native AWS metrics are not spoofed by the local demo publisher.
# These alarms attach to existing lab resources, not employer systems.
resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  count               = var.ec2_instance_id == null ? 0 : 1
  alarm_name          = "${local.name}-ec2-high-cpu"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = var.ec2_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count               = var.alb_arn_suffix == null ? 0 : 1
  alarm_name          = "${local.name}-alb-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# Error-rate math avoids alarming on a fixed error count at high volume.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.lambda_function_name == null ? 0 : 1
  alarm_name          = "${local.name}-lambda-error-rate"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  metric_query {
    id          = "rate"
    expression  = "IF(invocations > 0, 100 * errors / invocations, 0)"
    label       = "Lambda error rate (%)"
    return_data = true
  }
  metric_query {
    id          = "errors"
    return_data = false
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      dimensions  = { FunctionName = var.lambda_function_name }
      period      = 60
      stat        = "Sum"
    }
  }
  metric_query {
    id          = "invocations"
    return_data = false
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      dimensions  = { FunctionName = var.lambda_function_name }
      period      = 60
      stat        = "Sum"
    }
  }
}

resource "aws_cloudwatch_dashboard" "lab" {
  dashboard_name = local.name
  dashboard_body = templatefile("${path.module}/dashboard.json", {
    region    = var.aws_region
    namespace = local.namespace
    alarm_arn = aws_cloudwatch_metric_alarm.demo_errors.arn
  })
}

# Select an existing lab log group when running this query in the console.
# Saving a query does not ingest logs or execute a billable query.
resource "aws_cloudwatch_query_definition" "errors" {
  name         = "${local.name}/recent-errors"
  query_string = <<-QUERY
    fields @timestamp, @message, @logStream
    | filter @message like /ERROR|Exception|Traceback/
    | sort @timestamp desc
    | limit 20
  QUERY
}
