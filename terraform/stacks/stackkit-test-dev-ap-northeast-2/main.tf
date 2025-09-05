locals {
  name        = var.project_name
  environment = var.environment
  region      = var.aws_region

  # OPA(terraform.rego)에서 요구하는 필수 태그
  common_tags = {
    Project     = local.name
    Environment = local.environment
    Component   = local.name
    ManagedBy   = "terraform"
    CreatedBy   = "stackkit-cli"
  }
}

# provider는 stacks 레벨에서만! (modules/ 내 선언 금지)
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

# VPC 모듈
module "vpc" {
  source = "../../modules/vpc"

  project_name = local.name
  environment  = local.environment

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  enable_nat_gateway   = false # 비용 절약을 위해 NAT Gateway 비활성화

  common_tags = local.common_tags
}

# S3 버킷 모듈 - 테스트용 버킷
module "test_bucket" {
  source = "../../modules/s3"

  project_name       = local.name
  environment        = local.environment
  bucket_name        = "test-logs"
  versioning_enabled = true

  # 라이프사이클 규칙 - 30일 후 IA로 이동 (backend "local" 테스트)
  lifecycle_rules = [
    {
      id     = "logs_lifecycle"
      status = "Enabled"
      transitions = [
        {
          days          = 45
          storage_class = "STANDARD_IA"
        }
      ]
    }
  ]

  common_tags = local.common_tags
}

# 테스트용 추가 리소스 - Atlantis 테스트를 위한 더미 출력
resource "null_resource" "atlantis_test" {
  triggers = {
    timestamp = timestamp()
  }
  
  provisioner "local-exec" {
    command = "echo 'Atlantis test triggered at ${timestamp()}'"
  }
  
  lifecycle {
    create_before_destroy = true
  }
}
