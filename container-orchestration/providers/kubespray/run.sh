#!/usr/bin/env bash

# Master Deployment Controller
# Entry point for all deployment and validation operations

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
FORCE_VALIDATION=""
ENVIRONMENT="${ENVIRONMENT:-development}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[SUCCESS] [$(date +'%H:%M:%S')] [Cluster Orchestrator] $1${NC}"; }
info() { echo -e "${BLUE}[INFO]    [$(date +'%H:%M:%S')] [Cluster Orchestrator] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN]    [$(date +'%H:%M:%S')] [Cluster Orchestrator] $1${NC}"; }
error() { echo -e "${RED}[ERROR]   [$(date +'%H:%M:%S')] [Cluster Orchestrator] $1${NC}"; }

usage() {
	cat <<EOF
Usage: $0 [OPERATION] [OPTIONS]

OPERATIONS:
    validate        Run validation only
    deploy          Deploy cluster (includes validation)
    reset           Reset cluster (includes validation)
    upgrade         Upgrade cluster (includes validation)
    scale           Scale cluster (includes validation)
    recover         Recover control plane (includes validation)
    facts           Gather cluster facts
    status          Check deployment status
    shell           Open interactive shell
    
OPTIONS:
    --skip-validation       Skip validation (EMERGENCY USE ONLY)
    --force-validation      Force fresh validation
    --env NAME              Environment identifier (default: development)
    -v, --verbose          Enable verbose output
    -n, --dry-run          Perform a dry run
    -f, --force-pull       Force pull Docker image
    -l, --limit HOSTS      Limit execution to specific hosts
    -e, --extra ARGS       Pass additional arguments
    -h, --help             Show this help

EXAMPLES:
    $0 validate                    # Run validation only
    $0 deploy                      # Validate then deploy
    $0 deploy -v                   # Verbose deployment
    $0 scale -l k8s-worker-07      # Scale with specific host
    $0 deploy --skip-validation    # Emergency deploy without validation
EOF
}

run_validation() {
	if [[ ! -x "$VALIDATE_SCRIPT" ]]; then
		error "Validation script not found: $VALIDATE_SCRIPT"
		return 1
	fi

	info "Running validation..."
	"$VALIDATE_SCRIPT" --env "$ENVIRONMENT"
}

run_deployment() {
	local operation="$1"
	shift

	if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
		error "Deployment script not found: $DEPLOY_SCRIPT"
		return 1
	fi

	info "Starting deployment: $operation (env: $ENVIRONMENT)"
	"$DEPLOY_SCRIPT" "$operation" "--env" "$ENVIRONMENT" "$@"
}

copy_kubeconfig() {
	info "Copying kubeconfig from master node..."

	# Create .kube directory if it doesn't exist
	mkdir -p "$HOME/.kube"

	# Get first master IP and hostname from inventory
	local inventory_dir="${SCRIPT_DIR}/inventory/current"
	if [[ ! -f "${inventory_dir}/inventory.ini" ]]; then
		warn "No staged inventory found; skipping kubeconfig copy"
		return 0
	fi

	local master_line=$(awk '/\[kube_control_plane\]/{flag=1;next}/\[/{flag=0}flag && /ansible_host/{print; exit}' "${inventory_dir}/inventory.ini")
	local master_ip=$(echo "$master_line" | awk '{print $2}' | cut -d'=' -f2)
	local master_hostname=$(echo "$master_line" | awk '{print $1}')

	if [[ -z "$master_ip" || -z "$master_hostname" ]]; then
		warn "Could not find master IP or hostname in inventory"
		return 1
	fi

	# Get ansible user from host_vars
	local ansible_user=$(grep "ansible_user:" "${inventory_dir}/host_vars/${master_hostname}.yml" 2>/dev/null | awk '{print $2}' || echo "root")

	# Copy kubeconfig using the ansible user
	if ssh "$ansible_user@$master_ip" "sudo cp /etc/kubernetes/admin.conf \$HOME/kubeconfig-temp && sudo chown $ansible_user:$ansible_user \$HOME/kubeconfig-temp" &>/dev/null; then
		if scp "$ansible_user@$master_ip":/home/$ansible_user/kubeconfig-temp "$HOME/.kube/config" &>/dev/null; then
			ssh "$ansible_user@$master_ip" "rm -f \$HOME/kubeconfig-temp" &>/dev/null
			log "Kubeconfig copied to $HOME/.kube/config"

			# Verify kubeconfig works
			if kubectl cluster-info &>/dev/null; then
				local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
				log "Cluster accessible with $node_count nodes"
			else
				warn "Kubeconfig copied but cluster not accessible"
			fi
		else
			warn "Failed to copy kubeconfig via scp"
			ssh "$ansible_user@$master_ip" "rm -f \$HOME/kubeconfig-temp" &>/dev/null
		fi
	else
		warn "Failed to prepare kubeconfig on master node"
	fi
}

enforce_validation() {
	local operation="$1"

	if [[ "$SKIP_VALIDATION" == "true" ]]; then
		warn "⚠️  VALIDATION SKIPPED - Emergency mode"
		return 0
	fi

	info "Validation required before $operation"
	if run_validation; then
		log "Validation passed - proceeding with $operation"
	else
		error "Validation failed - $operation aborted"
		exit 1
	fi
}

# Parse arguments - separate validation flags from deploy script args
DEPLOY_ARGS=()
while [[ $# -gt 0 ]]; do
	case $1 in
	validate | deploy | reset | upgrade | scale | recover | facts | status | shell)
		OPERATION="$1"
		shift
		;;
	--env)
		ENVIRONMENT="$2"
		shift 2
		;;
	--skip-validation)
		SKIP_VALIDATION="true"
		shift
		;;
	--force-validation)
		FORCE_VALIDATION="true"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		# All other arguments go to deploy script
		DEPLOY_ARGS+=("$1")
		shift
		;;
	esac
done

# Default operation
[[ -z "$OPERATION" ]] && OPERATION="deploy"

info "Operation: $OPERATION"

# Execute operation
case $OPERATION in
validate)
	run_validation
	;;
deploy | reset | upgrade | scale | recover | facts)
	enforce_validation "$OPERATION"
	if run_deployment "$OPERATION" "${DEPLOY_ARGS[@]}"; then
		# Copy kubeconfig after successful deployment operations
		if [[ "$OPERATION" == "deploy" || "$OPERATION" == "upgrade" || "$OPERATION" == "scale" ]]; then
			copy_kubeconfig
		fi
	fi
	;;
status)
	if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null; then
		kubectl get nodes
	else
		warn "Cluster not accessible or kubectl not available"
	fi
	;;
shell)
	run_deployment "shell" "${DEPLOY_ARGS[@]}"
	;;
*)
	error "Unknown operation: $OPERATION"
	usage
	exit 1
	;;
esac

log "Operation completed!"
