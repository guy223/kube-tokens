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
KUBE_CONFIG_CREATED=false

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
        log_warn "kubectl config 파일이 없습니다. 새로 생성합니다: $KUBE_CONFIG"
        mkdir -p "$(dirname "$KUBE_CONFIG")"
        cat > "$KUBE_CONFIG" << 'KUBEEOF'
apiVersion: v1
clusters: []
contexts: []
current-context: ""
kind: Config
preferences: {}
users: []
KUBEEOF
        chmod 600 "$KUBE_CONFIG"
        KUBE_CONFIG_CREATED=true
        log_success "새 kubeconfig 생성: $KUBE_CONFIG"
    fi

    # 백업 디렉토리 생성
    mkdir -p "$BACKUP_DIR"
}

# 함수: 백업 생성
create_backup() {
    if [[ "$KUBE_CONFIG_CREATED" == "true" ]]; then
        log_info "새로 생성된 config 파일이므로 백업을 건너뜁니다"
        return 0
    fi

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

# 함수: 토큰 파일에서 cluster name 추출
extract_cluster_name_from_file() {
    local token_file="$1"
    local name
    name=$(yq eval '.clusters[0].name' "$token_file" 2>/dev/null || echo "")
    if [[ -z "$name" || "$name" == "null" ]]; then
        echo ""
        return 1
    fi
    echo "$name"
}

# 함수: 토큰 파일에서 server URL 추출
extract_server_from_file() {
    local token_file="$1"
    yq eval '.clusters[0].cluster.server' "$token_file" 2>/dev/null || echo ""
}

# 함수: 토큰 파일에서 CA data 추출
extract_ca_data_from_file() {
    local token_file="$1"
    yq eval '.clusters[0].cluster."certificate-authority-data"' "$token_file" 2>/dev/null || echo ""
}

# 함수: 토큰 파일에서 user name 추출
extract_user_name_from_file() {
    local token_file="$1"
    yq eval '.users[0].name' "$token_file" 2>/dev/null || echo ""
}

# 함수: 토큰 파일에서 context name 추출
extract_context_name_from_file() {
    local token_file="$1"
    yq eval '.contexts[0].name' "$token_file" 2>/dev/null || echo ""
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

# 함수: kube config에 cluster가 존재하는지 확인
cluster_exists() {
    local cluster_name="$1"
    local exists
    exists=$(yq eval ".clusters[] | select(.name == \"$cluster_name\") | .name" "$KUBE_CONFIG" 2>/dev/null || echo "")
    [[ -n "$exists" ]]
}

# 함수: kube config에 context가 존재하는지 확인
context_exists() {
    local context_name="$1"
    local exists
    exists=$(yq eval ".contexts[] | select(.name == \"$context_name\") | .name" "$KUBE_CONFIG" 2>/dev/null || echo "")
    [[ -n "$exists" ]]
}

# 함수: kube config에 cluster 항목 추가
add_cluster_to_config() {
    local cluster_name="$1"
    local server="$2"
    local ca_data="$3"

    CLUSTER_NAME="$cluster_name" SERVER_URL="$server" CA_DATA="$ca_data" \
    yq eval '.clusters += [{"cluster": {"certificate-authority-data": strenv(CA_DATA), "server": strenv(SERVER_URL)}, "name": strenv(CLUSTER_NAME)}]' -i "$KUBE_CONFIG"

    if [[ $? -eq 0 ]]; then
        log_success "cluster 항목 추가: $cluster_name"
        return 0
    else
        log_error "cluster 항목 추가 실패: $cluster_name"
        return 1
    fi
}

# 함수: kube config에 context 항목 추가
add_context_to_config() {
    local context_name="$1"
    local cluster_name="$2"
    local user_name="$3"

    CONTEXT_NAME="$context_name" CLUSTER_NAME="$cluster_name" USER_NAME="$user_name" \
    yq eval '.contexts += [{"context": {"cluster": strenv(CLUSTER_NAME), "user": strenv(USER_NAME)}, "name": strenv(CONTEXT_NAME)}]' -i "$KUBE_CONFIG"

    if [[ $? -eq 0 ]]; then
        log_success "context 항목 추가: $context_name"
        return 0
    else
        log_error "context 항목 추가 실패: $context_name"
        return 1
    fi
}

# 함수: kube config에 user 항목 추가
add_user_to_config() {
    local user_name="$1"
    local token="$2"

    USER_NAME="$user_name" TOKEN="$token" \
    yq eval '.users += [{"name": strenv(USER_NAME), "user": {"token": strenv(TOKEN)}}]' -i "$KUBE_CONFIG"

    if [[ $? -eq 0 ]]; then
        log_success "user 항목 추가: $user_name"
        return 0
    else
        log_error "user 항목 추가 실패: $user_name"
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

        # 파일 내부에서 cluster name 추출 (우선), 없으면 파일명 패턴으로 폴백
        local cluster_name
        if ! cluster_name=$(extract_cluster_name_from_file "$token_file") || [[ -z "$cluster_name" || "$cluster_name" == "null" ]]; then
            cluster_name=$(get_context_name "$base_filename")
        fi

        local user_name
        user_name=$(extract_user_name_from_file "$token_file")
        if [[ -z "$user_name" || "$user_name" == "null" ]]; then
            user_name="$cluster_name"
        fi

        local context_name
        context_name=$(extract_context_name_from_file "$token_file")
        if [[ -z "$context_name" || "$context_name" == "null" ]]; then
            context_name="$cluster_name"
        fi

        log_info "처리 중: $base_filename -> $cluster_name"

        # 토큰 추출
        local new_token
        if ! new_token=$(extract_token_from_file "$token_file"); then
            ((skipped = skipped + 1))
            ((processed = processed + 1))
            echo
            continue
        fi

        # cluster/context/user 존재 여부 확인
        local has_cluster has_context has_user
        cluster_exists "$cluster_name" && has_cluster=true || has_cluster=false
        context_exists "$context_name" && has_context=true || has_context=false
        user_exists    "$user_name"    && has_user=true    || has_user=false

        local op_success=false

        if [[ "$has_cluster" == "true" && "$has_context" == "true" && "$has_user" == "true" ]]; then
            # 모두 존재: 토큰만 업데이트
            log_info "$cluster_name: 기존 항목 발견 → 토큰만 업데이트"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "Dry-run: $user_name의 토큰을 업데이트할 예정"
                op_success=true
            elif update_user_token "$user_name" "$new_token"; then
                op_success=true
            fi
        else
            # 빠진 항목 추가
            log_info "$cluster_name: 새 항목 추가 (cluster=$has_cluster, context=$has_context, user=$has_user)"

            if [[ "$DRY_RUN" == "true" ]]; then
                [[ "$has_cluster" == "false" ]] && log_info "Dry-run: cluster 항목을 추가할 예정: $cluster_name"
                [[ "$has_context" == "false" ]] && log_info "Dry-run: context 항목을 추가할 예정: $context_name"
                [[ "$has_user"    == "false" ]] && log_info "Dry-run: user 항목을 추가할 예정: $user_name"
                log_info "Dry-run: $user_name의 토큰을 설정할 예정"
                op_success=true
            else
                local add_failed=false

                if [[ "$has_cluster" == "false" ]]; then
                    local server ca_data
                    server=$(extract_server_from_file "$token_file")
                    ca_data=$(extract_ca_data_from_file "$token_file")
                    if [[ -z "$server" || "$server" == "null" || -z "$ca_data" || "$ca_data" == "null" ]]; then
                        log_error "토큰 파일에서 cluster 정보(server/CA)를 찾을 수 없습니다: $filename"
                        add_failed=true
                    else
                        add_cluster_to_config "$cluster_name" "$server" "$ca_data" || add_failed=true
                    fi
                fi

                if [[ "$has_context" == "false" && "$add_failed" == "false" ]]; then
                    add_context_to_config "$context_name" "$cluster_name" "$user_name" || add_failed=true
                fi

                if [[ "$add_failed" == "false" ]]; then
                    if [[ "$has_user" == "false" ]]; then
                        add_user_to_config "$user_name" "$new_token" && op_success=true
                    else
                        update_user_token "$user_name" "$new_token" && op_success=true
                    fi
                fi
            fi
        fi

        if [[ "$op_success" == "true" ]]; then
            ((updated = updated + 1))

            # 성공 시 토큰 파일 삭제
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