#!/usr/bin/env bash
#

set -Eeuo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# Global log file variable
LOG_FILE=""

# Initialize logging to file
init_logging() {
	local log_dir="$1"

	# Create log directory if it doesn't exist
	if [[ ! -d "$log_dir" ]]; then
		mkdir -p "$log_dir" || fail "Failed to create log directory: $log_dir"
		echo "Created log directory: $log_dir"
	fi

	# Set log file path with timestamp
	LOG_FILE="${log_dir}/$(get_utctime).log"

	# Initialize log file with header
	{
		echo "=== Deployment Script Log Started ==="
		echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
		echo "Script: $0"
		echo "Arguments: $*"
		echo "========================================="
		echo ""
	} > "$LOG_FILE"

	echo "Logging initialized to: $LOG_FILE"
}

# Unified logging function with file output
log() {
	local level="$1"
	local message="$2"
	local file_output="[$(get_timestamp)] [${level^^}]: $message"

	case $level in
		success | SUCCESS)
			printf "${CYAN}[$(get_timestamp)] ${GREEN}[SUCCESS]: ${NC}%s\n" "$message"
			;;
		error | ERROR)
			printf "${CYAN}[$(get_timestamp)] ${RED}[ERROR]: ${NC}%s\n" "$message" >&2
			;;
		warning | WARNING | warn | WARN)
			printf "${CYAN}[$(get_timestamp)] ${YELLOW}[WARNING]: ${NC}%s\n" "$message"
			;;
		info | INFO)
			printf "${CYAN}[$(get_timestamp)] ${BLUE}[INFO]: ${NC}%s\n" "$message"
			;;
		debug | DEBUG)
			if [[ "${DEBUG:-}" == "1" ]]; then
				printf "${CYAN}[$(get_timestamp)] ${DIM}[DEBUG]: ${NC}%s\n" "$message"
			fi
			;;
		*)
			printf "${CYAN}[$(get_timestamp)] ${NC}[UNKNOWN]: %s\n" "$message"
			;;
	esac

	# Write clean output to log file if LOG_FILE is set
	if [[ -n "$LOG_FILE" ]]; then
		case $level in
			debug | DEBUG)
				if [[ "${DEBUG:-}" == "1" ]]; then
					echo "$file_output" >> "$LOG_FILE"
				fi
				;;
			error | ERROR)
				echo "$file_output" >> "$LOG_FILE"
				;;
			*)
				echo "$file_output" >> "$LOG_FILE"
				;;
		esac
	fi
}

separator() {
	printf "${MAGENTA}==================================================${NC}\n"
	# Also log separator to file (without colors)
	if [[ -n "$LOG_FILE" ]]; then
		echo "==================================================" >> "$LOG_FILE"
	fi
}

# Simple error trap
fail() {
	log error "$1"
	exit "${2:-1}"
}
trap 'log error "Script failed on line $LINENO"' ERR

get_timestamp() {
	date '+%Y-%m-%d %H:%M:%S'
}

get_utctime() {
	date '+%Y%m%d-%H%M%S'
}

check_tool() {
	local tool=$1
	local command=$2

	log info "Checking ${tool}..."
	if ! version=$(${command} 2> /dev/null); then
		fail "Prerequisite check failed: ${tool} not found or not executable"
	fi
	log success "${tool} found with version: ${version}"
}

check_variable() {
	local variable=$1
	local expected_value=$2
	local error_msg="${3:-}"

	log info "Checking variable ${variable}..."

	# Check if variable is set
	if [ -z "${!variable:-}" ]; then
		# If error message provided, it's a required variable
		if [[ -n "$error_msg" ]]; then
			fail "Variable '${variable}' is blank or not set. ${error_msg}"
		else
			log warning "Variable '${variable}' is not set"
			return 1
		fi
	# Check if variable equals expected value (if expected_value is provided)
	elif [[ -n "$expected_value" && "${!variable}" != "$expected_value" ]]; then
		if [[ -n "$error_msg" ]]; then
			fail "${error_msg}"
		else
			fail "Variable '${variable}' has unexpected value. Expected: '${expected_value}', Got: '${!variable}'"
		fi
	else
		log success "Variable '${variable}' is set to: ${!variable}"
	fi
}

