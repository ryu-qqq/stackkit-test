# STACKKIT 활용 테스트 레포 
## 🤖 Atlantis를 통한 Terraform 자동화

이 저장소는 [Atlantis](http://prod-atlantis-alb-955214135.ap-northeast-2.elb.amazonaws.com)를 통해 Terraform을 자동화합니다.

### 사용법

1. **Plan 실행**: PR에서 `atlantis plan` 댓글 작성
2. **Apply 실행**: PR 승인 후 `atlantis apply` 댓글 작성

### 명령어

- `atlantis plan` - Terraform plan 실행
- `atlantis apply` - Terraform apply 실행 (승인 필요)
- `atlantis plan -d .` - 특정 디렉토리만 plan
- `atlantis unlock` - 잠금 해제 (필요시)

### 자동 Plan

❌ 수동 Plan 모드 - 댓글로 직접 실행 필요

