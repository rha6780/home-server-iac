#!/bin/bash
# ============================================================
# HAProxy 노드 설치 스크립트
# - HAProxy LB 전용 노드에서 단독으로 실행
# - Kubernetes 설치 없음
#
# 설치 버전
#   HAProxy : 2.8.x (Ubuntu 24.04 LTS 기본 제공 LTS 버전)
# ============================================================

set -euo pipefail

# ============================
# 버전 설정
# ============================
HAPROXY_VERSION="2.8.*"        # apt 패턴 (2.8.x LTS)

# ============================
# [수정 필요] 환경 설정
# ============================
# CP_ALL_IPS: 공백으로 구분된 전체 CP IP 목록 (inject_haproxy 에서 주입)
CP_ALL_IPS="192.168.219.30 192.168.219.31 192.168.219.32"

LB_FRONTEND_PORT=6445          # 외부에서 접속하는 포트
K8S_API_PORT=6443              # 각 Control Plane 의 kube-apiserver 포트

STATS_PORT=8080                # HAProxy stats 페이지 포트
STATS_USER="admin"
STATS_PASS="admin"             # 프로덕션에서는 변경 필요

# true면 6445/8080을 점유한 기존 프로세스 정보를 기록하고 종료합니다.
RELEASE_CONFLICTING_PORTS="true"
# ============================

log() { echo "[$(date '+%H:%M:%S')] $*"; }

fail() {
  echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2
  exit 1
}

print_haproxy_diagnostics() {
  log "HAProxy 진단 정보:"
  echo ""
  echo "---- haproxy config check ----"
  sudo haproxy -c -f /etc/haproxy/haproxy.cfg || true
  echo ""
  echo "---- listening ports ----"
  sudo ss -ltnp 2>/dev/null | grep -E ":(${LB_FRONTEND_PORT}|${STATS_PORT})\\b" || true
  echo ""
  echo "---- systemctl status haproxy ----"
  sudo systemctl status haproxy --no-pager -l || true
  echo ""
  echo "---- journalctl -u haproxy ----"
  sudo journalctl -u haproxy --no-pager -n 80 || true
}

validate_inputs() {
  [[ -n "${CP_ALL_IPS// }" ]] || fail "CP_ALL_IPS가 비어 있습니다."
  [[ "${LB_FRONTEND_PORT}" =~ ^[0-9]+$ ]] || fail "LB_FRONTEND_PORT가 숫자가 아닙니다: ${LB_FRONTEND_PORT}"
  [[ "${K8S_API_PORT}" =~ ^[0-9]+$ ]] || fail "K8S_API_PORT가 숫자가 아닙니다: ${K8S_API_PORT}"
  [[ "${STATS_PORT}" =~ ^[0-9]+$ ]] || fail "STATS_PORT가 숫자가 아닙니다: ${STATS_PORT}"
  [[ "${LB_FRONTEND_PORT}" -ge 1 && "${LB_FRONTEND_PORT}" -le 65535 ]] || fail "LB_FRONTEND_PORT 범위 오류: ${LB_FRONTEND_PORT}"
  [[ "${K8S_API_PORT}" -ge 1 && "${K8S_API_PORT}" -le 65535 ]] || fail "K8S_API_PORT 범위 오류: ${K8S_API_PORT}"
  [[ "${STATS_PORT}" -ge 1 && "${STATS_PORT}" -le 65535 ]] || fail "STATS_PORT 범위 오류: ${STATS_PORT}"

  local ip
  for ip in ${CP_ALL_IPS}; do
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
      || fail "Control Plane IP 형식 오류: ${ip}"
  done

  if [[ "${STATS_USER}${STATS_PASS}" =~ [[:space:]] ]]; then
    fail "STATS_USER/STATS_PASS에는 공백을 사용할 수 없습니다."
  fi
}

warn_port_owner() {
  local port="$1"
  local owner
  owner=$(sudo ss -ltnp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print $0}' || true)
  if [[ -n "${owner}" && "${owner}" != *"haproxy"* ]]; then
    log "  [WARN] 포트 ${port}가 다른 프로세스에서 사용 중일 수 있습니다."
    echo "${owner}"
  fi
}

