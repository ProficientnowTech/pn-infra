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
create_platform_secrets() {
	log_info "Creating platform secrets..."

	# Create namespaces if they don't exist
	local namespaces=("postgres-operator" "platform-secrets")
	for ns in "${namespaces[@]}"; do
		if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
			kubectl create namespace "$ns" || log_warning "Namespace $ns already exists"
		fi
	done

	# Deploy secrets using Kustomize
	deploy_platform_secrets
}

deploy_platform_secrets() {
	log_info "Deploying platform secrets..."

	local secrets_dir="${SCRIPT_DIR}/bootstrap/secrets"

	if [[ ! -d "$secrets_dir" ]]; then
		log_error "Secrets directory not found: $secrets_dir"
		return 1
	fi

	# Check if secret environment file exists and has values
	local env_file="postgres-backup-credentials.env"
	local env_path="${secrets_dir}/${env_file}"

	if [[ ! -f "$env_path" ]]; then
		log_warning "Secret environment file not found: $env_file"
		log_info "Creating template environment file..."
		cat >"$env_path" <<EOF
# S3 Backup Credentials for Zalando Postgres Operator
# Fill in these values before deployment

# AWS Access Key for S3 backups
AWS_ACCESS_KEY_ID=

# AWS Secret Key for S3 backups
AWS_SECRET_ACCESS_KEY=

# AWS Region for S3 bucket
AWS_REGION=us-east-1

# S3 Bucket name for backups
AWS_S3_BUCKET=

# KMS Key ID for encryption (DSSE-KMS key)
AWS_KMS_KEY_ID=

# KMS Key ID for signing (optional)
AWS_KMS_SIGNING_KEY_ID=
EOF
		log_warning "Please fill in ${env_path} with your AWS credentials and redeploy"
		return 1
	fi

	# Check for empty values
	local missing_vars=0
	local required_vars=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_S3_BUCKET")

	for var in "${required_vars[@]}"; do
		local value=$(grep "^${var}=" "$env_path" | cut -d'=' -f2- | tr -d '[:space:]')
		if [[ -z "$value" ]]; then
			log_warning "Required variable $var is empty in $env_file"
			((missing_vars++))
		fi
	done

	if [[ $missing_vars -gt 0 ]]; then
		log_error "$missing_vars required secret values are empty"
		log_info "Please fill in the following required variables in ${env_path}:"
		for var in "${required_vars[@]}"; do
			local value=$(grep "^${var}=" "$env_path" | cut -d'=' -f2- | tr -d '[:space:]')
			if [[ -z "$value" ]]; then
				log_info "  - $var"
			fi
		done
		return 1
	fi

	# Deploy secrets using kustomize
	log_info "Applying S3 backup secrets to cluster..."
	if kubectl apply -k "$secrets_dir"; then
		log_success "S3 backup secrets deployed successfully"
	else
		log_error "Failed to deploy S3 backup secrets"
		return 1
	fi

	# Verify secret was created
	log_info "Verifying secret creation..."
	if kubectl get secret postgres-backup-credentials -n postgres-operator >/dev/null 2>&1; then
		log_success "✓ Secret postgres-backup-credentials created in postgres-operator namespace"

		# Show secret metadata (without revealing values)
		log_info "Secret details:"
		kubectl get secret postgres-backup-credentials -n postgres-operator -o jsonpath='{.metadata.name}{" created at "}{.metadata.creationTimestamp}{"\n"}' 2>/dev/null || true
	else
		log_error "✗ Secret postgres-backup-credentials missing in postgres-operator namespace"
		return 1
	fi
}

# Deploy ArgoCD if not present
deploy_argocd_old() {
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

# Check application health status
check_applications_health_old() {
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

# Deploy platform applications
deploy_platform_applications_old() {
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

	# Create platform secrets first
	create_platform_secrets

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
		kubectl get applications -n argocd 2>/dev/null | head -20 || log_warning "No applications found"

		# Show secret status
		echo
		log_info "Platform Secrets:"
		local secrets=("postgres-backup-credentials" "infisical-secrets")
		for secret in "${secrets[@]}"; do
			if kubectl get secret "$secret" -n "${secret##*-}" >/dev/null 2>&1; then
				echo -e "  ${GREEN}✓${NC} $secret"
			else
				echo -e "  ${RED}✗${NC} $secret"
			fi
		done
	else
		log_warning "ArgoCD not deployed"
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
create-secrets)
	create_platform_secrets
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
