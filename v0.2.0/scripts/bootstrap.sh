#!/usr/bin/env bash

# Production Kubernetes Bootstrap
# One script to rule them all - beautifully simple, brilliantly works

# Safer prologue
set -Eeuo pipefail

# Debug if requested
if [[ "${DEBUG:-}" == "true" ]]; then set -x; fi

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly KUBESPRAY_DIR="${SCRIPT_DIR}/../kubespray"
readonly PHASE_1_DIR="${SCRIPT_DIR}/../phase-1-k8s"
readonly PHASE_2_DIR="${SCRIPT_DIR}/../phase-2-argo-bootstrap"
readonly PHASE_3_DIR="${SCRIPT_DIR}/../phase-3-platform-infra"

# Default configuration - can be overridden by command line args
INVENTORY="${INVENTORY:-pn-production}"
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
CONFIG_FILE="${CONFIG_FILE:-}"
ANSIBLE_OPTS="${ANSIBLE_OPTS:-}"
VERBOSE=""
DEBUG="${DEBUG:-false}"

# LOG_FILE will be set after parsing arguments

# Colors
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m'

# ============================================================================
# UTILITIES
# ============================================================================

fail() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
    [[ -f "$LOG_FILE" ]] && echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] [ERROR]: $1" >>"$LOG_FILE"
    exit "${2:-1}"
}

