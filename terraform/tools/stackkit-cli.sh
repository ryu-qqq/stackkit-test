#!/usr/bin/env bash
set -euo pipefail

# =========================================
# StackKit CLI – 스택 생성/검증/배포 보조 스크립트
# 구조: terraform/{modules,policies,stacks,tools}
# =========================================

# 색상/아이콘
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
INFO="ℹ️"; OK="✅"; ERR="❌"; WARN="⚠️"

# terraform 루트 및 도구 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="${TERRAFORM_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"   # default: terraform
TOOLS_DIR="$TERRAFORM_ROOT/tools"
POLICY_DIR="$TERRAFORM_ROOT/policies"

log()   { echo -e "${BLUE}${INFO} $*${NC}"; }
ok()    { echo -e "${GREEN}${OK} $*${NC}"; }
warn()  { echo -e "${YELLOW}${WARN} $*${NC}"; }
fail()  { echo -e "${RED}${ERR} $*${NC}"; exit 1; }

usage() {
  cat <<EOF
${INFO} StackKit CLI

사용법:
  $(basename "$0") create <name> <env> [region] [--state-bucket BUCKET] [--lock-table TABLE]
  $(basename "$0") init   <name> <env> [region] [--backend false]
  $(basename "$0") plan   <name> <env> [region] [--tfvars FILE]
  $(basename "$0") apply  <name> <env> [region] [--tfvars FILE]
  $(basename "$0") validate <name> <env> [region]

인자:
  <name>   : 스택 이름(레포/서비스 명 등, 예: my-service)
  <env>    : dev | prod
  [region] : 기본 ap-northeast-2

규칙:
  - 스택 경로: terraform/stacks/<name>-<env>-<region>/
  - 필수 파일: versions.tf, variables.tf, main.tf, outputs.tf, backend.hcl, terraform.tfvars
  - 정책 가드:
      - 쉘 가드 : terraform/tools/tf_forbidden.sh
      - OPA     : terraform/policies/terraform.rego (tfplan.json 기반)
EOF
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "$1 명령을 찾을 수 없습니다."; }

# 기본값
DEFAULT_REGION="ap-northeast-2"

# 경로 도우미
stack_dir() {
  local name="$1" env="$2" region="${3:-$DEFAULT_REGION}"
  echo "$TERRAFORM_ROOT/stacks/${name}-${env}-${region}"
}

# 인자 파싱 공통
parse_common_args() {
  local name="$1" env="$2"; shift 2
  local region="${1:-$DEFAULT_REGION}"
  echo "$name" "$env" "$region"
}

