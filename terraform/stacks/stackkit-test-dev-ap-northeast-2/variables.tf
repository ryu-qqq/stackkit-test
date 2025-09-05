variable "project_name" {
  type        = string
  description = "프로젝트/스택 이름"
}

variable "environment" {
  type        = string
  description = "환경 (dev|prod)"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of dev|prod."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-northeast-2"
}
