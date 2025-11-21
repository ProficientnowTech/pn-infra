#!/bin/bash
# validate_role.sh - Comprehensive role definition validation
# Part of the infrastructure bootstrap system
# Usage: validate_role.sh [role-definition.yml] [--strict] [--verbose]

set -euo pipefail

# Configuration
SCRIPT_NAME="validate_role.sh"
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEMA_FILE="$BOOTSTRAP_DIR/schemas/role-definition.schema.yml"
DEFINITIONS_DIR="$BOOTSTRAP_DIR/definitions"
SCRIPTS_DIR="$BOOTSTRAP_DIR/scripts"
CLOUD_INIT_DIR="$BOOTSTRAP_DIR/cloud-init"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
STRICT_MODE=false
VERBOSE_MODE=false
EXIT_CODE=0

# Usage information
usage() {
	cat << EOF
Usage: $0 [OPTIONS] <role-definition.yml>

Validates a bootstrap role definition file against the schema and checks
for common issues, missing dependencies, and configuration problems.

OPTIONS:
    -s, --strict        Enable strict validation mode (warnings become errors)
    -v, --verbose       Enable verbose output with detailed checks
    -h, --help         Show this help message

EXAMPLES:
    $0 definitions/k8s-master.yml
    $0 --strict --verbose definitions/k8s-worker.yml
    $0 -sv definitions/my-custom-role.yml

VALIDATION CHECKS:
    • YAML schema validation against bootstrap schema
    • Required files existence (scripts, cloud-init templates)
    • Script syntax validation
    • Cloud-init template validation
    • Network configuration validation
    • Package availability checks
    • Dependency resolution validation
    • Security configuration checks
    • Hardware requirements validation

EXIT CODES:
    0 - Validation passed
    1 - Validation failed with errors
    2 - Invalid arguments or file not found
EOF
}

# Logging functions
log_info() {
	echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*"
	if [[ "$STRICT_MODE" == "true" ]]; then
		EXIT_CODE=1
	fi
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $*"
	EXIT_CODE=1
}

log_debug() {
	if [[ "$VERBOSE_MODE" == "true" ]]; then
		echo -e "${BLUE}[DEBUG]${NC} $*"
	fi
}

