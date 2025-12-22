#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"
SPEC_DIR="${ROOT_DIR}/platform/bootstrap/secrets/specs"
GENERATED_DIR="${ROOT_DIR}/platform/bootstrap/.generated"
CHART_DIR="${ROOT_DIR}/platform/bootstrap/secrets/chart"
MANIFEST_DIR="${CHART_DIR}/files/manifests"
SEALED_DIR="${MANIFEST_DIR}/sealed"
PUSH_DIR="${MANIFEST_DIR}/push"
STATE_DIR="${GENERATED_DIR}/state"
ENV_FILE="${ROOT_DIR}/platform/bootstrap/secrets/.env.local"
DEFAULT_SECRET_STORE_NAME="${VAULT_SECRET_STORE_NAME:-vault-backend}"
DEFAULT_SECRET_STORE_KIND="${VAULT_SECRET_STORE_KIND:-ClusterSecretStore}"
GITHUB_APP_TOKEN_VARS="${GITHUB_APP_TOKEN_VARS:-BACKSTAGE_GITHUB_TOKEN}"
GITHUB_TOKEN_HELPER="${SCRIPT_DIR}/github-app-token.sh"
TEMP_GITHUB_KEY_FILE=""
SEALED_SECRETS_CERT_FILE=""
HELM_RELEASE_NAME="${BOOTSTRAP_SECRETS_RELEASE:-bootstrap-secrets}"
HELM_RELEASE_NAMESPACE="${BOOTSTRAP_SECRETS_NAMESPACE:-argocd}"
declare -A NAMESPACES=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "%b[INFO]%b  [$(date +'%H:%M:%S')] [Secret Bootstrap] %s\n" "$BLUE" "$NC" "$1"; }
warn() { printf "%b[WARN]%b  [$(date +'%H:%M:%S')] [Secret Bootstrap] %s\n" "$YELLOW" "$NC" "$1"; }
error() { printf "%b[ERROR]%b [$(date +'%H:%M:%S')] [Secret Bootstrap] %s\n" "$RED" "$NC" "$1"; }
fatal() {
	error "$1"
	exit 1
}

cleanup() {
	if [[ -n "$TEMP_GITHUB_KEY_FILE" && -f "$TEMP_GITHUB_KEY_FILE" ]]; then
		rm -f "$TEMP_GITHUB_KEY_FILE"
	fi
	if [[ -n "$SEALED_SECRETS_CERT_FILE" && -f "$SEALED_SECRETS_CERT_FILE" ]]; then
		rm -f "$SEALED_SECRETS_CERT_FILE"
	fi
}
trap cleanup EXIT
trap 'fatal "Interrupted"' INT

