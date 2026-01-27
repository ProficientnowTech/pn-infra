#!/usr/bin/env bash

# Enhanced Kubespray Docker Management Script
# Supports deploy, reset, upgrade, scale and other Kubespray operations
# Uses official Kubespray Docker image without polluting your repository

set -e

# Configuration
KUBESPRAY_VERSION="v2.28.1"
# Default to our published Kubespray image (latest); allow override via IMAGE_NAME env
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/proficientnowtech/kubespray-pncp:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_PATH="${SCRIPT_DIR}/inventory/pn-production"
HOSTS_FILE="${INVENTORY_PATH}/hosts.yml"
SSH_KEY_PATH="${SSH_KEY_PATH:-/home/mohammmed-faizan/.ssh-manager/keys/pn-infra-prod/id_ed25519_pn-infra-prod-ansible_20260123-162958}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
OPERATION=""
VERBOSE=""
DRY_RUN=""
FORCE_PULL=""
EXTRA_ARGS=""
LIMIT_HOSTS=""
AUTO_YES=""
CEPH_FORCE_CLEANUP=""
CEPH_FORCE_CLEANUP_DRY_RUN=""
CEPH_FORCE_CLEANUP_MODE="full"
CEPH_FORCE_CLEANUP_CONFIRMED=""
CEPH_FORCE_CLEANUP_PARALLEL=""
CEPH_FORCE_CLEANUP_TIMEOUT=""

# Usage function
usage() {
	cat <<EOF
Usage: $0 [OPERATION] [OPTIONS]

OPERATIONS:
    deploy          Deploy a new Kubernetes cluster (default)
    reset           Reset/destroy the cluster
    upgrade         Upgrade cluster to newer Kubernetes version
    scale           Add/remove nodes to/from cluster
    recover         Recover control plane
    shell           Open interactive shell in container
    validate        Validate configuration (dry-run)
    facts           Gather cluster facts

OPTIONS:
    -v, --verbose       Enable verbose output
    -n, --dry-run      Perform a dry run (check mode)
    -f, --force-pull   Force pull Docker image even if present
    -l, --limit HOSTS  Limit execution to specific hosts (comma-separated)
    -e, --extra ARGS   Pass additional arguments to ansible-playbook
    -y, --yes          Non-interactive (assume yes)
    --ceph-force-cleanup           Irreversibly wipe non-OS disks (FULL wipe, DESTRUCTIVE)
    --ceph-force-cleanup-overwrite Irreversibly overwrite every byte on non-OS disks (SLOW, DESTRUCTIVE)
    --ceph-force-cleanup-fast      Irreversibly wipe non-OS disks (FAST metadata wipe, DESTRUCTIVE)
    --ceph-force-cleanup-dry-run   Show what would be wiped (no changes)
    --ceph-force-cleanup-parallel N  Parallel SSH workers for cleanup tooling (default varies by mode)
    --ceph-force-cleanup-timeout S   SSH timeout per host in seconds (0 disables; default varies by mode)
    -h, --help         Show this help message

EXAMPLES:
    $0 deploy                           # Deploy cluster
    $0 reset                           # Reset cluster
    $0 reset --ceph-force-cleanup       # Reset + wipe Ceph disks (non-OS disks only)
    $0 reset --ceph-force-cleanup-overwrite  # Reset + overwrite every byte (can take a very long time)
    $0 reset --ceph-force-cleanup-fast  # Reset + fast wipe (signatures/partition tables)
    $0 reset --ceph-force-cleanup-dry-run  # Preview wipe targets
    $0 upgrade -v                      # Upgrade with verbose output
    $0 scale -l k8s-worker-07          # Add new worker node
    $0 deploy -n                       # Dry run deployment
    $0 shell                          # Interactive container shell
    $0 validate                       # Validate configuration

CONFIGURATION:
    Kubespray Version: ${KUBESPRAY_VERSION}
    Inventory Path: ${HOSTS_FILE}
    SSH Key: ${SSH_KEY_PATH}
EOF
}

# Logging functions
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

# Validation functions
validate_prerequisites() {
	log_info "Validating prerequisites..."

	# Check Docker
	if ! command -v docker &>/dev/null; then
		log_error "Docker is not installed or not in PATH"
		exit 1
	fi

	if ! docker info >/dev/null 2>&1; then
		log_error "Docker is not running"
		exit 1
	fi

	# Check SSH key
	if [[ ! -f "${SSH_KEY_PATH}" ]]; then
		log_error "SSH private key not found at ${SSH_KEY_PATH}"
		exit 1
	fi

	# Check inventory
	if [[ ! -f "${HOSTS_FILE}" ]]; then
		log_error "Inventory file not found at ${HOSTS_FILE}"
		exit 1
	fi

	# Check inventory structure
	if [[ ! -d "${INVENTORY_PATH}/group_vars" ]]; then
		log_error "group_vars directory not found in inventory"
		exit 1
	fi

	log_success "Prerequisites validation passed"
}