# Check if required tools are available
check_prerequisites() {
	local missing_tools=()

	# Check for yq
	if ! command -v yq > /dev/null 2>&1; then
		missing_tools+=("yq")
	fi

	# Check for YAML schema validation (Python packages)
	if ! python3 -c "import yaml, jsonschema" > /dev/null 2>&1; then
		missing_tools+=("python3-yaml and jsonschema (pip install pyyaml jsonschema)")
	fi

	# Check for shellcheck (optional but recommended)
	if ! command -v shellcheck > /dev/null 2>&1; then
		log_debug "shellcheck not found - script syntax validation will be basic"
	fi

	if [[ ${#missing_tools[@]} -gt 0 ]]; then
		log_error "Missing required tools: ${missing_tools[*]}"
		echo "Please install the missing tools and try again."
		exit 2
	fi
}

# Validate YAML schema
validate_yaml_schema() {
	local role_file="$1"

	log_info "Validating YAML schema..."

	if [[ ! -f "$SCHEMA_FILE" ]]; then
		log_error "Schema file not found: $SCHEMA_FILE"
		return 1
	fi

	# Check if YAML is valid
	if ! yq eval . "$role_file" > /dev/null 2>&1; then
		log_error "Invalid YAML in role definition file"
		return 1
	fi

	# Validate against schema using Python
	if python3 -c "import yaml, jsonschema" > /dev/null 2>&1; then
		local validation_output
		if validation_output=$(python3 -c "
import yaml
import jsonschema
import sys

# Load role data (YAML)
with open('$role_file') as f:
    role_data = yaml.safe_load(f)

# Load schema (YAML format)
with open('$SCHEMA_FILE') as f:
    schema = yaml.safe_load(f)

try:
    jsonschema.validate(role_data, schema)
    print('Schema validation passed')
except jsonschema.exceptions.ValidationError as e:
    print(f'Schema validation failed: {e.message}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Validation error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1); then
			log_success "YAML schema validation passed"
		else
			log_error "YAML schema validation failed:"
			echo "$validation_output" | sed 's/^/  /'
			return 1
		fi
	else
		log_warn "YAML schema validation skipped (no validator available)"
	fi
}

# Validate role metadata
validate_role_metadata() {
	local role_file="$1"

	log_info "Validating role metadata..."

	local role_name
	role_name=$(yq e '.role.name // ""' "$role_file")

	if [[ -z "$role_name" ]]; then
		log_error "Role name is missing or empty"
		return 1
	fi

	if [[ ! "$role_name" =~ ^[a-z0-9-]+$ ]]; then
		log_error "Role name contains invalid characters (use lowercase letters, numbers, and hyphens only)"
		return 1
	fi

	local version
	version=$(yq e '.role.version // ""' "$role_file")

	if [[ -z "$version" ]]; then
		log_error "Role version is missing"
		return 1
	fi

	if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		log_error "Role version must follow semantic versioning (e.g., 1.0.0)"
		return 1
	fi

	log_debug "Role: $role_name, Version: $version"
	log_success "Role metadata validation passed"
}

# Validate hardware requirements
validate_hardware() {
	local role_file="$1"

	log_info "Validating hardware requirements..."

	local min_cpu min_memory min_disk
	min_cpu=$(yq e '.hardware.min_cpu // ""' "$role_file")
	min_memory=$(yq e '.hardware.min_memory_gb // ""' "$role_file")
	min_disk=$(yq e '.hardware.min_disk_gb // ""' "$role_file")

	if [[ -z "$min_cpu" ]] || [[ "$min_cpu" -lt 1 ]]; then
		log_error "Invalid minimum CPU requirement: $min_cpu"
		return 1
	fi

	if [[ -z "$min_memory" ]] || [[ "$min_memory" -lt 1 ]]; then
		log_error "Invalid minimum memory requirement: $min_memory GB"
		return 1
	fi

	if [[ -z "$min_disk" ]] || [[ "$min_disk" -lt 10 ]]; then
		log_error "Invalid minimum disk requirement: $min_disk GB"
		return 1
	fi

	# Check for reasonable limits
	if [[ "$min_cpu" -gt 64 ]]; then
		log_warn "Very high CPU requirement: $min_cpu cores"
	fi

	if [[ "$min_memory" -gt 256 ]]; then
		log_warn "Very high memory requirement: $min_memory GB"
	fi

	log_debug "Hardware: ${min_cpu}C/${min_memory}GB RAM/${min_disk}GB disk"
	log_success "Hardware requirements validation passed"
}

# Validate network configuration
validate_network() {
	local role_file="$1"

	log_info "Validating network configuration..."

	local valid_vlans=(
		"management"
		"internal_traffic"
		"public_traffic"
		"storage_public"
		"high_speed_external"
		"nested_cluster_data"
		"nested_cluster_apps"
	)

	local required_vlans
	required_vlans=$(yq e '.network.required_vlans[]? // ""' "$role_file")

	if [[ -z "$required_vlans" ]]; then
		log_error "No required VLANs specified"
		return 1
	fi

	while IFS= read -r vlan; do
		if [[ -n "$vlan" ]]; then
			local found=false
			for valid_vlan in "${valid_vlans[@]}"; do
				if [[ "$vlan" == "$valid_vlan" ]]; then
					found=true
					break
				fi
			done

			if [[ "$found" == "false" ]]; then
				log_error "Invalid VLAN specified: $vlan"
				return 1
			fi

			log_debug "Required VLAN: $vlan"
		fi
	done <<< "$required_vlans"

	# Check firewall rules
	local firewall_rules_count
	firewall_rules_count=$(yq e '.network.firewall_rules | length' "$role_file" 2> /dev/null || echo "0")

	if [[ "$firewall_rules_count" -eq 0 ]]; then
		log_warn "No firewall rules defined - consider adding security rules"
	else
		log_debug "Firewall rules defined: $firewall_rules_count"
	fi

	log_success "Network configuration validation passed"
}

# Validate software packages
validate_software() {
	local role_file="$1"

	log_info "Validating software configuration..."

	# Check base packages
	local base_packages_count
	base_packages_count=$(yq e '.software.base_packages | length' "$role_file" 2> /dev/null || echo "0")

	if [[ "$base_packages_count" -eq 0 ]]; then
		log_warn "No base packages specified"
	else
		log_debug "Base packages specified: $base_packages_count"
	fi

	# Validate Kubernetes tools configuration if present
	local k8s_tools_enabled
	k8s_tools_enabled=$(yq e '.software.kubernetes_tools.kubectl // false' "$role_file")

	if [[ "$k8s_tools_enabled" == "true" ]]; then
		local k8s_version
		k8s_version=$(yq e '.software.kubernetes_tools.version // ""' "$role_file")

		if [[ -z "$k8s_version" ]]; then
			log_error "Kubernetes tools enabled but no version specified"
			return 1
		fi

		if [[ ! "$k8s_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
			log_error "Invalid Kubernetes version format: $k8s_version"
			return 1
		fi

		log_debug "Kubernetes version: $k8s_version"
	fi

	# Check custom repositories
	local repos_count
	repos_count=$(yq e '.software.custom_repositories | length' "$role_file" 2> /dev/null || echo "0")

	if [[ "$repos_count" -gt 0 ]]; then
		log_debug "Custom repositories defined: $repos_count"

		# Validate repository URLs
		local repo_urls
		repo_urls=$(yq e '.software.custom_repositories[].url // ""' "$role_file")

		while IFS= read -r url; do
			if [[ -n "$url" ]]; then
				if [[ ! "$url" =~ ^https?:// ]]; then
					log_error "Invalid repository URL (must use http/https): $url"
					return 1
				fi
				log_debug "Repository URL: $url"
			fi
		done <<< "$repo_urls"
	fi

	log_success "Software configuration validation passed"
}

# Validate scripts
validate_scripts() {
	local role_file="$1"

	log_info "Validating scripts configuration..."

	local role_name
	role_name=$(yq e '.role.name' "$role_file")

	# Check script categories
	local script_categories=("pre_install" "post_install" "startup" "validation")

	for category in "${script_categories[@]}"; do
		local scripts
		scripts=$(yq e ".scripts.${category}[]? // \"\"" "$role_file")

		if [[ -n "$scripts" ]]; then
			while IFS= read -r script; do
				if [[ -n "$script" ]]; then
					local script_path=""

					# Determine script path
					if [[ "$script" == *"/common/"* ]]; then
						script_path="$SCRIPTS_DIR/$script"
					else
						script_path="$SCRIPTS_DIR/$role_name/$script"
					fi

					# Check if script exists
					if [[ ! -f "$script_path" ]]; then
						log_error "Script not found: $script_path"
						return 1
					fi

					# Check if script is executable
					if [[ ! -x "$script_path" ]]; then
						log_warn "Script is not executable: $script_path"
					fi

					# Basic syntax check
					if command -v shellcheck > /dev/null 2>&1; then
						if ! shellcheck "$script_path" > /dev/null 2>&1; then
							log_warn "Script has potential issues (shellcheck): $script"
						fi
					else
						# Basic bash syntax check
						if ! bash -n "$script_path" > /dev/null 2>&1; then
							log_error "Script has syntax errors: $script"
							return 1
						fi
					fi

					log_debug "Validated script: $script"
				fi
			done <<< "$scripts"
		fi
	done

	log_success "Scripts validation passed"
}

# Validate cloud-init template
validate_cloud_init() {
	local role_file="$1"

	log_info "Validating cloud-init configuration..."

	local template_name
	template_name=$(yq e '.cloud_init.template // ""' "$role_file")

	if [[ -n "$template_name" ]]; then
		local template_path="$CLOUD_INIT_DIR/$template_name"

		if [[ ! -f "$template_path" ]]; then
			log_error "Cloud-init template not found: $template_path"
			return 1
		fi

		# Basic YAML syntax check
		if command -v python3 > /dev/null 2>&1; then
			if ! python3 -c "
import yaml
import sys
try:
    with open('$template_path', 'r') as f:
        yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f'YAML syntax error: {e}', file=sys.stderr)
    sys.exit(1)
" 2> /dev/null; then
				log_error "Cloud-init template has YAML syntax errors: $template_name"
				return 1
			fi
		fi

		# Check for cloud-config directive
		if ! head -1 "$template_path" | grep -q "#cloud-config"; then
			log_warn "Cloud-init template should start with #cloud-config directive"
		fi

		log_debug "Cloud-init template: $template_name"
	else
		log_warn "No cloud-init template specified"
	fi

	log_success "Cloud-init configuration validation passed"
}

# Validate dependencies
validate_dependencies() {
	local role_file="$1"

	log_info "Validating dependencies..."

	local required_roles
	required_roles=$(yq e '.dependencies.required_roles[]? // ""' "$role_file")

	if [[ -n "$required_roles" ]]; then
		while IFS= read -r required_role; do
			if [[ -n "$required_role" ]]; then
				local required_role_file="$DEFINITIONS_DIR/${required_role}.yml"

				if [[ ! -f "$required_role_file" ]]; then
					log_error "Required role definition not found: $required_role_file"
					return 1
				fi

				log_debug "Required role found: $required_role"
			fi
		done <<< "$required_roles"
	fi

	local conflicting_roles
	conflicting_roles=$(yq e '.dependencies.conflicting_roles[]? // ""' "$role_file")

	if [[ -n "$conflicting_roles" ]]; then
		while IFS= read -r conflicting_role; do
			if [[ -n "$conflicting_role" ]]; then
				log_debug "Conflicting role: $conflicting_role"
			fi
		done <<< "$conflicting_roles"
	fi

	log_success "Dependencies validation passed"
}

# Validate external services
validate_external_services() {
	local role_file="$1"

	log_info "Validating external services..."

	local services_count
	services_count=$(yq e '.dependencies.external_services | length' "$role_file" 2> /dev/null || echo "0")

	if [[ "$services_count" -gt 0 ]]; then
		local service_hosts
		service_hosts=$(yq e '.dependencies.external_services[].host // ""' "$role_file")

		while IFS= read -r host; do
			if [[ -n "$host" ]]; then
				# Skip VLAN references and localhost
				if [[ "$host" =~ ^(internal_traffic|storage_public|management|localhost|127\.0\.0\.1)$ ]]; then
					log_debug "Internal service host: $host"
					continue
				fi

				# Basic hostname/IP validation
				if [[ ! "$host" =~ ^[a-zA-Z0-9.-]+$ ]]; then
					log_error "Invalid service host format: $host"
					return 1
				fi

				log_debug "External service host: $host"
			fi
		done <<< "$service_hosts"

		log_debug "External services defined: $services_count"
	fi

	log_success "External services validation passed"
}

# Run comprehensive validation
validate_role_comprehensive() {
	local role_file="$1"

	log_info "Starting comprehensive validation for: $role_file"
	echo "----------------------------------------"

	# Run all validation checks
	validate_yaml_schema "$role_file" || return 1
	validate_role_metadata "$role_file" || return 1
	validate_hardware "$role_file" || return 1
	validate_network "$role_file" || return 1
	validate_software "$role_file" || return 1
	validate_scripts "$role_file" || return 1
	validate_cloud_init "$role_file" || return 1
	validate_dependencies "$role_file" || return 1
	validate_external_services "$role_file" || return 1

	echo "----------------------------------------"

	if [[ $EXIT_CODE -eq 0 ]]; then
		log_success "All validation checks passed!"
	else
		log_error "Validation completed with errors"
	fi

	return $EXIT_CODE
}

# Parse command line arguments
parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case $1 in
			-s | --strict)
				STRICT_MODE=true
				shift
				;;
			-v | --verbose)
				VERBOSE_MODE=true
				shift
				;;
			-h | --help)
				usage
				exit 0
				;;
			-*)
				echo "Unknown option: $1"
				usage
				exit 2
				;;
			*)
				if [[ -z "${ROLE_FILE:-}" ]]; then
					ROLE_FILE="$1"
				else
					echo "Multiple role files specified"
					usage
					exit 2
				fi
				shift
				;;
		esac
	done
}

# Main function
main() {
	local role_file="${1:-}"

	if [[ -z "$role_file" ]]; then
		echo "Error: Role definition file not specified"
		echo
		usage
		exit 2
	fi

	if [[ ! -f "$role_file" ]]; then
		log_error "Role definition file not found: $role_file"
		exit 2
	fi

	# Convert to absolute path
	role_file="$(realpath "$role_file")"

	log_info "Bootstrap Role Validation Tool"
	log_info "Role file: $role_file"
	log_info "Strict mode: $STRICT_MODE"
	log_info "Verbose mode: $VERBOSE_MODE"
	echo

	# Check prerequisites
	check_prerequisites

	# Run comprehensive validation
	validate_role_comprehensive "$role_file"

	exit $EXIT_CODE
}

# Parse arguments and run main function
ROLE_FILE=""
parse_arguments "$@"
main "${ROLE_FILE}"
