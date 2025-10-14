#!/bin/bash

# Simple ArgoCD project deployment script
# Usage: ./deploy-projects.sh

set -e

PLATFORM_DIR="$(dirname "$(pwd)")"
PROJECT_CHART="$PLATFORM_DIR/project-chart"

echo "Deploying ArgoCD projects..."

# Check requirements
if ! kubectl get ns argocd >/dev/null 2>&1; then
    echo "ERROR: ArgoCD namespace not found. Run Phase 1 (Kubespray) first."
    exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
    echo "ERROR: helm command not found"
    exit 1
fi

if [[ ! -f "$PROJECT_CHART/Chart.yaml" ]]; then
    echo "ERROR: Project chart not found at $PROJECT_CHART"
    exit 1
fi

# Deploy projects
echo "Generating ArgoCD projects from templates..."
helm template argocd-projects "$PROJECT_CHART" \
    -f "$PROJECT_CHART/values-production.yaml" | \
    kubectl apply -f -

# Wait for projects to be created
echo "Waiting for projects to be created..."
sleep 5

# Verify projects
echo "Verifying ArgoCD projects:"
kubectl get appprojects -n argocd

echo ""
echo "✅ ArgoCD projects deployed successfully!"
echo ""
echo "Projects created:"
echo "  - platform-core      (Infrastructure: MetalLB, Ingress, cert-manager, Rook, Vault)"
echo "  - platform-monitoring (Observability: Prometheus, Grafana)"
echo "  - platform-ml         (ML Infrastructure: KubeRay, GPU operator)"
echo ""
echo "You can now deploy applications with: ./deploy.sh"