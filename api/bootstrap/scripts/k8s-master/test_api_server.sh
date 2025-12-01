#!/bin/bash
# Kubernetes API Server Test Script
# Tests API server connectivity and basic functionality

set -euo pipefail

echo "Testing Kubernetes API server..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
	echo "✗ kubectl not found"
	exit 1
fi

# Check if kubeconfig exists
if [ ! -f "/etc/kubernetes/admin.conf" ]; then
	echo "✗ Admin kubeconfig not found at /etc/kubernetes/admin.conf"
	exit 1
fi

export KUBECONFIG=/etc/kubernetes/admin.conf

# Test API server connectivity
echo -n "Testing API server connectivity: "
if kubectl version --client --short &> /dev/null; then
	echo "✓ Connected"
else
	echo "✗ Connection failed"
	exit 1
fi

# Test cluster info
echo -n "Getting cluster info: "
if kubectl cluster-info &> /dev/null; then
	echo "✓ Available"
	kubectl cluster-info
else
	echo "✗ Failed"
	exit 1
fi

# Check node status
echo "Checking node status:"
kubectl get nodes -o wide || true

# Check system pods
echo "Checking system pods:"
kubectl get pods -n kube-system || true

# Check API server health
echo -n "Checking API server health endpoint: "
if kubectl get --raw='/healthz' &> /dev/null; then
	echo "✓ Healthy"
else
	echo "✗ Unhealthy"
fi

echo "API server test completed"
