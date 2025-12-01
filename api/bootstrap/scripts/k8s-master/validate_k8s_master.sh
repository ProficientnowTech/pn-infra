#!/bin/bash
# validate_k8s_master.sh - Validation script for Kubernetes master nodes
# Part of the infrastructure bootstrap system
# Used by: k8s-master role

set -euo pipefail

# Configuration
SCRIPT_NAME="validate_k8s_master.sh"
LOG_FILE="/var/log/bootstrap.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Logging function
log() {
	local level="$1"
	shift
	echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $SCRIPT_NAME: $*" | tee -a "$LOG_FILE"
}

# Result logging functions
log_info() {
	echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
	echo -e "${GREEN}[PASS]${NC} $*"
	((PASSED_CHECKS++))
}

log_fail() {
	echo -e "${RED}[FAIL]${NC} $*"
	((FAILED_CHECKS++))
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*"
	((WARNING_CHECKS++))
}

# Increment total checks counter
check() {
	((TOTAL_CHECKS++))
}

# Check if running as root
check_root() {
	if [[ $EUID -ne 0 ]]; then
		log "ERROR" "This script should be run as root for complete validation"
		log_warn "Running as non-root user, some checks may be skipped"
		return 1
	fi
	return 0
}

# Check system resources
validate_system_resources() {
	log_info "Validating system resources..."

	check
	# Check CPU count
	local cpu_count
	cpu_count=$(nproc)
	if [[ $cpu_count -ge 2 ]]; then
		log_pass "CPU cores: $cpu_count (minimum 2 required)"
	else
		log_fail "CPU cores: $cpu_count (minimum 2 required)"
	fi

	check
	# Check memory
	local memory_gb
	memory_gb=$(free -g | awk '/^Mem:/ {print $2}')
	if [[ $memory_gb -ge 4 ]]; then
		log_pass "Memory: ${memory_gb}GB (minimum 4GB required)"
	else
		log_fail "Memory: ${memory_gb}GB (minimum 4GB required)"
	fi

	check
	# Check disk space
	local disk_space_gb
	disk_space_gb=$(df / | awk 'NR==2 {print int($2/1024/1024)}')
	if [[ $disk_space_gb -ge 50 ]]; then
		log_pass "Root disk space: ${disk_space_gb}GB (minimum 50GB required)"
	else
		log_fail "Root disk space: ${disk_space_gb}GB (minimum 50GB required)"
	fi

	check
	# Check swap is disabled
	if free | awk '/^Swap:/ {exit ($2 != 0)}'; then
		log_pass "Swap is disabled"
	else
		log_fail "Swap is still enabled"
	fi
}

# Check kernel modules
validate_kernel_modules() {
	log_info "Validating kernel modules..."

	local required_modules=(
		"br_netfilter"
		"overlay"
		"ip_vs"
		"ip_vs_rr"
		"ip_vs_wrr"
		"ip_vs_sh"
		"nf_conntrack"
	)

	for module in "${required_modules[@]}"; do
		check
		if lsmod | grep -q "^$module "; then
			log_pass "Kernel module loaded: $module"
		else
			log_fail "Kernel module not loaded: $module"
		fi
	done
}

# Check sysctl settings
validate_sysctl_settings() {
	log_info "Validating sysctl settings..."

	local required_settings=(
		"net.bridge.bridge-nf-call-iptables=1"
		"net.bridge.bridge-nf-call-ip6tables=1"
		"net.ipv4.ip_forward=1"
	)

	for setting in "${required_settings[@]}"; do
		check
		local key value expected_value
		key=$(echo "$setting" | cut -d'=' -f1)
		expected_value=$(echo "$setting" | cut -d'=' -f2)

		if command -v sysctl > /dev/null 2>&1; then
			value=$(sysctl -n "$key" 2> /dev/null || echo "0")
			if [[ "$value" == "$expected_value" ]]; then
				log_pass "Sysctl setting: $key=$value"
			else
				log_fail "Sysctl setting: $key=$value (expected $expected_value)"
			fi
		else
			log_warn "sysctl command not available, skipping: $key"
		fi
	done
}

# Check container runtime
validate_container_runtime() {
	log_info "Validating container runtime..."

	check
	# Check containerd service
	if systemctl is-active --quiet containerd 2> /dev/null; then
		log_pass "containerd service is running"
	else
		log_fail "containerd service is not running"
	fi

	check
	# Check containerd socket
	if [[ -S /run/containerd/containerd.sock ]]; then
		log_pass "containerd socket exists"
	else
		log_fail "containerd socket not found"
	fi

	check
	# Test containerd connectivity
	if command -v ctr > /dev/null 2>&1; then
		if ctr version > /dev/null 2>&1; then
			log_pass "containerd is responsive"
		else
			log_fail "containerd is not responsive"
		fi
	else
		log_warn "ctr command not available"
	fi
}

