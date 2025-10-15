#!/usr/bin/env bash

# Enhanced Template-Driven Platform Deployment Script
# Deploys complete platform infrastructure using target-chart with proper values files
# Usage: ./deploy.sh [environment] [options]

set -Eeuo pipefail

# Colors for output
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
readonly TARGET_CHART_DIR="$PLATFORM_DIR/target-chart"
readonly PROJECT_CHART_DIR="$PLATFORM_DIR/project-chart"
readonly ROOT_DIR="$(dirname "$(dirname "$PLATFORM_DIR")")"

# Default values
ENVIRONMENT="production"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"
WAIT_FOR_SYNC="${WAIT_FOR_SYNC:-true}"
DEPLOY_PROJECTS="${DEPLOY_PROJECTS:-true}"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    case "$level" in
    "info") printf "${BLUE}[INFO]${NC} %s - %s\n" "$timestamp" "$msg" ;;
    "success") printf "${GREEN}[SUCCESS]${NC} %s - %s\n" "$timestamp" "$msg" ;;
    "warn") printf "${YELLOW}[WARN]${NC} %s - %s\n" "$timestamp" "$msg" ;;
    "error") printf "${RED}[ERROR]${NC} %s - %s\n" "$timestamp" "$msg" ;;
    "debug") [[ "$DEBUG" == "true" ]] && printf "${CYAN}[DEBUG]${NC} %s - %s\n" "$timestamp" "$msg" ;;
    "verbose") [[ "$VERBOSE" == "true" || "$DEBUG" == "true" ]] && printf "${CYAN}[VERBOSE]${NC} %s - %s\n" "$timestamp" "$msg" ;;
    esac
}

fail() {
    log error "$1"
    exit "${2:-1}"
}

separator() {
    echo "=================================================================================================="
}

