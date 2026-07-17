# Kubernetes HA Cluster Shell Install

이 디렉터리는 Proxmox VM에 kubeadm 기반 Kubernetes HA 클러스터를 설치하는 실행 스크립트와 Helm 설정을 포함합니다. 프로젝트 전체 구조와 Terraform 설명은 [루트 README](../../README.md)를 참고하세요.

## 구성 결과

```text
로컬 kubectl
  → api.k8s.rha6780.com:6445
  → HAProxy 192.168.0.50:6445
  → Control Plane 192.168.0.51/52:6443
  → Worker 192.168.0.61/62
```

| 컴포넌트 | 기본 버전 | 역할 |
|---|---|---|
| containerd.io | `1.7.29-1~ubuntu.24.04~noble` | container runtime; 기존 VM은 실제 설치 버전으로 동기화 |
| Kubernetes | `1.36.2` | kubelet, kubeadm, kubectl |
| Helm | `3.21.2` | addon package manager |
| HAProxy | `2.8.*` | Kubernetes API load balancer |
| Calico | `3.32.0` | CNI와 network policy |
| MetalLB | `0.16.1` | bare-metal LoadBalancer |
| Gateway API | `1.5.1` | Gateway/HTTPRoute CRD |
| NGINX Gateway Fabric | `2.6.5` | Gateway API implementation |

버전의 기준은 `.env.example`입니다. `bootstrap.sh`는 기존 VM의 `containerd.io` 버전을 감지하면 생성된 `.env`와 동기화합니다.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `bootstrap.sh` | VM 생성부터 Kubernetes 설치까지 전체 진입점 |
| `deploy.sh` | Step 1~5 통합 오케스트레이터 |
| `check-versions.sh` | 설정·원격 설치·최신 후보 버전 조회 |
| `lib.sh` | SSH, preflight, lock, 설정 주입 공통 함수 |
| `step-1-haproxy.sh` | HAProxy 설치 |
| `step-2-cp-primary.sh` | Primary Control Plane 초기화 |
| `step-3-cp-join.sh` | 추가 Control Plane과 etcd join |
| `step-4-worker-join.sh` | Worker join |
| `step-5-helm.sh` | Calico, MetalLB, Gateway API, NGINX Gateway Fabric |
| `setup-haproxy.sh` | HAProxy VM에서 실행되는 스크립트 |
| `setup-master.sh` | Control Plane에서 실행되는 스크립트 |
| `setup-worker.sh` | Worker에서 실행되는 스크립트 |
| `05.post-install-helm.sh` | Primary Control Plane에서 실행되는 addon 설치 |
| `04.helm-charts/` | Helm values, MetalLB pool, Gateway manifest |

`.env` 및 `deploy_*.log`는 로컬 산출물이며 Git에서 제외됩니다.

## 사전 준비

- 대상 VM에 SSH key로 접속할 수 있어야 합니다.
- SSH 계정은 passwordless `sudo`를 사용할 수 있어야 합니다.
- 노드에서 Ubuntu package repository, Kubernetes repository, Docker repository, Helm/OCI registry에 접근할 수 있어야 합니다.
- Control Plane은 최소 2 CPU/1700 MB, Worker는 최소 1 CPU/1024 MB가 필요합니다.
- `CONTROL_PLANE_ENDPOINT`는 모든 노드와 관리 PC에서 HAProxy IP로 해석되어야 합니다.

권장 DNS 레코드:

```text
api.k8s.rha6780.com  A  192.168.0.50
```

Cloudflare를 사용하는 경우 해당 레코드는 DNS-only로 설정하세요. 내부와 VPN 환경은 split DNS로 HAProxy의 사설 IP를 반환하는 구성을 권장합니다.

## 배포 방법

### 1. Terraform VM 생성부터 전체 배포

저장소 루트에서 실행합니다.

```bash
cp terraform/k8s.auto.tfvars.example terraform/k8s.auto.tfvars
vi terraform/k8s.auto.tfvars

bash scripts/kubernetes/bootstrap.sh
```

`bootstrap.sh`의 실행 순서:

1. `terraform init/apply`로 Proxmox VM 생성
2. `terraform output k8s_shell_env_hint`를 이용해 `.env` 자동 생성
3. 모든 VM의 SSH 응답을 노드별 최대 300초 대기
4. 기존 containerd 버전을 `.env`와 동기화
5. `deploy.sh --all` 실행

### 2. 기존 VM에 Kubernetes만 배포

```bash
cp scripts/kubernetes/.env.example scripts/kubernetes/.env
vi scripts/kubernetes/.env

bash scripts/kubernetes/bootstrap.sh --skip-terraform
```

