#!/usr/bin/env bash

# Platform Validation Engine
# Validates platform templates, configurations, and deployment readiness

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-production}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[SUCCESS] [$(date +'%H:%M:%S')] [Validator] $1${NC}"; }
info() { echo -e "${BLUE}[INFO]    [$(date +'%H:%M:%S')] [Validator] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN]    [$(date +'%H:%M:%S')] [Validator] $1${NC}"; }
error() {
	echo -e "${RED}[ERROR]   [$(date +'%H:%M:%S')] [Validator] $1${NC}"
	((ERRORS++))
}

ERRORS=0

# Check required tools for platform deployment
check_tools() {
	info "Checking required tools for platform deployment..."

	local tools=("helm" "kubectl" "git" "yq" "jq")
	for tool in "${tools[@]}"; do
		if ! command -v "$tool" &>/dev/null; then
			error "Missing tool: $tool"
		fi
	done
}

# Check platform directory structure
check_platform_structure() {
	info "Checking platform directory structure..."

	local required_dirs=("stacks" "stack-orchestrator" "project-chart" "bootstrap")
	for dir in "${required_dirs[@]}"; do
		if [[ ! -d "${SCRIPT_DIR}/${dir}" ]]; then
			error "Platform directory missing: $dir"
		fi
	done
}

# Check Helm templates
check_helm_templates() {
	info "Checking Helm templates for environment: $ENVIRONMENT"

	if ! command -v helm &>/dev/null; then
		error "Helm not available - cannot validate templates"
		return
	fi

	# Check stack-orchestrator with environment values
	local stack_orchestrator="${SCRIPT_DIR}/stack-orchestrator"
	local values_file="${stack_orchestrator}/values-${ENVIRONMENT}.yaml"

	if [[ ! -f "$values_file" ]]; then
		error "Environment values file not found: values-${ENVIRONMENT}.yaml"
		return
	fi

	if ! helm template "target-chart-${ENVIRONMENT}" "$stack_orchestrator" -f "$values_file" --dry-run >/dev/null 2>&1; then
		error "Target-chart template validation failed for $ENVIRONMENT"
	else
		log "Target-chart template valid for $ENVIRONMENT"
	fi

	# Check individual stacks
	local stacks=("application-infra" "backup-and-disaster-recovery" "data-streaming" "developer-platform" "development-workloads" "infrastructure" "ml-infra" "monitoring" "platform-data" "security" "storage")
	for stack in "${stacks[@]}"; do
		local stack_dir="${SCRIPT_DIR}/stacks/${stack}/target-chart"
		local stack_values="${stack_dir}/values-${ENVIRONMENT}.yaml"

		if [[ -d "$stack_dir" ]]; then
			if ! helm template "$stack" "$stack_dir" -f "$stack_values" --dry-run >/dev/null 2>&1; then
				error "Chart template validation failed: $stack"
			else
				log "Chart template valid: $stack"
			fi
		fi
	done

	# Check project-chart
	local project_chart="${SCRIPT_DIR}/project-chart"
	local project_chart_values="${project_chart}/values-${ENVIRONMENT}.yaml"
	if [[ -d "$project_chart" ]]; then
		if ! helm template "project-chart" "$project_chart" -f "$project_chart_values" --dry-run >/dev/null 2>&1; then
			error "Project-chart template validation failed"
		else
			log "Project-chart template valid"
		fi
	fi
}

# Check ArgoCD bootstrap configuration
check_argocd_bootstrap() {
	info "Checking ArgoCD bootstrap configuration..."

	local bootstrap_dir="${SCRIPT_DIR}/bootstrap"
	local platform_root="${bootstrap_dir}/platform-root.yaml"

	# Check bootstrap script
	if [[ ! -f "${bootstrap_dir}/install-argo.sh" ]] || [[ ! -x "${bootstrap_dir}/install-argo.sh" ]]; then
		error "Bootstrap script not found or not executable"
	fi

	# Basic YAML syntax check
	if command -v yq &>/dev/null; then
		if ! yq eval '.' "$platform_root" >/dev/null 2>&1; then
			error "Invalid YAML syntax in ArgoCD bootstrap values"
		fi
	fi

	# Check for bootstrap application
	if [[ -f "$platform_root" ]]; then
		log "Bootstrap application found"
	else
		error "Bootstrap application not found"
	fi
}

