#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="${REPO_ROOT}/config/packages"

if ! command -v jq >/dev/null 2>&1; then
  echo "[config] jq is required to validate package manifests" >&2
  exit 1
fi

status=0

for manifest in "${PACKAGES_DIR}"/*/package.json; do
  pkg_dir="$(dirname "$manifest")"
  pkg_name="$(basename "$pkg_dir")"
  echo "[config] validating ${pkg_name}…"

  if ! jq -e '.id and .version and (.environments | length > 0)' "$manifest" >/dev/null 2>&1; then
    echo "  ✗ manifest missing required fields: $manifest" >&2
    status=1
    continue
  fi

  version="$(jq -r '.version' "$manifest")"
  if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "  ✗ version ${version} must use SemVer with leading v" >&2
    status=1
  fi

  while IFS= read -r rel_path; do
    if [[ ! -e "$pkg_dir/$rel_path" ]]; then
      echo "  ✗ referenced file missing: $rel_path" >&2
      status=1
    fi
  done < <(jq -r '.environments[].files[]' "$manifest")

  changes=$(git -C "$REPO_ROOT" status --porcelain "$pkg_dir" | grep -v 'package.json' || true)
  pkg_changes=$(git -C "$REPO_ROOT" status --porcelain "$pkg_dir/package.json" || true)
  if [[ -n "$changes" && -z "$pkg_changes" ]]; then
    echo "  ✗ detected changes in ${pkg_name} but version not bumped in package.json" >&2
    status=1
  fi
done

if [[ $status -eq 0 ]]; then
  echo "[config] all package manifests are valid"
fi

exit $status
