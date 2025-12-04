#!/usr/bin/env bash

# Platform Validation Engine
# Validates platform templates, configurations, and deployment readiness

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-production}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0

log_info() {
	echo -e "${BLUE}[INFO]    [$(date +'%H:%M:%S')] [Validator]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS] [$(date +'%H:%M:%S')] [Validator]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARN]    [$(date +'%H:%M:%S')] [Validator]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]   [$(date +'%H:%M:%S')] [Validator]${NC} $1"
	((ERRORS++))
}

# Check required tools for platform deployment
check_tools() {
	log_info "Checking required tools for platform deployment..."

	local tools=("helm" "kubectl" "git" "yq" "jq")
	for tool in "${tools[@]}"; do
		if ! command -v "$tool" &>/dev/null; then
			log_error "Missing tool: $tool"
		fi
	done
}

# Check platform directory structure
check_platform_structure() {
	log_info "Checking platform directory structure..."

	local required_dirs=("stacks" "stack-orchestrator" "project-chart" "bootstrap")
	for dir in "${required_dirs[@]}"; do
		if [[ ! -d "${SCRIPT_DIR}/${dir}" ]]; then
			log_error "Platform directory missing: $dir"
		fi
	done

	# Check bootstrap script
	if [[ ! -f "${SCRIPT_DIR}/bootstrap/install-argo.sh" ]] || [[ ! -x "${SCRIPT_DIR}/bootstrap/install-argo.sh" ]]; then
		log_error "Bootstrap script not found or not executable"
	fi
}

# Check Helm templates
check_helm_templates() {
	log_info "Checking Helm templates for environment: $ENVIRONMENT"

	if ! command -v helm &>/dev/null; then
		log_error "Helm not available - cannot validate templates"
		return
	fi

	# Check target-chart with environment values
	local stack_orchestrator="${SCRIPT_DIR}/stack-orchestrator"
	local values_file="${stack_orchestrator}/values-${ENVIRONMENT}.yaml"

	if [[ ! -f "$values_file" ]]; then
		log_error "Environment values file not found: values-${ENVIRONMENT}.yaml"
		return
	fi

	if ! helm template "target-chart-${ENVIRONMENT}" "$stack_orchestrator" -f "$values_file" --dry-run >/dev/null 2>&1; then
		log_error "Target-chart template validation failed for $ENVIRONMENT"
	else
		log_success "Target-chart template valid for $ENVIRONMENT"
	fi

	# Check individual charts
	local stacks=("infrastructure" "storage" "security" "monitoring" "data-streaming" "platform-data" "ml-infra" "developer-platform" "development-workloads" "application-infra" "backup-and-disaster-recovery")
	for stack in "${stacks[@]}"; do
		local stack_dir="${SCRIPT_DIR}/stacks/${chart}/target-chart"
		if [[ -d "$stack_dir" ]]; then
			if ! helm template "$stack" "$stack_dir" --dry-run >/dev/null 2>&1; then
				log_error "Chart template validation failed: $stack"
			else
				log_success "Chart template valid: $stack"
			fi
		fi
	done

	# Check project-chart
	local project_chart="${SCRIPT_DIR}/project-chart"
	if [[ -d "$project_chart" ]]; then
		if ! helm template "project-chart" "$project_chart" --dry-run >/dev/null 2>&1; then
			log_error "Project-chart template validation failed"
		else
			log_success "Project-chart template valid"
		fi
	fi
}

# Check ArgoCD bootstrap configuration
check_argocd_bootstrap() {
	log_info "Checking ArgoCD bootstrap configuration..."

	local bootstrap_dir="${SCRIPT_DIR}/bootstrap"
	local platform_root="${bootstrap_dir}/platform-root.yaml"

	# Basic YAML syntax check
	if command -v yq &>/dev/null; then
		if ! yq eval '.' "$platform_root" >/dev/null 2>&1; then
			log_error "Invalid YAML syntax in ArgoCD bootstrap values"
		fi
	fi

	# Check for repository configuration
	if [[ -f "${platform_root}" ]]; then
		log_success "Bootstrap application configuration found"
	else
		log_warning "Bootstrap application configuration not found"
	fi
}

# Check repository access (basic)
check_repository_access() {
	log_info "Checking repository access configuration..."

	# Check if we're in a git repository
	if [[ -d "${SCRIPT_DIR}/../.git" ]]; then
		log_success "Running from git repository"

		# Check remote configuration
		if git remote get-url origin >/dev/null 2>&1; then
			local repo_url=$(git remote get-url origin)
			log_info "Repository URL: $repo_url"
		fi
	else
		log_warning "Not running from git repository"
	fi
}

check_namespaces_for_deploying_secrets() {
	log_info "Checking required namespaces for deploying secrets..."

	local namespaces=("argocd" "external-secrets" "sealed-secrets" "backstage" "cert-manager" "external-dns" "capk-system" "monitoring" "harbor" "kargo" "keycloak" "onuptime" "verdaccio" "postgres-operator")
	for ns in "${namespaces[@]}"; do
		if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
			log_warning "Namespace not found: $ns, creating it..."
			kubectl create namespace "$ns"
			log_success "Namespace created: $ns"
		else
			log_success "Namespace exists: $ns"
		fi
	done
}

# Check cluster connectivity
check_cluster_connectivity() {
	log_info "Checking cluster connectivity..."

	if ! command -v kubectl &>/dev/null; then
		log_error "kubectl not available"
		return
	fi

	if ! kubectl cluster-info >/dev/null 2>&1; then
		log_error "Cannot connect to Kubernetes cluster"
		return
	fi

	# Check if cluster has nodes ready
	local ready_nodes=$(kubectl get nodes --no-headers | grep -c " Ready " || echo "0")
	local total_nodes=$(kubectl get nodes --no-headers | wc -l)

	if [[ $ready_nodes -eq $total_nodes && $total_nodes -gt 0 ]]; then
		log_success "Cluster connectivity verified ($ready_nodes/$total_nodes nodes ready)"
	else
		log_warning "Cluster connectivity issues ($ready_nodes/$total_nodes nodes ready)"
	fi
}

check_cluster_capacity() {
	# Requires metrics-server
	if ! kubectl top nodes &>/dev/null; then
		log_warning "Cannot check cluster capacity (metrics-server not available)"
		return 0
	fi

	# Check for reasonable available resources
	local total_allocatable_cpu=$(kubectl top nodes --no-headers | awk '{sum+=$2} END {print sum}')
	if [[ $total_allocatable_cpu -lt 4 ]]; then
		log_warning "Cluster has limited CPU resources ($total_allocatable_cpu cores)"
		read -p "Continue anyway? (y/N): " -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && return 1
	fi
}

# Main validation
run_validation() {
	log_info "Starting platform validation for environment: $ENVIRONMENT"

	check_tools
	check_platform_structure
	check_helm_templates
	check_argocd_bootstrap
	check_repository_access
	check_namespaces_for_deploying_secrets
	check_cluster_connectivity
	check_cluster_capacity

	echo
	if [[ $ERRORS -eq 0 ]]; then
		log_success "Platform validation passed for environment: $ENVIRONMENT"
		return 0
	else
		log_error "$ERRORS platform validation errors found"
		return 1
	fi
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	run_validation
fi
