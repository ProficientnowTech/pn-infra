#!/usr/bin/env bash

# Platform Deployment Engine
# Deploys platform applications using ArgoCD

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATION="${1:-deploy}"
ENVIRONMENT="${2:-production}"
SSH_PRIVATE_KEY_PATH="${3:-$HOME/.ssh/github_keys}"
ARGO_TIMEOUT="${4:-300s}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
	echo -e "${BLUE}[INFO]    [$(date +'%H:%M:%S')] [Deployment Manager]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS] [$(date +'%H:%M:%S')] [Deployment Manager]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARN]    [$(date +'%H:%M:%S')] [Deployment Manager]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]   [$(date +'%H:%M:%S')] [Deployment Manager]${NC} $1"
}

# Check if resource exists and is ready
check_resource_ready() {
	local resource_type="$1"
	local resource_name="$2"
	local namespace="$3"

	if kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1; then
		if [[ "$resource_type" == "pod" ]]; then
			kubectl wait --for=condition=ready "pod/$resource_name" -n "$namespace" --timeout=30s >/dev/null 2>&1 && return 0
		else
			return 0
		fi
	fi
	return 1
}

# Create required secrets for platform
render_bootstrap_secrets() {
	local script="${SCRIPT_DIR}/bootstrap/scripts/render-secrets.sh"
	if [[ ! -x "$script" ]]; then
		log_error "Bootstrap secret renderer not found or not executable: $script"
		return 1
	fi
	log_info "Rendering bootstrap secrets from specs..."
	if "$script" --apply; then
		log_success "Bootstrap secrets rendered."
	else
		log_error "Failed to render bootstrap secrets."
		return 1
	fi
}
install_sealed_secrets() {
	log_info "Ensuring sealed-secrets controller is installed..."
	local script="${SCRIPT_DIR}/bootstrap/install-sealed-secrets.sh"

	if [[ ! -x "$script" ]]; then
		log_error "Sealed-secrets install script not found or not executable: $script"
		return 1
	fi

	if "$script"; then
		log_success "Sealed-secrets controller is ready."
	else
		log_error "Failed to install sealed-secrets controller."
		return 1
	fi
}

# Deploy ArgoCD if not present - OPTIMIZED VERSION
deploy_argocd() {
	log_info "Checking ArgoCD deployment..."

	# Fast check - if CRD and server deployment exist and are ready, skip deployment
	if check_resource_ready "crd" "applications.argoproj.io" "" &&
		check_resource_ready "deployment" "argocd-server" "argocd"; then
		log_success "ArgoCD already deployed and ready"
		return 0
	fi

	log_info "Deploying ArgoCD..."
	if [[ -x "${SCRIPT_DIR}/bootstrap/install-argo.sh" ]]; then
		# Run install script in background and immediately proceed to wait
		if [[ -n "$SSH_PRIVATE_KEY_PATH" && -f "$SSH_PRIVATE_KEY_PATH" ]]; then
			log_info "Using SSH key: $SSH_PRIVATE_KEY_PATH"
			SSH_PRIVATE_KEY_PATH="$SSH_PRIVATE_KEY_PATH" "${SCRIPT_DIR}/bootstrap/install-argo.sh" &
		else
			log_warning "No SSH key provided or key not found - private repo access may not work"
			"${SCRIPT_DIR}/bootstrap/install-argo.sh" &
		fi

		local install_pid=$!

		# Immediately proceed - don't wait for installation to complete
		log_info "ArgoCD installation started (PID: $install_pid), proceeding with platform setup..."

	else
		log_error "Bootstrap script not found or not executable"
		return 1
	fi
}

