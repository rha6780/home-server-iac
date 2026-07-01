#!/bin/bash
# ============================================================
# deploy.sh - Kubernetes HA Cluster 통합 배포 오케스트레이터
# 로컬 PC 에서 실행
#
# 사용법:
#   bash deploy.sh              # 대화형 메뉴
#   bash deploy.sh --step 1     # Step 1 만 실행
#   bash deploy.sh --step 1,3,5 # Step 1, 3, 5 실행
#   bash deploy.sh --all        # 전체 실행 (1→2→3→4→5)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 로그 파일 (step 스크립트들이 공유)
export LOG_FILE="${SCRIPT_DIR}/deploy_$(date '+%Y%m%d_%H%M%S').log"

source "${SCRIPT_DIR}/lib.sh"
load_env

# ============================================================
# 로그 파일 헤더
# ============================================================
{
  echo "=================================================="
  echo "  Kubernetes HA Cluster Deploy"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "  LOG: ${LOG_FILE}"
  echo "=================================================="
} >> "$LOG_FILE"

log_info "로그 파일: ${LOG_FILE}"

# ============================================================
# Step 실행 (각 step-*.sh 파일 호출)
# ============================================================
run_step() {
  local num="$1"
  case "${num}" in
    1) bash "${SCRIPT_DIR}/step-1-haproxy.sh"     ;;
    2) bash "${SCRIPT_DIR}/step-2-cp-primary.sh"  ;;
    3) bash "${SCRIPT_DIR}/step-3-cp-join.sh"     ;;
    4) bash "${SCRIPT_DIR}/step-4-worker-join.sh" ;;
    5) bash "${SCRIPT_DIR}/step-5-helm.sh"        ;;
    *) log_warn "알 수 없는 Step: ${num} (1~5 중 선택)" ;;
  esac
}

run_steps() {
  local input="$1"
  IFS=',' read -ra LIST <<< "${input}"
  for s in "${LIST[@]}"; do
    run_step "$(echo "${s}" | tr -d ' ')"
  done
}

# ============================================================
# 요약 출력
# ============================================================
print_summary() {
  local cp_list="${CP_01_IP}"
  for ip in "${CP_JOIN_IPS[@]:-}"; do
    [[ -n "${ip}" ]] && cp_list+=" / ${ip}"
  done
  local worker_list="${WORKER_IPS[*]:-없음}"

  echo ""
  echo -e "${BOLD}${CYAN}=================================================${RESET}"
  echo -e "${BOLD}${CYAN}  배포 완료 요약${RESET}"
  echo -e "${BOLD}${CYAN}=================================================${RESET}"
  echo ""
  echo -e "  HAProxy LB   : ${HAPROXY_IP}:${LB_FRONTEND_PORT}"
  echo -e "  Stats 페이지  : http://${HAPROXY_IP}:${STATS_PORT}/stats"
  echo -e "  Control Plane: ${cp_list}"
  echo -e "  Worker Nodes : ${worker_list}"
  echo ""
  echo -e "  로그 파일    : ${LOG_FILE}"
  echo ""
}

# ============================================================
# 대화형 메뉴
# ============================================================
print_menu() {
  local cp_join_label="${CP_JOIN_IPS[*]:-설정 없음}"
  local worker_label="${WORKER_IPS[*]:-설정 없음}"

  echo ""
  echo -e "${BOLD}=================================================${RESET}"
  echo -e "${BOLD}  Kubernetes HA Cluster 배포 메뉴${RESET}"
  echo -e "${BOLD}=================================================${RESET}"
  echo ""
  echo -e "  ${CYAN}1${RESET}) step-1-haproxy.sh       HAProxy 설치       (${HAPROXY_IP})"
  echo -e "  ${CYAN}2${RESET}) step-2-cp-primary.sh    CP Primary 초기화  (${CP_01_IP})"
  echo -e "  ${CYAN}3${RESET}) step-3-cp-join.sh       CP Join            (${cp_join_label})"
  echo -e "  ${CYAN}4${RESET}) step-4-worker-join.sh   Worker Join        (${worker_label})"
  echo -e "  ${CYAN}5${RESET}) step-5-helm.sh          Helm 컴포넌트 설치  (${CP_01_IP})"
  echo -e "  ${CYAN}a${RESET}) 전체 실행               1 → 2 → 3 → 4 → 5"
  echo -e "  ${CYAN}q${RESET}) 종료"
  echo ""
  echo -n "  Step 번호 입력 (예: 1 / 2,3 / a): "
}

interactive_menu() {
  while true; do
    print_menu
    read -r INPUT
    echo ""

    case "${INPUT}" in
      q|Q)
        log_info "종료합니다."
        exit 0
        ;;
      a|A)
        run_steps "1,2,3,4,5"
        print_summary
        break
        ;;
      *)
        run_steps "${INPUT}"
        echo ""
        echo -n "  계속 진행하시겠습니까? [y/N]: "
        read -r CONT
        [[ "${CONT}" != "y" && "${CONT}" != "Y" ]] && break
        ;;
    esac
  done
}

# ============================================================
# 인수 파싱
# ============================================================
case "${1:-}" in
  --all)
    run_steps "1,2,3,4,5"
    print_summary
    ;;
  --step)
    if [[ -z "${2:-}" ]]; then
      log_error "--step 뒤에 번호를 입력하세요. (예: --step 1,3)"
      exit 1
    fi
    run_steps "$2"
    ;;
  "")
    interactive_menu
    ;;
  *)
    echo "사용법:"
    echo "  bash deploy.sh              # 대화형 메뉴"
    echo "  bash deploy.sh --step 1     # Step 1 만 실행"
    echo "  bash deploy.sh --step 1,3,5 # Step 1, 3, 5 실행"
    echo "  bash deploy.sh --all        # 전체 실행"
    exit 1
    ;;
esac
