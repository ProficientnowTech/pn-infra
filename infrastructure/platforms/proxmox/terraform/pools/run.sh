#!/bin/bash
# Pools Module Runner Script
# Creates Proxmox resource pools for organizing VMs

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
ENVIRONMENT="${ENVIRONMENT:-development}"
MODULE_CONFIG="${SCRIPT_DIR}/environments/${ENVIRONMENT}.config.yml"
ACTION="${1:-plan}"
DRY_RUN="${DRY_RUN:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		plan | apply | destroy)
			ACTION="$1"
			shift
			;;
		--env | -e)
			ENVIRONMENT="$2"
			MODULE_CONFIG="${SCRIPT_DIR}/environments/${ENVIRONMENT}.config.yml"
			shift 2
			;;
		--vars | -v)
			TERRAFORM_VARS_FILE="$2"
			shift 2
			;;
		--dry-run)
			DRY_RUN="true"
			shift
			;;
		--help | -h)
			echo "Usage: $0 [plan|apply|destroy] [--env ENVIRONMENT] [--vars VARS_FILE] [--dry-run]"
			echo "  plan      Show planned changes (default)"
			echo "  apply     Apply changes and create pools"
			echo "  destroy   Remove pool resources"
			echo "  --env     Environment to use"
			echo "  --vars    Path to terraform.tfvars file"
			echo "  --dry-run Run in dry-run mode (plan only)"
			exit 0
			;;
		*)
			echo "Unknown option $1"
			exit 1
			;;
	esac
done

echo "Pools Module - Proxmox Resource Pool Management"
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo "Module config: $MODULE_CONFIG"

# Validate module config exists
if [[ ! -f "$MODULE_CONFIG" ]]; then
	echo "Error: Module environment config not found: $MODULE_CONFIG"
	echo "Please create the config file with your Proxmox credentials and pool settings."
	exit 1
fi

# Generate terraform.tfvars from environment config
echo "Generating terraform.tfvars from environment config..."
cat > "${SCRIPT_DIR}/terraform.tfvars" << EOF
# Generated from pools module environment config
# Environment: $ENVIRONMENT

pools = [
$(yq '.pools.pool_names[]' "$MODULE_CONFIG" | tr -d '"' | sed 's/^/  "/;s/$/"/' | paste -sd,)
]

global_config = {
  environment     = "$(yq '.pools.environment' "$MODULE_CONFIG" | tr -d '"')"
  resource_prefix = "$(yq '.pools.resource_prefix' "$MODULE_CONFIG" | tr -d '"')"
  proxmox_config = {
    endpoint  = "$(yq '.pools.proxmox.url' "$MODULE_CONFIG" | tr -d '"')"
    api_token = "$(yq '.pools.proxmox.api_token' "$MODULE_CONFIG" | tr -d '"')"
    node_name = "$(yq '.pools.proxmox.node' "$MODULE_CONFIG" | tr -d '"')"
    datastore = "$(yq '.pools.proxmox.datastore' "$MODULE_CONFIG" | tr -d '"')"
  }
}
EOF

TERRAFORM_VARS_FILE="${SCRIPT_DIR}/terraform.tfvars"

# Validate required tools
echo "Validating required tools..."
for tool in terraform yq; do
	if ! command -v "$tool" &> /dev/null; then
		echo "Error: $tool is not installed or not in PATH"
		exit 1
	fi
done

cd "$SCRIPT_DIR"

# Initialize Terraform if needed
if [[ ! -d ".terraform" ]]; then
	echo "Initializing Terraform..."
	terraform init
else
	echo "Terraform already initialized"
fi

# Validate Terraform configuration
echo "Validating Terraform configuration..."
terraform validate
if [[ $? -ne 0 ]]; then
	echo "❌ Terraform validation failed"
	exit 1
fi
echo "✅ Terraform configuration is valid"

case "$ACTION" in
	plan)
		echo "Planning pool changes..."
		terraform plan -var-file="$TERRAFORM_VARS_FILE"
		;;

	apply)
		echo "Planning pool changes..."
		terraform plan -var-file="$TERRAFORM_VARS_FILE"

		if [[ "$DRY_RUN" == "true" ]]; then
			echo "Dry run mode - stopping after plan"
			exit 0
		fi

		echo "Creating resource pools..."
		terraform apply -var-file="$TERRAFORM_VARS_FILE" -auto-approve

		echo "Pools module completed successfully!"
		;;

	destroy)
		echo "Planning pool resource destruction..."
		terraform plan -destroy -var-file="$TERRAFORM_VARS_FILE"

		if [[ "$DRY_RUN" == "true" ]]; then
			echo "Dry run mode - stopping after destroy plan"
			exit 0
		fi

		echo "Removing pool resources..."
		terraform destroy -var-file="$TERRAFORM_VARS_FILE" -auto-approve
		;;

	*)
		echo "Error: Unknown action $ACTION"
		exit 1
		;;
esac

echo "Pools module execution completed."
