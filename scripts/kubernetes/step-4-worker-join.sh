#!/bin/bash
# ============================================================
# Step 4. Worker Node Join
# 대상: WORKER_IPS 에 설정된 모든 Worker 노드
# 실행: bash step-4-worker-join.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_env

log_step "Step 4. Worker Node Join"

# WORKER_IPS 빈값 필터링
VALID_WORKERS=()
for NODE_IP in "${WORKER_IPS[@]:-}"; do
  [[ -n "${NODE_IP}" ]] && VALID_WORKERS+=("${NODE_IP}")
done

if [[ ${#VALID_WORKERS[@]} -eq 0 ]]; then
  log_warn "WORKER_IPS 가 .env 에 설정되지 않아 Step 4 를 건너뜁니다."
  exit 0
fi

log_info "  Join 대상: ${VALID_WORKERS[*]}"

# cp-01 에서 join 토큰 수집
fetch_join_info

# 각 Worker 노드에 배포 및 join 실행
for NODE_IP in "${VALID_WORKERS[@]}"; do
  log_info ""
  log_info "  ── Worker join: ${NODE_IP} ──"

  check_ssh "${NODE_IP}"

  tmp=$(inject_worker \
    "${SCRIPT_DIR}/setup-worker.sh" \
    "${JOIN_TOKEN}" "${JOIN_CA_HASH}")
  scp_file "${tmp}" "${NODE_IP}" "~/setup-worker.sh"
  rm -f "${tmp}"

  remote_exec "${NODE_IP}" "Worker join" "sudo bash ~/setup-worker.sh"
  log_success "  Worker join 완료: ${NODE_IP}"
done

log_success "Step 4 완료 — Worker Join (${VALID_WORKERS[*]})"
