#!/bin/bash
#
# Production-Grade Platform Reset Script
# WARNING: This script will DESTROY ALL DATA and return cluster to pristine state
#
# What this script does:
# 1. Deletes all ArgoCD applications
# 2. Removes all Helm releases
# 3. Removes platform secrets (Cloudflare, SSH keys)
# 4. Removes MetalLB configuration resources
# 5. Deletes all namespaces (except protected: kube-system, default, kube-public, kube-node-lease, metallb-system)
# 6. Removes all CRDs (except protected: K8s core and MetalLB CRDs)
# 7. Cleans all PVCs and PVs
# 8. Wipes Ceph cluster data from all disks on all nodes
# 9. Removes Rook Ceph state from nodes
# 10. Returns cluster to fresh install state
#
# Usage: ./reset.sh [--force] [--skip-confirmation] [--light]
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$SCRIPT_DIR"
LOG_FILE="/tmp/platform-reset-$(date +%Y%m%d-%H%M%S).log"

# Flags
FORCE_MODE=false
SKIP_CONFIRMATION=false
LIGHT_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	--force)
		FORCE_MODE=true
		shift
		;;
	--skip-confirmation)
		SKIP_CONFIRMATION=true
		shift
		;;
	--light)
		LIGHT_MODE=true
		shift
		;;
	-h | --help)
		echo "Usage: $0 [OPTIONS]"
		echo ""
		echo "Options:"
		echo "  --force              Force cleanup even if errors occur"
		echo "  --skip-confirmation  Skip all confirmation prompts (DANGEROUS)"
		echo "  --light              Light reset (only platform apps, ArgoCD, no Ceph wipe)"
		echo "  -h, --help           Show this help message"
		echo ""
		echo "This script will completely wipe the platform and all data."
		echo "Use with extreme caution!"
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		exit 1
		;;
	esac
done

# Logging function
log() {
	local level=$1
	shift
	local message="$*"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

	case $level in
	INFO)
		echo -e "$timestamp ${GREEN}[INFO]${NC}    $message"
		;;
	WARN)
		echo -e "$timestamp ${YELLOW}[WARN]${NC}   $message"
		;;
	ERROR)
		echo -e "$timestamp ${RED}[ERROR]${NC}     $message"
		;;
	STEP)
		echo -e "$timestamp ${BLUE}[STEP]${NC}     $message"
		;;
	SUCCESS)
		echo -e "$timestamp ${GREEN}[SUCCESS]${NC} $message"
		;;
	esac

	echo "[$timestamp] [$level] $message" >>"$LOG_FILE"
}

# Error handler
error_exit() {
	log ERROR "$1"
	if [ "$FORCE_MODE" = false ]; then
		exit 1
	fi
}

# Check if running as root or with sudo
check_privileges() {
	if [ "$EUID" -eq 0 ]; then
		log WARN "Running as root - this is acceptable but not required for kubectl operations"
	fi
}

# Check prerequisites
check_prerequisites() {
	log STEP "Checking prerequisites..."

	# Check kubectl
	if ! command -v kubectl &>/dev/null; then
		error_exit "kubectl not found. Please install kubectl."
	fi

	# Check cluster connectivity
	if ! kubectl cluster-info &>/dev/null; then
		error_exit "Cannot connect to Kubernetes cluster. Check kubeconfig."
	fi

	# Check if we can list nodes
	if ! kubectl get nodes &>/dev/null; then
		error_exit "Cannot list nodes. Check RBAC permissions."
	fi

	log INFO "Prerequisites check passed"
}

