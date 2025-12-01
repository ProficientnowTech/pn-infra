# Secret Inventory (Bootstrap → Vault → ExternalSecret)

All sensitive configuration now lives under `platform/bootstrap/secrets/specs/` as `SecretSpec` files.
The bootstrap renderer (`platform/bootstrap/scripts/render-secrets.sh --apply`) performs three steps for
_every_ spec:

1. Create/refresh a `SealedSecret` in the target namespace so workloads can start immediately.
2. Generate a matching `PushSecret` that writes the data into Vault at `applications/<stack>/<app>/<scope>`.
3. External Secrets Operator later republishes the Vault data back into Kubernetes Secrets owned by each chart.

**Conventions**
- `vault.path` values are relative (no `secret/data` prefix); the ClusterSecretStore already knows the `secret` mount.
- OIDC client credentials are centralized under `applications/security/keycloak/clients/<clientName>` so every
  workload and Keycloak itself consume the same value.
- Environment variables listed below **must** be present before running the renderer; everything else is randomly generated
  and cached under `platform/bootstrap/.generated/state/`.
- Place local overrides in `platform/bootstrap/secrets/.env.local` (copy from `.env.example`). The renderer loads that file
  automatically and will list any missing variables before sealing secrets.
- A full list of required/optional environment variables plus acquisition guidance lives in
  [`docs/platform/security/bootstrap-secrets-env.md`](bootstrap-secrets-env.md). Guidance for using a single GitHub App across the platform
  is in [`docs/platform/security/github-app-integration.md`](github-app-integration.md).

## 1. Infrastructure Stack
| App | SecretSpec | Vault Path | Inputs / Notes |
|-----|------------|------------|----------------|
| cert-manager | `cloudflare-cert-manager.yaml` | `applications/infrastructure/cloudflare` | `CLOUDFLARE_API_TOKEN` (DNS01 token) |
| external-dns | `cloudflare-external-dns.yaml` | `applications/infrastructure/cloudflare` | Same token as cert-manager. |
| ArgoCD repo credentials | `argocd-repo.yaml` | `applications/infrastructure/argocd/repo` | `ARGOCD_REPO_SSH_PRIVATE_KEY`; auto-labels the secret as `repository`. |
| ArgoCD notifications | `argocd-notifications.yaml` | `applications/infrastructure/argocd/notifications` | `ARGOCD_NOTIFICATIONS_SLACK_TOKEN`, `ARGOCD_NOTIFICATIONS_EMAIL_PASSWORD`; SMTP username defaults to `platform-admin@pnats.cloud`. |

## 2. Storage & Platform Data Stack
| App | SecretSpec | Vault Path | Inputs / Notes |
|-----|------------|------------|----------------|
| Harbor core | `harbor-core.yaml` | `applications/developer-platform/harbor/core` | Generates registry admin/db/robot secrets. OIDC fields now come from Keycloak client spec. |
| Harbor S3 backend | _automated via `harborObjectStore`_ | `applications/developer-platform/harbor/s3` | Storage stack (`ceph-cluster` chart) now creates a CephObjectStoreUser + ObjectBucketClaim, then a PushSecret syncs the generated credentials into Vault. No `.env` values required. |
| Verdaccio registry | `verdaccio.yaml` | `applications/developer-platform/verdaccio/app` | Generates oauth cookie secret + robot creds; OIDC client pulled from Keycloak path. |
| PostgreSQL backups (Zalando) | `postgres-backup.yaml` | `applications/storage/postgres/backups` | S3 credentials for WAL backups. |
| ClusterAPI SSH | `clusterapi-ssh.yaml` | `applications/developer-platform/clusterapi/ssh` | `CLUSTERAPI_SSH_PRIVATE_KEY`. |

## 3. Security Stack
### Crossplane Provider Tokens
| Usage | Source | Location | Notes |
|-------|--------|----------|-------|
| Vault provider admin token | Vault chart PostSync hook (`rootTokenSync`) | Secret `vault-admin-token` in `crossplane-system` | Automatically copied from the `vault-init` secret once Vault finishes syncing — no `.env` entry needed. |
| ArgoCD provider token | ArgoCD chart PostSync hook (`providerTokenSync`) | Secret `argocd-admin-token` in `crossplane-system` | Job logs into ArgoCD using the initial admin password, mints a token via CLI, and writes it to the secret automatically. |

### Keycloak Platform Secrets
| Purpose | SecretSpec | Vault Path | Inputs |
|---------|-----------|------------|--------|
| Admin credentials | `keycloak-admin.yaml` | `applications/security/keycloak/admin` | `KEYCLOAK_ADMIN_PASSWORD` (optional, generated if absent). |
| PostgreSQL backend | `keycloak-postgres.yaml` | `applications/security/keycloak/postgres` | Random DB + superuser passwords. |
| SMTP relay | `keycloak-smtp.yaml` | `applications/security/keycloak/smtp` | `KEYCLOAK_SMTP_USERNAME`, `KEYCLOAK_SMTP_PASSWORD`. |
| AzureAD broker | `keycloak-azuread.yaml` | `applications/security/keycloak/azuread` | `AZUREAD_KEYCLOAK_CLIENT_SECRET`. |
| GitHub IdP | `keycloak-github.yaml` | `applications/security/keycloak/github` | `KEYCLOAK_GITHUB_CLIENT_ID/SECRET`. |

