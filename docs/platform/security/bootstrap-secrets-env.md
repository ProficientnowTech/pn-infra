# Bootstrap Secret Environment Variables

Use this guide when preparing `platform/bootstrap/secrets/.env.local`. Every entry maps
to a specific `SecretSpec` under `platform/bootstrap/secrets/specs/` and ultimately to a
Vault path listed in `docs/platform/security/secret-inventory.md`.

> **Workflow**
> 1. Copy `.env.example` → `.env.local` in the same directory.
> 2. Fill in the values below (leave blank only if marked optional).
> 3. Run `platform/bootstrap/scripts/render-secrets.sh --apply`. The script loads
>    `.env.local`, validates the required keys, and tells you if anything is still missing.

## Infrastructure & Bootstrap
| Variable | Required | Purpose / Usage | Where to obtain |
|----------|----------|-----------------|-----------------|
| `CLOUDFLARE_API_TOKEN` | ✓ | DNS-01 token for cert-manager & external-dns. | Cloudflare dashboard → API Tokens (must allow Zone:DNS:Edit). |
| `ARGOCD_REPO_SSH_PRIVATE_KEY` | ✓ | Private deploy key ArgoCD uses for `pn-infra` repo. | Generate via `ssh-keygen`; add the public key to GitHub repo deploy keys. |
| `ARGOCD_NOTIFICATIONS_SLACK_TOKEN` | ✓ | Slack bot token for ArgoCD Notifications. | Slack → Build App → **Bot Token Scopes** `chat:write`, install to workspace, copy the **Bot User OAuth Token** (`xoxb-...`). |
| `ARGOCD_NOTIFICATIONS_EMAIL_PASSWORD` | ✓ | SMTP password for ArgoCD Notifications. | Mail provider (Mailcow/SES/etc.). Example: Mailcow → Configuration → Mailboxes → create `platform-alerts@pnats.cloud` and copy its password or app-specific SMTP token. |

## Developer Platform
| Variable | Required | Purpose / Usage | Where to obtain |
|----------|----------|-----------------|-----------------|
| `BACKSTAGE_GITHUB_TOKEN` | ✓ (auto-populated) | GitHub App installation token for Backstage catalog + scaffolder. | Automatically generated if you set the GitHub App envs below; otherwise paste a token manually. |
| `GITHUB_APP_ID` | Optional | App ID for `pn-platform-bot`. Enables automatic token minting. | GitHub App settings → General. |
| `GITHUB_APP_INSTALLATION_ID` | Optional | Installation ID (from the URL). | After installing the App, copy the numeric ID. |
| `GITHUB_APP_PRIVATE_KEY` | Optional | Path to the `.pem` private key. Used by the renderer to mint tokens. | Secure location on your workstation. |
| `GITHUB_APP_TOKEN_VARS` | Optional | Comma-separated env vars that should receive the generated token. Defaults to `BACKSTAGE_GITHUB_TOKEN`. | e.g. `BACKSTAGE_GITHUB_TOKEN,ARGOCD_AUTO_PR_TOKEN`. |
| `CLUSTERAPI_SSH_PRIVATE_KEY` | ✓ | SSH key for ClusterAPI workload clusters. | Generate keypair; public key placed in cloud-init/users. |

> Harbor’s S3 credentials are created automatically once the storage stack deploys (CephObjectStoreUser + PushSecret). No `.env.local` entries are required for Harbor’s object storage anymore.

## Storage / Database Backups
| Variable | Required | Purpose / Usage | Where to obtain |
|----------|----------|-----------------|-----------------|
| `POSTGRES_BACKUP_AWS_ACCESS_KEY_ID` | ✓ | S3 backup credential for Zalando Postgres (same IAM user can serve all backup targets). | AWS IAM / MinIO access key. |
| `POSTGRES_BACKUP_AWS_SECRET_ACCESS_KEY` | ✓ | Secret key for above. | AWS IAM / MinIO secret key. |
| `POSTGRES_BACKUP_AWS_REGION` | ✓ | Region of the S3 bucket. | AWS region (e.g., `ap-south-1`). |
| `POSTGRES_BACKUP_S3_BUCKET` | ✓ | Bucket name used for WAL backups (unique per environment). | Name of dedicated backup bucket. |
| `POSTGRES_BACKUP_KMS_KEY_ID` | Optional | KMS key for encrypting backups. | AWS KMS key ID (leave blank if not used). |
| `POSTGRES_BACKUP_KMS_SIGNING_KEY_ID` | Optional | KMS signing key ID. | AWS KMS (only if using signed requests). |

