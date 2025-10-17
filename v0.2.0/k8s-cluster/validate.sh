#!/usr/bin/env bash

# Kubespray Cluster Deployment Validation
# Validates only prerequisites needed for Kubernetes cluster deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_PATH="${SCRIPT_DIR}/inventory/pn-production"

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
    
    # Check if we can pull Kubespray image
    local kubespray_version="v2.28.1"
    if ! docker pull quay.io/kubespray/kubespray:${kubespray_version} >/dev/null 2>&1; then
        log_warning "Cannot pull Kubespray Docker image - check network connectivity"
    fi
}

# Check SSH keys for cluster nodes
check_ssh() {
    log_info "Checking SSH configuration for cluster nodes..."
    
    local ssh_key="${HOME}/.ssh-manager/keys/pn-production-k8s/id_ed25519_pn-production-ansible-role_20250505-163646"
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
    
    # Check inventory file
    if [[ ! -f "${INVENTORY_PATH}/inventory.ini" ]]; then
        log_error "Inventory file not found: ${INVENTORY_PATH}/inventory.ini"
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
        if ! grep -q "kube_network_plugin:" "$k8s_config"; then
            log_error "Network plugin not configured in k8s-cluster.yml"
        else
            local network_plugin=$(grep "kube_network_plugin:" "$k8s_config" | cut -d: -f2 | xargs)
            local multus_enabled=$(grep "kube_network_plugin_multus:" "$k8s_config" | cut -d: -f2 | xargs)
            
            log_info "Network plugin: $network_plugin"
            if [[ "$multus_enabled" == "true" && "$network_plugin" == "calico" ]]; then
                log_warning "Multus + Calico may cause CNI deployment issues"
            fi
        fi
    fi
}

# Test SSH connectivity to cluster nodes
check_connectivity() {
    log_info "Testing SSH connectivity to cluster nodes..."
    
    local inventory_file="${INVENTORY_PATH}/inventory.ini"
    local ssh_key="${HOME}/.ssh-manager/keys/pn-production-k8s/id_ed25519_pn-production-ansible-role_20250505-163646"
    local test_hosts=()
    
    # Extract first few hosts for testing
    while IFS= read -r line; do
        if [[ $line =~ ^[a-zA-Z0-9-]+.*ansible_host= ]]; then
            local host_ip=$(echo "$line" | grep -o 'ansible_host=[^ ]*' | cut -d= -f2)
            test_hosts+=("$host_ip")
            [[ ${#test_hosts[@]} -ge 3 ]] && break
        fi
    done < "$inventory_file"
    
    if [[ ${#test_hosts[@]} -eq 0 ]]; then
        log_warning "No hosts found in inventory for connectivity testing"
        return
    fi
    
    local failed_hosts=()
    for host in "${test_hosts[@]}"; do
        if ! timeout 10 ssh -i "$ssh_key" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ansible@"$host" "echo 'SSH test'" >/dev/null 2>&1; then
            failed_hosts+=("$host")
        fi
    done
    
    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        log_error "SSH connectivity failed for hosts: ${failed_hosts[*]}"
    else
        log_success "SSH connectivity verified for test hosts"
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