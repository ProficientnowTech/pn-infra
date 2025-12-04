#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENVIRONMENT="${1:-development}"
ROLE="${2:-k8s-master}"

echo "[smoke] generating environment artifacts…"
"${REPO_ROOT}/api/bin/api" generate env --id "${ENVIRONMENT}" --config core --skip-validate >/dev/null

echo "[smoke] building role ${ROLE}…"
"${REPO_ROOT}/api/bin/api" provision build --role "${ROLE}" --env "${ENVIRONMENT}"

META_PATH="${REPO_ROOT}/api/outputs/${ENVIRONMENT}/provisioner/${ROLE}.json"
ARTIFACT_PATH="$(jq -r '.artifact' "$META_PATH")"

echo "[smoke] metadata written to ${META_PATH}"
echo "[smoke] artifact present at ${ARTIFACT_PATH}"
