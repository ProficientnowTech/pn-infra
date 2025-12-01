# PostgreSQL External Access - Complete Solution Summary

## What Was Implemented

I've designed and implemented a comprehensive solution for external PostgreSQL database access that integrates with your existing infrastructure (MetalLB, external-dns, cert-manager, Let's Encrypt).

## Architecture Overview

### Three Connection Types for Optimal Performance

```
Developer/Application
       |
       ├─── TRANSACTIONS (Pooled - High Scalability)
       │    ├─ Write: {cluster}-write.pnats.cloud → Master + PgBouncer
       │    └─ Read:  {cluster}-read.pnats.cloud  → Replicas + PgBouncer
       │
       └─── MIGRATIONS (Direct - Full Features)
            └─ Admin: {cluster}-admin.pnats.cloud → Master Direct (No Pool)
```

### Why This Architecture?

1. **Transaction Mode Pooling = Maximum Scalability**
   - PgBouncer in transaction mode provides highest connection scalability
   - 1000s of client connections → ~100 backend PostgreSQL connections
   - Perfect for applications with many short transactions
   - Limitations: No prepared statements, advisory locks, or session features

2. **Direct Connection = Full PostgreSQL Features**
   - Bypass pooler for migrations and admin tasks
   - Supports ALL PostgreSQL features:
     - Prepared statements (required by many ORMs)
     - Advisory locks
     - `LISTEN/NOTIFY`
     - Temporary tables
     - `VACUUM`, `ANALYZE`, `REINDEX`
     - Schema migrations (Flyway, Liquibase, Alembic)
   - Each connection = 1 backend process (resource intensive)

3. **Read/Write Split = Load Distribution**
   - Write endpoint → Master (authoritative data)
   - Read endpoint → Replicas (load balanced, may have slight lag)
   - Reduces master load for read-heavy applications

## Infrastructure Integration

### MetalLB IP Allocation (Shared IPs with Port-Based Routing)

**Efficient IP Utilization:**
- Only **3 IPs** used for all PostgreSQL external access (vs 6+ with dedicated IPs)
- Each database gets a unique port on shared IPs
- Scales easily - just assign next available port

| Shared IP | Type | Port Assignments | Purpose |
|-----------|------|------------------|---------|
| 103.110.174.18 | NGINX Ingress | 80, 443 | HTTP/HTTPS (existing) |
| **103.110.174.19** | **All Write Endpoints** | temporal:5432, platform:5433, apps:5434 | Application writes |
| **103.110.174.20** | **All Read Endpoints** | temporal:5432, platform:5433, apps:5434 | Application reads |
| **103.110.174.21** | **All Admin Endpoints** | temporal:5432, platform:5433, apps:5434 | Migrations/maintenance |

**Database Connection Details:**

| Database | Write | Read | Admin |
|----------|-------|------|-------|
| temporal-db | temporal-db-write.pnats.cloud:5432<br/>→ 103.110.174.19:5432 | temporal-db-read.pnats.cloud:5432<br/>→ 103.110.174.20:5432 | temporal-db-admin.pnats.cloud:5432<br/>→ 103.110.174.21:5432 |
| platform-db | platform-db-write.pnats.cloud:5433<br/>→ 103.110.174.19:5433 | _(internal only)_ | platform-db-admin.pnats.cloud:5433<br/>→ 103.110.174.21:5433 |
| applications-db | applications-db-write.pnats.cloud:5434<br/>→ 103.110.174.19:5434 | applications-db-read.pnats.cloud:5434<br/>→ 103.110.174.20:5434 | applications-db-admin.pnats.cloud:5434<br/>→ 103.110.174.21:5434 |

**Status:** Uses only 3 of 6 available IPs from your MetalLB `public-pool` (50% efficiency gain)

### external-dns Integration

- **Automatic DNS creation**: external-dns watches LoadBalancer services
- **Annotation**: `external-dns.alpha.kubernetes.io/hostname: temporal-db-write.pnats.cloud`
- **Result**: DNS A records automatically created in Cloudflare for pnats.cloud domain
- **TTL**: 300 seconds (5 minutes)

### TLS/SSL with Let's Encrypt

- **ClusterIssuer**: Uses existing `letsencrypt-production`
- **DNS-01 Challenge**: Cloudflare integration (already configured)
- **Certificates**: Automatically provisioned by cert-manager for each cluster
- **DNS Names**: Each certificate includes:
  - Internal: `{cluster}.{namespace}.svc.cluster.local`
  - External: `{cluster}-write.pnats.cloud`, `{cluster}-read.pnats.cloud`, `{cluster}-admin.pnats.cloud`
