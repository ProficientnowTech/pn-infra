#!/bin/bash
set -euo pipefail

# Configuration
ENVIRONMENT="${1:-production}"
ARGOCD_VERSION="${ARGOCD_VERSION:-7.7.8}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
REPO_URL="${REPO_URL:-git@github.com:pnow-devsupreme/pn-infra.git}"

# SSH Configuration - Use provided path or default
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH:-$HOME/.ssh-manager/keys/pn-production/id_ed25519_pn-production-ansible-role_20250505-163646}"
SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS:-github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] $1${NC}"; }

# Check prerequisites
check_prerequisites() {
    log "🔍 Checking prerequisites..."
    command -v kubectl >/dev/null 2>&1 || { error "kubectl required but not installed"; exit 1; }
    command -v helm >/dev/null 2>&1 || { error "helm required but not installed"; exit 1; }
    kubectl cluster-info >/dev/null 2>&1 || { error "Cannot connect to cluster"; exit 1; }

    # Check for SSH private key
    local expanded_ssh_key="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"
    if [[ ! -f "$expanded_ssh_key" ]]; then
        warn "SSH private key not found at: $expanded_ssh_key"
        warn "ArgoCD will be installed but private repository access may not work"
        warn "You can set SSH_PRIVATE_KEY_PATH environment variable to specify the key path"
    else
        log "✓ SSH private key found: $expanded_ssh_key"
    fi
    log "✓ Prerequisites OK"
}

# Create SSH secret for ArgoCD if key exists
create_ssh_secret() {
    local expanded_ssh_key="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"

    if [[ ! -f "$expanded_ssh_key" ]]; then
        warn "Skipping SSH secret creation - private key not found at: $expanded_ssh_key"
        return 0
    fi

    log "🔑 Creating SSH secret for private repository access..."

    # Check if secret already exists
    if kubectl get secret argocd-private-repo -n ${ARGOCD_NAMESPACE} >/dev/null 2>&1; then
        log "✓ SSH secret already exists, updating..."
        kubectl delete secret argocd-private-repo -n ${ARGOCD_NAMESPACE} >/dev/null 2>&1 || true
    fi

    # Create the repository secret with SSH key
    kubectl create secret generic argocd-private-repo \
        --namespace ${ARGOCD_NAMESPACE} \
        --from-literal=url=${REPO_URL} \
        --from-literal=type=git \
        --from-literal=name=pn-infra \
        --from-file=sshPrivateKey=${expanded_ssh_key} \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

    # Label the secret for ArgoCD to recognize it
    kubectl label secret argocd-private-repo \
        --namespace ${ARGOCD_NAMESPACE} \
        argocd.argoproj.io/secret-type=repository \
        --overwrite >/dev/null 2>&1

    log "✓ SSH secret created/updated"
}

# Install ArgoCD
install_argocd() {
    log "🚀 Installing ArgoCD..."

    helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1
    helm repo update >/dev/null 2>&1

    # Create temporary values file for SSH known hosts
    local temp_values=$(mktemp)
    cat > "$temp_values" << EOF
configs:
  ssh:
    knownHosts: |
      ${SSH_KNOWN_HOSTS}
EOF

    helm upgrade --install argocd argo/argo-cd \
        --version ${ARGOCD_VERSION} \
        --namespace ${ARGOCD_NAMESPACE} \
        --create-namespace \
        --set configs.cm.application.resourceTrackingMethod=annotation \
        -f $(dirname $0)/bootstrap-argocd-values.yaml \
        -f "$temp_values" \
        --wait --timeout=600s >/dev/null 2>&1

    # Clean up temporary file
    rm -f "$temp_values"

    log "✓ ArgoCD installed"
}


# Wait for ArgoCD
wait_for_argocd() {
    log "⏳ Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n ${ARGOCD_NAMESPACE} --timeout=300s >/dev/null 2>&1
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-application-controller -n ${ARGOCD_NAMESPACE} --timeout=300s >/dev/null 2>&1
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-repo-server -n ${ARGOCD_NAMESPACE} --timeout=300s >/dev/null 2>&1
    log "✓ ArgoCD ready"
}

# Verify repository access
verify_repository_access() {
    local expanded_ssh_key="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"

    if [[ ! -f "$expanded_ssh_key" ]]; then
        warn "Skipping repository verification - no SSH key provided"
        return 0
    fi

    log "🔍 Verifying repository access..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if kubectl exec -n ${ARGOCD_NAMESPACE} -l app.kubernetes.io/name=argocd-repo-server -- argocd repo list >/dev/null 2>&1; then
            # Give it a moment to register the repository
            sleep 10

            # Check if repository is connected
            if kubectl exec -n ${ARGOCD_NAMESPACE} -l app.kubernetes.io/name=argocd-repo-server -- sh -c "argocd repo list" 2>/dev/null | grep -q "${REPO_URL}"; then
                log "✓ Repository access verified"
                return 0
            fi
        fi

        warn "Attempt $attempt/$max_attempts: Waiting for repository access..."
        sleep 10
        ((attempt++))
    done

    error "Failed to verify repository access after $max_attempts attempts"
    return 1
}


# Show access info
show_access() {
    local password=$(kubectl get secret argocd-initial-admin-secret -n ${ARGOCD_NAMESPACE} -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "not-found")

    echo
    echo -e "${BLUE}🎯 ArgoCD Access:"
    echo -e "   URL: kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
    echo -e "   Username: admin"
    echo -e "   Password: ${password}${NC}"
    echo

    local expanded_ssh_key="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"
    if [[ -f "$expanded_ssh_key" ]]; then
        echo -e "${GREEN}✓ Private repository access configured with SSH key: $expanded_ssh_key${NC}"
    else
        echo -e "${YELLOW}⚠  No SSH key provided - private repository access not configured${NC}"
    fi
    echo
}


# Main
main() {
    log "🚀 Starting platform installation (${ENVIRONMENT})..."

    check_prerequisites
    install_argocd
    create_ssh_secret
    wait_for_argocd
    verify_repository_access
    show_access

    log "✅ ArgoCD installation completed!"
}

main "$@"
