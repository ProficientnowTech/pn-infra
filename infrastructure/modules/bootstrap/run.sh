#!/usr/bin/env bash
# Bootstrap Module Runner Script
# Generates role configurations for dependent modules only

set -Eeuo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
ENVIRONMENT="${ENVIRONMENT:-development}"
CONFIG_FILE="${SCRIPT_DIR}/environments/${ENVIRONMENT}.config.yml"

ARCH=$(uname -m)
OS=$(uname -s)
# Color definitions for better error messaging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Simple error trap with colored output
fail() {
	printf "${RED}${BOLD}[ERROR]${NC} %s\n" "$1" >&2
	exit "${2:-1}"
}
trap 'fail "❌ Script failed on line $LINENO"' ERR

check_tool() {
	tool=$1
	command=$2
	version_output="${3:-}"

	echo -n "🔍 Checking ${tool}... "
	version=$(${command}) || fail "Prerequisite check failed: ${tool} not found or not executable"
	printf "${GREEN}✅ ${tool}${NC} found with version: ${BOLD}${version}${NC}\n"
}

check_variable() {
	variable=$1
	expected_value=$2
	error_msg="${3:-}"

	echo -n "🔍 Checking variable ${variable}... "

	# Check if variable is set
	if [ -z "${!variable:-}" ]; then
		# If error message provided, it's a required variable
		if [[ -n "$error_msg" ]]; then
			fail "Variable '${variable}' is blank or not set. ${error_msg}"
		else
			printf "${YELLOW}⚠️  Variable '${variable}' is not set${NC}\n"
			return 1
		fi
	# Check if variable equals expected value (if expected_value is provided)
	elif [[ -n "$expected_value" && "${!variable}" != "$expected_value" ]]; then
		if [[ -n "$error_msg" ]]; then
			fail "Variable '${variable}' is not set to expected value '${expected_value}'. Current value: '${!variable}'. ${error_msg}"
		else
			fail "Variable '${variable}' has unexpected value. Expected: '${expected_value}', Got: '${!variable}'"
		fi
	else
		printf "${GREEN}✅ ${variable}${NC} is set to: ${BOLD}${!variable}${NC}\n"
	fi
}

check_prerequisites() {
	printf "\n${BOLD}🚀 Checking Prerequisites...${NC}\n"
	echo "arch: ${ARCH}"
	echo "os: ${OS}"

	check_variable "OS" "Linux" "Unsupported operating system: $OS"
	check_variable "ARCH" "x86_64" "Unsupported architecture: $ARCH"

	# Validate environment config exists
	if [[ ! -f "$ENVIRONMENT" ]]; then
		fail "variable env is required: $ENVIRONMENT"
	fi

	# Check required tools
	check_tool "yq" "yq --version" || fail "yq is required for YAML processing. Please install yq."
	check_tool "python3" "python3 --version" || fail "python3 is required for Jinja2 template processing. Please install python3."
	check_tool "jinja2" "jinja2 --version" || fail "jinja2-cli is required for template processing. Please install with: pip3 install jinja2-cli[yaml]"

	printf "${GREEN}✅ All prerequisites verified${NC}\n"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--env | -e)
			ENVIRONMENT="$2"
			CONFIG_FILE="${SCRIPT_DIR}/environments/${ENVIRONMENT}.config.yml"
			shift 2
			;;
		--help | -h)
			echo "Usage: $0 [--env ENVIRONMENT]"
			echo "  --env, -e     Environment to use (development|production)"
			echo ""
			echo "This script generates role configs for dependent modules:"
			echo "  - images/environments/{env}.config.yml"
			echo "  - templates/environments/{env}.config.yml"
			echo "  - nodes/environments/{env}.config.yml"
			echo "  - ansible/environments/{env}.config.yml"
			exit 0
			;;
		*)
			echo "Unknown option $1"
			exit 1
			;;
	esac
done

echo "Bootstrap Module - Role Config Generation for Dependent Modules"
echo "Environment: $ENVIRONMENT"
echo "Bootstrap config: $CONFIG_FILE"

