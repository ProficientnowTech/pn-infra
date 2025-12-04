#!/bin/bash
set -euo pipefail

# Configuration
ENVIRONMENT="${1:-production}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_VERSION="${ARGOCD_VERSION:-9.1.6}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
REPO_URL="${REPO_URL:-https://github.com/ProficientnowTech/pn-infra.git}"
REPO_TOKEN="${REPO_TOKEN:-}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[SUCCESS] [$(date +'%H:%M:%S')] [Argo Bootstrap] $1${NC}"; }
info() { echo -e "${BLUE}[INFO]    [$(date +'%H:%M:%S')] [Argo Bootstrap] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN]    [$(date +'%H:%M:%S')] [Argo Bootstrap] $1${NC}"; }
error() { echo -e "${RED}[ERROR]   [$(date +'%H:%M:%S')] [Argo Bootstrap] $1${NC}"; }

# Check prerequisites
check_prerequisites() {
	log "🔍 Checking prerequisites..."
	command -v kubectl >/dev/null 2>&1 || {
		error "kubectl required but not installed"
		exit 1
	}
	command -v helm >/dev/null 2>&1 || {
		error "helm required but not installed"
		exit 1
	}
	kubectl cluster-info >/dev/null 2>&1 || {
		error "Cannot connect to cluster"
		exit 1
	}
	log "✓ Prerequisites OK"
}

# Install ArgoCD
install_argocd() {
	log "🚀 Installing ArgoCD..."

	# Ensure repo exists
	if ! helm repo list | grep -q "^argo\\s"; then
		helm repo add argo https://argoproj.github.io/argo-helm || {
			error "Failed to add Argo Helm repository"
			return 1
		}
	fi
	helm repo update >/dev/null 2>&1

	# 🔥 FIX: If argocd-notifications-secret exists but is NOT Helm-owned, patch it
	if kubectl get secret argocd-notifications-secret -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
		owner_label=$(kubectl get secret argocd-notifications-secret -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
		release_name=$(kubectl get secret argocd-notifications-secret -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || echo "")

		if [[ "$owner_label" != "Helm" || "$release_name" != "argocd" ]]; then
			warn "⚠️ ArgoCD notifications secret exists but is not Helm-owned. Patching ownership..."

			kubectl label secret argocd-notifications-secret \
				app.kubernetes.io/managed-by=Helm --overwrite -n "${ARGOCD_NAMESPACE}" || {
				error "Failed to apply Helm ownership label"
				return 1
			}

			kubectl annotate secret argocd-notifications-secret \
				meta.helm.sh/release-name=argocd --overwrite -n "${ARGOCD_NAMESPACE}" || {
				error "Failed to apply Helm release-name annotation"
				return 1
			}

			kubectl annotate secret argocd-notifications-secret \
				meta.helm.sh/release-namespace="${ARGOCD_NAMESPACE}" --overwrite -n "${ARGOCD_NAMESPACE}" || {
				error "Failed to apply Helm release-namespace annotation"
				return 1
			}

			log "✓ Patched secret ownership: Helm will now accept this resource"
		else
			log "✓ argocd-notifications-secret already Helm-owned"
		fi
	fi

	# ---- Actual Helm install ----
	helm upgrade --install argocd argo/argo-cd \
		--version "${ARGOCD_VERSION}" \
		--namespace "${ARGOCD_NAMESPACE}" \
		--create-namespace \
		--set configs.cm.application.resourceTrackingMethod=annotation \
		--wait \
		--timeout=600s \
		2>&1 | tee /tmp/argocd-helm-install.log >/dev/null || {

		error "❌ Helm installation failed. See /tmp/argocd-helm-install.log"
		return 1
	}

	log "✓ ArgoCD installed"
}

