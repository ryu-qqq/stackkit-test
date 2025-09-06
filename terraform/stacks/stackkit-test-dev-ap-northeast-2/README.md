# 

## 빠른 시작
```bash
cd 
terraform init -backend-config=backend.hcl -reconfigure
terraform plan -out=plan.tfplan
terraform apply -auto-approve plan.tfplan
```

## 참고
- 원격 상태 S3/DynamoDB가 미리 있어야 합니다.
- 공통 태그: Environment/Project/Component/ManagedBy (OPA 정책)
