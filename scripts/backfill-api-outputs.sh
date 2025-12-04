#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="development"
CONFIG_PACKAGE="core"
PACKAGE_VERSION="v0.0.0-backfill"
TF_VARS_SOURCE=""
INVENTORY_SOURCE=""
BUSINESS_SOURCE=""

usage() {
	cat <<EOF
Backfill API outputs for an environment that was generated before the modular refactor.

Usage: $0 [OPTIONS]

Options:
  --env NAME              Environment identifier (default: development)
  --config PACKAGE        Config package ID (default: core)
  --package-version VER   Package version recorded in metadata (default: v0.0.0-backfill)
  --tfvars PATH           Path to an existing terraform.tfvars file to copy
  --inventory PATH        Path to an existing Kubespray inventory directory to copy
  --business PATH         Path to a Helm values file for business workloads
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
	case $1 in
		--env)
			ENVIRONMENT="$2"
			shift 2
			;;
		--config)
			CONFIG_PACKAGE="$2"
			shift 2
			;;
		--package-version)
			PACKAGE_VERSION="$2"
			shift 2
			;;
		--tfvars)
			TF_VARS_SOURCE="$2"
			shift 2
			;;
		--inventory)
			INVENTORY_SOURCE="$2"
			shift 2
			;;
		--business)
			BUSINESS_SOURCE="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage
			exit 1
			;;
	esac
done

OUTPUT_DIR="${REPO_ROOT}/api/outputs/${ENVIRONMENT}"
mkdir -p "$OUTPUT_DIR"

declare -A FILE_MAP

copy_file_if_set() {
	local key="$1"
	local src="$2"
	local dst="$3"
	if [[ -n "$src" ]]; then
		if [[ ! -e "$src" ]]; then
			echo "[backfill] source not found for ${key}: $src" >&2
			exit 1
		fi
		mkdir -p "$(dirname "$dst")"
		if [[ -d "$src" ]]; then
			rm -rf "$dst"
			cp -R "$src" "$dst"
		else
			cp "$src" "$dst"
		fi
		FILE_MAP["$key"]="$dst"
		echo "[backfill] copied ${key} -> ${dst}"
	fi
}

copy_file_if_set "terraform" "$TF_VARS_SOURCE" "${OUTPUT_DIR}/terraform.tfvars"
copy_file_if_set "kubesprayInventory" "$INVENTORY_SOURCE" "${OUTPUT_DIR}/kubespray"
copy_file_if_set "business" "$BUSINESS_SOURCE" "${OUTPUT_DIR}/business.yaml"

FILES_JSON="{}"
for key in "${!FILE_MAP[@]}"; do
	value=${FILE_MAP[$key]}
	FILES_JSON=$(jq -n --argjson files "$FILES_JSON" --arg k "$key" --arg v "$value" '$files + {($k): $v}')
done

METADATA_PATH="${OUTPUT_DIR}/metadata.json"
jq -n \
	--arg env "$ENVIRONMENT" \
	--arg pkg "$CONFIG_PACKAGE" \
	--arg ver "$PACKAGE_VERSION" \
	--argjson files "$FILES_JSON" \
	'{
		environment: $env,
		configPackage: {
			id: $pkg,
			version: $ver
		},
		generatedAt: (now | todateiso8601),
		files: $files
	}' > "$METADATA_PATH"

echo "[backfill] metadata written to ${METADATA_PATH}"