validate_ssh_connectivity() {
	log_info "Validating SSH connectivity..."

	# Extract all hosts from inventory (fail fast if any are unreachable).
	local hosts
	hosts="$(python3 - <<PY
import yaml, pathlib
inv = pathlib.Path("${HOSTS_FILE}")
data = yaml.safe_load(inv.read_text())
hosts = data.get("all", {}).get("hosts", {}) if isinstance(data, dict) else {}
for _, meta in hosts.items():
    ip = meta.get("ansible_host")
    if ip:
        print(ip)
PY
)"

	local max_parallel=20
	local failed_hosts
	failed_hosts="$(
		printf '%s\n' ${hosts} | xargs -P "${max_parallel}" -I{} bash -c \
			'timeout 8 ssh -i "'"${SSH_KEY_PATH}"'" -o IdentitiesOnly=yes -o IdentityAgent=none -o PreferredAuthentications=publickey -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@"{}" "echo ok" >/dev/null 2>&1 || echo "{}"'
	)"

	if [[ -n "$failed_hosts" ]]; then
		log_warning "SSH connectivity failed for hosts: ${failed_hosts//$'\n'/ }"
		log_warning "Deployment may fail. Check SSH keys and network connectivity."
		read -p "Continue anyway? (y/N): " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			exit 1
		fi
	else
		log_success "SSH connectivity validation passed"
	fi
}

check_docker_image() {
	log_info "Checking Docker image availability..."

	if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
		log_success "Docker image ${IMAGE_NAME} found locally"
		if [[ "$FORCE_PULL" == "true" ]]; then
			log_info "Force pull requested, updating image..."
			if ! docker pull "${IMAGE_NAME}"; then
				log_error "Failed to pull Docker image ${IMAGE_NAME}"
				exit 1
			fi
		fi
	else
		log_info "Docker image not found locally, pulling..."
		if ! docker pull "${IMAGE_NAME}"; then
			log_error "Failed to pull Docker image ${IMAGE_NAME}"
			exit 1
		fi
	fi
}

# Main execution function
run_kubespray() {
	local playbook="$1"
	local operation_name="$2"

	log_info "Starting Kubespray ${operation_name}..."

	# Build command arguments
	local cmd="cd /kubespray && chmod 600 /root/.ssh/id_rsa"
	local ansible_cfg_host="${SCRIPT_DIR}/ansible.cfg"

	# Add verbose flag
	local ansible_args="-i inventory/pn-production/hosts.yml"
	[[ "$VERBOSE" == "true" ]] && ansible_args="$ansible_args -v"
	[[ "$DRY_RUN" == "true" ]] && ansible_args="$ansible_args --check"
	[[ -n "$LIMIT_HOSTS" ]] && ansible_args="$ansible_args --limit $LIMIT_HOSTS"
	[[ -n "$EXTRA_ARGS" ]] && ansible_args="$ansible_args $EXTRA_ARGS"

	cmd="$cmd && export ANSIBLE_HOST_KEY_CHECKING=False"
	cmd="$cmd && ansible-playbook $ansible_args $playbook -b"

	# Run the container
	docker run --rm -it \
		-e ANSIBLE_CONFIG=/kubespray/ansible.cfg \
		--mount type=bind,source="${INVENTORY_PATH}",dst="/kubespray/inventory/pn-production/" \
		--mount type=bind,source="${SSH_KEY_PATH}",dst="/root/.ssh/id_rsa" \
		--mount type=bind,source="${ansible_cfg_host}",dst="/kubespray/ansible.cfg,readonly" \
		"${IMAGE_NAME}" \
		bash -c "$cmd"

	if [[ $? -eq 0 ]]; then
		log_success "Kubespray ${operation_name} completed successfully!"
	else
		log_error "Kubespray ${operation_name} failed!"
		exit 1
	fi
}

# Operation-specific functions
deploy_cluster() {
	log_info "Deploying Kubernetes cluster..."
	validate_ssh_connectivity
	run_kubespray "cluster.yml" "deployment"
}

