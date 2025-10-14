#!/bin/bash

# Complete platform deployment script
# Deploys ArgoCD projects first, then applications
# Usage: ./deploy.sh [stack]
# Stacks: base, monitoring, ml, all (default: all)

set -e

STACK="${1:-all}"
PLATFORM_DIR="$(dirname "$(pwd)")"
TARGET_CHART="$PLATFORM_DIR/target-chart"
PROJECT_CHART="$PLATFORM_DIR/project-chart"

echo "🚀 Complete Platform Deployment (stack: $STACK)"
echo "================================================"

# Check requirements
if ! kubectl get ns argocd >/dev/null 2>&1; then
    echo "ERROR: ArgoCD namespace not found. Run Phase 1 (Kubespray) first."
    exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
    echo "ERROR: helm command not found"
    exit 1
fi

# Step 1: Deploy ArgoCD projects
echo "Step 1: Deploying ArgoCD projects..."
if [[ -f "$PROJECT_CHART/Chart.yaml" ]]; then
    helm template argocd-projects "$PROJECT_CHART" \
        -f "$PROJECT_CHART/values-production.yaml" |
        kubectl apply -f -

    echo "Waiting for projects to be created..."
    sleep 5

    echo "✅ ArgoCD projects created:"
    kubectl get appprojects -n argocd --no-headers | awk '{print "  - " $1}'
else
    echo "⚠️  Project chart not found, skipping project creation"
fi

echo ""

# Step 2: Deploy applications
echo "Step 2: Deploying platform applications (stack: $STACK)..."

# Define applications by stack
case "$STACK" in
"base")
    APPS="metallb-config ingress-nginx-config cert-manager-config rook-ceph rook-ceph-cluster vault"
    ;;
"monitoring")
    APPS="prometheus grafana"
    ;;
"ml")
    APPS="kuberay-crds kuberay-operator gpu-operator"
    ;;
"all")
    APPS="metallb-config ingress-nginx-config cert-manager-config rook-ceph rook-ceph-cluster vault prometheus grafana kuberay-crds kuberay-operator gpu-operator"
    ;;
*)
    echo "ERROR: Unknown stack '$STACK'. Use: base, monitoring, ml, all"
    exit 1
    ;;
esac

# Function to get project for application
get_project_for_app() {
    case "$1" in
    metallb-config | ingress-nginx-config | cert-manager-config | rook-ceph | rook-ceph-cluster | vault)
        echo "platform-core"
        ;;
    prometheus | grafana)
        echo "platform-monitoring"
        ;;
    kuberay-crds | kuberay-operator | gpu-operator)
        echo "platform-ml"
        ;;
    *)
        echo "platform-core"
        ;;
    esac
}

# Create temporary values file
TEMP_VALUES="/tmp/values-$STACK.yaml"
cat >"$TEMP_VALUES" <<EOF
default:
  repoURL: "git@github.com:pnow-devsupreme/pn-infra.git"
  targetRevision: "main"

global:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true

applications:
EOF

# Add applications with sync waves and project mapping
for app in $APPS; do
    case "$app" in
    metallb-config | ingress-nginx-config | cert-manager-config) WAVE="-1" ;;
    rook-ceph) WAVE="1" ;;
    rook-ceph-cluster) WAVE="2" ;;
    vault) WAVE="3" ;;
    prometheus) WAVE="4" ;;
    grafana) WAVE="5" ;;
    kuberay-crds) WAVE="6" ;;
    kuberay-operator) WAVE="7" ;;
    gpu-operator) WAVE="8" ;;
    *) WAVE="0" ;;
    esac

    PROJECT=$(get_project_for_app "$app")

    cat >>"$TEMP_VALUES" <<EOF
  - name: $app
    namespace: $app
    project: $PROJECT
    annotations:
      argocd.argoproj.io/sync-wave: "$WAVE"
EOF
done

echo "Generating ArgoCD applications..."
helm template platform-apps "$TARGET_CHART" -f "$TEMP_VALUES" | kubectl apply -f -

echo "Waiting for applications to be created..."
sleep 5

# Check status
echo ""
echo "📊 Deployment Status:"
echo "===================="

echo "ArgoCD Projects:"
kubectl get appprojects -n argocd --no-headers | awk '{print "  ✅ " $1}'

echo ""
echo "ArgoCD Applications:"
for app in $APPS; do
    if kubectl get application "$app" -n argocd >/dev/null 2>&1; then
        echo "  ✅ $app"
    else
        echo "  ❌ $app"
    fi
done

# Cleanup
rm -f "$TEMP_VALUES"

echo ""
echo "🎉 Deployment complete!"
echo ""
echo "Monitor progress:"
echo "  kubectl get applications -n argocd"
echo "  kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443"