expand_path() {
	local path="$1"
	[[ -n "$path" ]] || return 1
	case "$path" in
	~)
		path="$HOME"
		;;
	~/*)
		path="${HOME}/${path#~/}"
		;;
	/*)
		;;
	./*)
		path="${REPO_ROOT}/${path#./}"
		;;
	*)
		path="${REPO_ROOT}/${path}"
		;;
	esac
	printf '%s' "$path"
}

ensure_dirs() {
	mkdir -p "$CHART_DIR" "$MANIFEST_DIR" "$SEALED_DIR" "$PUSH_DIR" "$STATE_DIR"
	find "$SEALED_DIR" -maxdepth 1 -type f -name '*.yaml' -delete
	find "$PUSH_DIR" -maxdepth 1 -type f -name '*.yaml' -delete
}

ensure_binaries() {
	local require_helm="$1"
	local bins=(yq jq kubeseal kubectl openssl)
	if [[ "$require_helm" == "true" ]]; then
		bins+=(helm)
	fi
	for bin in "${bins[@]}"; do
		command -v "$bin" >/dev/null 2>&1 || fatal "Required binary '$bin' not found in PATH"
	done
}

load_env_file() {
	if [[ -f "$ENV_FILE" ]]; then
		log "Loading env vars from $ENV_FILE"
		set -a
		# shellcheck source=/dev/null
		source "$ENV_FILE"
		set +a
	fi
}

ensure_github_app_token() {
	local app_id="${GITHUB_APP_ID:-}"
	local install_id="${GITHUB_APP_INSTALLATION_ID:-}"
	local private_key_path
	private_key_path="$(resolve_github_private_key_path)" || private_key_path=""
	if [[ -z "$app_id" || -z "$install_id" || -z "$private_key_path" ]]; then
		return
	fi
	if [[ ! -f "$private_key_path" ]]; then
		warn "GitHub App private key not found at $private_key_path; skipping auto-token generation."
		return
	fi
	local missing_targets=()
	IFS=',' read -r -a targets <<<"$GITHUB_APP_TOKEN_VARS"
	for target in "${targets[@]}"; do
		target="${target// /}"
		[[ -n "$target" ]] || continue
		if [[ -z "${!target:-}" ]]; then
			missing_targets+=("$target")
		fi
	done
	[[ ${#missing_targets[@]} -gt 0 ]] || return 0
	[[ -x "$GITHUB_TOKEN_HELPER" ]] || fatal "GitHub token helper not found at $GITHUB_TOKEN_HELPER"
	local tmp
	tmp="$(mktemp)"
	if ! "$GITHUB_TOKEN_HELPER" \
		--app-id "$app_id" \
		--installation-id "$install_id" \
		--private-key "$private_key_path" \
		--output "$tmp"; then
		rm -f "$tmp"
		warn "Failed to mint GitHub App installation token; skipping auto-fill."
		return
	fi
	local token
	token="$(<"$tmp")"
	rm -f "$tmp"
	for target in "${missing_targets[@]}"; do
		export "$target"="$token"
	done
	log "Injected GitHub token into: ${missing_targets[*]}"
}

resolve_github_private_key_path() {
	if [[ -n "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ]]; then
		expand_path "${GITHUB_APP_PRIVATE_KEY_FILE}"
		return
	fi

	local candidate="${GITHUB_APP_PRIVATE_KEY:-}"
	[[ -n "$candidate" ]] || return 1

	if [[ "$candidate" =~ -----BEGIN ]]; then
		TEMP_GITHUB_KEY_FILE="$(mktemp)"
		printf '%b\n' "$candidate" >"$TEMP_GITHUB_KEY_FILE"
		chmod 600 "$TEMP_GITHUB_KEY_FILE" || true
		printf '%s' "$TEMP_GITHUB_KEY_FILE"
		return 0
	fi

	expand_path "$candidate"
}

ensure_sealed_secrets_cert() {
	local controller="${SEALED_SECRETS_CONTROLLER:-sealed-secrets}"
	local namespace="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"

	if [[ -n "${SEALED_SECRETS_CERT_FILE:-}" && -f "$SEALED_SECRETS_CERT_FILE" ]]; then
		return 0
	fi

	local tmp_cert
	tmp_cert="$(mktemp)"
	local max_attempts=12
	local attempt=1

	while [[ $attempt -le $max_attempts ]]; do
		if kubeseal --controller-name "$controller" \
			--controller-namespace "$namespace" \
			--fetch-cert >"$tmp_cert" 2>/dev/null; then
			SEALED_SECRETS_CERT_FILE="$tmp_cert"
			log "Fetched sealed-secrets controller certificate"
			return 0
		fi
		warn "Waiting for sealed-secrets controller certificate (attempt $attempt/$max_attempts)..."
		sleep 5
		attempt=$((attempt + 1))
	done

	rm -f "$tmp_cert"
	fatal "Unable to fetch sealed-secrets controller certificate"
}

random_string() {
	local length="$1"
	local alphabet="$2"
	case "$alphabet" in
	hex)
		local bytes=$(((length + 1) / 2))
		openssl rand -hex "$bytes" | cut -c1-"$length"
		;;
	url)
		openssl rand -base64 $((length * 2)) | tr '+/' '-_' | tr -d '=' | cut -c1-"$length"
		;;
	base64)
		openssl rand -base64 $((length * 2)) | cut -c1-"$length"
		;;
	*)
		# Ignore SIGPIPE from tr when head closes the pipe
		(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null || true) | head -c "$length"
		;;
	esac
}

hash_value() {
	local method="$1"
	local value="$2"
	case "$method" in
	bcrypt)
		# OpenSSL doesn't support -bcrypt, use SHA512-crypt instead (equally secure)
		openssl passwd -6 "$value"
		;;
	sha512) openssl passwd -6 "$value" ;;
	apr1) openssl passwd -apr1 "$value" ;;
	*) printf "%s" "$value" ;;
	esac
}

read_json_file() {
	local file="$1"
	if [[ -f "$file" ]]; then
		cat "$file"
	else
		printf '{}'
	fi
}

write_json_file() {
	local file="$1"
	local content="$2"
	printf '%s\n' "$content" >"$file"
}

update_json_field() {
	local json="$1"
	local key="$2"
	local value="$3"
	printf '%s' "$json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}'
}

build_secret_json() {
	local name="$1" namespace="$2" type="$3" stringData="$4" labels="$5" annotations="$6"
	jq -n \
		--arg name "$name" \
		--arg namespace "$namespace" \
		--arg type "$type" \
		--argjson data "$stringData" \
		--argjson labels "$labels" \
		--argjson annotations "$annotations" '
		{
			apiVersion: "v1",
			kind: "Secret",
			metadata: (
				{ name: $name, namespace: $namespace }
				+ (if ($labels | length) > 0 then { labels: $labels } else {} end)
				+ (if ($annotations | length) > 0 then { annotations: $annotations } else {} end)
			),
			type: $type,
			stringData: $data
		}'
}

build_push_secret_json() {
	local namespace="$1" name="$2" secretName="$3" vaultPath="$4" stringDataKeys="$5" storeName="$6" storeKind="$7"
	jq -n \
		--arg ns "$namespace" \
		--arg name "${name}-push" \
		--arg localSecret "$secretName" \
		--arg vaultPath "$vaultPath" \
		--argjson data "$stringDataKeys" \
		--arg storeName "$storeName" \
		--arg storeKind "$storeKind" '
		{
			apiVersion: "external-secrets.io/v1alpha1",
			kind: "PushSecret",
			metadata: { name: $name, namespace: $ns },
			spec: {
				refreshInterval: "1h",
				secretStoreRefs: [{ name: $storeName, kind: $storeKind }],
				selector: { secret: { name: $localSecret } },
				data: (
					[ $data[] | {
						match: {
							secretKey: .secretKey,
							remoteRef: {
								remoteKey: $vaultPath,
								property: .property
							}
						}
					}]
				)
			}
		}'
}

process_spec() {
	local file="$1" force="$2"
	local spec_json
	spec_json="$(yq -o=json "$file")"
	local name namespace type
	name="$(jq -r '.metadata.name // empty' <<<"$spec_json")"
	namespace="$(jq -r '.spec.namespace // empty' <<<"$spec_json")"
	type="$(jq -r '.spec.type // "Opaque"' <<<"$spec_json")"
	[[ -n "$name" && -n "$namespace" ]] || {
		warn "Skipping $file (missing name/namespace)"
		return
	}
	NAMESPACES["$namespace"]=1

	local state_file="${STATE_DIR}/${namespace}-${name}.json"
	local state_json
	if [[ "$force" == "true" ]]; then
		state_json='{}'
	else
		state_json="$(read_json_file "$state_file")"
	fi

	local string_data='{}'
	local emitted_keys=()
	local data_keys=()
	mapfile -t data_keys < <(jq -r '.spec.data | keys[]?' <<<"$spec_json")
	for key in "${data_keys[@]}"; do
		local entry_json value cache hash_method format env_name literal alphabet length optional_entry
		entry_json="$(jq -r --arg key "$key" '.spec.data[$key]' <<<"$spec_json")"
		cache="$(jq -r '.cache // true' <<<"$entry_json")"
		hash_method="$(jq -r '.hash.method // empty' <<<"$entry_json")"
		format="$(jq -r '.format // empty' <<<"$entry_json")"
		env_name="$(jq -r '.env // empty' <<<"$entry_json")"
		literal="$(jq -r '.literal // empty' <<<"$entry_json")"
		alphabet="$(jq -r '.generate.alphabet // "alnum"' <<<"$entry_json")"
		length="$(jq -r '.generate.length // 32' <<<"$entry_json")"
		optional_entry="$(jq -r '.optional // false' <<<"$entry_json")"

		if [[ "$cache" == "true" && "$(jq -r --arg k "$key" '.[$k] // empty' <<<"$state_json")" != "" ]]; then
			value="$(jq -r --arg k "$key" '.[$k]' <<<"$state_json")"
		elif [[ -n "$env_name" ]]; then
			value="${!env_name:-}"
			if [[ -z "$value" ]]; then
				if [[ "$(jq -r '.spec.optional // false' <<<"$spec_json")" == "true" || "$optional_entry" == "true" ]]; then
					warn "Skipping optional entry $namespace/$name:$key (env $env_name missing)"
					continue
				else
					fatal "Env var $env_name missing for $namespace/$name:$key"
				fi
			fi
		elif [[ -n "$literal" ]]; then
			value="$literal"
		elif jq -e '.generate' >/dev/null <<<"$entry_json"; then
			value="$(random_string "$length" "$alphabet")"
		else
			fatal "No value source defined for $namespace/$name:$key"
		fi

		if [[ -n "$hash_method" ]]; then
			value="$(hash_value "$hash_method" "$value")"
		fi
		if [[ -n "$format" ]]; then
			value="${format/\{value\}/$value}"
		fi
		if [[ "$cache" == "true" ]]; then
			state_json="$(update_json_field "$state_json" "$key" "$value")"
		fi
		string_data="$(update_json_field "$string_data" "$key" "$value")"
		emitted_keys+=("$key")
	done

	if (($(jq 'length' <<<"$string_data") == 0)); then
		warn "No data rendered for $namespace/$name; skipping"
		return
	fi

	write_json_file "$state_file" "$state_json"

	local labels annotations
	labels="$(jq '.metadata.labels // {}' <<<"$spec_json")"
	annotations="$(jq '.metadata.annotations // {}' <<<"$spec_json")"
	local secret_json
	secret_json="$(build_secret_json "$name" "$namespace" "$type" "$string_data" "$labels" "$annotations")"
	local sealed_path="${SEALED_DIR}/${namespace}-${name}.yaml"
	local kubeseal_args=(--format yaml)
	if [[ -n "${SEALED_SECRETS_CERT_FILE:-}" && -f "$SEALED_SECRETS_CERT_FILE" ]]; then
		kubeseal_args+=(--cert "$SEALED_SECRETS_CERT_FILE")
	else
		kubeseal_args+=(
			--controller-name "${SEALED_SECRETS_CONTROLLER:-sealed-secrets}"
			--controller-namespace "${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
		)
	fi
	if ! printf '%s' "$secret_json" | kubeseal "${kubeseal_args[@]}" >"$sealed_path"; then
		fatal "Failed to seal secret for $namespace/$name"
	fi

	local push_json_file=""
	if jq -e '.spec.vault' >/dev/null <<<"$spec_json"; then
		local vault_path store_name store_kind
		vault_path="$(jq -r '.spec.vault.path // empty' <<<"$spec_json")"
		store_name="$(jq -r '.spec.vault.secretStoreRef.name // empty' <<<"$spec_json")"
		store_kind="$(jq -r '.spec.vault.secretStoreRef.kind // empty' <<<"$spec_json")"
		[[ -n "$vault_path" ]] || fatal "vault.path missing for $namespace/$name"
		[[ -n "$store_name" ]] || store_name="$DEFAULT_SECRET_STORE_NAME"
		[[ -n "$store_kind" ]] || store_kind="$DEFAULT_SECRET_STORE_KIND"
		local push_data='[]'
		for key in "${emitted_keys[@]}"; do
			local entry_json property
			entry_json="$(jq -r --arg key "$key" '.spec.data[$key]' <<<"$spec_json")"
			property="$(jq -r '.vaultProperty // empty' <<<"$entry_json")"
			[[ -n "$property" ]] || property="$key"
			push_data="$(printf '%s' "$push_data" | jq --arg sk "$key" --arg prop "$property" '. + [{secretKey: $sk, property: $prop}]')"
		done
		local push_json
		push_json="$(build_push_secret_json "$namespace" "$name" "$name" "$vault_path" "$push_data" "$store_name" "$store_kind")"
		push_json_file="${PUSH_DIR}/${namespace}-${name}-push.yaml"
		printf '%s\n' "$push_json" | yq -P >"$push_json_file"
	fi
	log "Rendered secrets for $namespace/$name -> $sealed_path${push_json_file:+, $push_json_file}"
}

deploy_with_helm() {
	local manifest_count
	manifest_count="$(find "$MANIFEST_DIR" -type f -name '*.yaml' | wc -l | tr -d ' ')"
	if [[ "${manifest_count:-0}" -eq 0 ]]; then
		warn "No generated manifests found under $MANIFEST_DIR; skipping Helm apply."
		return
	fi

	log "Deploying bootstrap secrets with Helm release ${HELM_RELEASE_NAME} in namespace ${HELM_RELEASE_NAMESPACE}"
	helm upgrade --install "$HELM_RELEASE_NAME" "$CHART_DIR" \
		--namespace "$HELM_RELEASE_NAMESPACE" \
		--create-namespace \
		--wait \
		--atomic
	log "Helm release ${HELM_RELEASE_NAME} applied with ${manifest_count} manifest(s)"
}

main() {
	local apply="false" force="false"
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--apply) apply="true" ;;
		--force) force="true" ;;
		-h | --help)
			cat <<EOF
Usage: $SCRIPT_NAME [--apply] [--force]
  --apply   Deploy generated manifests with Helm
  --force   Regenerate cached values even if state exists
EOF
			exit 0
			;;
		*)
			fatal "Unknown flag: $1"
			;;
		esac
		shift
	done

	ensure_dirs
	ensure_binaries "$apply"
	load_env_file
	ensure_github_app_token
	ensure_sealed_secrets_cert
	local spec_files
	mapfile -t spec_files < <(find "$SPEC_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) | sort)
	[[ ${#spec_files[@]} -gt 0 ]] || {
		warn "No spec files found in $SPEC_DIR"
		exit 0
	}
	for spec in "${spec_files[@]}"; do
		process_spec "$spec" "$force"
	done
	if [[ "$apply" == "true" ]]; then
		deploy_with_helm
	fi
}

main "$@"
