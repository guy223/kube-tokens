#!/bin/bash

# Kubernetes 토큰 업데이트 스크립트
# tokens/ 폴더의 토큰 파일들을 사용하여 ~/.kube/config의 user 토큰을 업데이트

set -euo pipefail

# 색깔 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 전역 변수
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKENS_DIR="${SCRIPT_DIR}/tokens"
KUBE_CONFIG="${HOME}/.kube/config"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# 함수: 사용법 출력
usage() {
    echo "사용법: $0 [옵션]"
    echo "옵션:"
    echo "  --dry-run    실제 변경 없이 미리보기 모드"
    echo "  --help       이 도움말 출력"
    exit 0
}

# 함수: 로그 출력
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 함수: yq 설치 확인
check_yq() {
    if ! command -v yq &> /dev/null; then
        log_error "yq가 설치되지 않았습니다. 다음 명령어로 설치하세요:"
        echo "  sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        echo "  sudo chmod +x /usr/local/bin/yq"
        exit 1
    fi
    
    # mikefarah/yq인지 확인
    local version_output=$(yq --version 2>/dev/null || echo "")
    if [[ ! "$version_output" =~ mikefarah ]]; then
        log_error "올바른 yq 버전이 아닙니다. mikefarah/yq가 필요합니다."
        log_error "현재 버전: $version_output"
        exit 1
    fi
}

# 함수: 필수 디렉토리 및 파일 확인
check_prerequisites() {
    if [[ ! -d "$TOKENS_DIR" ]]; then
        log_error "tokens 디렉토리를 찾을 수 없습니다: $TOKENS_DIR"
        exit 1
    fi

    if [[ ! -f "$KUBE_CONFIG" ]]; then
        log_error "kubectl config 파일을 찾을 수 없습니다: $KUBE_CONFIG"
        exit 1
    fi

    # 백업 디렉토리 생성
    mkdir -p "$BACKUP_DIR"
}

# 함수: 백업 생성
create_backup() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${BACKUP_DIR}/config_${timestamp}.bak"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cp "$KUBE_CONFIG" "$backup_file"
        log_success "백업 생성: $backup_file"
    else
        log_info "Dry-run: 백업을 생성할 예정: $backup_file"
    fi
}

# 함수: 토큰 파일에서 토큰 추출
extract_token_from_file() {
    local token_file="$1"
    local token
    
    # yq를 사용하여 토큰 추출
    token=$(yq eval '.users[0].user.token' "$token_file" 2>/dev/null || echo "")
    
    if [[ -z "$token" || "$token" == "null" ]]; then
        log_warn "토큰을 찾을 수 없습니다: $token_file"
        return 1
    fi
    
    echo "$token"
}

# 함수: kube config에서 user 토큰 업데이트
update_user_token() {
    local user_name="$1"
    local new_token="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run: $user_name의 토큰을 업데이트할 예정"
        return 0
    fi
    
    # yq를 사용하여 토큰 업데이트
    yq eval "(.users[] | select(.name == \"$user_name\") | .user.token) = \"$new_token\"" -i "$KUBE_CONFIG"
    
    if [[ $? -eq 0 ]]; then
        log_success "$user_name의 토큰이 업데이트되었습니다"
        return 0
    else
        log_error "$user_name의 토큰 업데이트에 실패했습니다"
        return 1
    fi
}

# 함수: 파일명에서 context 명 찾기
get_context_name() {
    local filename="$1"
    
    # 파일명 앞부분으로 context 매핑
    case "$filename" in
        niffler2-dev-apse1-k6*)
            echo "niffler2-dev-apse1-k6-cluster"
            ;;
        aws-niffler2-dev-apse1-db*)
            echo "aws-niffler2-dev-apse1-db-cluster"
            ;;
        aws-niffler2-dev-apse1-app*)
            echo "aws-niffler2-dev-apse1-app-cluster"
            ;;
        aws-niffler2-dev-apse1-sandbox*)
            echo "aws-niffler2-dev-apse1-sandbox-cluster"
            ;;
        niffler2-stg-apse1-db*)
            echo "niffler2-stg-apse1-db-cluster"
            ;;
        niffler2-stg-apse1-app*)
            echo "niffler2-stg-apse1-app-cluster"
            ;;
        niffler2-prod-apse1-db*)
            echo "niffler2-prod-apse1-db-cluster"
            ;;
        niffler2-prod-use1-db*)
            echo "niffler2-prod-use1-db-cluster"
            ;;
        niffler2-prod-euc1-db*)
            echo "niffler2-prod-euc1-db-cluster"
            ;;
        *)
            # 매핑되지 않은 경우 원래 파일명 그대로 사용
            echo "$filename"
            ;;
    esac
}

