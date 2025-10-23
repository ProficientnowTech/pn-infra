#!/usr/bin/env bash

# Platform Deployment Controller
# Entry point for platform validation and deployment operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SCRIPT="${SCRIPT_DIR}/validate.sh"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
OPERATION=""
SKIP_VALIDATION=""
ENVIRONMENT="production"
SSH_PRIVATE_KEY_PATH="$HOME/.ssh/github_keys"

log_info() {
	echo -e "${BLUE}[INFO]    [$(date +'%H:%M:%S')] [Orchestrator]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS] [$(date +'%H:%M:%S')] [Orchestrator]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARN]    [$(date +'%H:%M:%S')] [Orchestrator]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]   [$(date +'%H:%M:%S')] [Orchestrator]${NC} $1"
}

usage() {
	cat <<EOF
Usage: $0 [OPERATION] [OPTIONS]

OPERATIONS:
    validate        Run platform validation only
    deploy          Deploy platform applications (includes validation)
    reset           Reset platform (remove all platform applications and ArgoCD)
    setup-secrets   Setup required secrets (Cloudflare, etc.)
    status          Check platform deployment status

OPTIONS:
    --skip-validation       Skip validation (EMERGENCY USE ONLY)
    --env ENVIRONMENT       Environment (production|staging|development)
    -h, --help             Show this help

EXAMPLES:
    $0 validate                    # Run platform validation
    $0 deploy                      # Validate then deploy platform
    $0 reset                       # Reset platform (remove all apps and ArgoCD)
    $0 setup-secrets               # Setup required secrets only
    $0 deploy --env staging        # Deploy staging environment
    $0 status                      # Check platform status
EOF
}

run_validation() {
	if [[ ! -x "$VALIDATE_SCRIPT" ]]; then
		log_error "Platform validation script not found: $VALIDATE_SCRIPT"
		return 1
	fi

	log_info "Running platform validation..."
	"$VALIDATE_SCRIPT" "$ENVIRONMENT"
}

setup_required_secrets() {
	log_info "Checking and setting up required secrets..."

	# Check if cluster is accessible
	if ! kubectl cluster-info >/dev/null 2>&1; then
		log_warning "Cluster not accessible - skipping secret setup"
		return 0
	fi

	echo
	echo "🔐 Setting up required secrets for platform services..."
	echo "   You can skip any secret setup by typing 'skip'"
	echo

	# Setup Cloudflare API token for cert-manager
	setup_cloudflare_secret || {
		log_error "Failed to setup required secrets"
		return 1
	}

	# Setup additional secrets as needed
	# setup_slack_webhook_secret

	echo
	log_success "Secret setup completed!"
}

setup_cloudflare_secret() {
	local secret_name="cloudflare-api-token"
	local namespace="cert-manager"

	# Check if secret already exists
	if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
		log_success "Cloudflare API token secret already exists"
		return 0
	fi

	log_info "Cloudflare API token secret not found in namespace: $namespace"
	echo
	echo "🔑 Cert-Manager requires a Cloudflare API token for DNS01 challenges."
	echo "   The token needs the following permissions:"
	echo "   - Zone:Zone:Read"
	echo "   - Zone:DNS:Edit"
	echo "   - Include: All zones"
	echo

	# Prompt for API token and validate
	if [[ ! "$cloudflare_token" =~ ^[a-zA-Z0-9_-]{40,}$ ]]; then
		log_warning "Token format looks invalid (should be 40+ alphanumeric characters)"
		read -p "Continue anyway? (y/N): " -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && return 0
	fi

	if [[ "$cloudflare_token" == "skip" || -z "$cloudflare_token" ]]; then
		log_warning "Skipping Cloudflare secret creation - cert-manager may not work properly"
		return 0
	fi

	# Create namespace if it doesn't exist
	kubectl create namespace "$namespace" >/dev/null 2>&1 || true

	# Create the secret
	if kubectl create secret generic "$secret_name" \
		--from-literal=api-token="$cloudflare_token" \
		-n "$namespace" >/dev/null 2>&1; then
		log_success "Cloudflare API token secret created successfully"
	else
		log_error "Failed to create Cloudflare API token secret"
		return 1
	fi
}

