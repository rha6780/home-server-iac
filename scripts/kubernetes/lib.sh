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
  log_info ".env 로드: ${env_file}"
}

# ============================================================
# SSH / SCP 헬퍼
# ============================================================
_ssh() {
  local host="$1"; shift
  ssh -i "${SSH_KEY}" ${SSH_OPTS} "${SSH_USER}@${host}" "$@"
}

scp_file() {
  local src="$1" host="$2" dest="$3"
  log_info "  SCP: $(basename "${src}") → ${SSH_USER}@${host}:${dest}"
  scp -i "${SSH_KEY}" ${SSH_OPTS} "${src}" "${SSH_USER}@${host}:${dest}" \
    >> "$LOG_FILE" 2>&1
}

scp_dir() {
  local src="$1" host="$2" dest="$3"
  log_info "  SCP DIR: $(basename "${src}")/ → ${SSH_USER}@${host}:${dest}"
  scp -i "${SSH_KEY}" ${SSH_OPTS} -r "${src}" "${SSH_USER}@${host}:${dest}" \
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
  log_info "  TOKEN    : ${JOIN_TOKEN}"
  log_info "  CA_HASH  : ${JOIN_CA_HASH}"
  log_info "  CERT_KEY : ${JOIN_CERT_KEY}"
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
    -e "s|^K8S_MINOR=.*|K8S_MINOR=\"${K8S_MINOR}\"|" \
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
    -e "s|^K8S_MINOR=.*|K8S_MINOR=\"${K8S_MINOR}\"|" \
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
