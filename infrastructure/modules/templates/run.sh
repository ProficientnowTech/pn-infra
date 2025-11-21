#!/bin/bash
# Images Module Runner Script
# Builds role-specific images using Packer and uploads to MinIO

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
ENVIRONMENT="${BOOTSTRAP_ENVIRONMENT:-development}"
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
			echo "  apply     Apply changes and build images"
			echo "  destroy   Clean up images and resources"
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

echo "Images Module - Packer Build Runner"
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo "Module config: $MODULE_CONFIG"

# Validate module config exists
if [[ ! -f "$MODULE_CONFIG" ]]; then
	echo "Error: Module environment config not found: $MODULE_CONFIG"
	echo "Run bootstrap module first to generate configuration."
	exit 1
fi

# Generate terraform.tfvars from environment config
echo "Generating terraform.tfvars from environment config..."
cat > "${SCRIPT_DIR}/terraform.tfvars" << EOF
# Generated from images module environment config
# Environment: $ENVIRONMENT

# Global configuration
global_config = {
  environment     = "$(yq '.images.environment' "$MODULE_CONFIG" | tr -d '"')"
  resource_prefix = "$(yq '.images.environment' "$MODULE_CONFIG" | tr -d '"')-images"
  proxmox_config = {
    endpoint  = "$(yq '.images.proxmox.url' "$MODULE_CONFIG" | tr -d '"')"
    api_token = "$(yq '.images.proxmox.api_token' "$MODULE_CONFIG" | tr -d '"')"
    node_name = "$(yq '.images.proxmox.node' "$MODULE_CONFIG" | tr -d '"')"
    datastore = "$(yq '.images.proxmox.datastore' "$MODULE_CONFIG" | tr -d '"')"
  }
}

# MinIO configuration for image storage
minio_config = {
  endpoint   = "$(yq '.images.minio.endpoint' "$MODULE_CONFIG" | tr -d '"')"
  bucket     = "$(yq '.images.minio.bucket' "$MODULE_CONFIG" | tr -d '"')"
  access_key = "$(yq '.images.minio.access_key' "$MODULE_CONFIG" | tr -d '"')"
  secret_key = "$(yq '.images.minio.secret_key' "$MODULE_CONFIG" | tr -d '"')"
}

# Role configurations for image building
roles = {
$(yq '.images.roles | to_entries[] | "  " + .key + " = {" + "\n" + "    os = \"" + .value.os + "\"" + "\n" + "    vm_size = \"" + .value.vm_size + "\"" + "\n" + "  }"' "$MODULE_CONFIG" | tr -d '"')
}

# OS filter for building only needed images
os_filter = [
$(yq '.images.os_filter[]' "$MODULE_CONFIG" | tr -d '"' | sed 's/^/  "/;s/$/"/' | paste -sd,)
]

# Build configuration
build_config = {
  parallel_builds = $(yq '.images.build.parallel_builds' "$MODULE_CONFIG" | tr -d '"')
  optimization   = "$(yq '.images.build.optimization' "$MODULE_CONFIG" | tr -d '"')"
  workspace_path = "$(yq '.images.build.workspace_path' "$MODULE_CONFIG" | tr -d '"')"
}
EOF

TERRAFORM_VARS_FILE="${SCRIPT_DIR}/terraform.tfvars"

# Create workspace directories
mkdir -p "$SCRIPT_DIR"/{workspace/{builds,artifacts,logs},packer/{templates,scripts,variables}}

# Validate required tools
echo "Validating required tools..."
for tool in packer terraform yq; do
	if ! command -v "$tool" &> /dev/null; then
		echo "Error: $tool is not installed or not in PATH"
		exit 1
	fi
done

# Check Packer plugins
echo "Initializing Packer plugins..."
cd "$SCRIPT_DIR/packer"
packer init templates/ || {
	echo "Warning: Some Packer plugins may need manual installation"
}

