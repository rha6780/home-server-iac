# home-server-iac

![Terraform](https://img.shields.io/badge/terraform-1.14.0-purple)
![SemaPhore](https://img.shields.io/badge/semaphore-v.2.16.47-green)

개인 홈서버 구축을 위한 IaC(Infrastructure as Code) 프로젝트입니다.

---

## 개요

홈서버 환경에서 VM 생성, 네트워크 설정, 소프트웨어 구성 등을 코드로 관리하기 위한 저장소입니다.

- **Terraform** 으로 Proxmox 위에 VM 인프라를 프로비저닝합니다.
- **Ansible** 로 VM 내부 소프트웨어 설정 및 반복 작업을 자동화합니다.
- **Semaphore** 를 통해 Ansible 플레이북을 UI/스케줄러 기반으로 실행합니다.


---

## 디렉토리 구조

```
home-server-iac/
├── terraform/                  # Terraform 인프라 정의
│   ├── provider.tf             # Proxmox provider 설정
│   ├── variables.tf            # 변수 정의 (API URL, 인증 정보)
│   ├── terraform.tfvars        # 변수 실제값 (git 제외 권장)
│   └── main.tf                 # VM 리소스 정의
│
├── semaphore/                  # Semaphore + Ansible 자동화
│   └── playbooks/
│       ├── proxmox/
│       │   ├── list-vms.yml    # Proxmox VM 목록 조회 플레이북
│       │   └── requirements.yml # Ansible 컬렉션 의존성
│       └── kubernetes/
│           ├── site.yml        # Kubernetes 설치 Ansible 진입점
│           └── inventory.example.yml
│
└── scripts/
    └── kubernetes/             # Kubernetes shell-only 설치 스크립트
```

---

## Terraform

### 사용 Provider

| Provider | 버전 |
|---|---|
| `telmate/proxmox` | `3.0.2-rc06` |

### 변수 설정

`terraform/terraform.tfvars` 파일을 생성하여 아래 값을 설정합니다.

```hcl
provider_pm_api_url  = "https://<PROXMOX_HOST>:8006/api2/json"
provider_pm_user     = "root@pam"
provider_pm_password = "<PASSWORD>"
```

> 인증 정보가 포함된 `terraform.tfvars` 는 `.gitignore` 에 추가하는 것을 권장합니다.

### 주요 명령어

```bash
cd terraform

# 초기화
terraform init

# 변경사항 미리보기
terraform plan

# 인프라 적용
terraform apply

# 인프라 삭제
terraform destroy
```

### 현재 관리 중인 VM

| VM 이름 | VMID | CPU | RAM | Disk | 용도 | 부팅 |
|---|---|---|---|---|---|---|
| vm-npm-01 | 200 | 2 core | 2 GB | 20 GB | Nginx Proxy Manager (리버스 프록시) | 자동 |
| vm-database-01 | 201 | 4 core | 4 GB | 40 GB | 데이터베이스 서버 | 자동 |
| vm-hoppscotch-01 | 202 | 2 core | 2 GB | 20 GB | Hoppscotch (API 테스트 도구) | 자동 |
| vm-iac-01 | 203 | 2 core | 2 GB | 20 GB | IaC 관리 (Semaphore 등) | 자동 |
| vm-docker-registry-01 | 204 | 2 core | 2 GB | 20 GB | Docker 프라이빗 레지스트리 | 자동 |
| vm-vpn-01 | 205 | 2 core | 2 GB | 20 GB | VPN 서버 | 자동 |
| vm-jenkins-01 | 206 | 2 core | 2 GB | 20 GB | Jenkins CI/CD | 자동 |
| vm-vault-docs-01 | 207 | 2 core | 2 GB | 20 GB | 문서/Vault 서버 | 자동 |
| vm-netbox-01 | 208 | 2 core | 4 GB | 40 GB | NetBox Community (IPAM/DCIM) | 자동 |
| vm-ourjournal-01 | 301 | 2 core | 2 GB | 20 GB | 개인 저널 서비스 | 자동 |
| vm-file-share-01 | 504 | 2 core | 2 GB | 32 GB | 파일 공유 서버 | 자동 |
| vm-mine-lfin-01 | 505 | 4 core | 32 GB | 20 GB | 마인크래프트 Lifin 서버 | 자동 |
| vm-mine-base-01 | 500 | 2 core | 8 GB | 32 GB | 마인크래프트 베이스 서버 | 수동 |
| vm-mine-build-01 | 501 | 2 core | 8 GB | 32 GB | 마인크래프트 빌드 서버 | 수동 |
| vm-mine-wild-01 | 502 | 2 core | 8 GB | 32 GB | 마인크래프트 야생 서버 | 수동 |
| vm-mine-db-01 | 503 | 2 core | 2 GB | 32 GB | 마인크래프트 DB 서버 | 수동 |

> - 기본값: CPU 2 core, RAM 2 GB, Disk 20 GB (모듈 `proxmox_vm` 기준)
> - 부팅: 노드 시작 시 자동 부팅 여부 (`start_at_node_boot`)

---

## Semaphore + Ansible

Semaphore는 Ansible 플레이북을 Web UI에서 실행하고 스케줄링할 수 있는 오픈소스 도구입니다.

### Ansible 컬렉션 의존성

`semaphore/playbooks/proxmox/requirements.yml` 에 정의된 컬렉션을 설치합니다.

```bash
ansible-galaxy collection install -r semaphore/playbooks/proxmox/requirements.yml
```

### 현재 플레이북

| 플레이북 | 설명 |
|---|---|
| `proxmox/list-vms.yml` | Proxmox API를 통해 VM 목록 조회 |
| `kubernetes/site.yml` | shell 설치 스크립트를 Ansible/Semaphore에서 실행 |

### Proxmox 연동 변수 (Semaphore에서 설정)

| 변수명 | 설명 |
|---|---|
| `proxmox_api_host` | Proxmox 호스트 주소 |
| `proxmox_api_user` | API 사용자 (예: `ansible@pam`) |
| `proxmox_api_token_id` | API 토큰 ID |
| `proxmox_api_token_secret` | API 토큰 시크릿 |

---

## 전체 워크플로우

```text
로컬 PC
  ├─ Terraform → Proxmox API → VM 생성
  └─ Kubernetes 배포 스크립트 → SSH → 노드 설정

운영 자동화
  └─ Semaphore/Ansible → 같은 Kubernetes shell 스크립트 실행
```

---

## Kubernetes HA 클러스터

### 무엇을 구성하는가

이 저장소의 `scripts/kubernetes` 스크립트는 kubeadm 기반 Kubernetes HA 클러스터를 구성합니다. VM 생성부터 Kubernetes와 네트워크 컴포넌트 설치까지 한 번에 실행하거나, 이미 생성된 VM에 Kubernetes만 설치할 수 있습니다.

실행 스크립트별 역할과 상세 운영 절차는 [`scripts/kubernetes/README.md`](scripts/kubernetes/README.md)를 참고하세요.

| 역할 | 예시 호스트 | 주요 포트 | 설명 |
|---|---|---:|---|
| HAProxy | `192.168.0.50` | `6445` | Kubernetes API 단일 endpoint |
| Control Plane Primary | `192.168.0.51` | `6443` | 첫 control plane과 etcd |
| Control Plane Join | `192.168.0.52` | `6443` | 추가 control plane과 etcd |
| Worker | `192.168.0.61`, `.62` | - | 애플리케이션 workload 실행 |

IP는 예시이며 `terraform/k8s.auto.tfvars` 또는 `scripts/kubernetes/.env`에서 환경에 맞게 지정합니다.

### API 접근 흐름

```text
로컬 kubectl
  → https://api.k8s.rha6780.com:6445
  → HAProxy 192.168.0.50:6445
  → Control Plane 192.168.0.51/52:6443
```

`api.k8s.rha6780.com`은 클러스터 노드와 관리자 PC에서 HAProxy IP로 해석되어야 합니다. 내부 DNS에 다음 A 레코드를 만드는 split DNS 방식을 권장합니다.

```text
api.k8s.rha6780.com  A  192.168.0.50
```

Cloudflare를 사용하면 해당 레코드는 DNS-only여야 합니다. 일반 Cloudflare proxy는 Kubernetes API의 `6445` TCP 트래픽을 전달하지 않습니다. 외부에서는 API를 직접 공개하기보다 VPN을 통해 내부 DNS와 HAProxy에 접근하는 구성을 권장합니다.

### 기본 버전

| 컴포넌트 | 버전 | 비고 |
|---|---|---|
| Terraform | `1.14.0` | Proxmox VM 프로비저닝 |
| Proxmox provider | `3.0.2-rc06` | `telmate/proxmox` |
| Kubernetes | `1.36.2` | kubelet, kubeadm, kubectl |
| Helm | `3.21.2` | 클러스터 addon 설치 |
| HAProxy | `2.8.*` | API load balancer |
| Calico | `3.32.0` | CNI, Tigera Operator |
| MetalLB | `0.16.1` | bare-metal LoadBalancer |
| Gateway API | `1.5.1` | standard CRD bundle |
| NGINX Gateway Fabric | `2.6.5` | Gateway API implementation |

containerd는 `.env`의 `CONTAINERD_VERSION`을 사용하지만, `bootstrap.sh`는 기존 VM에 설치된 `containerd.io` 버전을 감지하면 `.env`와 동기화합니다. 설정·원격 설치·최신 후보 버전은 다음 명령으로 확인할 수 있습니다.

```bash
bash scripts/kubernetes/check-versions.sh
bash scripts/kubernetes/check-versions.sh --env scripts/kubernetes/.env --remote
bash scripts/kubernetes/check-versions.sh --env scripts/kubernetes/.env --remote --latest
```

### 사전 요구사항

- macOS 또는 Linux 관리 PC
- Proxmox VE API 접근 정보와 VM template
- Terraform, Python 3, `jq`, SSH/SCP
- 대상 VM에 SSH key 접속 가능
- SSH 계정의 passwordless `sudo`
- 모든 노드의 인터넷과 패키지/image registry 접근
- Control Plane 최소 2 CPU/1700 MB, Worker 최소 1 CPU/1024 MB

`bootstrap.sh`는 macOS에서 Python 3, `jq`, Terraform이 없으면 Homebrew로 설치를 시도합니다.

### 방법 1: VM 생성부터 전체 배포

Terraform으로 VM을 생성하고 Terraform output에서 IP를 읽어 `.env`를 자동 생성합니다.

```bash
cp terraform/k8s.auto.tfvars.example terraform/k8s.auto.tfvars
vi terraform/k8s.auto.tfvars

bash scripts/kubernetes/bootstrap.sh
```

실행 순서:

1. `terraform init/apply`로 Proxmox VM 생성
2. `terraform output` 기반 `scripts/kubernetes/.env` 생성
3. 모든 VM의 SSH 응답 대기
4. HAProxy 설치
5. Primary/Secondary Control Plane 구성
6. Worker join
7. Calico, MetalLB, Gateway API, NGINX Gateway Fabric 설치

### 방법 2: 기존 VM에 Kubernetes만 설치

Terraform을 사용하지 않는 경로입니다. `.env.example`을 복사한 뒤 IP, SSH key, endpoint, 버전을 실제 환경에 맞게 수정합니다.

```bash
cp scripts/kubernetes/.env.example scripts/kubernetes/.env
vi scripts/kubernetes/.env

bash scripts/kubernetes/bootstrap.sh --skip-terraform
```

`bootstrap.sh` 없이 전체 설치 또는 특정 단계만 실행할 수도 있습니다.

```bash
bash scripts/kubernetes/deploy.sh --all
bash scripts/kubernetes/deploy.sh --step 1
bash scripts/kubernetes/deploy.sh --step 3,4
bash scripts/kubernetes/deploy.sh --step 5
```

| Step | 내용 |
|---:|---|
| 1 | HAProxy 설치와 Control Plane backend 설정 |
| 2 | Primary Control Plane `kubeadm init` |
| 3 | 추가 Control Plane과 etcd join |
| 4 | Worker join |
| 5 | Calico, MetalLB, Gateway API, NGINX Gateway Fabric |

### Ansible/Semaphore에서 실행

Ansible 경로도 독립적인 Kubernetes 구현을 다시 작성하지 않고 같은 shell 스크립트를 실행합니다.

```bash
cp scripts/kubernetes/.env.example scripts/kubernetes/.env
vi scripts/kubernetes/.env

ansible-playbook \
  -i semaphore/playbooks/kubernetes/inventory.example.yml \
  semaphore/playbooks/kubernetes/site.yml
```

자세한 inventory와 Semaphore 설정은 `semaphore/playbooks/kubernetes/README.md`를 참고하세요.

### 로컬 PC에서 kubectl 사용

API 요청은 로컬에서도 HAProxy를 통해 전달됩니다. Control Plane의 kubeconfig에는 API endpoint, cluster CA, 관리자 client 인증서와 key가 있으므로 이 파일만 로컬로 복사하면 됩니다.

기존 OrbStack이나 다른 context를 덮어쓰지 않도록 별도 파일로 저장합니다.

```bash
mkdir -p ~/.kube

scp -i ~/.ssh/rha6780.pem \
  ubuntu@192.168.0.51:~/.kube/config \
  ~/.kube/home-server.yaml

chmod 600 ~/.kube/home-server.yaml
```

사용 예:

```bash
KUBECONFIG=~/.kube/home-server.yaml kubectl get nodes -o wide
KUBECONFIG=~/.kube/home-server.yaml kubectl get pods -A
KUBECONFIG=~/.kube/home-server.yaml kubectl get svc -n nginx-gateway
KUBECONFIG=~/.kube/home-server.yaml kubectl get gateway -A
```

선택적으로 alias를 사용할 수 있습니다.

```bash
alias hk='KUBECONFIG=$HOME/.kube/home-server.yaml kubectl'

hk get nodes
hk get pods -A
```

`home-server.yaml`은 cluster-admin client key를 포함하므로 Git에 커밋하거나 외부에 공유하지 마세요.

### 배포 확인

```bash
# DNS가 HAProxy를 보는지 확인
getent hosts api.k8s.rha6780.com       # Linux
dscacheutil -q host -a name api.k8s.rha6780.com  # macOS

# 로컬 → HAProxy → API server 통신 확인
nc -vz api.k8s.rha6780.com 6445
curl -k https://api.k8s.rha6780.com:6445/livez

# 클러스터 확인
KUBECONFIG=~/.kube/home-server.yaml kubectl get nodes -o wide
KUBECONFIG=~/.kube/home-server.yaml kubectl get pods -A
KUBECONFIG=~/.kube/home-server.yaml kubectl get gatewayclass,gateway -A
```

정상이면 API health check는 `ok`, 모든 노드는 `Ready`, 핵심 addon Pod는 `Running` 상태를 보여야 합니다.

### 재실행과 로그

- 스크립트는 이미 설치된 package, kubeadm join, Helm release를 가능한 범위에서 재사용합니다.
- `deploy_YYYYMMDD_HHMMSS.log`는 `scripts/kubernetes` 아래에 생성됩니다.
- 동시 실행 방지용 `/tmp/k8s-deploy.lock`을 사용합니다.
- 프로세스가 비정상 종료되어 lock만 남았다면 실행 중인 배포가 없는지 확인한 뒤 lock을 제거합니다.

```bash
rm -rf /tmp/k8s-deploy.lock
```

### 주요 대기 및 타임아웃

| 구간 | 기본 설정 |
|---|---:|
| VM SSH 부팅 대기 | 노드별 최대 300초 |
| 로컬 Control Plane API | 60초 |
| HAProxy API endpoint | 120초 |
| Calico Helm | 5분 |
| MetalLB Helm | 3분 |
| MetalLB controller Ready | 90초 |
| Gateway API CRD Established | 60초 |
| NGINX Gateway Fabric Helm | 3분 |

첫 설치에서는 image pull 속도에 따라 Helm timeout이 발생할 수 있습니다. Pod가 나중에 `Running`으로 바뀌었다면 같은 Step을 재실행하면 Helm release 상태가 정상화됩니다.

### 자주 발생하는 문제

#### `load-balanced endpoint` 대기에서 멈추는 경우

```bash
getent ahostsv4 api.k8s.rha6780.com
nc -vz api.k8s.rha6780.com 6445
```

DNS는 HAProxy IP를 반환해야 합니다. 이전 Cloudflare IP가 나오면 DNS cache를 비우거나 내부 DNS/임시 `/etc/hosts` mapping을 사용합니다.

#### Calico가 `ensure CRDs are installed first`로 실패하는 경우

Calico 3.32는 `projectcalico/crd.projectcalico.org.v1` chart를 먼저 server-side apply해야 합니다. 현재 Step 5는 CRD를 설치하고 `Installation`, `APIServer`, `Goldmane`, `Whisker` CRD가 Established가 될 때까지 대기한 후 Tigera Operator를 설치합니다.

#### NGINX Gateway Fabric chart가 `not found`로 실패하는 경우

현재 공식 OCI 경로는 다음과 같습니다.

```text
oci://ghcr.io/nginx/charts/nginx-gateway-fabric
```

예전 `ghcr.io/nginxinc/charts/...` 경로는 사용하지 않습니다.

### 최근 Kubernetes 배포 관련 변경

- Terraform VM output을 사용한 `.env` 자동 생성
- Terraform 없이 `.env`만으로 배포하는 `--skip-terraform` 경로
- 재실행에 안전한 package/kubeadm/Helm 멱등성 개선
- SSH, sudo, CPU, memory, swap, route, kernel module preflight
- HAProxy endpoint와 certificate SAN에 DNS/IP 자동 반영
- Calico 3.32 CRD chart 선행 설치 및 Established 대기
- NGINX Gateway Fabric OCI registry를 `ghcr.io/nginx/charts` 경로로 수정
- 설정값, 원격 설치 버전, 최신 후보를 비교하는 `check-versions.sh` 추가

---

## 보안 및 주의사항

- `terraform/terraform.tfvars`, `terraform/k8s.auto.tfvars`, `scripts/kubernetes/.env`에는 인증 정보와 실제 네트워크 정보가 들어갈 수 있습니다.
- kubeconfig, SSH private key, Proxmox password/token을 Git에 커밋하지 마세요.
- Kubernetes API, HAProxy stats, Proxmox API를 인터넷에 무제한으로 공개하지 마세요.
- `terraform destroy`, `bootstrap.sh --destroy`는 VM을 삭제할 수 있으므로 대상을 확인한 후 실행하세요.
