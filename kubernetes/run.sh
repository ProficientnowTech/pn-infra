#!/bin/bash
# Ansible Module Runner Script
# Configures deployed VMs and sets up Kubernetes cluster

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
ENVIRONMENT="${BOOTSTRAP_ENVIRONMENT:-development}"
PLAYBOOK="${1:-site.yml}"
INVENTORY_DIR="$BASE_DIR/nodes/inventory"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		site.yml | 01-system-config.yml | 02-kubernetes-deploy.yml | 03-argocd-bootstrap.yml)
			PLAYBOOK="playbooks/$1"
			shift
			;;
		--env | -e)
			ENVIRONMENT="$2"
			shift 2
			;;
		--inventory | -i)
			INVENTORY_DIR="$2"
			shift 2
			;;
		--check | -c)
			EXTRA_ARGS="--check"
			shift
			;;
		--help | -h)
			echo "Usage: $0 [PLAYBOOK] [--env ENVIRONMENT] [--inventory INVENTORY_DIR] [--check]"
			echo "Playbooks:"
			echo "  site.yml                    Run all playbooks (default)"
			echo "  01-system-config.yml        Phase 6: System configuration"
			echo "  02-kubernetes-deploy.yml    Phase 7: Kubernetes deployment"
			echo "  03-argocd-bootstrap.yml     Phase 8: ArgoCD setup"
			echo "Options:"
			echo "  --env, -e     Environment to use"
			echo "  --inventory   Inventory directory path"
			echo "  --check, -c   Run in check mode (dry run)"
			exit 0
			;;
		*)
			EXTRA_ARGS="${EXTRA_ARGS:-} $1"
			shift
			;;
	esac
done

echo "Ansible Module - Configuration Runner"
echo "Environment: $ENVIRONMENT"
echo "Playbook: $PLAYBOOK"
echo "Inventory: $INVENTORY_DIR"
echo "Extra args: ${EXTRA_ARGS:-none}"

# Validate inventory exists
HOSTS_FILE="$INVENTORY_DIR/hosts.yml"
if [[ ! -f "$HOSTS_FILE" ]]; then
	echo "Error: Ansible inventory not found: $HOSTS_FILE"
	echo "Run nodes module first to deploy VMs and generate inventory."
	exit 1
fi

# Validate generated group vars exist
GENERATED_VARS="$BASE_DIR/generated/ansible/group_vars"
if [[ ! -d "$GENERATED_VARS" ]]; then
	echo "Error: Generated Ansible variables not found: $GENERATED_VARS"
	echo "Run bootstrap module first to generate configuration."
	exit 1
fi

# Copy generated variables to ansible directory
echo "Copying generated variables..."
mkdir -p "$SCRIPT_DIR/group_vars"
cp -r "$GENERATED_VARS"/* "$SCRIPT_DIR/group_vars/"

# Validate required tools
echo "Validating required tools..."
for tool in ansible ansible-playbook; do
	if ! command -v "$tool" &> /dev/null; then
		echo "Error: $tool is not installed or not in PATH"
		exit 1
	fi
done

# Source environment variables
if [[ -f "$BASE_DIR/.env" ]]; then
	source "$BASE_DIR/.env"
fi

# Test connectivity before running playbooks
echo "Testing connectivity to all hosts..."
ansible all -i "$HOSTS_FILE" -m ping ${EXTRA_ARGS:-} || {
	echo "Warning: Some hosts are not reachable. Continuing anyway..."
}

# Validate playbook exists
PLAYBOOK_PATH="$SCRIPT_DIR/$PLAYBOOK"
if [[ ! -f "$PLAYBOOK_PATH" ]]; then
	echo "Error: Playbook not found: $PLAYBOOK_PATH"
	exit 1
fi

# Run ansible playbook
echo "Running Ansible playbook: $PLAYBOOK"
cd "$SCRIPT_DIR"

# Set up ansible configuration
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_STDOUT_CALLBACK=yaml
export ANSIBLE_INVENTORY="$HOSTS_FILE"

# Execute playbook with appropriate verbosity
case "$PLAYBOOK" in
	"site.yml")
		echo "Running complete infrastructure configuration..."
		ansible-playbook \
			-i "$HOSTS_FILE" \
			"$PLAYBOOK_PATH" \
			${EXTRA_ARGS:-} \
			-v
		;;
	"playbooks/01-system-config.yml")
		echo "Running Phase 6: System Configuration..."
		ansible-playbook \
			-i "$HOSTS_FILE" \
			"$PLAYBOOK_PATH" \
			${EXTRA_ARGS:-} \
			-v
		;;
	"playbooks/02-kubernetes-deploy.yml")
		echo "Running Phase 7: Kubernetes Deployment..."
		ansible-playbook \
			-i "$HOSTS_FILE" \
			"$PLAYBOOK_PATH" \
			${EXTRA_ARGS:-} \
			-v
		;;
	"playbooks/03-argocd-bootstrap.yml")
		echo "Running Phase 8: ArgoCD Bootstrap..."
		ansible-playbook \
			-i "$HOSTS_FILE" \
			"$PLAYBOOK_PATH" \
			${EXTRA_ARGS:-} \
			-v
		;;
	*)
		echo "Running custom playbook..."
		ansible-playbook \
			-i "$HOSTS_FILE" \
			"$PLAYBOOK_PATH" \
			${EXTRA_ARGS:-}
		;;
esac

# Check deployment status
echo "Checking deployment status..."

# Test Kubernetes cluster if it was deployed
if [[ "$PLAYBOOK" == "site.yml" ]] || [[ "$PLAYBOOK" == "playbooks/02-kubernetes-deploy.yml" ]]; then
	echo "Testing Kubernetes cluster..."

	# Find ansible controller from inventory
	ANS_CONTROLLER=$(yq e '.all.children.ans_controller_nodes.hosts | keys | .[0]' "$HOSTS_FILE" 2> /dev/null || echo "")

	if [[ -n "$ANS_CONTROLLER" ]]; then
		ANS_CONTROLLER_IP=$(yq e ".all.children.ans_controller_nodes.hosts.${ANS_CONTROLLER}.ansible_host" "$HOSTS_FILE")

		echo "Testing kubectl access on $ANS_CONTROLLER ($ANS_CONTROLLER_IP)..."
		ansible "$ANS_CONTROLLER" \
			-i "$HOSTS_FILE" \
			-m shell \
			-a "kubectl get nodes" || {
			echo "Warning: Kubernetes cluster may not be ready yet"
		}
	fi
fi

# Generate deployment report
echo "Generating deployment report..."
REPORT_FILE="deployment_report_${ENVIRONMENT}_$(date +%Y%m%d_%H%M%S).txt"

cat > "$REPORT_FILE" << EOF
# Ansible Deployment Report
Environment: $ENVIRONMENT
Playbook: $PLAYBOOK
Executed at: $(date -Iseconds)
Inventory: $HOSTS_FILE

## Host Summary
$(ansible all -i "$HOSTS_FILE" --list-hosts 2> /dev/null | grep -v "hosts (" || echo "Unable to list hosts")

## Connectivity Status
$(ansible all -i "$HOSTS_FILE" -m ping --one-line 2> /dev/null || echo "Unable to test connectivity")

## Additional Notes
- Bootstrap environment: $ENVIRONMENT
- Generated variables copied from: $GENERATED_VARS
- Playbook execution completed with exit code: $?
EOF

echo "Deployment report saved: $REPORT_FILE"
echo "Ansible module execution completed."
