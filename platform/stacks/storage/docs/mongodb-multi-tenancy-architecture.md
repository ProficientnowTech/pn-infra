# MongoDB Multi-Tenancy Architecture for 1,000-100,000 Tenants

## Executive Summary

Supporting 1,000-100,000 tenants with full data isolation requires a **multi-tier cluster pooling strategy** using Percona Operator for MongoDB.

## Architecture: Database-per-Tenant with Cluster Pooling

### Model Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Tenant Management Layer                      │
│  (Tenant Registry, Cluster Assignment, Connection Routing)      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
        ┌────────────────────────────────────────────┐
        │         Cluster Pool Manager               │
        │  (Auto-scaling, Load Balancing, Health)    │
        └────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                     │                      │
        ▼                     ▼                      ▼
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  Cluster 1   │      │  Cluster 2   │ ...  │  Cluster N   │
│              │      │              │      │              │
│ • tenant-001 │      │ • tenant-251 │      │ • tenant-501 │
│ • tenant-002 │      │ • tenant-252 │      │ • tenant-502 │
│ • ...        │      │ • ...        │      │ • ...        │
│ • tenant-250 │      │ • tenant-500 │      │ • tenant-750 │
│              │      │              │      │              │
│ 250 tenants  │      │ 250 tenants  │      │ 250 tenants  │
└──────────────┘      └──────────────┘      └──────────────┘

Total: 400 clusters × 250 tenants = 100,000 tenants
```

### Key Principles

1. **Database per Tenant**: Each tenant gets dedicated database
2. **Cluster Pooling**: 200-250 tenants per MongoDB cluster
3. **Namespace Grouping**: 5-10 clusters per Kubernetes namespace
4. **Automated Management**: Custom controller for cluster assignment

## Detailed Architecture

### Tier 1: Small/Free Tenants (80% of tenants)

**Characteristics**:
- Low resource usage (< 1 GB data)
- Infrequent access
- Best-effort SLA

**Configuration**:
```yaml
# 250 tenants per cluster
# 50-100 clusters for 20,000 small tenants
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: small-tenant-pool-01
  namespace: mongodb-small-tier
spec:
  replsets:
    - name: rs0
      size: 3
      resources:
        requests:
          cpu: "2"
          memory: "8Gi"
        limits:
          cpu: "4"
          memory: "16Gi"
      volumeSpec:
        persistentVolumeClaim:
          resources:
            requests:
              storage: 500Gi  # ~2GB per tenant avg

      configuration: |
        storage:
          wiredTiger:
            engineConfig:
              cacheSizeRatio: 0.5
        setParameter:
          maxConns: 2000  # ~8 connections per tenant
```

### Tier 2: Medium Tenants (15% of tenants)

**Characteristics**:
- Moderate usage (1-10 GB data)
- Regular access
- Standard SLA

**Configuration**:
```yaml
# 100 tenants per cluster
# 150 clusters for 15,000 medium tenants
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: medium-tenant-pool-01
  namespace: mongodb-medium-tier
spec:
  replsets:
    - name: rs0
      size: 3
      resources:
        requests:
          cpu: "4"
          memory: "16Gi"
        limits:
          cpu: "8"
          memory: "32Gi"
      volumeSpec:
        persistentVolumeClaim:
          resources:
            requests:
              storage: 1Ti  # ~10GB per tenant avg
```

### Tier 3: Large/Enterprise Tenants (5% of tenants)

**Characteristics**:
- High usage (10-100 GB data)
- Critical workloads
- Premium SLA

**Configuration**:
```yaml
# 25 tenants per cluster
# 200 clusters for 5,000 large tenants
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: large-tenant-pool-01
  namespace: mongodb-large-tier
spec:
  replsets:
    - name: rs0
      size: 3
      resources:
        requests:
          cpu: "8"
          memory: "32Gi"
        limits:
          cpu: "16"
          memory: "64Gi"
      volumeSpec:
        persistentVolumeClaim:
          resources:
            requests:
              storage: 2Ti
```

### Tier 4: Dedicated Clusters (Top 0.1%)

**Characteristics**:
- Very large data (100GB+)
- Guaranteed resources
- Custom SLA

**Configuration**:
```yaml
# 1-5 tenants per cluster (or dedicated)
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: enterprise-tenant-xyz
  namespace: mongodb-dedicated