# 템플릿 작성기
write_versions_tf() {
  cat > "$1/versions.tf" <<'HCL'
terraform {
  required_version = ">= 1.6.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
HCL
}

write_variables_tf() {
  cat > "$1/variables.tf" <<'HCL'
variable "project_name" {
  type        = string
  description = "프로젝트/스택 이름"
}

variable "environment" {
  type        = string
  description = "환경 (dev|prod)"
  validation {
    condition     = contains(["dev","prod"], var.environment)
    error_message = "environment must be one of dev|prod."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-northeast-2"
}
HCL
}

write_main_tf() {
  cat > "$1/main.tf" <<'HCL'
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

# 여기부터 modules 조립 예시(주석)
# module "example" {
#   source = "../../modules/s3-log-bucket"
#   name   = "${local.name}-${local.environment}-logs"
# }
HCL
}

write_outputs_tf() {
  cat > "$1/outputs.tf" <<'HCL'
output "stack_name" {
  description = "스택 식별자(name-env-region)"
  value       = "${var.project_name}-${var.environment}-${var.aws_region}"
}

# 필요시 module 출력값을 노출하세요.
HCL
}

write_backend_hcl() {
  local dir="$1" name="$2" env="$3" region="$4" bucket="$5" table="$6"
  cat > "$dir/backend.hcl" <<HCL
bucket         = "${bucket}"
key            = "stacks/${name}-${env}-${region}/terraform.tfstate"
region         = "${region}"
dynamodb_table = "${table}"
encrypt        = true
HCL
}

write_tfvars() {
  local dir="$1" name="$2" env="$3" region="$4"
  cat > "$dir/terraform.tfvars" <<HCL
project_name = "${name}"
environment  = "${env}"
aws_region   = "${region}"
HCL
}

write_readme() {
  local dir="$1" rel="$(realpath --relative-to="$(pwd)" "$dir" 2>/dev/null || echo "$dir")"
  cat > "$dir/README.md" <<MD
# ${rel}

## 빠른 시작
\`\`\`bash
cd ${rel}
terraform init -backend-config=backend.hcl -reconfigure
terraform plan -out=plan.tfplan
terraform apply -auto-approve plan.tfplan
\`\`\`

## 참고
- 원격 상태 S3/DynamoDB가 미리 있어야 합니다.
- 공통 태그: Environment/Project/Component/ManagedBy (OPA 정책)
MD
}

# 스택 생성
cmd_create() {
  need_cmd terraform
  local name="$1" env="$2" region="${3:-$DEFAULT_REGION}"; shift $#
  # 옵션 파싱
  local state_bucket="stackkit-tfstate-${env}"
  local lock_table="${env}-tf-lock"

  # 추가 옵션
  for ((i=1; i<="$#"; i++)); do :; done
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state-bucket) state_bucket="$2"; shift 2;;
      --lock-table)   lock_table="$2";   shift 2;;
      *) shift 1;;
    esac
  done

  local dir; dir="$(stack_dir "$name" "$env" "$region")"
  mkdir -p "$dir"

  log "스택 생성: $dir"
  write_versions_tf  "$dir"
  write_variables_tf "$dir"
  write_main_tf      "$dir"
  write_outputs_tf   "$dir"
  write_backend_hcl  "$dir" "$name" "$env" "$region" "$state_bucket" "$lock_table"
  write_tfvars       "$dir" "$name" "$env" "$region"
  write_readme       "$dir"

  ok  "필수 파일 생성 완료"
  echo "   - versions.tf, variables.tf, main.tf, outputs.tf, backend.hcl, terraform.tfvars, README.md"
  echo "   - state bucket: ${state_bucket}, lock table: ${lock_table}"
}

# init (로컬 검증용은 backend 비활성화 지원)
cmd_init() {
  need_cmd terraform
  local name="$1" env="$2" region="${3:-$DEFAULT_REGION}"
  local backend=true
  shift 3 || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backend) backend="$2"; shift 2;;
      *) shift 1;;
    esac
  done

  local dir; dir="$(stack_dir "$name" "$env" "$region")"
  [[ -d "$dir" ]] || fail "스택 디렉터리가 없습니다: $dir"

  log "terraform init ($dir)"
  if [[ "$backend" == "false" ]]; then
    (cd "$dir" && terraform init -backend=false -reconfigure)
  else
    (cd "$dir" && terraform init -backend-config=backend.hcl -reconfigure)
  fi
  ok "init 완료"
}

pick_tfvars() {
  local dir="$1" env="$2" custom="${3:-}"
  if [[ -n "$custom" && -f "$dir/$custom" ]]; then
    echo "$custom"; return
  fi
  if [[ -f "$dir/${env}.tfvars" ]]; then
    echo "${env}.tfvars"; return
  fi
  echo "terraform.tfvars"
}

cmd_plan() {
  need_cmd terraform
  local name="$1" env="$2" region="${3:-$DEFAULT_REGION}"
  shift 3 || true
  local tfvars=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tfvars) tfvars="$2"; shift 2;;
      *) shift 1;;
    esac
  done

  local dir; dir="$(stack_dir "$name" "$env" "$region")"
  [[ -d "$dir" ]] || fail "스택 디렉터리가 없습니다: $dir"
  (cd "$dir" && terraform init -backend-config=backend.hcl -reconfigure)

  local picked; picked="$(pick_tfvars "$dir" "$env" "$tfvars")"
  log "tfvars 사용: $picked"
  (cd "$dir" && terraform plan -var-file="$picked" -out=plan.tfplan)
  ok "plan 완료 → $dir/plan.tfplan"

  # tfplan.json 추출(OPA용)
  if command -v conftest >/dev/null 2>&1; then
    (cd "$dir" && terraform show -json plan.tfplan > tfplan.json)
    ok "tfplan.json 생성 (OPA용)"
  fi
}

cmd_apply() {
  need_cmd terraform
  local name="$1" env="$2" region="${3:-$DEFAULT_REGION}"
  shift 3 || true
  local tfvars=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tfvars) tfvars="$2"; shift 2;;
      *) shift 1;;
    esac
  done

  local dir; dir="$(stack_dir "$name" "$env" "$region")"
  [[ -d "$dir" ]] || fail "스택 디렉터리가 없습니다: $dir"
  (cd "$dir" && terraform init -backend-config=backend.hcl -reconfigure)

  # plan이 없으면 생성
  if [[ ! -f "$dir/plan.tfplan" ]]; then
    local picked; picked="$(pick_tfvars "$dir" "$env" "$tfvars")"
    log "tfvars 사용: $picked"
    (cd "$dir" && terraform plan -var-file="$picked" -out=plan.tfplan)
  fi

  (cd "$dir" && terraform apply -auto-approve plan.tfplan)
  ok "apply 완료"
}

cmd_validate() {
  need_cmd terr_
