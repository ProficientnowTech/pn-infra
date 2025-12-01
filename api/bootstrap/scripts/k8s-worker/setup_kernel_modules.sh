#!/bin/bash
# Kubernetes Kernel Modules Setup Script
# Sets up required kernel modules for Kubernetes networking

set -euo pipefail

# Required kernel modules for Kubernetes
MODULES=(
	"br_netfilter"
	"overlay"
	"ip_vs"
	"ip_vs_rr"
	"ip_vs_wrr"
	"ip_vs_sh"
	"nf_conntrack"
)

echo "Setting up kernel modules for Kubernetes..."

# Load modules immediately
for module in "${MODULES[@]}"; do
	echo "Loading module: $module"
	modprobe "$module" || {
		echo "Warning: Failed to load module $module"
		continue
	}
done

# Configure modules to load on boot
echo "Configuring modules for boot persistence..."
cat > /etc/modules-load.d/k8s.conf << EOF
# Kubernetes required kernel modules
br_netfilter
overlay
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

# Configure sysctl parameters for Kubernetes
echo "Configuring sysctl parameters..."
cat > /etc/sysctl.d/k8s.conf << EOF
# Kubernetes networking requirements
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
net.netfilter.nf_conntrack_max = 1048576
EOF

# Apply sysctl parameters
sysctl --system

echo "Kernel modules setup completed successfully"
