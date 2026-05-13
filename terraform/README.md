# home-server-iac / terraform

Proxmox VM 인프라를 Terraform으로 관리합니다.

## 파일 구조

```
terraform/
├── main.tf                  # locals (공통값)
├── vms.tf                   # VM 선언
├── imports.tf               # import 블록 (apply 후 제거)
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
