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
PROXMOX_TF_ROOT="$INFRA_DIR/platforms/proxmox/terraform"
PROXMOX_TEMPLATES_DIR="$PROXMOX_TF_ROOT/templates"
PROXMOX_POOLS_DIR="$PROXMOX_TF_ROOT/pools"
PROXMOX_NODES_DIR="$PROXMOX_TF_ROOT/nodes"
API_BIN="$PROJECT_ROOT/api/bin/api"
CONFIG_PACKAGE="core"
METADATA_FILE=""
TF_VARS_FILE=""
API_METADATA_LOADED=false

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

load_environment_config() {
	local env_file="$INFRA_DIR/environments/${ENVIRONMENT}.yaml"
	if [[ ! -f "$env_file" ]]; then
		log_error "Environment file not found: $env_file"
		exit 1
	}

	local pkg
	pkg=$(yq '.configPackage' "$env_file" | tr -d '"')
	if [[ -z "$pkg" || "$pkg" == "null" ]]; then
		pkg="core"
	fi
	CONFIG_PACKAGE="$pkg"
	log_info "Using config package: $CONFIG_PACKAGE"
}

load_metadata_paths() {
	METADATA_FILE="$PROJECT_ROOT/api/outputs/${ENVIRONMENT}/metadata.json"
	if [[ ! -f "$METADATA_FILE" ]]; then
		log_error "API metadata not found at $METADATA_FILE"
		exit 1
	}

	TF_VARS_FILE=$(jq -r '.files.terraform' "$METADATA_FILE")
	if [[ -z "$TF_VARS_FILE" || "$TF_VARS_FILE" == "null" || ! -f "$TF_VARS_FILE" ]]; then
		log_error "Terraform variables not present in metadata; rerun bootstrap phase."
		exit 1
	}
	API_METADATA_LOADED=true
}

generate_api_outputs() {
	if [[ "$DRY_RUN" == "true" ]]; then
		log_info "[DRY-RUN] Would run: $API_BIN generate env --id $ENVIRONMENT --config $CONFIG_PACKAGE --skip-validate"
		return
	}

	log_info "Running API CLI to materialize environment artifacts..."
	"$API_BIN" generate env --id "$ENVIRONMENT" --config "$CONFIG_PACKAGE" --skip-validate | tee -a "$LOG_FILE"
	load_metadata_paths
}

ensure_api_outputs_ready() {
	if [[ "$API_METADATA_LOADED" == "true" ]]; then
		return
	}

	local existing_meta="$PROJECT_ROOT/api/outputs/${ENVIRONMENT}/metadata.json"
	if [[ -f "$existing_meta" ]]; then
		load_metadata_paths
		return
	}

	if [[ "$DRY_RUN" == "true" ]]; then
		log_warn "[DRY-RUN] No existing metadata found; infrastructure phases will be skipped."
		return
	}

	generate_api_outputs
}

stage_tfvars_for_module() {
	local dest_dir="$1"
	ensure_api_outputs_ready

	if [[ -z "$TF_VARS_FILE" || "$TF_VARS_FILE" == "null" ]]; then
		if [[ "$DRY_RUN" == "true" ]]; then
			log_warn "[DRY-RUN] Terraform vars unavailable for ${dest_dir}; skipping staging."
			return 1
		}
		log_error "Terraform vars not available; rerun bootstrap phase."
		exit 1
	}

	if [[ "$DRY_RUN" == "true" ]]; then
		log_info "[DRY-RUN] Would copy $TF_VARS_FILE to ${dest_dir}/terraform.tfvars"
		return 0
	}

	local dest_file="${dest_dir}/terraform.tfvars"
	cp "$TF_VARS_FILE" "$dest_file"
	log_debug "Staged Terraform variables at $dest_file"
	return 0
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
    bootstrap                  Generate API artifacts (schemas, inventories, tfvars)
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
    infrastructure/environments/development.yaml (references config packages)

