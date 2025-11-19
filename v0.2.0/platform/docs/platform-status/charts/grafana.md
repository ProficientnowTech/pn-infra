# Grafana - Visualization & Dashboards

## Status Overview

| Attribute | Value |
|-----------|-------|
| **Status** | ✅ Deployed & Operational |
| **Version** | 11.2.1 |
| **Chart Version** | 8.5.2 |
| **Namespace** | `monitoring` |
| **Production Ready** | ✅ Yes |
| **Monitoring Enabled** | ✅ Self-monitored |
| **High Availability** | ⚠️ Single replica (StatefulSet limitation) |

## Quick Links

- **URL**: [https://grafana.pnats.cloud](https://grafana.pnats.cloud)
- **Admin Password**: Stored in secret `grafana`

## Dependencies

### Hard Dependencies
- **Cert Manager** - TLS certificates for HTTPS
- **Ingress NGINX** - External access
- **External DNS** - DNS management
- **Rook Ceph** - Persistent storage (10Gi PVC)

### Soft Dependencies (Data Sources)
- **Prometheus** - Metrics data source
- **Loki** - Logs data source
- **Tempo** - Traces data source

## Architecture

### Components

| Component | Replicas | Storage | Status |
|-----------|----------|---------|--------|
| **Grafana** | 1 | 10Gi (ceph-block) | ✅ Running |
| **Sidecar (Dashboards)** | 1 (sidecar) | N/A | ✅ Running |

### Data Sources Configured

1. **Prometheus** (Default)
   - URL: `http://prometheus-kube-prometheus-prometheus.monitoring:9090`
   - Type: Prometheus
   - Access: Proxy

2. **Loki**
   - URL: `http://loki.monitoring.svc.cluster.local:3100`
   - Type: Loki
   - Access: Proxy
   - Features: Derived fields for trace correlation

3. **Tempo**
   - URL: `http://tempo.monitoring.svc.cluster.local:3200`
   - Type: Tempo
   - Access: Proxy
   - Features: Traces to logs/metrics correlation

## Production Configuration

### Dashboard Management
- ✅ **Sidecar Enabled**: Automatic dashboard discovery
  - Searches ALL namespaces
  - Label: `grafana_dashboard: "1"`
  - Auto-loads dashboards from ConfigMaps

### Dashboards Available

#### Platform Dashboards (Auto-loaded)
- Kubernetes Cluster (GrafanaNet ID: 7249)
- Kubernetes Pods (GrafanaNet ID: 6417)
- Loki Logs (GrafanaNet ID: 13639)
- Tempo Traces (GrafanaNet ID: 16485)

#### Application Dashboards (Sidecar-loaded)
- **Temporal**:
  - Temporal Server Overview
  - Temporal Logs
  - Temporal PostgreSQL
- **Additional**: Any ConfigMap with `grafana_dashboard: "1"` label

### Persistence
- ✅ 10Gi persistent volume (Ceph)
- ✅ Stores: Dashboards, users, preferences, API keys

### Security
- ✅ HTTPS enabled (Let's Encrypt)
- ✅ Admin password in Kubernetes secret
- ⚠️ Default password should be changed
- ✅ Network policies (default Kubernetes)

### High Availability
- ⚠️ Single replica (PVC limitation - ReadWriteOnce)
- Note: Ceph RBD uses ReadWriteOnce, preventing multi-pod attachment
- **Enhancement Opportunity**: Switch to ReadWriteMany storage class

## Network Configuration

### External Access
- **URL**: `https://grafana.pnats.cloud`
- **Type**: Ingress (NGINX)
- **TLS**: Let's Encrypt certificate
- **DNS**: Managed by External-DNS

### Internal Access
- **Service**: `grafana.monitoring.svc:80`

## Monitoring & Observability

### Self-Monitoring
- Grafana exports its own metrics
- Can be scraped by Prometheus
- Dashboard available for Grafana metrics

## Known Issues

### None Currently

Recent changes:
- ✅ Enabled sidecar for automatic dashboard discovery (2025-11-19)
- ✅ Resolved PVC attachment issue during rollout

## Enhancement Opportunities

### High Priority
1. **High Availability**: Investigate ReadWriteMany storage
   - Option 1: Use CephFS instead of RBD
   - Option 2: External database for Grafana state
   - Option 3: Accept single replica with backup strategy

2. **Change Default Password**: Update admin password from default

### Medium Priority
3. **RBAC**: Implement fine-grained access control
   - Team-based folder permissions
   - Read-only users for viewers

4. **Alerting**: Configure Grafana alerting
   - Integrate with notification channels
   - Define alert rules

5. **Dashboard Organization**: Create folder structure
   - Infrastructure folder
   - Application folder
   - Security folder

### Low Priority
6. **Plugins**: Evaluate useful plugins
   - Additional visualization types
   - Data source plugins

7. **Theming**: Apply organizational branding

## Operational Procedures

### Add a New Dashboard via ConfigMap

Create a ConfigMap with the dashboard JSON and appropriate labels:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-my-app
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  my-app-dashboard.json: |
    {
      "dashboard": { ... }
    }
```

The sidecar will automatically detect and load it within seconds.

### Access Grafana Admin

```bash
# Get admin password
kubectl get secret -n monitoring grafana -o jsonpath='{.data.admin-password}' | base64 -d

# Port-forward (alternative to ingress)
kubectl port-forward -n monitoring svc/grafana 3000:80
```

### Backup Dashboards

```bash
# Export all dashboards (requires Grafana API key)
# Dashboards in ConfigMaps are backed up via Git
# Custom dashboards stored in PVC should be exported regularly
```

## Troubleshooting

### Dashboard Not Appearing

```bash
# Check sidecar logs
kubectl logs -n monitoring deployment/grafana -c grafana-sc-dashboard

# Verify ConfigMap has correct label
kubectl get configmap -n <namespace> -l grafana_dashboard=1

# Check ConfigMap structure
kubectl get configmap -n <namespace> <configmap-name> -o yaml
```

### Can't Access UI

```bash
# Check ingress
kubectl get ingress -n monitoring grafana

# Check certificate
kubectl get certificate -n monitoring grafana-tls

# Check pod
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
```

### Pod Stuck in Pending (PVC issue)

```bash
# Check PVC
kubectl get pvc -n monitoring

# Check PV
kubectl get pv | grep grafana

# Check Ceph cluster health
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

## Change Log

### 2025-11-19
- ✅ Enabled sidecar for automatic dashboard discovery
- ✅ Configured to search ALL namespaces
- ✅ Loaded Temporal dashboards successfully

### Earlier
- Initial deployment with Prometheus, Loki, Tempo data sources
- Configured ingress with TLS
- Set up persistent storage

## Related Documentation

- [Prometheus](prometheus.md)
- [Loki](loki.md)
- [Tempo](tempo.md)
- [Temporal Dashboards](temporal.md)