# Display warning and get confirmation
display_warning() {
	if [ "$SKIP_CONFIRMATION" = true ]; then
		log WARN "Skipping confirmation due to --skip-confirmation flag"
		return 0
	fi

	echo ""
	if [ "$LIGHT_MODE" = true ]; then
		echo "╔═══════════════════════════════════════════════════════════════════════════╗"
		echo "║                                                                           ║"
		echo "║                      ⚠️  LIGHT PLATFORM RESET  ⚠️                         ║"
		echo "║                                                                           ║"
		echo "║  This will remove platform applications and ArgoCD:                       ║"
		echo "║                                                                           ║"
		echo "║  • All ArgoCD applications                                                ║"
		echo "║  • All Helm releases                                                      ║"
		echo "║  • Platform secrets (Cloudflare, SSH keys)                                ║"
		echo "║  • Platform namespaces (argocd, cert-manager, etc.)                       ║"
		echo "║  • Platform CRDs                                                          ║"
		echo "║                                                                           ║"
		echo "║  This does NOT wipe Ceph data or other platform resources.                ║"
		echo "║                                                                           ║"
		echo "╚═══════════════════════════════════════════════════════════════════════════╝"
		echo ""

		read -p "Type 'RESET' to confirm light platform reset: " confirmation

		if [ "$confirmation" != "RESET" ]; then
			log INFO "Reset cancelled by user"
			exit 0
		fi
	else
		echo "╔═══════════════════════════════════════════════════════════════════════════╗"
		echo "║                                                                           ║"
		echo "║                         ⚠️  CRITICAL WARNING  ⚠️                          ║"
		echo "║                                                                           ║"
		echo "║  This script will PERMANENTLY DESTROY ALL DATA in the platform:           ║"
		echo "║                                                                           ║"
		echo "║  • All ArgoCD applications                                                ║"
		echo "║  • All Helm releases                                                      ║"
		echo "║  • All platform namespaces                                                ║"
		echo "║  • All Custom Resource Definitions (CRDs)                                 ║"
		echo "║  • All Persistent Volumes and Claims                                      ║"
		echo "║  • All Ceph data on physical disks                                        ║"
		echo "║  • All application data, databases, secrets                               ║"
		echo "║                                                                           ║"
		echo "║  This action is IRREVERSIBLE. There is NO UNDO.                           ║"
		echo "║                                                                           ║"
		echo "║  Affected nodes and disks:                                                ║"
		echo "║    • k8s-master-01: /dev/sdb                                              ║"
		echo "║    • k8s-master-02: /dev/sdb                                              ║"
		echo "║    • k8s-master-03: /dev/sdb                                              ║"
		echo "║    • k8s-master-04: /dev/sda, /dev/sdb, /dev/sdc, /dev/sdd, /dev/sde      ║"
		echo "║    • k8s-worker-02: /dev/sdb                                              ║"
		echo "║    • k8s-worker-10: /dev/sda, /dev/sdb                                    ║"
		echo "║                                                                           ║"
		echo "╚═══════════════════════════════════════════════════════════════════════════╝"
		echo ""

		read -p "Do you want to continue? Type 'yes-destroy-everything' to proceed: " confirmation

		if [ "$confirmation" != "yes-destroy-everything" ]; then
			log INFO "Reset cancelled by user"
			exit 0
		fi

		echo ""
		read -p "Are you ABSOLUTELY sure? Type 'confirm' to proceed: " second_confirmation

		if [ "$second_confirmation" != "confirm" ]; then
			log INFO "Reset cancelled by user"
			exit 0
		fi
	fi

	log INFO "User confirmed platform reset"
}

# Get list of Ceph nodes and devices from values.yaml
get_ceph_nodes() {
	cat <<'EOF'
k8s-master-01:/dev/sdb
k8s-master-02:/dev/sdb
k8s-master-03:/dev/sdb
k8s-master-04:/dev/sda,/dev/sdb,/dev/sdc,/dev/sdd,/dev/sde
k8s-worker-02:/dev/sdb
k8s-worker-10:/dev/sda,/dev/sdb
EOF
}

# Step 1: Delete all ArgoCD applications
delete_argocd_applications() {
	log STEP "Step 1: Deleting all ArgoCD applications..."

	if ! kubectl get namespace argocd &>/dev/null; then
		log INFO "ArgoCD namespace not found, skipping"
		return 0
	fi

	# Get all applications
	local apps=$(kubectl get applications -n argocd -o name 2>/dev/null || true)

	if [ -z "$apps" ]; then
		log INFO "No ArgoCD applications found"
		return 0
	fi

	log INFO "Found $(echo "$apps" | wc -l) ArgoCD applications"

	# Patch all apps to remove finalizers
	for app in $apps; do
		log INFO "Removing finalizers from $app"
		kubectl patch $app -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
	done

	# Delete all applications
	log INFO "Deleting all ArgoCD applications..."
	kubectl delete applications --all -n argocd --wait=false 2>/dev/null || true

	# Wait for applications to be deleted (with timeout)
	log INFO "Waiting for applications to be deleted..."
	local timeout=60
	local elapsed=0
	while [ $elapsed -lt $timeout ]; do
		local remaining=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
		if [ "$remaining" -eq 0 ]; then
			log SUCCESS "All ArgoCD applications deleted"
			return 0
		fi
		log INFO "Waiting... $remaining applications remaining"
		sleep 5
		elapsed=$((elapsed + 5))
	done

	log WARN "Timeout waiting for applications to delete, forcing..."
	for app in $(kubectl get applications -n argocd -o name 2>/dev/null || true); do
		kubectl delete $app -n argocd --force --grace-period=0 2>/dev/null || true
	done
}