# Check Kubernetes components
validate_kubernetes_components() {
	log_info "Validating Kubernetes components..."

	local k8s_binaries=("kubelet" "kubeadm" "kubectl")

	for binary in "${k8s_binaries[@]}"; do
		check
		if command -v "$binary" > /dev/null 2>&1; then
			local version
			version=$("$binary" --version 2> /dev/null | head -1 || echo "unknown")
			log_pass "$binary is installed: $version"
		else
			log_fail "$binary is not installed"
		fi
	done

	check
	# Check kubelet service
	if systemctl is-active --quiet kubelet 2> /dev/null; then
		log_pass "kubelet service is running"
	else
		log_fail "kubelet service is not running"
	fi

	check
	# Check kubelet is enabled
	if systemctl is-enabled --quiet kubelet 2> /dev/null; then
		log_pass "kubelet service is enabled"
	else
		log_fail "kubelet service is not enabled"
	fi
}

# Check network configuration
validate_network() {
	log_info "Validating network configuration..."

	check
	# Check if node has IP address
	local ip_addresses
	ip_addresses=$(hostname -I 2> /dev/null | wc -w)
	if [[ $ip_addresses -gt 0 ]]; then
		log_pass "Node has IP address(es): $(hostname -I | tr '\n' ' ')"
	else
		log_fail "Node has no IP addresses"
	fi

	check
	# Check DNS resolution
	if nslookup kubernetes.default.svc.cluster.local > /dev/null 2>&1; then
		log_pass "DNS resolution working (cluster DNS)"
	elif nslookup google.com > /dev/null 2>&1; then
		log_pass "DNS resolution working (external DNS)"
	else
		log_fail "DNS resolution not working"
	fi

	# Check required ports for Kubernetes master
	local required_ports=(
		"6443"  # Kubernetes API server
		"2379"  # etcd client
		"2380"  # etcd peer
		"10250" # Kubelet API
		"10259" # kube-scheduler
		"10257" # kube-controller-manager
	)

	for port in "${required_ports[@]}"; do
		check
		if ss -tlnp | grep -q ":$port "; then
			log_pass "Port $port is in use (service running)"
		else
			log_warn "Port $port is not in use (service may not be started yet)"
		fi
	done
}

# Check Kubernetes cluster status (if cluster is initialized)
validate_cluster_status() {
	log_info "Validating Kubernetes cluster status..."

	# Check if kubectl is configured
	if [[ -f /etc/kubernetes/admin.conf ]]; then
		export KUBECONFIG=/etc/kubernetes/admin.conf

		check
		# Check API server connectivity
		if kubectl cluster-info > /dev/null 2>&1; then
			log_pass "Kubernetes API server is accessible"
		else
			log_fail "Kubernetes API server is not accessible"
		fi

		check
		# Check node status
		local node_status
		node_status=$(kubectl get nodes --no-headers 2> /dev/null | awk '{print $2}' | head -1 || echo "Unknown")
		if [[ "$node_status" == "Ready" ]]; then
			log_pass "Node status: $node_status"
		else
			log_warn "Node status: $node_status (may be normal if cluster is being initialized)"
		fi

		check
		# Check system pods
		local system_pods_ready
		system_pods_ready=$(kubectl get pods -n kube-system --no-headers 2> /dev/null | grep -c "Running" || echo "0")
		if [[ $system_pods_ready -gt 0 ]]; then
			log_pass "System pods running: $system_pods_ready"
		else
			log_warn "No system pods running (cluster may be initializing)"
		fi

	else
		log_info "Cluster not yet initialized (/etc/kubernetes/admin.conf not found)"
		log_info "This is normal for a fresh master node before 'kubeadm init'"
	fi
}

# Check etcd health (if running)
validate_etcd() {
	log_info "Validating etcd..."

	check
	# Check if etcd is running as a pod or service
	if kubectl get pods -n kube-system --no-headers 2> /dev/null | grep -q etcd; then
		log_pass "etcd pod is running"

		check
		# Check etcd health
		if kubectl exec -n kube-system -l component=etcd -- etcdctl endpoint health > /dev/null 2>&1; then
			log_pass "etcd health check passed"
		else
			log_warn "etcd health check failed or not accessible"
		fi
	elif systemctl is-active --quiet etcd 2> /dev/null; then
		log_pass "etcd service is running"
	else
		log_info "etcd not yet running (normal for uninitialized cluster)"
	fi
}