spec:
  replsets:
    - name: rs0
      size: 5  # Higher replica count
      resources:
        requests:
          cpu: "16"
          memory: "64Gi"
        limits:
          cpu: "32"
          memory: "128Gi"
```

## Tenant Management Components

### 1. Tenant Registry Service

**Database Schema**:
```javascript
{
  tenantId: "tenant-12345",
  tier: "medium",  // small, medium, large, dedicated
  clusterId: "medium-tenant-pool-05",
  clusterNamespace: "mongodb-medium-tier",
  databaseName: "tenant_12345",
  connectionString: "mongodb://medium-tenant-pool-05-rs0.mongodb-medium-tier.svc:27017/tenant_12345",
  createdAt: ISODate("2025-01-15T10:00:00Z"),
  status: "active",

  metadata: {
    planType: "professional",
    maxStorage: "10GB",
    maxConnections: 50
  },

  credentials: {
    usernameSecretRef: "tenant-12345-user",
    passwordSecretRef: "tenant-12345-password"
  }
}
```

### 2. Cluster Assignment Logic

```go
// Pseudocode for tenant provisioning
func AssignClusterToTenant(tenant Tenant) (string, error) {
    // Determine tier based on plan
    tier := DetermineTier(tenant.PlanType)

    // Find cluster with capacity
    cluster := FindAvailableCluster(tier)
    if cluster == nil {
        // Create new cluster if needed
        cluster = CreateNewCluster(tier)
    }

    // Create database and user
    CreateDatabaseForTenant(cluster, tenant)
    CreateUserForTenant(cluster, tenant)

    // Update registry
    UpdateTenantRegistry(tenant.ID, cluster.ID)

    return cluster.ConnectionString, nil
}

func FindAvailableCluster(tier string) *Cluster {
    maxTenantsPerCluster := map[string]int{
        "small":     250,
        "medium":    100,
        "large":     25,
        "dedicated": 1,
    }

    clusters := GetClustersByTier(tier)
    for _, cluster := range clusters {
        if cluster.TenantCount < maxTenantsPerCluster[tier] {
            return cluster
        }
    }
    return nil
}
```

### 3. Connection Router/Proxy

Use **MongoDB mongos** or custom proxy to route connections:

```yaml
# Deploy mongos as connection router
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tenant-connection-router
spec:
  replicas: 10
  template:
    spec:
      containers:
      - name: router
        image: custom-tenant-router:latest
        env:
        - name: TENANT_REGISTRY_URL
          value: "mongodb://tenant-registry:27017/tenants"
```

**Router Logic**:
```javascript
// Authenticate tenant and route to correct cluster
async function routeConnection(tenantId, credentials) {
    // Lookup tenant in registry
    const tenant = await tenantRegistry.findOne({ tenantId });

    if (!tenant) {
        throw new Error("Tenant not found");
    }

    // Validate credentials
    await validateTenantCredentials(tenant, credentials);

    // Return connection to tenant's cluster
    return {
        connectionString: tenant.connectionString,
        database: tenant.databaseName,
        options: {
            maxPoolSize: tenant.metadata.maxConnections
        }
    };
}
```

## User and Security Management

### Per-Tenant User Creation

```yaml
# Automated user creation per tenant
apiVersion: v1
kind: Secret
metadata:
  name: tenant-12345-credentials
  namespace: mongodb-medium-tier
type: Opaque
stringData:
  username: "tenant_12345_user"
  password: "<generated-password>"
---
# Update PerconaServerMongoDB CR via operator
spec:
  users:
    - name: tenant_12345_user
      db: tenant_12345
      passwordSecretRef:
        name: tenant-12345-credentials
        key: password
      roles:
        - name: dbOwner
          db: tenant_12345
      authenticationRestrictions:
        - clientSource:
            - "10.0.0.0/8"  # Internal network only
```

### RBAC Isolation

```javascript
// Custom role limiting tenant to their database only
db.createRole({
    role: "tenant_12345_role",
    privileges: [
        {
            resource: { db: "tenant_12345", collection: "" },
            actions: [
                "find", "insert", "update", "remove",
                "createIndex", "dropIndex", "createCollection"
            ]
        }
    ],
    roles: []
});

