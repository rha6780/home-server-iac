#!/bin/bash
# ============================================================
# fetch-kubeconfig.sh - Control Plane kubeconfig를 로컬로 복사
#
# 사용법:
#   bash fetch-kubeconfig.sh
#   bash fetch-kubeconfig.sh --env .env --output ~/.kube/home-server.yaml
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/k8s-fetch-kubeconfig.log}"

source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${SCRIPT_DIR}/.env"
OUTPUT_FILE="${HOME}/.kube/home-server.yaml"

usage() {
  cat <<EOF
Usage:
  bash fetch-kubeconfig.sh [--env PATH] [--output PATH]

Options:
  --env PATH       읽을 환경 파일입니다. 기본값: scripts/kubernetes/.env
  --output PATH    저장할 kubeconfig 파일입니다. 기본값: ~/.kube/home-server.yaml
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ -n "${2:-}" ]] || { echo "--env 뒤에 파일 경로가 필요합니다." >&2; exit 1; }
      ENV_FILE="$2"
      shift 2
      ;;
    --output)
      [[ -n "${2:-}" ]] || { echo "--output 뒤에 파일 경로가 필요합니다." >&2; exit 1; }
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${ENV_FILE}" != /* ]]; then
  ENV_FILE="${PWD}/${ENV_FILE}"
fi
OUTPUT_FILE="${OUTPUT_FILE/#\~/$HOME}"

load_env "${ENV_FILE}"

TMP_FILE=$(mktemp /tmp/home-server-kubeconfig-XXXX.yaml)
trap 'rm -f "${TMP_FILE}"' EXIT

log_info "cp-master에서 kubeconfig 복사: ${CP_MASTER_IP}"
if ! _ssh "${CP_MASTER_IP}" "test -f ~/.kube/config"; then
  log_error "cp-master의 ~/.kube/config를 찾지 못했습니다."
  log_error "먼저 Control Plane 초기화가 완료됐는지 확인하세요: bash scripts/kubernetes/deploy.sh --step 2"
  exit 1
fi

scp -i "${SSH_KEY_PATH}" ${SSH_OPTS} "${SSH_USER}@${CP_MASTER_IP}:~/.kube/config" "${TMP_FILE}" \
  >/dev/null

mkdir -p "$(dirname "${OUTPUT_FILE}")"
if [[ -f "${OUTPUT_FILE}" ]]; then
  BACKUP_FILE="${OUTPUT_FILE}.bak.$(date '+%Y%m%d_%H%M%S')"
  cp "${OUTPUT_FILE}" "${BACKUP_FILE}"
  chmod 600 "${BACKUP_FILE}"
  log_info "기존 kubeconfig 백업: ${BACKUP_FILE}"
fi

install -m 0600 "${TMP_FILE}" "${OUTPUT_FILE}"

log_success "kubeconfig 저장 완료: ${OUTPUT_FILE}"
log_info "확인 명령:"
echo "  KUBECONFIG=${OUTPUT_FILE} kubectl config current-context"
echo "  KUBECONFIG=${OUTPUT_FILE} kubectl get nodes -o wide"

if command -v kubectl >/dev/null 2>&1; then
  echo ""
  echo "---- kubeconfig context ----"
  KUBECONFIG="${OUTPUT_FILE}" kubectl config current-context 2>/dev/null || true
  echo ""
  echo "---- kubeconfig cluster endpoint ----"
  KUBECONFIG="${OUTPUT_FILE}" kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}' 2>/dev/null || true
fi
