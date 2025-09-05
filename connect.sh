#!/bin/bash
set -euo pipefail

# 🔗 Connect Repository to Atlantis
# 저장소에 Atlantis 설정을 자동으로 추가하는 스크립트

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

show_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
 ____  _             _    _  _ _ _     ____                            _
/ ___|| |_ __ _  ___| | _| |/ (_) |_  / ___|___  _ __  _ __   ___  ___| |_
\___ \| __/ _` |/ __| |/ / ' /| | __|| |   / _ \| '_ \| '_ \ / _ \/ __| __|
 ___) | || (_| | (__|   <| . \| | |_ | |__| (_) | | | | | | |  __/ (__| |_
|____/ \__\__,_|\___|_|\_\_|\_\_|\__| \____\___/|_| |_|_| |_|\___|\___|\__|

🔗 Connect Repository to Atlantis
자동으로 저장소에 Atlantis 설정 추가
EOF
    echo -e "${NC}"
}


show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

🏗️  StackKit 표준 호환 - Atlantis 저장소 연결 스크립트

이 스크립트를 Terraform 프로젝트 루트에서 실행하세요.

StackKit 표준 변수 지원:
    환경변수 TF_STACK_REGION    AWS 리전 (기본: ap-northeast-2)
    환경변수 ATLANTIS_*         GitHub Secrets의 ATLANTIS_ 접두사 변수들

Options:
    --atlantis-url URL      Atlantis 서버 URL (필수)
    --repo-name NAME        저장소 이름 (예: myorg/myrepo)
    --project-dir DIR       Terraform 프로젝트 디렉토리 (기본: .)
    --github-token TOKEN    GitHub Personal Access Token (ATLANTIS_GITHUB_TOKEN 우선)
    --webhook-secret SECRET GitHub 웹훅 시크릿 (기존 시크릿 사용 또는 자동 생성)
    --secret-name NAME      Atlantis Secrets Manager 이름 (시크릿 동기화용)
    --aws-region REGION     AWS 리전 (TF_STACK_REGION 우선, 기본: ap-northeast-2)
    --auto-plan            자동 plan 활성화 (기본: false)
    --auto-merge           자동 merge 활성화 (기본: false)
    --skip-webhook         웹훅 설정 건너뛰기
    --enable-ai-reviewer   AI 리뷰어 활성화
    --ai-review-bucket     AI 리뷰용 S3 버킷 이름
    --help                 이 도움말 표시

Examples:
    # GitHub 웹훅 자동 설정 포함 (Atlantis 시크릿과 동기화)
    $0 --atlantis-url https://atlantis.company.com \\
       --repo-name myorg/myrepo \\
       --github-token ghp_xxxxxxxxxxxx \\
       --secret-name prod-atlantis-secrets

    # 웹훅 설정 없이 설정 파일만 생성
    $0 --atlantis-url https://atlantis.company.com \\
       --repo-name myorg/myrepo \\
       --skip-webhook

    # AI 리뷰어와 함께 설정
    $0 --atlantis-url https://atlantis.company.com \\
       --repo-name myorg/myrepo \\
       --github-token ghp_xxxxxxxxxxxx \\
       --secret-name prod-atlantis-secrets \\
       --enable-ai-reviewer \\
       --ai-review-bucket my-ai-review-bucket

    # 참고: OpenAI/Slack 키는 quick-deploy.sh에서 설정됩니다
EOF
}

# Default values (StackKit 표준 호환)
ATLANTIS_URL=""
REPO_NAME=""
PROJECT_DIR="."
GITHUB_TOKEN=""
WEBHOOK_SECRET=""
SECRET_NAME=""
TF_VERSION="1.8.5"
TF_STACK_REGION="${TF_STACK_REGION:-ap-northeast-2}"
AWS_REGION="${TF_STACK_REGION}"
AUTO_PLAN=false
AUTO_MERGE=false
SKIP_WEBHOOK=false
ENABLE_AI_REVIEWER=false
AI_REVIEW_BUCKET=""

# StackKit 호환 - 환경변수에서 값 읽기 (GitHub Actions/Secrets용)
ATLANTIS_GITHUB_TOKEN="${ATLANTIS_GITHUB_TOKEN:-$GITHUB_TOKEN}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --atlantis-url) ATLANTIS_URL="$2"; shift 2 ;;
        --repo-name) REPO_NAME="$2"; shift 2 ;;
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --github-token) GITHUB_TOKEN="$2"; shift 2 ;;
        --webhook-secret) WEBHOOK_SECRET="$2"; shift 2 ;;
        --secret-name) SECRET_NAME="$2"; shift 2 ;;
        --aws-region) AWS_REGION="$2"; shift 2 ;;
        --auto-plan) AUTO_PLAN=true; shift ;;
        --auto-merge) AUTO_MERGE=true; shift ;;
        --skip-webhook) SKIP_WEBHOOK=true; shift ;;
        --enable-ai-reviewer) ENABLE_AI_REVIEWER=true; shift ;;
        --ai-review-bucket) AI_REVIEW_BUCKET="$2"; shift 2 ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# Validation
if [[ -z "$ATLANTIS_URL" ]]; then
    log_error "Atlantis URL이 필요합니다."
    show_help
    exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
    # GitHub remote에서 자동으로 repo 이름 추출 시도
    if git remote -v >/dev/null 2>&1; then
        REPO_NAME=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[/:]||' | sed 's|\.git$||' || echo "")
        if [[ -n "$REPO_NAME" ]]; then
            log_info "GitHub remote에서 저장소 이름 자동 탐지: $REPO_NAME"
        fi
    fi

    if [[ -z "$REPO_NAME" ]]; then
        log_error "저장소 이름이 필요합니다."
        show_help
        exit 1
    fi
fi

# AI Reviewer validation
if [[ "$ENABLE_AI_REVIEWER" == true ]]; then
    if [[ -z "$AI_REVIEW_BUCKET" ]]; then
        log_error "AI 리뷰어가 활성화되었지만 S3 버킷이 지정되지 않았습니다. --ai-review-bucket 옵션이 필요합니다."
        show_help
        exit 1
    fi
fi

show_banner

# Sync webhook secret with Atlantis Secrets Manager
sync_webhook_secret() {
    if [[ -z "$WEBHOOK_SECRET" ]]; then
        if [[ -n "$SECRET_NAME" ]]; then
            log_info "Atlantis Secrets Manager에서 웹훅 시크릿 조회 중..."

            # AWS CLI 사용 가능한지 확인
            if ! command -v aws >/dev/null 2>&1; then
                log_warning "AWS CLI가 설치되지 않았습니다. 새 시크릿을 생성합니다."
                WEBHOOK_SECRET=$(openssl rand -hex 20)
                return
            fi

            # 기존 시크릿에서 webhook_secret 조회
            EXISTING_SECRET=$(aws secretsmanager get-secret-value \
                --region "$AWS_REGION" \
                --secret-id "$SECRET_NAME" \
                --query 'SecretString' \
                --output text 2>/dev/null | jq -r '.webhook_secret // empty' 2>/dev/null)

            if [[ -n "$EXISTING_SECRET" && "$EXISTING_SECRET" != "null" ]]; then
                WEBHOOK_SECRET="$EXISTING_SECRET"
                log_success "기존 Atlantis 웹훅 시크릿 사용: ${WEBHOOK_SECRET:0:8}..."
            else
                log_warning "기존 웹훅 시크릿을 찾을 수 없습니다. 새 시크릿을 생성합니다."
                WEBHOOK_SECRET=$(openssl rand -hex 20)

                # Secrets Manager 업데이트
                update_secrets_manager
            fi
        else
            WEBHOOK_SECRET=$(openssl rand -hex 20)
            log_info "새 웹훅 시크릿 생성: ${WEBHOOK_SECRET:0:8}..."
        fi
    fi
}

# Update Atlantis Secrets Manager with new webhook secret
update_secrets_manager() {
    if [[ -n "$SECRET_NAME" ]] && command -v aws >/dev/null 2>&1; then
        log_info "Atlantis Secrets Manager에 웹훅 시크릿 업데이트 중..."

        # 현재 시크릿 값 조회
        CURRENT_SECRET=$(aws secretsmanager get-secret-value \
            --region "$AWS_REGION" \
            --secret-id "$SECRET_NAME" \
            --query 'SecretString' \
            --output text 2>/dev/null)

        if [[ -n "$CURRENT_SECRET" ]]; then
            # 기존 시크릿에 webhook_secret 추가/업데이트
            UPDATED_SECRET=$(echo "$CURRENT_SECRET" | jq --arg secret "$WEBHOOK_SECRET" '. + {"webhook_secret": $secret}')

            aws secretsmanager update-secret \
                --region "$AWS_REGION" \
                --secret-id "$SECRET_NAME" \
                --secret-string "$UPDATED_SECRET" >/dev/null 2>&1

            if [[ $? -eq 0 ]]; then
                log_success "Atlantis Secrets Manager 웹훅 시크릿 업데이트 완료"
            else
                log_warning "Secrets Manager 업데이트 실패. 수동으로 webhook_secret 키를 추가하세요."
            fi
        fi
    fi
}

# StackKit 표준 호환 - 환경변수 우선 처리
if [[ -n "$ATLANTIS_GITHUB_TOKEN" ]]; then
    GITHUB_TOKEN="$ATLANTIS_GITHUB_TOKEN"
    log_info "ATLANTIS_GITHUB_TOKEN 환경변수 사용"
fi

sync_webhook_secret

# Webhook setup validation
if [[ "$SKIP_WEBHOOK" == false ]]; then
    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_warning "GitHub 토큰이 제공되지 않았습니다. 웹훅을 자동 설정하려면 --github-token을 사용하세요."
        log_info "웹훅 설정을 건너뛰려면 --skip-webhook을 사용하세요."
        SKIP_WEBHOOK=true
    fi

    # Check if curl/jq are available
    if ! command -v curl >/dev/null 2>&1; then
        log_warning "curl이 설치되지 않았습니다. 웹훅 설정을 건너뜁니다."
        SKIP_WEBHOOK=true
    fi

    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq가 설치되지 않았습니다. 웹훅 설정을 건너뜁니다."
        SKIP_WEBHOOK=true
    fi
fi

log_info "🏗️  StackKit 표준 호환 설정 확인:"
echo "  Atlantis URL: $ATLANTIS_URL"
echo "  저장소: $REPO_NAME"
echo "  프로젝트 디렉토리: $PROJECT_DIR"
echo "  Terraform 버전: $TF_VERSION"
echo "  자동 Plan: $AUTO_PLAN"
echo "  자동 Merge: $AUTO_MERGE"
echo "  웹훅 자동 설정: $([ "$SKIP_WEBHOOK" == false ] && echo "활성화" || echo "비활성화")"
echo "  AI 리뷰어: $([ "$ENABLE_AI_REVIEWER" == true ] && echo "활성화" || echo "비활성화")"
if [[ "$ENABLE_AI_REVIEWER" == true ]]; then
    echo "  AI 리뷰 S3 버킷: $AI_REVIEW_BUCKET"
    echo "  ※ OpenAI/Slack 키는 quick-deploy.sh에서 설정됨"
fi
if [[ -n "$SECRET_NAME" ]]; then
    echo "  Secrets Manager: $SECRET_NAME"
    echo "  AWS 리전 (TF_STACK_REGION): $AWS_REGION"
fi
echo ""

# Check if we're in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    log_error "Git 저장소가 아닙니다."
    exit 1
fi

# Check if project directory exists
if [[ ! -d "$PROJECT_DIR" ]]; then
    log_error "프로젝트 디렉토리가 존재하지 않습니다: $PROJECT_DIR"
    exit 1
fi

# Check if project directory has Terraform files
if [[ ! -f "$PROJECT_DIR/main.tf" && ! -f "$PROJECT_DIR/versions.tf" ]]; then
    log_warning "프로젝트 디렉토리에 Terraform 파일이 없습니다: $PROJECT_DIR"
fi

log_info "1/4 atlantis.yaml 설정 파일 생성 중..."

# Generate atlantis.yaml with AI Reviewer integration
if [[ "$ENABLE_AI_REVIEWER" == true && -n "$AI_REVIEW_BUCKET" ]]; then
    cat > atlantis.yaml << YAML
version: 3
projects:
- name: $(basename "$REPO_NAME")-$(basename "$PROJECT_DIR")
  dir: $PROJECT_DIR
  terraform_version: v1.8.5
  autoplan:
    when_modified: ["**/*.tf", "**/*.tfvars"]
    enabled: $AUTO_PLAN
  apply_requirements: ["approved", "mergeable"]
  delete_source_branch_on_merge: $AUTO_MERGE
  workflow: ai-review

workflows:
  ai-review:
    plan:
      steps:
      - init
      - plan:
          extra_args: ["-lock-timeout=10m", "-out=\$PLANFILE"]
      - run: |
          set -e  # Don't exit on error initially

          # Extract repo and PR info from environment
          REPO_ORG=\$(echo "\$BASE_REPO_OWNER" | tr '[:upper:]' '[:lower:]')
          REPO_NAME=\$(echo "\$BASE_REPO_NAME" | tr '[:upper:]' '[:lower:]')
          PR_NUM=\$PULL_NUM
          COMMIT_SHA=\$(echo "\$HEAD_COMMIT" | cut -c1-8)
          TIMESTAMP=\$(date -u +%Y%m%d%H%M%S)

          # Generate S3 path for organized storage
          S3_PATH="terraform-plans/\${REPO_ORG}/\${REPO_NAME}/\${PR_NUM}/\${COMMIT_SHA}"

          # Create result metadata
          RESULT_META="{\"repo\":\"\${REPO_ORG}/\${REPO_NAME}\",\"pr\":\${PR_NUM},\"commit\":\"\${COMMIT_SHA}\",\"timestamp\":\"\${TIMESTAMP}\",\"operation\":\"plan\""

          # Check if plan was successful by checking planfile existence
          if [ -f "\$PLANFILE" ]; then
            echo "✅ Plan succeeded - uploading results for AI analysis"
            RESULT_META="\${RESULT_META},\"status\":\"success\"}"

            # Convert plan to JSON and upload
            terraform show -json "\$PLANFILE" > plan.json
            aws s3 cp plan.json "s3://${AI_REVIEW_BUCKET}/\${S3_PATH}/plan.json" \
              --metadata "\${RESULT_META}"

            # Upload plan file as well for debugging
            aws s3 cp "\$PLANFILE" "s3://${AI_REVIEW_BUCKET}/\${S3_PATH}/plan.tfplan" \
              --metadata "\${RESULT_META}"

          else
            echo "❌ Plan failed - uploading error context for AI analysis"
            RESULT_META="\${RESULT_META},\"status\":\"failed\"}"

            # Create error context file
            ERROR_CONTEXT="{\"error\":\"Plan failed\",\"timestamp\":\"\${TIMESTAMP}\",\"logs\":\"Plan execution failed - check Atlantis logs\"}"
            echo "\$ERROR_CONTEXT" > plan_error.json

            # Upload error context
            aws s3 cp plan_error.json "s3://${AI_REVIEW_BUCKET}/\${S3_PATH}/plan_error.json" \
              --metadata "\${RESULT_META}"
          fi

          echo "📤 Plan result uploaded to S3: \${S3_PATH}/"
          echo "🤖 AI will analyze and comment on this PR shortly..."

          # Re-enable strict error handling for any subsequent steps
          set -euo pipefail
    apply:
      steps:
      - apply:
          extra_args: ["-lock-timeout=10m"]
      - run: |
          set -e

          # Extract repo and PR info from environment
          REPO_ORG=\$(echo "\$BASE_REPO_OWNER" | tr '[:upper:]' '[:lower:]')
          REPO_NAME=\$(echo "\$BASE_REPO_NAME" | tr '[:upper:]' '[:lower:]')
          PR_NUM=\$PULL_NUM
          COMMIT_SHA=\$(echo "\$HEAD_COMMIT" | cut -c1-8)
          TIMESTAMP=\$(date -u +%Y%m%d%H%M%S)

          # Generate S3 path for organized storage
          S3_PATH="terraform-plans/\${REPO_ORG}/\${REPO_NAME}/\${PR_NUM}/\${COMMIT_SHA}"

          # Create apply result metadata
          APPLY_META="{\"repo\":\"\${REPO_ORG}/\${REPO_NAME}\",\"pr\":\${PR_NUM},\"commit\":\"\${COMMIT_SHA}\",\"timestamp\":\"\${TIMESTAMP}\",\"operation\":\"apply\""

          # Check apply result by looking at exit code of previous step
          APPLY_EXIT_CODE=\${PIPESTATUS[0]:-0}

          if [ \$APPLY_EXIT_CODE -eq 0 ]; then
            echo "✅ Apply succeeded - uploading results"
            APPLY_META="\${APPLY_META},\"status\":\"success\"}"

            # Create apply success context
            APPLY_RESULT="{\"status\":\"success\",\"timestamp\":\"\${TIMESTAMP}\",\"message\":\"Apply completed successfully\"}"
            echo "\$APPLY_RESULT" > apply_result.json

            # Upload apply results
            aws s3 cp apply_result.json "s3://${AI_REVIEW_BUCKET}/\${S3_PATH}/apply_result.json" \
              --metadata "\${APPLY_META}"

          else
            echo "❌ Apply failed - uploading error context"
            APPLY_META="\${APPLY_META},\"status\":\"failed\"}"

            # Create apply error context
            APPLY_ERROR="{\"status\":\"failed\",\"timestamp\":\"\${TIMESTAMP}\",\"message\":\"Apply failed - check Atlantis logs\",\"exit_code\":\$APPLY_EXIT_CODE}"
            echo "\$APPLY_ERROR" > apply_error.json

            # Upload error context
            aws s3 cp apply_error.json "s3://${AI_REVIEW_BUCKET}/\${S3_PATH}/apply_error.json" \
              --metadata "\${APPLY_META}"
          fi

          echo "📤 Apply result uploaded to S3: \${S3_PATH}/"
          echo "🤖 AI has been notified of the apply result"
YAML
else
    cat > atlantis.yaml << YAML
version: 3
projects:
- name: $(basename "$REPO_NAME")-$(basename "$PROJECT_DIR")
  dir: $PROJECT_DIR
  terraform_version: v1.8.5
  autoplan:
    when_modified: ["**/*.tf", "**/*.tfvars"]
    enabled: $AUTO_PLAN
  apply_requirements: ["approved", "mergeable"]
  delete_source_branch_on_merge: $AUTO_MERGE
  workflow: default

workflows:
  default:
    plan:
      steps:
      - init
      - plan:
          extra_args: ["-lock-timeout=10m"]
    apply:
      steps:
      - apply:
          extra_args: ["-lock-timeout=10m"]
YAML
fi

log_success "atlantis.yaml 파일 생성 완료"

log_info "2/4 .gitignore 업데이트 중..."

# Update .gitignore
GITIGNORE_CONTENT="
# Terraform
*.tfplan
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.tfvars
!terraform.tfvars.example

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo
*~
"

if [[ -f ".gitignore" ]]; then
    # Check if Terraform entries already exist
    if ! grep -q "# Terraform" .gitignore; then
        echo "$GITIGNORE_CONTENT" >> .gitignore
        log_success ".gitignore에 Terraform 관련 항목 추가"
    else
        log_info ".gitignore에 이미 Terraform 관련 항목 존재"
    fi
else
    echo "$GITIGNORE_CONTENT" > .gitignore
    log_success ".gitignore 파일 생성 완료"
fi

log_info "3/4 README.md 업데이트 중..."

# Add Atlantis usage to README
ATLANTIS_SECTION="
## 🤖 Atlantis를 통한 Terraform 자동화

이 저장소는 [Atlantis](${ATLANTIS_URL})를 통해 Terraform을 자동화합니다.

### 사용법

1. **Plan 실행**: PR에서 \`atlantis plan\` 댓글 작성
2. **Apply 실행**: PR 승인 후 \`atlantis apply\` 댓글 작성

### 명령어

- \`atlantis plan\` - Terraform plan 실행
- \`atlantis apply\` - Terraform apply 실행 (승인 필요)
- \`atlantis plan -d ${PROJECT_DIR}\` - 특정 디렉토리만 plan
- \`atlantis unlock\` - 잠금 해제 (필요시)

### 자동 Plan

$(if [[ "$AUTO_PLAN" == true ]]; then
echo "✅ 자동 Plan 활성화됨 - .tf 파일 변경 시 자동으로 plan 실행"
else
echo "❌ 수동 Plan 모드 - 댓글로 직접 실행 필요"
fi)
"

if [[ -f "README.md" ]]; then
    # Check if Atlantis section already exists
    if ! grep -q "Atlantis를 통한 Terraform 자동화" README.md; then
        echo "$ATLANTIS_SECTION" >> README.md
        log_success "README.md에 Atlantis 사용법 추가"
    else
        log_info "README.md에 이미 Atlantis 관련 내용 존재"
    fi
else
    echo "# $(basename "$PWD")" > README.md
    echo "$ATLANTIS_SECTION" >> README.md
    log_success "README.md 파일 생성 완료"
fi

# GitHub webhook auto-setup function
setup_github_webhook() {
    if [[ "$SKIP_WEBHOOK" == true ]]; then
        return 0
    fi

    log_info "GitHub 웹훅 자동 설정 시작..."

    local webhook_url="$ATLANTIS_URL/events"
    local webhook_config=$(cat << EOF
{
  "name": "web",
  "active": true,
  "events": [
    "issue_comment",
    "pull_request",
    "pull_request_review",
    "pull_request_review_comment",
    "push"
  ],
  "config": {
    "url": "$webhook_url",
    "content_type": "json",
    "secret": "$WEBHOOK_SECRET",
    "insecure_ssl": "0"
  }
}
EOF
)

    # Check if webhook already exists
    log_info "기존 웹훅 존재 여부 확인 중..."
    local existing_webhook=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$REPO_NAME/hooks" | \
        jq -r ".[] | select(.config.url == \"$webhook_url\") | .id" 2>/dev/null || echo "")
    
    if [[ -n "$existing_webhook" ]]; then
        log_success "기존 웹훅 발견 (ID: $existing_webhook). 시크릿을 업데이트합니다."
        
        # Update existing webhook with new secret
        local response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            -X PATCH \
            -d "$webhook_config" \
            "https://api.github.com/repos/$REPO_NAME/hooks/$existing_webhook")
    else
        log_info "새 웹훅을 생성합니다."
        
        # Create new webhook
        local response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            -X POST \
            -d "$webhook_config" \
            "https://api.github.com/repos/$REPO_NAME/hooks")
    fi

    local http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    local response_body=$(echo "$response" | sed '/HTTP_STATUS:/d')

    case $http_status in
        201)
            log_success "GitHub 웹훅이 성공적으로 생성되었습니다!"
            local webhook_id=$(echo "$response_body" | jq -r '.id')
            echo "   - 웹훅 ID: $webhook_id"
            echo "   - URL: $webhook_url"
            ;;
        422)
            local error_message=$(echo "$response_body" | jq -r '.errors[0].message // .message')
            if [[ "$error_message" == *"Hook already exists"* ]]; then
                log_warning "웹훅이 이미 존재합니다. 기존 웹훅을 사용합니다."
            else
                log_error "웹훅 생성 실패: $error_message"
                return 1
            fi
            ;;
        401)
            log_error "GitHub 토큰이 잘못되었거나 권한이 없습니다."
            return 1
            ;;
        404)
            log_error "저장소를 찾을 수 없습니다: $REPO_NAME"
            return 1
            ;;
        *)
            log_error "웹훅 생성 실패 (HTTP $http_status): $response_body"
            return 1
            ;;
    esac

    return 0
}

# GitHub repository variables setup function
setup_github_variables() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_warning "GitHub 토큰이 없어서 레포 변수 설정을 건너뜁니다."
        return 0
    fi

    log_info "GitHub 레포 변수 자동 설정 시작..."

    # Set repository variables for Atlantis deployment
    local variables_config='[
        {"name": "ATLANTIS_REGION", "value": "'${AWS_REGION}'"},
        {"name": "ATLANTIS_ORG_NAME", "value": "'${REPO_NAME%/*}'"},
        {"name": "ATLANTIS_ENVIRONMENT", "value": "prod"}
    ]'

    log_info "필수 GitHub Variables 설정 중..."
    echo "$variables_config" | jq -c '.[]' | while IFS= read -r var; do
        name=$(echo "$var" | jq -r '.name')
        value=$(echo "$var" | jq -r '.value')
        
        log_info "변수 설정 중: $name = $value"
        
        # Set repository variable
        local response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -H "Content-Type: application/json" \
            -X POST \
            -d "{\"name\":\"$name\",\"value\":\"$value\"}" \
            "https://api.github.com/repos/$REPO_NAME/actions/variables")

        local http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
        case $http_status in
            201)
                log_success "GitHub Variable '$name' 설정 완료"
                ;;
            409)
                # Variable already exists, try to update
                local update_response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    -H "Content-Type: application/json" \
                    -X PATCH \
                    -d "{\"name\":\"$name\",\"value\":\"$value\"}" \
                    "https://api.github.com/repos/$REPO_NAME/actions/variables/$name")
                
                local update_status=$(echo "$update_response" | grep "HTTP_STATUS:" | cut -d: -f2)
                if [[ "$update_status" == "204" ]]; then
                    log_success "GitHub Variable '$name' 업데이트 완료"
                else
                    log_warning "Variable '$name' 업데이트 실패 (Status: $update_status)"
                fi
                ;;
            *)
                log_warning "Variable '$name' 설정 실패 (Status: $http_status)"
                ;;
        esac
    done

    log_success "GitHub 레포 변수 설정 완료"
}

log_info "4/6 GitHub 웹훅 자동 설정 중..."
setup_github_webhook

log_info "5/6 GitHub 레포 변수 자동 설정 중..."
setup_github_variables

log_info "6/6 설정 요약 출력 중..."

log_success "저장소 Atlantis 연결 설정 완료!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 다음 단계:"
echo ""
echo "1. Atlantis 서버에 이 저장소 추가:"
echo "   - repo_allowlist에 'github.com/$REPO_NAME' 추가"
echo ""

if [[ "$SKIP_WEBHOOK" == true ]]; then
echo "2. GitHub 웹훅 수동 설정:"
echo "   - URL: $ATLANTIS_URL/events"
echo "   - Events: Pull requests, Issue comments, Push"
echo "   - Content type: application/json"
echo "   - Secret: $WEBHOOK_SECRET"
echo ""
else
echo "2. ✅ GitHub 웹훅 자동 설정 완료"
echo ""
fi

echo "3. 변경사항 커밋 및 푸시:"
echo "   git add atlantis.yaml .gitignore README.md"
echo "   git commit -m 'feat: add Atlantis configuration'"
echo "   git push origin main"
echo ""
echo "4. PR 생성하여 테스트:"
echo "   - Terraform 파일 수정 후 PR 생성"
echo "   - 'atlantis plan' 댓글로 테스트"
if [[ "$ENABLE_AI_REVIEWER" == true ]]; then
echo "   - 🤖 AI가 자동으로 plan 분석 및 댓글 작성"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$SKIP_WEBHOOK" == false ]]; then
echo "🔐 보안 정보:"
echo "   - 웹훅 시크릿: $WEBHOOK_SECRET"
echo "   - 이 시크릿을 안전한 곳에 보관하세요"
echo ""
fi

log_success "Happy Infrastructure as Code! 🚀"