# Wait for ArgoCD to be fully ready
wait_for_argocd() {
	log "⏳ Waiting for ArgoCD to be ready..."

	# Wait for pods to be ready with kubectl wait (extended timeouts)
	log "⏳ Waiting for ArgoCD pods to be ready (timeout: 900s)..."
	kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n ${ARGOCD_NAMESPACE} --timeout=900s >/dev/null 2>&1
	kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-application-controller -n ${ARGOCD_NAMESPACE} --timeout=900s >/dev/null 2>&1
	kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-repo-server -n ${ARGOCD_NAMESPACE} --timeout=900s >/dev/null 2>&1

	# Additional wait for services to be fully operational with 1-second intervals (extended timeout)
	log "⏳ Waiting for ArgoCD services to be operational (checking every second for 90 seconds)..."
	local max_attempts=90
	local attempt=1

	while [ $attempt -le $max_attempts ]; do
		# Get detailed pod status
		local pod_status=$(kubectl get pods -n ${ARGOCD_NAMESPACE} -l app.kubernetes.io/part-of=argocd -o jsonpath='{range .items[*]}{.metadata.name}: {.status.phase} {.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null || echo "No pods found")

		# Count ready pods
		local ready_pods=$(echo "$pod_status" | grep "true" | wc -l)
		local total_pods=$(echo "$pod_status" | grep -c ":" || echo "0")

		if [[ $ready_pods -eq $total_pods && $total_pods -gt 0 ]]; then
			log "✓ All $total_pods ArgoCD pods ready and operational after $attempt seconds"
			break
		fi

		# Log detailed progress every time (1-second intervals)
		info "ArgoCD status [${attempt}/${max_attempts}]: $ready_pods/$total_pods pods ready"
		if [[ $attempt -eq 1 || $((attempt % 10)) -eq 0 ]]; then
			# Show detailed pod status every 10 attempts (less verbose)
			while IFS= read -r line; do
				if [[ -n "$line" ]]; then
					info "  - $line"
				fi
			done <<<"$pod_status"
		fi

		sleep 1
		((attempt++))
	done

	if [ $attempt -gt $max_attempts ]; then
		warn "⚠️  ArgoCD services check timed out after ${max_attempts} seconds"
		warn "Current pod status:"
		kubectl get pods -n ${ARGOCD_NAMESPACE} -l app.kubernetes.io/part-of=argocd 2>/dev/null || warn "Cannot get pod status"
	else
		log "✓ All ArgoCD pods confirmed ready"
	fi

	log "✓ ArgoCD ready"
}

# Get ArgoCD admin password
get_argocd_password() {
	local max_attempts=60
	local attempt=1

	while [ $attempt -le $max_attempts ]; do
		# Try to get the password from the initial admin secret
		local password=$(kubectl get secret argocd-initial-admin-secret -n ${ARGOCD_NAMESPACE} -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

		if [[ -n "$password" ]]; then
			echo "$password"
			return 0
		fi

		# If we can't find the initial admin secret, try getting it from the argocd-secret
		if [[ $attempt -eq 5 ]]; then
			info "Trying alternative method to get ArgoCD password..."
			password=$(kubectl get secret argocd-secret -n ${ARGOCD_NAMESPACE} -o jsonpath="{.data.admin\.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

			if [[ -n "$password" ]]; then
				echo "$password"
				return 0
			fi
		fi

		if [[ $attempt -eq 1 ]]; then
			info "Waiting for ArgoCD password to be generated..."
		elif [[ $((attempt % 5)) -eq 0 ]]; then
			info "Still waiting for ArgoCD password... (attempt $attempt/$max_attempts)"
		fi

		sleep 2
		((attempt++))
	done

	error "Failed to retrieve ArgoCD admin password after $max_attempts attempts"
	error "You may need to check the ArgoCD pods and secrets manually:"
	error "  kubectl get pods -n ${ARGOCD_NAMESPACE}"
	error "  kubectl get secrets -n ${ARGOCD_NAMESPACE} | grep admin"
	return 1
}

# Wait for user to manually add repository and confirm

# Print success message with access instructions
print_argo_success() {
	local password=$(get_argocd_password || echo "not-found")

	echo
	echo -e "${BLUE}========= ArgoCD Installation Complete ==========="
	echo -e "=================================================${NC}"
	echo
	echo -e "${GREEN}===== ArgoCD is now installed and ready${NC}====="
	echo
	echo -e "${YELLOW} Access instructions:${NC}"
	echo
	echo -e "1. ${BLUE}Start port-forward:${NC}"
	echo -e "   ${GREEN}kubectl port-forward --address 0.0.0.0,localhost svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443${NC}"
	echo
	echo -e "2. ${BLUE}Access:${NC} ${GREEN}https://localhost:8080${NC}"
	echo
	echo -e "3. ${BLUE}Login:${NC} Username: ${GREEN}admin${NC} | Password: ${GREEN}${password}${NC}"
	echo
}

# Main
main() {
	log "🚀 Starting ArgoCD installation (${ENVIRONMENT})..."

	info "Note: Repository credentials managed by sealed-secrets (applied before ArgoCD)"

	check_prerequisites
	install_argocd
	wait_for_argocd

	# Verify sealed secrets are present
	if kubectl get secret -n argocd argocd-private-repo &>/dev/null 2>&1; then
		log "✓ Repository credentials found (sealed-secrets)"
	else
		warn "⚠️ Repository credentials not found - sealed-secrets may not be unsealed yet"
	fi

	print_argo_success
	log "✅ ArgoCD installation completed!"
}

main "$@"
