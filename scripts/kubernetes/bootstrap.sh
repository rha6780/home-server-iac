#!/bin/bash
# ============================================================
# bootstrap.sh - Kubernetes HA Cluster 전체 배포 진입점
# 로컬 PC에서 실행
#
# 사용법:
#   bash bootstrap.sh                # VM 생성 + k8s 설치 전체
#   bash bootstrap.sh --skip-terraform  # VM 이미 있을 때 k8s 설치만
#   bash bootstrap.sh --destroy      # k8s VM 전체 삭제
#   bash bootstrap.sh --destroy --recreate  # k8s VM 삭제 후 재생성 + 설치
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
DESTROY=false
RECREATE=false
for arg in "$@"; do
  case "${arg}" in
    --skip-terraform) SKIP_TERRAFORM=true ;;
    --destroy)        DESTROY=true ;;
    --recreate)       RECREATE=true ;;
    *)
      echo "사용법:"
      echo "  bash bootstrap.sh                        # VM 생성 + k8s 설치 전체"
      echo "  bash bootstrap.sh --skip-terraform       # VM 이미 있을 때 k8s 설치만"
      echo "  bash bootstrap.sh --destroy              # k8s VM 전체 삭제"
      echo "  bash bootstrap.sh --destroy --recreate   # k8s VM 삭제 후 재생성 + 설치"
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

  local haproxy_ip cp_master_ip
  haproxy_ip=$(echo "${hint}" | jq -r '.haproxy_ip')
  cp_master_ip=$(echo "${hint}"   | jq -r '.cp_master_ip')

  # CP join IPs (가변 배열, bash 3.2 호환)
  local cp_join_ips_arr=()
  while IFS= read -r ip; do
    [[ -n "${ip}" ]] && cp_join_ips_arr+=("${ip}")
  done < <(echo "${hint}" | jq -r '.cp_join_ips[] | select(. != "null")')

  # Worker IPs (가변 배열, bash 3.2 호환)
  local worker_ips_arr=()
  while IFS= read -r ip; do
    [[ -n "${ip}" ]] && worker_ips_arr+=("${ip}")
  done < <(echo "${hint}" | jq -r '.worker_ips[]')

  if [[ ! -f "${SCRIPT_DIR}/.env.example" ]]; then
    log_error ".env.example 이 없습니다: ${SCRIPT_DIR}/.env.example"
    exit 1
  fi

  cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"

  # CP_JOIN_IPS 배열 문자열
  local cp_join_block="CP_JOIN_IPS=("
  for ip in "${cp_join_ips_arr[@]}"; do
    cp_join_block+=$'\n'"  \"${ip}\""
  done
  cp_join_block+=$'\n'")"

  # WORKER_IPS 배열 문자열
  local worker_block="WORKER_IPS=("
  for ip in "${worker_ips_arr[@]}"; do
    worker_block+=$'\n'"  \"${ip}\""
  done
  worker_block+=$'\n'")"

  # Python으로 IP 관련 블록 일괄 치환
  # CP_NNN_IP 변수들 + CP_JOIN_IPS 배열, WORKER_IPS 배열을 통째로 재작성
  python3 - "${ENV_FILE}" "${haproxy_ip}" "${cp_master_ip}" "${cp_join_block}" "${worker_block}" <<'PYEOF'
import sys, re

env_path      = sys.argv[1]
haproxy_ip    = sys.argv[2]
cp_master_ip      = sys.argv[3]
cp_join_block = sys.argv[4]
worker_block  = sys.argv[5]

with open(env_path) as f:
    content = f.read()

# HAPROXY_IP
content = re.sub(r'^HAPROXY_IP=.*', f'HAPROXY_IP="{haproxy_ip}"', content, flags=re.MULTILINE)

# CP_MASTER_IP 한 줄 치환
content = re.sub(r'^CP_MASTER_IP=.*', f'CP_MASTER_IP="{cp_master_ip}"', content, flags=re.MULTILINE)

# CP_NNN_IP 변수 줄 제거 (CP_02_IP, CP_03_IP 등 — CP_JOIN_IPS로 통합)
content = re.sub(r'^CP_0[2-9]_IP=.*\n?', '', content, flags=re.MULTILINE)

# CP_JOIN_IPS 블록 치환
content = re.sub(r'CP_JOIN_IPS=\([^)]*\)', cp_join_block, content, flags=re.DOTALL)

# WORKER_IPS 블록 치환
content = re.sub(r'WORKER_IPS=\([^)]*\)', worker_block, content, flags=re.DOTALL)

with open(env_path, 'w') as f:
    f.write(content)