reset_cluster() {
	log_warning "This will completely destroy the Kubernetes cluster!"
	log_warning "All data, pods, and configurations will be lost!"

	if [[ "$AUTO_YES" != "true" ]]; then
		read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
		if [[ "$REPLY" != "yes" ]]; then
			log_info "Reset operation cancelled"
			exit 0
		fi
	fi

	# Optional Ceph forced disk cleanup (non-OS disks only) prior to reset.
	if [[ "$CEPH_FORCE_CLEANUP" == "true" || "$CEPH_FORCE_CLEANUP_DRY_RUN" == "true" ]]; then
		log_warning "Ceph forced disk cleanup enabled."
		log_warning "THIS ACTION IS DESTRUCTIVE, IRREVERSIBLE, AND CANNOT BE UNDONE."
		log_warning "This will wipe ALL non-OS disks on the selected hosts."
		case "$CEPH_FORCE_CLEANUP_MODE" in
		overwrite)
			log_warning "Wipe mode: OVERWRITE (writes zeros over every byte; may take hours/days on large HDDs)."
			;;
		full)
			log_warning "Wipe mode: FULL (wipes entire disks; may use device discard when available, otherwise full overwrite; may take a long time)."
			;;
		*)
			log_warning "Wipe mode: FAST (wipes signatures/partition tables; quick but not a full byte-for-byte overwrite)."
			;;
		esac
		if [[ "$DRY_RUN" == "true" ]]; then
			log_warning "Dry-run mode enabled: Ceph cleanup will run in dry-run (no wiping)."
		elif [[ "$CEPH_FORCE_CLEANUP_DRY_RUN" != "true" && "$AUTO_YES" != "true" ]]; then
			read -p "Type 'WIPE-CEPH' to confirm disk wiping: " -r
			if [[ "$REPLY" != "WIPE-CEPH" ]]; then
				log_info "Ceph disk cleanup cancelled"
				exit 0
			fi
			CEPH_FORCE_CLEANUP_CONFIRMED="true"
		fi

		validate_ssh_connectivity

		log_info "Collecting non-OS disk inventory (for review) ..."
		local inventory_args=(
			"${SCRIPT_DIR}/tools/collect_non_os_disks.py"
			"--hosts-file" "${HOSTS_FILE}"
			"--ssh-key" "${SSH_KEY_PATH}"
		)
		[[ -n "$LIMIT_HOSTS" ]] && inventory_args+=("--limit" "$LIMIT_HOSTS")
		python3 "${inventory_args[@]}"
		log_success "Non-OS disk inventory written under ${SCRIPT_DIR}/.artifacts/"

		local cleanup_args=(
			"${SCRIPT_DIR}/tools/ceph_force_disk_cleanup.py"
			"--hosts-file" "${HOSTS_FILE}"
			"--ssh-key" "${SSH_KEY_PATH}"
			"--mode" "${CEPH_FORCE_CLEANUP_MODE}"
		)
		[[ -n "$LIMIT_HOSTS" ]] && cleanup_args+=("--limit" "$LIMIT_HOSTS")
		[[ "$DRY_RUN" == "true" || "$CEPH_FORCE_CLEANUP_DRY_RUN" == "true" ]] && cleanup_args+=("--dry-run")
		[[ "$AUTO_YES" == "true" || "$CEPH_FORCE_CLEANUP_CONFIRMED" == "true" ]] && cleanup_args+=("--yes")
		# Defaults: FULL/OVERWRITE wipes can take a long time; avoid SSH timeouts and avoid wiping many nodes at once.
		if [[ -n "$CEPH_FORCE_CLEANUP_TIMEOUT" ]]; then
			cleanup_args+=("--timeout" "$CEPH_FORCE_CLEANUP_TIMEOUT")
		elif [[ "$CEPH_FORCE_CLEANUP_MODE" == "full" || "$CEPH_FORCE_CLEANUP_MODE" == "overwrite" ]]; then
			cleanup_args+=("--timeout" "0")
		fi
		if [[ -n "$CEPH_FORCE_CLEANUP_PARALLEL" ]]; then
			cleanup_args+=("--parallel" "$CEPH_FORCE_CLEANUP_PARALLEL")
		elif [[ "$CEPH_FORCE_CLEANUP_MODE" == "full" || "$CEPH_FORCE_CLEANUP_MODE" == "overwrite" ]]; then
			cleanup_args+=("--parallel" "1")
		fi

		log_info "Running Ceph forced disk cleanup..."
		python3 "${cleanup_args[@]}"
		log_success "Ceph forced disk cleanup completed"
	fi

	run_kubespray "reset.yml" "reset"
}

upgrade_cluster() {
	log_info "Upgrading Kubernetes cluster..."
	log_warning "Cluster upgrade is a complex operation. Ensure you have backups!"
	read -p "Continue with upgrade? (y/N): " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 0
	fi
	run_kubespray "upgrade-cluster.yml" "upgrade"
}