# Check certificates
validate_certificates() {
	log_info "Validating certificates..."

	local cert_dirs=(
		"/etc/kubernetes/pki"
		"/var/lib/etcd"
	)

	for cert_dir in "${cert_dirs[@]}"; do
		check
		if [[ -d "$cert_dir" ]]; then
			log_pass "Certificate directory exists: $cert_dir"

			# Check if directory has proper permissions
			local perms
			perms=$(stat -c "%a" "$cert_dir" 2> /dev/null || echo "000")
			if [[ "$perms" == "755" ]] || [[ "$perms" == "700" ]]; then
				log_pass "Certificate directory permissions: $cert_dir ($perms)"
			else
				log_warn "Certificate directory permissions may be incorrect: $cert_dir ($perms)"
			fi
		else
			log_info "Certificate directory not yet created: $cert_dir (normal before cluster init)"
		fi
	done

	# Check for CA certificate (if exists)
	check
	if [[ -f /etc/kubernetes/pki/ca.crt ]]; then
		log_pass "CA certificate exists"

		# Check certificate validity
		local cert_expiry
		cert_expiry=$(openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -enddate 2> /dev/null | cut -d'=' -f2 || echo "unknown")
		if [[ "$cert_expiry" != "unknown" ]]; then
			log_pass "CA certificate expires: $cert_expiry"
		fi
	else
		log_info "CA certificate not yet created (normal before cluster init)"
	fi
}

# Check firewall configuration
validate_firewall() {
	log_info "Validating firewall configuration..."

	check
	# Check if UFW is installed and configured
	if command -v ufw > /dev/null 2>&1; then
		local ufw_status
		ufw_status=$(ufw status 2> /dev/null | head -1 || echo "inactive")

		if [[ "$ufw_status" == *"active"* ]]; then
			log_pass "UFW firewall is active"

			# Check if required ports are allowed
			local k8s_ports=("6443" "2379" "2380" "10250" "10259" "10257")
			for port in "${k8s_ports[@]}"; do
				if ufw status | grep -q "$port"; then
					log_pass "UFW allows port $port"
				else
					log_warn "UFW may not allow port $port"
				fi
			done
		else
			log_warn "UFW firewall is not active"
		fi
	else
		log_info "UFW not installed (firewall configuration varies)"
	fi
}

# Check package holds
validate_package_holds() {
	log_info "Validating package holds..."

	local k8s_packages=("kubelet" "kubeadm" "kubectl")

	for package in "${k8s_packages[@]}"; do
		check
		if apt-mark showhold | grep -q "^$package$"; then
			log_pass "Package held from updates: $package"
		else
			log_warn "Package not held from updates: $package"
		fi
	done
}

# Print validation summary
print_summary() {
	echo
	log_info "Kubernetes Master Node Validation Summary"
	echo "=========================================="
	echo "Total checks: $TOTAL_CHECKS"
	echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
	echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
	echo -e "Warnings: ${YELLOW}$WARNING_CHECKS${NC}"
	echo "=========================================="

	local success_rate=0
	if [[ $TOTAL_CHECKS -gt 0 ]]; then
		success_rate=$(((PASSED_CHECKS * 100) / TOTAL_CHECKS))
	fi

	echo "Success rate: $success_rate%"
	echo

	if [[ $FAILED_CHECKS -eq 0 ]]; then
		log_pass "Kubernetes master node validation completed successfully!"
		echo
		if [[ $WARNING_CHECKS -gt 0 ]]; then
			echo "Note: There were $WARNING_CHECKS warnings. Review them to ensure optimal configuration."
		fi
		return 0
	else
		echo -e "${RED}Kubernetes master node validation failed!${NC}"
		echo "Please address the failed checks before proceeding with cluster initialization."
		return 1
	fi
}

# Main validation function
main() {
	log "INFO" "Starting Kubernetes master node validation..."

	echo "Kubernetes Master Node Validation"
	echo "=================================="
	echo

	# Run all validation checks
	validate_system_resources
	echo

	validate_kernel_modules
	echo

	validate_sysctl_settings
	echo

	validate_container_runtime
	echo

	validate_kubernetes_components
	echo

	validate_network
	echo

	validate_cluster_status
	echo

	validate_etcd
	echo

	validate_certificates
	echo

	validate_firewall
	echo

	validate_package_holds
	echo

	# Print summary and return appropriate exit code
	if print_summary; then
		log "INFO" "Kubernetes master node validation completed successfully"
		exit 0
	else
		log "ERROR" "Kubernetes master node validation failed"
		exit 1
	fi
}

# Handle script interruption
cleanup() {
	log "WARN" "Validation script interrupted"
	exit 130
}

trap cleanup SIGINT SIGTERM

# Run main function
main "$@"
