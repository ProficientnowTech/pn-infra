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

render_bootstrap_secrets() {
	local script="${SCRIPT_DIR}/bootstrap/scripts/render-secrets.sh"
	if [[ ! -x "$script" ]]; then
		log_error "Bootstrap secret renderer not found: $script"
		return 1
	fi
	log_info "Rendering sealed secrets from specs..."
	"$script" --apply
}

usage() {
	cat <<EOF
Usage: $0 [OPERATION] [OPTIONS]

OPERATIONS:
    validate        Run platform validation only
    deploy          Deploy platform applications (includes validation)
    reset           Reset platform (remove all platform applications and ArgoCD)
    setup-secrets   Render and apply bootstrap sealed secrets
    status          Check platform deployment status

OPTIONS:
    --skip-validation       Skip validation (EMERGENCY USE ONLY)
    --env ENVIRONMENT       Environment (production|staging|development)
    -h, --help             Show this help

EXAMPLES:
    $0 validate                    # Run platform validation
    $0 deploy                      # Validate then deploy platform
    $0 reset                       # Reset platform (remove all apps and ArgoCD)
    $0 setup-secrets               # Render bootstrap sealed secrets only
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


run_deployment() {
	if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
		log_error "Platform deployment script not found: $DEPLOY_SCRIPT"
		return 1
	fi

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
	log_info "Calling platform reset script..."

	# Path to reset script
	local reset_script="${SCRIPT_DIR}/reset.sh"

	# Check if reset script exists
	if [[ ! -f "$reset_script" ]]; then
		log_error "Reset script not found at: $reset_script"
		return 1
	fi

	# Make script executable if not already
	chmod +x "$reset_script"

	# Call reset script with light mode flag (default behavior)
	# For full reset with Ceph wipe, user should call reset.sh directly
	bash "$reset_script" --light
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
	render_bootstrap_secrets
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
