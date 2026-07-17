terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc06"
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.6"
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

provider "netbox" {
  allow_insecure_https = var.netbox_allow_insecure_https
  skip_version_check   = var.netbox_skip_version_check
}
