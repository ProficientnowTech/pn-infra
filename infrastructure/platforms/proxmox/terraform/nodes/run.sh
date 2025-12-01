#!/bin/bash
# Nodes Module Runner Script
# Deploys VMs using images and templates

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
ENVIRONMENT="${BOOTSTRAP_ENVIRONMENT:-development}"
TERRAFORM_VARS_FILE="${SCRIPT_DIR}/terraform.tfvars"
ACTION="${1:-plan}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		plan | apply | destroy)
			ACTION="$1"
			shift
			;;
		--env | -e)
			ENVIRONMENT="$2"
			shift 2
			;;
		--vars | -v)
			TERRAFORM_VARS_FILE="$2"
			shift 2
			;;
		--help | -h)
			echo "Usage: $0 [plan|apply|destroy] [--env ENVIRONMENT] [--vars VARS_FILE]"
			echo "  plan      Show planned changes (default)"
			echo "  apply     Apply changes and deploy nodes"
			echo "  destroy   Clean up nodes and resources"
			echo "  --env     Environment to use"
			echo "  --vars    Path to terraform.tfvars file"
			exit 0
			;;
		*)
			echo "Unknown option $1"
			exit 1
			;;
	esac
done

echo "Nodes Module - VM Deployment Runner"
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo "Terraform vars: $TERRAFORM_VARS_FILE"

# Validate terraform vars file exists
if [[ ! -f "$TERRAFORM_VARS_FILE" ]]; then
	echo "Error: Terraform vars file not found: $TERRAFORM_VARS_FILE"
	echo "Run bootstrap module first to generate configuration."
	exit 1
fi

# Validate required tools
echo "Validating required tools..."
for tool in terraform yq jq; do
	if ! command -v "$tool" &> /dev/null; then
		echo "Error: $tool is not installed or not in PATH"
		exit 1
	fi
done

# Source environment variables
if [[ -f "$BASE_DIR/.env" ]]; then
	source "$BASE_DIR/.env"
fi

# Validate dependencies - check if images and templates are ready
echo "Validating dependencies..."

# Check images registry
IMAGES_REGISTRY="$BASE_DIR/images/workspace/artifacts/image_registry.json"
if [[ ! -f "$IMAGES_REGISTRY" ]]; then
	echo "Error: Images registry not found: $IMAGES_REGISTRY"
	echo "Run images module first to build required images."
	exit 1
fi

# Check templates registry
TEMPLATES_REGISTRY="$BASE_DIR/templates/template_registry.json"
if [[ ! -f "$TEMPLATES_REGISTRY" ]]; then
	echo "Error: Templates registry not found: $TEMPLATES_REGISTRY"
	echo "Run templates module first to create resource templates."
	exit 1
fi

# Generate additional variables from registries
ADDITIONAL_VARS_FILE="/tmp/nodes_additional_${ENVIRONMENT}.tfvars"
echo "# Additional variables from images and templates registries" > "$ADDITIONAL_VARS_FILE"

# Add image registry data
echo "Extracting image registry data..."
echo "image_registry = $(cat "$IMAGES_REGISTRY")" >> "$ADDITIONAL_VARS_FILE"

# Add template registry data
echo "Extracting template registry data..."
echo "template_registry = $(cat "$TEMPLATES_REGISTRY")" >> "$ADDITIONAL_VARS_FILE"

# Generate inventory file for ansible
echo "Generating Ansible inventory..."
mkdir -p "$SCRIPT_DIR/inventory"

# Create dynamic inventory based on planned deployments
generate_inventory() {
	local action=$1

	if [[ "$action" == "plan" ]]; then
		echo "inventory_preview:"
		echo "  # Inventory will be generated after 'terraform apply'"
		return
	fi

	# Generate actual inventory from Terraform state
	cd "$SCRIPT_DIR"

	if [[ -f "terraform.tfstate" ]]; then
		echo "Generating inventory from Terraform state..."

		# Create hosts.yml for ansible
		cat > inventory/hosts.yml << 'EOF'
---
# Generated Ansible inventory from Terraform state
# DO NOT EDIT MANUALLY - This file is auto-generated

all:
  children:
EOF

		# Extract VM information from terraform state and generate inventory
		terraform show -json | jq -r '
        .values.root_module.resources[] |
        select(.type == "proxmox_vm_qemu") |
        {
            name: .values.name,
            ip: .values.default_ipv4_address,
            role: .values.tags.role,
            vmid: .values.vmid
        }' | jq -s 'group_by(.role)' | jq -r '
        .[] as $group |
        "    \($group[0].role)_nodes:",
        "      hosts:",
        ($group[] | "        \(.name):",
        "          ansible_host: \(.ip)",
        "          vm_id: \(.vmid)",
        "          role: \(.role)")
        ' >> inventory/hosts.yml

		echo "Inventory generated: $SCRIPT_DIR/inventory/hosts.yml"
	fi
}

case "$ACTION" in
	plan)
		echo "Planning node deployment..."
		cd "$SCRIPT_DIR"
		terraform init
		terraform plan \
			-var-file="$TERRAFORM_VARS_FILE" \
			-var-file="$ADDITIONAL_VARS_FILE"

		generate_inventory "plan"
		;;

	apply)
		echo "Deploying nodes..."
		cd "$SCRIPT_DIR"

		# Initialize Terraform
		terraform init

		# Apply Terraform configuration
		terraform apply \
			-var-file="$TERRAFORM_VARS_FILE" \
			-var-file="$ADDITIONAL_VARS_FILE" \
			-auto-approve

		# Generate inventory for Ansible
		generate_inventory "apply"

		# Wait for VMs to be ready
		echo "Waiting for VMs to be ready..."
		sleep 30

		# Test connectivity
		echo "Testing VM connectivity..."
		if [[ -f "inventory/hosts.yml" ]]; then
			ansible all -i inventory/hosts.yml -m ping || {
				echo "Warning: Some VMs may not be ready yet. Check manually."
			}
		fi

		echo "Nodes deployment completed successfully!"
		echo "Ansible inventory: $SCRIPT_DIR/inventory/hosts.yml"
		;;

	destroy)
		echo "Destroying nodes..."
		cd "$SCRIPT_DIR"

		terraform destroy \
			-var-file="$TERRAFORM_VARS_FILE" \
			-var-file="$ADDITIONAL_VARS_FILE" \
			-auto-approve

		# Clean up generated files
		rm -f "$ADDITIONAL_VARS_FILE" inventory/hosts.yml
		;;

	*)
		echo "Error: Unknown action $ACTION"
		exit 1
		;;
esac

# Clean up temporary files
rm -f "$ADDITIONAL_VARS_FILE"

echo "Nodes module execution completed."
