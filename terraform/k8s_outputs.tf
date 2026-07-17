output "k8s_inventory" {
  description = "Kubernetes 설치에 사용할 VM 이름/IP/역할 정보"
  value       = module.kubernetes.inventory
}

output "k8s_shell_env_hint" {
  description = "scripts/kubernetes/.env 작성 시 참고할 주요 IP"
  value       = module.kubernetes.shell_env_hint
}
