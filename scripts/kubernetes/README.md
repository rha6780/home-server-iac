# Kubernetes HA Cluster Shell Install

이 디렉터리는 Terraform으로 생성한 VM에 Kubernetes HA 클러스터를 설치하는 shell-only 실행 경로입니다.

## 구성

| 파일 | 역할 |
|---|---|
| `bootstrap.sh` | **VM 생성 + k8s 설치 전체를 한 번에** (진입점) |
| `deploy.sh` | 로컬에서 실행하는 통합 오케스트레이터 |
| `step-1-haproxy.sh` | HAProxy LB 설치 |
| `step-2-cp-primary.sh` | 첫 번째 Control Plane 초기화 |
| `step-3-cp-join.sh` | 추가 Control Plane join |
| `step-4-worker-join.sh` | Worker join |
| `step-5-helm.sh` | Calico, MetalLB, Gateway API, NGINX Gateway Fabric 설치 |
| `setup-haproxy.sh` | HAProxy 노드에서 실행되는 실제 설치 스크립트 |
| `setup-master.sh` | Control Plane 노드에서 실행되는 실제 설치 스크립트 |
| `setup-worker.sh` | Worker 노드에서 실행되는 실제 설치 스크립트 |
| `04.helm-charts/` | Helm values와 Gateway/MetalLB manifest |

## 사용법

### 한 번에 전체 배포 (추천)

```bash
# tfvars 준비 (최초 1회)
cp terraform/k8s.auto.tfvars.example terraform/k8s.auto.tfvars
vi terraform/k8s.auto.tfvars

# VM 생성 + .env 자동 생성 + k8s 설치
bash scripts/kubernetes/bootstrap.sh

# VM이 이미 있을 때 k8s 설치만
bash scripts/kubernetes/bootstrap.sh --skip-terraform
```

`bootstrap.sh` 내부 흐름:
1. `terraform apply` — Proxmox VM 생성
2. `terraform output` → `.env` 자동 생성 (IP 수동 입력 불필요)
3. 전체 VM SSH 부팅 대기
4. `deploy.sh --all` — step 1~5 순서대로 실행

### 단계별 직접 실행

```bash
cd scripts/kubernetes
cp .env.example .env
vi .env          # IP 직접 편집

bash deploy.sh
bash deploy.sh --step 1
bash deploy.sh --step 1,2,3
bash deploy.sh --all
```

`.env`와 `deploy_*.log`는 로컬 실행 산출물이므로 git에서 제외합니다.