check_prerequisites() {
	log info "Checking Prerequisites..."
	log debug "arch: ${ARCH}"
	log debug "os: ${OS}"

	separator
	log info "Checking OS and ARCH"

	check_variable "OS" "Linux" "Unsupported operating system: $OS"
	check_variable "ARCH" "x86_64" "Unsupported architecture: $ARCH"

	log success "Operating System and Architecture are supported"
	separator
	log info "Validating script parameters"

	# Validate ENVIRONMENT variable
	if [[ ! "$ENVIRONMENT" =~ ^(development|production)$ ]]; then
		fail "ENVIRONMENT variable is invalid or not set. Must be 'development' or 'production' got: $ENVIRONMENT"
	fi

	# Validate environment config exists
	if [[ ! -f "$CONFIG_FILE" ]]; then
		fail "Bootstrap environment config not found: $CONFIG_FILE"
	fi

	log success "Parameters are valid"

	separator
	log info "Checking required tools"

	# Check required tools
	check_tool "yq" "yq --version" || fail "yq is required for YAML processing. Please install yq."
	check_tool "yaml-validator-cli" "yaml-validator-cli --version" || fail "yaml-validator-cli is required for YAML schema validation. Please install yaml-validator-cli."
	check_tool "python3" "python3 --version" || fail "python3 is required for Jinja2 template processing. Please install python3."
	check_tool "jinja2" "jinja2 --version" || fail "jinja2-cli is required for template processing. Please install with: pip3 install jinja2-cli[yaml]"

	log success "All required tools are installed"
	log success "All prerequisites verified"
}

generate_packer_templates() {
	local images_packer_dir="$BASE_DIR"/images/packer

	for role_file in "$SCRIPT_DIR"/definitions/*.yml; do
		if [[ -f "$role_file" ]]; then
			local role_name=$(basename "$role_file" .yml)

			local enabled=$(yq eval ".bootstrap.roles[\"$role_name\"].enabled // false" "$CONFIG_FILE")
			if [[ "$enabled" != true ]]; then
				log info "Skipping disabled role: $role_name"
				continue
			fi
			log info "Generating Packer templates for role: $role_name"
			# create packer directories in the images module
			mkdir -p "$images_packer_dir"/workspace/"$role_name"/{templates,variables,http}

			# Create role context for Jinja2 templates
			local role_context_file="/tmp/${role_name}-context.yml"
			local os_type=$(yq eval ".operating_system.name" "$role_file")
			local packages_yaml=$(yq e ".software.base_packages[].name" "$role_file")

			# Clean up temporary file
			rm -f "$role_context_file"
			echo "Generated Packer files for $role_name"
		fi
	done

	echo "Generating role configs for dependent modules..."
}

# Initialize script variables
ARCH=$(uname -m)
OS=$(uname -s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

ENVIRONMENT="${ENVIRONMENT:-development}"
CONFIG_FILE="${SCRIPT_DIR}/environments/${ENVIRONMENT}.config.yml"

DEBUG="${DEBUG:-0}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--env | -e)
			ENVIRONMENT="$2"
			CONFIG_FILE="${SCRIPT_DIR}/environments/${ENVIRONMENT}.config.yml"
			shift 2
			;;
		--debug | -d)
			DEBUG=1
			shift 1
			;;
		--help | -h)
			echo "Usage: $0 [--env ENVIRONMENT] [--debug] [--log-dir LOG_DIRECTORY]"
			echo "  --env, -e       Environment to use (development|production)"
			echo "  --debug, -d     Enable debug output"
			echo "  --log-dir, -l   Directory to save log files"
			echo ""
			echo "This script generates role configs for dependent modules:"
			echo "  - images/environments/{env}.config.yml"
			echo "  - templates/environments/{env}.config.yml"
			echo "  - nodes/environments/{env}.config.yml"
			echo "  - ansible/environments/{env}.config.yml"
			exit 0
			;;
		--log-dir | -l)
			init_logging "$2"
			shift 2
			;;
		*)
			echo "Unknown option $1"
			exit 1
			;;
	esac
done

# Initialize default logging if not set via command line
if [[ -z "$LOG_FILE" ]]; then
	init_logging "./logs"
fi

check_prerequisites
