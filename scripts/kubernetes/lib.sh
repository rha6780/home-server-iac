#!/bin/bash
# ============================================================
# lib.sh - 공통 유틸리티 함수
# 각 step 스크립트에서 source 하여 사용
# ============================================================

# ============================================================
# OS 호환 sed -i (macOS BSD sed vs GNU sed)
# macOS: sed -i '' -e '...'  /  Linux: sed -i -e '...'
# ============================================================
_sed_i() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# ============================================================
# 색상 / 로그
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# LOG_FILE 이 없으면 기본값 설정
LOG_FILE="${LOG_FILE:-/tmp/k8s-deploy.log}"
LOCK_DIR="${LOCK_DIR:-/tmp/k8s-deploy.lock}"

log_info()    { local msg="[$(date '+%H:%M:%S')] [INFO]  $*"; echo -e "${BLUE}${msg}${RESET}";   echo "${msg}" >> "$LOG_FILE"; }
log_success() { local msg="[$(date '+%H:%M:%S')] [OK]    $*"; echo -e "${GREEN}${msg}${RESET}";  echo "${msg}" >> "$LOG_FILE"; }
log_warn()    { local msg="[$(date '+%H:%M:%S')] [WARN]  $*"; echo -e "${YELLOW}${msg}${RESET}"; echo "${msg}" >> "$LOG_FILE"; }
log_error()   { local msg="[$(date '+%H:%M:%S')] [ERROR] $*"; echo -e "${RED}${msg}${RESET}";    echo "${msg}" >> "$LOG_FILE"; }
log_step()    {
  local msg="[$(date '+%H:%M:%S')] ▶ $*"
  echo -e "\n${BOLD}${CYAN}${msg}${RESET}"
  echo "${msg}" >> "$LOG_FILE"
}

# ============================================================
# .env 로드
# ============================================================
load_env() {
  local env_file="${1:-${SCRIPT_DIR}/.env}"
  if [[ ! -f "${env_file}" ]]; then
    log_error ".env 파일이 없습니다: ${env_file}"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "${env_file}"
  K8S_MINOR="${K8S_VERSION%.*}"
  normalize_ssh_opts
  log_info ".env 로드: ${env_file}"
}

# ============================================================
# SSH / SCP 헬퍼
# ============================================================
normalize_ssh_opts() {
  SSH_USER="${SSH_USER:-ubuntu}"
  SSH_OPTS="${SSH_OPTS:-}"
  SSH_KEY_PATH="${SSH_KEY/#\~/$HOME}"

  case " ${SSH_OPTS} " in
    *" BatchMode="*) ;;
    *) SSH_OPTS="-o BatchMode=yes ${SSH_OPTS}" ;;
  esac

  case " ${SSH_OPTS} " in
    *" ConnectTimeout="*) ;;
    *) SSH_OPTS="-o ConnectTimeout=10 ${SSH_OPTS}" ;;
  esac

  case " ${SSH_OPTS} " in
    *" StrictHostKeyChecking="*) ;;
    *) SSH_OPTS="-o StrictHostKeyChecking=accept-new ${SSH_OPTS}" ;;
  esac
}

mask_secret() {
  local value="${1:-}"
  local len="${#value}"
  if [[ -z "${value}" ]]; then
    echo ""
  elif (( len <= 8 )); then
    echo "********"
  else
    echo "${value:0:4}...${value: -4}"
  fi
}

acquire_deploy_lock() {
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    echo "$$" > "${LOCK_DIR}/pid"
    trap 'release_deploy_lock' EXIT INT TERM
    log_info "실행 lock 획득: ${LOCK_DIR}"
    return 0
  fi

  local owner="unknown"
  [[ -f "${LOCK_DIR}/pid" ]] && owner=$(cat "${LOCK_DIR}/pid" 2>/dev/null || echo "unknown")
  log_error "다른 Kubernetes 배포가 실행 중입니다. lock=${LOCK_DIR}, pid=${owner}"
  log_error "실행 중인 프로세스가 없다면 수동으로 lock 디렉터리를 삭제하세요: ${LOCK_DIR}"
  return 1
}

