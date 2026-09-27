variable "aws_region" {
  description = "AWS region for both Terraform and the demo publisher."
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Inbox that will confirm the SNS subscription. Never commit its value."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alert_email))
    error_message = "Provide a valid alert email address."
  }
}

variable "ec2_instance_id" {
  description = "Optional existing lab EC2 instance. Null skips its alarm."
  type        = string
  default     = null
}

variable "alb_arn_suffix" {
  description = "Optional existing lab ALB ARN suffix: app/name/id. Null skips its alarm."
  type        = string
  default     = null
}

variable "lambda_function_name" {
  description = "Optional existing lab Lambda function name. Null skips its alarm."
  type        = string
  default     = null
}