# Step 2: Delete all Helm releases
delete_helm_releases() {
	log STEP "Step 2: Deleting all Helm releases..."

	if ! command -v helm &>/dev/null; then
		log WARN "Helm not found, skipping Helm release cleanup"
		return 0
	fi

	# Get all Helm releases across all namespaces
	local releases=$(helm list --all-namespaces -q 2>/dev/null || true)

	if [ -z "$releases" ]; then
		log INFO "No Helm releases found"
		return 0
	fi

	log INFO "Found $(echo "$releases" | wc -l) Helm releases"

	# Delete each release
	while IFS= read -r release; do
		local namespace=$(helm list --all-namespaces | grep "^$release" | awk '{print $2}')
		log INFO "Uninstalling Helm release: $release (namespace: $namespace)"
		helm uninstall "$release" -n "$namespace" --wait --timeout 5m 2>/dev/null || true
	done <<<"$releases"

	log SUCCESS "All Helm releases deleted"
}

# Step 3: Remove platform secrets
reset_platform_secrets() {
	log STEP "Step 3: Removing platform secrets..."

	# Remove Cloudflare API token secrets from all namespaces
	local namespaces=("cert-manager" "external-dns")
	for ns in "${namespaces[@]}"; do
		if kubectl get namespace "$ns" &>/dev/null 2>&1; then
			if kubectl get secret cloudflare-api-token -n "$ns" &>/dev/null 2>&1; then
				kubectl delete secret cloudflare-api-token -n "$ns" || true
				log INFO "Removed Cloudflare API token secret from namespace: $ns"
			fi
		fi
	done

	# Remove SSH repository secret (if ArgoCD namespace still exists)
	if kubectl get namespace argocd &>/dev/null 2>&1; then
		if kubectl get secret argocd-private-repo -n argocd &>/dev/null 2>&1; then
			kubectl delete secret argocd-private-repo -n argocd || true
			log INFO "Removed SSH repository secret"
		fi
	fi

	log SUCCESS "Platform secrets removed"
}

# Step 4: Remove MetalLB configuration resources
reset_metallb_resources() {
	log STEP "Step 4: Removing MetalLB configuration resources..."

	# Check if MetalLB namespace exists
	if ! kubectl get namespace metallb-system &>/dev/null 2>&1; then
		log INFO "MetalLB namespace not found - skipping MetalLB resource cleanup"
		return 0
	fi

	# Only delete resources managed by metallb-addresspool kustomization
	# Do NOT delete MetalLB controller/speaker or namespace itself

	log INFO "Deleting MetalLB IPAddressPools..."
	kubectl delete ipaddresspool --all -n metallb-system --timeout=60s 2>/dev/null || true

	log INFO "Deleting MetalLB L2Advertisements..."
	kubectl delete l2advertisement --all -n metallb-system --timeout=60s 2>/dev/null || true

	log INFO "Deleting MetalLB BGPAdvertisements..."
	kubectl delete bgpadvertisement --all -n metallb-system --timeout=60s 2>/dev/null || true

	log INFO "Deleting MetalLB BGPPeers..."
	kubectl delete bgppeer --all -n metallb-system --timeout=60s 2>/dev/null || true

	log SUCCESS "MetalLB configuration resources cleaned up (MetalLB controller/speaker unchanged)"
}

