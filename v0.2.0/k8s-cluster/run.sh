#!/usr/bin/env bash

# Master Deployment Controller
# Entry point for all deployment and validation operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SCRIPT="${SCRIPT_DIR}/validate.sh"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy.sh"
CNI_IMAGE="${CNI_IMAGE:-ghcr.io/proficientnowtech/kubespray-pncp:latest}"
KUBECONFIG_LOCAL="${SCRIPT_DIR}/.kube/config"
KUBECONFIG_HOME="${HOME}/.kube/config"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh-manager/keys/pn-production-k8s/id_ed25519_pn-production-ansible-role_20250505-163646}"
DOCKER_BIN="docker"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
OPERATION=""
SKIP_VALIDATION=""
FORCE_VALIDATION=""
FORCE_PULL=""

ensure_inventory() {
	local inventory_file="${SCRIPT_DIR}/inventory/pn-production/hosts.yml"
	if [[ ! -f "$inventory_file" ]]; then
		log_error "Inventory not found: ${inventory_file}"
		exit 1
	fi
	python3 - "$inventory_file" <<'PY'
import sys, yaml, pathlib
inv_path = pathlib.Path(sys.argv[1])
data = yaml.safe_load(inv_path.read_text())
hosts = data.get("all", {}).get("hosts", {}) if isinstance(data, dict) else {}
if not hosts:
    sys.stderr.write(f"[ERROR] No hosts defined in {inv_path}\n")
    sys.exit(1)
PY
	if [[ $? -ne 0 ]]; then
		log_error "Inventory validation failed: see errors above"
		exit 1
	fi
}

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

usage() {
	cat <<EOF
Usage: $0 [OPERATION] [OPTIONS]

OPERATIONS:
    validate        Run validation only
    deploy          Deploy cluster (includes validation)
    reset           Reset cluster (includes validation)
    upgrade         Upgrade cluster (includes validation)
    scale           Scale cluster (includes validation)
    recover         Recover control plane (includes validation)
    facts           Gather cluster facts
    status          Check deployment status
    shell           Open interactive shell
    kubeconfig      Copy kubeconfig from first master (only)
    cni             Run post-deploy CNI playbook (requires kubeconfig)
    cni-reset       Run CNI reset playbook (requires kubeconfig)
    
OPTIONS:
    --skip-validation       Skip validation (EMERGENCY USE ONLY)
    --force-validation      Force fresh validation
    -v, --verbose          Enable verbose output
    -n, --dry-run          Perform a dry run
    -f, --force-pull       Force pull Docker image
    -l, --limit HOSTS      Limit execution to specific hosts
    -e, --extra ARGS       Pass additional arguments
    -h, --help             Show this help

EXAMPLES:
    $0 validate                    # Run validation only
    $0 deploy                      # Validate then deploy
    $0 deploy -v                   # Verbose deployment
    $0 scale -l k8s-worker-07      # Scale with specific host
    $0 deploy --skip-validation    # Emergency deploy without validation
EOF
}

run_validation() {
	if [[ ! -x "$VALIDATE_SCRIPT" ]]; then
		log_error "Validation script not found: $VALIDATE_SCRIPT"
		return 1
	fi

	log_info "Running validation..."
	"$VALIDATE_SCRIPT"
}

run_deployment() {
	local operation="$1"
	shift

	if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
		log_error "Deployment script not found: $DEPLOY_SCRIPT"
		return 1
	fi

	log_info "Starting deployment: $operation"
	"$DEPLOY_SCRIPT" "$operation" "$@"
}

