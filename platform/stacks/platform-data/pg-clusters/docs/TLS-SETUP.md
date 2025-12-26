# PostgreSQL TLS Certificate Management

This chart provides **automatic TLS certificate provisioning** for PostgreSQL clusters using cert-manager. TLS encryption is enabled by default in production environments to secure database connections.

## Overview

When TLS is enabled for a PostgreSQL cluster:

1. **Certificate Resource**: A cert-manager Certificate is automatically created
2. **Secret Creation**: cert-manager provisions a TLS certificate and stores it in a Secret
3. **PostgreSQL Configuration**: The Zalando operator configures PostgreSQL to use the certificate
4. **Automatic Renewal**: Certificates are automatically renewed before expiration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Certificate Flow                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. Helm Deploy                                               │
│     │                                                         │
│     ├──▶ ClusterIssuer (cert-manager CA)                     │
│     │    └──▶ Creates self-signed CA or uses existing CA    │
│     │                                                         │
│     └──▶ Certificate (per cluster)                           │
│          │                                                    │
│          ├──▶ DNS Names:                                     │
│          │    - {name}.{namespace}.svc.cluster.local         │
│          │    - {name}-repl.{namespace}.svc.cluster.local   │
│          │    - {name}-pooler.{namespace}.svc.cluster.local │
│          │                                                    │
│          └──▶ cert-manager provisions certificate            │
│               │                                               │
│               └──▶ Secret: {name}-tls-cert                   │
│                    ├─ tls.crt (certificate)                  │
│                    ├─ tls.key (private key)                  │
│                    └─ ca.crt (CA certificate)                │
│                                                               │
│  2. PostgreSQL CR references Secret                          │
│     │                                                         │
│     └──▶ Zalando Operator configures PostgreSQL              │
│          │                                                    │
│          └──▶ PostgreSQL pods use TLS certificates           │
│                                                               │
│  3. Automatic Renewal                                         │
│     │                                                         │
│     └──▶ cert-manager renews before expiration               │
│          └──▶ PostgreSQL automatically picks up new cert     │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Enable TLS for a Cluster

In your values file (e.g., `values-production.yaml`):

```yaml
pgClusters:
  - name: my-db
    namespace: applications
    teamId: platform

    # ... other configuration ...

    # Enable TLS encryption
    tls:
      enabled: true
```

That's it! The certificate will be automatically provisioned.

## Configuration Options

### Global TLS Configuration

Controls the cert-manager issuer used for all clusters:

```yaml
# Global TLS settings
tls:
  # Create a ClusterIssuer for PostgreSQL certificates
  createIssuer: true

  # Name of the issuer to create/use
  issuerName: platform-postgres-ca

  # Issuer type: selfSigned, ca, acme, vault
  issuerType: selfSigned

  # Sync wave (deploy before clusters)
  issuerSyncWave: "-5"
```

### Per-Cluster TLS Configuration

Fine-tune TLS settings for individual clusters:

```yaml
pgClusters:
  - name: my-db
    tls:
      # Basic settings
      enabled: true

      # Certificate lifetime
      duration: 2160h        # 90 days
      renewBefore: 720h      # Renew 30 days before expiry

      # Organization name in certificate
      organization: "My Organization"

      # Use a different issuer for this cluster
      issuer: custom-issuer
      issuerKind: ClusterIssuer

      # Or use advanced issuer reference
      issuerRef:
        name: vault-issuer
        kind: Issuer
        group: cert-manager.io

      # Additional DNS names (e.g., external load balancer)
      additionalDNSNames:
        - postgres.example.com
        - db.example.com

      # Direct IP access
      ipAddresses:
        - 10.0.1.50
        - 192.168.1.100

      # Private key settings
      privateKey:
        algorithm: RSA      # or ECDSA
        size: 2048          # RSA: 2048, 4096; ECDSA: 256, 384
        encoding: PKCS1
        rotationPolicy: Always

      # Enable CA certificate in secret
      caEnabled: true
      caFileName: ca.crt

      # Custom secret name (default: {name}-tls-cert)
      secretName: custom-tls-secret

      # Certificate file names (defaults shown)
      certificateFile: tls.crt
      privateKeyFile: tls.key
      caFile: ca.crt
```

