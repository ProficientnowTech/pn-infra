# Prometheus Chart

ArgoCD Application for Prometheus monitoring stack.

## Purpose

Deploys Prometheus for metrics collection, storage, and alerting across the platform infrastructure.

## Configuration

### Chart Values (`values.yaml`)

```yaml
# Global repository settings
global:
  repoURL: "git@github.com:pnow-devsupreme/pn-infra.git"
  targetRevision: "main"
  rbac:
    create: true
    pspEnabled: false

# Labels configuration
labels:
  component: monitoring        # Component type for Kubernetes labels
  managed-by: argocd          # Override default Helm with ArgoCD

# Prometheus configuration
prometheus:
  enabled: true
  prometheusSpec:
    retention: 30d
    retentionSize: 50GB
    replicas: 2               # High availability

    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 8Gi

    # Storage configuration
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: rook-ceph-block
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 100Gi

# Alertmanager configuration
alertmanager:
  enabled: true
  alertmanagerSpec:
    replicas: 2
    retention: 120h

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

## Key Features

- **High Availability**: 2 replicas with persistent storage
- **Long-term Storage**: 30 days retention, 50GB size limit
- **Alerting**: Integrated Alertmanager for notifications
- **Service Discovery**: Automatic Kubernetes service discovery
- **Storage Integration**: Uses Rook Ceph for persistent metrics storage

## Generated Application

**Sync Wave**: `4` - Deploys after storage and security infrastructure
**Target Namespace**: `monitoring`
**Dependencies**: Rook Ceph storage cluster

## Integration Points

- **Grafana**: Data source for visualization
- **Platform Services**: Scrapes metrics from all platform components
- **Alerting**: Sends alerts for platform health issues

## Monitoring Targets

Platform services automatically monitored:
- ArgoCD (application sync status, performance)
- Rook Ceph (storage health, performance)
- Vault (authentication, seal status)
- Kubernetes (node/pod metrics, events)
- Ingress/MetalLB (traffic, connectivity)

## Troubleshooting

```bash
kubectl get pods -n monitoring
kubectl get prometheus -n monitoring
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```
