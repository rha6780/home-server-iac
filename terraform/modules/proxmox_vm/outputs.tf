output "name" {
  description = "VM 이름"
  value       = proxmox_vm_qemu.vm.name
}

output "vmid" {
  description = "Proxmox VM ID"
  value       = proxmox_vm_qemu.vm.vmid
}

output "id" {
  description = "Terraform 리소스 ID"
  value       = proxmox_vm_qemu.vm.id
}
