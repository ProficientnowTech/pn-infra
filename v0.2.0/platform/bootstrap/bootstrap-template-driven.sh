#!/usr/bin/env bash

# Template-Driven Platform Deployment Script
# 2-Phase Architecture: Phase 2 - Deploy platform applications via ArgoCD application factory
# Usage: ./bootstrap-template-driven.sh [command] [options]

set -Eeuo pipefail

# Colors
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
readonly TARGET_CHART_DIR="$PLATFORM_DIR/target-chart"
readonly CHARTS_DIR="$PLATFORM_DIR/charts"
readonly ROOT_DIR="$(dirname "$(dirname "$PLATFORM_DIR")")"

# Deployment configuration
DEPLOYMENT_STACK="${DEPLOYMENT_STACK:-all}" # base, monitoring, ml, all
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# ============================================================================
# UTILITIES
# ============================================================================

log() {
    local level="$1"
    shift
    local msg="$*"

    case "$level" in
    "info") printf "${BLUE}[INFO]${NC} %s\n" "$msg" ;;
    "success") printf "${GREEN}[SUCCESS]${NC} %s\n" "$msg" ;;
    "warn") printf "${YELLOW}[WARN]${NC} %s\n" "$msg" ;;
    "error") printf "${RED}[ERROR]${NC} %s\n" "$msg" ;;
    esac
}

fail() {
    log error "$1"
    exit "${2:-1}"
}

separator() {
    echo "=================================================================================================="
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

validate_environment() {
    log info "Validating template-driven deployment environment..."

    # Check kubectl
    if ! command -v kubectl &>/dev/null; then
        fail "kubectl is required but not installed"
    fi

    # Check helm
    if ! command -v helm &>/dev/null; then
        fail "helm is required but not installed"
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        fail "Cannot connect to Kubernetes cluster. Ensure Phase 1 (Kubespray) is completed."
    fi

    # Check ArgoCD namespace
    if ! kubectl get namespace argocd &>/dev/null; then
        fail "ArgoCD namespace not found. Ensure Phase 1 (Kubespray) deployed ArgoCD successfully."
    fi

    # Check ArgoCD is running
    if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server | grep -q Running; then
        log warn "ArgoCD server may not be fully ready. Deployment may fail."
    fi

    # Check required directories
    local required_dirs=("$TARGET_CHART_DIR" "$CHARTS_DIR")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            fail "Required directory not found: $dir"
        fi
    done

    # Validate target-chart structure
    if [[ ! -f "$TARGET_CHART_DIR/Chart.yaml" ]]; then
        fail "Target-chart Chart.yaml not found: $TARGET_CHART_DIR/Chart.yaml"
    fi

    if [[ ! -f "$TARGET_CHART_DIR/values-production.yaml" ]]; then
        fail "Production values file not found: $TARGET_CHART_DIR/values-production.yaml"
    fi

    log success "Environment validation passed"
}

validate_templates() {
    log info "Validating Helm templates..."

    # Test target-chart template rendering
    local values_file="$TARGET_CHART_DIR/values-production.yaml"

    log info "Testing target-chart template with production values..."
    if ! helm template platform-apps "$TARGET_CHART_DIR" -f "$values_file" >/dev/null 2>&1; then
        log error "Template rendering failed. Testing with debug output:"
        helm template platform-apps "$TARGET_CHART_DIR" -f "$values_file" || fail "Target-chart template validation failed"
    fi

    # Validate that template generates expected applications
    local rendered_apps
    rendered_apps=$(helm template platform-apps "$TARGET_CHART_DIR" -f "$values_file" | grep "kind: Application" | wc -l)
    log info "Target-chart will generate $rendered_apps ArgoCD applications"

    if [[ "$rendered_apps" -eq 0 ]]; then
        fail "No ArgoCD applications would be generated from template"
    fi

    log success "Template validation passed"
}

# ============================================================================
# DEPLOYMENT FUNCTIONS
# ============================================================================

get_applications_by_stack() {
    local stack="$1"
    local values_file="$TARGET_CHART_DIR/values-production.yaml"

    case "$stack" in
    "base")
        # Infrastructure foundation applications (sync-wave -1 to 3)
        echo "metallb-config ingress-nginx-config cert-manager-config rook-ceph rook-ceph-cluster vault"
        ;;
    "monitoring")
        # Monitoring applications (sync-wave 4-5)
        echo "prometheus grafana"
        ;;
    "ml")
        # ML infrastructure applications (sync-wave 6-8)
        echo "kuberay-crds kuberay-operator gpu-operator"
        ;;
    "all")
        # All applications
        echo "metallb-config ingress-nginx-config cert-manager-config rook-ceph rook-ceph-cluster vault prometheus grafana kuberay-crds kuberay-operator gpu-operator"
        ;;
    *)
        fail "Unknown stack: $stack"
        ;;
    esac
}

