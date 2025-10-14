#!/usr/bin/env bash

# Template-Driven Bootstrap Integration Script
# Extends existing bootstrap.sh with template-driven deployment capabilities
# Usage: ./bootstrap-template-driven.sh [--mode template|legacy|hybrid] [--stack base|monitoring|ml|all]

set -Eeuo pipefail

# Colors
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
readonly TARGET_CHART_DIR="$PLATFORM_DIR/target-chart"
readonly BOOTSTRAP_DIR="$PLATFORM_DIR/bootstrap"
readonly CHARTS_DIR="$PLATFORM_DIR/charts"

# Deployment modes
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-template}"  # template, legacy, hybrid
DEPLOYMENT_STACK="${DEPLOYMENT_STACK:-all}"     # base, monitoring, ml, all
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# ============================================================================
# UTILITIES
# ============================================================================

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp="$(date -u '+%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        "info")    printf "${BLUE}[INFO]${NC} %s\n" "$msg" ;;
        "success") printf "${GREEN}[SUCCESS]${NC} %s\n" "$msg" ;;
        "warn")    printf "${YELLOW}[WARN]${NC} %s\n" "$msg" ;;
        "error")   printf "${RED}[ERROR]${NC} %s\n" "$msg" ;;
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
    if ! command -v kubectl &> /dev/null; then
        fail "kubectl is required but not installed"
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        fail "helm is required but not installed"
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        fail "Cannot connect to Kubernetes cluster"
    fi
    
    # Check ArgoCD
    if ! kubectl get namespace argocd &>/dev/null; then
        fail "ArgoCD namespace not found. Run Phase 2 bootstrap first."
    fi
    
    # Check required directories and files
    local required_dirs=("$TARGET_CHART_DIR" "$BOOTSTRAP_DIR" "$CHARTS_DIR")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            fail "Required directory not found: $dir"
        fi
    done
    
    # Validate target-chart
    if [[ ! -f "$TARGET_CHART_DIR/Chart.yaml" ]]; then
        fail "Target-chart not found: $TARGET_CHART_DIR/Chart.yaml"
    fi
    
    log success "Environment validation passed"
}

validate_templates() {
    log info "Validating Helm templates..."
    
    local templates_valid=true
    
    # Test target-chart with different values files
    local values_files=(
        "$BOOTSTRAP_DIR/values-base.yaml"
        "$BOOTSTRAP_DIR/values-monitoring.yaml" 
        "$BOOTSTRAP_DIR/values-ml.yaml"
    )
    
    for values_file in "${values_files[@]}"; do
        if [[ ! -f "$values_file" ]]; then
            log warn "Values file not found: $values_file"
            continue
        fi
        
        log info "Testing template: $(basename "$values_file")"
        if ! helm template test-$(basename "$values_file" .yaml) "$TARGET_CHART_DIR" -f "$values_file" >/dev/null 2>&1; then
            log error "Template validation failed for: $values_file"
            templates_valid=false
        fi
    done
    
    if [[ "$templates_valid" != "true" ]]; then
        fail "Template validation failed"
    fi
    
    log success "Template validation passed"
}

# ============================================================================
# DEPLOYMENT FUNCTIONS
# ============================================================================

deploy_argocd_self_management() {
    log info "🔄 Deploying ArgoCD self-management..."
    
    local argocd_app="$BOOTSTRAP_DIR/argocd-self-management.yaml"
    if [[ ! -f "$argocd_app" ]]; then
        fail "ArgoCD self-management application not found: $argocd_app"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log info "DRY RUN: Would apply ArgoCD self-management"
        kubectl apply -f "$argocd_app" --dry-run=client
    else
        log info "Applying ArgoCD self-management application..."
        kubectl apply -f "$argocd_app"
        
        # Wait for ArgoCD to start managing itself
        log info "Waiting for ArgoCD self-management to sync..."
        kubectl wait --for=condition=Synced application/argocd-self-management -n argocd --timeout=300s
    fi
    
    log success "ArgoCD self-management deployed"
}

deploy_platform_stack() {
    local stack="$1"
    log info "🚀 Deploying platform stack: $stack"
    
    local bootstrap_app=""
    case "$stack" in
        "base")
            bootstrap_app="$BOOTSTRAP_DIR/platform-base.yaml"
            ;;
        "monitoring")
            bootstrap_app="$BOOTSTRAP_DIR/platform-monitoring.yaml"
            ;;
        "ml")
            bootstrap_app="$BOOTSTRAP_DIR/platform-ml.yaml"
            ;;
        *)
            fail "Unknown stack: $stack"
            ;;
    esac
    
    if [[ ! -f "$bootstrap_app" ]]; then
        fail "Bootstrap application not found: $bootstrap_app"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log info "DRY RUN: Would apply $stack stack"
        kubectl apply -f "$bootstrap_app" --dry-run=client
    else
        log info "Applying $stack stack bootstrap application..."
        kubectl apply -f "$bootstrap_app"
        
        # Wait for stack to sync
        local app_name="platform-$stack"
        log info "Waiting for $app_name to sync..."
        kubectl wait --for=condition=Synced application/"$app_name" -n argocd --timeout=600s
    fi
    
    log success "Platform stack '$stack' deployed"
}

