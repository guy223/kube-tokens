# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

이 프로젝트는 Kubernetes 토큰 관리 도구입니다.

## Kubernetes 환경 설정

### Context 전환 명령어
```bash
# 개발 환경
k6        # niffler2-dev-apse1-k6-cluster
dev       # aws-niffler2-dev-apse1-db-cluster  
app-dev   # aws-niffler2-dev-apse1-app-cluster
sd        # aws-niffler2-dev-apse1-sandbox-cluster

# 스테이징 환경  
stg       # niffler2-stg-apse1-db-cluster
app-stg   # niffler2-stg-apse1-app-cluster

# 프로덕션 환경
prod      # niffler2-prod-apse1-db-cluster (AP)
usprod    # niffler2-prod-use1-db-cluster (US)  
euprod    # niffler2-prod-euc1-db-cluster (EU)
```

### 주요 네임스페이스
- `clickhouse`: ClickHouse 관련 리소스

### ClickHouse Pod 접근
- ClickHouse 컨테이너: `ch00`, `ch01`, `ch10`, `ch11` ... `ch91`
- Backup 컨테이너: `backup00`, `backup01`, `backup10`, `backup11` ... `backup91`
- ZooKeeper: `zoo0`

### 환경별 클러스터 구성
- **Development**: 2 pods (shard 0-1, replica 0-1)
- **Staging**: 5 pods (shard 0-4, replica 0-1)
- **AP Production**: 10 pods (shard 0-9, replica 0-1)
- **US Production**: 4 pods (shard 0-3, replica 0-1)  
- **EU Production**: 18 pods (shard 0-8, replica 0-1)

### 유용한 명령어
```bash
# Pod 상태 모니터링
getpod    # watch -n 1 kubectl get pod -o wide -n clickhouse

# Secret 확인
kubectl get secret niffler2-signoz-clickhouse-secret -n clickhouse
```

## 개발 참고사항

- Shell script 작성 시 `++` 연산자 사용 금지 (오류 발생)
- `count++` 같은 구문은 동작하지 않음
- 커밋 메시지는 한글로 작성

## update-kube-tokens.sh 주요 함수

| 함수 | 역할 |
|------|------|
| `check_prerequisites()` | yq 설치 확인, tokens 디렉토리 확인, config 없으면 자동 생성 |
| `create_backup()` | config 백업 (새로 생성된 파일은 건너뜀) |
| `extract_*_from_file()` | 토큰 파일에서 cluster/server/CA/user/context 정보 추출 |
| `cluster_exists()` | kube config에 cluster 항목 존재 여부 확인 |
| `context_exists()` | kube config에 context 항목 존재 여부 확인 |
| `user_exists()` | kube config에 user 항목 존재 여부 확인 |
| `add_cluster_to_config()` | kube config에 cluster 항목 추가 (yq strenv() 사용) |
| `add_context_to_config()` | kube config에 context 항목 추가 |
| `add_user_to_config()` | kube config에 user 항목 추가 |
| `update_user_token()` | 기존 user의 토큰만 업데이트 |
| `process_tokens()` | 메인 처리 루프 |

### process_tokens() 처리 흐름

```
tokens/*.txt 파일 순회
    ↓
파일에서 cluster_name, user_name, context_name 추출
    ↓
cluster/context/user 모두 존재? ─── YES → 토큰만 update_user_token()
    │ NO
    ↓
빠진 항목 추가 (add_cluster / add_context / add_user)
    ↓
처리 성공 시 토큰 파일 삭제
```

### 특수문자 처리

JWT 토큰 및 CA data (base64)는 yq의 `strenv()`를 통해 환경변수로 전달:
```bash
CLUSTER_NAME="..." SERVER_URL="..." CA_DATA="..." \
yq eval '.clusters += [{"cluster": {"certificate-authority-data": strenv(CA_DATA), ...}}]' -i "$KUBE_CONFIG"
```