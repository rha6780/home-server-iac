module "vm-iac-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-iac-01"
  vmid        = 203
  target_node = local.default_node
  memory      = 2048
  cores       = 2
  disk_size   = "20G"
  storage     = local.default_storage
  macaddr = "bc:24:11:36:e2:1f"
}

module "vm-npm-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-npm-01"
  vmid        = 200
  target_node = local.default_node
  storage     = local.default_storage
}

module "vm-database-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-database-01"
  vmid        = 201
  target_node = local.default_node
  storage     = local.default_storage
  cores = 4
  memory = 4096
  disk_size = "40G"
}

module "vm-hoppscotch-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-hoppscotch-01"
  vmid        = 202
  target_node = local.default_node
  storage     = local.default_storage
}

module "vm-docker-registry-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-docker-registry-01"
  vmid        = 204
  target_node = local.default_node
  storage     = local.default_storage
}

module "vm-vpn-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-vpn-01"
  vmid        = 205
  target_node = local.default_node
  storage     = local.default_storage
}

module "vm-jenkins-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-jenkins-01"
  vmid        = 206
  target_node = local.default_node
  storage     = local.default_storage
}

module "vm-ourjournal-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-ourjournal-01"
  vmid        = 301
  target_node = local.default_node
  storage     = local.default_storage
}

module "vm-mine-base-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-mine-base-01"
  vmid        = 500
  target_node = local.default_node
  storage     = local.default_storage
  memory      = 8196
  cores       = 2
  disk_size   = "32G"
  start_at_node_boot = false

}

module "vm-mine-build-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-mine-build-01"
  vmid        = 501
  target_node = local.default_node
  storage     = local.default_storage
  memory      = 8196
  cores       = 2
  disk_size   = "32G"
  start_at_node_boot = false
}

module "vm-mine-wild-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-mine-wild-01"
  vmid        = 502
  target_node = local.default_node
  storage     = local.default_storage
  memory      = 8196
  disk_size   = "32G"
  start_at_node_boot = false
}

module "vm-mine-db-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-mine-db-01"
  vmid        = 503
  target_node = local.default_node
  storage     = local.default_storage
  disk_size   = "32G"
  start_at_node_boot = false
}

module "vm-file-share-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-file-share-01"
  vmid        = 504
  target_node = local.default_node
  storage     = local.default_storage
  disk_size = "32G"
}

module "vm-mine-lfin-01" {
  source = "./modules/proxmox_vm"

  name        = "vm-mine-lfin-01"
  vmid        = 505
  target_node = local.default_node
  storage     = local.default_storage
  memory      = 32768
  cores       = 4
}