db.createUser({
    user: "tenant_12345_user",
    pwd: "<password>",
    roles: [
        { role: "tenant_12345_role", db: "admin" }
    ],
    authenticationRestrictions: [
        { clientSource: ["10.0.0.0/8"] }
    ]
});
```

## Backup and Restore Strategy

### Challenge: 100,000 Individual Backups

**Solution**: Cluster-level backups with selective restore

### Backup Configuration

```yaml
backup:
  enabled: true

  # Physical backups for fast full cluster restore
  tasks:
    - name: daily-physical
      enabled: true
      schedule: "0 2 * * *"
      type: physical
      storageName: s3-backup
      keep: 7

    - name: weekly-physical
      enabled: true
      schedule: "0 3 * * 0"
      type: physical
      storageName: s3-backup
      keep: 4

  # PITR for point-in-time recovery
  pitr:
    enabled: true
    oplogSpanMin: 60  # 1 hour of oplog

  storages:
    s3-backup:
      type: s3
      s3:
        bucket: mongodb-backups
        prefix: "medium-tier/pool-01"
        region: us-east-1
```

### Selective Tenant Restore

```yaml
# Restore single tenant from cluster backup
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBRestore
metadata:
  name: restore-tenant-12345
spec:
  clusterName: medium-tenant-pool-05
  backupName: "2025-01-15-daily"

  # Only restore specific tenant database
  replset:
    - name: rs0
      configuration: |
        nsInclude:
          - "tenant_12345.*"
```

### Backup Retention Strategy

```yaml
# Tiered backup retention
Small Tier:
  - Daily: 3 days
  - Weekly: 2 weeks
  - Monthly: 1 month

Medium Tier:
  - Daily: 7 days
  - Weekly: 4 weeks
  - Monthly: 3 months

Large/Enterprise Tier:
  - Daily: 14 days
  - Weekly: 8 weeks
  - Monthly: 12 months
  - PITR: Full history
```

## Monitoring and Observability

### Cluster-Level Metrics

```yaml
pmm:
  enabled: true
  image: percona/pmm-client:2
  serverHost: pmm-server.monitoring.svc
  resources:
    requests:
      cpu: "300m"
      memory: "512Mi"
```

### Per-Tenant Metrics Collection

```javascript
// Custom metrics collection
{
  tenantId: "tenant-12345",
  clusterId: "medium-pool-05",
  metrics: {
    storageUsedGB: 5.2,
    activeConnections: 12,
    opsPerSecond: 150,
    queryLatencyMs: 8.5
  },
  timestamp: ISODate("2025-01-15T12:00:00Z")
}
```

### Alerting Rules

```yaml
# Alert on tenant approaching limits
- alert: TenantStorageNearLimit
  expr: |
    tenant_storage_used_bytes / tenant_storage_limit_bytes > 0.85
  labels:
    severity: warning
  annotations:
    summary: "Tenant {{ $labels.tenant_id }} using 85% of storage quota"

- alert: ClusterOverCapacity
  expr: |
    mongodb_cluster_tenant_count > 250
  labels:
    severity: critical
  annotations:
    summary: "Cluster {{ $labels.cluster }} exceeds tenant capacity"
```

## Resource Planning

### Infrastructure Requirements for 100,000 Tenants

**Small Tier (80,000 tenants)**:
- 320 clusters (250 tenants each)
- ~32 Kubernetes namespaces (10 clusters per namespace)
- Resources per cluster: 4 CPU, 16Gi RAM, 500Gi storage
- Total: 1,280 CPU cores, 5,120 Gi RAM, 160 Ti storage

**Medium Tier (15,000 tenants)**:
- 150 clusters (100 tenants each)
- ~15 Kubernetes namespaces
- Resources per cluster: 8 CPU, 32Gi RAM, 1Ti storage
- Total: 1,200 CPU cores, 4,800 Gi RAM, 150 Ti storage

**Large Tier (5,000 tenants)**:
- 200 clusters (25 tenants each)
- ~20 Kubernetes namespaces
- Resources per cluster: 16 CPU, 64Gi RAM, 2Ti storage
- Total: 3,200 CPU cores, 12,800 Gi RAM, 400 Ti storage

**Grand Total**:
- ~670 MongoDB clusters
- ~70 Kubernetes namespaces
- ~5,680 CPU cores
- ~22,720 Gi RAM (~22 TiB)
- ~710 TiB storage

### Cost Optimization

1. **Use spot/preemptible instances** for small tier non-critical workloads
2. **Auto-scaling**: Scale down clusters during off-hours
3. **Storage tiering**: Move cold tenant data to cheaper storage
4. **Compression**: Enable WiredTiger compression to reduce storage costs

## Migration and Tenant Movement

### Moving Tenant to Different Tier

```bash
# 1. Create backup of tenant database
kubectl apply -f - <<EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBBackup
metadata:
  name: tenant-12345-migration