# Function to generate Packer templates and scripts for each role
generate_packer_templates() {
	local images_packer_dir="$BASE_DIR/images/packer"

	# Create packer directories in images module
	mkdir -p "$images_packer_dir"/{templates,variables,workspace/http}

	# Process each enabled role
	for role_file in "$SCRIPT_DIR/definitions"/*.yml; do
		if [[ -f "$role_file" ]]; then
			local role_name=$(basename "$role_file" .yml)

			# Check if role is enabled
			local enabled=$(yq ".bootstrap.roles[\"$role_name\"].enabled // false" "$CONFIG_FILE")
			if [[ "$enabled" != "true" ]]; then
				echo "  Skipping disabled role: $role_name"
				continue
			fi

			echo "  Generating Packer templates for role: $role_name"

			# Create role context for Jinja2 templates
			local role_context_file="/tmp/${role_name}-context.yml"

			# Extract role data from definition and environment config
			#      cat >"$role_context_file" <<EOF
			# role_name: $(yq '.role.name' "$role_file" | tr -d '"')
			# role_id: $(yq '.role.role_id' "$role_file")
			# environment: $ENVIRONMENT
			# os: $(yq '.operating_system.preferred' "$role_file" | tr -d '"')
			# vm_id: $((8000 + $(yq '.role.role_id' "$role_file")))

			#          resources:
			#              cpu: $(yq '.hardware.min_cpu' "$role_file")
			#              memory: $(($(yq '.hardware.min_memory_gb' "$role_file") * 1024))
			#              disk: $(yq '.hardware.min_disk_gb' "$role_file")

			#          packages:
			#              $(yq '.software.packages[]' "$role_file" | sed 's/^/  - /')

			#          scripts:
			#              - name: base-setup
			#                content: |
			#              $(cat "$SCRIPT_DIR/scripts/common/ubuntu-base-setup.sh" | sed 's/^/      /')

			#          proxmox:
			#              url: $(yq '.bootstrap.proxmox.url' "$CONFIG_FILE" | tr -d '"')
			#              api_token: $(yq '.bootstrap.proxmox.api_token' "$CONFIG_FILE" | tr -d '"')
			#              api_secret: $(yq '.bootstrap.proxmox.api_secret' "$CONFIG_FILE" | tr -d '"')
			#              node: $(yq '.bootstrap.proxmox.node' "$CONFIG_FILE" | tr -d '"')
			#              datastore: $(yq '.bootstrap.proxmox.datastore' "$CONFIG_FILE" | tr -d '"')
			#              iso_storage: $(yq '.bootstrap.proxmox.iso_storage' "$CONFIG_FILE" | tr -d '"')

			#          iso_url: $(yq '.bootstrap.iso_configs[.operating_system.preferred].url' "$role_file $CONFIG_FILE" | tr -d '"' | head -1)
			#          iso_checksum: $(yq '.bootstrap.iso_configs[.operating_system.preferred].checksum' "$role_file $CONFIG_FILE" | tr -d '"' | head -1)
			#      EOF

			# Generate Packer template
			local os_type=$(yq '.operating_system.preferred' "$role_file" | tr -d '"')
			jinja2 "$SCRIPT_DIR/templates/packer/${os_type}.pkr.hcl.j2" "$role_context_file" > "$images_packer_dir/templates/${role_name}.pkr.hcl"

			# Generate Packer variables
			jinja2 "$SCRIPT_DIR/templates/packer/variables.pkrvars.hcl.j2" "$role_context_file" > "$images_packer_dir/variables/${role_name}.pkrvars.hcl"

			# Create role-specific autoinstall config
			cat > "$images_packer_dir/workspace/http/user-data-${role_name}" << EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US
  keyboard:
    layout: us
  ssh:
    install-server: true
    allow-pw: true
    authorized-keys: []
  packages:
$(yq '.software.packages[]' "$role_file" | sed 's/^/    - /')
  storage:
    layout:
      name: direct
    swap:
      size: 0
  user-data:
    disable_root: false
    users:
      - name: ubuntu
        passwd: "\$6\$rounds=4096\$aQ7U9y8O2C0\$6P0.EzJgSZ1qaOUOmYg.DL8VJ5Jq8rZwOzJXfJG8lKzGhCj0YjFvT7NlBp.AyPvO6L6BcAkj9BoYjvHSKdMVg1"
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: [adm, sudo]
        lock_passwd: false
  late-commands:
    - echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu
    - chmod 440 /target/etc/sudoers.d/ubuntu
    - systemctl enable ssh
    - systemctl enable qemu-guest-agent
    - echo "$(yq '.role.role_id' "$role_file")" > /target/etc/infrastructure-role-id
    - echo "$role_name" > /target/etc/infrastructure-role-name
EOF

			# Clean up temporary file
			rm -f "$role_context_file"

			echo "✅ Generated Packer files for $role_name"
		fi
	done

	echo "📦 Packer templates generated in: $images_packer_dir"
}

echo "Generating role configs for dependent modules..."

# Generate Images module environment config (roles only)
echo "Generating images/environments/${ENVIRONMENT}.config.yml..."
cat > "$BASE_DIR/images/environments/${ENVIRONMENT}.config.yml" << EOF
# Generated by bootstrap module for images module
# Environment: $ENVIRONMENT

images:
  environment: "$(yq '.bootstrap.environment' "$CONFIG_FILE" | tr -d '"')"
  domain: "$(yq '.bootstrap.domain' "$CONFIG_FILE" | tr -d '"')"

  # Proxmox configuration
  proxmox:
    url: "$(yq '.bootstrap.proxmox.url' "$CONFIG_FILE" | tr -d '"')"
    api_token: "$(yq '.bootstrap.proxmox.api_token' "$CONFIG_FILE" | tr -d '"')"
    api_secret: "$(yq '.bootstrap.proxmox.api_secret' "$CONFIG_FILE" | tr -d '"')"
    node: "$(yq '.bootstrap.proxmox.node' "$CONFIG_FILE" | tr -d '"')"
    datastore: "$(yq '.bootstrap.proxmox.datastore' "$CONFIG_FILE" | tr -d '"')"
    iso_storage: "$(yq '.bootstrap.proxmox.iso_storage' "$CONFIG_FILE" | tr -d '"')"

  # MinIO configuration
  minio:
    endpoint: "$(yq '.bootstrap.minio.endpoint' "$CONFIG_FILE" | tr -d '"')"
    bucket: "$(yq '.bootstrap.minio.bucket' "$CONFIG_FILE" | tr -d '"')"
    access_key: "$(yq '.bootstrap.minio.access_key' "$CONFIG_FILE" | tr -d '"')"
    secret_key: "$(yq '.bootstrap.minio.secret_key' "$CONFIG_FILE" | tr -d '"')"

  # Enabled roles for image building
  roles:
$(yq '.bootstrap.roles | to_entries[] | select(.value.enabled == true) | "    " + .key + ":" + " {os: " + .value.preferred_os + ", vm_size: " + .value.vm_size + "}"' "$CONFIG_FILE" | tr -d '"')

  # OS configurations
  iso_configs:
$(yq '.bootstrap.iso_configs | to_entries[] | "    " + .key + ":" + "\n" + "      url: " + .value.url + "\n" + "      checksum: " + .value.checksum' "$CONFIG_FILE" | tr -d '"')
EOF

# Generate Templates module environment config (roles only)
echo "Generating templates/environments/${ENVIRONMENT}.config.yml..."
cat > "$BASE_DIR/templates/environments/${ENVIRONMENT}.config.yml" << EOF
# Generated by bootstrap module for templates module
# Environment: $ENVIRONMENT

templates:
  environment: "$(yq '.bootstrap.environment' "$CONFIG_FILE" | tr -d '"')"

  # Role VM sizes from bootstrap definitions
  role_vm_sizes:
$(yq '.bootstrap.roles | to_entries[] | select(.value.enabled == true) | "    " + .key + ": " + .value.vm_size' "$CONFIG_FILE" | tr -d '"')
EOF

# Generate Nodes module environment config (roles only)
echo "Generating nodes/environments/${ENVIRONMENT}.config.yml..."
cat > "$BASE_DIR/nodes/environments/${ENVIRONMENT}.config.yml" << EOF
# Generated by bootstrap module for nodes module
# Environment: $ENVIRONMENT
# NOTE: This config will be updated by images and templates modules

nodes:
  environment: "$(yq '.bootstrap.environment' "$CONFIG_FILE" | tr -d '"')"
  domain: "$(yq '.bootstrap.domain' "$CONFIG_FILE" | tr -d '"')"

  # Role configurations from bootstrap
  roles:
    k8s-master:
      instances: $(yq '.bootstrap.roles["k8s-master"].instances' "$CONFIG_FILE" | tr -d '"')
      preferred_os: "$(yq '.bootstrap.roles["k8s-master"].preferred_os' "$CONFIG_FILE" | tr -d '"')"
      vm_size: "$(yq '.bootstrap.roles["k8s-master"].vm_size' "$CONFIG_FILE" | tr -d '"')"
    k8s-worker:
      instances: $(yq '.bootstrap.roles["k8s-worker"].instances' "$CONFIG_FILE" | tr -d '"')
      preferred_os: "$(yq '.bootstrap.roles["k8s-worker"].preferred_os' "$CONFIG_FILE" | tr -d '"')"
      vm_size: "$(yq '.bootstrap.roles["k8s-worker"].vm_size' "$CONFIG_FILE" | tr -d '"')"
    ans-controller:
      instances: $(yq '.bootstrap.roles["ans-controller"].instances' "$CONFIG_FILE" | tr -d '"')
      preferred_os: "$(yq '.bootstrap.roles["ans-controller"].preferred_os' "$CONFIG_FILE" | tr -d '"')"
      vm_size: "$(yq '.bootstrap.roles["ans-controller"].vm_size' "$CONFIG_FILE" | tr -d '"')"
    k8s-storage:
      instances: $(yq '.bootstrap.roles["k8s-storage"].instances' "$CONFIG_FILE" | tr -d '"')
      preferred_os: "$(yq '.bootstrap.roles["k8s-storage"].preferred_os' "$CONFIG_FILE" | tr -d '"')"
      vm_size: "$(yq '.bootstrap.roles["k8s-storage"].vm_size' "$CONFIG_FILE" | tr -d '"')"

  # These will be populated by dependent modules:
  # image_registry: {} # Populated by images module
  # template_registry: {} # Populated by templates module
EOF

# Generate Ansible module environment config (roles only)
echo "Generating ansible/environments/${ENVIRONMENT}.config.yml..."
cat > "$BASE_DIR/ansible/environments/${ENVIRONMENT}.config.yml" << EOF
# Generated by bootstrap module for ansible module
# Environment: $ENVIRONMENT
# NOTE: This config will be updated by nodes module with inventory details

ansible:
  environment: "$(yq '.bootstrap.environment' "$CONFIG_FILE" | tr -d '"')"
  domain: "$(yq '.bootstrap.domain' "$CONFIG_FILE" | tr -d '"')"

  # Role configurations from bootstrap
  roles:
    k8s-master:
      instances: $(yq '.bootstrap.roles["k8s-master"].instances' "$CONFIG_FILE" | tr -d '"')
      enabled: $(yq '.bootstrap.roles["k8s-master"].enabled' "$CONFIG_FILE" | tr -d '"')
    k8s-worker:
      instances: $(yq '.bootstrap.roles["k8s-worker"].instances' "$CONFIG_FILE" | tr -d '"')
      enabled: $(yq '.bootstrap.roles["k8s-worker"].enabled' "$CONFIG_FILE" | tr -d '"')
    ans-controller:
      instances: $(yq '.bootstrap.roles["ans-controller"].instances' "$CONFIG_FILE" | tr -d '"')
      enabled: $(yq '.bootstrap.roles["ans-controller"].enabled' "$CONFIG_FILE" | tr -d '"')
    k8s-storage:
      instances: $(yq '.bootstrap.roles["k8s-storage"].instances' "$CONFIG_FILE" | tr -d '"')
      enabled: $(yq '.bootstrap.roles["k8s-storage"].enabled' "$CONFIG_FILE" | tr -d '"')

  # This will be populated by nodes module:
  # inventory_path: "" # Set by nodes module after VM deployment
EOF

# Generate Packer templates for images module
echo "Generating Packer templates for enabled roles..."
generate_packer_templates

echo ""
echo "✅ Role config generation completed successfully!"
echo ""
echo "Generated role configs and Packer templates for dependent modules:"
echo "  📁 images/environments/${ENVIRONMENT}.config.yml"
echo "  📁 templates/environments/${ENVIRONMENT}.config.yml"
echo "  📁 nodes/environments/${ENVIRONMENT}.config.yml"
echo "  📁 ansible/environments/${ENVIRONMENT}.config.yml"
echo "  📦 images/packer/templates/*.pkr.hcl (role-specific Packer templates)"
echo "  📦 images/packer/variables/*.pkrvars.hcl (role-specific variables)"
echo "  📦 images/packer/workspace/http/user-data-* (autoinstall configs)"
echo ""
echo "Next steps:"
echo "  1. Run images module: cd ../images && ./run.sh apply --env ${ENVIRONMENT}"
echo "  2. Run templates module: cd ../templates && ./run.sh apply --env ${ENVIRONMENT}"
echo "  3. Run nodes module: cd ../nodes && ./run.sh apply --env ${ENVIRONMENT}"
echo "  4. Run ansible module: cd ../ansible && ./run.sh site.yml --env ${ENVIRONMENT}"
echo ""
echo "Or use the parent orchestrator:"
echo "  ./deploy.sh --env ${ENVIRONMENT}"
