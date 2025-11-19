# Platform Status Change Log

## 2025-11-19

### New Deployments
- **Temporal** - Workflow orchestration platform
  - Version: 1.24.2
  - 3-node PostgreSQL cluster (Zalando operator)
  - LoadBalancer for external gRPC access
  - Configured namespaces: default, pnats, pnats-staging, pnats-dev
  - Monitoring enabled with 3 Grafana dashboards

### Updates
- **Grafana** - Enabled sidecar for automatic dashboard discovery
  - Now automatically loads dashboards from ConfigMaps
  - Searches all namespaces
  - Successfully loaded Temporal dashboards

### Fixes
- **Temporal** - Resolved multiple deployment issues
  - Fixed web ingress hosts format for upstream chart compatibility
  - Corrected PostgreSQL secret reference (temporal user vs postgres user)
  - Removed duplicate TEMPORAL_ADDRESS environment variable
  - Updated admin-tools image tag to available version

### Infrastructure
- **External DNS** - Successfully managing DNS for new services
  - temporal.pnats.cloud → 103.110.174.23
  - temporal-ui.pnats.cloud → NGINX ingress

### Documentation
- Created comprehensive platform-status documentation structure
  - README with overview and dependency graph
  - Detailed documentation for Temporal
  - Detailed documentation for Grafana
  - Template for documenting other charts

## Previous Changes

### 2025-11-XX (Earlier)
- Initial platform deployment
- Core infrastructure: ArgoCD, Prometheus, Grafana, Loki
- Storage: Rook Ceph cluster
- Networking: NGINX Ingress, MetalLB, External DNS
- Security: Cert Manager, Vault, Keycloak
- CI/CD: Tekton, Argo Rollouts, Kargo
- Databases: Zalando PostgreSQL Operator, Redis Operator
- Messaging: Strimzi Kafka Operator
- Monitoring: Prometheus, Grafana, Loki, Tempo
- Container Registry: Harbor
- Cost Management: Kubecost
- Uptime Monitoring: Uptime Kuma
