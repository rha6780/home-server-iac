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
└── semaphore/                  # Semaphore + Ansible 자동화
    └── playbooks/
        └── proxmox/
            ├── list-vms.yml    # Proxmox VM 목록 조회 플레이북
            └── requirements.yml # Ansible 컬렉션 의존성
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

### Proxmox 연동 변수 (Semaphore에서 설정)

| 변수명 | 설명 |
|---|---|
| `proxmox_api_host` | Proxmox 호스트 주소 |
| `proxmox_api_user` | API 사용자 (예: `ansible@pam`) |
| `proxmox_api_token_id` | API 토큰 ID |
| `proxmox_api_token_secret` | API 토큰 시크릿 |

---

## 워크플로우

```
1. VM 프로비저닝
   로컬 터미널 → terraform apply → Proxmox API → VM 생성

2. VM 구성 자동화
   Semaphore UI → Ansible 플레이북 실행 → Proxmox API / SSH → VM 설정
```

---

## 사전 요구사항

- Terraform >= 0.14
- Ansible (+ `community.proxmox` 컬렉션)
- Proxmox VE 환경 (API 접근 가능)
- Semaphore 인스턴스 (Ansible 플레이북 UI 실행용)
