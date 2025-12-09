#!/usr/bin/env bash
#
# Verifies that every node/device pair defined in the Ceph cluster values file
# exists in the Kubernetes cluster. This is a read-only helper that validates
# labels and reports missing devices so operators can fix them before running
# the storage stack.
#
# Usage:
#   ./verify-osd-devices.sh [path/to/values.yaml]

set -euo pipefail

VALUES_FILE="${1:-$(git rev-parse --show-toplevel)/platform/stacks/storage/charts/ceph-cluster/values.yaml}"
YQ_BIN="${YQ_BIN:-yq}"

if ! command -v "${YQ_BIN}" >/dev/null 2>&1; then
  echo "yq binary not found. Install yq or set YQ_BIN." >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl binary not found. Install kubectl." >&2
  exit 1
fi

echo "Reading Ceph storage topology from ${VALUES_FILE}"

cluster_nodes_query='.rook-ceph-cluster.cephClusterSpec.storage.nodes'
node_count="$("${YQ_BIN}" "${cluster_nodes_query} | length" "${VALUES_FILE}" 2>/dev/null || echo 0)"
if [[ "${node_count}" -eq 0 ]]; then
  echo "No nodes defined under ${cluster_nodes_query} in ${VALUES_FILE}" >&2
  exit 1
fi

missing_nodes=()
missing_devices=()

for node in $("${YQ_BIN}" -r "${cluster_nodes_query}[].name" "${VALUES_FILE}"); do
  echo "----"
  echo "Node: ${node}"
  if ! kubectl get node "${node}" >/dev/null 2>&1; then
    echo "  ❌ Kubernetes node not found"
    missing_nodes+=("${node}")
    continue
  fi

  ready_condition=$(kubectl get node "${node}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}')
  echo "  Ready condition: ${ready_condition}"

  label_status=$(kubectl get node "${node}" --show-labels | awk 'NR==2 {print $NF}')
  echo "  Labels: ${label_status}"

  for device in $("${YQ_BIN}" -r "${cluster_nodes_query}[] | select(.name==\"${node}\") | .devices[].name" "${VALUES_FILE}"); do
    disk_path="/host${device}"
    echo "    Checking device ${device} ..."
    if kubectl debug "node/${node}" --quiet --image=registry.k8s.io/e2e-test-images/busybox:1.29 -- chroot /host test -b "${device}" >/dev/null 2>&1; then
      echo "      ✅ Found block device ${device}"
    else
      echo "      ❌ Device ${device} not detected on node ${node}"
      missing_devices+=("${node}:${device}")
    fi
  done
done

echo "==== Summary ===="
if [[ ${#missing_nodes[@]} -eq 0 && ${#missing_devices[@]} -eq 0 ]]; then
  echo "All nodes and devices are present."
else
  [[ ${#missing_nodes[@]} -gt 0 ]] && printf 'Missing nodes: %s\n' "${missing_nodes[*]}"
  [[ ${#missing_devices[@]} -gt 0 ]] && printf 'Missing devices: %s\n' "${missing_devices[*]}"
  exit 2
fi
