#!/bin/bash
# ============================================================
# Master(Control Plane) 노드 설치 스크립트
# - MODE=primary : 첫 번째 CP 노드 (클러스터 초기화)
# - MODE=join    : 추가 CP 노드 (클러스터 참여)
# ============================================================

set -euo pipefail

# ============================
# 버전 설정
# ============================
CONTAINERD_VERSION="1.7.29-1~ubuntu.24.04~noble"
ALLOW_CONTAINERD_DOWNGRADE="false"
K8S_VERSION="1.36.2"
K8S_APT_VERSION="${K8S_VERSION}-2.1"
K8S_MINOR="${K8S_VERSION%.*}"
HELM_VERSION="3.21.2"

# ============================
# [수정 필요] 공통 설정
# ============================
MODE="primary"
THIS_NODE_IP="192.168.219.31"
CLUSTER_NAME="my-cluster"
CONTROL_PLANE_ENDPOINT="api.k8s.your-domain.com:6445"
POD_SUBNET="10.219.0.0/16"
SERVICE_SUBNET="10.96.0.0/12"

CERT_SANS=(
  "api.k8s.your-domain.com"
  "192.168.219.30"
  "192.168.219.31"
  "192.168.219.32"
  "192.168.219.33"
)

JOIN_TOKEN=""
JOIN_CA_CERT_HASH=""
JOIN_CERTIFICATE_KEY=""

# OrbStack/컨테이너 환경 여부 (true: OrbStack 워크어라운드 적용)
IS_ORBSTACK="false"
# ============================

log() { echo "[$(date '+%H:%M:%S')] $*"; }

admin_kubeconfig_source() {
  if [[ -f /etc/kubernetes/super-admin.conf ]]; then
    echo "/etc/kubernetes/super-admin.conf"
  elif [[ -f /etc/kubernetes/admin.conf ]]; then
    echo "/etc/kubernetes/admin.conf"
  else
    return 1
  fi
}

write_user_kubeconfig() {
  local server="$1"
  local src
  src=$(admin_kubeconfig_source)

  mkdir -p "$HOME/.kube"
  sudo cp -f "$src" "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  sed -i "s|server: https://.*|server: https://${server}|g" "$HOME/.kube/config"

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    local sudo_home
    sudo_home=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    if [[ -n "${sudo_home}" && -d "${sudo_home}" ]]; then
      mkdir -p "${sudo_home}/.kube"
      cp -f "$HOME/.kube/config" "${sudo_home}/.kube/config"
      chown -R "${SUDO_USER}:" "${sudo_home}/.kube"
    fi
  fi
}

wait_for_kube_api() {
  local server="$1" desc="$2" timeout="${3:-300}"
  local interval=5 elapsed=0

  export KUBECONFIG="$HOME/.kube/config"
  log "  API 서버 응답 대기: ${desc} (${server}, 최대 ${timeout}s)..."

  until kubectl --request-timeout=5s cluster-info > /dev/null 2>&1; do
    if (( elapsed >= timeout )); then
      log "  [ERROR] API 서버 응답 타임아웃: ${desc} (${server})"
      return 1
    fi
    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done

  log "  API 서버 응답 확인: ${desc} (${elapsed}s)"
}

print_control_plane_diagnostics() {
  log "  진단 정보 수집..."
  sudo systemctl --no-pager --full status kubelet || true
  sudo journalctl -u kubelet --no-pager -n 80 || true
  sudo crictl ps -a 2>/dev/null || true
}

