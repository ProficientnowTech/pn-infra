#!/usr/bin/env bash

# Platform Deployment Engine
# Deploys platform applications using ArgoCD

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATION="${1:-deploy}"
ENVIRONMENT="${2:-production}"
SSH_PRIVATE_KEY_PATH="${3:-$HOME/.ssh/github_keys}"
ARGO_TIMEOUT="${4:-300s}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[PLATFORM-DEPLOY]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Deploy ArgoCD if not present
deploy_argocd() {
    log_info "Checking ArgoCD deployment..."

    # Check if ArgoCD is actually deployed by checking for CRDs and server deployment
    if kubectl get crd applications.argoproj.io >/dev/null 2>&1 && kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
        log_success "ArgoCD already deployed"
    else
        log_info "Deploying ArgoCD..."
        if [[ -x "${SCRIPT_DIR}/bootstrap/install-argo.sh" ]]; then
            # Pass SSH key path to install script if provided
            if [[ -n "$SSH_PRIVATE_KEY_PATH" && -f "$SSH_PRIVATE_KEY_PATH" ]]; then
                log_info "Using SSH key: $SSH_PRIVATE_KEY_PATH"
                SSH_PRIVATE_KEY_PATH="$SSH_PRIVATE_KEY_PATH" "${SCRIPT_DIR}/bootstrap/install-argo.sh"
            else
                log_warning "No SSH key provided or key not found - private repo access may not work"
                "${SCRIPT_DIR}/bootstrap/install-argo.sh"
            fi
        else
            log_error "Bootstrap script not found or not executable"
            return 1
        fi
    fi
}


# Deploy platform applications
deploy_platform_applications() {
    log_info "Deploying platform applications for environment: $ENVIRONMENT"

    # Check if cluster is ready
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    # Deploy ArgoCD first
    deploy_argocd

    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout="$ARGO_TIMEOUT" || {
        log_warning "ArgoCD server not ready within timeout"
    }

    # Apply platform root application
    local bootstrap_app="${SCRIPT_DIR}/bootstrap/bootstrap-app-production.yaml"
    if [[ -f "$bootstrap_app" ]]; then
        log_info "Applying platform root application..."
        kubectl apply -f "$bootstrap_app"
        log_success "Platform applications deployment initiated"
    else
        log_error "Bootstrap application not found"
        return 1
    fi
}

# Show deployment status
show_status() {
    log_info "Platform deployment status:"

    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to cluster"
        return 1
    fi

    # Show ArgoCD applications
    if kubectl get namespace argocd >/dev/null 2>&1; then
        echo
        log_info "ArgoCD Applications:"
        kubectl get applications -n argocd 2>/dev/null || log_warning "No applications found"

        echo
        log_info "ArgoCD Pods:"
        kubectl get pods -n argocd

        # Show repository status
        echo
        log_info "ArgoCD Repository Status:"
        kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository 2>/dev/null || log_warning "No repository secrets found"
    else
        log_warning "ArgoCD not deployed"
    fi
}

# Main execution
case $OPERATION in
    deploy)
        deploy_platform_applications
        ;;
    status)
        show_status
        ;;
    *)
        log_error "Unknown operation: $OPERATION"
        exit 1
        ;;
esac

log_success "Platform deployment operation completed!"
