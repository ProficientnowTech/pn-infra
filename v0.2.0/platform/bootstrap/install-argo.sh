#!/bin/bash
set -euo pipefail

# Configuration
ENVIRONMENT="${1:-production}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_VERSION="${ARGOCD_VERSION:-8.6.3}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
REPO_URL="${REPO_URL:-https://github.com/pnow-devsupreme/pn-infra.git}"
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

	if ! helm repo list | grep -q "^argo\\s"; then
		helm repo add argo https://argoproj.github.io/argo-helm || {
			error "Failed to add Argo Helm repository"
			return 1
		}
	fi
	helm repo update >/dev/null 2>&1

	helm upgrade --install argocd argo/argo-cd \
		--version ${ARGOCD_VERSION} \
		--namespace ${ARGOCD_NAMESPACE} \
		--create-namespace \
		--set configs.cm.application.resourceTrackingMethod=annotation \
		-f $(dirname $0)/argocd/argocd-values.yaml \
		--wait --timeout=600s >/dev/null 2>&1 | tee /tmp/argocd-helm-install.log || {
		error "Helm installation failed. Check /tmp/argocd-helm-install.log"
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
print_argo_success() {
	local password=$(get_argocd_password || echo "not-found")

	echo
	echo -e "${BLUE}========= ArgoCD Installation Complete ==========="
	echo -e "=================================================${NC}"
	echo
	echo -e "${GREEN}===== ArgoCD is now installed and ready${NC}====="
	echo
	echo -e "${YELLOW} You could proceed with the following steps:${NC}"
	echo
	echo -e "1. ${BLUE}Start port-forward (in a separate terminal):${NC}"
	echo -e "   ${GREEN}kubectl port-forward --address 0.0.0.0,localhost svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443${NC}"
	echo
	echo -e "2. ${BLUE}Access ArgoCD Dashboard:${NC}"
	echo -e "   ${GREEN}https://localhost:8080${NC}"
	echo
	echo -e "3. ${BLUE}Login with:${NC}"
	echo -e "   Username: ${GREEN}admin${NC}"
	echo -e "   Password: ${GREEN}${password}${NC}"
	echo
}

setup_argocd_repository() {
	local repo_secret_file="${SCRIPT_DIR}/repositories/pn-infra.yaml"
	local temp_secret_file
	# trap exit on error and clean up temp secret
	trap 'rm -f "$temp_secret_file"' EXIT ERR

	info "Setting up ArgoCD repository access via Kubernetes Secret..."

	# Check if repository secret already exists
	if kubectl get secret -n argocd pn-infra &>/dev/null; then
		log "Repository secret already exists in ArgoCD"
		return 0
	fi

	# Check if secret file exists
	if [[ ! -f "$repo_secret_file" ]]; then
		error "Repository secret file not found: $repo_secret_file"
		return 1
	fi

	# Prompt for GitHub token (masked input)
	echo
	info "🔑 GitHub Token required for private repository access"
	echo "   Repository: https://github.com/pnow-devsupreme/pn-infra.git"
	echo "   The token needs 'repo' scope permissions"
	echo

	while true; do
		read -r -s -p "Enter your GitHub Personal Access Token (input hidden): " REPO_TOKEN
		echo

		if [[ -z "$REPO_TOKEN" ]]; then
			error "Token cannot be empty"
			continue
		fi

		# Validate token format (basic check)
		if [[ ! "$REPO_TOKEN" =~ ^ghp_[a-zA-Z0-9]{36}$ ]] && [[ ! "$REPO_TOKEN" =~ ^github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}$ ]]; then
			warn "Token format doesn't match GitHub PAT patterns (ghp_... or github_pat_...)"
			read -p "Continue anyway? (y/N): " -n 1 -r
			echo
			if [[ ! $REPLY =~ ^[Yy]$ ]]; then
				continue
			fi
		fi

		# Validate token against GitHub API
		info "Validating GitHub token..."
		local validation_result
		validation_result=$(curl -s -H "Authorization: Bearer $REPO_TOKEN" \
			-H "Accept: application/vnd.github.v3+json" \
			"https://api.github.com/user" 2>/dev/null | grep -E '"login"|"message"' || echo "invalid")

		if echo "$validation_result" | grep -q '"login"'; then
			local github_user
			github_user=$(echo "$validation_result" | grep '"login"' | cut -d'"' -f4)
			log "Token validated successfully! GitHub user: $github_user"
			break
		elif echo "$validation_result" | grep -q '"message"'; then
			local error_msg
			error_msg=$(echo "$validation_result" | grep '"message"' | cut -d'"' -f4)
			error "Token validation failed: $error_msg"
		else
			error "Token validation failed: Cannot connect to GitHub API"
			read -p "Continue without validation? (not recommended) (y/N): " -n 1 -r
			echo
			if [[ ! $REPLY =~ ^[Yy]$ ]]; then
				continue
			else
				warn "Proceeding with unvalidated token"
				break
			fi
		fi
	done

	# Create temporary file with actual token
	temp_secret_file=$(mktemp)
	sed "s/TOKEN_PLACEHOLDER/$REPO_TOKEN/g" "$repo_secret_file" >"$temp_secret_file"

	# Wait for ArgoCD namespace to be ready
	info "Waiting for ArgoCD components to be ready..."
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s || {
		warn "ArgoCD server not fully ready, but continuing with repository setup..."
	}
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=120s || {
		warn "ArgoCD application controller not fully ready, but continuing with repository setup..."
	}
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=120s || {
		warn "ArgoCD repo server not fully ready, but continuing with repository setup..."
	}

	# Apply the repository secret
	info "Applying repository secret to ArgoCD..."
	if kubectl apply -f "$temp_secret_file"; then
		log "Repository secret successfully applied to ArgoCD"

		# Wait for repository connection
		info "Waiting for repository connection to be established..."
		local max_attempts=30
		local attempt=1

		while [[ $attempt -le $max_attempts ]]; do
			# Check if the secret has the ArgoCD repository label
			local secret_type=$(kubectl get secret -n argocd pn-infra -o json 2>/dev/null | jq -r '.metadata.labels["argocd.argoproj.io/secret-type"] // empty')

			if [[ "$secret_type" == "repository" ]]; then
				log "Repository connection established (secret labeled correctly)"
				# Clean up temporary file
				rm -f "$temp_secret_file"
				return 0
			fi

			if [[ $attempt -eq $max_attempts ]]; then
				warn "Repository secret applied but connection status unknown"
				info "ArgoCD should pick up the repository shortly"
				# Clean up temporary file
				rm -f "$temp_secret_file"
				return 0
			fi

			info "Waiting for repository connection... (attempt $attempt/$max_attempts)"
			sleep 2
			((attempt++))
		done

	else
		error "Failed to apply repository secret"
		rm -f "$temp_secret_file"
		return 1
	fi
}

setup_argocd_projects() {
	local argo_projects_file="${SCRIPT_DIR}/projects"

	info "Setting up ArgoCD projects via Kustomization..."

	# Check if project already exists
	if kubectl get AppProject -n argocd platform &>/dev/null; then
		log "Argo Project already exists in ArgoCD"
		return 0
	fi

	# Check if secret file exists
	if [[ ! -f "$argo_projects_file/kustomization.yaml" ]]; then
		error "Projects Kustomization file not found: $argo_projects_file"
		return 1
	fi

	# Apply the repository secret
	info "Applying Argo Project to ArgoCD..."
	if kubectl apply -k "$argo_projects_file"; then
		log "Argo Project successfully created in ArgoCD"
		return 0
	else
		error "Failed to create Argo Project successfully"
		return 1
	fi
}

# Main
main() {
	log "🚀 Starting ArgoCD installation (${ENVIRONMENT})..."

	check_prerequisites
	install_argocd
	wait_for_argocd
	setup_argocd_repository
	setup_argocd_projects
	print_argo_success

	log "✅ ArgoCD installation and repository setup completed!"
}

main "$@"
