#!/bin/bash
# ============================================================
# bootstrap.sh - Kubernetes HA Cluster 전체 배포 진입점
# 로컬 PC에서 실행
#
# 사용법:
#   bash bootstrap.sh                # VM 생성 + k8s 설치 전체
#   bash bootstrap.sh --skip-terraform  # VM 이미 있을 때 k8s 설치만
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
ENV_FILE="${SCRIPT_DIR}/.env"

export LOG_FILE="${SCRIPT_DIR}/deploy_$(date '+%Y%m%d_%H%M%S').log"

source "${SCRIPT_DIR}/lib.sh"

# ============================================================
# 인수 파싱
# ============================================================
SKIP_TERRAFORM=false
for arg in "$@"; do
  case "${arg}" in
    --skip-terraform) SKIP_TERRAFORM=true ;;
    *)
      echo "사용법:"
      echo "  bash bootstrap.sh                  # VM 생성 + k8s 설치 전체"
      echo "  bash bootstrap.sh --skip-terraform # VM 이미 있을 때 k8s 설치만"
      exit 1
      ;;
  esac
done

# ============================================================
# 사전 요구사항 확인 + 자동 설치
# ============================================================

# brew 패키지명 매핑 (명령어 이름과 다를 경우)
_brew_pkg() {
  case "$1" in
    terraform) echo "hashicorp/tap/terraform" ;;
    *)         echo "$1" ;;
  esac
}

_ensure_homebrew() {
  if command -v brew &>/dev/null; then return; fi
  log_info "Homebrew가 없습니다. 설치합니다..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    >> "${LOG_FILE}" 2>&1
  # Apple Silicon / Intel 경로 모두 대응
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  log_success "Homebrew 설치 완료"
}

_install_if_missing() {
  local cmd="$1"
  if command -v "${cmd}" &>/dev/null; then return; fi

  if [[ "$(uname)" != "Darwin" ]]; then
    log_error "${cmd} 가 없습니다. 수동으로 설치해 주세요."
    return 1
  fi

  _ensure_homebrew
  local pkg
  pkg=$(_brew_pkg "${cmd}")
  log_info "  brew install ${pkg}"
  brew install "${pkg}" >> "${LOG_FILE}" 2>&1
  log_success "  ${cmd} 설치 완료"
}

check_requirements() {
  log_step "사전 요구사항 확인"

  # ssh / scp 는 macOS 기본 탑재 — 없으면 OS 문제이므로 설치 시도하지 않음
  for cmd in ssh scp; do
    if ! command -v "${cmd}" &>/dev/null; then
      log_error "${cmd} 가 없습니다. (macOS 기본 탑재 도구 — OS 상태를 확인하세요)"
      exit 1
    fi
  done

  # 자동 설치 대상
  for cmd in python3 jq terraform; do
    _install_if_missing "${cmd}"
  done

  log_success "요구사항 확인 완료"
}

# ============================================================
# Step A. Terraform apply
# ============================================================
run_terraform() {
  log_step "Step A. Terraform — VM 생성"

  if [[ ! -f "${TF_DIR}/k8s.auto.tfvars" ]]; then
    log_error "tfvars 파일이 없습니다: ${TF_DIR}/k8s.auto.tfvars"
    log_error "  cp ${TF_DIR}/k8s.auto.tfvars.example ${TF_DIR}/k8s.auto.tfvars 후 편집하세요."
    exit 1
  fi

  log_info "terraform init"
  terraform -chdir="${TF_DIR}" init -input=false >> "${LOG_FILE}" 2>&1

  log_info "terraform apply"
  terraform -chdir="${TF_DIR}" apply -auto-approve -input=false >> "${LOG_FILE}" 2>&1

  log_success "Step A 완료 — VM 생성"
}

