# Kubernetes 토큰 관리 도구

Kubernetes 클러스터 토큰을 자동으로 업데이트하는 스크립트입니다. `tokens/` 폴더의 토큰 파일을 사용하여 `~/.kube/config`의 사용자 토큰을 업데이트합니다.

## 기능

- 자동 토큰 업데이트: tokens/ 폴더의 .txt 파일을 읽어 kube config 업데이트
- 자동 백업: 업데이트 전 기존 config 파일 백업
- Dry-run 모드: 실제 변경 없이 미리보기 가능
- 안전한 파일 처리: 업데이트 완료 후 토큰 파일 자동 삭제
- 컬러 로그: 직관적인 상태 표시

## 설치 및 설정

### 1. 필수 요구사항

#### yq 설치
이 스크립트는 YAML 파일 처리를 위해 `yq` (mikefarah/yq)가 필요합니다.

```bash
# Linux (AMD64/x86_64)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Linux (x86_64 - 다른 방법)
curl -LO https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo mv yq_linux_amd64 /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq

# Linux (ARM64)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64
sudo chmod +x /usr/local/bin/yq

# macOS (Homebrew)
brew install yq

# macOS (수동 설치)
curl -LO https://github.com/mikefarah/yq/releases/latest/download/yq_darwin_amd64
sudo mv yq_darwin_amd64 /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq

# 설치 확인
yq --version
```

**중요**: 반드시 `mikefarah/yq`를 설치해야 합니다. 다른 yq 구현체는 지원되지 않습니다.

#### kubectl 설정
kubectl이 설치되어 있고 `~/.kube/config` 파일이 존재해야 합니다.

```bash
# kubectl 설치 확인
kubectl version --client

# kube config 확인
ls -la ~/.kube/config
```

### 2. 프로젝트 설정

#### 저장소 클론
```bash
git clone https://github.com/guy223/kube-tokens.git
cd kube-tokens
```

#### 디렉토리 구조 확인
```
kube-tokens/
├── README.md
├── CLAUDE.md
├── update-kube-tokens.sh
├── tokens/              # 토큰 파일을 여기에 배치
├── backups/            # 자동 생성되는 백업 폴더
└── ...
```

#### 스크립트 실행 권한 부여
```bash
chmod +x update-kube-tokens.sh
```

### 3. 토큰 파일 준비

`tokens/` 폴더에 클러스터별 토큰 파일을 배치합니다. 파일명은 다음 패턴을 따라야 합니다:

```
tokens/
├── niffler2-dev-apse1-k6-cluster.txt
├── aws-niffler2-dev-apse1-db-cluster.txt
├── aws-niffler2-dev-apse1-app-cluster.txt
├── niffler2-stg-apse1-db-cluster.txt
├── niffler2-prod-apse1-db-cluster.txt
└── ...
```

#### 토큰 파일 형식
각 토큰 파일은 다음과 같은 YAML 형식이어야 합니다:

```yaml
users:
- name: cluster-name
  user:
    token: "eyJhbGciOiJSUzI1NiIsImtpZCI6Il..."
```

## 사용법

### 기본 사용법
```bash
# 토큰 업데이트 실행
./update-kube-tokens.sh
```

### Dry-run 모드 (권장)
실제 변경 전에 미리보기:
```bash
./update-kube-tokens.sh --dry-run
```

### 도움말
```bash
./update-kube-tokens.sh --help
```

## 작동 원리

1. **사전 검사**: yq 설치 및 필수 파일/디렉토리 확인
2. **백업 생성**: 현재 kube config를 `backups/` 폴더에 백업
3. **토큰 처리**:
   - `tokens/` 폴더의 모든 .txt 파일 스캔
   - 파일명을 기반으로 클러스터명 매핑
   - YAML에서 토큰 추출
   - kube config의 해당 사용자 토큰 업데이트
   - 성공 시 토큰 파일 삭제
4. **결과 보고**: 처리된 파일 수, 업데이트 성공/실패 통계

