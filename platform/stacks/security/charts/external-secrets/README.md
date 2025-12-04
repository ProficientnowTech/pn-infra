# External Secrets Operator

Kubernetes Operator that synchronizes secrets from external secret management systems (Vault, AWS Secrets Manager, Google Secret Manager, etc.) into Kubernetes secrets.

## Overview

This chart deploys the External Secrets Operator (ESO) configured to work with HashiCorp Vault as the secret backend, enabling:
- **Centralized secret management** in Vault
- **Automatic secret synchronization** to Kubernetes
- **Secret rotation** without pod restarts
- **Multi-namespace** secret distribution
- **Audit trail** for secret access

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│         External Secrets Operator (2 replicas)              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Controllers:                                           │ │
│  │  ├── ClusterSecretStore Controller                     │ │
│  │  ├── ExternalSecret Controller                         │ │
│  │  ├── Webhook (validation/mutation)                     │ │
│  │  └── Cert Controller                                   │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────┬────────────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
   ┌────▼────┐               ┌──────▼──────┐
   │  Vault  │               │  Kubernetes │
   │ Backend │───────────────│   Secrets   │
   └─────────┘    Sync       └─────────────┘
```

## Prerequisites

1. **Vault** must be installed and unsealed:
   ```bash
   kubectl get pods -n vault
   ```

2. **Vault Kubernetes Auth** must be configured:
   ```bash
   kubectl exec -it vault-0 -n vault -- vault auth list
   # Should show 'kubernetes/' in the list
   ```

## Installation

### Step 1: Install External Secrets Operator

```bash
# Add dependencies
helm dependency update

# Install
helm install external-secrets . -n external-secrets --create-namespace

# Or upgrade
helm upgrade --install external-secrets . -n external-secrets
```

### Step 2: Configure Vault Authentication

The operator needs permission to authenticate with Vault:

```bash
# Create Vault policy for ESO
kubectl exec -it vault-0 -n vault -- vault policy write external-secrets -<<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["list"]
}
EOF

# Create Vault role for ESO
kubectl exec -it vault-0 -n vault -- vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets-vault \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=24h
```

### Step 3: Verify Installation

```bash
# Check ESO pods
kubectl get pods -n external-secrets

# Check ClusterSecretStore
kubectl get clustersecretstore

# Should show:
# NAME            AGE   STATUS   READY
# vault-backend   1m    Valid    True
```

## Usage

### Creating Secrets in Vault

Store secrets in Vault that you want to sync:

```bash
# Example: Database credentials
kubectl exec -it vault-0 -n vault -- vault kv put secret/database/my-app \
  username=dbuser \
  password=supersecret

# Example: API keys
kubectl exec -it vault-0 -n vault -- vault kv put secret/api/service-x \
  api-key=abc123 \
  api-secret=xyz789

# Example: OIDC credentials
kubectl exec -it vault-0 -n vault -- vault kv put secret/keycloak/clients/my-app \
  client-id=my-app \
  client-secret=my-secret
```

### Sync All Secret Data

Create an `ExternalSecret` to sync all data from a Vault path:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: my-app
spec:
  refreshInterval: 1h  # Check for updates every hour
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: database-secret  # Kubernetes secret name
    creationPolicy: Owner
  dataFrom:
  - extract:
      key: database/my-app  # Vault path: secret/data/database/my-app
```

### Sync Specific Keys

Create an `ExternalSecret` to sync specific keys:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-keys
  namespace: my-app
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: api-secret
    creationPolicy: Owner
  data:
  - secretKey: API_KEY  # Key in Kubernetes secret
    remoteRef:
      key: api/service-x  # Vault path
      property: api-key   # Property in Vault secret
  - secretKey: API_SECRET
    remoteRef:
      key: api/service-x
      property: api-secret
```

### Template Secrets

Use templates to transform secret data:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: oidc-config
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: oidc-config-secret
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        config.yaml: |
          oidc:
            client_id: {{ .clientId }}
            client_secret: {{ .clientSecret }}
            issuer_url: https://keycloak.pnats.cloud/realms/proficientnow
            redirect_url: https://my-app.pnats.cloud/callback
  data:
  - secretKey: clientId
    remoteRef:
      key: keycloak/clients/my-app
      property: client-id
  - secretKey: clientSecret
    remoteRef:
      key: keycloak/clients/my-app
      property: client-secret
```

### Namespace-Specific SecretStore

For namespace-scoped secrets:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-store
  namespace: my-app
spec:
  provider:
    vault:
      server: "http://vault-active.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "my-app-role"
          serviceAccountRef:
            name: my-app-sa
```

## Common Use Cases

### 1. Database Credentials

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-creds
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: postgres-secret
    template:
      type: Opaque
      data:
        POSTGRES_USER: "{{ .username }}"
        POSTGRES_PASSWORD: "{{ .password }}"
        POSTGRES_HOST: "postgres.my-app.svc.cluster.local"
        POSTGRES_DB: "mydb"
        DATABASE_URL: "postgresql://{{ .username }}:{{ .password }}@postgres.my-app.svc.cluster.local:5432/mydb"
  data:
  - secretKey: username
    remoteRef:
      key: database/my-app
      property: username
  - secretKey: password
    remoteRef:
      key: database/my-app
      property: password
```