# Step 5: Clean Rook Ceph cluster
clean_rook_ceph() {
	log STEP "Step 5: Cleaning Rook Ceph cluster..."

	if ! kubectl get namespace rook-ceph &>/dev/null; then
		log INFO "Rook Ceph namespace not found, skipping"
		return 0
	fi

	# Patch CephCluster to enable cleanup
	log INFO "Enabling Ceph cleanup policy..."
	kubectl patch cephcluster -n rook-ceph rook-ceph \
		-p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}' \
		--type=merge 2>/dev/null || true

	# Delete CephCluster
	log INFO "Deleting CephCluster..."
	kubectl delete cephcluster -n rook-ceph rook-ceph --wait=false 2>/dev/null || true

	# Wait a bit for cleanup to start
	sleep 10

	# Delete all Rook Ceph resources
	log INFO "Deleting Ceph object stores..."
	kubectl delete cephobjectstore --all -n rook-ceph --wait=false 2>/dev/null || true

	log INFO "Deleting Ceph filesystems..."
	kubectl delete cephfilesystem --all -n rook-ceph --wait=false 2>/dev/null || true

	log INFO "Deleting Ceph block pools..."
	kubectl delete cephblockpool --all -n rook-ceph --wait=false 2>/dev/null || true

	# Remove finalizers from all Ceph resources
	log INFO "Removing finalizers from Ceph resources..."
	for resource in cephcluster cephblockpool cephfilesystem cephobjectstore; do
		for item in $(kubectl get $resource -n rook-ceph -o name 2>/dev/null || true); do
			kubectl patch $item -n rook-ceph -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
		done
	done

	# Force delete remaining resources
	log INFO "Force deleting Ceph resources..."
	kubectl delete cephcluster --all -n rook-ceph --force --grace-period=0 2>/dev/null || true
	kubectl delete cephblockpool --all -n rook-ceph --force --grace-period=0 2>/dev/null || true
	kubectl delete cephfilesystem --all -n rook-ceph --force --grace-period=0 2>/dev/null || true
	kubectl delete cephobjectstore --all -n rook-ceph --force --grace-period=0 2>/dev/null || true

	log SUCCESS "Rook Ceph cluster cleanup initiated"
}

# Step 6: Delete all PVCs and PVs
delete_pvcs_and_pvs() {
	log STEP "Step 6: Deleting all PVCs and PVs..."

	# Get all PVCs
	local pvcs=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' || true)

	if [ -z "$pvcs" ]; then
		log INFO "No PVCs found"
	else
		log INFO "Found $(echo "$pvcs" | wc -l) PVCs"

		# Remove finalizers and delete PVCs
		while IFS= read -r pvc; do
			local namespace=$(echo "$pvc" | cut -d'/' -f1)
			local name=$(echo "$pvc" | cut -d'/' -f2)
			log INFO "Deleting PVC: $namespace/$name"
			kubectl patch pvc "$name" -n "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
			kubectl delete pvc "$name" -n "$namespace" --wait=false 2>/dev/null || true
		done <<<"$pvcs"

		# Force delete remaining PVCs
		kubectl delete pvc --all --all-namespaces --force --grace-period=0 2>/dev/null || true
	fi

	# Get all PVs
	local pvs=$(kubectl get pv -o name 2>/dev/null || true)

	if [ -z "$pvs" ]; then
		log INFO "No PVs found"
	else
		log INFO "Found $(echo "$pvs" | wc -l) PVs"

		# Remove finalizers and delete PVs
		for pv in $pvs; do
			log INFO "Deleting PV: $pv"
			kubectl patch $pv -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
			kubectl delete $pv --wait=false 2>/dev/null || true
		done

		# Force delete remaining PVs
		kubectl delete pv --all --force --grace-period=0 2>/dev/null || true
	fi

	log SUCCESS "All PVCs and PVs deleted"
}