ensure_primary_ready() {
  local local_server="${THIS_NODE_IP}:6443"

  if ! admin_kubeconfig_source > /dev/null; then
    log "  [ERROR] kube-apiserver manifest는 있지만 admin kubeconfig가 없습니다."
    log "          부분 초기화 상태일 수 있습니다. 재초기화가 필요하면 kubeadm reset 후 다시 실행하세요."
    print_control_plane_diagnostics
    return 1
  fi

  write_user_kubeconfig "${local_server}"
  if ! wait_for_kube_api "${local_server}" "local control-plane" 60; then
    log "  local API 미응답 — kubelet/containerd 재시작 후 재확인합니다."
    sudo systemctl restart containerd || true
    sudo systemctl restart kubelet || true
    if ! wait_for_kube_api "${local_server}" "local control-plane after restart" 300; then
      print_control_plane_diagnostics
      return 1
    fi
  fi

  write_user_kubeconfig "${CONTROL_PLANE_ENDPOINT}"
  if ! wait_for_kube_api "${CONTROL_PLANE_ENDPOINT}" "load-balanced endpoint" 120; then
    log "  [ERROR] 로컬 API는 정상이나 CONTROL_PLANE_ENDPOINT가 응답하지 않습니다."
    log "          HAProxy 설정, DNS/hosts, 방화벽, ${CONTROL_PLANE_ENDPOINT} → ${THIS_NODE_IP}:6443 경로를 확인하세요."
    print_control_plane_diagnostics
    return 1
  fi
}

log "=== Master 노드 설정 시작 (MODE=${MODE}) ==="
log "    containerd : ${CONTAINERD_VERSION}"
log "    Kubernetes : ${K8S_VERSION}"
log "    Helm       : ${HELM_VERSION}"
log "    IS_ORBSTACK: ${IS_ORBSTACK}"
echo ""

# ============================================================
# STEP 1. 공통 Prerequisites
# ============================================================

log "[1/6] Swap 비활성화..."
if swapon --show | grep -q .; then
  if [[ "$IS_ORBSTACK" == "true" ]]; then
    # OrbStack: swapoff 권한 없음 → kubeadm에서 무시 처리
    if sudo swapoff -a 2>/dev/null; then
      log "    Swap 비활성화 완료"
      sudo sed -i '/^[^#].*swap/s/^/# /' /etc/fstab
    else
      log "    [WARN] swapoff 실패 (OrbStack 환경) — kubeadm --ignore-preflight-errors=Swap 으로 진행"
    fi
  else
    # 실서버: 정상 비활성화
    sudo swapoff -a
    sudo sed -i '/^[^#].*swap/s/^/# /' /etc/fstab
    log "    Swap 비활성화 완료"
  fi
else
  log "    [SKIP] Swap 이미 비활성화됨"
fi

if [[ "$IS_ORBSTACK" == "true" ]]; then
  log "[2/6] /dev/kmsg 생성 (OrbStack 환경 대응)..."
  if [[ ! -e /dev/kmsg ]]; then
    sudo touch /dev/kmsg && sudo chmod 644 /dev/kmsg
    log "    /dev/kmsg 생성 완료"
  fi
  echo "f /dev/kmsg 0644 root root - -" \
    | sudo tee /etc/tmpfiles.d/kmsg.conf > /dev/null
else
  log "[2/6] /dev/kmsg 확인..."
  log "    [SKIP] 실서버 환경 — /dev/kmsg 생성 불필요"
fi

log "[3/6] 커널 파라미터 설정..."
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
  # OrbStack: 일부 커널 파라미터 설정 불가 → 에러 무시
  sudo sysctl --system 2>&1 | grep -v "Operation not permitted" || true
else
  sudo sysctl --system
fi

log "[4/6] containerd ${CONTAINERD_VERSION} 설치..."
INSTALLED_CTR=$(dpkg-query -W -f='${Version}' containerd.io 2>/dev/null || echo "")
if [[ "${INSTALLED_CTR}" == "${CONTAINERD_VERSION}" ]]; then
  log "    [SKIP] containerd 이미 설치됨: ${INSTALLED_CTR}"
elif [[ -n "${INSTALLED_CTR}" && "${ALLOW_CONTAINERD_DOWNGRADE}" != "true" ]]; then
  log "    [SKIP] containerd 다른 버전이 이미 설치됨: ${INSTALLED_CTR}"
  log "           목표 버전: ${CONTAINERD_VERSION}"
  log "           downgrade/변경이 필요하면 ALLOW_CONTAINERD_DOWNGRADE=true 로 실행하세요."
  sudo apt-mark hold containerd.io 2>/dev/null || true
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
  if [[ -n "${INSTALLED_CTR}" && "${ALLOW_CONTAINERD_DOWNGRADE}" == "true" ]]; then
    sudo apt-get install -y --allow-downgrades "containerd.io=${CONTAINERD_VERSION}"
  else
    sudo apt-get install -y "containerd.io=${CONTAINERD_VERSION}"
  fi
  sudo apt-mark hold containerd.io
