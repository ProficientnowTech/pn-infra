# Rook Ceph Cluster Chart

ArgoCD Application for Rook Ceph storage cluster deployment.

## Purpose

Deploys a Ceph storage cluster managed by Rook operator, providing persistent storage for platform workloads including block storage, object storage, and shared filesystem.

## Configuration

### Chart Values (`values.yaml`)

```yaml
# Global repository settings
global:
  repoURL: 'git@github.com:pnow-devsupreme/pn-infra.git'
  targetRevision: 'main'

# Labels configuration
labels:
  component: storage           # Component type for Kubernetes labels
  managed-by: argocd          # Override default Helm with ArgoCD

# Ceph cluster configuration
cluster:
  name: rook-ceph
  namespace: rook-ceph
  dataDirHostPath: /var/lib/rook
  skipUpgradeChecks: false
  continueUpgradeAfterChecksEvenIfNotHealthy: false
  waitTimeoutForHealthyOSDInMinutes: 10

# Storage configuration
storage:
  useAllNodes: true
  useAllDevices: true
  config:
    osdsPerDevice: "1"
    encryptedDevice: "true"

# Monitoring integration
monitoring:
  enabled: true
  createPrometheusRules: true

# Resource specifications
resources:
  mgr:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  
  mon:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  
  osd:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2Gi
```

### Key Configuration Options

| Setting | Default | Purpose |
|---------|---------|---------|
| `labels.component` | `storage` | Kubernetes component label |
| `labels.managed-by` | `argocd` | Management tool identifier |
| `cluster.dataDirHostPath` | `/var/lib/rook` | Host path for Rook data |
| `cluster.waitTimeoutForHealthyOSDInMinutes` | `10` | OSD health check timeout |
| `storage.useAllNodes` | `true` | Use all available nodes |
| `storage.useAllDevices` | `true` | Use all available block devices |
| `storage.config.osdsPerDevice` | `"1"` | OSDs per storage device |
| `storage.config.encryptedDevice` | `"true"` | Enable device encryption |
| `monitoring.enabled` | `true` | Enable Prometheus monitoring |

### Storage Configuration

**Device Selection:**
- **useAllNodes**: `true` - Automatically discover and use all cluster nodes
- **useAllDevices**: `true` - Automatically discover and use all available block devices
- **osdsPerDevice**: `1` - Create one OSD (Object Storage Daemon) per device

**Security:**
- **encryptedDevice**: `true` - Encrypt data at rest on storage devices

### Resource Specifications

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|------------|---------------|-----------|--------------|
| **Manager (mgr)** | 100m | 128Mi | 500m | 512Mi |
| **Monitor (mon)** | 100m | 128Mi | 500m | 512Mi |
| **OSD** | 100m | 512Mi | 1000m | 2Gi |

## Generated Application

When deployed via target-chart, creates ArgoCD Application with:

```yaml
metadata:
  name: rook-ceph-cluster
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: '2'  # Deploy after rook-ceph operator
  labels:
    # From chart helper
    helm.sh/chart: rook-ceph-cluster-0.1.0
    app.kubernetes.io/name: rook-ceph-cluster
    app.kubernetes.io/instance: {release-name}
    app.kubernetes.io/managed-by: argocd
    app.kubernetes.io/component: storage
    
    # From target-chart commonLabels
    app.kubernetes.io/part-of: platform-infrastructure
    platform.pn-infra.io/stack: platform
    platform.pn-infra.io/environment: {environment}
    platform.pn-infra.io/application: "rook-ceph-cluster"

spec:
  project: platform
  sources:
    - repoURL: https://charts.rook.io/release
      chart: rook-ceph-cluster
      targetRevision: v1.18.3
      helm:
        releaseName: rook-ceph-cluster
        parameters:
          - name: operatorNamespace
            value: rook-ceph
        valueFiles:
          - $values/platform/charts/rook-ceph-cluster/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: rook-ceph
```

## Deployment

**Sync Wave**: `2` - Deploys after rook-ceph operator (wave 1) but before applications that need storage

**Dependencies:**
- rook-ceph operator (deployed in wave 1)
- Available block devices on nodes
- Adequate node resources

**Target Namespace**: `rook-ceph`

## Storage Classes Created

After successful deployment, the following storage classes are available:

- **rook-ceph-block**: Block storage for databases, stateful applications
- **rook-ceph-filesystem**: Shared filesystem for multi-pod access
- **rook-ceph-object**: Object storage for backup, artifacts

## Monitoring Integration

**Prometheus Metrics:**
- Ceph cluster health and performance
- OSD status and utilization
- Pool and PG statistics
- Network and disk I/O metrics

**Grafana Dashboards:**
- Ceph cluster overview
- OSD performance
- Pool utilization
- Health and alerts

## Node Requirements

### Minimum Requirements per Node
- **CPU**: 2 cores available for Ceph processes
- **Memory**: 4GB RAM minimum (8GB recommended)
- **Storage**: At least one unused block device (not partitioned)
- **Network**: 1Gbps minimum (10Gbps recommended for production)

### Recommended Production Setup
- **3+ nodes** for high availability
- **Dedicated storage devices** (SSD preferred)
- **Dedicated storage network** for Ceph traffic
- **Node labeling** for storage node selection

## Customization

### Node Selection
```yaml
# In values.yaml
storage:
  useAllNodes: false
  nodes:
    - name: "node1"
      devices:
        - name: "/dev/sdb"
    - name: "node2" 
      devices:
        - name: "/dev/sdc"
```

### Resource Tuning
```yaml
# For high-performance workloads
resources:
  osd:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
```

### Encryption Configuration
```yaml
storage:
  config:
    encryptedDevice: "true"      # Device-level encryption
    encryption:
      enable: true               # Cluster-level encryption
      keyManagementService:
        connectionDetails:
          KMS_PROVIDER: "vault"   # Use Vault for key management
```

## Troubleshooting

### Check Cluster Status
```bash
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph
```

### Check Ceph Status
```bash
kubectl exec -n rook-ceph deployment/rook-ceph-tools -- ceph status
kubectl exec -n rook-ceph deployment/rook-ceph-tools -- ceph osd status
```

### Check Storage Classes
```bash
kubectl get storageclass | grep rook-ceph
```

### Debug OSD Issues
```bash
kubectl logs -n rook-ceph -l app=rook-ceph-osd
kubectl describe pod -n rook-ceph -l app=rook-ceph-osd
```