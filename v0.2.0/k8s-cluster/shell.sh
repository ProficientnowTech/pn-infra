#!/bin/bash

# Kubespray Docker Shell Access
# Opens an interactive shell in the Kubespray container for debugging/manual operations

set -e

KUBESPRAY_VERSION="v2.28.0"
INVENTORY_PATH="$(pwd)/inventory/pn-production"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_rsa}"

echo "Starting Kubespray container shell..."
echo "Kubespray Version: ${KUBESPRAY_VERSION}"
echo "Inventory mounted at: /inventory"
echo "SSH Key mounted at: /root/.ssh/id_rsa"

docker run --rm -it \
    --mount type=bind,source="${INVENTORY_PATH}",dst=/inventory \
    --mount type=bind,source="${SSH_KEY_PATH}",dst=/root/.ssh/id_rsa,readonly \
    quay.io/kubespray/kubespray:${KUBESPRAY_VERSION} \
    bash

echo "Container shell closed."