PYEOF

  log_success "Step B 완료 — .env 생성: ${ENV_FILE}"
  log_info "  HAProxy    : ${haproxy_ip}"
  log_info "  CP Primary : ${cp_master_ip}"
  log_info "  CP Join    : ${cp_join_ips_arr[*]:-없음}"
  log_info "  Workers    : ${worker_ips_arr[*]}"
}

# ============================================================
# Step C. VM SSH 부팅 대기
# ============================================================
wait_for_vms() {
  log_step "Step C. VM SSH 부팅 대기"
  source "${ENV_FILE}"
  K8S_MINOR="${K8S_VERSION%.*}"
  normalize_ssh_opts

  local all_ips=("${HAPROXY_IP}" "${CP_MASTER_IP}")
  for ip in "${CP_JOIN_IPS[@]:-}"; do [[ -n "${ip}" ]] && all_ips+=("${ip}"); done
  for ip in "${WORKER_IPS[@]:-}";  do [[ -n "${ip}" ]] && all_ips+=("${ip}"); done

  local max_wait=300 interval=10

  for ip in "${all_ips[@]}"; do
    log_info "  대기 중: ${ip}"
    local elapsed=0
    until ssh -i "${SSH_KEY_PATH}" ${SSH_OPTS} -o ConnectTimeout=5 \
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
# Step D. VM의 실제 containerd 버전을 .env에 반영
# ============================================================
sync_containerd_version() {
  log_step "Step D. containerd 버전 동기화"
  source "${ENV_FILE}"
  K8S_MINOR="${K8S_VERSION%.*}"
  normalize_ssh_opts

  local installed_ver
  installed_ver=$(ssh -i "${SSH_KEY_PATH}" ${SSH_OPTS} "${SSH_USER}@${CP_MASTER_IP}" \
    "dpkg-query -W -f='\${Version}' containerd.io 2>/dev/null || echo ''" )

  if [[ -z "${installed_ver}" ]]; then
    log_warn "  containerd.io 미설치 — .env 버전 유지: ${CONTAINERD_VERSION}"
    return
  fi

  if [[ "${installed_ver}" == "${CONTAINERD_VERSION}" ]]; then
    log_info "  containerd 버전 일치: ${installed_ver}"
    return
  fi

  log_info "  VM 설치 버전: ${installed_ver} / .env 버전: ${CONTAINERD_VERSION} → 동기화"
  _sed_i "s|^CONTAINERD_VERSION=.*|CONTAINERD_VERSION=\"${installed_ver}\"|" "${ENV_FILE}"
  log_success "Step D 완료 — CONTAINERD_VERSION=${installed_ver}"
}

# ============================================================
# Step E. k8s 설치 (deploy.sh --all)
# ============================================================
run_deploy() {
  log_step "Step E. Kubernetes 설치"
  SKIP_DEPLOY_LOCK=true bash "${SCRIPT_DIR}/deploy.sh" --all
  log_success "Step E 완료 — Kubernetes 설치"
}

# ============================================================
# k8s VM 삭제
# ============================================================
destroy_vms() {
  log_step "k8s VM 삭제"

  if [[ ! -f "${TF_DIR}/k8s.auto.tfvars" ]]; then
    log_error "tfvars 파일이 없습니다: ${TF_DIR}/k8s.auto.tfvars"
    exit 1
  fi

  # k8s_vms 변수에서 VM 이름 목록 추출
  local vm_names=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && vm_names+=("${name}")
  done < <(grep -E '^\s+vm-' "${TF_DIR}/k8s.auto.tfvars" | sed 's/[[:space:]={}]//g')

  if [[ ${#vm_names[@]} -eq 0 ]]; then
    log_error "k8s.auto.tfvars 에서 VM 목록을 찾을 수 없습니다."
    exit 1
  fi

  local targets=()
  for name in "${vm_names[@]}"; do
    targets+=("-target=module.k8s_vms[\"${name}\"]")
  done

  log_info "삭제 대상: ${vm_names[*]}"
  terraform -chdir="${TF_DIR}" destroy "${targets[@]}" -auto-approve >> "${LOG_FILE}" 2>&1

  log_success "k8s VM 삭제 완료"
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
acquire_deploy_lock

check_requirements

if [[ "${DESTROY}" == "true" ]]; then
  destroy_vms
  if [[ "${RECREATE}" == "false" ]]; then
    exit 0
  fi
  run_terraform
  generate_env
  wait_for_vms
  sync_containerd_version
  run_deploy
  exit 0
fi

if [[ "${SKIP_TERRAFORM}" == "false" ]]; then
  run_terraform
  generate_env
fi

wait_for_vms
sync_containerd_version
run_deploy
