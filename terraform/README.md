# home-server-iac / terraform

Proxmox VM 인프라를 Terraform으로 관리합니다.

## 파일 구조

```
terraform/
├── main.tf                  # locals (공통값)
├── vms.tf                   # VM 선언
├── imports.tf               # import 블록 (apply 후 제거)
├── netbox.tf.example        # NetBox 인벤토리 연동 예시
├── netbox.tf                # NetBox 로컬 인벤토리 (gitignore)
├── provider.tf              # Proxmox provider 설정
├── variables.tf             # 민감 변수 선언
├── terraform.tfvars         # 실제 값 주입 (gitignore)
└── modules/
    └── proxmox_vm/          # VM 공통 모듈
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf
```

## 명령어

### 초기화

```bash
terraform init
```

NetBox 연동을 처음 추가했거나 provider 버전을 바꾼 경우에도 다시 실행합니다.

```bash
terraform init
```

### Plan

```bash
# 전체 plan
terraform plan

# destroy 항목만 확인
terraform plan 2>&1 | grep -E "will be destroyed|must be replaced"

# 특정 VM만 plan
terraform plan -target=module.vm-iac-01
```

### Apply

```bash
# 전체 apply
terraform apply

# 특정 VM만 apply
terraform apply -target=module.vm-iac-01 -target=module.vm-npm-01
```

### State

```bash
# 리소스 목록 확인
terraform state list

# 리소스 state 이동 (모듈 이전 시)
terraform state mv proxmox_vm_qemu.vm-iac-01 module.vm-iac-01.proxmox_vm_qemu.vm
```

### Import

```bash
# imports.tf 선언 후 plan으로 diff 확인
terraform plan

# 특정 VM만 import apply
terraform apply -target=module.vm-iac-01
```

### 문서 업데이트

```bash
# 모듈 변수 변경 후 README 재생성
terraform-docs ./modules/proxmox_vm
```

## VM 추가 방법

`vms.tf`에 아래 블록 추가 후 `imports.tf`에 import 블록 추가:

```hcl
# vms.tf
module "vm-xxx-01" {
  source      = "./modules/proxmox_vm"
  name        = "vm-xxx-01"
  vmid        = 999
  target_node = local.default_node
  storage     = local.default_storage
  memory      = 2048
  cores       = 2
  disk_size   = "20G"
  macaddr     = "bc:24:11:xx:xx:xx"
  notes       = "- 추가 설명"
}

# imports.tf
import {
  to = module.vm-xxx-01.proxmox_vm_qemu.vm
  id = "pve-main/qemu/999"
}
```

## Kubernetes HA VM 세트

Kubernetes 설치용 VM은 `k8s_vms.tf`에 별도 선언되어 있으며 기본값은 비활성화되어 있습니다.

```bash
cp k8s.auto.tfvars.example k8s.auto.tfvars
terraform plan
terraform apply
terraform output k8s_shell_env_hint
```

`k8s_vms`의 IP는 VM 내부 네트워크 설정을 직접 바꾸지는 않습니다. Terraform VM 생성값과 `scripts/kubernetes/.env`, Ansible inventory를 같은 기준으로 맞추기 위한 설치 입력값입니다.

## NetBox 연동

Terraform이 Proxmox VM을 만들고, 같은 선언을 NetBox 인벤토리에도 등록하도록 구성할 수 있습니다. 기본값은 비활성화입니다.

```bash
cp netbox.tf.example netbox.tf
export NETBOX_SERVER_URL="https://<NETBOX_HOST>"
export NETBOX_API_TOKEN="nbt_xxx..."

terraform plan -var='netbox_enabled=true'
terraform apply -var='netbox_enabled=true'
```

`netbox.tf`는 VM 이름, VMID, MAC, 내부 IP 같은 로컬 인벤토리를 포함할 수 있어 git에서 제외합니다. Git에는 `netbox.tf.example`만 올립니다.

생성되는 NetBox 객체:

- Site: `Home Lab`
- Cluster Type: `Proxmox VE`
- Cluster: `proxmox-home`
- Virtual Machine: Terraform에 선언된 일반 VM과, `k8s_enabled=true`일 때 Kubernetes VM
- Interface: 각 VM의 `eth0`
- IP Address/Primary IP: `netbox_regular_vm_ips` 또는 `k8s_vms`에 IP가 있는 VM
- MAC Address: Terraform 선언에 `macaddr`가 있는 VM

일반 VM의 IP는 Terraform 코드에 확정값이 없는 경우가 있어 별도 변수로 주입합니다.

```hcl
netbox_enabled = true

netbox_regular_vm_ips = {
  vm-netbox-01 = "192.168.219.208/24"
  vm-iac-01    = "192.168.219.203/24"
}
```

NetBox를 내부 HTTPS 또는 자체 서명 인증서로 운영한다면 필요할 때만 아래 값을 사용합니다.

```hcl
netbox_allow_insecure_https = true
```

Proxbox를 함께 쓰는 경우에도 Terraform이 만든 VM/IP/MAC 객체는 Terraform이 소유하도록 두는 것을 권장합니다. Proxbox는 Proxmox 실제 상태 조회나 초기 발견 보조 용도로만 쓰면 NetBox 안에서 소유권이 덜 섞입니다.