# Check application health status (optimized)
check_applications_health() {
	log_info "Checking application health status..."

	local max_attempts=45 # Reduced from 60
	local attempt=1
	local last_status=""

	while [[ $attempt -le $max_attempts ]]; do
		# Get applications data once per iteration
		local apps_data
		apps_data=$(kubectl get applications -n argocd -o json 2>/dev/null || echo "{}")

		if [[ "$apps_data" == "{}" || -z "$apps_data" ]]; then
			if [[ "$last_status" != "empty" ]]; then
				echo -e "\r${YELLOW}Waiting for applications to be created...${NC}                          "
				last_status="empty"
			fi
			sleep 2
			((attempt++))
			continue
		fi

		# Parse data efficiently
		local total_apps synced_apps healthy_apps progressing_apps
		total_apps=$(echo "$apps_data" | jq -r '.items | length')
		synced_apps=$(echo "$apps_data" | jq -r '[.items[] | select(.status.sync.status == "Synced")] | length')
		healthy_apps=$(echo "$apps_data" | jq -r '[.items[] | select(.status.health.status == "Healthy")] | length')
		progressing_apps=$(echo "$apps_data" | jq -r '[.items[] | select(.status.sync.status == "OutOfSync" or .status.operationState.phase == "Running")] | length')

		# Build status line
		local status_line="${BLUE}[${attempt}/${max_attempts}]${NC} Apps:${total_apps} ${GREEN}✓:${healthy_apps}/${synced_apps}${NC}"

		if [[ $progressing_apps -gt 0 ]]; then
			status_line+=" ${YELLOW}→:${progressing_apps}${NC}"
		fi

		# Update status line in place
		if [[ "$status_line" != "$last_status" ]]; then
			echo -ne "\r${status_line}                                  "
			last_status="$status_line"
		fi

		# Check completion
		if [[ $total_apps -gt 0 && $healthy_apps -eq $total_apps && $synced_apps -eq $total_apps ]]; then
			echo -e "\n"
			log_success "All ${total_apps} applications are healthy and synced!"
			return 0
		fi

		# Early exit if we're making progress but some apps take longer
		if [[ $attempt -gt 20 && $((healthy_apps + synced_apps)) -gt 0 ]]; then
			local completed=$(((healthy_apps + synced_apps) * 100 / (total_apps * 2)))
			if [[ $completed -gt 70 ]]; then
				echo -e "\n"
				log_success "${completed}% of applications healthy/synced - continuing..."
				return 0
			fi
		fi

		sleep 2
		((attempt++))
	done

	echo -e "\n"
	log_warning "Health check timed out"
	log_info "Current status:"
	kubectl get applications -n argocd --no-headers 2>/dev/null | head -10 || true
	return 0 # Don't fail deployment due to timeout
}

# Wait for ArgoCD to be ready
wait_for_argocd_ready() {
	log_info "Waiting for ArgoCD to be ready..."
	local max_wait=120
	local waited=0

	while [[ $waited -lt $max_wait ]]; do
		if kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=10s >/dev/null 2>&1; then
			log_success "ArgoCD is ready"
			return 0
		fi
		waited=$((waited + 10))
		log_info "Waiting for ArgoCD... (${waited}s/${max_wait}s)"
	done

	log_warning "ArgoCD not ready within ${max_wait}s, continuing anyway"
	return 0
}

# Deploy platform applications
deploy_platform_applications() {
	log_info "Deploying platform applications for environment: $ENVIRONMENT"

	# Check if cluster is ready
	if ! kubectl cluster-info >/dev/null 2>&1; then
		log_error "Cannot connect to Kubernetes cluster"
		return 1
	fi

	# Check if platform applications are already deployed
	if check_platform_deployed; then
		log_success "Platform applications are already deployed and healthy"
		show_status
		exit 0
	fi

	install_sealed_secrets
	render_bootstrap_secrets

	# Start ArgoCD deployment (non-blocking)
	deploy_argocd

	# Wait for ArgoCD to be ready (optimized wait)
	wait_for_argocd_ready

	# Apply platform root application
	local bootstrap_app="${SCRIPT_DIR}/bootstrap/platform-root.yaml"
	if [[ -f "$bootstrap_app" ]]; then
		log_info "Applying platform root application..."
		kubectl apply -f "$bootstrap_app"
		log_success "Platform applications deployment initiated"

		# Brief pause for ArgoCD to start processing
		sleep 3

		# Check application health (non-blocking, won't fail deployment)
		check_applications_health
	else
		log_error "Bootstrap application not found: $bootstrap_app"
		return 1
	fi
}