release_deploy_lock() {
  if [[ -d "${LOCK_DIR}" && "$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "${LOCK_DIR}"
  fi
}

_ssh() {
  local host="$1"; shift
  ssh -i "${SSH_KEY_PATH}" ${SSH_OPTS} "${SSH_USER}@${host}" "$@"
}

scp_file() {
  local src="$1" host="$2" dest="$3"
  log_info "  SCP: $(basename "${src}") → ${SSH_USER}@${host}:${dest}"
  scp -i "${SSH_KEY_PATH}" ${SSH_OPTS} "${src}" "${SSH_USER}@${host}:${dest}" \
    >> "$LOG_FILE" 2>&1
}

scp_dir() {
  local src="$1" host="$2" dest="$3"
  log_info "  SCP DIR: $(basename "${src}")/ → ${SSH_USER}@${host}:${dest}"
  scp -i "${SSH_KEY_PATH}" ${SSH_OPTS} -r "${src}" "${SSH_USER}@${host}:${dest}" \
    >> "$LOG_FILE" 2>&1
}

remote_exec() {
  local host="$1" desc="$2" cmd="$3"
  log_info "  실행 [${host}]: ${desc}"
  _ssh "${host}" "${cmd}" 2>&1 | tee -a "$LOG_FILE" | sed 's/^/    | /'
  local exit_code="${PIPESTATUS[0]}"
  if [[ $exit_code -ne 0 ]]; then
    log_error "  실패 [${host}]: exit ${exit_code}"
    return "${exit_code}"
  fi
}

check_ssh() {
  local host="$1"
  log_info "  SSH 연결 확인: ${host}"
  if ! _ssh "${host}" "exit" &>/dev/null; then
    log_error "SSH 접속 실패: ${host} (key: ${SSH_KEY}, user: ${SSH_USER})"
    return 1
  fi
  log_success "  SSH OK: ${host}"
}

preflight_node() {
  local host="$1" role="$2" min_cpu="$3" min_mem_mb="$4"
  log_info "  preflight [${role}] ${host}"

  local remote_cmd
  remote_cmd=$(cat <<EOF
set -e
sudo -n true
cpu=\$(nproc)
mem_mb=\$(awk '/MemTotal/ {print int(\$2/1024)}' /proc/meminfo)
hostname=\$(hostname)
if [ "\$cpu" -lt "${min_cpu}" ]; then
  echo "[ERROR] CPU 부족: \$cpu core < ${min_cpu} core"
  exit 10
fi
if [ "\$mem_mb" -lt "${min_mem_mb}" ]; then
  echo "[ERROR] Memory 부족: \${mem_mb}MB < ${min_mem_mb}MB"
  exit 11
fi
if swapon --show | grep -q .; then
  echo "[WARN] Swap 활성화됨. 설치 단계에서 비활성화합니다."
fi
if ! ip route get 1.1.1.1 >/dev/null 2>&1; then
  echo "[ERROR] 기본 네트워크 라우팅 확인 실패"
  exit 12
fi
if ! sudo modprobe br_netfilter >/dev/null 2>&1; then
  echo "[WARN] br_netfilter modprobe 실패. 설치 단계에서 다시 시도합니다."
fi
echo "[OK] hostname=\${hostname} cpu=\${cpu} mem_mb=\${mem_mb}"
EOF
)

  if ! _ssh "${host}" "${remote_cmd}" 2>&1 | tee -a "$LOG_FILE" | sed 's/^/    | /'; then
    log_error "  preflight 실패 [${role}] ${host}"
    return 1
  fi
}

run_preflight() {
  log_step "Preflight. Kubernetes 노드 사전 점검"

  local required_vars=(
    SSH_KEY HAPROXY_IP CP_MASTER_IP CONTROL_PLANE_ENDPOINT
    CLUSTER_NAME POD_SUBNET SERVICE_SUBNET K8S_VERSION
  )
  local var_name
  for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
      log_error "필수 환경변수가 비어 있습니다: ${var_name}"
      return 1
    fi
  done

  if [[ ! -r "${SSH_KEY_PATH}" ]]; then
    log_error "SSH key 파일을 읽을 수 없습니다: ${SSH_KEY}"
    return 1
  fi

  preflight_node "${HAPROXY_IP}" "haproxy" 1 512
  preflight_node "${CP_MASTER_IP}" "control-plane-primary" 2 1700

  local ip
  for ip in "${CP_JOIN_IPS[@]:-}"; do
    [[ -n "${ip}" ]] && preflight_node "${ip}" "control-plane-join" 2 1700
  done
  for ip in "${WORKER_IPS[@]:-}"; do
    [[ -n "${ip}" ]] && preflight_node "${ip}" "worker" 1 1024
  done

  log_success "Preflight 완료"
}

# ============================================================
# join 토큰 수집 (cp-master 에서)
# 결과를 전역 변수에 저장: JOIN_TOKEN, JOIN_CA_HASH, JOIN_CERT_KEY
# ============================================================
fetch_join_info() {
  log_info "join 토큰 수집 중 (cp-master: ${CP_MASTER_IP})..."

  local join_cmd
  join_cmd=$(_ssh "${CP_MASTER_IP}" \
    "sudo kubeadm token create --print-join-command --ttl 2h 2>/dev/null")

  # macOS BSD grep은 -P 미지원 → Python으로 파싱
  JOIN_TOKEN=$(echo "${join_cmd}" | python3 -c "
import sys, re
m = re.search(r'--token (\S+)', sys.stdin.read())
print(m.group(1) if m else '')
")
  JOIN_CA_HASH=$(echo "${join_cmd}" | python3 -c "
import sys, re
m = re.search(r'--discovery-token-ca-cert-hash sha256:(\S+)', sys.stdin.read())
print(m.group(1) if m else '')
")

  local cert_out
  cert_out=$(_ssh "${CP_MASTER_IP}" \
    "sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null")
  JOIN_CERT_KEY=$(echo "${cert_out}" | tail -1)

  if [[ -z "${JOIN_TOKEN:-}" || -z "${JOIN_CA_HASH:-}" || -z "${JOIN_CERT_KEY:-}" ]]; then
    log_error "join 토큰 수집 실패 — cp-master 이 정상 실행 중인지 확인하세요."
    return 1
  fi

  log_success "토큰 수집 완료"
  log_info "  TOKEN    : $(mask_secret "${JOIN_TOKEN}")"
  log_info "  CA_HASH  : $(mask_secret "${JOIN_CA_HASH}")"
  log_info "  CERT_KEY : $(mask_secret "${JOIN_CERT_KEY}")"
}

# ============================================================
# .env 값을 스크립트에 주입 (sed 치환)
# ============================================================

# setup-master.sh 에 환경변수 주입 후 임시파일 경로 반환
inject_master() {
  local src="$1" mode="$2" node_ip="$3"
  local tmp
  tmp=$(mktemp /tmp/setup-master-XXXX.sh)
  cp "${src}" "${tmp}"

  _sed_i \
    -e "s|^MODE=.*|MODE=\"${mode}\"|" \
    -e "s|^THIS_NODE_IP=.*|THIS_NODE_IP=\"${node_ip}\"|" \
    -e "s|^CLUSTER_NAME=.*|CLUSTER_NAME=\"${CLUSTER_NAME}\"|" \
    -e "s|^CONTROL_PLANE_ENDPOINT=.*|CONTROL_PLANE_ENDPOINT=\"${CONTROL_PLANE_ENDPOINT}\"|" \
    -e "s|^POD_SUBNET=.*|POD_SUBNET=\"${POD_SUBNET}\"|" \
    -e "s|^SERVICE_SUBNET=.*|SERVICE_SUBNET=\"${SERVICE_SUBNET}\"|" \
    -e "s|^CONTAINERD_VERSION=.*|CONTAINERD_VERSION=\"${CONTAINERD_VERSION}\"|" \
    -e "s|^K8S_VERSION=.*|K8S_VERSION=\"${K8S_VERSION}\"|" \
    -e "s|^K8S_MINOR=.*|K8S_MINOR=\"${K8S_VERSION%.*}\"|" \
    -e "s|^HELM_VERSION=.*|HELM_VERSION=\"${HELM_VERSION}\"|" \
    -e "s|^IS_ORBSTACK=.*|IS_ORBSTACK=\"${IS_ORBSTACK:-false}\"|" \
    "${tmp}"

  # CERT_SANS 배열 교체
  # CP_JOIN_IPS 배열을 공백 구분 문자열로 전달
  local join_ips_str="${CP_JOIN_IPS[*]:-}"

  python3 - "${tmp}" "${CONTROL_PLANE_ENDPOINT%%:*}" "${HAPROXY_IP}" \
      "${CP_MASTER_IP}" "${join_ips_str}" <<'PYEOF'
import sys, re

path    = sys.argv[1]
ep      = sys.argv[2]  # endpoint hostname
lb      = sys.argv[3]  # haproxy ip
cp01    = sys.argv[4]  # cp-master
joins   = sys.argv[5].split() if sys.argv[5] else []  # CP_JOIN_IPS

sans = [s for s in [ep, lb, cp01] + joins if s]
block = "CERT_SANS=(\n" + "".join(f'  "{s}"\n' for s in sans) + ")"
content = re.sub(r'CERT_SANS=\(.*?\)', block, open(path).read(), flags=re.DOTALL)
open(path, 'w').write(content)
PYEOF

  echo "${tmp}"
}

# setup-master.sh join 모드용 추가 주입
inject_master_join() {
  local src="$1" node_ip="$2" token="$3" ca_hash="$4" cert_key="$5"
  local tmp
  tmp=$(inject_master "${src}" "join" "${node_ip}")
  _sed_i \
    -e "s|^JOIN_TOKEN=.*|JOIN_TOKEN=\"${token}\"|" \
    -e "s|^JOIN_CA_CERT_HASH=.*|JOIN_CA_CERT_HASH=\"${ca_hash}\"|" \
    -e "s|^JOIN_CERTIFICATE_KEY=.*|JOIN_CERTIFICATE_KEY=\"${cert_key}\"|" \
    "${tmp}"
  echo "${tmp}"
}

# setup-worker.sh 에 환경변수 주입
inject_worker() {
  local src="$1" token="$2" ca_hash="$3"
  local tmp
  tmp=$(mktemp /tmp/setup-worker-XXXX.sh)
  cp "${src}" "${tmp}"
  _sed_i \
    -e "s|^CONTROL_PLANE_ENDPOINT=.*|CONTROL_PLANE_ENDPOINT=\"${CONTROL_PLANE_ENDPOINT}\"|" \
    -e "s|^JOIN_TOKEN=.*|JOIN_TOKEN=\"${token}\"|" \
    -e "s|^JOIN_CA_CERT_HASH=.*|JOIN_CA_CERT_HASH=\"${ca_hash}\"|" \
    -e "s|^CONTAINERD_VERSION=.*|CONTAINERD_VERSION=\"${CONTAINERD_VERSION}\"|" \
    -e "s|^K8S_VERSION=.*|K8S_VERSION=\"${K8S_VERSION}\"|" \
    -e "s|^K8S_MINOR=.*|K8S_MINOR=\"${K8S_VERSION%.*}\"|" \
    -e "s|^IS_ORBSTACK=.*|IS_ORBSTACK=\"${IS_ORBSTACK:-false}\"|" \
    "${tmp}"
  echo "${tmp}"
}

# setup-haproxy.sh 에 환경변수 주입
inject_haproxy() {
  local src="$1"
  local tmp
  tmp=$(mktemp /tmp/setup-haproxy-XXXX.sh)
  cp "${src}" "${tmp}"

  # CP_MASTER + CP_JOIN_IPS 를 공백구분 문자열로 합산
  local all_ips="${CP_MASTER_IP}"
  for ip in "${CP_JOIN_IPS[@]:-}"; do
    [[ -n "${ip}" ]] && all_ips+=" ${ip}"
  done

  _sed_i \
    -e "s|^CP_ALL_IPS=.*|CP_ALL_IPS=\"${all_ips}\"|" \
    -e "s|^LB_FRONTEND_PORT=.*|LB_FRONTEND_PORT=${LB_FRONTEND_PORT}|" \
    -e "s|^K8S_API_PORT=.*|K8S_API_PORT=${K8S_API_PORT}|" \
    -e "s|^STATS_PORT=.*|STATS_PORT=${STATS_PORT}|" \
    -e "s|^STATS_USER=.*|STATS_USER=\"${STATS_USER}\"|" \
    -e "s|^STATS_PASS=.*|STATS_PASS=\"${STATS_PASS}\"|" \
    -e "s|^HAPROXY_VERSION=.*|HAPROXY_VERSION=\"${HAPROXY_VERSION}\"|" \
    "${tmp}"
  echo "${tmp}"
}

# 05.post-install-helm.sh 에 환경변수 주입
inject_helm() {
  local src="$1"
  local tmp
  tmp=$(mktemp /tmp/post-install-helm-XXXX.sh)
  cp "${src}" "${tmp}"
  _sed_i \
    -e "s|^CALICO_CHART_VERSION=.*|CALICO_CHART_VERSION=\"${CALICO_CHART_VERSION}\"|" \
    -e "s|^METALLB_CHART_VERSION=.*|METALLB_CHART_VERSION=\"${METALLB_CHART_VERSION}\"|" \
    -e "s|^GATEWAY_API_VERSION=.*|GATEWAY_API_VERSION=\"${GATEWAY_API_VERSION}\"|" \
    -e "s|^NGF_CHART_VERSION=.*|NGF_CHART_VERSION=\"${NGF_CHART_VERSION}\"|" \
    "${tmp}"
  echo "${tmp}"
}

# MetalLB ip-address-pool.yaml 에 IP 범위 주입
inject_ip_pool() {
  local src="$1"
  local tmp
  tmp=$(mktemp /tmp/ip-address-pool-XXXX.yaml)
  cp "${src}" "${tmp}"
  _sed_i \
    "s|192\.168\.[0-9]*\.[0-9]*-192\.168\.[0-9]*\.[0-9]*|${METALLB_IP_RANGE}|g" \
    "${tmp}"
  echo "${tmp}"
}