setup_ssh_private_key_secret() {
	local secret_name="argocd-private-repo"
	local namespace="argocd"

	# Check if secret already exists
	if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
		log_success "SSH private key secret already exists"
		return 0
	fi

	log_info "SSH private key secret not found in namespace: $namespace"
	echo
	echo "🔑 ArgoCD requires an SSH private key to access private Git repositories."
	echo "   The key should have read access to your private repository."
	echo

	local ssh_key_path=""

	# Use provided SSH key path if available
	if [[ -n "$SSH_PRIVATE_KEY_PATH" && -f "$SSH_PRIVATE_KEY_PATH" ]]; then
		ssh_key_path="$SSH_PRIVATE_KEY_PATH"
		log_info "Using provided SSH key: $ssh_key_path"
	else
		# Try default locations
		local default_keys=(
			"$HOME/.ssh/id_rsa"
			"$HOME/.ssh/id_ed25519"
			"$HOME/.ssh/github_rsa"
		)

		for key in "${default_keys[@]}"; do
			if [[ -f "$key" ]]; then
				ssh_key_path="$key"
				log_info "Found SSH key at default location: $ssh_key_path"
				break
			fi
		done

		# Prompt if no key found
		if [[ -z "$ssh_key_path" ]]; then
			read -p "Enter the path to your SSH private key (or 'skip' to continue without): " ssh_key_path
			if [[ "$ssh_key_path" == "skip" || -z "$ssh_key_path" ]]; then
				log_warning "Skipping SSH secret creation - private repos may not be accessible"
				return 0
			fi
		fi
	fi

	# Expand path (handle ~)
	ssh_key_path="${ssh_key_path/#\~/$HOME}"

	if [[ ! -f "$ssh_key_path" ]]; then
		log_error "SSH private key not found at: $ssh_key_path"
		return 1
	fi

	# Create namespace if it doesn't exist
	kubectl create namespace "$namespace" >/dev/null 2>&1 || true

	# Create the repository secret with proper ArgoCD format
	if kubectl create secret generic "$secret_name" \
		--from-literal=type=git \
		--from-literal=url=git@github.com:pnow-devsupreme/pn-infra.git \
		--from-file=sshPrivateKey="$ssh_key_path" \
		-n "$namespace" >/dev/null 2>&1; then
		log_success "SSH private key secret created successfully"

		# Label the secret for ArgoCD
		kubectl label secret "$secret_name" \
			--namespace "$namespace" \
			argocd.argoproj.io/secret-type=repository \
			--overwrite >/dev/null 2>&1
	else
		log_error "Failed to create SSH private key secret"
		return 1
	fi
}

update_configuration_values() {
	log_info "Checking configuration values..."

	# Check if important values need to be updated
	local needs_update=false

	# Check cert-manager email configuration
	if grep -q "admin@example.com" "$SCRIPT_DIR/charts/cert-manager/values.yaml" 2>/dev/null; then
		echo
		log_warning "⚠️  Cert-Manager is using default email (admin@example.com)"
		echo "   This should be updated to your actual email address for Let's Encrypt notifications."
		echo "   File: charts/cert-manager/values.yaml"
		needs_update=true
	fi

	# Check MetalLB IP configuration
	if grep -q "192.168.102.50-192.168.102.80" "$SCRIPT_DIR/charts/metallb/values.yaml" 2>/dev/null; then
		echo
		log_warning "⚠️  MetalLB is using default IP range (192.168.102.50-80)"
		echo "   This should be updated to match your network's available IP range."
		echo "   File: charts/metallb/values.yaml"
		needs_update=true
	fi

	if [[ "$needs_update" == "true" ]]; then
		echo
		echo "📝 Please review and update the configuration files mentioned above"
		echo "   before deploying to production. You can continue for now, but"
		echo "   some services may not work properly with default values."
		echo
		read -p "Continue with deployment? (y/N): " continue_deploy
		if [[ ! "$continue_deploy" =~ ^[Yy]$ ]]; then
			log_info "Deployment cancelled by user"
			exit 0
		fi
	fi
}

run_deployment() {
	if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
		log_error "Platform deployment script not found: $DEPLOY_SCRIPT"
		return 1
	fi

	# Setup secrets and check configuration before deployment
	setup_cloudflare_secret || {
		log_error "Failed to setup required secrets"
		return 1
	}
	update_configuration_values

	log_info "Starting platform deployment for environment: $ENVIRONMENT"
	# Pass SSH key path if available
	if [[ -n "$SSH_PRIVATE_KEY_PATH" && -f "$SSH_PRIVATE_KEY_PATH" ]]; then
		SSH_PRIVATE_KEY_PATH="$SSH_PRIVATE_KEY_PATH" "$DEPLOY_SCRIPT" deploy "$ENVIRONMENT"
	else
		"$DEPLOY_SCRIPT" deploy "$ENVIRONMENT"
	fi
}

