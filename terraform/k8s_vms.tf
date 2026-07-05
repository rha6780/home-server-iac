variable "k8s_enabled" {
  type        = bool
  description = "Kubernetes HA cluster VM 생성 여부"
  default     = false
}

variable "k8s_vm_clone" {
  type        = string
  description = "Kubernetes VM 생성에 사용할 Proxmox 템플릿 또는 원본 VM 이름"
  default     = "vm-tamplate-01"
}

variable "k8s_vms" {
  type = map(object({
    vmid        = number
    memory      = optional(number, 4096)
    cores       = optional(number, 2)
    disk_size   = optional(string, "40G")
    macaddr     = optional(string)
    target_node = optional(string)
    storage     = optional(string)
    bridge      = optional(string, "vmbr0")
    ip          = string
    role        = string
  }))
  description = "Kubernetes HA cluster VM 정의. ip는 설치 스크립트/Ansible inventory 생성 기준값입니다."
  default = {
    vm-dev-haproxy-01 = {
      vmid      = 610
      memory    = 2048
      cores     = 2
      disk_size = "20G"
      ip        = "192.168.219.29"
      role      = "haproxy"
    }
    vm-dev-k8s-cp-01 = {
      vmid      = 611
      memory    = 8192
      cores     = 4
      disk_size = "60G"
      ip        = "192.168.219.30"
      role      = "control-plane-primary"
    }
    vm-dev-k8s-cp-02 = {
      vmid      = 612
      memory    = 8192
      cores     = 4
      disk_size = "60G"
      ip        = "192.168.219.31"
      role      = "control-plane"
    }
    vm-dev-k8s-cp-03 = {
      vmid      = 613
      memory    = 8192
      cores     = 4
      disk_size = "60G"
      ip        = "192.168.219.32"
      role      = "control-plane"
    }
    vm-dev-k8s-wk-01 = {
      vmid      = 621
      memory    = 8192
      cores     = 4
      disk_size = "80G"
      ip        = "192.168.219.41"
      role      = "worker"
    }
    vm-dev-k8s-wk-02 = {
      vmid      = 622
      memory    = 8192
      cores     = 4
      disk_size = "80G"
      ip        = "192.168.219.42"
      role      = "worker"
    }
    vm-dev-k8s-wk-03 = {
      vmid      = 623
      memory    = 8192
      cores     = 4
      disk_size = "80G"
      ip        = "192.168.219.43"
      role      = "worker"
    }
  }
}

locals {
  k8s_enabled_vms = var.k8s_enabled ? var.k8s_vms : {}
}

module "k8s_vms" {
  for_each = local.k8s_enabled_vms
  source   = "./modules/proxmox_vm"

  name        = each.key
  vmid        = each.value.vmid
  target_node = coalesce(each.value.target_node, local.default_node)
  storage     = coalesce(each.value.storage, local.default_storage)
  clone       = var.k8s_vm_clone
  memory      = each.value.memory
  cores       = each.value.cores
  disk_size   = each.value.disk_size
  macaddr     = each.value.macaddr
  bridge      = each.value.bridge
  ip          = each.value.ip
  tags        = "kubernetes;${each.value.role}"
  notes       = "- role : ${each.value.role}\n- ip : ${each.value.ip}"
}
