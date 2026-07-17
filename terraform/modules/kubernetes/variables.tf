variable "enabled" {
  type        = bool
  description = "Kubernetes VM 생성 여부"
}

variable "vm_clone" {
  type        = string
  description = "Kubernetes VM 생성에 사용할 Proxmox 템플릿 또는 원본 VM 이름"
}

variable "default_target_node" {
  type        = string
  description = "VM별 target_node가 없을 때 사용할 기본 Proxmox 노드"
}

variable "default_storage" {
  type        = string
  description = "VM별 storage가 없을 때 사용할 기본 스토리지"
}

variable "vms" {
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
  description = "Kubernetes VM 정의"
}
