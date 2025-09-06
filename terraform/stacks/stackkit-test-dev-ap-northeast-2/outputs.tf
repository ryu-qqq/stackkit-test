output "stack_name" {
  description = "스택 식별자(name-env-region)"
  value       = "${var.project_name}-${var.environment}-${var.aws_region}"
}

# VPC 출력값
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR 블록"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = module.vpc.private_subnet_ids
}

# S3 버킷 출력값
output "test_bucket_name" {
  description = "테스트 S3 버킷 이름"
  value       = module.test_bucket.bucket_name
}

output "test_bucket_arn" {
  description = "테스트 S3 버킷 ARN"
  value       = module.test_bucket.bucket_arn
}