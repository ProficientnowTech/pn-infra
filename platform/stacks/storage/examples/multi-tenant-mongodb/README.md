# Multi-Tenant MongoDB Architecture Examples

This directory contains example configurations for implementing a scalable multi-tenant MongoDB architecture using Percona Operator for MongoDB.

## Architecture Overview

Support for **1,000 to 100,000 tenants** with **full database-level isolation** using a cluster pooling strategy.

```
100,000 tenants = 670 MongoDB clusters across 3 tiers
├── Small Tier:  80,000 tenants / 320 clusters (250 tenants per cluster)
├── Medium Tier: 15,000 tenants / 150 clusters (100 tenants per cluster)
└── Large Tier:   5,000 tenants / 200 clusters (25 tenants per cluster)
```

## Files in This Directory

### 1. `small-tier-cluster.yaml`
Example MongoDB cluster configuration for small/free tier tenants.
- **Capacity**: 250 tenants per cluster
- **Resources**: 4 CPU, 16Gi RAM, 500Gi storage
- **Use Case**: Free tier, low-usage tenants

### 2. `medium-tier-cluster.yaml`
Example MongoDB cluster configuration for medium/professional tier tenants.
- **Capacity**: 100 tenants per cluster
- **Resources**: 8 CPU, 32Gi RAM, 1Ti storage
- **Use Case**: Standard SaaS plans

### 3. `tenant-provisioning-example.yaml`
Complete example showing:
- Custom Tenant CRD definition
- Tenant resource example
- Secrets management
- MongoDB user creation
- RBAC configuration
- Network policies

### 4. `../docs/mongodb-multi-tenancy-architecture.md`
Comprehensive architecture documentation covering:
- Detailed tier breakdown
- Tenant management components
- Backup strategies
- Monitoring approaches
- Resource planning
- Implementation roadmap

## Quick Start

### Prerequisites

1. **Percona Operator installed** in cluster-wide mode:
```bash
cd /home/devsupreme/work/pn-infra-main/platform/stacks/storage/charts/percona-mongodb-operator
helm dependency update
helm install psmdb-operator . \
  --namespace psmdb-operator \
  --create-namespace \
  --set psmdb-operator.watchAllNamespaces=true
```

2. **Create tier namespaces**:
```bash
kubectl create namespace mongodb-small-tier
kubectl create namespace mongodb-medium-tier
kubectl create namespace mongodb-large-tier
kubectl create namespace mongodb-dedicated
```

3. **Create backup storage secrets**:
```bash
kubectl create secret generic s3-backup-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=<your-key> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<your-secret> \
  -n mongodb-small-tier

# Repeat for other namespaces
```

### Deploy First Cluster Pool

```bash
# Deploy small tier cluster
kubectl apply -f small-tier-cluster.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=ready \
  perconaservermongodb/small-tenant-pool-01 \
  -n mongodb-small-tier \
  --timeout=600s

# Verify cluster status
kubectl get psmdb -n mongodb-small-tier
```

## Tenant Provisioning Flow

### Manual Provisioning (for testing)

```bash
# 1. Create tenant credentials secret
kubectl create secret generic tenant-000001-credentials \
  --from-literal=username=tenant_000001_user \
  --from-literal=password=$(openssl rand -base64 32) \
  -n mongodb-small-tier

# 2. Add user to cluster (patch PSMDB CR)
kubectl patch psmdb small-tenant-pool-01 \
  -n mongodb-small-tier \
  --type=merge \
  -p '{
    "spec": {
      "users": [
        {
          "name": "tenant_000001_user",
          "db": "tenant_000001",
          "passwordSecretRef": {
            "name": "tenant-000001-credentials",
            "key": "password"
          },
          "roles": [
            {
              "name": "dbOwner",
              "db": "tenant_000001"
            }
          ]
        }
      ]
    }
  }'

# 3. Get connection string
CONN_STRING=$(kubectl get svc small-tenant-pool-01-rs0 \
  -n mongodb-small-tier \
  -o jsonpath='{.spec.clusterIP}')
echo "mongodb://tenant_000001_user:<password>@${CONN_STRING}:27017/tenant_000001?ssl=true&replicaSet=rs0"
```

### Automated Provisioning (recommended)

Build a **Tenant Provisioning Controller** (see architecture doc) that:
1. Watches for Tenant CRs
2. Assigns tenants to clusters based on tier
3. Creates MongoDB users automatically
4. Manages lifecycle (upgrades, migrations, deletions)

Example using the Tenant CRD:
```bash
kubectl apply -f - <<EOF
apiVersion: multitenancy.platform.io/v1alpha1
kind: Tenant
metadata:
  name: tenant-000001
spec:
  tenantId: "tenant-000001"
  plan: professional
  tier: medium
  maxStorage: "10Gi"
  maxConnections: 50
EOF

# Controller automatically:
# - Creates credentials secret
# - Adds user to appropriate cluster
# - Updates tenant registry
# - Returns connection string in status
```

## Scaling Considerations

### When to Add New Cluster

Monitor cluster metrics:
```bash
# Check tenant count per cluster
kubectl get psmdb -n mongodb-small-tier \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.status.replsets[0].size}{"\n"}{end}'

# Add new cluster when approaching capacity:
# - Small tier: > 240 tenants (96% of 250)
# - Medium tier: > 95 tenants (95% of 100)
# - Large tier: > 23 tenants (92% of 25)
```