deploy_template_driven() {
    log info "🎯 Starting template-driven deployment..."
    separator
    
    # Deploy ArgoCD self-management first (sync-wave -1)
    deploy_argocd_self_management
    
    # Deploy platform stacks based on selection
    case "$DEPLOYMENT_STACK" in
        "base")
            deploy_platform_stack "base"
            ;;
        "monitoring")
            deploy_platform_stack "base"
            deploy_platform_stack "monitoring"
            ;;
        "ml")
            deploy_platform_stack "base"
            deploy_platform_stack "monitoring"
            deploy_platform_stack "ml"
            ;;
        "all")
            deploy_platform_stack "base"
            deploy_platform_stack "monitoring"
            deploy_platform_stack "ml"
            ;;
        *)
            fail "Unknown deployment stack: $DEPLOYMENT_STACK"
            ;;
    esac
    
    log success "✅ Template-driven deployment completed"
}

deploy_legacy() {
    log info "🔄 Starting legacy deployment..."
    
    # Apply the original platform-root-app
    local legacy_root="/home/devsupreme/work/pn-infra/v0.2.0/bootstrap/phase-3-platform-infra/manifests/platform-root-app.yaml"
    
    if [[ ! -f "$legacy_root" ]]; then
        fail "Legacy root application not found: $legacy_root"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log info "DRY RUN: Would apply legacy root application"
        kubectl apply -f "$legacy_root" --dry-run=client
    else
        log info "Applying legacy root application..."
        kubectl apply -f "$legacy_root"
        
        # Wait for applications to sync
        log info "Waiting for platform applications to sync..."
        kubectl wait --for=condition=Synced application/platform-root -n argocd --timeout=600s
    fi
    
    log success "✅ Legacy deployment completed"
}

deploy_hybrid() {
    log info "🔄 Starting hybrid deployment (side-by-side validation)..."
    
    # Deploy both systems for comparison
    deploy_template_driven
    sleep 30  # Give template system time to start
    deploy_legacy
    
    # Compare generated vs static applications
    log info "📊 Comparing template-driven vs legacy applications..."
    
    local template_apps legacy_apps
    template_apps=$(kubectl get applications -n argocd -l managed-by=target-chart -o name 2>/dev/null | wc -l)
    legacy_apps=$(kubectl get applications -n argocd -l managed-by=argocd -o name 2>/dev/null | wc -l)
    
    log info "Template-driven applications: $template_apps"
    log info "Legacy applications: $legacy_apps"
    
    log success "✅ Hybrid deployment completed"
}

# ============================================================================
# STATUS AND MONITORING
# ============================================================================

show_deployment_status() {
    log info "📊 Deployment Status Report"
    separator
    
    # ArgoCD applications
    log info "ArgoCD Applications:"
    kubectl get applications -n argocd -o custom-columns=\
"NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,SYNC-WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave" 2>/dev/null || true
    
    echo ""
    
    # Platform services health
    log info "Platform Services Health:"
    kubectl get pods -A -l managed-by=argocd -o wide 2>/dev/null || true
    
    echo ""
    
    # Template-driven specific status
    if [[ "$DEPLOYMENT_MODE" == "template" || "$DEPLOYMENT_MODE" == "hybrid" ]]; then
        log info "Template-Driven Applications:"
        kubectl get applications -n argocd -l managed-by=target-chart 2>/dev/null || true
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
            
            case "$DEPLOYMENT_MODE" in
                "template")
                    deploy_template_driven
                    ;;
                "legacy")
                    deploy_legacy
                    ;;
                "hybrid")
                    deploy_hybrid
                    ;;
                *)
                    fail "Unknown deployment mode: $DEPLOYMENT_MODE"
                    ;;
            esac
            
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
        *)
            cat << EOF
Template-Driven Bootstrap Script

Usage: $0 [command] [options]

Commands:
  deploy     Deploy platform using specified mode
  status     Show deployment status
  validate   Validate environment and templates

Options:
  --mode template|legacy|hybrid    Deployment mode (default: template)
  --stack base|monitoring|ml|all   Platform stack to deploy (default: all)
  --dry-run                        Show what would be deployed
  --verbose                        Enable verbose output

Examples:
  $0 deploy --mode template --stack base
  $0 deploy --mode hybrid --stack all
  $0 status
  $0 validate

Environment Variables:
  DEPLOYMENT_MODE    Deployment mode
  DEPLOYMENT_STACK   Platform stack
  DRY_RUN           Enable dry run
  VERBOSE           Enable verbose output
EOF
            ;;
    esac
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            DEPLOYMENT_MODE="$2"
            shift 2
            ;;
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
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Run main function
main "$@"