# Step 7: Delete platform namespaces
delete_namespaces() {
	log STEP "Step 7: Deleting platform namespaces..."

	# Protected namespaces that should NOT be deleted
	local protected_namespaces="default kube-system kube-public kube-node-lease metallb-system"

	# Get all namespaces
	local all_namespaces=$(kubectl get namespaces -o name | sed 's|namespace/||')

	# Filter out protected namespaces
	local namespaces_to_delete=""
	for ns in $all_namespaces; do
		if ! echo "$protected_namespaces" | grep -qw "$ns"; then
			namespaces_to_delete="$namespaces_to_delete $ns"
		fi
	done

	if [ -z "$namespaces_to_delete" ]; then
		log INFO "No namespaces to delete"
		return 0
	fi

	log INFO "Deleting namespaces: $namespaces_to_delete"

	# Remove finalizers from all resources in namespaces
	for ns in $namespaces_to_delete; do
		log INFO "Cleaning namespace: $ns"

		# Remove finalizers from common resources
		for resource in deployment statefulset daemonset service ingress configmap secret pvc; do
			for item in $(kubectl get $resource -n $ns -o name 2>/dev/null || true); do
				kubectl patch $item -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
			done
		done

		# Delete namespace
		kubectl delete namespace $ns --wait=false 2>/dev/null || true
	done

	# Wait for namespaces to be deleted (with timeout)
	log INFO "Waiting for namespaces to be deleted..."
	local timeout=120
	local elapsed=0
	while [ $elapsed -lt $timeout ]; do
		local remaining=0
		for ns in $namespaces_to_delete; do
			if kubectl get namespace $ns &>/dev/null; then
				remaining=$((remaining + 1))
			fi
		done

		if [ "$remaining" -eq 0 ]; then
			log SUCCESS "All namespaces deleted"
			return 0
		fi

		log INFO "Waiting... $remaining namespaces remaining"
		sleep 5
		elapsed=$((elapsed + 5))
	done

	# Force delete stuck namespaces
	log WARN "Timeout waiting for namespaces, forcing deletion..."
	for ns in $namespaces_to_delete; do
		if kubectl get namespace $ns &>/dev/null; then
			log INFO "Force deleting namespace: $ns"

			# Remove finalizers from namespace itself
			kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

			# Delete namespace
			kubectl delete namespace $ns --force --grace-period=0 2>/dev/null || true

			# If still stuck, use raw API to delete
			kubectl get namespace $ns -o json 2>/dev/null |
				jq '.spec.finalizers = []' |
				kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
		fi
	done

	log SUCCESS "Namespace deletion completed"
}

# Step 8: Delete all CRDs
delete_crds() {
	log STEP "Step 8: Deleting all Custom Resource Definitions (CRDs)..."

	# Get all CRDs
	local crds=$(kubectl get crds -o name 2>/dev/null || true)

	if [ -z "$crds" ]; then
		log INFO "No CRDs found"
		return 0
	fi

	log INFO "Found $(echo "$crds" | wc -l) CRDs"

	# List of CRDs to keep (core Kubernetes and MetalLB CRDs)
	local protected_crds="certificatesigningrequests.certificates.k8s.io ipaddresspools.metallb.io l2advertisements.metallb.io bfdprofiles.metallb.io bgpadvertisements.metallb.io bgppeers.metallb.io communities.metallb.io"

	# Remove finalizers and delete CRDs
	for crd in $crds; do
		local crd_name=$(echo "$crd" | sed 's|customresourcedefinition.apiextensions.k8s.io/||')

		# Skip protected CRDs
		if echo "$protected_crds" | grep -q "$crd_name"; then
			log INFO "Skipping protected CRD: $crd_name"
			continue
		fi

		log INFO "Deleting CRD: $crd_name"

		# Remove finalizers
		kubectl patch $crd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

		# Delete CRD
		kubectl delete $crd --wait=false 2>/dev/null || true
	done

	# Wait for CRDs to be deleted
	log INFO "Waiting for CRDs to be deleted..."
	local timeout=60
	local elapsed=0
	while [ $elapsed -lt $timeout ]; do
		local remaining=$(kubectl get crds 2>/dev/null | grep -vE "^NAME|certificatesigningrequests|metallb.io" | wc -l)
		if [ "$remaining" -eq 0 ]; then
			log SUCCESS "All CRDs deleted"
			return 0
		fi
		log INFO "Waiting... $remaining CRDs remaining"
		sleep 5
		elapsed=$((elapsed + 5))
	done

	# Force delete remaining CRDs
	log WARN "Timeout waiting for CRDs, forcing deletion..."
	for crd in $(kubectl get crds -o name 2>/dev/null | grep -vE "certificatesigningrequests|metallb.io" || true); do
		kubectl delete $crd --force --grace-period=0 2>/dev/null || true
	done

	log SUCCESS "CRD deletion completed"
}