enforce_validation() {
	local operation="$1"

	if [[ "$SKIP_VALIDATION" == "true" ]]; then
		log_warning "⚠️  PLATFORM VALIDATION SKIPPED - Emergency mode"
		return 0
	fi

	log_info "Platform validation required before $operation"
	if run_validation; then
		log_success "Platform validation passed - proceeding with $operation"
	else
		log_error "Platform validation failed - $operation aborted"
		exit 1
	fi
}

reset_platform() {
	log_warning "🔥 PLATFORM RESET - This will remove ALL platform applications and ArgoCD"
	echo
	echo "This will delete:"
	echo "  ✗ All ArgoCD applications (MetalLB, Ingress-NGINX, Cert-Manager, External-DNS, ArgoCD-Self)"
	echo "  ✗ ArgoCD server and CRDs"
	echo "  ✗ All platform secrets (Cloudflare API token, SSH keys)"
	echo "  ✗ All platform namespaces and configurations"
	echo
	log_warning "This is DESTRUCTIVE and cannot be undone!"
	echo

	read -p "Type 'RESET' to confirm platform reset: " -r
	if [[ "$REPLY" != "RESET" ]]; then
		log_info "Platform reset cancelled"
		return 0
	fi

	echo
	log_info "🚀 Starting platform reset..."

	# Check cluster connectivity
	if ! kubectl cluster-info >/dev/null 2>&1; then
		log_error "Cannot connect to Kubernetes cluster"
		return 1
	fi

	# Remove platform applications first (if ArgoCD exists)
	reset_platform_applications

	# Remove ArgoCD completely
	reset_argocd

	# Remove platform secrets
	reset_platform_secrets

	# Remove platform namespaces
	reset_platform_namespaces

	log_success "🎉 Platform reset completed!"
}