create_filtered_values() {
    local stack="$1"
    local temp_values="/tmp/values-${stack}.yaml"
    local apps=($(get_applications_by_stack "$stack"))

    # Read the default configuration from production values
    cat >"$temp_values" <<EOF
# Auto-generated values for stack: $stack
default:
  repoURL: "git@github.com:pnow-devsupreme/pn-infra.git"
  targetRevision: "main"
  project: "platform"

applications:
EOF

    # Add applications for this stack
    for app in "${apps[@]}"; do
        local sync_wave
        case "$app" in
        metallb-config | ingress-nginx-config | cert-manager-config) sync_wave="-1" ;;
        rook-ceph) sync_wave="1" ;;
        rook-ceph-cluster) sync_wave="2" ;;
        vault) sync_wave="3" ;;
        prometheus) sync_wave="4" ;;
        grafana) sync_wave="5" ;;
        kuberay-crds) sync_wave="6" ;;
        kuberay-operator) sync_wave="7" ;;
        gpu-operator) sync_wave="8" ;;
        *) sync_wave="0" ;;
        esac

        cat >>"$temp_values" <<EOF
  - name: $app
    namespace: ${app}
    annotations:
      argocd.argoproj.io/sync-wave: "$sync_wave"
EOF
    done

    echo "$temp_values"
}

deploy_platform_root_application() {
    local stack="$1"
    log info "🚀 Deploying platform root application for stack: $stack"

    # Create filtered values file for the stack
    local temp_values
    temp_values=$(create_filtered_values "$stack")

    # Create the platform root application manifest
    local root_app_manifest="/tmp/platform-root-${stack}.yaml"

    cat >"$root_app_manifest" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-${stack}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: file://$TARGET_CHART_DIR
    path: .
    helm:
      valueFiles:
        - file://${temp_values}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

    if [[ "$DRY_RUN" == "true" ]]; then
        log info "DRY RUN: Would apply platform root application:"
        cat "$root_app_manifest"
        return
    fi

    # Apply the root application
    log info "Applying platform root application..."
    kubectl apply -f "$root_app_manifest"

    # Wait for the application to sync
    log info "Waiting for platform-${stack} to sync..."
    if kubectl wait --for=condition=Synced application/platform-${stack} -n argocd --timeout=600s; then
        log success "Platform stack '$stack' synced successfully"
    else
        log warn "Platform stack '$stack' sync timed out, checking status..."
        kubectl describe application/platform-${stack} -n argocd
    fi

    # Clean up temp files
    rm -f "$root_app_manifest" "$temp_values"
}

deploy_via_kubectl() {
    local stack="$1"
    log info "🎯 Deploying platform applications via direct kubectl apply (stack: $stack)"

    # Create filtered values and render templates
    local temp_values
    temp_values=$(create_filtered_values "$stack")

    log info "Rendering templates for stack: $stack"
    local rendered_manifest="/tmp/platform-apps-${stack}.yaml"
    helm template platform-apps "$TARGET_CHART_DIR" -f "$temp_values" >"$rendered_manifest"

    if [[ "$DRY_RUN" == "true" ]]; then
        log info "DRY RUN: Would apply the following applications:"
        grep "name:" "$rendered_manifest" | head -20
        rm -f "$rendered_manifest" "$temp_values"
        return
    fi

    # Apply the rendered applications
    log info "Applying platform applications..."
    kubectl apply -f "$rendered_manifest"

    # Wait for applications to appear
    sleep 10

    # Check application sync status
    local apps=($(get_applications_by_stack "$stack"))
    for app in "${apps[@]}"; do
        if kubectl get application "$app" -n argocd &>/dev/null; then
            log info "⏳ Waiting for $app to sync..."
            kubectl wait --for=condition=Synced application/"$app" -n argocd --timeout=300s ||
                log warn "Application $app sync timeout - check manually"
        else
            log warn "Application $app not found after deployment"
        fi
    done

    # Clean up temp files
    rm -f "$rendered_manifest" "$temp_values"

    log success "Platform stack '$stack' deployed"
}

