output "k8s_inventory" {
  description = "Kubernetes 설치에 사용할 VM 이름/IP/역할 정보"
  value = {
    for name, vm in var.k8s_vms : name => {
      vmid = vm.vmid
      ip   = vm.ip
      role = vm.role
    }
  }
}

output "k8s_shell_env_hint" {
  description = "scripts/kubernetes/.env 작성 시 참고할 주요 IP"
  value = {
    haproxy_ip = one([
      for _, vm in var.k8s_vms : vm.ip
      if vm.role == "haproxy"
    ])
    cp_master_ip = one([
      for _, vm in var.k8s_vms : vm.ip
      if vm.role == "control-plane-primary"
    ])
    cp_join_ips = [
      for _, vm in var.k8s_vms : vm.ip
      if vm.role == "control-plane"
    ]
    worker_ips = [
      for _, vm in var.k8s_vms : vm.ip
      if vm.role == "worker"
    ]
  }
}
