# Infisical Secrets Management

This directory contains the Sealed Secrets configuration for Infisical bootstrap secrets.

## Files

- `infisical-secrets.secret` - **TEMPLATE** with actual secret values (DO NOT COMMIT)
- `infisical-secrets-sealed.yaml` - Sealed/encrypted version (safe to commit)
- `.gitignore` - Prevents committing unsealed secrets

## Sealing Secrets

When you need to create or update secrets:

1. **Edit the template** with actual values:
   ```bash
   vi infisical-secrets.secret
   ```

2. **Seal the secret** using kubeseal:
   ```bash
   kubeseal --controller-name=sealed-secrets \
     --controller-namespace=sealed-secrets \
     -f infisical-secrets.secret \
     -o yaml > infisical-secrets-sealed.yaml
   ```

3. **Commit only the sealed version**:
   ```bash
   git add infisical-secrets-sealed.yaml
   git commit -m "feat(infisical): update sealed secrets"
   git push
   ```

## Dynamic Certificate Management

**IMPORTANT**: The `DB_ROOT_CERT` field is automatically managed by the `postgres-cert-sync` Job. You should leave it empty in the template.

### How It Works

1. **ArgoCD Sync** triggers the cert-sync-job (sync-wave: -1)
2. **Job extracts** PostgreSQL certificate from platform-db-cluster-0
3. **Job patches** the secret with base64-encoded certificate
4. **ArgoCD ignores** the runtime change (IgnoreExtraneous annotation)

See [../CERTIFICATE-SYNC.md](../CERTIFICATE-SYNC.md) for detailed documentation.

## Secret Structure

The secret contains environment variables for:

- **Core Secrets**: ENCRYPTION_KEY, AUTH_SECRET
- **Database**: DB_CONNECTION_URI, DB_ROOT_CERT (auto-managed), DB_READ_REPLICAS
- **Redis**: Sentinel configuration
- **Platform**: SITE_URL, CORS settings
- **SMTP**: Email configuration
- **Authentication**: GitHub OAuth
- **Integrations**: AWS, GitHub

## Security Notes

- ⚠️ **NEVER** commit `infisical-secrets.secret` with real values
- ✅ Only commit `infisical-secrets-sealed.yaml` (encrypted)
- ✅ DB_ROOT_CERT is dynamically populated (leave empty in template)
- ✅ Template includes ArgoCD annotations for drift prevention

## Troubleshooting

### Secret Not Syncing
Check ArgoCD app status:
```bash
kubectl get application infisical -n argocd
```

### Certificate Not Being Added
Check job logs:
```bash
kubectl logs -n infisical -l job-name=postgres-cert-sync
```

### Sealed Secret Decryption Failed
Verify sealed-secrets controller is running:
```bash
kubectl get pod -n sealed-secrets
```

## References

- [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Certificate Sync Documentation](../CERTIFICATE-SYNC.md)
- [Infisical Environment Variables](https://infisical.com/docs/self-hosting/configuration/envars)
