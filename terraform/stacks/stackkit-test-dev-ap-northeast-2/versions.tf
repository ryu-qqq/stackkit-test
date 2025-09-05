terraform {
  required_version = ">= 1.6.0, < 2.0.0"
  
  # 테스트용으로 로컬 백엔드 사용 (Atlantis 호환성)
  backend "local" {
    path = "terraform.tfstate"
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
