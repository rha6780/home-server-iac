locals {
  enabled_vms = var.enabled ? var.vms : {}
}

module "vms" {
  for_each = local.enabled_vms
  source   = "../proxmox_vm"

  name        = each.key
  vmid        = each.value.vmid
  target_node = coalesce(each.value.target_node, var.default_target_node)
  storage     = coalesce(each.value.storage, var.default_storage)
  clone       = var.vm_clone
  memory      = each.value.memory
  cores       = each.value.cores
  disk_size   = each.value.disk_size
  macaddr     = each.value.macaddr
  bridge      = each.value.bridge
  ip          = each.value.ip
  tags        = "kubernetes;${each.value.role}"
  notes       = "- role : ${each.value.role}\n- ip : ${each.value.ip}"
}