Usage in deployment:
```yaml
envFrom:
- secretRef:
    name: postgres-secret
```

### 2. TLS Certificates

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: tls-cert
  namespace: my-app
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: tls-secret
    template:
      type: kubernetes.io/tls
      data:
        tls.crt: "{{ .cert }}"
        tls.key: "{{ .key }}"
  data:
  - secretKey: cert
    remoteRef:
      key: tls/my-app
      property: certificate
  - secretKey: key
    remoteRef:
      key: tls/my-app
      property: private-key
```

### 3. Docker Registry Credentials

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: docker-registry
  namespace: my-app
spec:
  refreshInterval: 6h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: docker-registry-secret
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: '{"auths":{"{{ .server }}":{"username":"{{ .username }}","password":"{{ .password }}","auth":"{{ printf "%s:%s" .username .password | b64enc }}"}}}'
  data:
  - secretKey: server
    remoteRef:
      key: docker/registry
      property: server
  - secretKey: username
    remoteRef:
      key: docker/registry
      property: username
  - secretKey: password
    remoteRef:
      key: docker/registry
      property: password
```

## Secret Rotation

ESO automatically refreshes secrets based on `refreshInterval`:

- **Immediate rotation**: Set `refreshInterval: 5m` for critical secrets
- **Hourly rotation**: Set `refreshInterval: 1h` for normal secrets
- **Daily rotation**: Set `refreshInterval: 24h` for stable secrets

**Note**: Applications must be configured to reload secrets on change or restart pods:

```yaml
# Option 1: Use Reloader to auto-restart on secret change
apiVersion: v1
kind: ConfigMap
metadata:
  annotations:
    reloader.stakater.com/match: "true"

# Option 2: Mount secrets as volumes (auto-updated)
volumes:
- name: secret-volume
  secret:
    secretName: my-secret
```

## Monitoring

### Check ExternalSecret Status

```bash
# List all ExternalSecrets
kubectl get externalsecrets --all-namespaces

# Check specific ExternalSecret
kubectl describe externalsecret my-secret -n my-app

# Should show:
# Status:
#   Conditions:
#     Type:    Ready
#     Status:  True
#     Reason:  SecretSynced
```

### Metrics

ESO exposes Prometheus metrics on port 8080:

```bash
# Check metrics
kubectl port-forward -n external-secrets svc/external-secrets 8080:8080
curl http://localhost:8080/metrics
```

Key metrics:
- `externalsecret_sync_calls_total` - Total sync attempts
- `externalsecret_sync_calls_error` - Failed syncs
- `externalsecret_status_condition` - Current status

## Troubleshooting

### ExternalSecret Not Syncing

```bash
# Check status
kubectl describe externalsecret my-secret -n my-app

# Common issues:
# 1. Vault path doesn't exist
# 2. Vault authentication failed
# 3. Incorrect secret key mapping
```

### Vault Authentication Failed

```bash
# Check ServiceAccount
kubectl get sa external-secrets-vault -n external-secrets

# Check Vault role
kubectl exec -it vault-0 -n vault -- vault read auth/kubernetes/role/external-secrets

# Test authentication
kubectl exec -it vault-0 -n vault -- vault write auth/kubernetes/login \
  role=external-secrets \
  jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

### Secret Not Created

```bash
# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Check webhook
kubectl logs -n external-secrets -l app.kubernetes.io/component=webhook
```

### Debugging

Enable debug logging:

```yaml
# values.yaml
external-secrets:
  extraArgs:
    - --log-level=debug
```

## Best Practices

1. **Use ClusterSecretStore** for shared Vault configuration
2. **Set appropriate refreshInterval** based on security requirements
3. **Use templates** to transform secrets into application-specific formats
4. **Monitor sync status** with Prometheus metrics
5. **Implement proper RBAC** for Vault access
6. **Rotate secrets regularly** in Vault
7. **Test secret rotation** before production
8. **Use namespaced SecretStore** for tenant isolation

## Security Considerations

1. **Vault Authentication**: ESO uses Kubernetes ServiceAccount tokens
2. **RBAC**: Limit which namespaces can create ExternalSecrets
3. **Vault Policies**: Follow least-privilege principle
4. **Secret Encryption**: Kubernetes secrets are encrypted at rest
5. **Audit Logging**: Enable Vault audit logs for compliance

## Migration from Sealed Secrets

To migrate from Sealed Secrets to ESO:

1. Store secrets in Vault:
   ```bash
   kubectl get secret my-sealed-secret -o json | \
     jq -r '.data | to_entries[] | "\(.key)=\(.value | @base64d)"' | \
     while IFS='=' read key value; do
       kubectl exec vault-0 -n vault -- vault kv put secret/my-app/$key value="$value"
     done
   ```

2. Create ExternalSecret pointing to Vault path

3. Verify new secret is created and working

4. Delete sealed secret

## Resources

- [External Secrets Operator Documentation](https://external-secrets.io)
- [Vault Integration Guide](https://external-secrets.io/latest/provider/hashicorp-vault/)
- [API Reference](https://external-secrets.io/latest/api/externalsecret/)

## Support

For issues or questions:
- Platform Team: snoorullah@proficientnowtech.com
- GitHub Issues: https://github.com/external-secrets/external-secrets/issues