# Step 9: Clean Ceph data from all nodes
clean_ceph_data_from_nodes() {
	log STEP "Step 9: Cleaning Ceph data from all nodes..."

	# Get node-device mapping
	local node_devices=$(get_ceph_nodes)

	log INFO "Cleaning Ceph devices on all nodes..."

	while IFS=':' read -r node devices; do
		log INFO "Processing node: $node"

		# Split devices by comma
		IFS=',' read -ra device_array <<<"$devices"

		for device in "${device_array[@]}"; do
			log INFO "  Cleaning device: $device on $node"

			# Execute cleanup on node
			if kubectl get node "$node" &>/dev/null; then
				# Use kubectl debug to run on node
				log INFO "  Executing cleanup on $node for $device..."
				kubectl debug node/"$node" -it --image=alpine -- sh -c "
                    apk add --no-cache util-linux e2fsprogs lvm2 2>/dev/null || true

                    # Cleanup script inline
                    if mount | grep -q '$device'; then
                        umount -f '$device' 2>/dev/null || true
                        umount -f '${device}1' 2>/dev/null || true
                        umount -f '${device}2' 2>/dev/null || true
                    fi

                    if command -v lvremove &> /dev/null; then
                        for vg in \$(pvs 2>/dev/null | grep '$device' | awk '{print \$2}'); do
                            lvremove -f \$vg 2>/dev/null || true
                            vgremove -f \$vg 2>/dev/null || true
                        done
                        pvremove -f '$device' 2>/dev/null || true
                    fi

                    wipefs --all --force '$device' 2>/dev/null || true
                    dd if=/dev/zero of='$device' bs=1M count=1024 conv=fsync 2>/dev/null || true

                    echo 'Device $device cleaned'
                " 2>&1 | grep -v "Defaulting container" || log WARN "  Failed to clean $device on $node"
			else
				log WARN "  Node $node not found, skipping device cleanup"
			fi
		done

	done <<<"$node_devices"

	log SUCCESS "Ceph device cleanup completed"
}

# Step 10: Remove Rook Ceph state from nodes
remove_rook_state() {
	log STEP "Step 10: Removing Rook Ceph state from nodes..."

	local nodes=$(kubectl get nodes -o name | sed 's|node/||')

	for node in $nodes; do
		log INFO "Cleaning Rook state on node: $node"

		# Remove /var/lib/rook directory
		kubectl debug node/"$node" -it --image=alpine -- sh -c "
            rm -rf /host/var/lib/rook
            rm -rf /host/var/lib/kubelet/plugins/rook-ceph.rbd.csi.ceph.com
            rm -rf /host/var/lib/kubelet/plugins/rook-ceph.cephfs.csi.ceph.com
            rm -rf /host/var/lib/kubelet/plugins_registry/rook-ceph.rbd.csi.ceph.com-reg.sock
            rm -rf /host/var/lib/kubelet/plugins_registry/rook-ceph.cephfs.csi.ceph.com-reg.sock
            echo 'Rook state cleaned on $node'
        " 2>&1 | grep -v "Defaulting container" || log WARN "Failed to clean Rook state on $node"
	done

	log SUCCESS "Rook state cleanup completed"
}

# Step 11: Clean up remaining resources
cleanup_remaining_resources() {
	log STEP "Step 11: Cleaning up remaining resources..."

	# Delete webhook configurations
	log INFO "Deleting webhook configurations..."
	kubectl delete validatingwebhookconfigurations --all 2>/dev/null || true
	kubectl delete mutatingwebhookconfigurations --all 2>/dev/null || true

	# Delete API services
	log INFO "Cleaning up API services..."
	for api in $(kubectl get apiservices -o name | grep -v "v1." || true); do
		kubectl delete $api 2>/dev/null || true
	done

	# Delete cluster roles and bindings
	log INFO "Deleting custom cluster roles and bindings..."
	for cr in $(kubectl get clusterroles -o name | grep -vE "system:|admin|edit|view" || true); do
		kubectl delete $cr 2>/dev/null || true
	done

	for crb in $(kubectl get clusterrolebindings -o name | grep -vE "system:|cluster-admin" || true); do
		kubectl delete $crb 2>/dev/null || true
	done

	# Delete storage classes
	log INFO "Deleting storage classes..."
	kubectl delete storageclass --all 2>/dev/null || true

	log SUCCESS "Remaining resources cleaned up"
}

