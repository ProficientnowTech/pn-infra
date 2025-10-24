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

# Deploy ArgoCD if not present
deploy_argocd() {
	log_info "Checking ArgoCD deployment..."

	# Check if ArgoCD is actually deployed by checking for CRDs and server deployment
	if kubectl get crd applications.argoproj.io >/dev/null 2>&1 && kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
		log_success "ArgoCD already deployed"
	else
		log_info "Deploying ArgoCD..."
		if [[ -x "${SCRIPT_DIR}/bootstrap/install-argo.sh" ]]; then
			# Pass SSH key path to install script if provided
			if [[ -n "$SSH_PRIVATE_KEY_PATH" && -f "$SSH_PRIVATE_KEY_PATH" ]]; then
				log_info "Using SSH key: $SSH_PRIVATE_KEY_PATH"
				SSH_PRIVATE_KEY_PATH="$SSH_PRIVATE_KEY_PATH" "${SCRIPT_DIR}/bootstrap/install-argo.sh"
			else
				log_warning "No SSH key provided or key not found - private repo access may not work"
				"${SCRIPT_DIR}/bootstrap/install-argo.sh"
			fi
		else
			log_error "Bootstrap script not found or not executable"
			return 1
		fi
	fi
}

# Check application health status
check_applications_health() {
	log_info "Checking application health status..."
	echo

	local max_attempts=30 # 30 seconds
	local attempt=1

	while [[ $attempt -le $max_attempts ]]; do
		# Get all applications with their health and sync status
		local apps_data=$(kubectl get applications -n argocd -o json 2>/dev/null)

		if [[ -z "$apps_data" || "$apps_data" == "{}" ]]; then
			echo -ne "\r${YELLOW}[${attempt}/${max_attempts}s]${NC} Waiting for applications to be created...                              "
			sleep 1
			((attempt++))
			continue
		fi

		# Parse application statuses
		local total_apps=$(echo "$apps_data" | jq -r '.items | length')
		local healthy_apps=$(echo "$apps_data" | jq -r '[.items[] | select(.status.health.status == "Healthy")] | length')
		local synced_apps=$(echo "$apps_data" | jq -r '[.items[] | select(.status.sync.status == "Synced")] | length')
		local progressing_apps=$(echo "$apps_data" | jq -r '[.items[] | select(.status.sync.status == "OutOfSync" or .status.operationState.phase == "Running")] | length')
		local degraded_apps=$(echo "$apps_data" | jq -r '[.items[] | select(.status.health.status == "Degraded")] | length')
		local missing_apps=$(echo "$apps_data" | jq -r '[.items[] | select(.status.health.status == "Missing")] | length')

		# Build status line with colors
		local status_line="${BLUE}[${attempt}/${max_attempts}s]${NC} Apps: ${total_apps} | "
		status_line+="${GREEN}Healthy: ${healthy_apps}${NC} | "
		status_line+="${GREEN}Synced: ${synced_apps}${NC}"

		if [[ $progressing_apps -gt 0 ]]; then
			status_line+=" | ${YELLOW}Progressing: ${progressing_apps}${NC}"
		fi

		if [[ $degraded_apps -gt 0 ]]; then
			status_line+=" | ${RED}Degraded: ${degraded_apps}${NC}"
		fi

		if [[ $missing_apps -gt 0 ]]; then
			status_line+=" | ${RED}Missing: ${missing_apps}${NC}"
		fi

		# Print status (overwrite previous line)
		echo -ne "\r${status_line}                                        "

		# Check if all applications are healthy and synced
		if [[ $healthy_apps -eq $total_apps && $synced_apps -eq $total_apps && $total_apps -gt 0 ]]; then
			echo -e "\n"
			log_success "All ${total_apps} applications are healthy and synced!"
			echo

			# Show final application list
			log_info "Application Status:"
			kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,MESSAGE:.status.conditions[0].message 2>/dev/null || true

			return 0
		fi

		# Check for failed applications
		if [[ $degraded_apps -gt 0 || $missing_apps -gt 0 ]]; then
			if [[ $attempt -ge 15 ]]; then # After 15 seconds, warn about issues
				echo -e "\n"
				log_warning "Some applications are not healthy after ${attempt} seconds"

				# Show problematic applications
				echo
				log_info "Problematic Applications:"
				kubectl get applications -n argocd -o json |
					jq -r '.items[] | select(.status.health.status != "Healthy" or .status.sync.status != "Synced") |
					"\(.metadata.name): Health=\(.status.health.status // "Unknown"), Sync=\(.status.sync.status // "Unknown")"' 2>/dev/null || true
				echo
			fi
		fi

		sleep 1
		((attempt++))
	done

	# Timeout reached
	echo -e "\n"
	log_warning "Health check timed out after ${max_attempts} seconds"
	echo

	# Show final status
	log_info "Current Application Status:"
	kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || log_warning "Cannot retrieve application status"

	echo
	log_info "Some applications may still be syncing. Check status with:"
	echo "  kubectl get applications -n argocd"
	echo "  kubectl get applications -n argocd <app-name> -o yaml"

	return 1
}

# Deploy platform applications
deploy_platform_applications() {
	log_info "Deploying platform applications for environment: $ENVIRONMENT"

	# Check if cluster is ready
	if ! kubectl cluster-info >/dev/null 2>&1; then
		log_error "Cannot connect to Kubernetes cluster"
		return 1
	fi

	# Deploy ArgoCD first
	deploy_argocd

	# Wait for ArgoCD to be ready
	log_info "Waiting for ArgoCD to be ready..."
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout="$ARGO_TIMEOUT" || {
		log_warning "ArgoCD server not ready within timeout"
	}

	# Apply platform root application
	local bootstrap_app="${SCRIPT_DIR}/bootstrap/platform-root.yaml"
	if [[ -f "$bootstrap_app" ]]; then
		log_info "Applying platform root application..."
		kubectl apply -f "$bootstrap_app"
		log_success "Platform applications deployment initiated"
		echo

		# Wait a moment for ArgoCD to process the application
		log_info "Waiting for ArgoCD to process applications..."
		sleep 5

		# Check application health
		check_applications_health
	else
		log_error "Bootstrap application not found"
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
