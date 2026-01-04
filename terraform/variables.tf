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



