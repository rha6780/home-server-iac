#!/bin/bash
# ============================================================
# Step 3. Control Plane Join
# 대상: CP_JOIN_IPS 배열에 설정된 노드 — 개수 제한 없음, 빈 배열이면 스킵
# 실행: bash step-3-cp-join.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_env

log_step "Step 3. Control Plane Join"

# CP_JOIN_IPS 배열 빈값 필터링
CP_JOIN_NODES=()
for NODE_IP in "${CP_JOIN_IPS[@]:-}"; do
  [[ -n "${NODE_IP}" ]] && CP_JOIN_NODES+=("${NODE_IP}")
done

if [[ ${#CP_JOIN_NODES[@]} -eq 0 ]]; then
  log_warn "CP_JOIN_IPS 가 .env 에 설정되지 않아 Step 3 를 건너뜁니다."
  exit 0
fi

log_info "  Join 대상: ${CP_JOIN_NODES[*]}"

# cp-01 에서 join 토큰 수집
fetch_join_info

# 각 CP 노드에 배포 및 join 실행
for NODE_IP in "${CP_JOIN_NODES[@]}"; do
  log_info ""
  log_info "  ── CP join: ${NODE_IP} ──"

  check_ssh "${NODE_IP}"

  tmp=$(inject_master_join \
    "${SCRIPT_DIR}/setup-master.sh" \
    "${NODE_IP}" \
    "${JOIN_TOKEN}" "${JOIN_CA_HASH}" "${JOIN_CERT_KEY}")
  scp_file "${tmp}" "${NODE_IP}" "~/setup-master.sh"
  rm -f "${tmp}"

  remote_exec "${NODE_IP}" "CP join" "sudo bash ~/setup-master.sh"
  log_success "  CP join 완료: ${NODE_IP}"
done

log_success "Step 3 완료 — Control Plane Join (${CP_JOIN_NODES[*]})"
