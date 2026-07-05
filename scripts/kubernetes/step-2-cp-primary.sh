#!/bin/bash
# ============================================================
# Step 2. Control Plane Primary 초기화
# 대상: cp-01 (CP_MASTER_IP) — 첫 번째 Control Plane 노드
# 실행: bash step-2-cp-primary.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_env

log_step "Step 2. Control Plane Primary 초기화 (${CP_MASTER_IP})"

# SSH 연결 확인
check_ssh "${CP_MASTER_IP}"

# setup-master.sh 에 .env 값 주입 (MODE=primary)
tmp=$(inject_master "${SCRIPT_DIR}/setup-master.sh" "primary" "${CP_MASTER_IP}")
scp_file "${tmp}" "${CP_MASTER_IP}" "~/setup-master.sh"
rm -f "${tmp}"

# 원격 실행
remote_exec "${CP_MASTER_IP}" "CP Primary 초기화" "sudo bash ~/setup-master.sh"

log_success "Step 2 완료 — Control Plane Primary (${CP_MASTER_IP})"
log_info ""
log_info "  다음 단계:"
log_info "    bash step-3-cp-join.sh    # cp-02, cp-03 join"
log_info "    bash step-4-worker-join.sh # Worker 노드 join"