# 함수: kube config에 user가 존재하는지 확인
user_exists() {
    local user_name="$1"
    local exists
    
    exists=$(yq eval ".users[] | select(.name == \"$user_name\") | .name" "$KUBE_CONFIG" 2>/dev/null || echo "")
    
    if [[ -n "$exists" ]]; then
        return 0
    else
        return 1
    fi
}

# 함수: 메인 처리
process_tokens() {
    local token_files=("$TOKENS_DIR"/*.txt)
    local processed=0
    local updated=0
    local skipped=0
    
    if [[ ! -e "${token_files[0]}" ]]; then
        log_warn "tokens 디렉토리에 .txt 파일이 없습니다"
        return 0
    fi
    
    log_info "토큰 업데이트를 시작합니다..."
    echo
    
    for token_file in "${token_files[@]}"; do
        if [[ ! -f "$token_file" ]]; then
            continue
        fi
        
        # 파일명에서 클러스터 이름 추출 (.txt 확장자 제거)
        local filename=$(basename "$token_file")
        local base_filename="${filename%.txt}"
        local cluster_name=$(get_context_name "$base_filename")
        
        log_info "처리 중: $base_filename -> $cluster_name"
        
        # 토큰 추출
        local new_token
        if ! new_token=$(extract_token_from_file "$token_file"); then
            ((skipped = skipped + 1))
            continue
        fi
        
        # kube config에서 해당 user 확인
        if ! user_exists "$cluster_name"; then
            log_warn "kube config에서 user를 찾을 수 없습니다: $cluster_name"
            ((skipped = skipped + 1))
            continue
        fi
        
        # 토큰 업데이트
        if update_user_token "$cluster_name" "$new_token"; then
            ((updated = updated + 1))
            
            # 토큰 업데이트 성공 시 파일 삭제
            if [[ "$DRY_RUN" == "false" ]]; then
                if rm "$token_file" 2>/dev/null; then
                    log_success "토큰 파일 삭제: $filename"
                    # Zone.Identifier 파일도 삭제 (Windows에서 복사 시 생성되는 메타데이터)
                    local zone_file="${token_file}:Zone.Identifier"
                    if [[ -f "$zone_file" ]]; then
                        rm "$zone_file" 2>/dev/null && log_info "Zone 파일 삭제: ${filename}:Zone.Identifier"
                    fi
                else
                    log_warn "토큰 파일 삭제 실패: $filename"
                fi
            else
                log_info "Dry-run: 토큰 파일을 삭제할 예정: $filename"
                if [[ -f "${token_file}:Zone.Identifier" ]]; then
                    log_info "Dry-run: Zone 파일도 삭제할 예정: ${filename}:Zone.Identifier"
                fi
            fi
        else
            ((skipped = skipped + 1))
        fi
        
        ((processed = processed + 1))
        echo
    done
    
    # 결과 요약
    echo "========================================"
    log_info "처리 완료!"
    log_info "총 파일 수: $processed"
    log_success "업데이트된 토큰: $updated"
    if [[ $skipped -gt 0 ]]; then
        log_warn "건너뛴 항목: $skipped"
    fi
    echo "========================================"
}

# 메인 함수
main() {
    # 인수 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log_info "Dry-run 모드 활성화"
                shift
                ;;
            --help)
                usage
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                usage
                ;;
        esac
    done
    
    log_info "Kubernetes 토큰 업데이트 스크립트 시작"
    
    # 사전 검사
    check_yq
    check_prerequisites
    
    # 백업 생성
    create_backup
    
    # 토큰 처리
    process_tokens
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run 모드였습니다. 실제 변경사항은 없습니다."
        log_info "실제로 실행하려면 --dry-run 옵션을 제거하고 다시 실행하세요."
    fi
}

# 스크립트 실행
main "$@"