deploy_argocd_projects() {
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

# Check if platform applications are already deployed and healthy
check_platform_deployed() {
	log_info "Checking if platform applications are already deployed..."

	# Check if S3 backup secret exists (indicates previous deployment)
	if kubectl get secret postgres-backup-credentials -n postgres-operator >/dev/null 2>&1; then
		log_info "S3 backup secret exists - platform has been deployed before"
	fi

	# Check if ArgoCD has any applications
	if ! kubectl get applications -n argocd >/dev/null 2>&1; then
		log_info "No ArgoCD applications found - platform not deployed"
		return 1
	fi

	local apps_data
	apps_data=$(kubectl get applications -n argocd -o json 2>/dev/null || echo "{}")

	if [[ "$apps_data" == "{}" ]]; then
		log_info "No applications in ArgoCD - platform not deployed"
		return 1
	fi

	local total_apps
	total_apps=$(echo "$apps_data" | jq -r '.items | length')

	if [[ $total_apps -eq 0 ]]; then
		log_info "Zero applications found - platform not deployed"
		return 1
	fi

	# Check if core platform applications exist and are healthy
	local core_apps=("ingress-nginx" "cert-manager" "external-dns" "argocd-self" "rook-ceph")
	local found_apps=0
	local healthy_apps=0

	for app in "${core_apps[@]}"; do
		if kubectl get application "$app" -n argocd >/dev/null 2>&1; then
			((found_apps++))
			local app_status
			app_status=$(kubectl get application "$app" -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
			if [[ "$app_status" == "Synced/Healthy" ]]; then
				((healthy_apps++))
			fi
		fi
	done

	# Consider platform deployed if we find at least 3 core apps and majority are healthy
	if [[ $found_apps -ge 3 ]]; then
		local health_percent=$((healthy_apps * 100 / found_apps))
		log_info "Found $found_apps/$health_percent% core applications healthy"

		if [[ $health_percent -ge 80 ]]; then
			log_success "Platform is already deployed and healthy ($health_percent% of core apps)"
			return 0
		else
			log_warning "Platform is deployed but only $health_percent% healthy - may need remediation"
			return 0 # Still consider it deployed
		fi
	else
		log_info "Insufficient core applications found ($found_apps) - platform not fully deployed"
		return 1
	fi

}

# Check if specific application exists and is healthy
check_app_healthy() {
	local app_name="$1"
	local namespace="${2:-argocd}"

	if kubectl get application "$app_name" -n "$namespace" >/dev/null 2>&1; then
		local sync_status health_status
		sync_status=$(kubectl get application "$app_name" -n "$namespace" -o jsonpath='{.status.sync.status}' 2>/dev/null)
		health_status=$(kubectl get application "$app_name" -n "$namespace" -o jsonpath='{.status.health.status}' 2>/dev/null)

		if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
			return 0
		else
			log_warning "Application $app_name status: Sync=$sync_status, Health=$health_status"
			return 1
		fi
	else
		return 1
	fi
}

# Show deployment status
show_status() {
	log_info "Platform deployment status:"

	if ! kubectl cluster-info >/dev/null 2>&1; then
		log_error "Cannot connect to cluster"
		return 1
	fi

	# Show ArgoCD applications
	if kubectl get namespace argocd >/dev/null 2>&1; then
		echo
		log_info "ArgoCD Applications:"
		kubectl get applications -n argocd 2>/dev/null || log_warning "No applications found"

		echo
		log_info "ArgoCD Pods:"
		kubectl get pods -n argocd

		# Show repository status
		echo
		log_info "ArgoCD Repository Status:"
		kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository 2>/dev/null || log_warning "No repository secrets found"
	else
		log_warning "ArgoCD not deployed"
	fi
}

# Main execution
case $OPERATION in
deploy)
	deploy_platform_applications
	;;
status)
	show_status
	;;
*)
	log_error "Unknown operation: $OPERATION"
	exit 1
	;;
esac

log_success "Platform deployment operation completed!"
