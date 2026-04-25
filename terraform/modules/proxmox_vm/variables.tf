variable "name" {
  type        = string
  description = "VM 이름"
}

variable "vmid" {
  type        = number
  description = "Proxmox VM ID"
}

variable "target_node" {
  type        = string
  description = "Proxmox 노드 이름"
  default     = "pve-main"
}

variable "memory" {
  type        = number
  description = "메모리 (MB)"
  default     = 2048
}

variable "cores" {
  type        = number
  description = "CPU 코어 수"
  default     = 2
}

variable "sockets" {
  type        = number
  description = "CPU 소켓 수"
  default     = 1
}

variable "cpu_type" {
  type        = string
  description = "CPU 타입"
  default     = "x86-64-v2-AES"
}

variable "disk_size" {
  type        = string
  description = "디스크 크기 (예: 20G)"
  default     = "20G"
}

variable "storage" {
  type        = string
  description = "스토리지 풀"
  default     = "local-lvm"
}

variable "macaddr" {
  type        = string
  description = "네트워크 MAC 주소 (null이면 Proxmox 자동 할당)"
  default     = null
}

variable "bridge" {
  type        = string
  description = "네트워크 브릿지"
  default     = "vmbr0"
}

variable "tags" {
  type        = string
  description = "VM 태그"
  default     = ""
}

variable "notes" {
  type        = string
  description = "VM 추가 설명 (공통 포맷 외 추가 내용)"
  default     = ""
}

variable "start_at_node_boot" {
  type        = bool
  description = "노드 부팅 시 자동 시작"
  default     = true
}
