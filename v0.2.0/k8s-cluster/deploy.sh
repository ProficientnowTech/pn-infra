#!/usr/bin/env bash

# Enhanced Kubespray Docker Management Script
# Supports deploy, reset, upgrade, scale and other Kubespray operations
# Uses official Kubespray Docker image without polluting your repository

set -e

# Configuration
KUBESPRAY_VERSION="v2.28.1"
INVENTORY_PATH="$(pwd)/inventory/pn-production"
SSH_KEY_PATH="${HOME}/.ssh-manager/keys/pn-production-k8s/id_ed25519_pn-production-ansible-role_20250505-163646"
IMAGE_NAME="quay.io/kubespray/kubespray:${KUBESPRAY_VERSION}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
OPERATION=""
VERBOSE=""
DRY_RUN=""
FORCE_PULL=""
EXTRA_ARGS=""
LIMIT_HOSTS=""

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPERATION] [OPTIONS]

OPERATIONS:
    deploy          Deploy a new Kubernetes cluster (default)
    reset           Reset/destroy the cluster
    upgrade         Upgrade cluster to newer Kubernetes version
    scale           Add/remove nodes to/from cluster
    recover         Recover control plane
    shell           Open interactive shell in container
    validate        Validate configuration (dry-run)
    facts           Gather cluster facts

OPTIONS:
    -v, --verbose       Enable verbose output
    -n, --dry-run      Perform a dry run (check mode)
    -f, --force-pull   Force pull Docker image even if present
    -l, --limit HOSTS  Limit execution to specific hosts (comma-separated)
    -e, --extra ARGS   Pass additional arguments to ansible-playbook
    -h, --help         Show this help message

EXAMPLES:
    $0 deploy                           # Deploy cluster
    $0 reset                           # Reset cluster
    $0 upgrade -v                      # Upgrade with verbose output
    $0 scale -l k8s-worker-07          # Add new worker node
    $0 deploy -n                       # Dry run deployment
    $0 shell                          # Interactive container shell
    $0 validate                       # Validate configuration

CONFIGURATION:
    Kubespray Version: ${KUBESPRAY_VERSION}
    Inventory Path: ${INVENTORY_PATH}
    SSH Key: ${SSH_KEY_PATH}
EOF
}

# Logging functions
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

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        exit 1
    fi
    
    # Check SSH key
    if [[ ! -f "${SSH_KEY_PATH}" ]]; then
        log_error "SSH private key not found at ${SSH_KEY_PATH}"
        exit 1
    fi
    
    # Check inventory
    if [[ ! -f "${INVENTORY_PATH}/inventory.ini" ]]; then
        log_error "Inventory file not found at ${INVENTORY_PATH}/inventory.ini"
        exit 1
    fi
    
    # Check inventory structure
    if [[ ! -d "${INVENTORY_PATH}/group_vars" ]]; then
        log_error "group_vars directory not found in inventory"
        exit 1
    fi
    
    log_success "Prerequisites validation passed"
}

validate_ssh_connectivity() {
    log_info "Validating SSH connectivity..."
    
    # Extract hosts from inventory
    local hosts=$(awk '/^\[.*\]/ {next} /^[a-zA-Z]/ {print $2}' "${INVENTORY_PATH}/inventory.ini" | grep "ansible_host=" | sed 's/.*ansible_host=//' | sed 's/ .*//' | head -3)
    
    local failed_hosts=""
    for host in $hosts; do
        if ! timeout 5 ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ansible@"$host" "echo 'SSH test successful'" >/dev/null 2>&1; then
            failed_hosts="$failed_hosts $host"
        fi
    done
    
    if [[ -n "$failed_hosts" ]]; then
        log_warning "SSH connectivity failed for hosts:$failed_hosts"
        log_warning "Deployment may fail. Check SSH keys and network connectivity."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "SSH connectivity validation passed"
    fi
}

check_docker_image() {
    log_info "Checking Docker image availability..."
    
    if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        log_success "Docker image ${IMAGE_NAME} found locally"
        if [[ "$FORCE_PULL" == "true" ]]; then
            log_info "Force pull requested, updating image..."
            docker pull "${IMAGE_NAME}"
        fi
    else
        log_info "Docker image not found locally, pulling..."
        docker pull "${IMAGE_NAME}"
    fi
}