# Step 12: Verify cluster state
verify_cluster_state() {
	log STEP "Step 12: Verifying cluster state..."

	local issues=0

	# Check namespaces
	local ns_count=$(kubectl get namespaces --no-headers 2>/dev/null | grep -vE "^(default|kube-system|kube-public|kube-node-lease|metallb-system)" | wc -l)
	if [ "$ns_count" -gt 0 ]; then
		log WARN "Found $ns_count unexpected namespaces remaining"
		kubectl get namespaces --no-headers | grep -vE "^(default|kube-system|kube-public|kube-node-lease|metallb-system)"
		issues=$((issues + 1))
	else
		log INFO "✓ Only system namespaces remain"
	fi

	# Check PVCs
	local pvc_count=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
	if [ "$pvc_count" -gt 0 ]; then
		log WARN "Found $pvc_count PVCs remaining"
		kubectl get pvc --all-namespaces
		issues=$((issues + 1))
	else
		log INFO "✓ No PVCs remaining"
	fi

	# Check PVs
	local pv_count=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
	if [ "$pv_count" -gt 0 ]; then
		log WARN "Found $pv_count PVs remaining"
		kubectl get pv
		issues=$((issues + 1))
	else
		log INFO "✓ No PVs remaining"
	fi

	# Check CRDs
	local crd_count=$(kubectl get crds --no-headers 2>/dev/null | grep -vE "certificatesigningrequests|metallb.io" | wc -l)
	if [ "$crd_count" -gt 0 ]; then
		log WARN "Found $crd_count CRDs remaining"
		kubectl get crds | grep -vE "NAME|certificatesigningrequests|metallb.io"
		issues=$((issues + 1))
	else
		log INFO "✓ Only system and MetalLB CRDs remain"
	fi

	# Check storage classes
	local sc_count=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
	if [ "$sc_count" -gt 0 ]; then
		log WARN "Found $sc_count storage classes remaining"
		kubectl get storageclass
		issues=$((issues + 1))
	else
		log INFO "✓ No storage classes remaining"
	fi

	if [ "$issues" -eq 0 ]; then
		log SUCCESS "✓ Cluster verification passed - cluster is in pristine state"
		return 0
	else
		log WARN "⚠ Cluster verification found $issues issues"
		return 1
	fi
}

# Main execution
main() {
	echo ""
	echo "═══════════════════════════════════════════════════════════════════════════"
	if [ "$LIGHT_MODE" = true ]; then
		echo "                   Platform Light Reset Script v1.0"
	else
		echo "                   Platform Reset Script v1.0"
	fi
	echo "═══════════════════════════════════════════════════════════════════════════"
	echo ""

	log INFO "Starting platform reset at $(date)"
	log INFO "Log file: $LOG_FILE"

	# Run checks
	check_privileges
	check_prerequisites

	# Display warning and get confirmation
	display_warning

	log INFO "Beginning platform reset..."
	echo ""

	# Execute cleanup steps
	delete_argocd_applications
	delete_helm_releases
	reset_platform_secrets
	reset_metallb_resources

	if [ "$LIGHT_MODE" = false ]; then
		# Full reset mode - includes Ceph wipe
		clean_rook_ceph
		delete_pvcs_and_pvs
		delete_namespaces
		delete_crds
		clean_ceph_data_from_nodes
		remove_rook_state
		cleanup_remaining_resources

		# Verify
		echo ""
		verify_cluster_state
	else
		# Light mode - only platform apps and namespaces
		delete_namespaces
		delete_crds
		log SUCCESS "Light reset completed - Ceph data preserved"
	fi

	# Final summary
	echo ""
	echo "═══════════════════════════════════════════════════════════════════════════"
	log INFO "Platform reset completed at $(date)"
	log INFO "Full log available at: $LOG_FILE"
	echo "═══════════════════════════════════════════════════════════════════════════"
	echo ""

	if [ "$LIGHT_MODE" = false ]; then
		echo "Next steps:"
		echo "1. Verify cluster state: kubectl get all --all-namespaces"
		echo "2. Check nodes are ready: kubectl get nodes"
		echo "3. Verify disks are clean on nodes"
		echo "4. Redeploy platform from scratch"
	else
		echo "Next steps:"
		echo "1. Verify cluster state: kubectl get all --all-namespaces"
		echo "2. Redeploy platform applications"
	fi
	echo ""
}

# Run main function
main "$@"
