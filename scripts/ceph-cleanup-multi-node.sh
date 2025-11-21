#!/bin/bash
# cleanup-all-nodes.sh
# Run rook-disk-reset.sh on all nodes via SSH

# Configuration
NODES=("192.168.106.111" "192.168.106.112" "192.168.106.113" "192.168.106.122")
DEVICE="/dev/sdb"
SSH_USER="ansible"
SSH_KEY="/home/devsupreme/.ssh-manager/keys/pn-production-k8s/id_ed25519_pn-production-ansible-role_20250505-163646"
SCRIPT_PATH="./ceph-cleanup.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}☢️  MULTI-NODE ROOK-CEPH CLEANUP${NC}"
echo -e "${RED}=================================${NC}"
echo -e "${YELLOW}Nodes: ${NODES[*]}${NC}"
echo -e "${YELLOW}Device: $DEVICE${NC}"
echo ""
echo -e "${RED}This will WIPE ALL DATA on $DEVICE on ALL nodes!${NC}"
echo ""
echo -e "${YELLOW}Type 'DESTROY-ALL' to confirm:${NC}"
read -r confirmation

if [ "$confirmation" != "DESTROY-ALL" ]; then
	echo "Aborted."
	exit 0
fi

# Check if cleanup script exists
if [ ! -f "$SCRIPT_PATH" ]; then
	echo -e "${RED}ERROR: $SCRIPT_PATH not found!${NC}"
	exit 1
fi

echo ""
echo -e "${GREEN}Starting multi-node cleanup...${NC}"

# Cleanup each node
for node in "${NODES[@]}"; do
	echo ""
	echo -e "${BLUE}========================================${NC}"
	echo -e "${BLUE}Cleaning node: $node${NC}"
	echo -e "${BLUE}========================================${NC}"

	# Copy script to node
	echo "Copying cleanup script to $node..."
	scp -i "$SSH_KEY" "$SCRIPT_PATH" "${SSH_USER}@${node}:/tmp/rook-disk-reset.sh" || {
		echo -e "${RED}Failed to copy script to $node${NC}"
		continue
	}

	# Execute script on node
	echo "Executing cleanup on $node..."
	ssh -i "$SSH_KEY" "${SSH_USER}@${node}" "chmod +x /tmp/rook-disk-reset.sh && /tmp/rook-disk-reset.sh $DEVICE force" || {
		echo -e "${RED}Cleanup failed on $node${NC}"
		continue
	}

	# Remove script from node
	ssh -i "$SSH_KEY" "${SSH_USER}@${node}" "rm -f /tmp/rook-disk-reset.sh"

	echo -e "${GREEN}✓ $node cleaned successfully${NC}"
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Multi-node cleanup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Verify all nodes are clean"
echo "2. Deploy Kubernetes"
echo "3. Deploy Rook-Ceph"
echo ""