EOF
}

# Check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."

	# Create log directory
	mkdir -p "$LOG_DIR"

	# Check for required directories
	local required_paths=(
		"platforms/proxmox/terraform/templates"
		"platforms/proxmox/terraform/pools"
		"platforms/proxmox/terraform/nodes"
		"environments"
	)

	local missing_dirs=()

	for rel in "${required_paths[@]}"; do
		if [[ ! -d "$INFRA_DIR/$rel" ]]; then
			missing_dirs+=("$rel")
		fi
	done

	if [ ${#missing_dirs[@]} -ne 0 ]; then
		log_error "Missing required Directories: ${missing_dirs[*]}"
		exit 1
	else
		log_debug "Directories checks Passed"
	fi

	# Check for required tools
	local required_tools=("yq" "jq" "openssl" "terraform")
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

	if [[ ! -x "$API_BIN" ]]; then
		log_error "API binary not found at $API_BIN (build it with 'go build ./api/cmd/api')"
		exit 1
	}

	log_success "Prerequisites check passed"
}

# Phase 1: Bootstrap configuration generation
run_bootstrap_phase() {
	log_info "=== Phase 1: API Artifact Generation ==="
	ensure_api_outputs_ready
	if [[ "$DRY_RUN" == "false" ]]; then
		log_success "Environment artifacts available under api/outputs/${ENVIRONMENT}"
	else
		log_info "[DRY-RUN] Skipped API CLI execution"
	}
}

# Phase 2: VM Images (Packer builds)
run_images_phase() {
	log_info "=== Phase 2: VM Images (Packer Build) ==="

	local images_script="$PROXMOX_TEMPLATES_DIR/run.sh"

	if [[ ! -f "$images_script" ]]; then
		log_warn "Images script not found, skipping: $images_script"
		return 0
	fi

	if ! stage_tfvars_for_module "$PROXMOX_TEMPLATES_DIR"; then
		return 0
	}
	chmod +x "$images_script"
	log_info "Building VM images with Packer..."

	local action="plan"
	if [[ "$DRY_RUN" == "false" ]]; then
		action="apply"
	fi

	cd "$PROXMOX_TEMPLATES_DIR"
	if ./run.sh "$action" --env "$ENVIRONMENT"; then
		log_success "Images phase completed successfully"
	else
		log_error "Images phase failed"
		exit 1
	fi
}

# Phase 3: VM Templates (Resource allocation)
run_templates_phase() {
	log_info "=== Phase 3: Proxmox Resource Pools ==="

	local templates_script="$PROXMOX_POOLS_DIR/run.sh"

	if [[ ! -f "$templates_script" ]]; then
		log_warn "Templates script not found, skipping: $templates_script"
		return 0
	fi

	if ! stage_tfvars_for_module "$PROXMOX_POOLS_DIR"; then
		return 0
	}
	chmod +x "$templates_script"
	log_info "Creating resource templates..."

	local action="plan"
	if [[ "$DRY_RUN" == "false" ]]; then
		action="apply"
	fi

	cd "$PROXMOX_POOLS_DIR"
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

	local nodes_script="$PROXMOX_NODES_DIR/run.sh"

	if [[ ! -f "$nodes_script" ]]; then
		log_warn "Nodes script not found, skipping: $nodes_script"
		return 0
	fi

	if ! stage_tfvars_for_module "$PROXMOX_NODES_DIR"; then
		return 0
	}
	chmod +x "$nodes_script"
	log_info "Deploying VMs..."

	local action="plan"
	if [[ "$DRY_RUN" == "false" ]]; then
		action="apply"
	fi

	cd "$PROXMOX_NODES_DIR"
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

	load_environment_config

	# Print configuration
	log_info "Configuration:"
	log_info "  Environment: $ENVIRONMENT"
	log_info "  Config package: $CONFIG_PACKAGE"
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
