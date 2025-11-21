#!/usr/bin/env bash
set -eEuo pipefail

# Configuration
readonly DEFINITION_TYPES=("size" "role" "vlan" "disk")
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly DEFINITIONS_DIR="$SCRIPT_DIR/definitions"
readonly SCHEMA_DIR="$SCRIPT_DIR/schemas"

# Logging functions
log() { printf "[%s] %s\n" "$1" "$2" >&2; }
log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }
fail() {
	log_error "$1"
	exit 1
}

# Check if yaml-validator-cli is available
check_validator() {
	if command -v yaml-validator-cli &> /dev/null; then
		return 0
	fi

	fail "yaml-validator-cli not found. Install with: cargo install yaml-validator-cli"
}

# Validate a single YAML file against schema
validate_file() {
	local file="$1"
	local schema="$2"
	local metadata_schema="$3"
	local schema_name="$4"

	local output exit_code
	output=$(yaml-validator-cli -s "$schema" "$metadata_schema" -u "$schema_name" "$file" 2>&1)
	exit_code=$?

	if [[ $exit_code -eq 0 ]]; then
		return 0
	else
		echo "$output"
		return 1
	fi
}

# Validate all definitions of a specific type
validate_type() {
	local type="$1"
	local definitions_dir="$DEFINITIONS_DIR/${type}s"
	local schema_file="$SCHEMA_DIR/${type}.schema.yml"
	local metadata_schema="$SCHEMA_DIR/metadata.schema.yml"
	local schema_name="${type}s_schema"

	# Check if directories and schema files exist
	[[ -d "$definitions_dir" ]] || {
		log_warning "No ${type}s directory: $definitions_dir"
		return 0
	}
	[[ -f "$schema_file" ]] || fail "Schema file not found: $schema_file"
	[[ -f "$metadata_schema" ]] || fail "Metadata schema not found: $metadata_schema"

	log_info "Validating ${type} definitions..."

	local files_found=0 files_valid=0 files_invalid=0
	local invalid_files=()

	# Process all YAML files in the definitions directory
	while IFS= read -r -d '' definition; do
		files_found=$((files_found + 1))
		local filename
		filename=$(basename "$definition" .yml)

		if validate_file "$definition" "$schema_file" "$metadata_schema" "$schema_name" > /dev/null 2>&1; then
			log_success "${type^} valid: $filename"
			files_valid=$((files_valid + 1))
		else
			log_error "${type^} invalid: $filename"
			invalid_files+=("$filename")
			files_invalid=$((files_invalid + 1))

			# Show validation errors for this file
			if ! validate_file "$definition" "$schema_file" "$metadata_schema" "$schema_name" 2> /dev/null; then
				validate_file "$definition" "$schema_file" "$metadata_schema" "$schema_name" 2>&1 \
					| sed 's/^/    /' >&2
			fi
		fi
	done < <(find "$definitions_dir" -name "*.yml" -type f -print0 2> /dev/null)

	# Summary
	if [[ $files_found -eq 0 ]]; then
		log_warning "No ${type} definitions found in: $definitions_dir"
		return 0
	fi

	log_info "${type^} summary: $files_valid valid, $files_invalid invalid (total: $files_found)"

	if [[ $files_invalid -gt 0 ]]; then
		log_error "Invalid ${type} files: ${invalid_files[*]}"
		return 1
	fi

	return 0
}

# Validate a specific type or all types
validate_definitions() {
	local target_type="${1:-}"

	# If specific type provided, validate only that type
	if [[ -n "$target_type" ]]; then
		if [[ " ${DEFINITION_TYPES[*]} " =~ " $target_type " ]]; then
			validate_type "$target_type"
		else
			fail "Invalid type: $target_type. Available types: ${DEFINITION_TYPES[*]}"
		fi
		return
	fi

	# Otherwise validate all types
	local start_time total_invalid=0
	start_time=$(date +%s)

	log_info "Starting validation for all definition types..."

	for type in "${DEFINITION_TYPES[@]}"; do
		if ! validate_type "$type"; then
			total_invalid=$((total_invalid + 1))
		fi
	done

	local duration
	duration=$(($(date +%s) - start_time))

	if [[ $total_invalid -gt 0 ]]; then
		fail "Validation completed with $total_invalid invalid types (${duration}s)"
	else
		log_success "All definitions validated successfully (${duration}s)"
	fi
}

# Show usage information
show_usage() {
	cat << EOF
Usage: $0 [TYPE]

Validate YAML definition files against their schemas using yaml-validator-cli.

Arguments:
  TYPE    Optional. Validate only files of specific type.
          Available types: ${DEFINITION_TYPES[*]}
          If not specified, validates all types.

Examples:
  $0           # Validate all definition types
  $0 role      # Validate only role definitions
  $0 size      # Validate only size definitions

Requirements:
  - yaml-validator-cli (install with: cargo install yaml-validator-cli)
EOF
}

# Main execution
main() {
	# Handle help flags
	case "${1:-}" in
		-h | --help | help)
			show_usage
			exit 0
			;;
	esac

	# Check prerequisites
	check_validator

	# Validate definitions
	validate_definitions "$@"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
