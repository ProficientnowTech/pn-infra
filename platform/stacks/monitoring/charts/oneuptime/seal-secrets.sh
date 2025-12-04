#!/bin/bash
set -euo pipefail

# OneUptime Secrets Sealing Script
# This script seals Kubernetes Secret YAML files into SealedSecrets

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/secrets"
TEMPLATES_DIR="${SCRIPT_DIR}/templates/"
SEALED_SECRETS_CONTROLLER_NAME="sealed-secrets"
SEALED_SECRETS_CONTROLLER_NAMESPACE="sealed-secrets"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
	log_info "Checking requirements..."

	if ! command -v kubectl &>/dev/null; then
		log_error "kubectl is not installed. Please install kubectl first."
		exit 1
	fi

	if ! command -v kubeseal &>/dev/null; then
		log_error "kubeseal is not installed. Please install kubeseal first."
		echo ""
		echo "Install instructions:"
		echo "  macOS: brew install kubeseal"
		echo "  Linux: https://github.com/bitnami-labs/sealed-secrets/releases"
		exit 1
	fi

	log_success "All requirements met"
}

check_cluster_access() {
	log_info "Checking cluster access..."

	if ! kubectl cluster-info &>/dev/null; then
		log_error "Cannot access Kubernetes cluster. Please check your kubeconfig."
		exit 1
	fi

	# Check if sealed-secrets controller is running
	if ! kubectl get deployment "${SEALED_SECRETS_CONTROLLER_NAME}" -n "${SEALED_SECRETS_CONTROLLER_NAMESPACE}" &>/dev/null; then
		log_warn "Sealed Secrets controller not found in namespace '${SEALED_SECRETS_CONTROLLER_NAMESPACE}'"
		log_warn "Proceeding anyway, but secrets may not be decrypted until controller is deployed"
	fi

	log_success "Cluster access verified"
}

# Seal a secret file
seal_secret() {
	local secret_file="$1"
	local secret_name="$2"
	local output_file="${TEMPLATES_DIR}${secret_name}-sealed.yaml"

	log_info "Sealing ${secret_name}..."

	if [[ ! -f "$secret_file" ]]; then
		log_error "Secret file not found: $secret_file"
		return 1
	fi

	# Validate it's a valid Kubernetes Secret
	if ! kubectl apply --dry-run=client -f "$secret_file" &>/dev/null; then
		log_error "Invalid Kubernetes Secret YAML: $secret_file"
		return 1
	fi

	# Seal the secret directly
	if kubeseal \
		--controller-name="${SEALED_SECRETS_CONTROLLER_NAME}" \
		--controller-namespace="${SEALED_SECRETS_CONTROLLER_NAMESPACE}" \
		--format=yaml \
		-f "$secret_file" \
		-w "$output_file"; then

		# Add metadata header
		local temp_file="${output_file}.tmp"
		cat >"$temp_file" <<EOF
---
# SealedSecret for OneUptime ${secret_name}
# Generated from secrets/${secret_name}.secret - DO NOT EDIT MANUALLY
# To update: Edit secrets/${secret_name}.secret and run ./seal-secrets.sh
EOF
		cat "$output_file" >>"$temp_file"
		mv "$temp_file" "$output_file"

		log_success "${secret_name} sealed: ${output_file}"
	else
		log_error "Failed to seal ${secret_name}"
		return 1
	fi
}

# Main
main() {
	echo ""
	echo "========================================"
	echo "  OneUptime Secrets Sealing Script"
	echo "========================================"
	echo ""

	check_requirements
	check_cluster_access

	echo ""

	# Check if specific secret type was requested
	if [[ $# -gt 0 ]]; then
		case "$1" in
		smtp)
			seal_secret "${SECRETS_DIR}/smtp.secret" "smtp"
			;;
		slack)
			seal_secret "${SECRETS_DIR}/slack.secret" "slack"
			;;
		slack-app)
			seal_secret "${SECRETS_DIR}/slack-app.secret" "slack-app"
			;;
		*)
			log_error "Unknown secret type: $1"
			echo "Usage: $0 [smtp|slack|slack-app]"
			exit 1
			;;
		esac
	else
		# Seal all secrets
		seal_secret "${SECRETS_DIR}/smtp.secret" "smtp"
		echo ""
		seal_secret "${SECRETS_DIR}/slack.secret" "slack"
		echo ""
		seal_secret "${SECRETS_DIR}/slack-app.secret" "slack-app"
	fi

	echo ""
	log_success "All secrets sealed successfully!"
	echo ""
	echo "Next steps:"
	echo "  1. Review generated files in: ${TEMPLATES_DIR}/"
	echo "  2. Commit sealed secrets to Git:"
	echo "     git add ${TEMPLATES_DIR}/*.yaml"
	echo "     git commit -m 'Update OneUptime sealed secrets'"
	echo "     git push"
	echo "  3. ArgoCD will deploy and Sealed Secrets controller will decrypt them"
	echo ""
}

# Run main
main "$@"
