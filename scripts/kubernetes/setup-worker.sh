#!/bin/bash
# ============================================================
# Worker 노드 설치 스크립트
# - 각 Worker 노드에서 단독으로 실행
# ============================================================

set -euo pipefail

# ============================
# 버전 설정
# ============================
CONTAINERD_VERSION="1.7.29-1~ubuntu.24.04~noble"
K8S_VERSION="1.36.2"
K8S_APT_VERSION="${K8S_VERSION}-2.1"
K8S_MINOR="${K8S_VERSION%.*}"

# ============================
# [수정 필요] 환경 설정
# ============================
CONTROL_PLANE_ENDPOINT="api.k8s.your-domain.com:6445"

JOIN_TOKEN=""
JOIN_CA_CERT_HASH=""

# OrbStack/컨테이너 환경 여부 (true: OrbStack 워크어라운드 적용)
IS_ORBSTACK="false"
# ============================

log() { echo "[$(date '+%H:%M:%S')] $*"; }

if [[ -z "$JOIN_TOKEN" || -z "$JOIN_CA_CERT_HASH" ]]; then
  echo "[ERROR] JOIN_TOKEN, JOIN_CA_CERT_HASH 를 설정하세요."
  echo "  Primary CP 에서 확인: sudo kubeadm token create --print-join-command --ttl 24h"
  exit 1
fi

log "=== Worker 노드 설정 시작 ==="
log "    containerd : ${CONTAINERD_VERSION}"
log "    Kubernetes : ${K8S_VERSION}"
log "    IS_ORBSTACK: ${IS_ORBSTACK}"
echo ""

# ============================================================
# STEP 1. 공통 Prerequisites
# ============================================================

log "[1/5] Swap 비활성화..."
if swapon --show | grep -q .; then
  if [[ "$IS_ORBSTACK" == "true" ]]; then
    if sudo swapoff -a 2>/dev/null; then
      log "    Swap 비활성화 완료"
      sudo sed -i '/^[^#].*swap/s/^/# /' /etc/fstab
    else
      log "    [WARN] swapoff 실패 (OrbStack 환경) — kubeadm --ignore-preflight-errors=Swap 으로 진행"
    fi
  else
    sudo swapoff -a
    sudo sed -i '/^[^#].*swap/s/^/# /' /etc/fstab
    log "    Swap 비활성화 완료"
  fi
else
  log "    [SKIP] Swap 이미 비활성화됨"
fi

if [[ "$IS_ORBSTACK" == "true" ]]; then
  log "[2/5] /dev/kmsg 생성 (OrbStack 환경 대응)..."
  if [[ ! -e /dev/kmsg ]]; then
    sudo touch /dev/kmsg && sudo chmod 644 /dev/kmsg
    log "    /dev/kmsg 생성 완료"
  fi
  echo "f /dev/kmsg 0644 root root - -" \
    | sudo tee /etc/tmpfiles.d/kmsg.conf > /dev/null
else
  log "[2/5] /dev/kmsg 확인..."
  log "    [SKIP] 실서버 환경 — /dev/kmsg 생성 불필요"
fi

log "[3/5] 커널 파라미터 설정..."
sudo tee /etc/modules-load.d/containerd.conf > /dev/null <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/kubernetes.conf > /dev/null <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

if [[ "$IS_ORBSTACK" == "true" ]]; then
  sudo sysctl --system 2>&1 | grep -v "Operation not permitted" || true
else
  sudo sysctl --system
fi

log "[4/5] containerd ${CONTAINERD_VERSION} 설치..."
INSTALLED_CTR=$(dpkg-query -W -f='${Version}' containerd.io 2>/dev/null || echo "")
if [[ "${INSTALLED_CTR}" == "${CONTAINERD_VERSION}" ]]; then
  log "    [SKIP] containerd 이미 설치됨: ${INSTALLED_CTR}"
else
  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl gnupg

  sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --batch --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-mark unhold containerd.io 2>/dev/null || true
  sudo apt-get update -qq
  sudo apt-get install -y "containerd.io=${CONTAINERD_VERSION}"
  sudo apt-mark hold containerd.io
fi

# containerd 기본 설정 (공통)
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

if [[ "$IS_ORBSTACK" == "true" ]]; then
  sudo apt-get install -y crun 2>/dev/null || true
  sudo sed -i 's/snapshotter = "overlayfs"/snapshotter = "native"/g' /etc/containerd/config.toml
  sudo sed -i 's/NoPivotRoot = false/NoPivotRoot = true/g' /etc/containerd/config.toml
  sudo sed -i 's|BinaryName = ""|BinaryName = "/usr/local/bin/crun-wrapper"|' /etc/containerd/config.toml

  sudo tee /usr/local/bin/crun-wrapper > /dev/null << 'CRUNWRAPPER'