## Issuer Types

### 1. Self-Signed Issuer (Default)

**Best for**: Internal cluster communication, development, staging

Creates a self-signed CA certificate. Each PostgreSQL cluster gets a certificate signed by this CA.

```yaml
tls:
  issuerType: selfSigned
```

**Pros**:
- No external dependencies
- Works immediately
- Perfect for internal mTLS
- No cost

**Cons**:
- Not trusted by external clients
- Certificate warnings in external tools

### 2. CA Issuer

**Best for**: Enterprise environments with existing PKI

Uses an existing CA certificate from a Secret.

```yaml
tls:
  issuerType: ca
  caSecretName: my-ca-certificate
```

The CA secret must contain:
- `tls.crt`: CA certificate
- `tls.key`: CA private key

**Pros**:
- Integrates with existing PKI
- Centralized trust management
- Enterprise compliance

**Cons**:
- Requires manual CA setup
- CA secret must be managed externally

### 3. ACME Issuer (Let's Encrypt)

**Best for**: PostgreSQL exposed to the internet (rare)

Uses ACME protocol (Let's Encrypt) for publicly trusted certificates.

```yaml
tls:
  issuerType: acme
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecret: postgres-acme-key
    ingressClass: nginx
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Pros**:
- Publicly trusted certificates
- Automatic renewal
- Free

**Cons**:
- Requires public DNS
- Requires HTTP/HTTPS exposure
- Rate limits
- **Not recommended** for database servers

### 4. Vault Issuer

**Best for**: HashiCorp Vault PKI integration

Uses Vault's PKI secrets engine to issue certificates.

```yaml
tls:
  issuerType: vault
  vault:
    server: https://vault.vault.svc.cluster.local:8200
    path: pki/sign/postgres
    role: postgres-issuer
    auth:
      kubernetes:
        role: postgres-issuer
        mountPath: /v1/auth/kubernetes
```

**Pros**:
- Enterprise PKI integration
- Centralized audit logging
- Dynamic secrets
- Fine-grained access control

**Cons**:
- Requires Vault deployment
- Complex setup
- Additional infrastructure

## DNS Names Covered

Each certificate automatically includes DNS names for:

### Master Service
- `{name}.{namespace}.svc.cluster.local` (FQDN)
- `{name}.{namespace}.svc`
- `{name}.{namespace}`
- `{name}`

### Replica Service
- `{name}-repl.{namespace}.svc.cluster.local`
- `{name}-repl.{namespace}.svc`
- `{name}-repl.{namespace}`

### Connection Pooler (if enabled)
- `{name}-pooler.{namespace}.svc.cluster.local`
- `{name}-pooler.{namespace}.svc`
- `{name}-pooler.{namespace}`
- `{name}-pooler-repl.{namespace}.svc.cluster.local` (if replica pooler enabled)

## Connection Examples

### Using psql

```bash
# Connect with SSL verification
psql "postgresql://myuser@my-db.applications.svc.cluster.local:5432/mydb?sslmode=verify-full&sslrootcert=/path/to/ca.crt"

# Connect requiring SSL (no verification)
psql "postgresql://myuser@my-db.applications.svc.cluster.local:5432/mydb?sslmode=require"
```

### Using Connection String

```
postgresql://username:password@my-db.applications.svc.cluster.local:5432/database?sslmode=verify-full&sslrootcert=/etc/ssl/certs/ca.crt
```

### Python (psycopg2)

```python
import psycopg2

conn = psycopg2.connect(
    host="my-db.applications.svc.cluster.local",
    port=5432,
    database="mydb",
    user="myuser",
    password="mypassword",
    sslmode="verify-full",
    sslrootcert="/path/to/ca.crt"
)
```

### Java (JDBC)

```java
String url = "jdbc:postgresql://my-db.applications.svc.cluster.local:5432/mydb"
    + "?ssl=true&sslmode=verify-full&sslrootcert=/path/to/ca.crt";
Connection conn = DriverManager.getConnection(url, "myuser", "mypassword");
```

## Certificate Rotation

Certificates are automatically renewed by cert-manager:

- **Default Duration**: 90 days
- **Default Renewal**: 30 days before expiry
- **Process**: Automatic, no downtime

PostgreSQL automatically picks up renewed certificates without restart.

### Monitoring Certificate Expiry

```bash
# Check certificate in secret
kubectl get secret my-db-tls-cert -n applications -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates

# Check cert-manager certificate status
kubectl get certificate -n applications
kubectl describe certificate my-db-tls -n applications
```

## Troubleshooting

### Certificate Not Created

**Check cert-manager logs**:
```bash
kubectl logs -n cert-manager deployment/cert-manager
```

**Check Certificate resource**:
```bash
kubectl describe certificate my-db-tls -n applications
```

**Common issues**:
- cert-manager not installed
- Issuer not found
- DNS validation failing (ACME)
- Vault auth failing

### PostgreSQL Not Using TLS

**Check PostgreSQL logs**:
```bash
kubectl logs -n applications my-db-0
```

**Verify secret exists**:
```bash
kubectl get secret my-db-tls-cert -n applications
```

**Check secret has correct keys**:
```bash
kubectl get secret my-db-tls-cert -n applications -o jsonpath='{.data}' | jq 'keys'
```

Should show: `["ca.crt", "tls.crt", "tls.key"]`

### Certificate Validation Errors

**Get CA certificate**:
```bash
kubectl get secret my-db-tls-cert -n applications -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```

**Test connection**:
```bash
psql "postgresql://user@my-db.applications.svc:5432/db?sslmode=verify-full&sslrootcert=./ca.crt"
```

## Security Best Practices

1. **Use TLS in Production**: Always enable TLS for production databases
2. **Verify Certificates**: Use `sslmode=verify-full` in connection strings
3. **Rotate Regularly**: Keep default 90-day duration
4. **Monitor Expiry**: Set up alerts for certificate expiration
5. **Protect CA**: Ensure CA secrets have restricted RBAC
6. **Use Strong Keys**: Use RSA 2048-bit or ECDSA 256-bit minimum
7. **Network Policies**: Combine TLS with network policies for defense in depth

## Examples

### Production Setup (Self-Signed CA)

```yaml
# Global configuration
tls:
  createIssuer: true
  issuerName: platform-postgres-ca
  issuerType: selfSigned

# Per-cluster
pgClusters:
  - name: production-db
    namespace: applications
    tls:
      enabled: true
      duration: 2160h      # 90 days
      renewBefore: 720h    # 30 days
      organization: "My Company"
```

### Enterprise Setup (Vault PKI)

```yaml
# Global configuration
tls:
  createIssuer: true
  issuerName: vault-postgres-issuer
  issuerType: vault
  vault:
    server: https://vault.vault.svc:8200
    path: pki/sign/postgres
    role: postgres-issuer
    auth:
      kubernetes:
        role: postgres-issuer

# Per-cluster
pgClusters:
  - name: enterprise-db
    namespace: applications
    tls:
      enabled: true
      duration: 720h       # 30 days (shorter for compliance)
      renewBefore: 168h    # 7 days
```

### Multi-Region Setup (External Access)

```yaml
pgClusters:
  - name: global-db
    namespace: applications
    tls:
      enabled: true
      # Add external DNS names
      additionalDNSNames:
        - postgres.us-east.example.com
        - postgres.eu-west.example.com
        - db.example.com
      # Add load balancer IPs
      ipAddresses:
        - 203.0.113.10  # US Load Balancer
        - 198.51.100.20 # EU Load Balancer
```

## Prerequisites

- **cert-manager** must be installed in the cluster
- **ClusterIssuer** or **Issuer** must exist (or set `createIssuer: true`)
- Sufficient RBAC permissions for cert-manager to create secrets

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Zalando PostgreSQL Operator TLS](https://postgres-operator.readthedocs.io/en/latest/user/#tls-configuration)
- [PostgreSQL SSL Documentation](https://www.postgresql.org/docs/current/ssl-tcp.html)