spec:
  clusterName: small-tenant-pool-10
  storageName: s3-backup
EOF

# 2. Restore to new cluster in different tier
kubectl apply -f - <<EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBRestore
metadata:
  name: restore-tenant-12345
  namespace: mongodb-medium-tier
spec:
  clusterName: medium-tenant-pool-05
  backupName: tenant-12345-migration
  replset:
    - name: rs0
      configuration: |
        nsInclude:
          - "tenant_12345.*"
EOF

# 3. Update tenant registry
db.tenants.updateOne(
  { tenantId: "tenant-12345" },
  {
    $set: {
      tier: "medium",
      clusterId: "medium-tenant-pool-05",
      clusterNamespace: "mongodb-medium-tier"
    }
  }
)

# 4. Update application connection (zero-downtime)
# Use blue-green deployment or connection pooling
```

## Automation Requirements

### Custom Kubernetes Operator/Controller

Build a **Tenant Provisioning Controller** to automate:

```go
// Tenant CRD
type Tenant struct {
    metav1.TypeMeta
    metav1.ObjectMeta

    Spec TenantSpec
    Status TenantStatus
}

type TenantSpec struct {
    TenantID    string
    Plan        string  // free, starter, professional, enterprise
    MaxStorage  string  // "10Gi"
    MaxConnections int
}

type TenantStatus struct {
    Phase       string  // Pending, Provisioning, Active, Migrating
    ClusterID   string
    Database    string
    ConnectionString string
}
```

**Controller Responsibilities**:
1. Watch for new Tenant CRs
2. Assign tenant to appropriate cluster pool
3. Create MongoDB database and user
4. Manage Kubernetes Secrets for credentials
5. Update tenant registry
6. Monitor usage and trigger auto-scaling
7. Handle tier migrations

## Implementation Roadmap

### Phase 1: Foundation (Months 1-2)
- Deploy Percona operator in cluster-wide mode
- Create 3 tier namespaces (small, medium, large)
- Deploy initial cluster pools (10 clusters per tier)
- Build tenant registry service

### Phase 2: Automation (Months 3-4)
- Develop tenant provisioning controller
- Implement connection routing
- Set up monitoring and alerting
- Create backup automation

### Phase 3: Scale Testing (Months 5-6)
- Load test with 10,000 tenants
- Optimize cluster sizing
- Tune resource limits
- Performance benchmarking

### Phase 4: Production Rollout (Months 7+)
- Gradual tenant migration
- Auto-scaling implementation
- Cost optimization
- 24/7 monitoring

## Alternative: Sharded Multi-Tenant Architecture

If you're willing to trade some isolation for efficiency, consider:

### Sharded Cluster with Tenant-Based Shard Key

```yaml
sharding:
  enabled: true
  configsvrReplSet:
    size: 3
  mongos:
    size: 10

replsets:
  - name: shard0
    size: 3
  - name: shard1
    size: 3
  # ... up to N shards
```

**Shard by tenant ID**:
```javascript
// Enable sharding
sh.enableSharding("shared_db")

// Shard collection by tenantId
sh.shardCollection("shared_db.items", { tenantId: 1, _id: 1 })

// Create tenant-specific zones for data locality
sh.addShardTag("shard0", "region-us-east")
sh.addTagRange(
  "shared_db.items",
  { tenantId: "tenant-000000", _id: MinKey },
  { tenantId: "tenant-050000", _id: MaxKey },
  "region-us-east"
)
```

**Benefits**:
- Better resource utilization
- Easier to scale horizontally
- Lower infrastructure costs

**Drawbacks**:
- Weaker isolation (logical, not physical)
- Backup/restore complexity
- Noisy neighbor risks

## Conclusion

For 100,000 tenants with full data isolation:

1. **Use database-per-tenant with cluster pooling**
2. **Deploy ~670 MongoDB clusters across tiered namespaces**
3. **Build custom automation for tenant lifecycle management**
4. **Implement cluster-level backups with selective restore**
5. **Use connection routing for transparent tenant access**

This architecture provides:
- ✅ Full database-level isolation
- ✅ Scalable to 100,000+ tenants
- ✅ Cost-effective resource utilization
- ✅ Automated management
- ✅ Independent backup/restore per tenant
- ✅ Tier-based SLA support
