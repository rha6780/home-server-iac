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
# ============================

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== HAProxy 노드 설정 시작 ==="
log "    HAProxy : ${HAPROXY_VERSION}"
echo ""

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

sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 4096
    daemon

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

# -----------
# 3. HAProxy 활성화 및 시작
# -----------
log "[3/3] HAProxy 서비스 시작..."
sudo systemctl enable haproxy
sudo systemctl restart haproxy

echo ""
log "=== HAProxy 설치 완료 ==="
echo ""
echo "  HAProxy 버전  : ${INSTALLED_VER}"
echo "  LB 엔드포인트 : $(hostname -I | awk '{print $1}'):${LB_FRONTEND_PORT}"
echo "  Stats 페이지  : http://$(hostname -I | awk '{print $1}'):${STATS_PORT}/stats"
echo ""
sudo systemctl status haproxy --no-pager -l
