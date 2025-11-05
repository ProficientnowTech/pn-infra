# Infisical Secrets Management with Sealed Secrets

This directory contains templates and instructions for managing Infisical bootstrap secrets using Bitnami Sealed Secrets.

## Prerequisites

1. **Sealed Secrets Controller** installed in `sealed-secrets` namespace
2. **kubeseal CLI** installed locally
3. **kubectl** configured to access your cluster

## Quick Reference

### Check Sealed Secrets Controller

```bash
# Verify controller is running
kubectl get pods -n sealed-secrets

# Expected output:
# NAME                                         READY   STATUS    RESTARTS   AGE
# sealed-secrets-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          Xd
```

### Verify kubeseal is installed

```bash
kubeseal --version
# Should show: kubeseal version: vX.XX.X
```

---

## Step-by-Step: Create and Seal Infisical Secrets

### Step 1: Generate Required Secrets

Infisical requires two cryptographic secrets. Generate them:

```bash
# Generate ENCRYPTION_KEY (16-byte hex)
openssl rand -hex 16

# Generate AUTH_SECRET (32-byte base64)
openssl rand -base64 32
```

**Save these values securely** - you'll need them in Step 2.

---

### Step 2: Fill in the Template

1. **Copy the template**:
   ```bash
   cp infisical-secrets.yaml infisical-secrets-filled.yaml
   ```

2. **Edit `infisical-secrets-filled.yaml`** and replace ALL `PLACEHOLDER_` values:

   **Required (minimum for Infisical to start)**:
   - `ENCRYPTION_KEY` - from Step 1
   - `AUTH_SECRET` - from Step 1
   - `SITE_URL` - e.g., `https://infisical.pnats.cloud`
   - `SMTP_*` - Your SMTP server details

   **Recommended (for production)**:
   - `CLIENT_ID_GITHUB_LOGIN` + `CLIENT_SECRET_GITHUB_LOGIN` - GitHub SSO
   - `SAML_ORG_SLUG` - Your organization slug

   **Optional (configure as needed)**:
   - AWS integration credentials
   - GitHub App credentials
   - Other OAuth providers

3. **Review database and Redis URIs** (already pre-filled with correct values):
   - `DB_CONNECTION_URI` - Points to platform-db cluster
   - `DB_READ_REPLICAS` - Points to platform-db replica service
   - `REDIS_SENTINEL_HOSTS` - Points to platform-kv sentinel
   - `REDIS_SENTINEL_MASTER_NAME` - Configured as `platform-kv-master`

---

### Step 3: Seal the Secret

Once you've filled in all values, seal the secret:

```bash
# Seal the secret using your cluster's public key
kubeseal \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format yaml \
  < infisical-secrets-filled.yaml \
  > infisical-secrets-sealed.yaml
```

**What just happened?**
- kubeseal fetched the public key from your cluster's Sealed Secrets controller
- It encrypted your secret using that public key
- Only the controller (with the private key) can decrypt it
- The sealed secret is **safe to commit to Git**

---

### Step 4: Verify the Sealed Secret

Check the sealed secret was created correctly:

```bash
# View the sealed secret (it's encrypted, safe to see)
cat infisical-secrets-sealed.yaml
```

You should see:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: infisical-secrets
  namespace: infisical
spec:
  encryptedData:
    ENCRYPTION_KEY: AgB... (long encrypted string)
    AUTH_SECRET: AgC... (long encrypted string)
    ...
```

---

### Step 5: Deploy the Sealed Secret

Apply the sealed secret to your cluster:

```bash
# Create namespace if it doesn't exist
kubectl create namespace infisical --dry-run=client -o yaml | kubectl apply -f -

# Apply the sealed secret
kubectl apply -f infisical-secrets-sealed.yaml
```

**What happens next?**
1. Kubernetes creates the `SealedSecret` resource
2. Sealed Secrets controller watches for `SealedSecret` resources
3. Controller decrypts it using its private key
4. Controller creates a regular Kubernetes `Secret` named `infisical-secrets`
5. Infisical pods can now mount this secret

---

### Step 6: Verify Secret Creation

Check that the regular Secret was created:

```bash
# List secrets in infisical namespace
kubectl get secret -n infisical infisical-secrets

# Expected output:
# NAME                 TYPE     DATA   AGE
# infisical-secrets    Opaque   XX     Xs

# Verify it has all the keys (don't decode values in production!)
kubectl get secret infisical-secrets -n infisical -o jsonpath='{.data}' | jq 'keys'
```

---

### Step 7: Commit to Git (ONLY the Sealed Version!)

```bash
# Add ONLY the sealed secret to Git
git add infisical-secrets-sealed.yaml

# Commit it
git commit -m "feat(infisical): add sealed bootstrap secrets"