# ============================================================================
# STATUS AND MONITORING
# ============================================================================

show_deployment_status() {
    log info "📊 Deployment Status Report"
    separator

    # Check if ArgoCD is available
    if ! kubectl get namespace argocd &>/dev/null; then
        log warn "ArgoCD namespace not found. Phase 1 (Kubespray) may not be completed."
        return
    fi

    # ArgoCD applications
    log info "ArgoCD Applications:"
    if kubectl get applications -n argocd &>/dev/null; then
        kubectl get applications -n argocd -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,SYNC-WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave"
    else
        echo "No applications found"
    fi

    echo ""

    # Platform services health summary
    log info "Platform Services Summary:"
    local services=("metallb-system" "ingress-nginx" "cert-manager" "rook-ceph" "vault" "monitoring" "kuberay-system")
    for ns in "${services[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pod_count
            pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
            local running_count
            running_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep Running | wc -l)
            printf "  %-20s: %s/%s pods running\n" "$ns" "$running_count" "$pod_count"
        fi
    done

    echo ""

    # Template-driven applications
    log info "Template-Driven Applications:"
    if kubectl get applications -n argocd -l 'argocd.argoproj.io/instance' &>/dev/null; then
        kubectl get applications -n argocd -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"
    else
        echo "No template-driven applications found"
    fi
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    local cmd="${1:-deploy}"

    case "$cmd" in
    "deploy")
        validate_environment
        validate_templates

        log info "🎯 Starting template-driven deployment (stack: $DEPLOYMENT_STACK)..."
        separator

        # Use direct kubectl approach (simpler and more reliable)
        deploy_via_kubectl "$DEPLOYMENT_STACK"

        echo ""
        show_deployment_status
        ;;
    "status")
        show_deployment_status
        ;;
    "validate")
        validate_environment
        validate_templates
        log success "✅ All validations passed"
        ;;
    "help" | "--help" | "-h")
        cat <<EOF
Template-Driven Platform Deployment Script

Usage: $0 [command] [options]

Commands:
  deploy     Deploy platform applications using template-driven approach
  status     Show deployment status and health
  validate   Validate environment and templates
  help       Show this help message

Options:
  --stack base|monitoring|ml|all   Platform stack to deploy (default: all)
  --dry-run                        Show what would be deployed without applying
  --verbose                        Enable verbose output

Stacks:
  base        Infrastructure foundation (MetalLB, Ingress, cert-manager, Rook-Ceph, Vault)
  monitoring  Monitoring stack (Prometheus, Grafana) - requires base
  ml          ML infrastructure (KubeRay, GPU operator) - requires base + monitoring
  all         Complete platform (all applications)

Examples:
  $0 deploy --stack base           # Deploy core infrastructure only
  $0 deploy --stack all            # Deploy complete platform
  $0 status                        # Check deployment status
  $0 validate                      # Validate environment
  $0 deploy --stack ml --dry-run   # Preview ML stack deployment

Prerequisites:
  - Phase 1 (Kubespray) completed with ArgoCD deployed
  - kubectl configured to access the cluster
  - helm installed locally

Environment Variables:
  DEPLOYMENT_STACK   Platform stack (base|monitoring|ml|all)
  DRY_RUN           Enable dry run (true|false)
  VERBOSE           Enable verbose output (true|false)
EOF
        ;;
    *)
        log error "Unknown command: $cmd"
        log info "Use '$0 help' for usage information"
        exit 1
        ;;
    esac
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
    --stack)
        DEPLOYMENT_STACK="$2"
        shift 2
        ;;
    --dry-run)
        DRY_RUN="true"
        shift
        ;;
    --verbose)
        VERBOSE="true"
        set -x
        shift
        ;;
    deploy | status | validate | help)
        break
        ;;
    *)
        log error "Unknown option: $1"
        log info "Use '$0 help' for usage information"
        exit 1
        ;;
    esac
done

# Run main function
main "$@"