# ============================================================
# Step B. terraform output → .env 자동 생성
# ============================================================
generate_env() {
  log_step "Step B. terraform output → .env 생성"

  local hint
  hint=$(terraform -chdir="${TF_DIR}" output -json k8s_shell_env_hint)

  local haproxy_ip cp_01_ip cp_02_ip cp_03_ip
  haproxy_ip=$(echo "${hint}" | jq -r '.haproxy_ip')
  cp_01_ip=$(echo "${hint}"   | jq -r '.cp_01_ip')
  cp_02_ip=$(echo "${hint}"   | jq -r '.cp_join_ips[0]')
  cp_03_ip=$(echo "${hint}"   | jq -r '.cp_join_ips[1]')

  # worker IPs (배열 크기 동적 처리)
  local worker_ips_arr
  mapfile -t worker_ips_arr < <(echo "${hint}" | jq -r '.worker_ips[]')

  # .env.example 을 베이스로 IP만 덮어쓰기
  if [[ ! -f "${SCRIPT_DIR}/.env.example" ]]; then
    log_error ".env.example 이 없습니다: ${SCRIPT_DIR}/.env.example"
    exit 1
  fi

  cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"

  _sed_i "s|^HAPROXY_IP=.*|HAPROXY_IP=\"${haproxy_ip}\"|" "${ENV_FILE}"
  _sed_i "s|^CP_01_IP=.*|CP_01_IP=\"${cp_01_ip}\"|"       "${ENV_FILE}"
  _sed_i "s|^CP_02_IP=.*|CP_02_IP=\"${cp_02_ip}\"|"       "${ENV_FILE}"
  _sed_i "s|^CP_03_IP=.*|CP_03_IP=\"${cp_03_ip}\"|"       "${ENV_FILE}"

  # WORKER_IPS 배열 재작성
  local worker_block="WORKER_IPS=("
  for ip in "${worker_ips_arr[@]}"; do
    worker_block+=$'\n'"  \"${ip}\""
  done
  worker_block+=$'\n'")"

  # .env 에서 기존 WORKER_IPS 블록 교체 (멀티라인 sed 대신 Python 사용)
  python3 - "${ENV_FILE}" "${worker_block}" <<'PYEOF'
import sys, re

env_path = sys.argv[1]
new_block = sys.argv[2]

with open(env_path) as f:
    content = f.read()

# WORKER_IPS=(\n...\n) 블록 치환
content = re.sub(
    r'WORKER_IPS=\(.*?\)',
    new_block,
    content,
    flags=re.DOTALL
)

with open(env_path, 'w') as f:
    f.write(content)
PYEOF

  log_success "Step B 완료 — .env 생성: ${ENV_FILE}"
  log_info "  HAProxy    : ${haproxy_ip}"
  log_info "  CP Primary : ${cp_01_ip}"
  log_info "  CP Join    : ${cp_02_ip}, ${cp_03_ip}"
  log_info "  Workers    : ${worker_ips_arr[*]}"
}

# ============================================================
# Step C. VM SSH 부팅 대기
# ============================================================
wait_for_vms() {
  log_step "Step C. VM SSH 부팅 대기"
  source "${ENV_FILE}"

  local all_ips=("${HAPROXY_IP}" "${CP_01_IP}")
  for ip in "${CP_JOIN_IPS[@]:-}"; do [[ -n "${ip}" ]] && all_ips+=("${ip}"); done
  for ip in "${WORKER_IPS[@]:-}";  do [[ -n "${ip}" ]] && all_ips+=("${ip}"); done

  local max_wait=300 interval=10

  for ip in "${all_ips[@]}"; do
    log_info "  대기 중: ${ip}"
    local elapsed=0
    until ssh -i "${SSH_KEY}" ${SSH_OPTS} -o ConnectTimeout=5 \
               "${SSH_USER}@${ip}" "exit" &>/dev/null; do
      if (( elapsed >= max_wait )); then
        log_error "SSH 연결 타임아웃 (${max_wait}s): ${ip}"
        exit 1
      fi
      sleep "${interval}"
      elapsed=$(( elapsed + interval ))
    done
    log_success "  접속 확인: ${ip}"
  done

  log_success "Step C 완료 — 전체 VM SSH 응답 확인"
}

# ============================================================
# Step D. k8s 설치 (deploy.sh --all)
# ============================================================
run_deploy() {
  log_step "Step D. Kubernetes 설치"
  bash "${SCRIPT_DIR}/deploy.sh" --all
  log_success "Step D 완료 — Kubernetes 설치"
}

# ============================================================
# 실행
# ============================================================
{
  echo "=================================================="
  echo "  Kubernetes HA Cluster Bootstrap"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "  LOG: ${LOG_FILE}"
  echo "=================================================="
} >> "${LOG_FILE}"

log_info "로그 파일: ${LOG_FILE}"

check_requirements

if [[ "${SKIP_TERRAFORM}" == "false" ]]; then
  run_terraform
  generate_env
fi

wait_for_vms
run_deploy
