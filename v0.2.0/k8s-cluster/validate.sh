#!/usr/bin/env bash

# Kubespray Cluster Deployment Validation
# Validates only prerequisites needed for Kubernetes cluster deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_PATH="${SCRIPT_DIR}/inventory/pn-production"
HOSTS_FILE="${INVENTORY_PATH}/hosts.yml"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/proficientnowtech/kubespray-pncp:latest}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0

log_info() {
    echo -e "${BLUE}[VALIDATE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

# Check required tools for cluster deployment
check_tools() {
    log_info "Checking required tools for cluster deployment..."

    local tools=("docker" "ssh")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Missing tool: $tool"
        fi
    done
}

# Check Docker for Kubespray
check_docker() {
    log_info "Checking Docker for Kubespray..."

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker not running or accessible"
        return
    fi

    # Check if we can pull the configured Kubespray image
    if ! docker pull "${IMAGE_NAME}" >/dev/null 2>&1; then
        log_warning "Cannot pull Kubespray Docker image (${IMAGE_NAME}) - check network connectivity"
    fi
}

# Check SSH keys for cluster nodes
check_ssh() {
    log_info "Checking SSH configuration for cluster nodes..."

    local ssh_key="${HOME}/.ssh-manager/keys/pn-infra-prod/id_ed25519_pn-infra-prod-ansible_20260123-162958"
    if [[ ! -f "$ssh_key" ]]; then
        log_error "SSH key not found: $ssh_key"
        return
    fi

    # Check key permissions
    local key_perms=$(stat -c %a "$ssh_key" 2>/dev/null)
    if [[ "$key_perms" != "600" ]]; then
        log_warning "SSH key permissions should be 600, found: $key_perms"
    fi
}

# Check Kubespray inventory and configuration
check_inventory() {
    log_info "Checking Kubespray inventory and configuration..."

    # Check inventory file (canonical)
    if [[ ! -f "${HOSTS_FILE}" ]]; then
        log_error "Inventory file not found: ${HOSTS_FILE}"
        return
    fi

    # Check essential configuration files
    local config_files=(
        "group_vars/k8s_cluster/k8s-cluster.yml"
        "group_vars/k8s_cluster/addons.yml"
        "group_vars/all/all.yml"
    )

    for config_file in "${config_files[@]}"; do
        if [[ ! -f "${INVENTORY_PATH}/${config_file}" ]]; then
            log_error "Essential config file missing: $config_file"
        fi
    done

    # Check network plugin configuration
    local k8s_config="${INVENTORY_PATH}/group_vars/k8s_cluster/k8s-cluster.yml"
    if [[ -f "$k8s_config" ]]; then
        if ! python3 - <<PY
import pathlib, sys, yaml
p = pathlib.Path("${k8s_config}")
cfg = yaml.safe_load(p.read_text()) or {}
plugin = cfg.get("kube_network_plugin")
multus = bool(cfg.get("kube_network_plugin_multus", False))
lb = cfg.get("loadbalancer_apiserver", None)
vip = cfg.get("kube_vip_address", None)
print(f"[VALIDATE] Network plugin: {plugin!s}")
if plugin is None:
    print("[ERROR] Network plugin not configured in k8s-cluster.yml")
    sys.exit(1)
if plugin != "calico":
    print(f"[WARNING] Expected calico for a simple cluster; found: {plugin}")
if multus:
    print("[WARNING] Multus is enabled; for a simple cluster, keep kube_network_plugin_multus: false")
if lb not in (None, {}, ""):
    if isinstance(lb, dict) and lb.get("address") and vip and (str(lb.get("address")) != str(vip)):
        print(f"[WARNING] loadbalancer_apiserver.address ({lb.get('address')}) != kube_vip_address ({vip}); these should normally match for kube-vip HA")
    print("[INFO] loadbalancer_apiserver is set; ensure kube-vip is enabled and the VIP is reachable during bootstrap")
PY
        then
            log_error "Network plugin validation failed (see output above)"
        fi
    fi
}

# Test SSH connectivity to cluster nodes
check_connectivity() {
    log_info "Testing SSH connectivity to cluster nodes..."

    local ssh_key="${HOME}/.ssh-manager/keys/pn-infra-prod/id_ed25519_pn-infra-prod-ansible_20260123-162958"
    local test_hosts=()
    local max_parallel=20

    # Extract all hosts from hosts.yml for testing
    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        test_hosts+=("$ip")
    done < <(python3 - <<PY
import yaml, pathlib
inv = pathlib.Path("${HOSTS_FILE}")
data = yaml.safe_load(inv.read_text())
hosts = data.get("all", {}).get("hosts", {}) if isinstance(data, dict) else {}
for _, meta in hosts.items():
    ip = meta.get("ansible_host")
    if ip:
        print(ip)
PY
    )

    if [[ ${#test_hosts[@]} -eq 0 ]]; then
        log_warning "No hosts found in inventory for connectivity testing"
        return
    fi

    # Run SSH checks in parallel for faster failure detection.
    local failed
    failed="$(
        printf '%s\n' "${test_hosts[@]}" | xargs -P "${max_parallel}" -I{} bash -c \
            'timeout 8 ssh -i "'"${ssh_key}"'" -o IdentitiesOnly=yes -o IdentityAgent=none -o PreferredAuthentications=publickey -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@"{}" "echo ok" >/dev/null 2>&1 || echo "{}"'
    )"

    if [[ -n "$failed" ]]; then
        log_error "SSH connectivity failed for hosts: ${failed//$'\n'/ }"
    else
        log_success "SSH connectivity verified for all hosts"
    fi
}

# Main validation
run_validation() {
    log_info "Starting Kubespray cluster deployment validation..."

    check_tools
    check_docker
    check_ssh
    check_inventory
    check_connectivity

    echo
    if [[ $ERRORS -eq 0 ]]; then
        log_success "Cluster deployment validation passed!"
        return 0
    else
        log_error "$ERRORS validation errors found"
        return 1
    fi
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_validation
fi