fi

# containerd 기본 설정 (공통)
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

if [[ "$IS_ORBSTACK" == "true" ]]; then
  # OrbStack: btrfs + 커널 제한으로 overlayfs/pivot_root/mknod 불가
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

log "[5/6] Kubernetes ${K8S_VERSION} 설치 (kubelet / kubeadm / kubectl)..."
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

log "[6/6] Helm ${HELM_VERSION} 설치..."
INSTALLED_HELM=$(helm version --short 2>/dev/null | grep -oP 'v[\d.]+' || echo "")
if [[ "${INSTALLED_HELM}" == "v${HELM_VERSION}" ]]; then
  log "    [SKIP] Helm 이미 설치됨: ${INSTALLED_HELM}"
else
  HELM_ARCH=$(dpkg --print-architecture)
  HELM_TAR="helm-v${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"
  curl -fsSL "https://get.helm.sh/${HELM_TAR}" -o "/tmp/${HELM_TAR}"
  tar -zxf "/tmp/${HELM_TAR}" -C /tmp
  sudo mv "/tmp/linux-${HELM_ARCH}/helm" /usr/local/bin/helm
  sudo chmod +x /usr/local/bin/helm
  rm -f "/tmp/${HELM_TAR}"
fi
log "    설치 확인: $(helm version --short)"

# ============================================================
# STEP 2. 노드 역할별 처리
# ============================================================

if [[ "$MODE" == "primary" ]]; then
  log "[7/7] 클러스터 초기화 (kubeadm init)..."

  # 이미 초기화된 노드면 kubeconfig 확인 후 스킵
  if [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]]; then
    log "    [SKIP] 이미 Control Plane 으로 초기화된 노드입니다."
    log "           재초기화가 필요하면: sudo kubeadm reset -f && sudo rm -rf /etc/kubernetes"
    ensure_primary_ready
    exit 0
  fi

  CLUSTER_CONFIG=$(mktemp /tmp/cluster-config-XXXX.yaml)
  cat > "$CLUSTER_CONFIG" <<EOF
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
clusterName: ${CLUSTER_NAME}
controlPlaneEndpoint: "${CONTROL_PLANE_ENDPOINT}"
kubernetesVersion: "v${K8S_VERSION}"
networking:
  podSubnet: "${POD_SUBNET}"
  serviceSubnet: "${SERVICE_SUBNET}"
apiServer:
  certSANs:
$(printf "    - \"%s\"\n" "${CERT_SANS[@]}")
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "${THIS_NODE_IP}"
  bindPort: 6443
EOF

  # OrbStack 환경에서만 failSwapOn: false 추가
  if [[ "$IS_ORBSTACK" == "true" ]]; then
    cat >> "$CLUSTER_CONFIG" <<EOF
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
failSwapOn: false
cgroupDriver: systemd
EOF
    sudo kubeadm init --config "$CLUSTER_CONFIG" --upload-certs \
      --ignore-preflight-errors=Swap || true
  else
    sudo kubeadm init --config "$CLUSTER_CONFIG" --upload-certs
  fi
  rm -f "$CLUSTER_CONFIG"

  ensure_primary_ready

  grep -qxF 'export KUBECONFIG=$HOME/.kube/config' ~/.bash_profile 2>/dev/null \
    || cat >> ~/.bash_profile <<'PROFILE'