# Main execution function
run_kubespray() {
    local playbook="$1"
    local operation_name="$2"
    
    log_info "Starting Kubespray ${operation_name}..."
    
    # Build command arguments
    local cmd="cd /kubespray && chmod 600 /root/.ssh/id_rsa"
    
    # Add verbose flag
    local ansible_args="-i inventory/pn-production/inventory.ini"
    [[ "$VERBOSE" == "true" ]] && ansible_args="$ansible_args -v"
    [[ "$DRY_RUN" == "true" ]] && ansible_args="$ansible_args --check"
    [[ -n "$LIMIT_HOSTS" ]] && ansible_args="$ansible_args --limit $LIMIT_HOSTS"
    [[ -n "$EXTRA_ARGS" ]] && ansible_args="$ansible_args $EXTRA_ARGS"
    
    cmd="$cmd && export ANSIBLE_HOST_KEY_CHECKING=False"
    cmd="$cmd && ansible-playbook $ansible_args $playbook -b"
    
    # Run the container
    docker run --rm -it \
        --mount type=bind,source="${INVENTORY_PATH}",dst="/kubespray/inventory/pn-production/" \
        --mount type=bind,source="${SSH_KEY_PATH}",dst="/root/.ssh/id_rsa" \
        "${IMAGE_NAME}" \
        bash -c "$cmd"
    
    if [[ $? -eq 0 ]]; then
        log_success "Kubespray ${operation_name} completed successfully!"
    else
        log_error "Kubespray ${operation_name} failed!"
        exit 1
    fi
}

# Operation-specific functions
deploy_cluster() {
    log_info "Deploying Kubernetes cluster..."
    validate_ssh_connectivity
    run_kubespray "cluster.yml" "deployment"
}

reset_cluster() {
    log_warning "This will completely destroy the Kubernetes cluster!"
    log_warning "All data, pods, and configurations will be lost!"
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    if [[ "$REPLY" != "yes" ]]; then
        log_info "Reset operation cancelled"
        exit 0
    fi
    run_kubespray "reset.yml" "reset"
}

upgrade_cluster() {
    log_info "Upgrading Kubernetes cluster..."
    log_warning "Cluster upgrade is a complex operation. Ensure you have backups!"
    read -p "Continue with upgrade? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    run_kubespray "upgrade-cluster.yml" "upgrade"
}

scale_cluster() {
    if [[ -z "$LIMIT_HOSTS" ]]; then
        log_error "Scale operation requires --limit flag to specify hosts"
        log_info "Example: $0 scale --limit k8s-worker-07"
        exit 1
    fi
    log_info "Scaling cluster with hosts: $LIMIT_HOSTS"
    run_kubespray "scale.yml" "scaling"
}

recover_cluster() {
    log_info "Recovering control plane..."
    log_warning "This should only be used when control plane nodes are down"
    read -p "Continue with recovery? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    run_kubespray "recover-control-plane.yml" "recovery"
}

validate_config() {
    log_info "Validating Kubespray configuration..."
    DRY_RUN="true"
    VERBOSE="true"
    run_kubespray "cluster.yml" "validation"
}

gather_facts() {
    log_info "Gathering cluster facts..."
    run_kubespray "facts.yml" "fact gathering"
}

open_shell() {
    log_info "Opening interactive Kubespray container shell..."
    log_info "Inventory mounted at: /kubespray/inventory/pn-production/"
    log_info "SSH Key mounted at: /root/.ssh/id_rsa"
    log_info "Run 'ansible-playbook -i inventory/pn-production/inventory.ini cluster.yml -b' to deploy"
    
    docker run --rm -it \
        --mount type=bind,source="${INVENTORY_PATH}",dst="/kubespray/inventory/pn-production/" \
        --mount type=bind,source="${SSH_KEY_PATH}",dst="/root/.ssh/id_rsa" \
        "${IMAGE_NAME}" \
        bash -c "cd /kubespray && chmod 600 /root/.ssh/id_rsa && bash"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        deploy|reset|upgrade|scale|recover|shell|validate|facts)
            OPERATION="$1"
            shift
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -n|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -f|--force-pull)
            FORCE_PULL="true"
            shift
            ;;
        -l|--limit)
            LIMIT_HOSTS="$2"
            shift 2
            ;;
        -e|--extra)
            EXTRA_ARGS="$2"
            shift 2
            ;;
        -h|--help)
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
[[ -z "$OPERATION" ]] && OPERATION="deploy"

# Print header
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Enhanced Kubespray Manager              ║${NC}"
echo -e "${CYAN}║            Docker-based Deployment               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo
log_info "Operation: ${OPERATION}"
log_info "Kubespray Version: ${KUBESPRAY_VERSION}"
[[ "$VERBOSE" == "true" ]] && log_info "Verbose mode enabled"
[[ "$DRY_RUN" == "true" ]] && log_info "Dry run mode enabled"
[[ -n "$LIMIT_HOSTS" ]] && log_info "Limited to hosts: ${LIMIT_HOSTS}"

# Validate prerequisites
validate_prerequisites

# Check and pull Docker image
check_docker_image

# Execute operation
case $OPERATION in
    deploy)
        deploy_cluster
        ;;
    reset)
        reset_cluster
        ;;
    upgrade)
        upgrade_cluster
        ;;
    scale)
        scale_cluster
        ;;
    recover)
        recover_cluster
        ;;
    validate)
        validate_config
        ;;
    facts)
        gather_facts
        ;;
    shell)
        open_shell
        ;;
    *)
        log_error "Unknown operation: $OPERATION"
        usage
        exit 1
        ;;
esac