`--skip-terraform`은 Terraform apply와 `.env` 자동 생성을 건너뛰니다. 실행 전에 `.env`가 반드시 준비되어 있어야 합니다.

### 3. 전체 또는 특정 Step 직접 실행

```bash
bash scripts/kubernetes/deploy.sh --all
bash scripts/kubernetes/deploy.sh --step 1
bash scripts/kubernetes/deploy.sh --step 2,3,4
bash scripts/kubernetes/deploy.sh --step 5
```

`deploy.sh`를 인수 없이 실행하면 대화형 메뉴를 표시하고 사용자 입력을 대기합니다. CI/Semaphore에서는 `--all` 또는 `--step`을 명시하세요.

| Step | 작업 |
|---:|---|
| 1 | HAProxy 설치, `6445` frontend, Control Plane `6443` backend 구성 |
| 2 | Primary Control Plane `kubeadm init` |
| 3 | 추가 Control Plane과 stacked etcd join |
| 4 | Worker join |
| 5 | Calico CRD/CNI → MetalLB → Gateway API CRD → NGINX Gateway Fabric |

## Step 5 설치 순서

Calico 3.32부터는 Tigera Operator보다 CRD chart를 먼저 적용해야 합니다. 현재 스크립트는 다음 순서로 실행합니다.

1. `projectcalico/crd.projectcalico.org.v1` CRD server-side apply
2. `Installation`, `APIServer`, `Goldmane`, `Whisker` CRD Established 대기
3. `projectcalico/tigera-operator` 설치
4. MetalLB와 `.env` 기반 IP pool 설치
5. Gateway API standard CRD 설치
6. 공식 OCI chart로 NGINX Gateway Fabric 설치
7. `main-gateway` 적용

NGINX Gateway Fabric의 현재 공식 OCI 경로:

```text
oci://ghcr.io/nginx/charts/nginx-gateway-fabric
```

예전 `ghcr.io/nginxinc/charts/...` 경로는 chart를 찾을 수 없으므로 사용하지 않습니다.

`gateway.yaml`의 HTTPS listener는 `nginx-gateway/tls-secret`을 참조합니다. HTTPS를 사용하려면 해당 TLS Secret을 생성하거나 manifest의 `certificateRefs` 이름을 실제 Secret에 맞게 수정하세요.

## Preflight와 재실행

`deploy.sh`는 배포 전에 다음을 확인합니다.

| 항목 | 확인 내용 |
|---|---|
| SSH | key 파일, 노드 접속, passwordless sudo |
| 리소스 | CPU와 memory 최소치 |
| OS | swap, 기본 route, `br_netfilter` |
| 설정 | 필수 `.env` 변수 |

특별한 진단 상황을 제외하고 preflight를 건너뛰지 마세요.

```bash
SKIP_PREFLIGHT=true bash scripts/kubernetes/deploy.sh --step 5
```

스크립트는 이미 설치된 package, kubeadm 초기화/join, Helm release를 확인해 재실행할 수 있도록 구성되어 있습니다.

`bootstrap.sh`와 `deploy.sh`는 `/tmp/k8s-deploy.lock`을 사용해 동시 실행을 막습니다. 비정상 종료로 lock만 남았다면 실행 중인 배포가 없는지 확인한 후 제거합니다.

```bash
rm -rf /tmp/k8s-deploy.lock
```

## 버전 확인

```bash
# .env.example의 설정 버전
bash scripts/kubernetes/check-versions.sh

# .env와 원격 설치 버전
bash scripts/kubernetes/check-versions.sh \
  --env scripts/kubernetes/.env \
  --remote

# 최신 후보까지 비교
bash scripts/kubernetes/check-versions.sh \
  --env scripts/kubernetes/.env \
  --remote \
  --latest
```

`K8S_MINOR`는 `K8S_VERSION`에서 자동 계산하므로 `.env`에 따로 정의하지 않습니다.

## 로컬에서 kubectl 사용

Control Plane의 kubeconfig를 로컬로 복사하면 요청은 `CONTROL_PLANE_ENDPOINT` → HAProxy → Control Plane으로 전달됩니다. 기존 kubeconfig를 덮어쓰지 않도록 별도 파일을 사용하세요.