- **Validity**: 90 days with automatic renewal 30 days before expiry
- **Trust**: Publicly trusted (Let's Encrypt root CA in all OS trust stores)

## Security Implementation

### Network Security Layers

1. **IP Allowlisting (MetalLB LoadBalancer)**
   - `loadBalancerSourceRanges` restricts access by source IP
   - Write/Read endpoints: Configurable (currently `0.0.0.0/0` - must restrict!)
   - Admin endpoint: STRICT - office network only (`103.110.174.0/24`)

2. **TLS Encryption (Always On)**
   - All connections require TLS/SSL
   - Let's Encrypt certificates with `verify-full` mode
   - Man-in-the-middle attack protection
   - Encrypted data in transit

3. **PostgreSQL Authentication (scram-sha-256)**
   - Modern password hashing (not md5)
   - pg_hba rules enforce scram-sha-256
   - Different users for different purposes:
     - Application users: Limited permissions
     - `platform_admin`: Superuser from Keycloak
     - `postgres_exporter`: Monitoring only

4. **Connection Type Isolation**
   - Write/Read: Application users only
   - Admin: Requires superuser credentials + IP allowlist

## Files Created

### 1. `templates/external-services.yaml`

Creates three LoadBalancer services per cluster:
- `{cluster}-external-write`: Master with pooler
- `{cluster}-external-read`: Replicas with pooler
- `{cluster}-external-admin`: Master direct (no pooler)

**Features:**
- MetalLB annotations for IP assignment
- external-dns annotations for DNS automation
- IP allowlisting via `loadBalancerSourceRanges`
- Session affinity for admin connections
- Proper selectors for master vs replica pods

### 2. `templates/certificates.yaml`

Automatically provisions TLS certificates via cert-manager:
- Certificate resource per cluster (when `tls.enabled: true`)
- DNS names for all service endpoints
- Let's Encrypt DNS-01 challenge
- 90-day validity with automatic renewal

### 3. `templates/cluster-issuer.yaml`

Optional ClusterIssuer creation (disabled in production, using existing):
- Self-signed CA option (for internal)
- ACME/Let's Encrypt option (for public)
- Vault PKI option (for enterprise)
- CA issuer option (for existing CA)

### 4. `TLS-SETUP.md`

Complete TLS documentation:
- How cert-manager integration works
- Different issuer types explained
- Configuration examples
- Troubleshooting guide

### 5. `DEVELOPER-GUIDE.md`

**Comprehensive developer guide** covering:
- Connection architecture explanation
- When to use which endpoint
- Connection examples in 7+ languages
- Migration tool configuration (Flyway, Liquibase, Alembic, golang-migrate)
- TLS/SSL setup and troubleshooting
- Credentials management
- Best practices
- Quick reference tables

## Configuration Example (Production)

```yaml
# values-production.yaml

# Global TLS - use existing Let's Encrypt
tls:
  createIssuer: false
  issuerName: letsencrypt-production
  issuerType: acme

pgClusters:
  - name: temporal-db
    namespace: temporal

    # ... cluster config ...

    # TLS with Let's Encrypt
    tls:
      enabled: true
      additionalDNSNames:
        - temporal-db-write.pnats.cloud
        - temporal-db-read.pnats.cloud
        - temporal-db-admin.pnats.cloud

    # External access configuration
    externalAccess:
      enabled: true

      # Write endpoint
      write:
        enabled: true
        hostname: temporal-db-write.pnats.cloud
        loadBalancerIP: 103.110.174.19
        port: 5432

      # Read endpoint
      read:
        enabled: true
        hostname: temporal-db-read.pnats.cloud
        loadBalancerIP: 103.110.174.20
        port: 5432

      # Admin endpoint (restricted)
      admin:
        enabled: true
        hostname: temporal-db-admin.pnats.cloud
        loadBalancerIP: 103.110.174.21
        port: 5432
        allowedSourceRanges:
          - 103.110.174.0/24  # Office network
```

## Deployment Flow

```
1. ArgoCD deploys Helm chart
   ↓
2. cert-manager creates Certificate resources
   ↓
3. Certificate resources trigger DNS-01 challenge
   ↓
4. Let's Encrypt validates DNS and issues certificates
   ↓
5. Certificates stored in Secrets ({cluster}-tls-cert)
   ↓
6. PostgreSQL CRs reference TLS secrets
   ↓
7. Zalando operator configures PostgreSQL with TLS
   ↓
8. LoadBalancer services created
   ↓
9. MetalLB assigns public IPs
   ↓
10. external-dns creates DNS A records in Cloudflare
    ↓
11. Everything ready for external connections!
```

**Timeline:** ~5-10 minutes for full deployment

## Developer Workflow

### For Application Development

```bash
# Set environment variables
export DB_WRITE_URL="postgresql://app_user:password@temporal-db-write.pnats.cloud:5432/mydb?sslmode=verify-full"
export DB_READ_URL="postgresql://app_user:password@temporal-db-read.pnats.cloud:5432/mydb?sslmode=verify-full"

# Run application
npm start
```

### For Database Migrations

```bash
# Use admin endpoint
flyway \
  -url="jdbc:postgresql://temporal-db-admin.pnats.cloud:5432/mydb?ssl=true&sslmode=verify-full" \
  -user=platform_admin \
  -password="${ADMIN_PASSWORD}" \
  migrate
```

### Getting Credentials

```bash
# Get from Kubernetes (if you have access)
kubectl get secret temporal.temporal-db.credentials.postgresql.acid.zalan.do \
  -n temporal \
  -o jsonpath='{.data.password}' | base64 -d

# Or from Vault (recommended)
vault kv get -field=password database/temporal-db/app_user
```

## Recommended Pooler Mode: TRANSACTION

For **maximum scalability**, use **transaction mode** (already configured):

```yaml
pooler:
  mode: transaction  # ← This is the best for scalability
```

### Why Transaction Mode?

**Scalability:**
- Highest connection reuse
- Minimal backend connections
- Best for microservices architectures
- Handles 1000s of concurrent clients

**Limitations:**
- No prepared statements → Use direct admin connection for migrations
- No advisory locks → Rarely needed in applications
- No session features → Use admin connection when needed

**Alternatives considered:**
- `session` mode: Full features but NO connection pooling benefit
- `statement` mode: Not recommended (limited use cases)

## Monitoring

### Check External Access

```bash
# Test DNS resolution
nslookup temporal-db-write.pnats.cloud
# Should return: 103.110.174.19

# Test connectivity
telnet temporal-db-write.pnats.cloud 5432

# Test TLS
openssl s_client -connect temporal-db-write.pnats.cloud:5432 -starttls postgres
```

### Monitor Certificates

```bash
# Check certificate status
kubectl get certificate -n temporal

# Check certificate details
kubectl describe certificate temporal-db-tls -n temporal

# View certificate expiry
kubectl get secret temporal-db-tls-cert -n temporal \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

### Monitor LoadBalancers

```bash
# Check external IPs assigned
kubectl get svc -n temporal | grep external

# Check external-dns logs
kubectl logs -n external-dns deployment/external-dns
```

## Security Recommendations

### Immediate Actions Required

1. **Restrict Write/Read Endpoints**
   ```yaml
   externalAccess:
     allowedSourceRanges:
       - 203.0.113.0/24     # Your office network
       - 198.51.100.50/32   # VPN gateway
       - 192.0.2.0/24       # Cloud application subnet
   ```

2. **Use Strong Passwords**
   - Rotate default passwords immediately
   - Use password manager or Vault
   - Enable password rotation in values:
     ```yaml
     usersWithSecretRotation:
       - app_user
     ```

3. **Monitor Access Logs**
   ```bash
   kubectl logs -n temporal temporal-db-0 | grep "connection authorized"
   ```

### Production Hardening

- [ ] Replace `0.0.0.0/0` with actual IP ranges
- [ ] Enable VPN for developer access
- [ ] Set up connection auditing
- [ ] Configure pg_hba for stricter rules
- [ ] Enable SSL client certificates (optional, advanced)
- [ ] Set up IP allowlist automation (integrate with VPN)

## Troubleshooting

See `DEVELOPER-GUIDE.md` for detailed troubleshooting, including:
- Connection refused issues
- SSL/TLS errors
- Certificate validation problems
- Pooler limitation errors
- IP allowlist issues

## Next Steps

1. **Deploy the chart** with production values
2. **Verify DNS records** created by external-dns
3. **Test connections** from developer workstation
4. **Update IP allowlists** to actual office/VPN ranges
5. **Share DEVELOPER-GUIDE.md** with development teams
6. **Set up monitoring** for connection metrics
7. **Document credential access** in team wiki

## Support

- **Template Issues**: Check templates/*.yaml files
- **Connection Issues**: See DEVELOPER-GUIDE.md
- **TLS Issues**: See TLS-SETUP.md
- **Platform Team**: platform-team@pnats.cloud
