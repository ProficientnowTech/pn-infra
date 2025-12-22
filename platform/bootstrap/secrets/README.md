# Bootstrap Secret Specs

> **Reminder:** This bootstrap layer now sits on top of the API-driven infrastructure workflow. Run `./api/bin/api generate env …` before rendering secrets to ensure namespaces and cluster configuration files are present.

Secrets are defined declaratively under `platform/bootstrap/secrets/specs/`.
Each file contains a single `SecretSpec` document that drives the bootstrap
pipeline:

```yaml
apiVersion: platform.pnats.cloud/v1alpha1
kind: SecretSpec
metadata:
  name: backstage-secrets
spec:
  namespace: backstage
  type: Opaque
  vault:
    path: secret/applications/developer-platform/backstage/app
  data:
    keycloak-client-secret:
      generate:
        length: 48
    github-token:
      env: BACKSTAGE_GITHUB_TOKEN
      cache: false
```

Supported data sources:

| Field      | Description                                                                  |
|------------|------------------------------------------------------------------------------|
| `env`      | Read value from environment variable (fails if unset unless `cache: true`).  |
| `literal`  | Hard-coded value.                                                             |
| `generate` | Random string generator (`length`, `alphabet` = `alnum|hex|url|base64`).      |
| `hash`     | Hash method (`bcrypt`, `sha512`, `apr1`).                                     |
| `format`   | Template applied after hashing; `{value}` is replaced with the computed data. |
| `cache`    | Whether to persist the generated value in `.generated/state`.                |

`metadata.labels` and `metadata.annotations` can be provided if the resulting Secret
needs additional metadata (e.g., `argocd.argoproj.io/secret-type: repository`).

`vault.path` determines where the `PushSecret` writes inside Vault. Paths are always
relative to the mount defined in the ClusterSecretStore (`secret`), so use values such
as `applications/developer-platform/harbor/core` rather than `secret/data/...`.

### Rendering & Applying

`platform/bootstrap/scripts/render-secrets.sh --apply` will:

1. Read every spec in `specs/`.
2. Generate deterministic values (cached in `.generated/state`).
3. Write SealedSecret manifests under `platform/bootstrap/secrets/chart/files/manifests/sealed/`.
4. Write matching PushSecret manifests under `platform/bootstrap/secrets/chart/files/manifests/push/`.
5. Deploy both via `helm upgrade --install` against `platform/bootstrap/secrets/chart` (release `bootstrap-secrets` in namespace `argocd` by default).

The rendered manifests are gitignored. Customize the Helm release/namespace with `BOOTSTRAP_SECRETS_RELEASE` and `BOOTSTRAP_SECRETS_NAMESPACE` if needed.

All generated values are cached under `.generated/state/`. Delete the corresponding
`<namespace>-<name>.json` (or pass `--force`) to re-roll credentials.

### Environment Variables

The renderer automatically loads key/value pairs from `platform/bootstrap/secrets/.env.local`
if the file exists. Create it by copying `.env.example` in the same directory and fill in the
values (tokens, passwords, SSH keys, etc.). The file is gitignored so it never leaves your
workstation.

All required `env:` entries across every `SecretSpec` are validated up-front. If anything is
missing the script prints the full list, allowing you to update `.env.local` once instead of
discovering secrets piecemeal while it runs.

If you define `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, and `GITHUB_APP_PRIVATE_KEY`,
the renderer automatically calls `platform/scripts/github-app-token.sh` and injects a fresh
GitHub App installation token into every env listed in `GITHUB_APP_TOKEN_VARS` (defaults to
`BACKSTAGE_GITHUB_TOKEN`) before rendering SealedSecrets.

To force regeneration of cached random values, delete the relevant file under
`.generated/state/` or run the script with `--force`.
