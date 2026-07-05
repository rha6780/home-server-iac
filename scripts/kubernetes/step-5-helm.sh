#!/bin/bash
# ============================================================
# Step 5. Helm 컴포넌트 설치
# 대상: cp-01 (CP_MASTER_IP)
# 설치: Calico CNI / MetalLB / Gateway API CRD / NGINX Gateway Fabric
# 실행: bash step-5-helm.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_env

log_step "Step 5. Helm 컴포넌트 설치 (${CP_MASTER_IP})"
log_info "  Calico           : ${CALICO_CHART_VERSION}"
log_info "  MetalLB          : ${METALLB_CHART_VERSION}"
log_info "  Gateway API CRD  : ${GATEWAY_API_VERSION}"
log_info "  NGINX GW Fabric  : ${NGF_CHART_VERSION}"

# SSH 연결 확인
check_ssh "${CP_MASTER_IP}"

# helm-charts 디렉터리 전체 전송
scp_dir "${SCRIPT_DIR}/04.helm-charts" "${CP_MASTER_IP}" "~/"

# MetalLB IP 풀 yaml 에 .env IP 범위 주입 후 덮어쓰기
tmp_pool=$(inject_ip_pool \
  "${SCRIPT_DIR}/04.helm-charts/metallb/ip-address-pool.yaml")
scp_file "${tmp_pool}" "${CP_MASTER_IP}" \
  "~/04.helm-charts/metallb/ip-address-pool.yaml"
rm -f "${tmp_pool}"

# 05.post-install-helm.sh 에 버전 주입 후 전송
tmp_helm=$(inject_helm "${SCRIPT_DIR}/05.post-install-helm.sh")
scp_file "${tmp_helm}" "${CP_MASTER_IP}" "~/05.post-install-helm.sh"
rm -f "${tmp_helm}"

# 원격 실행
remote_exec "${CP_MASTER_IP}" "Helm 컴포넌트 설치" "bash ~/05.post-install-helm.sh"

log_success "Step 5 완료 — Helm 컴포넌트 설치"
log_info ""
log_info "  확인 명령어 (cp-01 에서):"
log_info "    kubectl get nodes -o wide"
log_info "    kubectl get pods -A"
log_info "    kubectl get svc  -n nginx-gateway"
log_info "    kubectl get gateway -A"