banner() {
    separator
    echo "🚀 PLATFORM DEPLOYMENT - TEMPLATE-DRIVEN ARCHITECTURE"
    echo "Environment: $ENVIRONMENT"
    echo "Target Chart: $TARGET_CHART_DIR"
    echo "Values File: $TARGET_CHART_DIR/values-${ENVIRONMENT}.yaml"
    [[ "$DRY_RUN" == "true" ]] && echo "MODE: DRY RUN"
    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Enabled"
    [[ "$VERBOSE" == "true" ]] && echo "VERBOSE: Enabled"
    separator
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

validate_environment() {
    log info "Validating deployment environment..."

    # Check required tools
    local required_tools=("kubectl" "helm")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            fail "$tool is required but not installed"
        fi
        log verbose "$tool found: $(command -v "$tool")"
    done

    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        fail "Cannot connect to Kubernetes cluster. Check kubeconfig and cluster status."
    fi
    log verbose "Kubernetes cluster connection verified"

    # Check ArgoCD namespace exists
    if ! kubectl get namespace argocd &>/dev/null; then
        fail "ArgoCD namespace not found. Ensure ArgoCD is deployed in Phase 1 (Kubespray)."
    fi
    log verbose "ArgoCD namespace found"

    # Check ArgoCD server is running
    if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
        fail "ArgoCD server deployment not found. Ensure ArgoCD is properly deployed."
    fi

    local argocd_ready
    argocd_ready=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$argocd_ready" == "0" ]]; then
        log warn "ArgoCD server may not be fully ready. Deployment may encounter issues."
    else
        log verbose "ArgoCD server is ready ($argocd_ready replicas)"
    fi

    # Validate target-chart structure
    if [[ ! -d "$TARGET_CHART_DIR" ]]; then
        fail "Target chart directory not found: $TARGET_CHART_DIR"
    fi

    if [[ ! -f "$TARGET_CHART_DIR/Chart.yaml" ]]; then
        fail "Target chart Chart.yaml not found: $TARGET_CHART_DIR/Chart.yaml"
    fi

    local values_file="$TARGET_CHART_DIR/values-${ENVIRONMENT}.yaml"
    if [[ ! -f "$values_file" ]]; then
        fail "Values file not found: $values_file"
    fi
    log verbose "Values file found: $values_file"

    # Validate project-chart if needed
    if [[ "$DEPLOY_PROJECTS" == "true" ]]; then
        if [[ ! -d "$PROJECT_CHART_DIR" ]]; then
            fail "Project chart directory not found: $PROJECT_CHART_DIR"
        fi
        
        if [[ ! -f "$PROJECT_CHART_DIR/Chart.yaml" ]]; then
            fail "Project chart Chart.yaml not found: $PROJECT_CHART_DIR/Chart.yaml"
        fi
        
        if [[ ! -f "$PROJECT_CHART_DIR/values-production.yaml" ]]; then
            fail "Project chart values not found: $PROJECT_CHART_DIR/values-production.yaml"
        fi
        log verbose "Project chart validated"
    fi

    log success "Environment validation completed"
}

validate_templates() {
    log info "Validating Helm templates..."

    local values_file="$TARGET_CHART_DIR/values-${ENVIRONMENT}.yaml"

    # Test template rendering
    log verbose "Testing template rendering with $values_file"
    if ! helm template platform-apps "$TARGET_CHART_DIR" -f "$values_file" >/dev/null 2>&1; then
        log error "Template rendering failed. Debug output:"
        helm template platform-apps "$TARGET_CHART_DIR" -f "$values_file" || fail "Template validation failed"
    fi

    # Count expected applications
    local app_count
    app_count=$(helm template platform-apps "$TARGET_CHART_DIR" -f "$values_file" | grep "kind: Application" | wc -l)
    
    if [[ "$app_count" -eq 0 ]]; then
        fail "No ArgoCD applications would be generated. Check values file configuration."
    fi

    log info "Template validation passed - will generate $app_count ArgoCD applications"
    
    # Show which applications will be deployed
    if [[ "$VERBOSE" == "true" || "$DEBUG" == "true" ]]; then
        log verbose "Applications to be deployed:"
        helm template platform-apps "$TARGET_CHART_DIR" -f "$values_file" | \
            grep -A 2 "kind: Application" | grep "name:" | sed 's/.*name: /  - /' || true
    fi

    # Validate project templates if needed
    if [[ "$DEPLOY_PROJECTS" == "true" ]]; then
        log verbose "Testing project template rendering..."
        if ! helm template argocd-projects "$PROJECT_CHART_DIR" -f "$PROJECT_CHART_DIR/values-production.yaml" >/dev/null 2>&1; then
            log error "Project template rendering failed. Debug output:"
            helm template argocd-projects "$PROJECT_CHART_DIR" -f "$PROJECT_CHART_DIR/values-production.yaml" || fail "Project template validation failed"
        fi
        log verbose "Project template validation passed"
    fi

    log success "Template validation completed"
}

# ============================================================================
# PROJECT DEPLOYMENT FUNCTIONS
# ============================================================================

deploy_argocd_projects() {
    log info "🏗️  Deploying ArgoCD projects..."

    local project_values="$PROJECT_CHART_DIR/values-production.yaml"
    local rendered_projects="/tmp/argocd-projects-$(date +%s).yaml"

    # Render project templates
    log verbose "Rendering ArgoCD projects from project-chart..."
    helm template argocd-projects "$PROJECT_CHART_DIR" \
        -f "$project_values" \
        --namespace argocd > "$rendered_projects"

    if [[ "$DRY_RUN" == "true" ]]; then
        log info "DRY RUN: Would deploy the following projects:"
        echo "----------------------------------------"
        grep -A 1 "kind: AppProject" "$rendered_projects" | grep "name:" | sed 's/.*name: /  ✓ /' || true
        echo "----------------------------------------"
        log info "Rendered projects manifest available at: $rendered_projects"
        return
    fi

    # Apply the projects
    log info "Applying ArgoCD projects to cluster..."
    kubectl apply -f "$rendered_projects"

    # Wait for projects to be created
    sleep 5

    # Verify projects
    log verbose "Verifying ArgoCD projects..."
    if kubectl get appprojects -n argocd &>/dev/null; then
        local project_count
        project_count=$(kubectl get appprojects -n argocd --no-headers | wc -l)
        log success "Created $project_count ArgoCD projects"
        
        if [[ "$VERBOSE" == "true" || "$DEBUG" == "true" ]]; then
            echo "Projects created:"
            kubectl get appprojects -n argocd --no-headers | awk '{print "  ✅ " $1}'
        fi
    else
        log warn "Could not verify project creation"
    fi

    # Clean up rendered manifest
    rm -f "$rendered_projects"
}

# ============================================================================
# APPLICATION DEPLOYMENT FUNCTIONS
# ============================================================================

deploy_platform_applications() {
    log info "🎯 Deploying platform applications for environment: $ENVIRONMENT"

    local values_file="$TARGET_CHART_DIR/values-${ENVIRONMENT}.yaml"
    local rendered_manifest="/tmp/platform-apps-${ENVIRONMENT}-$(date +%s).yaml"

    # Render templates
    log info "Rendering ArgoCD applications from target-chart..."
    helm template platform-apps "$TARGET_CHART_DIR" \
        -f "$values_file" \
        --namespace argocd > "$rendered_manifest"

    if [[ "$DRY_RUN" == "true" ]]; then
        log info "DRY RUN: Would deploy the following applications:"
        echo "----------------------------------------"
        grep -A 1 "kind: Application" "$rendered_manifest" | grep "name:" | sed 's/.*name: /  ✓ /' || true
        echo "----------------------------------------"
        log info "Rendered manifest available at: $rendered_manifest"
        return
    fi

    # Apply the applications
    log info "Applying ArgoCD applications to cluster..."
    kubectl apply -f "$rendered_manifest"

    # Wait a moment for applications to be created
    sleep 5

    # Get list of deployed applications
    local deployed_apps=()
    while IFS= read -r app; do
        [[ -n "$app" ]] && deployed_apps+=("$app")
    done < <(grep -A 1 "kind: Application" "$rendered_manifest" | grep "name:" | sed 's/.*name: //' | tr -d ' ')

    log success "Applied ${#deployed_apps[@]} ArgoCD applications"

    # Optionally wait for sync
    if [[ "$WAIT_FOR_SYNC" == "true" ]]; then
        wait_for_applications_sync "${deployed_apps[@]}"
    fi

    # Clean up rendered manifest
    rm -f "$rendered_manifest"
}

wait_for_applications_sync() {
    local apps=("$@")
    log info "⏳ Waiting for applications to sync..."

    local sync_timeout=600  # 10 minutes
    local check_interval=10  # 10 seconds

    for app in "${apps[@]}"; do
        log verbose "Checking sync status for: $app"
        
        # Wait for application to exist
        local retry_count=0
        while ! kubectl get application "$app" -n argocd &>/dev/null && [[ $retry_count -lt 30 ]]; do
            log debug "Waiting for application $app to be created..."
            sleep 2
            ((retry_count++))
        done

        if ! kubectl get application "$app" -n argocd &>/dev/null; then
            log warn "Application $app not found after waiting"
            continue
        fi

        # Wait for sync with timeout
        log debug "Waiting for $app to sync (timeout: ${sync_timeout}s)"
        if kubectl wait --for=condition=Synced application/"$app" -n argocd --timeout="${sync_timeout}s" 2>/dev/null; then
            log success "✅ $app synced successfully"
        else
            log warn "⚠️  $app sync timeout - checking status..."
            if [[ "$VERBOSE" == "true" || "$DEBUG" == "true" ]]; then
                kubectl get application "$app" -n argocd -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,MESSAGE:.status.conditions[0].message" || true
            fi
        fi
    done
}

# ============================================================================
# STATUS AND MONITORING
# ============================================================================

show_deployment_status() {
    log info "📊 Platform Deployment Status"
    separator

    # ArgoCD Applications
    echo "ArgoCD Applications:"
    if kubectl get applications -n argocd &>/dev/null; then
        kubectl get applications -n argocd \
            -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,SYNC-WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave" \
            --sort-by='.metadata.annotations.argocd\.argoproj\.io/sync-wave'
    else
        echo "  No applications found"
    fi

    echo ""

    # ArgoCD Projects
    echo "ArgoCD Projects:"
    if kubectl get appprojects -n argocd &>/dev/null; then
        kubectl get appprojects -n argocd --no-headers | awk '{print "  ✅ " $1}'
    else
        echo "  No projects found"
    fi

    echo ""

    # Platform Services Health
    echo "Platform Services Health:"
    local namespaces=("metallb-system" "ingress-nginx" "cert-manager" "argocd" "rook-ceph" "vault" "monitoring" "kuberay-system" "gpu-operator-resources")
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local total_pods running_pods
            total_pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
            running_pods=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
            
            if [[ $total_pods -gt 0 ]]; then
                if [[ $running_pods -eq $total_pods ]]; then
                    printf "  ${GREEN}✅${NC} %-25s: %s/%s pods running\n" "$ns" "$running_pods" "$total_pods"
                else
                    printf "  ${YELLOW}⚠️${NC}  %-25s: %s/%s pods running\n" "$ns" "$running_pods" "$total_pods"
                fi
            fi
        fi
    done

    if [[ "$VERBOSE" == "true" || "$DEBUG" == "true" ]]; then
        echo ""
        echo "Application Sync Waves:"
        if kubectl get applications -n argocd &>/dev/null; then
            kubectl get applications -n argocd \
                -o custom-columns="WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave,NAME:.metadata.name,STATUS:.status.sync.status" \
                --sort-by='.metadata.annotations.argocd\.argoproj\.io/sync-wave' | \
                awk 'NR>1 {printf "  Wave %-2s: %-20s (%s)\n", $1, $2, $3}'
        fi
    fi
}

show_access_info() {
    log info "🌐 Platform Access Information"
    separator

    # ArgoCD Access
    echo "ArgoCD Access:"
    
    # Check for LoadBalancer service
    local argocd_lb_ip
    argocd_lb_ip=$(kubectl get service argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$argocd_lb_ip" ]]; then
        echo "  🌍 LoadBalancer: https://$argocd_lb_ip"
    fi

    # Port-forward option
    echo "  🔗 Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  👤 Default user: admin"
    echo "  🔑 Get password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"

    echo ""
    echo "Platform URLs (if ingress is configured):"
    echo "  🎯 ArgoCD: https://argocd.platform.local"
    echo "  📊 Grafana: https://grafana.platform.local"
    echo "  🔍 Prometheus: https://prometheus.platform.local"
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

usage() {
    cat <<EOF
Enhanced Template-Driven Platform Deployment Script

Usage: $0 [environment] [options]

Environments:
  production   Deploy full production stack (15 applications)
  staging      Deploy staging stack (11 applications) 
  development  Deploy development stack (5 applications)

Options:
  -d, --dry-run           Show what would be deployed without applying
  -v, --verbose           Enable verbose output (includes all log levels)
  --debug                 Enable debug mode (bash trace + verbose)
  -w, --no-wait           Don't wait for application sync
  -p, --skip-projects     Skip ArgoCD project deployment
  -h, --help              Show this help message

Examples:
  $0                          # Deploy production environment
  $0 staging                  # Deploy staging environment
  $0 production -d            # Preview production deployment
  $0 development -v           # Deploy development with verbose output
  $0 production --debug       # Deploy with full debug output

Environment Variables:
  DRY_RUN=true               Enable dry run mode
  VERBOSE=true               Enable verbose output  
  DEBUG=true                 Enable debug mode
  WAIT_FOR_SYNC=false        Skip waiting for application sync
  DEPLOY_PROJECTS=false      Skip project deployment

Prerequisites:
  - Kubernetes cluster with ArgoCD deployed
  - kubectl configured and connected to cluster
  - helm installed locally
  - Target-chart values files present for specified environment

The script uses target-chart with environment-specific values files:
  - values-production.yaml   (15 apps: full platform)
  - values-staging.yaml      (11 apps: no ML infrastructure)  
  - values-development.yaml  (5 apps: minimal stack)
EOF
}

main() {
    case "${1:-}" in
    "--help" | "-h" | "help")
        usage
        exit 0
        ;;
    esac

    banner

    # Validate environment parameter
    case "$ENVIRONMENT" in
    "production" | "staging" | "development")
        log info "Deploying $ENVIRONMENT environment"
        ;;
    *)
        log error "Invalid environment: $ENVIRONMENT"
        log info "Valid environments: production, staging, development"
        exit 1
        ;;
    esac

    # Run deployment
    validate_environment
    validate_templates
    
    log info "🚀 Starting platform deployment..."
    
    # Deploy projects first if enabled
    if [[ "$DEPLOY_PROJECTS" == "true" ]]; then
        deploy_argocd_projects
        echo ""
    fi
    
    # Deploy applications
    deploy_platform_applications

    echo ""
    show_deployment_status
    echo ""
    show_access_info

    if [[ "$DRY_RUN" != "true" ]]; then
        log success "🎉 Platform deployment completed!"
        log info "Monitor deployment progress with: kubectl get applications -n argocd -w"
    else
        log info "🔍 Dry run completed - no changes applied"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
    -d|--dry-run)
        DRY_RUN="true"
        shift
        ;;
    -v|--verbose)
        VERBOSE="true"
        shift
        ;;
    --debug)
        DEBUG="true"
        VERBOSE="true"  # Debug implies verbose
        set -x  # Enable bash trace
        shift
        ;;
    -w|--no-wait)
        WAIT_FOR_SYNC="false"
        shift
        ;;
    -p|--skip-projects)
        DEPLOY_PROJECTS="false"
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    production|staging|development)
        ENVIRONMENT="$1"
        shift
        ;;
    *)
        log error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

# Run main function
main "$@"