copy_kubeconfig() {
	log_info "Copying kubeconfig from master node..."

	mkdir -p "$(dirname "$KUBECONFIG_LOCAL")"
	mkdir -p "$(dirname "$KUBECONFIG_HOME")"

	# If kubeconfig already exists and works, skip copy
	if [[ -f "$KUBECONFIG_LOCAL" ]]; then
		if KUBECONFIG="$KUBECONFIG_LOCAL" kubectl cluster-info &>/dev/null; then
			log_success "Kubeconfig already present and working at $KUBECONFIG_LOCAL"
			cp "$KUBECONFIG_LOCAL" "$KUBECONFIG_HOME"
			return 0
		fi
	fi

	local master_ip=""
	local master_hostname=""

	read -r master_hostname master_ip <<<"$(python3 - "$SCRIPT_DIR" <<'PY'
import sys, yaml, pathlib
inv = pathlib.Path(sys.argv[1]) / "inventory/pn-production/hosts.yml"
data = yaml.safe_load(inv.read_text())
hosts = data.get("all", {}).get("hosts", {}) if isinstance(data, dict) else {}
first = next(iter(hosts.items()))
print(f"{first[0]} {first[1].get('ansible_host','')}")
PY
)"

	if [[ -z "$master_ip" || -z "$master_hostname" ]]; then
		log_warning "Could not find master IP or hostname in inventory"
		exit 1
	fi

	local ansible_user
	ansible_user=$(grep "ansible_user:" "$SCRIPT_DIR/inventory/pn-production/host_vars/${master_hostname}.yml" 2>/dev/null | awk '{print $2}' || echo "root")

	# Copy kubeconfig directly via sudo cat over SSH
	local SSH_OPTS=(-i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
	if ssh "${SSH_OPTS[@]}" "$ansible_user@$master_ip" "sudo cat /etc/kubernetes/admin.conf" >"$KUBECONFIG_LOCAL"; then
		# Also copy to user default location for convenience
		cp "$KUBECONFIG_LOCAL" "$KUBECONFIG_HOME"
		log_success "Kubeconfig copied to $KUBECONFIG_LOCAL and $KUBECONFIG_HOME"

		# Verify kubeconfig works
		if KUBECONFIG="$KUBECONFIG_LOCAL" kubectl cluster-info &>/dev/null; then
			local node_count
			node_count=$(KUBECONFIG="$KUBECONFIG_LOCAL" kubectl get nodes --no-headers 2>/dev/null | wc -l)
			log_success "Cluster accessible with $node_count nodes"
		else
			log_warning "Kubeconfig copied but cluster not accessible"
		fi
	else
		log_warning "Failed to copy kubeconfig via ssh. Check SSH key path: $SSH_KEY_PATH"
	fi
}

enforce_validation() {
	local operation="$1"

	if [[ "$SKIP_VALIDATION" == "true" ]]; then
		log_warning "⚠️  VALIDATION SKIPPED - Emergency mode"
		return 0
	fi

	log_info "Validation required before $operation"
	if run_validation; then
		log_success "Validation passed - proceeding with $operation"
	else
		log_error "Validation failed - $operation aborted"
		exit 1
	fi
}

# Parse arguments - separate validation flags from deploy script args
DEPLOY_ARGS=()
while [[ $# -gt 0 ]]; do
	case $1 in
validate | deploy | reset | upgrade | scale | recover | facts | status | shell)
        OPERATION="$1"
        shift
        ;;
kubeconfig | cni | cni-reset)
        OPERATION="$1"
        shift
        ;;
	--skip-validation)
		SKIP_VALIDATION="true"
		shift
		;;
	--force-validation)
		FORCE_VALIDATION="true"
		shift
		;;
	-f | --force-pull)
		FORCE_PULL="true"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		# All other arguments go to deploy script
		DEPLOY_ARGS+=("$1")
		shift
		;;
	esac
done

# Default operation
[[ -z "$OPERATION" ]] && OPERATION="deploy"

log_info "Operation: $OPERATION"
ensure_inventory

select_docker() {
	if $DOCKER_BIN info >/dev/null 2>&1; then
		return 0
	fi
	if sudo -n docker info >/dev/null 2>&1; then
		DOCKER_BIN="sudo docker"
		return 0
	fi
	log_error "Docker daemon not accessible (need access to /var/run/docker.sock or sudo rights)"
	return 1
}

ensure_cni_image() {
	select_docker || return 1
	if [[ "$FORCE_PULL" == "true" ]] || ! $DOCKER_BIN image inspect "${CNI_IMAGE}" >/dev/null 2>&1; then
		log_info "Pulling CNI image ${CNI_IMAGE}..."
		$DOCKER_BIN pull "${CNI_IMAGE}"
	fi
}