### Keycloak OIDC Clients (shared across apps)
_All client specs live in `platform/bootstrap/secrets/specs/keycloak-client-*.yaml` and write to `applications/security/keycloak/clients/<client>`._

| Client / App | SecretSpec |
|--------------|------------|
| ArgoCD | `keycloak-client-argocd.yaml` |
| Grafana | `keycloak-client-grafana.yaml` |
| Backstage | `keycloak-client-backstage.yaml` |
| OneUptime | `keycloak-client-oneuptime.yaml` |
| Harbor | `keycloak-client-harbor.yaml` |
| Verdaccio (oauth2-proxy) | `keycloak-client-verdaccio.yaml` |
| Kargo | `keycloak-client-kargo.yaml` |
| Tekton Dashboard | `keycloak-client-tekton.yaml` |
| Argo Rollouts Dashboard | `keycloak-client-argo-rollouts.yaml` |

Each spec stores `client-id` (literal) and `client-secret` (generated). Workloads reference the same vault path while the Keycloak
Crossplane client CRs `lookup` the Kubernetes secret to configure Keycloak.

## 4. Monitoring Stack
| App | SecretSpec | Vault Path | Inputs / Notes |
|-----|------------|------------|----------------|
| Grafana admin | `grafana-admin.yaml` | `applications/monitoring/grafana/admin` | Username defaults to `admin`; password generated. Client secret pulled from Keycloak clients/grafana. |
| OneUptime core | `oneuptime-core.yaml` | `applications/monitoring/oneuptime/core` | Generates `oneuptimeSecret` + `encryptionSecret`. |
| OneUptime SMTP | `oneuptime-smtp.yaml` | `applications/monitoring/oneuptime/smtp` | `ONEUPTIME_SMTP_USERNAME`, `ONEUPTIME_SMTP_PASSWORD`; host/from literals may be edited if needed. |
| OneUptime Slack webhooks | `oneuptime-slack.yaml` | `applications/monitoring/oneuptime/slack` | `ONEUPTIME_SLACK_WEBHOOK_CREATE_USER`, `..._DELETE_PROJECT`, `..._CREATE_PROJECT`, `..._SUBSCRIPTION_UPDATE`. |
| OneUptime Slack app | `oneuptime-slack-app.yaml` | `applications/monitoring/oneuptime/slack-app` | `ONEUPTIME_SLACK_APP_CLIENT_ID/SECRET/SIGNING_SECRET`. |

## 5. Developer Platform Stack
| App | SecretSpec | Vault Path | Inputs / Notes |
|-----|------------|------------|----------------|
| Backstage | `backstage.yaml` | `applications/developer-platform/backstage/app` | `BACKSTAGE_GITHUB_TOKEN`. Keycloak client secret comes from `keycloak/clients/backstage`. |
| Harbor (non-OIDC) | `harbor-core.yaml` | See Section 2 | Randomized/given above. |
| Verdaccio (non-OIDC) | `verdaccio.yaml` | `applications/developer-platform/verdaccio/app` | Generates oauth cookie + robot creds. |
| ClusterAPI SSH | `clusterapi-ssh.yaml` | `applications/developer-platform/clusterapi/ssh` | `CLUSTERAPI_SSH_PRIVATE_KEY`. |

## 6. Development Workloads Stack
| App | SecretSpec | Vault Path | Inputs / Notes |
|-----|------------|------------|----------------|
| Kargo admin | `kargo-admin.yaml` | `applications/development-workloads/kargo/admin` | Generates bcrypt admin hash + signing key. |
| Kargo bootstrap users | `kargo-users.yaml` | `applications/development-workloads/kargo/users` | Email/password pairs for platform-admin/devops/readonly users (edit literals if desired). |

## 7. Shared / Backup Secrets
| App | SecretSpec | Vault Path | Notes |
|-----|------------|------------|-------|
| PostgreSQL backup S3 | `postgres-backup.yaml` | `applications/storage/postgres/backups` | S3 credentials for WAL backups. |

## Operational Notes
- Run `platform/bootstrap/scripts/render-secrets.sh --apply` after installing the SealedSecrets controller. Missing env vars abort the run (unless `spec.optional: true`).
- All vault paths listed above are the keys you must use in `ExternalSecret` definitions (no `secret/data/` prefix). PushSecrets automatically publish to those paths once Vault is online.
- Keycloak client secrets are now single-sourced under `applications/security/keycloak/clients/*`. Consumer charts (Harbor, Backstage, Verdaccio, etc.)
  request `client-id`/`client-secret` from that path, while the Keycloak Crossplane client CRs `lookup` the same Kubernetes secret during template rendering.
- To rotate a secret, set the appropriate environment variable (if not randomly generated) and re-run the renderer with `--force`; otherwise delete the cached state file for that spec,
  run the renderer, then `argocd app sync security-crossplane` and the dependent stack.