## Keycloak Identity Providers & SMTP
| Variable | Required | Purpose / Usage | Where to obtain |
|----------|----------|-----------------|-----------------|
| `KEYCLOAK_GITHUB_CLIENT_ID` | ✓ | GitHub IdP client ID for Keycloak (stored in the same secret Keycloak reads at runtime). | GitHub → Settings → Developer settings → OAuth Apps → “New OAuth App”. Set **Homepage URL** to your platform domain and **Authorization callback URL** to `https://keycloak.<domain>/realms/<realm>/broker/github/endpoint`. |
| `KEYCLOAK_GITHUB_CLIENT_SECRET` | ✓ | GitHub IdP client secret. | Same OAuth App page → “Generate a new client secret”. |
| `KEYCLOAK_SMTP_PASSWORD` | ✓ | SMTP credential for Keycloak email notifications. | Mail provider account password/token. |
| `AZUREAD_KEYCLOAK_CLIENT_SECRET` | ✓ (if AzureAD broker enabled) | Secret from Azure AD app registration used by Keycloak federation. | Azure Portal → App registration → Client secret. |

## OneUptime (Monitoring)
| Variable | Required | Purpose / Usage | Where to obtain |
|----------|----------|-----------------|-----------------|
| `ONEUPTIME_SMTP_USERNAME` | ✓ | SMTP username for OneUptime notifications (reuse the same SMTP credential used by Keycloak/ArgoCD if desired). | Mail provider. |
| `ONEUPTIME_SMTP_PASSWORD` | ✓ | SMTP password/token. | Mail provider. |
| `ONEUPTIME_SLACK_WEBHOOK_CREATE_USER` | Optional | Slack webhook for “create user” automation. | Slack → Incoming Webhooks → Activate → select channel → copy URL. |
| `ONEUPTIME_SLACK_WEBHOOK_DELETE_PROJECT` | Optional | Slack webhook for “delete project”. | Same as above (new webhook per channel/message flavor). |
| `ONEUPTIME_SLACK_WEBHOOK_CREATE_PROJECT` | Optional | Slack webhook for “create project”. | Same as above. |
| `ONEUPTIME_SLACK_WEBHOOK_SUBSCRIPTION_UPDATE` | Optional | Slack webhook for subscription updates. | Same as above. |
| `ONEUPTIME_SLACK_APP_CLIENT_ID` | Optional | Slack app OAuth client (if interactive app features enabled). | Slack App → Basic Information → App Credentials section. |
| `ONEUPTIME_SLACK_APP_CLIENT_SECRET` | Optional | Slack app client secret. | Slack App → Basic Information → App Credentials. |
| `ONEUPTIME_SLACK_APP_SIGNING_SECRET` | Optional | Slack app signing secret. | Slack App → Basic Information → App Credentials. |

## Notes
- Any variable marked “Optional” may be omitted if the corresponding feature is disabled. The renderer will still list it as missing; set it to an empty string if you want to acknowledge that it’s intentionally unused.
- Many services intentionally share the same credential (e.g., SMTP, GitHub App tokens, AWS backup IAM user). Copy the same value into each variable that references that credential so the renderer satisfies every spec without inventing duplicates.
- If `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, and `GITHUB_APP_PRIVATE_KEY` are set, the bootstrap script automatically invokes `platform/scripts/github-app-token.sh` and populates every env listed in `GITHUB_APP_TOKEN_VARS` with a fresh installation token before sealing secrets.
- Keep `.env.local` out of version control (already gitignored). Use 1Password/Bitwarden/Vault to store long-term values and rotate via the bootstrap pipeline.
- Slack tokens/webhooks: create a Slack App inside your workspace, add the necessary scopes (`chat:write` for bot tokens, `incoming-webhook` for webhooks), install it to the target channel, then copy the generated token/URL from the app’s **OAuth & Permissions** page.
- Vault’s initial admin token is copied automatically after the Vault chart syncs (PostSync hook). You no longer need to populate `VAULT_ADMIN_TOKEN` manually.
- The ArgoCD chart now generates the Crossplane provider token automatically after the app syncs (`providerTokenSync` job). No `.env` input is required for `ARGOCD_PROVIDER_TOKEN`.
- After updating `.env.local`, rerun the renderer and then sync the relevant ArgoCD stacks so PushSecrets/ExternalSecrets propagate the changes.
