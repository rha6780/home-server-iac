terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc06"
    }
  }
  required_version = ">= 0.14"
}

provider "proxmox" {
  pm_api_url      = var.provider_pm_api_url
  pm_user         = var.provider_pm_user
  pm_password     = var.provider_pm_password
  pm_tls_insecure = true
}