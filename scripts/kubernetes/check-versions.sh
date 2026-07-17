#!/bin/bash
# ============================================================
# check-versions.sh - Kubernetes 배포 구성요소 버전 조회
#
# 기본값:
#   - .env.example 의 설정 버전만 출력
#
# 사용법:
#   bash check-versions.sh
#   bash check-versions.sh --env .env --remote
#   bash check-versions.sh --latest
#   bash check-versions.sh --env .env --remote --latest
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/k8s-version-check.log}"

source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${SCRIPT_DIR}/.env.example"
CHECK_REMOTE=false
CHECK_LATEST=false

usage() {
  cat <<EOF
Usage:
  bash check-versions.sh [--env PATH] [--remote] [--latest]

Options:
  --env PATH    읽을 환경 파일입니다. 기본값: scripts/kubernetes/.env.example
  --remote      .env의 SSH 정보로 원격 노드에 설치된 버전을 조회합니다.
  --latest      인터넷/helm repo를 통해 최신 후보 버전을 조회합니다.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      if [[ -z "${2:-}" ]]; then
        echo "--env 뒤에 파일 경로가 필요합니다." >&2
        exit 1
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    --remote)
      CHECK_REMOTE=true
      shift
      ;;
    --latest)
      CHECK_LATEST=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${ENV_FILE}" != /* ]]; then
  ENV_FILE="${PWD}/${ENV_FILE}"
fi

load_env "${ENV_FILE}"

print_row() {
  printf "%-28s %-24s %-24s %-24s\n" "$1" "$2" "$3" "$4"
}

print_section() {
  echo ""
  echo "== $1 =="
}

strip_v() {
  local value="${1:-}"
  value="${value#v}"
  echo "${value}"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

fetch_url() {
  local url="$1"
  if need_cmd curl; then
    curl -fsSL "$url"
  else
    return 1
  fi
}

latest_github_release() {
  local repo="$1"
  fetch_url "https://api.github.com/repos/${repo}/releases/latest" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))'
}

latest_github_tag() {
  local repo="$1"
  fetch_url "https://api.github.com/repos/${repo}/tags?per_page=1" \
    | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data[0].get("name","") if data else "")'
}

latest_helm_chart() {
  local repo_name="$1" repo_url="$2" chart="$3"
  if ! need_cmd helm; then
    echo "helm 없음"
    return 0
  fi

  helm repo add "$repo_name" "$repo_url" >/dev/null 2>&1 || true
  helm repo update "$repo_name" >/dev/null 2>&1 || true
  helm search repo "${repo_name}/${chart}" -o json 2>/dev/null \
    | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data[0].get("version","") if data else "")'
}

latest_oci_chart() {
  local chart_ref="$1"
  if ! need_cmd helm; then
    echo "helm 없음"
    return 0
  fi

  helm show chart "$chart_ref" 2>/dev/null \
    | awk -F': ' '$1 == "version" {print $2; exit}'
}

configured_versions() {
  print_section "Configured versions (${ENV_FILE})"
  print_row "component" "configured" "remote" "latest"
  print_row "---------" "----------" "------" "------"
  print_row "containerd.io" "${CONTAINERD_VERSION:-unset}" "-" "-"
  print_row "Kubernetes" "${K8S_VERSION:-unset}" "-" "-"
  print_row "Kubernetes minor" "${K8S_MINOR:-unset}" "-" "-"
  print_row "Helm" "${HELM_VERSION:-unset}" "-" "-"
  print_row "HAProxy" "${HAPROXY_VERSION:-unset}" "-" "-"
  print_row "Calico chart" "${CALICO_CHART_VERSION:-unset}" "-" "-"
  print_row "MetalLB chart" "${METALLB_CHART_VERSION:-unset}" "-" "-"
  print_row "Gateway API CRD" "${GATEWAY_API_VERSION:-unset}" "-" "-"
  print_row "NGINX Gateway Fabric" "${NGF_CHART_VERSION:-unset}" "-" "-"
}