check_secrets() {
	info "Checking secrets dir..."

	local bootstrap_dir="${SCRIPT_DIR}/bootstrap"
	local secrets_dir="${bootstrap_dir}/bootstrap/secrets"

	if [[ ! -f "${bootstrap_dir}/scripts/render-secrets.sh" ]] || [[ ! -x "${bootstrap_dir}/scripts/render-secrets.sh" ]]; then
		error "Secrets Bootstrap Script Not Found or Not Executable"
	fi

	if [[ ! -d "$secrets_dir" ]] || [[ ! -d "${secrets_dir}/specs" ]]; then
		error "Secrets Bootstrap Directory doesn't exist"
	fi

	if [[ ! -f "${secrets_dir}/.env.local" ]]; then
		error "Secrets env file does not exist"
	fi

	if [[ ! -d "$secrets_dir" ]] || [[ ! -d "${secrets_dir}/specs" ]]; then
		error "Secrets Bootstrap Directory doesn't exist"
	fi

	if [[ ! -f "${secrets_dir}/.env.local" ]]; then
		error "Secrets env file does not exist"
	fi
}

check_namespaces_for_deploying_secrets() {
	info "Checking required namespaces for deploying secrets..."

	local namespaces=("argocd" "external-secrets" "sealed-secrets" "backstage" "cert-manager" "external-dns" "capk-system" "monitoring" "harbor" "kargo" "keycloak" "onuptime" "verdaccio" "postgres-operator")
	for ns in "${namespaces[@]}"; do
		if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
			warn "Namespace not found: $ns, creating it..."
			kubectl create namespace "$ns"
			log "Namespace created: $ns"
		else
			log "Namespace exists: $ns"
		fi
	done
}

# Check cluster connectivity
check_cluster_connectivity() {
	info "Checking cluster connectivity..."

	if ! command -v kubectl &>/dev/null; then
		error "kubectl not available"
		return
	fi

	if ! kubectl cluster-info >/dev/null 2>&1; then
		error "Cannot connect to Kubernetes cluster"
		return
	fi

	# Check if cluster has nodes ready
	local ready_nodes=$(kubectl get nodes --no-headers | grep -c " Ready " || echo "0")
	local total_nodes=$(kubectl get nodes --no-headers | wc -l)

	if [[ $ready_nodes -eq $total_nodes && $total_nodes -gt 0 ]]; then
		log "Cluster connectivity verified ($ready_nodes/$total_nodes nodes ready)"
	else
		warn "Cluster connectivity issues ($ready_nodes/$total_nodes nodes ready)"
	fi
}

check_cluster_capacity() {
	# Requires metrics-server
	if ! kubectl top nodes &>/dev/null; then
		warn "Cannot check cluster capacity (metrics-server not available)"
		return 0
	fi

	# Check for reasonable available resources
	local total_allocatable_cpu=$(kubectl top nodes --no-headers | awk '{sum+=$2} END {print sum}')
	if [[ $total_allocatable_cpu -lt 4 ]]; then
		warn "Cluster has limited CPU resources ($total_allocatable_cpu cores)"
		read -p "Continue anyway? (y/N): " -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && return 1
	fi
}

# Main validation
run_validation() {
	info "Starting platform validation for environment: $ENVIRONMENT"

	check_tools
	check_platform_structure
	check_helm_templates
	check_argocd_bootstrap
	check_namespaces_for_deploying_secrets
	check_secrets
	check_cluster_connectivity
	check_cluster_capacity

	echo
	if [[ $ERRORS -eq 0 ]]; then
		log "Platform validation passed for environment: $ENVIRONMENT"
		return 0
	else
		error "$ERRORS platform validation errors found"
		return 1
	fi
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	run_validation
fi
