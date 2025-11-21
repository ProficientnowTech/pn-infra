#!/usr/bin/env bash

# Kubernetes Productivity Tools Installer
# Installs kubectl, k9s, kubectx/kubens, helm, stern, kustomize, and sets up aliases
# Usage: curl -sSL https://raw.githubusercontent.com/your-repo/install-k8s-tools.sh | bash
# Or: wget -O - https://raw.githubusercontent.com/your-repo/install-k8s-tools.sh | bash

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configuration
readonly LOCAL_BIN="$HOME/.local/bin"
readonly SHELL_RC="$HOME/.${SHELL##*/}rc"

# Utility functions
log() {
    local level="$1" msg="$2"
    local timestamp="$(date '+%H:%M:%S')"
    
    case $level in
        "info") echo -e "${CYAN}[$timestamp]${NC} ${BLUE}INFO${NC} $msg" ;;
        "success") echo -e "${CYAN}[$timestamp]${NC} ${GREEN}SUCCESS${NC} $msg" ;;
        "warn") echo -e "${CYAN}[$timestamp]${NC} ${YELLOW}WARN${NC} $msg" ;;
        "error") echo -e "${CYAN}[$timestamp]${NC} ${RED}ERROR${NC} $msg" ;;
    esac
}

separator() {
    echo -e "${CYAN}================================================================${NC}"
}

fail() {
    log error "$1"
    exit "${2:-1}"
}

check_dependencies() {
    log info "Checking system dependencies..."
    
    local missing=()
    for cmd in curl wget tar; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing required commands: ${missing[*]}. Please install them first."
    fi
    
    log success "All dependencies found"
}

setup_directories() {
    log info "Setting up directories..."
    mkdir -p "$LOCAL_BIN"
    mkdir -p "$HOME/.kube"
    
    # Add local bin to PATH if not already there
    if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
        echo "export PATH=\"\$PATH:$LOCAL_BIN\"" >> "$SHELL_RC"
        export PATH="$PATH:$LOCAL_BIN"
        log info "Added $LOCAL_BIN to PATH in $SHELL_RC"
    fi
}

install_kubectl() {
    if command -v kubectl >/dev/null 2>&1; then
        log info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
        return 0
    fi
    
    log info "Installing kubectl..."
    
    local version
    version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    
    curl -LO "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl "$LOCAL_BIN/"
    
    log success "kubectl $version installed"
}

install_k9s() {
    if command -v k9s >/dev/null 2>&1; then
        log info "k9s already installed: $(k9s version --short 2>/dev/null || echo 'unknown version')"
        return 0
    fi
    
    log info "Installing k9s..."
    
    # Use webi installer for k9s
    if curl -sS https://webi.sh/k9s | sh >/dev/null 2>&1; then
        log success "k9s installed via webi"
    else
        # Fallback to direct installation
        log warn "Webi failed, trying direct installation..."
        local latest_url
        latest_url=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep "browser_download_url.*Linux_amd64.tar.gz" | cut -d '"' -f 4)
        
        wget -O /tmp/k9s.tar.gz "$latest_url"
        tar -xzf /tmp/k9s.tar.gz -C /tmp k9s
        mv /tmp/k9s "$LOCAL_BIN/"
        rm -f /tmp/k9s.tar.gz
        
        log success "k9s installed directly"
    fi
}