## 지원하는 클러스터

| 파일명 패턴 | 매핑되는 클러스터명 | 환경 |
|------------|-------------------|------|
| `niffler2-dev-apse1-k6*` | niffler2-dev-apse1-k6-cluster | 개발 |
| `aws-niffler2-dev-apse1-db*` | aws-niffler2-dev-apse1-db-cluster | 개발 |
| `aws-niffler2-dev-apse1-app*` | aws-niffler2-dev-apse1-app-cluster | 개발 |
| `aws-niffler2-dev-apse1-sandbox*` | aws-niffler2-dev-apse1-sandbox-cluster | 샌드박스 |
| `niffler2-stg-apse1-db*` | niffler2-stg-apse1-db-cluster | 스테이징 |
| `niffler2-stg-apse1-app*` | niffler2-stg-apse1-app-cluster | 스테이징 |
| `niffler2-prod-apse1-db*` | niffler2-prod-apse1-db-cluster | 프로덕션 (AP) |
| `niffler2-prod-use1-db*` | niffler2-prod-use1-db-cluster | 프로덕션 (US) |
| `niffler2-prod-euc1-db*` | niffler2-prod-euc1-db-cluster | 프로덕션 (EU) |

## 컨텍스트 전환 Aliases

편의를 위해 다음 aliases를 `~/.bashrc` 또는 `~/.zshrc`에 추가할 수 있습니다:

```bash
# 개발 환경
alias k6="kubectl config use-context niffler2-dev-apse1-k6-cluster"
alias dev="kubectl config use-context aws-niffler2-dev-apse1-db-cluster"  
alias app-dev="kubectl config use-context aws-niffler2-dev-apse1-app-cluster"
alias sd="kubectl config use-context aws-niffler2-dev-apse1-sandbox-cluster"

# 스테이징 환경
alias stg="kubectl config use-context niffler2-stg-apse1-db-cluster"
alias app-stg="kubectl config use-context niffler2-stg-apse1-app-cluster"

# 프로덕션 환경
alias prod="kubectl config use-context niffler2-prod-apse1-db-cluster"
alias usprod="kubectl config use-context niffler2-prod-use1-db-cluster"
alias euprod="kubectl config use-context niffler2-prod-euc1-db-cluster"
```

## 트러블슈팅

### 일반적인 문제

#### yq 버전 오류
```
ERROR: 올바른 yq 버전이 아닙니다. mikefarah/yq가 필요합니다.
```
**해결방법**: 올바른 yq 설치 (위의 설치 섹션 참조)

#### 토큰 파일 형식 오류
```
WARN: 토큰을 찾을 수 없습니다: tokens/cluster.txt
```
**해결방법**: 토큰 파일이 올바른 YAML 형식인지 확인

#### 사용자 없음 오류
```
WARN: kube config에서 user를 찾을 수 없습니다: cluster-name
```
**해결방법**: kube config에 해당 클러스터가 등록되어 있는지 확인

### 로그 레벨

- `[INFO]` (파란색): 일반 정보
- `[WARN]` (노란색): 경고 (건너뛰어짐)
- `[ERROR]` (빨간색): 오류 (중단됨)
- `[SUCCESS]` (초록색): 성공

### 백업 파일

모든 config 변경 전에 백업이 생성됩니다:
- 위치: `backups/config_YYYYMMDD_HHMMSS.bak`
- 복원: `cp backups/config_20231201_123456.bak ~/.kube/config`

## 저장소 정보

- **GitHub 저장소**: https://github.com/guy223/kube-tokens
- **클론 URL (HTTPS)**: `https://github.com/guy223/kube-tokens.git`
- **클론 URL (SSH)**: `git@github.com:guy223/kube-tokens.git`

## 기여하기

1. 이슈 보고 또는 기능 제안
2. Fork 후 브랜치 생성
3. 변경사항 커밋
4. Pull Request 생성

## 라이선스

이 프로젝트는 [라이선스명]에 따라 배포됩니다.