# Push to repository
git push
```

**CRITICAL**: 
- ✅ **DO commit**: `infisical-secrets-sealed.yaml` (encrypted)
- ❌ **NEVER commit**: `infisical-secrets-filled.yaml` (contains raw secrets!)
- ❌ **NEVER commit**: `infisical-secrets.yaml` (template is OK, but don't modify it with real values)

---

## Using the Secret in Infisical Deployment

In your Infisical Helm values or deployment manifest, reference the secret:

```yaml
# values.yaml or deployment
envFrom:
- secretRef:
    name: infisical-secrets  # The decrypted secret created by controller
```

Or for individual env vars:

```yaml
env:
- name: ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: infisical-secrets
      key: ENCRYPTION_KEY
- name: AUTH_SECRET
  valueFrom:
    secretKeyRef:
      name: infisical-secrets
      key: AUTH_SECRET
# ... etc
```

---

## Updating Secrets

To update a secret value:

1. **Edit your filled template**:
   ```bash
   vim infisical-secrets-filled.yaml
   # Update the value you want to change
   ```

2. **Re-seal it**:
   ```bash
   kubeseal \
     --controller-name=sealed-secrets \
     --controller-namespace=sealed-secrets \
     --format yaml \
     < infisical-secrets-filled.yaml \
     > infisical-secrets-sealed.yaml
   ```

3. **Apply the updated sealed secret**:
   ```bash
   kubectl apply -f infisical-secrets-sealed.yaml
   ```

4. **Restart Infisical pods** to pick up new values:
   ```bash
   kubectl rollout restart deployment infisical -n infisical
   ```

5. **Commit the new sealed secret**:
   ```bash
   git add infisical-secrets-sealed.yaml
   git commit -m "chore(infisical): update secrets"
   git push
   ```

---

## Troubleshooting

### Sealed Secret not decrypting

**Check controller logs**:
```bash
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```

**Common issues**:
- Wrong controller name/namespace in kubeseal command
- Sealed secret created with different cluster's public key
- Controller doesn't have permission to create secrets

### Secret not appearing

**Check SealedSecret resource**:
```bash
kubectl get sealedsecret -n infisical infisical-secrets -o yaml
```

Look for `status` field for errors.

### Wrong values in secret

**Decode and check** (be careful, this exposes secrets!):
```bash
kubectl get secret infisical-secrets -n infisical -o jsonpath='{.data.ENCRYPTION_KEY}' | base64 -d
```

If wrong, re-seal with correct values (see "Updating Secrets" above).

---

## Security Best Practices

1. ✅ **DO**: Keep `infisical-secrets-filled.yaml` in a secure password manager
2. ✅ **DO**: Add `*-filled.yaml` to `.gitignore`
3. ✅ **DO**: Rotate secrets periodically
4. ✅ **DO**: Use RBAC to limit who can read Secrets in the cluster
5. ❌ **DON'T**: Share filled templates via Slack/email
6. ❌ **DON'T**: Store filled templates in Git (even private repos)
7. ❌ **DON'T**: Use the same ENCRYPTION_KEY/AUTH_SECRET across environments

---

## Database & Redis Access

### PostgreSQL Connection

**Internal DNS** (recommended for in-cluster):
```
platform-db-cluster.platform-db-pg.svc.cluster.local:5432
```

**External DNS** (if configured with pnats.cloud):
```
platform-db.pnats.cloud:5432
```

**Read Replica**:
```
platform-db-cluster-repl.platform-db-pg.svc.cluster.local:5432
```

### Redis Connection

**Sentinel Configuration** (HA, recommended):
```
REDIS_SENTINEL_HOSTS: platform-kv-sentinel-sentinel.platform-kv-redis-cluster.svc.cluster.local:26379
REDIS_SENTINEL_MASTER_NAME: platform-kv-master
```

**Direct Connection** (fallback):
```
REDIS_URL: redis://platform-kv.platform-kv-redis-cluster.svc.cluster.local:6379/0
```

**Note**: Redis does NOT have external access by default. If Infisical runs outside the cluster, you'll need to:
1. Add LoadBalancer service for Redis
2. Configure external-dns for Redis
3. Update REDIS_SENTINEL_HOSTS with external domain

---

## Integration with External Secrets Operator

Once Infisical is running, you can configure External Secrets Operator (ESO) to sync secrets FROM Infisical INTO Kubernetes:

```yaml
# Example: ESO SecretStore pointing to Infisical
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: infisical-backend
  namespace: default
spec:
  provider:
    infisical:
      auth:
        universalAuth:
          credentialsRef:
            clientId:
              name: infisical-auth  # Another sealed secret with Infisical Machine Identity credentials
              key: clientId
            clientSecret:
              name: infisical-auth
              key: clientSecret
      hostAPI: https://infisical.pnats.cloud
```

This creates a **tiered secret architecture**:
- **Tier 1 (Bootstrap)**: Sealed Secrets → Infisical credentials
- **Tier 2 (Infrastructure)**: Infisical → ESO authentication
- **Tier 3 (Applications)**: ESO → Application secrets

---

## Additional Resources

- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [Infisical Environment Variables](https://infisical.com/docs/self-hosting/configuration/envars)
- [External Secrets Operator](https://external-secrets.io/)
