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

| VM 이름 | VMID | CPU | RAM | Disk | OS | Node |
|---|---|---|---|---|---|---|
| vm-iac-01 | 203 | 2 core | 2 GB | 20 GB | Ubuntu 24.04 | pve-main |

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
