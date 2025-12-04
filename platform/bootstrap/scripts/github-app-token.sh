#!/usr/bin/env bash
#
# Generate a GitHub App installation access token.
# Usage:
#   platform/scripts/github-app-token.sh \
#     --app-id 12345 \
#     --installation-id 67890 \
#     --private-key /secure/path/pn-platform-bot.pem
#
# Optional: --output token.txt  (writes token only)

set -euo pipefail

APP_ID=""
INSTALLATION_ID=""
PRIVATE_KEY=""
OUTPUT_PATH=""

usage() {
	cat <<EOF
Usage: $0 --app-id <id> --installation-id <id> --private-key <path> [--output <file>]

Required flags:
  --app-id            GitHub App ID
  --installation-id   Installation ID from the App's installation URL
  --private-key       Path to the GitHub App PEM private key

Optional flags:
  --output            File to write the access token to (token only)
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--app-id)
		APP_ID="$2"
		shift 2
		;;
	--installation-id)
		INSTALLATION_ID="$2"
		shift 2
		;;
	--private-key)
		PRIVATE_KEY="$2"
		shift 2
		;;
	--output)
		OUTPUT_PATH="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown flag: $1" >&2
		usage
		exit 1
		;;
	esac
done

if [[ -z "$APP_ID" || -z "$INSTALLATION_ID" || -z "$PRIVATE_KEY" ]]; then
	echo "Missing required flags." >&2
	usage
	exit 1
fi

if [[ ! -f "$PRIVATE_KEY" ]]; then
	echo "Private key not found: $PRIVATE_KEY" >&2
	exit 1
fi

command -v openssl >/dev/null 2>&1 || { echo "openssl is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

b64url() {
	openssl base64 -A | tr '+/' '-_' | tr -d '='
}

now=$(date +%s)
iat=$((now - 60))
exp=$((now + 9 * 60)) # 9 minutes gives breathing room before the 10-minute max

header='{"alg":"RS256","typ":"JWT"}'
payload=$(jq -nc --argjson iat "$iat" --argjson exp "$exp" --arg app_id "$APP_ID" '{iat:$iat,exp:$exp,iss: ($app_id|tonumber)}')

unsigned_header=$(printf '%s' "$header" | b64url)
unsigned_payload=$(printf '%s' "$payload" | b64url)
unsigned_token="${unsigned_header}.${unsigned_payload}"

signature=$(printf '%s' "$unsigned_token" | openssl dgst -sha256 -sign "$PRIVATE_KEY" | b64url)
jwt="${unsigned_token}.${signature}"

response=$(curl -sf -X POST \
	-H "Authorization: Bearer ${jwt}" \
	-H "Accept: application/vnd.github+json" \
	"https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens")

token=$(echo "$response" | jq -r '.token')
expires_at=$(echo "$response" | jq -r '.expires_at')

if [[ -z "$token" || "$token" == "null" ]]; then
	echo "Failed to obtain installation token. Response:" >&2
	echo "$response" >&2
	exit 1
fi

cat <<EOF
GitHub App installation token generated.
  App ID:           ${APP_ID}
  Installation ID:  ${INSTALLATION_ID}
  Expires at:       ${expires_at}

Token:
${token}
EOF

if [[ -n "$OUTPUT_PATH" ]]; then
	printf '%s' "$token" >"$OUTPUT_PATH"
	echo "Token written to ${OUTPUT_PATH}"
fi