# kubectl
export KUBECONFIG=$HOME/.kube/config
alias k='kubectl'
alias kw='kubectl -o wide'
source <(kubectl completion bash)
complete -F __start_kubectl k
PROFILE

  # kubeadm init 중간 실패 시 나머지 단계 완료
  if ! kubectl get clusterrole cluster-admin > /dev/null 2>&1; then
    log "  kubeadm 나머지 단계 완료 중..."
    sudo kubeadm init phase upload-config kubeadm 2>/dev/null || true
    sudo kubeadm init phase mark-control-plane 2>/dev/null || true
    sudo kubeadm init phase bootstrap-token 2>/dev/null || true
    sudo kubeadm init phase addon all 2>/dev/null || true
  fi

  # kube-proxy strictARP 활성화 (MetalLB 요구사항)
  log "  kube-proxy strictARP 활성화..."
  kubectl get configmap kube-proxy -n kube-system -o yaml \
    | sed 's/strictARP: false/strictARP: true/' \
    | kubectl apply -f - > /dev/null
  kubectl -n kube-system rollout restart daemonset kube-proxy > /dev/null

  echo ""
  log "=== Primary Control Plane 초기화 완료 ==="

elif [[ "$MODE" == "join" ]]; then
  if [[ -z "$JOIN_TOKEN" || -z "$JOIN_CA_CERT_HASH" || -z "$JOIN_CERTIFICATE_KEY" ]]; then
    echo "[ERROR] MODE=join 시 JOIN_TOKEN, JOIN_CA_CERT_HASH, JOIN_CERTIFICATE_KEY 를 설정하세요."
    exit 1
  fi

  log "[7/7] Control Plane 클러스터 참여 (kubeadm join)..."

  # OrbStack 환경에서만 fail-swap-on 비활성화
  if [[ "$IS_ORBSTACK" == "true" ]]; then
    echo 'KUBELET_EXTRA_ARGS="--fail-swap-on=false"' | sudo tee /etc/default/kubelet > /dev/null
    sudo systemctl daemon-reload
  fi

  if [[ -f /etc/kubernetes/kubelet.conf ]]; then
    if [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]]; then
      log "    [SKIP] 이미 Control Plane 으로 참여된 노드입니다."
      log "           재참여가 필요하면: sudo kubeadm reset -f && sudo rm -rf /etc/kubernetes"
      exit 0
    fi

    log "    [ERROR] kubelet.conf는 있지만 kube-apiserver manifest가 없습니다."
    log "            Control Plane join이 중간 실패한 상태일 수 있습니다."
    log "            재참여가 필요하면: sudo kubeadm reset -f && sudo rm -rf /etc/kubernetes"
    exit 1
  fi

  if [[ "$IS_ORBSTACK" == "true" ]]; then
    sudo kubeadm join "${CONTROL_PLANE_ENDPOINT}" \
      --token "${JOIN_TOKEN}" \
      --discovery-token-ca-cert-hash "sha256:${JOIN_CA_CERT_HASH}" \
      --control-plane \
      --certificate-key "${JOIN_CERTIFICATE_KEY}" \
      --apiserver-advertise-address "${THIS_NODE_IP}" \
      --ignore-preflight-errors=Swap
  else
    sudo kubeadm join "${CONTROL_PLANE_ENDPOINT}" \
      --token "${JOIN_TOKEN}" \
      --discovery-token-ca-cert-hash "sha256:${JOIN_CA_CERT_HASH}" \
      --control-plane \
      --certificate-key "${JOIN_CERTIFICATE_KEY}" \
      --apiserver-advertise-address "${THIS_NODE_IP}"
  fi

  write_user_kubeconfig "${CONTROL_PLANE_ENDPOINT}"

  grep -qxF 'export KUBECONFIG=$HOME/.kube/config' ~/.bash_profile 2>/dev/null \
    || cat >> ~/.bash_profile <<'PROFILE'

# kubectl
export KUBECONFIG=$HOME/.kube/config
alias k='kubectl'
alias kw='kubectl -o wide'
source <(kubectl completion bash)
complete -F __start_kubectl k
PROFILE

  echo ""
  log "=== Control Plane join 완료 ==="

else
  echo "[ERROR] MODE 는 'primary' 또는 'join' 이어야 합니다."
  exit 1
fi
