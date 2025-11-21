#!/bin/bash
# deploy.sh - Main infrastructure deployment orchestrator
# Coordinates all infrastructure deployment phases in the correct order

set -euo pipefail

# Configuration
SCRIPT_NAME="deploy.sh"
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$INFRA_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/infra-deploy-$(date +%Y%m%d_%H%M%S).log"

# Default values
ENVIRONMENT=""
PHASE=""
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
	echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_debug() {
	if [[ "$VERBOSE" == "true" ]]; then
		echo -e "${CYAN}[DEBUG]${NC} $*" | tee -a "$LOG_FILE"
	fi
}

# Usage information
usage() {
	cat << 'EOF'
Infrastructure Deployment Orchestrator

USAGE:
    deploy.sh [OPTIONS]

DESCRIPTION:
    Orchestrates infrastructure deployment phases in the correct order.
    Uses module environment configs for all settings and credentials.

OPTIONS:
    -e, --env ENV              Target environment (development|staging|production)
    -p, --phase PHASE          Run specific phase only
    --dry-run                  Show what would be deployed without executing
    --verbose                  Enable verbose logging
    -h, --help                 Show this help message

PHASES:
    bootstrap                  Generate configuration files from environment configs
    images                     Build role-specific VM images with Packer and upload to MinIO
    templates                  Create resource templates for VM deployment
    nodes                      Deploy VMs using images and templates
    ansible                    Configure deployed VMs and setup Kubernetes cluster

EXAMPLES:
    # Deploy development environment
    deploy.sh --env development

    # Deploy specific phase only
    deploy.sh --env development --phase bootstrap

    # Dry run to see what would happen
    deploy.sh --env development --dry-run

CONFIGURATION:
    Edit module environment configs with your settings:
    modules/bootstrap/environments/development.config.yml

EOF
}

# Check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."

	# Create log directory
	mkdir -p "$LOG_DIR"

	# Check for required directories
	local required_dirs=(
		"bootstrap"
		"internal-developer-platform"
		"kubernetes"
		"nodes"
		"pools"
		"templates"
	)

	local missing_dirs=()

	for dir in "${required_dirs[@]}"; do
		if [[ ! -d "$INFRA_DIR/modules/$dir" ]]; then
			missing_dirs+=("$dir")
		fi
	done

	if [ ${#missing_dirs[@]} -ne 0 ]; then
		log_error "Missing required Directories: ${missing_dirs[*]}"
		exit 1
	else
		log_debug "Directories checks Passed"
	fi

	# Check for required tools
	local required_tools=("yq" "openssl" "terraform")
	local missing_tools=()

	for tool in "${required_tools[@]}"; do
		if ! command -v "$tool" > /dev/null 2>&1; then
			missing_tools+=("$tool")
		fi
	done

	if [ ${#missing_tools[@]} -ne 0 ]; then
		log_error "Missing required tools: ${missing_tools[*]}"
		exit 1
	else
		log_debug "Tools checks Passed"
	fi

	log_success "Prerequisites check passed"
}

# Phase 1: Bootstrap configuration generation
run_bootstrap_phase() {
	log_info "=== Phase 1: Bootstrap Configuration Generation ==="

	local bootstrap_script="$INFRA_DIR/modules/bootstrap/run.sh"

	if [[ ! -f "$bootstrap_script" ]]; then
		log_error "Bootstrap script not found: $bootstrap_script"
		exit 1
	fi

	# Make script executable
	chmod +x "$bootstrap_script"

	log_info "Running bootstrap configuration generation..."

	# Set environment variables for the script
	export ENVIRONMENT
	# export OUTPUT_DIR="$INFRA_DIR/generated"

	if [[ "$DRY_RUN" == "true" ]]; then
		log_info "Would generate configuration files for environment: $ENVIRONMENT"
		return 0
	fi

	cd "$INFRA_DIR/modules/bootstrap"
	if ./run.sh --env "$ENVIRONMENT"; then
		log_success "Bootstrap phase completed successfully"
		# Export variables for other phases
		source <(./run.sh --env "$ENVIRONMENT" | grep "^export ")
	else
		log_error "Bootstrap phase failed"
		exit 1
	fi
}

# Phase 2: VM Images (Packer builds)
run_images_phase() {
	log_info "=== Phase 2: VM Images (Packer Build) ==="

	local images_script="$INFRA_DIR/modules/images/run.sh"

	if [[ ! -f "$images_script" ]]; then
		log_warn "Images script not found, skipping: $images_script"
		return 0
	fi

	chmod +x "$images_script"
	log_info "Building VM images with Packer..."

	local action="plan"
	if [[ "$DRY_RUN" == "false" ]]; then
		action="apply"
	fi

	cd "$INFRA_DIR/modules/images"
	if ./run.sh "$action" --env "$ENVIRONMENT"; then
		log_success "Images phase completed successfully"
	else
		log_error "Images phase failed"
		exit 1
	fi
}

# Phase 3: VM Templates (Resource allocation)
run_templates_phase() {
	log_info "=== Phase 3: VM Templates (Resource Templates) ==="

	local templates_script="$INFRA_DIR/modules/templates/run.sh"

	if [[ ! -f "$templates_script" ]]; then
		log_warn "Templates script not found, skipping: $templates_script"
		return 0
	fi

	chmod +x "$templates_script"
	log_info "Creating resource templates..."

	local action="plan"
	if [[ "$DRY_RUN" == "false" ]]; then
		action="apply"
	fi

	cd "$INFRA_DIR/modules/templates"
	if ./run.sh "$action" --env "$ENVIRONMENT"; then
		log_success "Templates phase completed successfully"
	else
		log_error "Templates phase failed"
		exit 1
	fi
}

# Phase 4: VM Deployment
run_nodes_phase() {
	log_info "=== Phase 4: VM Deployment ==="

	local nodes_script="$INFRA_DIR/modules/nodes/run.sh"

	if [[ ! -f "$nodes_script" ]]; then
		log_warn "Nodes script not found, skipping: $nodes_script"
		return 0
	fi

	chmod +x "$nodes_script"
	log_info "Deploying VMs..."

	local action="plan"
	if [[ "$DRY_RUN" == "false" ]]; then
		action="apply"
	fi

	cd "$INFRA_DIR/modules/nodes"
	if ./run.sh "$action" --env "$ENVIRONMENT"; then
		log_success "Nodes phase completed successfully"
	else
		log_error "Nodes phase failed"
		exit 1
	fi
}

# Phase 5: Ansible Configuration
run_ansible_phase() {
	log_info "=== Phase 5: Ansible Configuration ==="

	local ansible_script="$INFRA_DIR/modules/ansible/run.sh"

	if [[ ! -f "$ansible_script" ]]; then
		log_warn "Ansible script not found, skipping: $ansible_script"
		return 0
	fi

	chmod +x "$ansible_script"
	log_info "Configuring deployed VMs with Ansible..."

	if [[ "$DRY_RUN" == "true" ]]; then
		log_info "Would run Ansible playbooks for infrastructure configuration"
		return 0
	fi

	cd "$INFRA_DIR/modules/ansible"
	if ./run.sh site.yml --env "$ENVIRONMENT"; then
		log_success "Ansible phase completed successfully"
	else
		log_error "Ansible phase failed"
		exit 1
	fi
}

# Run all phases
run_all_phases() {
	log_info "Running all infrastructure deployment phases..."

	run_bootstrap_phase
	run_images_phase
	run_templates_phase
	run_nodes_phase
	run_ansible_phase

	log_success "All phases completed successfully"
}

# Run specific phase
run_specific_phase() {
	local phase="$1"

	log_info "Running specific phase: $phase"

	case "$phase" in
		bootstrap)
			run_bootstrap_phase
			;;
		images)
			run_images_phase
			;;
		templates)
			run_templates_phase
			;;
		nodes)
			run_nodes_phase
			;;
		ansible)
			run_ansible_phase
			;;
		*)
			log_error "Unknown phase: $phase"
			log_error "Valid phases: bootstrap, images, templates, nodes, ansible"
			exit 2
			;;
	esac
}

