#!/bin/bash
# ============================================================
# Step 1. HAProxy 설치
# 대상: HAProxy 전용 노드 (HAPROXY_IP)
# 실행: bash step-1-haproxy.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_env

log_step "Step 1. HAProxy 설치 (${HAPROXY_IP})"

# SSH 연결 확인
check_ssh "${HAPROXY_IP}"

# setup-haproxy.sh 에 .env 값 주입 후 전송
tmp=$(inject_haproxy "${SCRIPT_DIR}/setup-haproxy.sh")
scp_file "${tmp}" "${HAPROXY_IP}" "~/setup-haproxy.sh"
rm -f "${tmp}"

# 원격 실행
remote_exec "${HAPROXY_IP}" "HAProxy 설치" "sudo bash ~/setup-haproxy.sh"

log_success "Step 1 완료 — HAProxy"
log_info "  LB 엔드포인트 : ${HAPROXY_IP}:${LB_FRONTEND_PORT}"
log_info "  Stats 페이지  : http://${HAPROXY_IP}:${STATS_PORT}/stats"
