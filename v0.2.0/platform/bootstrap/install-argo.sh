#!/bin/bash
set -euo pipefail

# Configuration
ENVIRONMENT="${1:-production}"
ARGOCD_VERSION="${ARGOCD_VERSION:-8.6.3}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
REPO_URL="${REPO_URL:-git@github.com:pnow-devsupreme/pn-infra.git}"
REPO_NAME="${REPO_NAME:-pn-infra}"

# SSH Configuration
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/github_keys}"
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
    log "✓ Prerequisites OK"
}

# Install ArgoCD
install_argocd() {
    log "🚀 Installing ArgoCD..."

    helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
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

# Wait for ArgoCD to be fully ready
wait_for_argocd() {
    log "⏳ Waiting for ArgoCD to be ready..."

    # Wait for pods to be ready with kubectl wait (extended timeouts)
    log "⏳ Waiting for ArgoCD pods to be ready (timeout: 900s)..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n ${ARGOCD_NAMESPACE} --timeout=900s >/dev/null 2>&1
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-application-controller -n ${ARGOCD_NAMESPACE} --timeout=900s >/dev/null 2>&1
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-repo-server -n ${ARGOCD_NAMESPACE} --timeout=900s >/dev/null 2>&1

    # Additional wait for services to be fully operational with 1-second intervals (extended timeout)
    log "⏳ Waiting for ArgoCD services to be operational (checking every second for 90 seconds)..."
    local max_attempts=90
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        # Get detailed pod status
        local pod_status=$(kubectl get pods -n ${ARGOCD_NAMESPACE} -l app.kubernetes.io/part-of=argocd -o jsonpath='{range .items[*]}{.metadata.name}: {.status.phase} {.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null || echo "No pods found")

        # Count ready pods
        local ready_pods=$(echo "$pod_status" | grep "true" | wc -l)
        local total_pods=$(echo "$pod_status" | grep -c ":" || echo "0")

        if [[ $ready_pods -eq $total_pods && $total_pods -gt 0 ]]; then
            log "✓ All $total_pods ArgoCD pods ready and operational after $attempt seconds"
            break
        fi

        # Log detailed progress every time (1-second intervals)
        info "ArgoCD status [${attempt}/${max_attempts}]: $ready_pods/$total_pods pods ready"
        if [[ $attempt -eq 1 || $((attempt % 10)) -eq 0 ]]; then
            # Show detailed pod status every 10 attempts (less verbose)
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    info "  - $line"
                fi
            done <<< "$pod_status"
        fi

        sleep 1
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        warn "⚠️  ArgoCD services check timed out after ${max_attempts} seconds"
        warn "Current pod status:"
        kubectl get pods -n ${ARGOCD_NAMESPACE} -l app.kubernetes.io/part-of=argocd 2>/dev/null || warn "Cannot get pod status"
    else
        log "✓ All ArgoCD pods confirmed ready"
    fi

    log "✓ ArgoCD ready"
}

# Get ArgoCD admin password
get_argocd_password() {
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        # Try to get the password from the initial admin secret
        local password=$(kubectl get secret argocd-initial-admin-secret -n ${ARGOCD_NAMESPACE} -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

        if [[ -n "$password" ]]; then
            echo "$password"
            return 0
        fi

        # If we can't find the initial admin secret, try getting it from the argocd-secret
        if [[ $attempt -eq 5 ]]; then
            info "Trying alternative method to get ArgoCD password..."
            password=$(kubectl get secret argocd-secret -n ${ARGOCD_NAMESPACE} -o jsonpath="{.data.admin\.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

            if [[ -n "$password" ]]; then
                echo "$password"
                return 0
            fi
        fi

        if [[ $attempt -eq 1 ]]; then
            info "Waiting for ArgoCD password to be generated..."
        elif [[ $((attempt % 5)) -eq 0 ]]; then
            info "Still waiting for ArgoCD password... (attempt $attempt/$max_attempts)"
        fi

        sleep 2
        ((attempt++))
    done

    error "Failed to retrieve ArgoCD admin password after $max_attempts attempts"
    error "You may need to check the ArgoCD pods and secrets manually:"
    error "  kubectl get pods -n ${ARGOCD_NAMESPACE}"
    error "  kubectl get secrets -n ${ARGOCD_NAMESPACE} | grep admin"
    return 1
}

# Wait for user to manually add repository and confirm
wait_for_manual_repo_setup() {
    local password=$(get_argocd_password || echo "not-found")

    echo
    echo -e "${BLUE}🎯 ArgoCD Installation Complete - Manual Setup Required"
    echo -e "=================================================${NC}"
    echo
    echo -e "${GREEN}✅ ArgoCD is now installed and ready${NC}"
    echo
    echo -e "${YELLOW}📋 Please complete these steps:${NC}"
    echo
    echo -e "1. ${BLUE}Start port-forward (in a separate terminal):${NC}"
    echo -e "   ${GREEN}kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443${NC}"
    echo
    echo -e "2. ${BLUE}Access ArgoCD Dashboard:${NC}"
    echo -e "   ${GREEN}https://localhost:8080${NC}"
    echo
    echo -e "3. ${BLUE}Login with:${NC}"
    echo -e "   Username: ${GREEN}admin${NC}"
    echo -e "   Password: ${GREEN}${password}${NC}"
    echo
    echo -e "4. ${BLUE}Add your repository:${NC}"
    echo -e "   - Go to 'Settings' → 'Repositories'"
    echo -e "   - Click 'Connect Repo'"
    echo -e "   - Repository URL: ${GREEN}${REPO_URL}${NC}"
    echo -e "   - Use SSH private key from: ${GREEN}${SSH_PRIVATE_KEY_PATH}${NC}"
    echo
    echo -e "5. ${BLUE}Verify the repository connection is 'Successful'${NC}"
    echo

    local expanded_ssh_key="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"
    if [[ -f "$expanded_ssh_key" ]]; then
        echo -e "${GREEN}✓ SSH key found at: $expanded_ssh_key${NC}"
    else
        echo -e "${YELLOW}⚠  SSH key not found at: $expanded_ssh_key${NC}"
        echo -e "   Please ensure you have the correct SSH key for the repository${NC}"
    fi

    echo
    echo -e "${YELLOW}================================================================================${NC}"
    echo -e "${YELLOW}⏳ WAITING: The script will pause here until you confirm the repository is added${NC}"
    echo -e "${YELLOW}================================================================================${NC}"
    echo
    echo -e "After you have successfully added the repository and verified it shows 'Successful'"
    echo -e "connection status in the ArgoCD dashboard, please return here and confirm."
    echo

    while true; do
        echo -e "${BLUE}Please choose:${NC}"
        echo -e "  ${GREEN}y${NC} - Repository added successfully, continue deployment"
        echo -e "  ${YELLOW}n${NC} - I need more time or encountered an issue"
        echo -e "  ${RED}exit${NC} - Abort the deployment"
        echo
        read -p "Have you successfully added the repository to ArgoCD? (y/n/exit): " answer

        case $answer in
            [Yy]* )
                log "✓ Repository setup confirmed - continuing with deployment..."
                return 0
                ;;
            [Nn]* )
                echo
                echo -e "${YELLOW}⏳ Please complete the repository setup and then return here.${NC}"
                echo -e "${YELLOW}   Make sure the repository shows 'Successful' connection status.${NC}"
                echo
                ;;
            [Ee][Xx][Ii][Tt] )
                log "Deployment aborted by user"
                exit 0
                ;;
            * )
                echo -e "${YELLOW}Please answer yes (y), no (n), or exit.${NC}"
                ;;
        esac
    done
}

# Main
main() {
    log "🚀 Starting ArgoCD installation (${ENVIRONMENT})..."

    check_prerequisites
    install_argocd
    wait_for_argocd
    wait_for_manual_repo_setup

    log "✅ ArgoCD installation and repository setup completed!"
    log "🚀 Continuing with platform deployment..."
}

main "$@"