install_kubectx_kubens() {
    if command -v kubectx >/dev/null 2>&1 && command -v kubens >/dev/null 2>&1; then
        log info "kubectx/kubens already installed"
        return 0
    fi
    
    log info "Installing kubectx and kubens..."
    
    # Try webi first
    if curl -sS https://webi.sh/kubectx | sh >/dev/null 2>&1 && curl -sS https://webi.sh/kubens | sh >/dev/null 2>&1; then
        log success "kubectx/kubens installed via webi"
    else
        # Fallback to direct installation
        log warn "Webi failed, trying direct installation..."
        
        local version
        version=$(curl -s https://api.github.com/repos/ahmetb/kubectx/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        
        # Install kubectx
        wget -O /tmp/kubectx.tar.gz "https://github.com/ahmetb/kubectx/releases/download/$version/kubectx_${version}_linux_x86_64.tar.gz"
        tar -xzf /tmp/kubectx.tar.gz -C /tmp kubectx
        mv /tmp/kubectx "$LOCAL_BIN/"
        rm -f /tmp/kubectx.tar.gz
        
        # Install kubens
        wget -O /tmp/kubens.tar.gz "https://github.com/ahmetb/kubectx/releases/download/$version/kubens_${version}_linux_x86_64.tar.gz"
        tar -xzf /tmp/kubens.tar.gz -C /tmp kubens
        mv /tmp/kubens "$LOCAL_BIN/"
        rm -f /tmp/kubens.tar.gz
        
        log success "kubectx/kubens $version installed directly"
    fi
}

install_helm() {
    if command -v helm >/dev/null 2>&1; then
        log info "helm already installed: $(helm version --short 2>/dev/null || helm version)"
        return 0
    fi
    
    log info "Installing helm..."
    
    local version
    version=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    wget -O /tmp/helm.tar.gz "https://get.helm.sh/helm-$version-linux-amd64.tar.gz"
    tar -xzf /tmp/helm.tar.gz -C /tmp
    mv /tmp/linux-amd64/helm "$LOCAL_BIN/"
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64
    
    log success "helm $version installed"
}

install_stern() {
    if command -v stern >/dev/null 2>&1; then
        log info "stern already installed: $(stern --version 2>/dev/null || echo 'unknown version')"
        return 0
    fi
    
    log info "Installing stern..."
    
    local version
    version=$(curl -s https://api.github.com/repos/stern/stern/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    wget -O /tmp/stern.tar.gz "https://github.com/stern/stern/releases/download/$version/stern_${version#v}_linux_amd64.tar.gz"
    tar -xzf /tmp/stern.tar.gz -C /tmp stern
    mv /tmp/stern "$LOCAL_BIN/"
    rm -f /tmp/stern.tar.gz
    
    log success "stern $version installed"
}

install_kustomize() {
    if command -v kustomize >/dev/null 2>&1; then
        log info "kustomize already installed: $(kustomize version --short 2>/dev/null || echo 'unknown version')"
        return 0
    fi
    
    log info "Installing kustomize..."
    
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    mv kustomize "$LOCAL_BIN/"
    
    log success "kustomize installed"
}

setup_shell_config() {
    log info "Setting up shell configuration..."
    
    # Detect shell
    local shell_name="${SHELL##*/}"
    local rc_file="$HOME/.${shell_name}rc"
    
    # Create backup
    if [[ -f "$rc_file" ]]; then
        cp "$rc_file" "${rc_file}.backup.$(date +%s)"
        log info "Created backup: ${rc_file}.backup.$(date +%s)"
    fi
    
    # Add configuration section
    cat >> "$rc_file" << 'EOF'

# ============================================================================
# Kubernetes Productivity Tools Configuration
# ============================================================================

# kubectl aliases
alias k=kubectl
alias kgp="kubectl get pods"
alias kgs="kubectl get svc"
alias kgn="kubectl get nodes"
alias kgd="kubectl get deployments"
alias kgns="kubectl get namespaces"
alias kdp="kubectl describe pod"
alias kds="kubectl describe svc"
alias kdd="kubectl describe deployment"
alias kdn="kubectl describe node"
alias klogs="kubectl logs"
alias kexec="kubectl exec -it"
alias kapply="kubectl apply -f"
alias kdelete="kubectl delete -f"

# More advanced aliases
alias kall="kubectl get all --all-namespaces"
alias kwatch="kubectl get pods --watch"
alias ktop="kubectl top nodes && echo && kubectl top pods --all-namespaces"

# kubectl completion
if command -v kubectl >/dev/null 2>&1; then
    if [[ "$SHELL" == *"zsh"* ]]; then
        source <(kubectl completion zsh)
        compdef __start_kubectl k
    elif [[ "$SHELL" == *"bash"* ]]; then
        source <(kubectl completion bash)
        complete -o default -F __start_kubectl k
    fi
fi

# helm completion
if command -v helm >/dev/null 2>&1; then
    if [[ "$SHELL" == *"zsh"* ]]; then
        source <(helm completion zsh)
    elif [[ "$SHELL" == *"bash"* ]]; then
        source <(helm completion bash)
    fi
fi

# ============================================================================
EOF
    
    log success "Shell configuration added to $rc_file"
}

copy_kubeconfig() {
    if [[ -f "$HOME/.kube/config" ]]; then
        log info "kubeconfig already exists at $HOME/.kube/config"
        return 0
    fi
    
    log warn "No kubeconfig found. You'll need to copy it manually:"
    echo
    echo -e "${YELLOW}For remote cluster:${NC}"
    echo "scp -o StrictHostKeyChecking=no -i <ssh-key> user@master-node:/etc/kubernetes/admin.conf ~/.kube/config"
    echo
    echo -e "${YELLOW}Or if cluster is local:${NC}"
    echo "sudo cp /etc/kubernetes/admin.conf ~/.kube/config"
    echo "sudo chown \$(id -u):\$(id -g) ~/.kube/config"
    echo
}

show_completion_message() {
    separator
    log success "🎉 Kubernetes productivity tools installation complete!"
    separator
    
    echo
    echo -e "${GREEN}Installed tools:${NC}"
    echo -e "  ✅ kubectl - Kubernetes command line tool"
    echo -e "  ✅ k9s - Terminal UI for Kubernetes"
    echo -e "  ✅ kubectx/kubens - Context and namespace switching"
    echo -e "  ✅ helm - Kubernetes package manager"
    echo -e "  ✅ stern - Multi-pod log tailing"
    echo -e "  ✅ kustomize - Kubernetes configuration management"
    echo -e "  ✅ Shell aliases and completions"
    
    echo
    echo -e "${GREEN}Useful aliases:${NC}"
    echo -e "  k = kubectl"
    echo -e "  kgp = kubectl get pods"
    echo -e "  kgs = kubectl get svc"
    echo -e "  kgn = kubectl get nodes"
    echo -e "  kdp = kubectl describe pod"
    echo -e "  kds = kubectl describe svc"
    
    echo
    echo -e "${GREEN}Next steps:${NC}"
    echo -e "  1. ${CYAN}source $SHELL_RC${NC} or restart your terminal"
    echo -e "  2. Copy your kubeconfig to ~/.kube/config"
    echo -e "  3. Test with: ${CYAN}k get nodes${NC}"
    echo -e "  4. Launch k9s with: ${CYAN}k9s${NC}"
    
    echo
    separator
}

main() {
    separator
    log info "🚀 Installing Kubernetes Productivity Tools"
    separator
    
    check_dependencies
    setup_directories
    
    # Install tools
    install_kubectl
    install_k9s
    install_kubectx_kubens
    install_helm
    install_stern
    install_kustomize
    
    # Setup configuration
    setup_shell_config
    copy_kubeconfig
    
    show_completion_message
}

# Run main function
main "$@"