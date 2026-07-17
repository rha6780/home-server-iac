#!/bin/bash
# ============================================================
# 05. Post-Install: Control Plane init 이후 Helm 컴포넌트 설치
# 첫 번째 Control Plane 노드에서 실행
#
# 설치 버전
#   Calico (tigera-operator) : 3.29.3
#   MetalLB                  : 0.14.9
#   Gateway API CRD          : 1.2.0
#   NGINX Gateway Fabric     : 1.5.1
# ============================================================

set -euo pipefail

# ============================
# 버전 설정
# ============================
CALICO_CHART_VERSION="3.29.3"       # tigera-operator Helm chart (== Calico 버전)
METALLB_CHART_VERSION="0.14.9"      # MetalLB Helm chart
GATEWAY_API_VERSION="1.2.0"         # Kubernetes Gateway API CRD
NGF_CHART_VERSION="1.5.1"           # NGINX Gateway Fabric Helm chart
# ============================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="${SCRIPT_DIR}/04.helm-charts"

export KUBECONFIG="$HOME/.kube/config"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== Helm 컴포넌트 설치 시작 ==="
log "    Calico (tigera-operator) : ${CALICO_CHART_VERSION}"
log "    MetalLB                  : ${METALLB_CHART_VERSION}"
log "    Gateway API CRD          : ${GATEWAY_API_VERSION}"
log "    NGINX Gateway Fabric     : ${NGF_CHART_VERSION}"
echo ""

# -----------
# Helm repo 추가 및 업데이트
# -----------
helm repo add projectcalico https://docs.tigera.io/calico/charts
helm repo add metallb       https://metallb.github.io/metallb
helm repo update

# -----------
# 1. Calico CRD
# -----------
log "[1/5] Calico CRD ${CALICO_CHART_VERSION} 설치..."
helm template calico-crds projectcalico/crd.projectcalico.org.v1 \
  --version "${CALICO_CHART_VERSION}" \
  | kubectl apply --server-side -f -

log "  Calico operator CRD 등록 완료 대기..."
kubectl wait --for=condition=established \
  crd/installations.operator.tigera.io \
  crd/apiservers.operator.tigera.io \
  crd/goldmanes.operator.tigera.io \
  crd/whiskers.operator.tigera.io \
  --timeout=90s

# -----------
# 2. Calico CNI
# -----------
log "[2/5] Calico CNI ${CALICO_CHART_VERSION} 설치..."
helm upgrade --install calico projectcalico/tigera-operator \
  --namespace tigera-operator \
  --create-namespace \
  --version "${CALICO_CHART_VERSION}" \
  --values "${CHARTS_DIR}/calico/values.yaml" \
  --wait --timeout 5m

log "  Calico 노드 상태:"
kubectl get pods -n calico-system -l app.kubernetes.io/name=calico-node 2>/dev/null \
  || kubectl get pods -n kube-system -l k8s-app=calico-node

# -----------
# 3. MetalLB
# -----------
log "[3/5] MetalLB ${METALLB_CHART_VERSION} 설치..."
helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  --version "${METALLB_CHART_VERSION}" \
  --values "${CHARTS_DIR}/metallb/values.yaml" \
  --wait --timeout 3m

log "  MetalLB IP 풀 적용..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

kubectl apply -f "${CHARTS_DIR}/metallb/ip-address-pool.yaml"

# -----------
# 4. Gateway API CRD (NGINX Gateway Fabric 요구사항)
# -----------
log "[4/5] Gateway API CRD v${GATEWAY_API_VERSION} 설치..."
kubectl apply -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${GATEWAY_API_VERSION}/standard-install.yaml"

# CRD 등록 완료 대기
kubectl wait --for=condition=established \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io \
  --timeout=60s

# -----------
# 5. NGINX Gateway Fabric
# -----------
log "[5/5] NGINX Gateway Fabric ${NGF_CHART_VERSION} 설치..."
helm upgrade --install nginx-gateway-fabric \
  oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace \
  --version "${NGF_CHART_VERSION}" \
  --values "${CHARTS_DIR}/nginx-gateway-fabric/values.yaml" \
  --wait --timeout 3m

log "  Gateway 리소스 적용..."
kubectl apply -f "${CHARTS_DIR}/nginx-gateway-fabric/gateway.yaml"

echo ""
log "=== 설치 완료 ==="
echo ""
echo "설치된 버전:"
echo "  Calico           : $(helm list -n tigera-operator -o json | python3 -c "import sys,json; [print(r['chart']) for r in json.load(sys.stdin)]" 2>/dev/null || echo "${CALICO_CHART_VERSION}")"
echo "  MetalLB          : $(helm list -n metallb-system -o json | python3 -c "import sys,json; [print(r['chart']) for r in json.load(sys.stdin)]" 2>/dev/null || echo "${METALLB_CHART_VERSION}")"
echo "  NGINX GW Fabric  : $(helm list -n nginx-gateway -o json | python3 -c "import sys,json; [print(r['chart']) for r in json.load(sys.stdin)]" 2>/dev/null || echo "${NGF_CHART_VERSION}")"
echo ""
echo "확인 명령어:"
echo "  kubectl get nodes -o wide"
echo "  kubectl get pods -A"
echo "  kubectl get svc -n nginx-gateway"
echo "  kubectl get gateway -A"