# SSH connection helper function
# Usage: ssh_run_command <host> <command>
ssh_run_command() {
    local host="$1"
    local command="$2"
    local inventory_path="$ANSIBLE_DIR/inventory/${INVENTORY}.yml"

    # Extract SSH credentials from Ansible inventory
    local ssh_user ssh_key ssh_pass
    ssh_user=$(python3 -c "
import yaml
with open('$inventory_path', 'r') as f:
    inventory = yaml.safe_load(f)
print(inventory.get('all', {}).get('vars', {}).get('ansible_user', 'root'))
" 2>/dev/null)

    ssh_key=$(python3 -c "
import yaml
with open('$inventory_path', 'r') as f:
    inventory = yaml.safe_load(f)
key_file = inventory.get('all', {}).get('vars', {}).get('ansible_ssh_private_key_file', '')
print(key_file)
" 2>/dev/null)

    # Build SSH command with proper options
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

    if [[ -n "$ssh_key" && -f "$ssh_key" ]]; then
        ssh_opts="$ssh_opts -i $ssh_key"
    fi

    # Execute SSH command
    if [[ -n "$ssh_user" ]]; then
        ssh $ssh_opts "${ssh_user}@${host}" "$command"
    else
        ssh $ssh_opts "$host" "$command"
    fi
}

# Get master host from inventory
get_master_host() {
    local inventory_path="$ANSIBLE_DIR/inventory/${INVENTORY}.yml"

    # Debug: Check if file exists
    if [[ ! -f "$inventory_path" ]]; then
        echo "ERROR: Inventory file not found: $inventory_path" >&2
        return 1
    fi

    python3 -c "
import yaml
import sys
try:
    with open('$inventory_path', 'r') as f:
        inventory = yaml.safe_load(f)

    masters = inventory.get('all', {}).get('children', {}).get('masters', {}).get('hosts', {})
    if masters:
        # Get the first master and its ansible_host if available
        master_name = list(masters.keys())[0]
        master_config = masters[master_name]
        if isinstance(master_config, dict) and 'ansible_host' in master_config:
            print(master_config['ansible_host'])
        else:
            print(master_name)
    else:
        print('ERROR: No masters found in inventory', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: Failed to parse inventory: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

log() {
    local level="${1^^}" msg="$2"
    local timestamp="$(date -u '+%Y-%m-%d %H:%M:%S')"

    declare -A colors=([ERROR]="$RED" [WARN]="$YELLOW" [INFO]="$BLUE" [SUCCESS]="$GREEN")

    printf "${CYAN}%s${NC} ${colors[$level]:-}[%s]${NC} %s\n" "$timestamp" "$level" "$msg"

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] [$level]: $msg" >>"$LOG_FILE"
}

separator() {
    local line="=================================================================="
    printf "${CYAN}%s${NC}\n" "$line"
    echo "$line" >>"$LOG_FILE"
}

check_tools() {
    log info "Checking prerequisites..."
    local missing=()

    for tool in ansible-playbook kubectl helm; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        else
            log success "$tool found"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing tools: ${missing[*]}"
    fi
}

run_playbook() {
    local playbook="$1" description="$2"
    local playbook_path="$ANSIBLE_DIR/playbooks/$playbook"
    local inventory_path="$ANSIBLE_DIR/inventory/${INVENTORY}.yml"

    log info "Running: $description"

    [[ ! -f "$playbook_path" ]] && fail "Playbook not found: $playbook_path"
    [[ ! -f "$inventory_path" ]] && fail "Inventory not found: $inventory_path"

    # Build ansible command with options
    local ansible_cmd="ansible-playbook -i \"$inventory_path\""
    [[ -n "$VERBOSE" ]] && ansible_cmd="$ansible_cmd $VERBOSE"
    [[ -n "$ANSIBLE_OPTS" ]] && ansible_cmd="$ansible_cmd $ANSIBLE_OPTS"
    [[ -n "$CONFIG_FILE" ]] && ansible_cmd="$ansible_cmd --extra-vars @\"$CONFIG_FILE\""
    ansible_cmd="$ansible_cmd \"$playbook_path\""

    log info "Command: $ansible_cmd"

    if ! eval "$ansible_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        fail "Playbook failed: $playbook"
    fi

    log success "Completed: $description"
}

wait_for_cluster() {
    log info "Waiting for Kubernetes API to be accessible..."

    local max_attempts=20 attempt=1

    # Get master host using helper function
    local master_host
    master_host=$(get_master_host)

    if [[ -z "$master_host" ]]; then
        fail "Could not find master host in inventory"
    fi

    log info "Checking Kubernetes API accessibility on master node: $master_host"

    while [[ $attempt -le $max_attempts ]]; do
        # Only check if Kubernetes API is accessible - don't care about node readiness yet
        if ssh_run_command "$master_host" "kubectl get nodes >/dev/null 2>&1"; then
            # Get total node count to verify cluster is functional
            local total_nodes
            total_nodes=$(ssh_run_command "$master_host" "
                kubectl get nodes --no-headers 2>/dev/null | wc -l || echo '0'
            " 2>/dev/null)

            if [[ -n "$total_nodes" && "$total_nodes" -gt 0 ]]; then
                log success "Kubernetes API accessible on $master_host: $total_nodes nodes detected"
                log info "Note: Nodes may be NotReady - this is expected before CNI deployment"
                return 0
            else
                log info "API accessible but no nodes detected (attempt $attempt/$max_attempts)"
            fi
        else
            log info "Kubernetes API not accessible yet on $master_host (attempt $attempt/$max_attempts)"
        fi

        sleep 15
        ((attempt++))
    done

    fail "Kubernetes API failed to become accessible on master node: $master_host"
}

reset_cluster() {
    log warn "Performing deep reset..."
    separator

    # Reset Kubespray
    if [[ -f "$KUBESPRAY_DIR/reset.yml" ]]; then
        log info "Running Kubespray reset..."
        cd "$KUBESPRAY_DIR"
        # Build reset command with options
        local reset_cmd="ansible-playbook -i \"inventory/$INVENTORY/inventory.ini\" reset.yml --become --become-user=root"
        [[ -n "$VERBOSE" ]] && reset_cmd="$reset_cmd $VERBOSE"
        [[ -n "$ANSIBLE_OPTS" ]] && reset_cmd="$reset_cmd $ANSIBLE_OPTS"

        if eval "$reset_cmd"; then
            log success "Kubespray reset completed"
        else
            log warn "Kubespray reset had issues (this is often normal)"
        fi
    fi

    # Clean up local kubeconfig
    [[ -f "$HOME/.kube/config" ]] && {
        log info "Backing up and removing kubeconfig..."
        mv "$HOME/.kube/config" "$HOME/.kube/config.backup.$(date +%s)" 2>/dev/null || true
    }

    log success "Deep reset completed"
    exit 0
}

# ============================================================================
# MAIN PHASES - Enhanced 3-Phase Architecture
# ============================================================================

phase_1_deploy_cluster() {
    log info "🚀 PHASE 1: Kubernetes Cluster + Infrastructure Components"
    separator

    # Validate phase 1 prerequisites
    local validate_script="$PHASE_1_DIR/scripts/validate-phase-1.sh"
    if [[ -f "$validate_script" ]]; then
        log info "Running Phase 1 validation..."
        if ! "$validate_script"; then
            fail "Phase 1 validation failed"
        fi
        log success "Phase 1 validation passed"
    fi

    cd "$KUBESPRAY_DIR"
    local inventory_file="inventory/$INVENTORY/inventory.ini"

    [[ ! -f "$inventory_file" ]] && fail "Inventory not found: $inventory_file"

    log info "Running Kubespray cluster deployment with addons..."

    # Build kubespray command with options
    local kubespray_cmd="ansible-playbook -i \"$inventory_file\" cluster.yml --become --become-user=root"
    [[ -n "$VERBOSE" ]] && kubespray_cmd="$kubespray_cmd $VERBOSE"
    [[ -n "$ANSIBLE_OPTS" ]] && kubespray_cmd="$kubespray_cmd $ANSIBLE_OPTS"
    [[ -n "$CONFIG_FILE" ]] && kubespray_cmd="$kubespray_cmd --extra-vars @\"$CONFIG_FILE\""

    log info "Command: $kubespray_cmd"

    if ! eval "$kubespray_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        fail "Kubespray cluster deployment failed"
    fi

    # Verify phase 1 completion
    local verify_script="$PHASE_1_DIR/scripts/verify-phase-1.sh"
    if [[ -f "$verify_script" ]]; then
        log info "Verifying Phase 1 deployment..."
        if ! "$verify_script"; then
            fail "Phase 1 verification failed"
        fi
        log success "Phase 1 verification passed"
    fi

    log success "✅ Phase 1: Kubernetes cluster with infrastructure components deployed"
}

phase_2_deploy_argocd_bootstrap() {
    log info "🎯 PHASE 2: ArgoCD Bootstrap + Infrastructure Configuration"
    separator

    # Validate phase 2 prerequisites
    local validate_script="$PHASE_2_DIR/scripts/validate-phase-2.sh"
    if [[ -f "$validate_script" ]]; then
        log info "Running Phase 2 validation..."
        if ! "$validate_script"; then
            fail "Phase 2 validation failed"
        fi
        log success "Phase 2 validation passed"
    fi

    # Wait for cluster to be ready
    wait_for_cluster

    # Run ArgoCD deployment using enhanced Ansible roles
    cd "$PHASE_2_DIR/ansible"
    local inventory_file="inventory/$INVENTORY/inventory.ini"
    local playbook="playbooks/deploy-argocd.yml"

    [[ ! -f "$inventory_file" ]] && fail "Phase 2 inventory not found: $inventory_file"
    [[ ! -f "$playbook" ]] && fail "Phase 2 playbook not found: $playbook"

    log info "Deploying ArgoCD with infrastructure configurations..."

    # Build ansible command with options
    local ansible_cmd="ansible-playbook -i \"$inventory_file\" \"$playbook\""
    [[ -n "$VERBOSE" ]] && ansible_cmd="$ansible_cmd $VERBOSE"
    [[ -n "$ANSIBLE_OPTS" ]] && ansible_cmd="$ansible_cmd $ANSIBLE_OPTS"
    [[ -n "$CONFIG_FILE" ]] && ansible_cmd="$ansible_cmd --extra-vars @\"$CONFIG_FILE\""

    log info "Command: $ansible_cmd"

    if ! eval "$ansible_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        fail "Phase 2 ArgoCD deployment failed"
    fi

    # Verify phase 2 completion
    local verify_script="$PHASE_2_DIR/scripts/verify-phase-2.sh"
    if [[ -f "$verify_script" ]]; then
        log info "Verifying Phase 2 deployment..."
        if ! "$verify_script"; then
            fail "Phase 2 verification failed"
        fi
        log success "Phase 2 verification passed"
    fi

    log success "✅ Phase 2: ArgoCD bootstrap and infrastructure configuration deployed"
}

phase_3_deploy_platform_infrastructure() {
    log info "🏗️ PHASE 3: Platform Infrastructure via GitOps"
    separator

    # Validate phase 3 prerequisites
    local validate_script="$PHASE_3_DIR/scripts/validate-phase-3.sh"
    if [[ -f "$validate_script" ]]; then
        log info "Running Phase 3 validation..."
        if ! "$validate_script"; then
            fail "Phase 3 validation failed"
        fi
        log success "Phase 3 validation passed"
    fi

    # Deploy platform project and root application
    log info "Deploying platform project and applications..."

    # Apply platform project
    local platform_project="$PHASE_3_DIR/manifests/platform-project.yaml"
    if [[ -f "$platform_project" ]]; then
        log info "Creating platform project..."
        if ! kubectl apply -f "$platform_project" 2>&1 | tee -a "$LOG_FILE"; then
            fail "Failed to create platform project"
        fi
        log success "Platform project created"
    fi

    # Apply platform root application
    local root_app="$PHASE_3_DIR/manifests/platform-root-app.yaml"
    if [[ -f "$root_app" ]]; then
        log info "Deploying platform root application..."
        if ! kubectl apply -f "$root_app" 2>&1 | tee -a "$LOG_FILE"; then
            fail "Failed to deploy platform root application"
        fi
        log success "Platform root application deployed"
    fi

    # Wait for applications to sync
    log info "Waiting for platform applications to sync..."
    local max_wait=600  # 10 minutes
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        local synced_apps
        synced_apps=$(kubectl get applications -n argocd -l managed-by=argocd -o jsonpath='{.items[?(@.status.sync.status=="Synced")].metadata.name}' 2>/dev/null | wc -w)
        local total_apps
        total_apps=$(kubectl get applications -n argocd -l managed-by=argocd -o name 2>/dev/null | wc -l)

        if [[ $synced_apps -gt 0 && $synced_apps -eq $total_apps ]]; then
            log success "All platform applications synced ($synced_apps/$total_apps)"
            break
        else
            log info "Platform applications syncing... ($synced_apps/$total_apps synced)"
            sleep 30
            elapsed=$((elapsed + 30))
        fi
    done

    # Verify phase 3 completion
    local verify_script="$PHASE_3_DIR/scripts/verify-phase-3.sh"
    if [[ -f "$verify_script" ]]; then
        log info "Verifying Phase 3 deployment..."
        if ! "$verify_script"; then
            fail "Phase 3 verification failed"
        fi
        log success "Phase 3 verification passed"
    fi

    log success "✅ Phase 3: Platform infrastructure deployed via GitOps"
}

show_access_info() {
    log info "🔗 ACCESS INFORMATION:"

    # ArgoCD access information
    if kubectl get service argocd-server -n argocd >/dev/null 2>&1; then
        local argocd_host
        if kubectl get ingress -n argocd 2>/dev/null | grep -q argocd; then
            argocd_host=$(kubectl get ingress -n argocd -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)
            [[ -n "$argocd_host" ]] && log info "• ArgoCD UI: https://$argocd_host"
        fi
        log info "• ArgoCD Port Forward: kubectl port-forward -n argocd svc/argocd-server 8080:80"
        log info "• ArgoCD Username: admin"
        log info "• ArgoCD Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    fi

    # Monitoring access information
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        if kubectl get service -n monitoring | grep -q grafana; then
            log info "• Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
            log info "• Grafana Login: admin / (check secret: kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
        fi
        if kubectl get service -n monitoring | grep -q prometheus; then
            log info "• Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
        fi
    fi

    # Vault access information
    if kubectl get namespace vault >/dev/null 2>&1; then
        if kubectl get service -n vault | grep -q vault; then
            log info "• Vault UI: kubectl port-forward -n vault svc/vault-ui 8200:8200"
            log info "• Vault Init: kubectl exec -n vault vault-0 -- vault operator init (run once)"
        fi
    fi

    separator
}

# ============================================================================
# MAIN
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy a production-grade Kubernetes cluster with 3-phase enhanced architecture

OPTIONS:
    --reset                 Perform deep cluster reset
    -s, --start N          Start from phase N (1-3)
    -i, --inventory NAME   Use inventory NAME (default: pn-production)
    -v, --verbose          Enable verbose Ansible output
    -y, --yes              Skip confirmations
    -d, --debug            Enable debug mode
    -e, --extra-vars VARS  Pass extra variables to Ansible
    -c, --config FILE      Use config file for extra variables
    -l, --log-dir DIR      Log directory (default: ./logs)
    -h, --help             Show this help

ENHANCED 3-PHASE ARCHITECTURE:
    1. Kubernetes + Infrastructure Components
       - Kubespray cluster deployment with essential addons
       - CNI (Calico), Ingress (NGINX), cert-manager, MetalLB, storage
       - Foundation for GitOps workflows

    2. ArgoCD Bootstrap + Infrastructure Configuration  
       - ArgoCD deployment with production configuration
       - Infrastructure configurations (MetalLB pools, ClusterIssuers, etc.)
       - Network policies and security configurations
       - GitOps foundation establishment

    3. Platform Infrastructure via GitOps
       - Rook-Ceph storage platform
       - HashiCorp Vault secrets management
       - Prometheus monitoring stack
       - Grafana visualization platform
       - App-of-apps GitOps pattern

EXAMPLES:
    $(basename "$0")                           # Full 3-phase deployment
    $(basename "$0") --reset                   # Deep reset
    $(basename "$0") -s 2                      # Start from ArgoCD bootstrap
    $(basename "$0") -i staging -v             # Use staging inventory with verbose
    $(basename "$0") -c config.yml -d          # Use config file with debug
    $(basename "$0") -e "cluster_domain=prod.example.com"  # Pass extra variables

MIGRATION FROM 4-PHASE:
    This script now implements the enhanced 3-phase architecture that combines
    the previous 4 phases into a more efficient and maintainable structure:
    - Old Phase 1 + 2 → New Phase 1 (Kubespray with addons)
    - Old Phase 3 → New Phase 2 (ArgoCD + configurations)  
    - Old Phase 4 → New Phase 3 (Platform services via GitOps)

EOF
}

main() {
    local start_phase=1 skip_confirm=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        --reset) reset_cluster ;;
        -s | --start)
            start_phase="$2"
            shift 2
            ;;
        -i | --inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -v | --verbose)
            VERBOSE="-v"
            shift
            ;;
        -y | --yes)
            skip_confirm=true
            shift
            ;;
        -d | --debug)
            export DEBUG=true
            set -x
            shift
            ;;
        -e | --extra-vars)
            ANSIBLE_OPTS="$ANSIBLE_OPTS --extra-vars '$2'"
            shift 2
            ;;
        -c | --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -l | --log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) fail "Unknown option: $1. Use -h for help." ;;
        esac
    done

    # Validation
    [[ ! "$start_phase" =~ ^[1-3]$ ]] && fail "Invalid phase: $start_phase. Must be 1-3"
    [[ -n "$CONFIG_FILE" && ! -f "$CONFIG_FILE" ]] && fail "Config file not found: $CONFIG_FILE"

    # Set log file after LOG_DIR is finalized
    readonly LOG_FILE="${LOG_DIR}/bootstrap-$(date -u '+%Y%m%d_%H%M%S').log"

    # Create log directory
    mkdir -p "$LOG_DIR"

    # Initialize
    log info "🎯 Production Kubernetes Bootstrap - Enhanced 3-Phase Architecture"
    log info "Inventory: $INVENTORY"
    log info "Start phase: $start_phase"
    log info "Log directory: $LOG_DIR"
    log info "Log file: $LOG_FILE"
    [[ -n "$CONFIG_FILE" ]] && log info "Config file: $CONFIG_FILE"
    [[ -n "$VERBOSE" ]] && log info "Verbose mode: enabled"
    [[ "$DEBUG" == "true" ]] && log info "Debug mode: enabled"
    separator

    check_tools

    # Confirmation
    if [[ "$skip_confirm" != "true" ]]; then
        echo -n "Proceed with 3-phase deployment? (y/N) "
        read -r reply
        [[ ! "$reply" =~ ^[Yy]$ ]] && {
            log info "Cancelled"
            exit 0
        }
    fi

    # Execute phases
    local start_time="$(date +%s)"

    [[ $start_phase -le 1 ]] && phase_1_deploy_cluster
    [[ $start_phase -le 2 ]] && phase_2_deploy_argocd_bootstrap
    [[ $start_phase -le 3 ]] && phase_3_deploy_platform_infrastructure

    # Success
    local duration=$(($(date +%s) - start_time))

    separator
    log success "🎉 DEPLOYMENT COMPLETE!"
    log info "Duration: $((duration / 60))m $((duration % 60))s"
    separator

    show_access_info

    log info "📝 NEXT STEPS:"
    log info "1. Access ArgoCD and verify all applications are synced"
    log info "2. Initialize Vault (if deployed): kubectl exec vault-0 -n vault -- vault operator init"
    log info "3. Configure monitoring dashboards in Grafana"
    log info "4. Set up additional applications via GitOps"
    log info "5. Review platform documentation in each phase directory"
    separator

    log success "Your production platform is ready! 🚀"
}

# Error handling
trap 'fail "Script failed at line $LINENO"' ERR

# Execute
main "$@"