scale_cluster() {
	if [[ -z "$LIMIT_HOSTS" ]]; then
		log_error "Scale operation requires --limit flag to specify hosts"
		log_info "Example: $0 scale --limit k8s-worker-07"
		exit 1
	fi
	log_info "Scaling cluster with hosts: $LIMIT_HOSTS"
	run_kubespray "scale.yml" "scaling"
}

recover_cluster() {
	log_info "Recovering control plane..."
	log_warning "This should only be used when control plane nodes are down"
	read -p "Continue with recovery? (y/N): " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 0
	fi
	run_kubespray "recover-control-plane.yml" "recovery"
}

validate_config() {
	log_info "Validating Kubespray configuration..."
	DRY_RUN="true"
	VERBOSE="true"
	run_kubespray "cluster.yml" "validation"
}

gather_facts() {
	log_info "Gathering cluster facts..."
	run_kubespray "playbooks/facts.yml" "fact gathering"
}

open_shell() {
	log_info "Opening interactive Kubespray container shell..."
	log_info "Inventory mounted at: /kubespray/inventory/pn-production/"
	log_info "SSH Key mounted at: /root/.ssh/id_rsa"
	log_info "Run 'ansible-playbook -i inventory/pn-production/hosts.yml cluster.yml -b' to deploy"

	docker run --rm -it \
		--mount type=bind,source="${INVENTORY_PATH}",dst="/kubespray/inventory/pn-production/" \
		--mount type=bind,source="${SSH_KEY_PATH}",dst="/root/.ssh/id_rsa" \
		"${IMAGE_NAME}" \
		bash -c "cd /kubespray && chmod 600 /root/.ssh/id_rsa && bash"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	deploy | reset | upgrade | scale | recover | shell | validate | facts)
		OPERATION="$1"
		shift
		;;
	-v | --verbose)
		VERBOSE="true"
		shift
		;;
	-n | --dry-run)
		DRY_RUN="true"
		shift
		;;
	-f | --force-pull)
		FORCE_PULL="true"
		shift
		;;
	-l | --limit)
		LIMIT_HOSTS="$2"
		shift 2
		;;
	-e | --extra)
		EXTRA_ARGS="$2"
		shift 2
		;;
	-y | --yes)
		AUTO_YES="true"
		shift
		;;
	--ceph-force-cleanup)
		CEPH_FORCE_CLEANUP="true"
		CEPH_FORCE_CLEANUP_MODE="full"
		shift
		;;
	--ceph-force-cleanup-overwrite)
		CEPH_FORCE_CLEANUP="true"
		CEPH_FORCE_CLEANUP_MODE="overwrite"
		shift
		;;
	--ceph-force-cleanup-fast)
		CEPH_FORCE_CLEANUP="true"
		CEPH_FORCE_CLEANUP_MODE="fast"
		shift
		;;
	--ceph-force-cleanup-dry-run)
		CEPH_FORCE_CLEANUP_DRY_RUN="true"
		shift
		;;
	--ceph-force-cleanup-parallel)
		CEPH_FORCE_CLEANUP_PARALLEL="$2"
		shift 2
		;;
	--ceph-force-cleanup-timeout)
		CEPH_FORCE_CLEANUP_TIMEOUT="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		log_error "Unknown option: $1"
		usage
		exit 1
		;;
	esac
done

# Default operation
[[ -z "$OPERATION" ]] && OPERATION="deploy"

# Print header
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Enhanced Kubespray Manager              ║${NC}"
echo -e "${CYAN}║            Docker-based Deployment               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo
log_info "Operation: ${OPERATION}"
log_info "Kubespray Version: ${KUBESPRAY_VERSION}"
[[ "$VERBOSE" == "true" ]] && log_info "Verbose mode enabled"
[[ "$DRY_RUN" == "true" ]] && log_info "Dry run mode enabled"
[[ -n "$LIMIT_HOSTS" ]] && log_info "Limited to hosts: ${LIMIT_HOSTS}"

# Validate prerequisites
validate_prerequisites

# Check and pull Docker image
check_docker_image

# Execute operation
case $OPERATION in
deploy)
	deploy_cluster
	;;
reset)
	reset_cluster
	;;
upgrade)
	upgrade_cluster
	;;
scale)
	scale_cluster
	;;
recover)
	recover_cluster
	;;
validate)
	validate_config
	;;
facts)
	gather_facts
	;;
shell)
	open_shell
	;;
*)
	log_error "Unknown operation: $OPERATION"
	usage
	exit 1
	;;
esac