# Parse command line arguments
parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case $1 in
			-e | --env)
				if [[ -n "${2:-}" ]]; then
					ENVIRONMENT="$2"
					shift 2
				else
					log_error "Environment required after --env"
					exit 2
				fi
				;;
			-p | --phase)
				if [[ -n "${2:-}" ]]; then
					PHASE="$2"
					shift 2
				else
					log_error "Phase required after --phase"
					exit 2
				fi
				;;
			--dry-run)
				DRY_RUN=true
				shift
				;;
			--verbose)
				VERBOSE=true
				shift
				;;
			-h | --help)
				usage
				exit 0
				;;
			*)
				log_error "Unknown option: $1"
				usage
				exit 2
				;;
		esac
	done
}

# Main function
main() {
	log_info "Infrastructure Deployment Orchestrator"
	log_info "Starting deployment process..."

	# Parse command line arguments
	parse_arguments "$@"

	# Environment is required
	if [[ -z "$ENVIRONMENT" ]]; then
		log_error "Environment must be specified with --env"
		usage
		exit 2
	fi

	# Validate environment value
	if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
		log_error "Invalid environment: $ENVIRONMENT. Must be development, staging, or production."
		exit 2
	fi

	# Print configuration
	log_info "Configuration:"
	log_info "  Environment: $ENVIRONMENT"
	if [[ -n "$PHASE" ]]; then
		log_info "  Phase: $PHASE"
	else
		log_info "  Phase: all"
	fi
	log_info "  Dry run: $DRY_RUN"
	log_info "  Verbose: $VERBOSE"
	echo

	# Check prerequisites
	check_prerequisites

	# Run deployment
	if [[ -n "$PHASE" ]]; then
		run_specific_phase "$PHASE"
	else
		run_all_phases
	fi

	if [[ "$DRY_RUN" == "false" ]]; then
		log_success "Infrastructure deployment completed successfully"
		log_info "Log file: $LOG_FILE"
	else
		log_success "Dry run completed successfully"
	fi
}

# Run main function with all arguments
main "$@"