reset_platform_applications() {
	log_info "Removing platform applications..."

	# Check if ArgoCD namespace exists
	if ! kubectl get namespace argocd >/dev/null 2>&1; then
		log_info "ArgoCD namespace not found - skipping application cleanup"
		return 0
	fi

	# Get all ArgoCD applications dynamically
	local all_apps
	all_apps=$(kubectl get applications -n argocd --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")

	if [[ -z "$all_apps" ]]; then
		log_info "No ArgoCD applications found"
		return 0
	fi

	log_info "Found $(echo "$all_apps" | wc -l) ArgoCD applications to remove"

	# Remove finalizers and delete applications one by one
	while IFS= read -r app; do
		if [[ -n "$app" ]]; then
			log_info "Processing application: $app"

			# Check if application has finalizers
			local finalizers
			finalizers=$(kubectl get application "$app" -n argocd -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "")

			if [[ -n "$finalizers" && "$finalizers" != "[]" ]]; then
				log_info "Removing finalizers from application: $app"
				kubectl patch application "$app" -n argocd --type='merge' -p='{"metadata":{"finalizers":[]}}' || true
			fi

			# Delete the application
			log_info "Deleting application: $app"
			kubectl delete application "$app" -n argocd --timeout=60s || true
		fi
	done <<<"$all_apps"

	# Verify all applications are deleted
	verify_applications_deleted
}

verify_applications_deleted() {
	log_info "Verifying all applications are deleted..."

	local max_attempts=30
	local attempt=1

	while [[ $attempt -le $max_attempts ]]; do
		local remaining_apps
		remaining_apps=$(kubectl get applications -n argocd --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")

		if [[ -z "$remaining_apps" ]]; then
			log_success "All applications successfully deleted"
			return 0
		fi

		local app_count
		app_count=$(echo "$remaining_apps" | grep -c . || echo "0")
		log_info "Waiting for $app_count applications to be deleted... (attempt $attempt/$max_attempts)"

		if [[ $attempt -eq $max_attempts ]]; then
			log_warning "Some applications still remain after $max_attempts attempts:"
			echo "$remaining_apps" | while read -r app; do
				[[ -n "$app" ]] && log_warning "  - $app"
			done
			log_warning "Proceeding with namespace cleanup anyway..."
			break
		fi

		sleep 5
		((attempt++))
	done
}

reset_argocd() {
	log_info "Removing ArgoCD installation..."

	# Remove ArgoCD Helm release if it exists
	if helm list -n argocd | grep -q argocd; then
		log_info "Uninstalling ArgoCD Helm release..."
		helm uninstall argocd -n argocd --timeout=300s || true
	fi

	# Remove ArgoCD CRDs (this will remove all applications)
	local crds=(
		"applications.argoproj.io"
		"applicationsets.argoproj.io"
		"appprojects.argoproj.io"
	)

	for crd in "${crds[@]}"; do
		if kubectl get crd "$crd" >/dev/null 2>&1; then
			log_info "Removing CRD: $crd"
			kubectl delete crd "$crd" --timeout=60s || true
		fi
	done

	# Force remove ArgoCD namespace if it still exists
	if kubectl get namespace argocd >/dev/null 2>&1; then
		log_info "Force removing ArgoCD namespace..."
		kubectl delete namespace argocd --force --grace-period=0 --timeout=120s || true
	fi
}

reset_platform_secrets() {
	log_info "Removing platform secrets..."

	# Remove Cloudflare API token secret
	if kubectl get secret cloudflare-api-token -n cert-manager >/dev/null 2>&1; then
		kubectl delete secret cloudflare-api-token -n cert-manager || true
		log_info "Removed Cloudflare API token secret"
	fi

	# Remove SSH repository secret (if ArgoCD namespace still exists)
	if kubectl get namespace argocd >/dev/null 2>&1; then
		if kubectl get secret argocd-private-repo -n argocd >/dev/null 2>&1; then
			kubectl delete secret argocd-private-repo -n argocd || true
			log_info "Removed SSH repository secret"
		fi
	fi
}

reset_platform_namespaces() {
	log_info "Removing platform namespaces..."

	local namespaces=("ingress-nginx" "cert-manager" "external-dns" "argocd")

	for ns in "${namespaces[@]}"; do
		if kubectl get namespace "$ns" >/dev/null 2>&1; then
			log_info "Processing namespace: $ns"

			# Check if namespace has finalizers
			local finalizers
			finalizers=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "")

			if [[ -n "$finalizers" && "$finalizers" != "[]" ]]; then
				log_info "Removing finalizers from namespace: $ns"
				kubectl patch namespace "$ns" --type='merge' -p='{"metadata":{"finalizers":[]}}' || true
			fi

			# Delete the namespace
			log_info "Deleting namespace: $ns"
			kubectl delete namespace "$ns" --timeout=120s || true
		fi
	done

	# Verify namespace deletion
	verify_namespaces_deleted "${namespaces[@]}"
}

verify_namespaces_deleted() {
	local namespaces=("$@")
	log_info "Verifying namespace deletion..."

	local max_attempts=24 # 2 minutes
	local attempt=1

	while [[ $attempt -le $max_attempts ]]; do
		local remaining_namespaces=()

		for ns in "${namespaces[@]}"; do
			if kubectl get namespace "$ns" >/dev/null 2>&1; then
				remaining_namespaces+=("$ns")
			fi
		done

		if [[ ${#remaining_namespaces[@]} -eq 0 ]]; then
			log_success "All platform namespaces successfully deleted"
			return 0
		fi

		log_info "Waiting for ${#remaining_namespaces[@]} namespaces to be deleted... (attempt $attempt/$max_attempts)"
		log_info "Remaining: ${remaining_namespaces[*]}"

		if [[ $attempt -eq $max_attempts ]]; then
			log_warning "Some namespaces still remain after $max_attempts attempts:"
			for ns in "${remaining_namespaces[@]}"; do
				log_warning "  - $ns ($(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo 'Unknown'))"
			done
			log_warning "You may need to manually investigate and clean up these namespaces"
			break
		fi

		sleep 5
		((attempt++))
	done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	validate | deploy | reset | setup-secrets | status)
		OPERATION="$1"
		shift
		;;
	--skip-validation)
		SKIP_VALIDATION="true"
		shift
		;;
	--env)
		ENVIRONMENT="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		log_error "Unknown option: $1"
		usage
		exit 1
		;;
	esac
done

# Default operation
[[ -z "$OPERATION" ]] && OPERATION="validate"

log_info "Operation: $OPERATION | Environment: $ENVIRONMENT"

# Execute operation
case $OPERATION in
validate)
	run_validation
	;;
deploy)
	enforce_validation "$OPERATION"
	run_deployment
	;;
reset)
	reset_platform
	;;
setup-secrets)
	setup_required_secrets
	;;
status)
	if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null; then
		log_info "Checking ArgoCD applications status..."
		kubectl get applications -n argocd 2>/dev/null || log_warning "ArgoCD not accessible"
	else
		log_warning "Cluster not accessible or kubectl not available"
	fi
	;;
*)
	log_error "Unknown operation: $OPERATION"
	usage
	exit 1
	;;
esac

log_success "Platform operation completed!"
