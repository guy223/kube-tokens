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