# Generate Packer variable files for each role
generate_packer_vars() {
	local bootstrap_output_dir="../bootstrap/output"

	# Check if bootstrap has generated role configs
	if [[ ! -d "$bootstrap_output_dir" ]]; then
		echo "Error: Bootstrap output directory not found: $bootstrap_output_dir"
		echo "Run bootstrap module first to generate role configurations."
		exit 1
	fi

	# Create Packer variables for each role
	for role_config in "$bootstrap_output_dir"/*.yml; do
		if [[ -f "$role_config" ]]; then
			local role_name=$(basename "$role_config" .yml)
			echo "Generating Packer vars for role: $role_name"

			# Extract role-specific configuration
			local vm_id=$(yq ".role_configs.${role_name}.vm_id // 8000" "$MODULE_CONFIG")
			local vm_name="${ENVIRONMENT}-${role_name}-base"
			local vm_cores=$(yq ".role_configs.${role_name}.resources.cpu // 2" "$MODULE_CONFIG")
			local vm_memory=$(yq ".role_configs.${role_name}.resources.memory // 2048" "$MODULE_CONFIG")
			local os_type=$(yq ".role_configs.${role_name}.os // \"ubuntu-22.04\"" "$MODULE_CONFIG")

			# Create role-specific Packer variable file
			cat > "packer/variables/${role_name}.pkrvars.hcl" << EOF
# Packer variables for ${role_name} role
# Generated from environment config: $ENVIRONMENT

# Proxmox settings
proxmox_api_url          = "$(yq '.images.proxmox.url' "$MODULE_CONFIG" | tr -d '"')"
proxmox_api_token_id     = "$(yq '.images.proxmox.api_token' "$MODULE_CONFIG" | tr -d '"')"
proxmox_api_token_secret = "$(yq '.images.proxmox.api_secret' "$MODULE_CONFIG" | tr -d '"')"
proxmox_node             = "$(yq '.images.proxmox.node' "$MODULE_CONFIG" | tr -d '"')"
proxmox_storage_pool     = "$(yq '.images.proxmox.datastore' "$MODULE_CONFIG" | tr -d '"')"

# VM configuration
vm_id          = ${vm_id}
vm_name        = "${vm_name}"
vm_description = "Base ${os_type} image for ${role_name} role"
vm_cores       = ${vm_cores}
vm_memory      = ${vm_memory}

# OS-specific settings
iso_url        = "$(yq '.images.iso_configs.'${os_type}'.url' "$MODULE_CONFIG" | tr -d '"')"
iso_checksum   = "$(yq '.images.iso_configs.'${os_type}'.checksum' "$MODULE_CONFIG" | tr -d '"')"
iso_storage_pool = "$(yq '.images.proxmox.iso_storage' "$MODULE_CONFIG" | tr -d '"')"
EOF
		fi
	done
}

# Build images for each role using Packer
build_role_images() {
	local bootstrap_output_dir="../bootstrap/output"

	echo "Building role-specific images..."

	for role_config in "$bootstrap_output_dir"/*.yml; do
		if [[ -f "$role_config" ]]; then
			local role_name=$(basename "$role_config" .yml)
			local os_type=$(yq ".role_configs.${role_name}.os // \"ubuntu-22.04\"" "$MODULE_CONFIG")
			local packer_template="packer/templates/${os_type}.pkr.hcl"
			local packer_vars="packer/variables/${role_name}.pkrvars.hcl"

			echo "Building image for role: $role_name (OS: $os_type)"

			if [[ ! -f "$packer_template" ]]; then
				echo "Warning: Packer template not found: $packer_template, skipping"
				continue
			fi

			# Copy role-specific bootstrap scripts to Packer scripts directory
			if [[ -f "$bootstrap_output_dir/${role_name}-scripts.tar.gz" ]]; then
				echo "Extracting bootstrap scripts for $role_name..."
				mkdir -p "packer/scripts/roles/${role_name}"
				tar -xzf "$bootstrap_output_dir/${role_name}-scripts.tar.gz" -C "packer/scripts/roles/${role_name}"
			fi

			# Build the image
			cd packer
			packer build \
				-var-file="variables/common.pkrvars.hcl" \
				-var-file="$packer_vars" \
				-var "role_name=${role_name}" \
				-var "bootstrap_scripts_path=scripts/roles/${role_name}" \
				"$packer_template"
			cd ..

			echo "✅ Image built successfully for role: $role_name"
		fi
	done

	echo "All role images built successfully"
}

# Note: Proxmox and MinIO credentials are now configured in the environment config file

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
		echo "Planning image builds..."
		terraform plan -var-file="$TERRAFORM_VARS_FILE"
		;;

	apply)
		echo "Planning image builds..."
		terraform plan -var-file="$TERRAFORM_VARS_FILE"

		if [[ "$DRY_RUN" == "true" ]]; then
			echo "Dry run mode - stopping after plan"
			exit 0
		fi

		echo "Building images with Packer..."

		# Generate Packer variable files from environment config
		echo "Generating Packer variable files..."
		generate_packer_vars

		# Build images for each role
		build_role_images

		# Apply terraform to register images
		terraform apply -var-file="$TERRAFORM_VARS_FILE" -auto-approve

		# Generate image registry for nodes module
		echo "Generating image registry..."
		terraform output -json > workspace/artifacts/image_registry.json

		# Update nodes module environment config with image registry
		echo "Updating nodes module config with image registry..."
		NODES_CONFIG="$BASE_DIR/nodes/environments/${ENVIRONMENT}.config.yml"
		if [[ -f "$NODES_CONFIG" ]]; then
			# Create backup
			cp "$NODES_CONFIG" "${NODES_CONFIG}.backup"

			# Add image registry to nodes config
			yq eval '.nodes.image_registry = load("workspace/artifacts/image_registry.json")' -i "$NODES_CONFIG"
			echo "✅ Updated nodes config with image registry"
		else
			echo "⚠️ Nodes config not found: $NODES_CONFIG"
		fi

		echo "Images build completed successfully!"
		echo "Image registry saved to: workspace/artifacts/image_registry.json"
		echo "Nodes module config updated with image registry"
		;;

	destroy)
		echo "Planning image resource destruction..."
		terraform plan -destroy -var-file="$TERRAFORM_VARS_FILE"

		if [[ "$DRY_RUN" == "true" ]]; then
			echo "Dry run mode - stopping after destroy plan"
			exit 0
		fi

		echo "Cleaning up image resources..."
		terraform destroy -var-file="$TERRAFORM_VARS_FILE" -auto-approve

		# Clean up workspace (optional - keep logs for debugging)
		read -p "Clean up workspace? (y/N): " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			rm -rf workspace/{builds,artifacts}/*
			echo "Workspace cleaned up."
		fi
		;;

	*)
		echo "Error: Unknown action $ACTION"
		exit 1
		;;
esac

echo "Images module execution completed."