remote_node_versions() {
  local host="$1" role="$2"
  local cmd
  cmd=$(cat <<'EOF'
set +e
echo "containerd=$(containerd --version 2>/dev/null | awk '{print $3}')"
echo "containerd_pkg=$(dpkg-query -W -f='${Version}' containerd.io 2>/dev/null)"
echo "kubelet=$(kubelet --version 2>/dev/null | awk '{print $2}')"
echo "kubeadm=$(kubeadm version -o short 2>/dev/null)"
echo "kubectl=$(kubectl version --client=true --output=yaml 2>/dev/null | awk '/gitVersion:/ {print $2; exit}')"
echo "helm=$(helm version --short 2>/dev/null | sed 's/^v//' | cut -d+ -f1)"
echo "haproxy=$(haproxy -v 2>/dev/null | awk 'NR==1 {print $3}')"
EOF
)

  echo ""
  echo "-- ${role} (${host}) --"
  if ! _ssh "$host" "$cmd" 2>/dev/null; then
    echo "ERROR: SSH 조회 실패"
  fi
}

remote_cluster_versions() {
  print_section "Remote installed versions"

  remote_node_versions "${HAPROXY_IP}" "haproxy"
  remote_node_versions "${CP_MASTER_IP}" "control-plane-primary"

  local ip
  for ip in "${CP_JOIN_IPS[@]:-}"; do
    [[ -n "$ip" ]] && remote_node_versions "$ip" "control-plane-join"
  done
  for ip in "${WORKER_IPS[@]:-}"; do
    [[ -n "$ip" ]] && remote_node_versions "$ip" "worker"
  done

  print_section "Remote Helm releases (${CP_MASTER_IP})"
  _ssh "${CP_MASTER_IP}" '
set +e
helm list -A 2>/dev/null | awk "NR==1 || /calico|metallb|nginx-gateway-fabric/"
kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath="{.metadata.labels.gateway\.networking\.k8s\.io/bundle-version}{\"\n\"}" 2>/dev/null \
  | awk "{print \"gateway_api_crd=\" \$0}"
' || echo "ERROR: Helm release 조회 실패"
}

latest_versions() {
  print_section "Latest candidates"
  print_row "component" "configured" "remote" "latest"
  print_row "---------" "----------" "------" "------"

  local k8s_latest k8s_minor_latest helm_latest calico_latest metallb_latest gateway_latest ngf_latest
  k8s_latest=$(strip_v "$(fetch_url "https://dl.k8s.io/release/stable.txt" 2>/dev/null || true)")
  k8s_minor_latest=$(strip_v "$(fetch_url "https://dl.k8s.io/release/stable-${K8S_MINOR}.txt" 2>/dev/null || true)")
  helm_latest=$(strip_v "$(latest_github_release "helm/helm" 2>/dev/null || true)")
  calico_latest=$(latest_helm_chart "projectcalico" "https://docs.tigera.io/calico/charts" "tigera-operator" 2>/dev/null || true)
  metallb_latest=$(latest_helm_chart "metallb" "https://metallb.github.io/metallb" "metallb" 2>/dev/null || true)
  gateway_latest=$(strip_v "$(latest_github_release "kubernetes-sigs/gateway-api" 2>/dev/null || latest_github_tag "kubernetes-sigs/gateway-api" 2>/dev/null || true)")
  ngf_latest=$(latest_oci_chart "oci://ghcr.io/nginx/charts/nginx-gateway-fabric" 2>/dev/null || true)

  print_row "Kubernetes stable" "${K8S_VERSION:-unset}" "-" "${k8s_latest:-unknown}"
  print_row "Kubernetes ${K8S_MINOR}" "${K8S_VERSION:-unset}" "-" "${k8s_minor_latest:-unknown}"
  print_row "Helm" "${HELM_VERSION:-unset}" "-" "${helm_latest:-unknown}"
  print_row "Calico chart" "${CALICO_CHART_VERSION:-unset}" "-" "${calico_latest:-unknown}"
  print_row "MetalLB chart" "${METALLB_CHART_VERSION:-unset}" "-" "${metallb_latest:-unknown}"
  print_row "Gateway API CRD" "${GATEWAY_API_VERSION:-unset}" "-" "${gateway_latest:-unknown}"
  print_row "NGINX Gateway Fabric" "${NGF_CHART_VERSION:-unset}" "-" "${ngf_latest:-unknown}"
  print_row "containerd.io" "${CONTAINERD_VERSION:-unset}" "-" "check via apt-cache on target Ubuntu"
  print_row "HAProxy" "${HAPROXY_VERSION:-unset}" "-" "check via apt-cache on target Ubuntu"
}

configured_versions

if [[ "${CHECK_REMOTE}" == "true" ]]; then
  remote_cluster_versions
fi

if [[ "${CHECK_LATEST}" == "true" ]]; then
  latest_versions
fi
