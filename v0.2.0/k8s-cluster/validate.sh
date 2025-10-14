#!/bin/bash

# Kubespray Docker Validation
# Runs syntax check and dry-run validation using Kubespray Docker image

set -e

KUBESPRAY_VERSION="v2.28.0"
INVENTORY_PATH="$(pwd)/inventory/pn-production"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_rsa}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Running Kubespray validation...${NC}"

echo -e "${YELLOW}1. Syntax check...${NC}"
docker run --rm \
    --mount type=bind,source="${INVENTORY_PATH}",dst=/inventory \
    --mount type=bind,source="${SSH_KEY_PATH}",dst=/root/.ssh/id_rsa,readonly \
    quay.io/kubespray/kubespray:${KUBESPRAY_VERSION} \
    ansible-playbook -i /inventory/inventory.ini --syntax-check cluster.yml

echo -e "${YELLOW}2. Dry run (check mode)...${NC}"
docker run --rm \
    --mount type=bind,source="${INVENTORY_PATH}",dst=/inventory \
    --mount type=bind,source="${SSH_KEY_PATH}",dst=/root/.ssh/id_rsa,readonly \
    quay.io/kubespray/kubespray:${KUBESPRAY_VERSION} \
    ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_rsa --check cluster.yml

echo -e "${GREEN}Validation completed successfully!${NC}"