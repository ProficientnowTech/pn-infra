# Temporal - Workflow Orchestration

## Status Overview

| Attribute | Value |
|-----------|-------|
| **Status** | ✅ Deployed & Operational |
| **Version** | 1.24.2 |
| **Namespace** | `temporal` |
| **Deployment Date** | 2025-11-19 |
| **Production Ready** | ⚠️ Partially (Requires Load Testing) |
| **Monitoring Enabled** | ✅ Yes |
| **High Availability** | ✅ Yes (3 replicas per service) |

## Quick Links

- **UI**: [https://temporal-ui.pnats.cloud](https://temporal-ui.pnats.cloud)
- **gRPC Endpoint**: `temporal.pnats.cloud:7233` (LoadBalancer, no TLS)
- **Grafana Dashboards**: Available in Grafana under "Temporal" folder

## Dependencies

### Hard Dependencies
- **Zalando PostgreSQL Operator** (`zalando-pg`)
  - Required for database management
  - Status: ✅ Operational

- **Temporal PostgreSQL Database** (`temporal-db`)
  - 3-node PostgreSQL cluster
  - Databases: `temporal`, `temporal_visibility`
  - Status: ✅ Operational

- **Cert Manager** (`cert-manager`)
  - Required for TLS certificates (UI ingress)
  - Status: ✅ Operational

- **Ingress NGINX** (`ingress-nginx`)
  - Required for UI access
  - Status: ✅ Operational

- **External DNS** (`external-dns`)
  - Required for DNS management
  - Status: ✅ Operational

- **MetalLB** (`metallb-config`)
  - Required for LoadBalancer service
  - Status: ✅ Operational

### Soft Dependencies
- **Prometheus** - Metrics collection (monitoring)
- **Grafana** - Dashboards and visualization
- **Loki** - Log aggregation

## Architecture

### Components Deployed

| Component | Replicas | Resources | Status |
|-----------|----------|-----------|--------|
| **Frontend** | 3 | 200m-1000m CPU, 512Mi-1Gi RAM | ✅ Running |
| **History** | 3 | 500m-2000m CPU, 1Gi-4Gi RAM | ✅ Running |
| **Matching** | 3 | 200m-1000m CPU, 512Mi-1Gi RAM | ✅ Running |
| **Worker** | 5 | 200m-1000m CPU, 512Mi-1Gi RAM | ✅ Running |
| **Web UI** | 2 | 100m-500m CPU, 128Mi-512Mi RAM | ✅ Running |
| **Admin Tools** | 1 | Default | ✅ Running |
| **Grafana** | 1 | Default | ✅ Running |

### Namespaces Configured

| Namespace | Retention Period | Purpose |
|-----------|-----------------|---------|
| `default` | 72h (3 days) | Default namespace |
| `pnats` | 2160h (90 days) | Production workflows |
| `pnats-staging` | 1440h (60 days) | Staging environment |
| `pnats-dev` | 720h (30 days) | Development environment |

### Storage

- **Database**: PostgreSQL 16 (Zalando operator managed)
  - Default DB: 3 replicas, persistent storage
  - Visibility DB: 3 replicas, persistent storage
  - Storage Class: `ceph-block`

- **History Shards**: 512 (IMMUTABLE - cannot be changed)

## Network Configuration

### External Access

#### gRPC API (Production)
- **URL**: `temporal.pnats.cloud:7233`
- **Type**: LoadBalancer (MetalLB)
- **TLS**: Disabled (direct gRPC)
- **External IP**: `103.110.174.23`
- **DNS**: Managed by External-DNS
- **Use Case**: Client connections from outside cluster

#### Web UI
- **URL**: `https://temporal-ui.pnats.cloud`
- **Type**: Ingress (NGINX)
- **TLS**: Enabled (Let's Encrypt)
- **DNS**: Managed by External-DNS
- **Use Case**: Human interface for workflow management

### Internal Access

- **Frontend Service**: `temporal-frontend.temporal.svc:7233`
- **Use Case**: In-cluster client connections

## Monitoring & Observability

### Metrics
- **Source**: Prometheus ServiceMonitors
- **Scrape Interval**: 30s
- **Dashboards**:
  - Temporal Server Overview
  - Temporal Logs
  - Temporal PostgreSQL

### Logs
- **Aggregation**: Loki
- **Source**: All Temporal pods
- **Dashboard**: Temporal Logs (Grafana)

### Traces
- **Status**: Not configured
- **Enhancement**: Consider integrating with Tempo

## Production Configuration

### High Availability
- ✅ Multiple replicas for all services
- ✅ Pod anti-affinity (implicit via Kubernetes)
- ✅ Rolling updates configured
- ✅ Health checks (liveness/readiness) enabled

### Resource Management
- ✅ CPU/Memory limits defined
- ✅ Resource requests defined
- ✅ Appropriate sizing for each component

### Security
- ✅ TLS for Web UI (Let's Encrypt)
- ⚠️ gRPC endpoint without TLS (considered acceptable for trusted networks)
- ✅ PostgreSQL password managed via Zalando operator
- ✅ Network policies (via Kubernetes defaults)

### Persistence
- ✅ PostgreSQL with persistent volumes
- ✅ 3-node database cluster for HA
- ✅ Automated backups (via Zalando operator)

## Known Issues

### None Currently

All deployment issues have been resolved:
- ✅ Fixed web ingress hosts format compatibility
- ✅ Fixed PostgreSQL secret reference
- ✅ Fixed duplicate environment variables
- ✅ Fixed admin-tools image tag

## Enhancement Opportunities

### High Priority
1. **Load Testing**: Conduct comprehensive load testing
   - Validate handling of production workload
   - Identify performance bottlenecks
   - Tune resource allocations

2. **TLS for gRPC**: Consider adding TLS termination
   - Evaluate mTLS for client authentication
   - Balance security vs complexity

### Medium Priority
3. **Alerting**: Define SLOs and alerts
   - Workflow execution failures
   - Database connection issues
   - High latency warnings

4. **Tracing Integration**: Enable distributed tracing
   - Integrate with Tempo
   - Trace workflow executions

5. **Archival**: Configure history archival
   - Setup S3/object storage
   - Define archival policies

### Low Priority
6. **Multi-Region**: Plan for multi-region deployment
   - Active-passive setup
   - Cross-region replication

7. **Advanced Visibility**: Enable advanced visibility features
   - Custom search attributes
   - Enhanced query capabilities

## Operational Procedures

### Access Temporal CLI

```bash
# Via admin-tools pod
kubectl exec -n temporal deployment/temporal-admintools -- tctl namespace list

# Register a new namespace
kubectl exec -n temporal deployment/temporal-admintools -- \
  tctl --namespace <name> namespace register \
  --retention 72h
```

### Check Cluster Health

```bash
# Check all pods
kubectl get pods -n temporal

# Check frontend service
kubectl get svc -n temporal temporal-frontend-external

# View logs
kubectl logs -n temporal deployment/temporal-frontend --tail=100
```

### Database Access

```bash
# Connect to PostgreSQL
kubectl exec -it -n temporal temporal-postgres-0 -- \
  psql -U temporal -d temporal
```

## Backup & Recovery

### Database Backups
- **Automated**: Managed by Zalando PostgreSQL operator
- **Frequency**: Continuous WAL archiving
- **Retention**: Configured in postgres-operator
- **Recovery**: Via Zalando operator restore procedures

### Configuration Backups
- **Source Control**: All configuration in Git
- **ArgoCD**: Declarative, can redeploy from Git

## Troubleshooting

### Common Issues

#### Pod CrashLoopBackOff
```bash
# Check logs
kubectl logs -n temporal <pod-name> --previous

# Common causes:
# - Database connection issues
# - Configuration errors
# - Resource constraints
```

#### Can't Connect from External Client
```bash
# Verify DNS
nslookup temporal.pnats.cloud

# Verify LoadBalancer
kubectl get svc -n temporal temporal-frontend-external

# Test connectivity
nc -zv temporal.pnats.cloud 7233
```

#### Web UI Not Accessible
```bash
# Check ingress
kubectl get ingress -n temporal temporal-web

# Check certificate
kubectl get certificate -n temporal temporal-ui-tls

# Check web pods
kubectl get pods -n temporal -l app.kubernetes.io/component=web
```

## Change Log

### 2025-11-19
- ✅ Initial deployment
- ✅ Fixed web ingress configuration
- ✅ Fixed PostgreSQL authentication
- ✅ Configured LoadBalancer for gRPC access
- ✅ Enabled monitoring and dashboards
- ✅ Created all configured namespaces

## Related Documentation

- [Temporal Official Docs](https://docs.temporal.io/)
- [PostgreSQL Operator Docs](../zalando-pg.md)
- [Monitoring Setup](../prometheus.md)
- [CI/CD Architecture](../../ci-cd/README.md)