run_cni_playbook() {
	local playbook="$1"
	local playbook_path="${SCRIPT_DIR}/playbooks/${playbook}"
	local roles_path="${SCRIPT_DIR}/roles"
	local kubeconfig_path="${KUBECONFIG_LOCAL}"

	if [[ ! -f "$playbook_path" ]]; then
		log_warning "CNI playbook not found: $playbook_path (skipping)"
		return 0
	fi

	if [[ ! -d "$roles_path" ]]; then
		log_error "CNI roles directory missing: $roles_path"
		return 1
	fi

	if [[ ! -f "$kubeconfig_path" ]]; then
		log_warning "Kubeconfig not found at $kubeconfig_path; attempting to copy from master..."
		copy_kubeconfig
		if [[ ! -f "$kubeconfig_path" ]]; then
			log_error "Kubeconfig still missing after copy attempt; aborting CNI playbook ${playbook}"
			return 1
		fi
	fi

	ensure_cni_image || return 1

	log_info "Running CNI playbook ${playbook} via ${CNI_IMAGE}"
	$DOCKER_BIN run --rm \
		-e KUBECONFIG=/root/.kube/config \
		-e ANSIBLE_ROLES_PATH=/workspace/roles \
		-e ANSIBLE_STDOUT_CALLBACK=default \
		-e ANSIBLE_CALLBACKS_ENABLED=profile_tasks,timer \
		-e ANSIBLE_DISPLAY_SKIPPED_HOSTS=False \
		-e ANSIBLE_FORCE_COLOR=True \
		-e ANSIBLE_CONFIG=/workspace/playbooks/ansible.cfg \
		-v "${kubeconfig_path}":/root/.kube/config:ro \
		-v "${SCRIPT_DIR}":/workspace \
		"${CNI_IMAGE}" \
		ansible-playbook -i localhost, -c local "/workspace/playbooks/${playbook}"
}

run_cni_playbooks() {
	local kubeconfig_path="${KUBECONFIG_LOCAL}"
	local roles_path="${SCRIPT_DIR}/roles"
	if [[ ! -d "$roles_path" ]]; then
		log_error "CNI roles directory missing: $roles_path"
		return 1
	fi
	if [[ ! -f "$kubeconfig_path" ]]; then
		log_warning "Kubeconfig not found at $kubeconfig_path; attempting to copy from master..."
		copy_kubeconfig
		if [[ ! -f "$kubeconfig_path" ]]; then
			log_error "Kubeconfig still missing after copy attempt; aborting CNI playbooks"
			return 1
		fi
	fi
	ensure_cni_image

	local cmds=()
	for pb in "$@"; do
		if [[ ! -f "${SCRIPT_DIR}/playbooks/${pb}" ]]; then
			log_error "CNI playbook not found: ${SCRIPT_DIR}/playbooks/${pb}"
			return 1
		fi
		cmds+=("ansible-playbook -i localhost, -c local /workspace/playbooks/${pb}")
		cmds+=("&&")
	done
	cmds=("${cmds[@]:0:${#cmds[@]}-1}") # drop trailing &&
	log_info "Running CNI playbooks (${*}) via ${CNI_IMAGE}"
	$DOCKER_BIN run --rm \
		-e KUBECONFIG=/root/.kube/config \
		-e ANSIBLE_ROLES_PATH=/workspace/roles \
		-e ANSIBLE_STDOUT_CALLBACK=default \
		-e ANSIBLE_CALLBACKS_ENABLED=profile_tasks,timer \
		-e ANSIBLE_DISPLAY_SKIPPED_HOSTS=False \
		-e ANSIBLE_FORCE_COLOR=True \
		-e ANSIBLE_CONFIG=/workspace/playbooks/ansible.cfg \
		-v "${kubeconfig_path}":/root/.kube/config:ro \
		-v "${SCRIPT_DIR}":/workspace \
		"${CNI_IMAGE}" \
		sh -c "${cmds[*]}"
}

# Execute operation
case $OPERATION in
validate)
	run_validation
	;;
deploy | reset | upgrade | scale | recover | facts)
	enforce_validation "$OPERATION"
	if run_deployment "$OPERATION" "${DEPLOY_ARGS[@]}"; then
		# Copy kubeconfig after successful deployment operations
		if [[ "$OPERATION" == "deploy" || "$OPERATION" == "upgrade" || "$OPERATION" == "scale" ]]; then
			copy_kubeconfig
			run_cni_playbooks "cni.yml"
		fi
	fi
	if [[ "$OPERATION" == "reset" ]]; then
		run_cni_playbooks "cni-reset.yml" || log_warning "CNI reset playbook failed/was skipped"
	fi
	;;
status)
	if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null; then
		kubectl get nodes
	else
		log_warning "Cluster not accessible or kubectl not available"
	fi
	;;
shell)
	run_deployment "shell" "${DEPLOY_ARGS[@]}"
	;;
cni)
	copy_kubeconfig
	run_cni_playbooks "cni.yml"
	;;
cni-reset)
	copy_kubeconfig
	run_cni_playbooks "cni-reset.yml"
	;;
kubeconfig)
	copy_kubeconfig
	;;
*)
	log_error "Unknown operation: $OPERATION"
	usage
	exit 1
	;;
esac

log_success "Operation completed!"
