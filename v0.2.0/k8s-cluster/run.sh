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

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
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
        log_error "Validation script not found: $VALIDATE_SCRIPT"
        return 1
    fi
    
    log_info "Running validation..."
    "$VALIDATE_SCRIPT"
}

run_deployment() {
    local operation="$1"
    shift
    
    if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
        log_error "Deployment script not found: $DEPLOY_SCRIPT"
        return 1
    fi
    
    log_info "Starting deployment: $operation"
    "$DEPLOY_SCRIPT" "$operation" "$@"
}

copy_kubeconfig() {
    log_info "Copying kubeconfig from master node..."
    
    # Create .kube directory if it doesn't exist
    mkdir -p "$HOME/.kube"
    
    # Get first master IP and hostname from inventory
    local master_line=$(awk '/\[kube_control_plane\]/{flag=1;next}/\[/{flag=0}flag && /ansible_host/{print; exit}' "$SCRIPT_DIR/inventory/pn-production/inventory.ini")
    local master_ip=$(echo "$master_line" | awk '{print $2}' | cut -d'=' -f2)
    local master_hostname=$(echo "$master_line" | awk '{print $1}')
    
    if [[ -z "$master_ip" || -z "$master_hostname" ]]; then
        log_warning "Could not find master IP or hostname in inventory"
        return 1
    fi
    
    # Get ansible user from host_vars
    local ansible_user=$(grep "ansible_user:" "$SCRIPT_DIR/inventory/pn-production/host_vars/${master_hostname}.yml" 2>/dev/null | awk '{print $2}' || echo "root")
    
    # Copy kubeconfig using the ansible user
    if ssh "$ansible_user@$master_ip" "sudo cp /etc/kubernetes/admin.conf \$HOME/kubeconfig-temp && sudo chown $ansible_user:$ansible_user \$HOME/kubeconfig-temp" &>/dev/null; then
        if scp "$ansible_user@$master_ip":/home/$ansible_user/kubeconfig-temp "$HOME/.kube/config" &>/dev/null; then
            ssh "$ansible_user@$master_ip" "rm -f \$HOME/kubeconfig-temp" &>/dev/null
            log_success "Kubeconfig copied to $HOME/.kube/config"
            
            # Verify kubeconfig works
            if kubectl cluster-info &>/dev/null; then
                local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
                log_success "Cluster accessible with $node_count nodes"
            else
                log_warning "Kubeconfig copied but cluster not accessible"
            fi
        else
            log_warning "Failed to copy kubeconfig via scp"
            ssh "$ansible_user@$master_ip" "rm -f \$HOME/kubeconfig-temp" &>/dev/null
        fi
    else
        log_warning "Failed to prepare kubeconfig on master node"
    fi
}

enforce_validation() {
    local operation="$1"
    
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_warning "⚠️  VALIDATION SKIPPED - Emergency mode"
        return 0
    fi
    
    log_info "Validation required before $operation"
    if run_validation; then
        log_success "Validation passed - proceeding with $operation"
    else
        log_error "Validation failed - $operation aborted"
        exit 1
    fi
}

# Parse arguments - separate validation flags from deploy script args
DEPLOY_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        validate|deploy|reset|upgrade|scale|recover|facts|status|shell)
            OPERATION="$1"
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION="true"
            shift
            ;;
        --force-validation)
            FORCE_VALIDATION="true"
            shift
            ;;
        -h|--help)
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

log_info "Operation: $OPERATION"

# Execute operation
case $OPERATION in
    validate)
        run_validation
        ;;
    deploy|reset|upgrade|scale|recover|facts)
        enforce_validation "$OPERATION"
        if run_deployment "$OPERATION" "${DEPLOY_ARGS[@]}"; then
            # Copy kubeconfig after successful deployment operations
            if [[ "$OPERATION" == "deploy" || "$OPERATION" == "upgrade" || "$OPERATION" == "scale" ]]; then
                copy_kubeconfig
            fi
        fi
        ;;
    status)
        if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
            kubectl get nodes
        else
            log_warning "Cluster not accessible or kubectl not available"
        fi
        ;;
    shell)
        run_deployment "shell" "${DEPLOY_ARGS[@]}"
        ;;
    *)
        log_error "Unknown operation: $OPERATION"
        usage
        exit 1
        ;;
esac

log_success "Operation completed!"