```bash
mkdir -p ~/.kube

scp -i ~/.ssh/rha6780.pem \
  ubuntu@192.168.0.51:~/.kube/config \
  ~/.kube/home-server.yaml

chmod 600 ~/.kube/home-server.yaml

KUBECONFIG=~/.kube/home-server.yaml kubectl get nodes -o wide
KUBECONFIG=~/.kube/home-server.yaml kubectl get pods -A
KUBECONFIG=~/.kube/home-server.yaml kubectl get svc -n nginx-gateway
KUBECONFIG=~/.kube/home-server.yaml kubectl get gatewayclass,gateway -A
```

선택적 alias:

```bash
alias hk='KUBECONFIG=$HOME/.kube/home-server.yaml kubectl'
hk get nodes
```

kubeconfig는 cluster-admin client certificate/key를 포함하므로 Git에 커밋하거나 외부에 공유하지 마세요.

## 정상 상태 확인

```bash
# DNS 및 HAProxy API
getent ahostsv4 api.k8s.rha6780.com
nc -vz api.k8s.rha6780.com 6445
curl -k https://api.k8s.rha6780.com:6445/livez

# Kubernetes
KUBECONFIG=~/.kube/home-server.yaml kubectl get nodes -o wide
KUBECONFIG=~/.kube/home-server.yaml kubectl get pods -A
KUBECONFIG=~/.kube/home-server.yaml kubectl get tigerastatus
KUBECONFIG=~/.kube/home-server.yaml helm list -A
```

정상 기준:

- API `/livez`가 `ok`를 반환합니다.
- 모든 Kubernetes 노드가 `Ready`입니다.
- Calico, MetalLB, NGINX Gateway Fabric Pod가 `Running`입니다.
- Helm release가 `deployed`입니다.
- Gateway는 listener와 TLS Secret 설정에 따라 `Programmed=True`를 보여야 합니다.

## 대기와 타임아웃

| 구간 | 시간 |
|---|---:|
| VM SSH 부팅 | 노드별 300초 |
| Primary local API | 60초 |
| HAProxy API endpoint | 120초 |
| Calico Helm | 5분 |
| MetalLB Helm | 3분 |
| MetalLB controller | 90초 |
| Gateway API CRD | 60초 |
| NGINX Gateway Fabric Helm | 3분 |

`terraform init/apply`, `apt-get`, `curl`, `helm repo update`, 일반 원격 SSH 명령에는 전체 실행 시간 제한이 없습니다. 저장소나 registry 장애가 있으면 오랫동안 대기할 수 있습니다.

## 문제 해결

### `load-balanced endpoint` 대기 후 timeout

Control Plane에서 endpoint가 HAProxy IP로 해석되는지 확인합니다.

```bash
getent ahostsv4 api.k8s.rha6780.com
nc -vz api.k8s.rha6780.com 6445
```

Cloudflare IP가 보이면 DNS-only 전파/cache 문제입니다. 내부 DNS를 수정하고 필요하면 `resolvectl flush-caches`로 Linux DNS cache를 비웁니다.

### Calico `ensure CRDs are installed first`

Step 5를 재실행하세요. 현재 스크립트는 Calico 3.32 CRD chart를 먼저 적용하고 CRD Established를 대기합니다.

```bash
bash scripts/kubernetes/deploy.sh --step 5
```

### MetalLB `context deadline exceeded`

최초 image pull이 3분보다 길어 Helm timeout이 발생할 수 있습니다. Pod가 이후 `Running`이 되었다면 Step 5를 재실행해 Helm release를 정상화합니다.

```bash
KUBECONFIG=~/.kube/home-server.yaml kubectl get pods -n metallb-system
bash scripts/kubernetes/deploy.sh --step 5
```

### NGINX chart `FetchReference ... not found`

script에 다음 공식 OCI 경로가 사용되는지 확인하세요.

```text
oci://ghcr.io/nginx/charts/nginx-gateway-fabric
```

### Gateway가 Ready/Programmed가 아님

```bash
KUBECONFIG=~/.kube/home-server.yaml kubectl describe gateway -n nginx-gateway main-gateway
KUBECONFIG=~/.kube/home-server.yaml kubectl get secret -n nginx-gateway tls-secret
```

HTTPS listener가 참조하는 `tls-secret`이 없으면 Gateway가 완전히 Programmed되지 않을 수 있습니다.

## 보안 주의사항

- `.env`, SSH private key, kubeconfig, Proxmox 인증 정보를 커밋하지 마세요.
- API endpoint와 HAProxy stats 포트를 인터넷에 무제한으로 공개하지 마세요.
- kubeconfig는 cluster-admin 권한이므로 `chmod 600`으로 보호하세요.
- 외부 접근은 Kubernetes API를 직접 노출하기보다 VPN을 사용하세요.