haproxy_pids_on_port() {
  local port="$1"
  sudo ss -ltnp 2>/dev/null \
    | awk -v p=":${port}" '$4 ~ p"$" && $0 ~ /haproxy/ {print $0}' \
    | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' \
    | sort -u
}

port_owner() {
  local port="$1"
  sudo ss -ltnp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print $0}' || true
}

port_owner_pids() {
  local port="$1"
  sudo ss -ltnp 2>/dev/null \
    | awk -v p=":${port}" '$4 ~ p"$" {print $0}' \
    | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' \
    | sort -u
}

record_port_conflict() {
  local port="$1" report="$2"
  {
    echo "============================================================"
    echo "HAProxy port conflict report"
    echo "time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "host: $(hostname)"
    echo "port: ${port}"
    echo "============================================================"
    echo ""
    echo "---- ss -ltnp ----"
    sudo ss -ltnp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print $0}' || true
    echo ""
    echo "---- process details ----"
    local pid
    for pid in $(port_owner_pids "${port}"); do
      echo ""
      echo "[pid ${pid}]"
      ps -fp "${pid}" || true
      echo ""
      echo "cmdline:"
      tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true
      echo ""
    done
    if command -v docker >/dev/null 2>&1; then
      echo ""
      echo "---- docker ps publishing port ${port} ----"
      docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Ports}}' 2>/dev/null \
        | awk -v p=":${port}->" 'NR==1 || index($0, p) {print $0}' || true
    fi
  } | sudo tee -a "${report}" > /dev/null
}

release_port_owner() {
  local port="$1"
  local owner report pids pid

  owner=$(port_owner "${port}")
  [[ -n "${owner}" ]] || return 0

  report="/var/log/haproxy-port-conflict-$(date '+%Y%m%d_%H%M%S')-${port}.log"
  log "  [WARN] 포트 ${port} 점유 프로세스 발견. 상세 정보 기록: ${report}"
  record_port_conflict "${port}" "${report}"
  echo "${owner}"

  if [[ "${RELEASE_CONFLICTING_PORTS}" != "true" ]]; then
    fail "포트 ${port}가 이미 사용 중입니다. RELEASE_CONFLICTING_PORTS=true 로 설정하면 점유 프로세스를 기록 후 종료합니다."
  fi

  pids=$(port_owner_pids "${port}")
  [[ -n "${pids}" ]] || fail "포트 ${port} 점유 pid를 찾지 못했습니다."

  log "  포트 ${port} 점유 프로세스 종료 시도: ${pids}"
  for pid in ${pids}; do
    sudo kill "${pid}" 2>/dev/null || true
  done
  sleep 2

  pids=$(port_owner_pids "${port}")
  if [[ -n "${pids}" ]]; then
    log "  [WARN] 프로세스가 아직 살아 있습니다. 강제 종료합니다: ${pids}"
    for pid in ${pids}; do
      sudo kill -9 "${pid}" 2>/dev/null || true
    done
    sleep 1
  fi
}

cleanup_existing_haproxy() {
  log "  기존 HAProxy listener 정리..."
  sudo systemctl stop haproxy 2>/dev/null || true
  sudo systemctl reset-failed haproxy 2>/dev/null || true
  sleep 1

  local port pid pids
  for port in "${LB_FRONTEND_PORT}" "${STATS_PORT}"; do
    pids=$(haproxy_pids_on_port "${port}" || true)
    if [[ -n "${pids}" ]]; then
      log "  [WARN] systemd 밖에 남은 HAProxy 프로세스가 포트 ${port}를 사용 중입니다. 종료합니다: ${pids}"
      for pid in ${pids}; do
        sudo kill "${pid}" 2>/dev/null || true
      done
      sleep 1
    fi

    pids=$(haproxy_pids_on_port "${port}" || true)
    if [[ -n "${pids}" ]]; then
      log "  [WARN] HAProxy 프로세스가 아직 남아 있습니다. 강제 종료합니다: ${pids}"
      for pid in ${pids}; do
        sudo kill -9 "${pid}" 2>/dev/null || true
      done
      sleep 1
    fi
  done
}

