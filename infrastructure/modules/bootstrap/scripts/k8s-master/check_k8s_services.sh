#!/bin/bash
# Kubernetes Services Health Check Script
# Verifies that essential Kubernetes services are running

set -euo pipefail

echo "Checking Kubernetes service health..."

# Services to check
SERVICES=(
	"containerd"
	"kubelet"
)

# Check systemd services
for service in "${SERVICES[@]}"; do
	echo -n "Checking $service service: "
	if systemctl is-active --quiet "$service"; then
		echo "✓ Running"
	else
		echo "✗ Not running"
		echo "Service $service is not active. Status:"
		systemctl status "$service" --no-pager || true
	fi
done

# Check kernel modules
echo "Checking kernel modules..."
MODULES=("br_netfilter" "overlay" "ip_vs")
for module in "${MODULES[@]}"; do
	echo -n "Checking $module module: "
	if lsmod | grep -q "$module"; then
		echo "✓ Loaded"
	else
		echo "✗ Not loaded"
	fi
done

# Check sysctl parameters
echo "Checking sysctl parameters..."
SYSCTL_PARAMS=(
	"net.bridge.bridge-nf-call-iptables"
	"net.bridge.bridge-nf-call-ip6tables"
	"net.ipv4.ip_forward"
)

for param in "${SYSCTL_PARAMS[@]}"; do
	echo -n "Checking $param: "
	value=$(sysctl -n "$param" 2> /dev/null || echo "not set")
	if [ "$value" = "1" ]; then
		echo "✓ Enabled"
	else
		echo "✗ Value: $value"
	fi
done

# Check swap
echo -n "Checking swap status: "
if [ "$(cat /proc/swaps | wc -l)" -le 1 ]; then
	echo "✓ Disabled"
else
	echo "✗ Enabled"
	cat /proc/swaps
fi

# Check containerd socket
echo -n "Checking containerd socket: "
if [ -S "/var/run/containerd/containerd.sock" ]; then
	echo "✓ Available"
else
	echo "✗ Not found"
fi

echo "Kubernetes services health check completed"