#!/bin/bash
BUNDLE=""
PREV=""
for ARG in "$@"; do
    if [[ "$PREV" == "--bundle" || "$PREV" == "-b" ]]; then
        BUNDLE="$ARG"
    fi
    PREV="$ARG"
done

if [[ -n "$BUNDLE" && -f "$BUNDLE/config.json" ]]; then
    python3 -c "
import json
with open('$BUNDLE/config.json') as f:
    c = json.load(f)
c.get('process', {}).pop('oomScoreAdj', None)
c.get('linux', {}).pop('oomScoreAdj', None)
caps = c.get('process', {}).get('capabilities', {})
for cap_type in ('bounding', 'effective', 'permitted', 'inheritable'):
    cap_list = caps.get(cap_type, [])
    if 'CAP_MKNOD' not in cap_list:
        cap_list.append('CAP_MKNOD')
    caps[cap_type] = cap_list
if caps:
    c.setdefault('process', {})['capabilities'] = caps
mounts = c.get('mounts', [])
new_mounts = []
for m in mounts:
    if m.get('destination') == '/dev' and m.get('type') == 'tmpfs':
        new_mounts.append({'destination': '/dev', 'type': 'bind', 'source': '/dev', 'options': ['rbind', 'rw']})
    elif m.get('destination') in ('/dev/pts', '/dev/mqueue', '/dev/shm'):
        pass
    else:
        new_mounts.append(m)
c['mounts'] = new_mounts
c.get('linux', {}).pop('devices', None)
with open('$BUNDLE/config.json', 'w') as f:
    json.dump(c, f)
" 2>/dev/null
fi

exec /usr/bin/crun.real "$@"
CRUNWRAPPER
  sudo chmod +x /usr/local/bin/crun-wrapper
  [[ -f /usr/bin/crun && ! -L /usr/bin/crun ]] && sudo mv /usr/bin/crun /usr/bin/crun.real
  sudo ln -sf /usr/local/bin/crun-wrapper /usr/bin/runc 2>/dev/null || true
fi

sudo systemctl restart containerd
sudo systemctl enable containerd
log "    설치 확인: $(containerd --version)"

log "[5/5] Kubernetes ${K8S_VERSION} 설치 (kubelet / kubeadm / kubectl)..."
INSTALLED_KUBELET=$(dpkg-query -W -f='${Version}' kubelet 2>/dev/null || echo "")
if [[ "${INSTALLED_KUBELET}" == "${K8S_APT_VERSION}" ]]; then
  log "    [SKIP] kubelet 이미 설치됨: ${INSTALLED_KUBELET}"
else
  sudo mkdir -p /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
      | sudo gpg --batch --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  fi

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
    https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
  sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

  sudo apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
  sudo apt-get update -qq
  sudo apt-get install -y \
    "kubelet=${K8S_APT_VERSION}" \
    "kubeadm=${K8S_APT_VERSION}" \
    "kubectl=${K8S_APT_VERSION}"
  sudo apt-mark hold kubelet kubeadm kubectl
  sudo systemctl enable kubelet
fi
log "    설치 확인: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

# ============================================================
# STEP 2. 클러스터 참여
# ============================================================

log "[6/6] 클러스터 참여 (kubeadm join)..."

if [[ "$IS_ORBSTACK" == "true" ]]; then
  echo 'KUBELET_EXTRA_ARGS="--fail-swap-on=false"' | sudo tee /etc/default/kubelet > /dev/null
  sudo systemctl daemon-reload
fi

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  log "    [SKIP] 이미 클러스터에 참여된 노드입니다."
  log "           재참여가 필요하면: sudo kubeadm reset -f && sudo rm -rf /etc/kubernetes"
  exit 0
fi

if [[ "$IS_ORBSTACK" == "true" ]]; then
  sudo kubeadm join "${CONTROL_PLANE_ENDPOINT}" \
    --token "${JOIN_TOKEN}" \
    --discovery-token-ca-cert-hash "sha256:${JOIN_CA_CERT_HASH}" \
    --ignore-preflight-errors=Swap
else
  sudo kubeadm join "${CONTROL_PLANE_ENDPOINT}" \
    --token "${JOIN_TOKEN}" \
    --discovery-token-ca-cert-hash "sha256:${JOIN_CA_CERT_HASH}"
fi

echo ""
log "=== Worker 노드 설정 완료 ==="
echo ""
echo "  Control Plane 에서 확인: kubectl get nodes -o wide"