Deploy additional cluster:
```bash
# Copy and modify cluster YAML
cp small-tier-cluster.yaml small-tier-cluster-02.yaml

# Update metadata.name: small-tenant-pool-02
sed -i 's/pool-01/pool-02/g' small-tier-cluster-02.yaml

# Deploy
kubectl apply -f small-tier-cluster-02.yaml
```

### Tenant Migration Between Tiers

When tenant outgrows tier:
```bash
# 1. Backup tenant database
kubectl apply -f - <<EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBBackup
metadata:
  name: tenant-000001-migration
  namespace: mongodb-small-tier
spec:
  clusterName: small-tenant-pool-01
  storageName: s3-small-tier
EOF

# 2. Restore to new tier
kubectl apply -f - <<EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBRestore
metadata:
  name: restore-tenant-000001
  namespace: mongodb-medium-tier
spec:
  clusterName: medium-tenant-pool-01
  backupName: tenant-000001-migration
  replset:
    - name: rs0
      configuration: |
        nsInclude:
          - "tenant_000001.*"
EOF

# 3. Update application connection string
# 4. Verify data in new cluster
# 5. Delete from old cluster
```

## Monitoring

### Per-Cluster Metrics (via PMM)
- Connection count
- Operation latency
- Storage usage
- Replication lag

### Per-Tenant Metrics (custom)
Collect via MongoDB queries:
```javascript
// Get tenant database stats
db.getSiblingDB("tenant_000001").stats()

// Monitor tenant connections
db.getSiblingDB("admin").aggregate([
  { $currentOp: { allUsers: true, idleConnections: true } },
  { $match: { ns: /^tenant_000001\./ } },
  { $group: { _id: null, count: { $sum: 1 } } }
])
```

## Backup and Restore

### Cluster-Level Backup
Automated daily/weekly backups configured in cluster YAML.

### Single Tenant Restore
```bash
kubectl apply -f - <<EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBRestore
metadata:
  name: restore-tenant-12345
  namespace: mongodb-medium-tier
spec:
  clusterName: medium-tenant-pool-05
  backupName: "2025-01-15-daily"
  pitr:
    type: date
    date: "2025-01-15T10:30:00Z"
  replset:
    - name: rs0
      configuration: |
        nsInclude:
          - "tenant_12345.*"
EOF
```

## Cost Optimization

### Resource Right-Sizing
- **Monitor actual usage** via PMM
- **Adjust cluster resources** based on real metrics
- **Use spot instances** for non-critical small tier

### Storage Optimization
- **Enable compression**: `blockCompressor: snappy`
- **Archive inactive tenants**: Move to cheaper storage
- **Delete terminated tenants**: After retention period

### Auto-Scaling (future enhancement)
- Scale down clusters during off-hours
- Adjust replica count based on load
- Dynamic tier assignment based on usage patterns

## Security Checklist

- [x] TLS enabled for all connections (`mode: requireTLS`)
- [x] Data-at-rest encryption enabled
- [x] Database-level user isolation
- [x] Network policies restricting inter-namespace traffic
- [x] Resource quotas per namespace
- [x] Kubernetes RBAC for cluster access
- [x] MongoDB authentication restrictions (IP-based)
- [x] Regular security audits via PMM
- [x] Automated backup verification
- [x] Credential rotation policy

## Troubleshooting

### Cluster Not Ready
```bash
# Check operator logs
kubectl logs -n psmdb-operator deployment/percona-server-mongodb-operator

# Check cluster status
kubectl describe psmdb small-tenant-pool-01 -n mongodb-small-tier

# Check pod logs
kubectl logs -n mongodb-small-tier small-tenant-pool-01-rs0-0
```

### Tenant Cannot Connect
```bash
# Verify user exists
kubectl exec -n mongodb-small-tier small-tenant-pool-01-rs0-0 -- \
  mongo admin --eval "db.system.users.find({user: 'tenant_000001_user'})"

# Check credentials secret
kubectl get secret tenant-000001-credentials -n mongodb-small-tier -o yaml

# Test connection from pod
kubectl run -it --rm mongodb-client --image=mongo:7.0 --restart=Never -- \
  mongosh "mongodb://tenant_000001_user:<password>@small-tenant-pool-01-rs0:27017/tenant_000001?ssl=true"
```

### High Memory Usage
```bash
# Check WiredTiger cache size
kubectl exec -n mongodb-small-tier small-tenant-pool-01-rs0-0 -- \
  mongo admin --eval "db.serverStatus().wiredTiger.cache"

# Adjust cacheSizeRatio if needed (requires restart)
```

## Next Steps

1. **Read the full architecture document**: `../docs/mongodb-multi-tenancy-architecture.md`
2. **Deploy test clusters** in each tier
3. **Build tenant provisioning controller**
4. **Set up monitoring and alerting**
5. **Implement tenant registry service**
6. **Create migration procedures**
7. **Load test with target tenant count**
8. **Plan production rollout**

## References

- [Percona Operator Documentation](https://docs.percona.com/percona-operator-for-mongodb/)
- [MongoDB Multi-Tenancy Best Practices](https://www.mongodb.com/docs/manual/core/multitenancy/)
- [Kubernetes Multi-Tenancy Guide](https://kubernetes.io/docs/concepts/security/multi-tenancy/)
