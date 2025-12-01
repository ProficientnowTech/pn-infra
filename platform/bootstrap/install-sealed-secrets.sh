#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
RELEASE_NAME="${SEALED_SECRETS_RELEASE:-sealed-secrets}"
CHART_VERSION="${SEALED_SECRETS_VERSION:-2.15.2}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]    [$(date +'%H:%M:%S')] [SealedSecrets]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]    [$(date +'%H:%M:%S')] [SealedSecrets]${NC} $1"; }
error() { echo -e "${RED}[ERROR]   [$(date +'%H:%M:%S')] [SealedSecrets]${NC} $1"; }
ok()    { echo -e "${GREEN}[SUCCESS] [$(date +'%H:%M:%S')] [SealedSecrets]${NC} $1"; }

ensure_tools() {
	if ! command -v helm >/dev/null 2>&1; then
		error "helm binary not found. Install helm before running this script."
		exit 1
	fi
	if ! command -v kubectl >/dev/null 2>&1; then
		error "kubectl binary not found. Install kubectl before running this script."
		exit 1
	fi
}

sealed_secrets_ready() {
	kubectl get deployment "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1 \
		&& kubectl wait --for=condition=available deployment/"${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=5s >/dev/null 2>&1
}

install_chart() {
	log "Installing sealed-secrets controller (release ${RELEASE_NAME}, namespace ${NAMESPACE})..."

	if ! helm repo list | grep -q "^bitnami"; then
		helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
	fi
	helm repo update >/dev/null

	helm upgrade --install "${RELEASE_NAME}" bitnami/sealed-secrets \
		--namespace "${NAMESPACE}" \
		--create-namespace \
		--version "${CHART_VERSION}" \
		--set fullnameOverride="${RELEASE_NAME}" \
		--wait >/dev/null

	ok "Helm release ${RELEASE_NAME} installed."
}

wait_for_controller() {
	log "Waiting for sealed-secrets controller to become ready..."
if kubectl rollout status deployment/"${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=180s >/dev/null; then
	ok "Sealed-secrets controller is ready."
else
	error "Timed out waiting for sealed-secrets controller."
	exit 1
fi
}

ensure_tools

if sealed_secrets_ready; then
	ok "Sealed-secrets controller already installed."
	exit 0
fi

install_chart
wait_for_controller
