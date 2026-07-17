output "inventory" {
  description = "Kubernetes 설치에 사용할 VM 이름/IP/역할 정보"
  value = {
    for name, vm in var.vms : name => {
      vmid = vm.vmid
      ip   = vm.ip
      role = vm.role
    }
  }
}

output "shell_env_hint" {
  description = "Kubernetes 설치 스크립트 환경 변수 작성에 사용할 IP 정보"
  value = {
    haproxy_ip = one([
      for _, vm in var.vms : vm.ip
      if vm.role == "haproxy"
    ])
    cp_master_ip = one([
      for _, vm in var.vms : vm.ip
      if vm.role == "control-plane-primary"
    ])
    cp_join_ips = [
      for _, vm in var.vms : vm.ip
      if vm.role == "control-plane"
    ]
    worker_ips = [
      for _, vm in var.vms : vm.ip
      if vm.role == "worker"
    ]
  }
}
