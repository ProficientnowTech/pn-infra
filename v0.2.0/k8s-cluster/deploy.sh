#!/usr/bin/env bash

# Kubespray Docker Deployment Script
# This script uses the official Kubespray Docker image to deploy Kubernetes
# without polluting your repository with Kubespray source code.

set -e

# Configuration
KUBESPRAY_VERSION="v2.28.1"
INVENTORY_PATH="$(pwd)/inventory/pn-production"
SSH_KEY_PATH="${HOME}/.ssh-manager/keys/pn-production-k8s/id_ed25519_pn-production-ansible-role_20250505-163646"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Kubespray Docker Deployment${NC}"
echo "Kubespray Version: ${KUBESPRAY_VERSION}"
echo "Inventory Path: ${INVENTORY_PATH}"
echo "SSH Key: ${SSH_KEY_PATH}"

# Verify prerequisites
if [[ ! -f "${SSH_KEY_PATH}" ]]; then
    echo -e "${RED}Error: SSH private key not found at ${SSH_KEY_PATH}${NC}"
    exit 1
fi

if [[ ! -f "${INVENTORY_PATH}/inventory.ini" ]]; then
    echo -e "${RED}Error: Inventory file not found at ${INVENTORY_PATH}/inventory.ini${NC}"
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    exit 1
fi

echo -e "${YELLOW}Pulling Kubespray Docker image...${NC}"
docker pull quay.io/kubespray/kubespray:${KUBESPRAY_VERSION}

echo -e "${YELLOW}Starting Kubespray container...${NC}"
docker run --rm -it \
    --mount type=bind,source="${INVENTORY_PATH}",dst="/kubespray/inventory/pn-production/" \
    --mount type=bind,source="${SSH_KEY_PATH}",dst="/root/.ssh/id_rsa" \
    quay.io/kubespray/kubespray:${KUBESPRAY_VERSION} \
    bash -c "
    cd /kubespray
    ansible-playbook -i inventory/pn-production/inventory.ini cluster.yml -b -v
    "

echo -e "${GREEN}Kubespray deployment completed!${NC}"