ensure_ports_available() {
  local port owner
  for port in "${LB_FRONTEND_PORT}" "${STATS_PORT}"; do
    owner=$(port_owner "${port}")
    if [[ -n "${owner}" ]]; then
      release_port_owner "${port}"
      owner=$(port_owner "${port}")
      if [[ -n "${owner}" ]]; then
        echo "${owner}"
        fail "포트 ${port} 점유 프로세스를 종료했지만 포트가 아직 사용 중입니다."
      fi
    fi
  done
}

log "=== HAProxy 노드 설정 시작 ==="
log "    HAProxy : ${HAPROXY_VERSION}"
echo ""

validate_inputs

# -----------
# 1. HAProxy 설치 (이미 설치된 경우 스킵)
# -----------
log "[1/3] HAProxy ${HAPROXY_VERSION} 설치..."
INSTALLED_HAPROXY=$(dpkg-query -W -f='${Version}' haproxy 2>/dev/null || echo "")
if [[ -n "${INSTALLED_HAPROXY}" ]]; then
  log "  [SKIP] HAProxy 이미 설치됨: ${INSTALLED_HAPROXY}"
else
  sudo apt-get update -qq
  sudo apt-get install -y "haproxy=${HAPROXY_VERSION}"
  sudo apt-mark hold haproxy
fi

# 설치된 버전 확인
INSTALLED_VER=$(haproxy -v 2>&1 | head -1)
log "    설치 확인: ${INSTALLED_VER}"

# -----------
# 2. HAProxy 설정 파일 생성
# -----------
log "[2/3] HAProxy 설정 적용..."

TMP_CFG=$(mktemp /tmp/haproxy-k8s-XXXX.cfg)
cat > "${TMP_CFG}" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 4096

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    retries 3
    timeout connect  5s
    timeout client  30s
    timeout server  30s

#--------------------------------------------------------------------
# Frontend: 외부 -> HAProxy (port ${LB_FRONTEND_PORT})
#--------------------------------------------------------------------
frontend k8s-api
    bind *:${LB_FRONTEND_PORT}
    default_backend k8s-api-servers

#--------------------------------------------------------------------
# Backend: HAProxy -> Control Plane Nodes (port ${K8S_API_PORT})
# inter 10s  : 10초마다 health check
# fall 3     : 3번 실패 시 다운 처리
# rise 2     : 2번 성공 시 복구 처리
#--------------------------------------------------------------------
backend k8s-api-servers
    balance roundrobin
    option  tcp-check

$(
  idx=1
  for IP in ${CP_ALL_IPS}; do
    printf "    server cp-%02d %s:%s check inter 10s fall 3 rise 2\n" \
      "${idx}" "${IP}" "${K8S_API_PORT}"
    idx=$((idx + 1))
  done
)

#--------------------------------------------------------------------
# Stats 페이지
#--------------------------------------------------------------------
listen stats
    bind *:${STATS_PORT}
    mode  http
    stats enable
    stats uri  /stats
    stats auth ${STATS_USER}:${STATS_PASS}
EOF

log "  HAProxy 설정 문법 검사..."
if ! haproxy -c -f "${TMP_CFG}"; then
  rm -f "${TMP_CFG}"
  fail "생성된 HAProxy 설정 파일 문법 검사가 실패했습니다."
fi

sudo install -m 0644 "${TMP_CFG}" /etc/haproxy/haproxy.cfg
rm -f "${TMP_CFG}"

# -----------
# 3. HAProxy 활성화 및 시작
# -----------
log "[3/3] HAProxy 서비스 시작..."
cleanup_existing_haproxy
ensure_ports_available
sudo systemctl enable haproxy
if ! sudo systemctl restart haproxy; then
  print_haproxy_diagnostics
  fail "HAProxy 서비스 시작 실패"
fi

echo ""
log "=== HAProxy 설치 완료 ==="
echo ""
echo "  HAProxy 버전  : ${INSTALLED_VER}"
echo "  LB 엔드포인트 : $(hostname -I | awk '{print $1}'):${LB_FRONTEND_PORT}"
echo "  Stats 페이지  : http://$(hostname -I | awk '{print $1}'):${STATS_PORT}/stats"
echo ""
sudo systemctl status haproxy --no-pager -l
