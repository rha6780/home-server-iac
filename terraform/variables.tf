# variables.tf
variable "provider_pm_api_url" {
  type        = string
  sensitive   = true
  description = "Proxmox API URL"
}

variable "provider_pm_user" {
  type        = string
  sensitive   = true
  description = "Proxmox API user"
}


variable "provider_pm_password" {
  type        = string
  sensitive   = true
  description = "Proxmox API user password"
}

variable "netbox_enabled" {
  type        = bool
  description = "NetBox에 Terraform 관리 VM/IP 인벤토리를 등록할지 여부"
  default     = false
}

variable "netbox_allow_insecure_https" {
  type        = bool
  description = "NetBox가 자체 서명 인증서 또는 내부 인증서를 사용할 때 HTTPS 검증을 완화할지 여부"
  default     = false
}

variable "netbox_skip_version_check" {
  type        = bool
  description = "Terraform plan 시 NetBox 버전 확인을 건너뜁니다. 로컬 테스트 또는 일시적인 접속 문제 확인에 유용합니다."
  default     = false
}

variable "netbox_site_name" {
  type        = string
  description = "NetBox에 생성할 홈서버 사이트 이름"
  default     = "Home Lab"
}

variable "netbox_site_slug" {
  type        = string
  description = "NetBox 홈서버 사이트 slug"
  default     = "home-lab"
}

variable "netbox_cluster_name" {
  type        = string
  description = "NetBox에 생성할 Proxmox 클러스터 이름"
  default     = "proxmox-home"
}

variable "netbox_regular_vm_ips" {
  type        = map(string)
  description = "일반 VM의 NetBox IP 등록값. CIDR 형식으로 입력합니다. 예: { vm-netbox-01 = \"192.168.219.208/24\" }"
  default     = {}
}

variable "netbox_k8s_ip_prefix_length" {
  type        = number
  description = "k8s_vms의 단일 IP를 NetBox CIDR IP로 등록할 때 사용할 prefix length"
  default     = 24
}


