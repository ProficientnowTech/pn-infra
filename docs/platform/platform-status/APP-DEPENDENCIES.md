# Application Dependencies Matrix

This document maps all 43 deployed ArgoCD applications and their dependencies on other platform components.

Last Updated: 2025-11-19

---

## Dependency Legend

- **Hard Dependency**: Application will not function without this component
- **Soft Dependency**: Application will function but with reduced capabilities
- **External Access**: Application is accessible from outside the cluster
- **Database**: Application requires persistent database storage
- **Storage**: Application requires persistent volume storage

---

## Platform Infrastructure (11 apps)

### 1. argocd-self
**Purpose**: GitOps continuous deployment controller
**Namespace**: argocd
**External Access**: ✅ https://argocd.pnats.cloud

**Dependencies**:
- **Hard**:
  - `cert-manager` - TLS certificate for ingress
  - `ingress-nginx` - Web UI access
  - `external-dns` - DNS management
- **Soft**:
  - `prometheus` - Metrics collection
  - `grafana` - Dashboard visualization
- **Internal**:
  - Redis (embedded) - Caching
  - Git repository - Application manifests

---

### 2. argocd-config
**Purpose**: ArgoCD ingress and configuration
**Namespace**: argocd

**Dependencies**:
- **Hard**:
  - `argocd-self` - ArgoCD deployment
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Ingress controller
  - `external-dns` - DNS record creation

---

### 3. cert-manager
**Purpose**: Automated TLS certificate management
**Namespace**: cert-manager

**Dependencies**:
- **None** - Core infrastructure component
- **Used By**: All applications with HTTPS ingress (15 apps)

---

### 4. cert-manager-config
**Purpose**: ClusterIssuer configuration for Let's Encrypt
**Namespace**: cert-manager

**Dependencies**:
- **Hard**:
  - `cert-manager` - Certificate controller

---

### 5. external-dns
**Purpose**: Automatic DNS record management from ingress/services
**Namespace**: external-dns

**Dependencies**:
- **Hard**:
  - DNS provider (Cloudflare/Route53/etc) - External service
- **Used By**: All applications with LoadBalancer or Ingress (15 apps)

---

### 6. external-dns-config
**Purpose**: External DNS configuration and credentials
**Namespace**: external-dns

**Dependencies**:
- **Hard**:
  - `external-dns` - DNS controller
  - DNS provider credentials - Secret

---

### 7. ingress-nginx
**Purpose**: HTTP/HTTPS ingress controller
**Namespace**: ingress-nginx

**Dependencies**:
- **Hard**:
  - `metallb-config` - LoadBalancer IP assignment
- **Used By**: All applications with web UI (15 apps)

---

### 8. ingress-nginx-config
**Purpose**: Ingress NGINX ConfigMap and customization
**Namespace**: ingress-nginx

**Dependencies**:
- **Hard**:
  - `ingress-nginx` - Ingress controller

---

### 9. metallb-config
**Purpose**: Load balancer IP address pool configuration
**Namespace**: metallb-system

**Dependencies**:
- **None** - Core networking component
- **Used By**:
  - `ingress-nginx` (103.110.174.18)
  - `platform-db-cluster` (103.110.174.19, 103.110.174.20)
  - `platform-kv` (103.110.174.21)
  - `temporal-frontend` (103.110.174.23)
  - CDI upload proxy (103.110.174.22)

---

### 10. external-secrets
**Purpose**: Sync secrets from external stores to Kubernetes
**Namespace**: external-secrets

**Dependencies**:
- **Hard**:
  - `vault` - Secret backend (when configured)
- **Soft**:
  - AWS Secrets Manager / GCP Secret Manager / Azure Key Vault
- **Current Status**: Deployed but not actively used

---

### 11. sealed-secrets
**Purpose**: Encrypted secrets stored in Git
**Namespace**: kube-system

**Dependencies**:
- **None** - Self-contained
- **Used By**:
  - `backstage` - GitHub token, Keycloak client secret
  - `harbor` - Admin password, database password, S3 credentials
  - `kargo` - Admin credentials
  - `temporal` - PostgreSQL credentials

---

## Storage & Data (6 apps)

### 12. rook-ceph
**Purpose**: Ceph storage orchestrator
**Namespace**: rook-ceph

**Dependencies**:
- **Hard**:
  - Raw block devices on nodes - Physical storage
- **Used By**: All applications requiring persistent storage (25+ PVCs)

---

### 13. rook-ceph-cluster
**Purpose**: Ceph cluster deployment (OSDs, MONs, MGRs)
**Namespace**: rook-ceph
**External Access**: ✅ https://ceph.pnats.cloud (dashboard)

**Dependencies**:
- **Hard**:
  - `rook-ceph` - Ceph operator
  - `cert-manager` - Dashboard TLS
  - `ingress-nginx` - Dashboard access
- **Provides**:
  - `ceph-block` StorageClass (RBD)
  - `ceph-filesystem` StorageClass (CephFS)
  - Object storage via RGW (s3.pnats.cloud)

---

### 14. zalando-pg
**Purpose**: PostgreSQL operator for database cluster management
**Namespace**: postgres-operator

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - Persistent storage
- **Soft**:
  - `prometheus` - Metrics export
- **Used By**:
  - `temporal-db` - Temporal workflows database
  - `postgres-keycloak` - Keycloak identity database
  - `postgres-shared` - Shared platform database
  - Any app requiring PostgreSQL

---

### 15. redis-operator
**Purpose**: Redis operator for cache/queue management
**Namespace**: redis-operator

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - Persistent storage (if persistence enabled)
- **Used By**:
  - `platform-kv` - Platform key-value store

---

### 16. platform-kv
**Purpose**: Platform Redis key-value store
**Namespace**: platform-kv
**External Access**: ✅ LoadBalancer 103.110.174.21:6379

**Dependencies**:
- **Hard**:
  - `redis-operator` - Redis management
  - `metallb-config` - LoadBalancer IP
  - `rook-ceph-cluster` - Persistent storage

---

### 17. temporal-db
**Purpose**: PostgreSQL cluster for Temporal workflows
**Namespace**: temporal

**Dependencies**:
- **Hard**:
  - `zalando-pg` - PostgreSQL operator
  - `rook-ceph-cluster` - 3x 50Gi persistent volumes
- **Used By**:
  - `temporal` - Workflow orchestration

---

## Security & Auth (3 apps)

### 18. vault
**Purpose**: HashiCorp Vault for secrets management
**Namespace**: vault
**External Access**: ✅ https://vault.pnats.cloud

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - 6x 10Gi volumes (3 data + 3 audit)
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access
- **Soft**:
  - `prometheus` - Metrics collection
  - `external-secrets` - Secret synchronization
- **Used By**:
  - `external-secrets` - Secret backend (ClusterSecretStore configured)
  - `crossplane` - Service account token stored

---

### 19. keycloak
**Purpose**: SSO and identity provider (OIDC/SAML)
**Namespace**: keycloak
**External Access**: ✅ https://keycloak.pnats.cloud

**Dependencies**:
- **Hard**:
  - Internal PostgreSQL (StatefulSet) - 8Gi PVC
  - `rook-ceph-cluster` - Persistent storage
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access
  - `external-dns` - DNS management
- **Soft**:
  - `prometheus` - Metrics collection
- **Used By**:
  - `backstage` - OIDC authentication (configured)
  - **Potential**: argocd, grafana, harbor, vault, kargo (not yet configured)

---

### 20. crossplane
**Purpose**: Infrastructure as Code / Cloud resource provisioning
**Namespace**: crossplane-system

**Dependencies**:
- **Hard**:
  - `vault` - Service account token (crossplane-init secret)
- **Soft**:
  - Cloud provider credentials (not configured)
- **Current Status**: Deployed but no providers installed
- **Potential Use**: PostgreSQL, Redis, S3 bucket provisioning

---

## Observability (8 apps)

### 21. prometheus
**Purpose**: Metrics collection and time-series database
**Namespace**: monitoring

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - 2x 50Gi PVCs (Prometheus + Alertmanager)
- **Soft**:
  - `cert-manager` - Alertmanager webhook TLS
- **Used By**:
  - `grafana` - Primary data source
  - `kubecost` - Cost metrics
  - All apps with ServiceMonitors

---

### 22. grafana
**Purpose**: Metrics and logs visualization
**Namespace**: monitoring
**External Access**: ✅ https://grafana.pnats.cloud

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - 10Gi PVC
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access
  - `external-dns` - DNS management
- **Soft**:
  - `prometheus` - Metrics data source
  - `loki` - Logs data source
  - `tempo` - Traces data source
- **Current Auth**: Built-in (admin/changeme) - **INSECURE**

---

### 23. loki
**Purpose**: Log aggregation system
**Namespace**: monitoring

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - Storage for logs
- **Used By**:
  - `grafana` - Logs data source
  - `promtail` - Log shipping

---

### 24. promtail
**Purpose**: Log collection agent (ships to Loki)
**Namespace**: monitoring

**Dependencies**:
- **Hard**:
  - `loki` - Log aggregation backend
- **Collects From**: All pods on all nodes (DaemonSet)

---

### 25. tempo
**Purpose**: Distributed tracing backend
**Namespace**: monitoring

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - Trace storage
- **Used By**:
  - `grafana` - Traces data source

---

### 26. kubecost
**Purpose**: Kubernetes cost monitoring and optimization
**Namespace**: kubecost
**External Access**: ✅ https://cost.pnats.cloud

**Dependencies**:
- **Hard**:
  - `prometheus` - Metrics source
  - `rook-ceph-cluster` - 50Gi PVC
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access
- **Current Auth**: None - **OPEN ACCESS**

---

### 27. uptime-kuma
**Purpose**: Uptime monitoring and status page
**Namespace**: monitoring
**External Access**: ✅ https://status.pnats.cloud

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - 5Gi PVC (SQLite database)
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access
- **Current Auth**: Built-in user accounts

---

### 28. monitors
**Purpose**: Custom Prometheus monitoring resources
**Namespace**: monitoring

**Dependencies**:
- **Hard**:
  - `prometheus` - ServiceMonitor/PrometheusRule CRDs

---

## CI/CD & Development (9 apps)

### 29. tekton-operator
**Purpose**: Tekton Operator for CI/CD infrastructure
**Namespace**: tekton-operator

**Dependencies**:
- **None** - Manages Tekton components
- **Used By**: tekton-pipelines, tekton-dashboard

---

### 30. tekton-pipelines
**Purpose**: Tekton Pipeline CRDs and controllers
**Namespace**: tekton-pipelines

**Dependencies**:
- **Hard**:
  - `tekton-operator` - Lifecycle management
  - Internal PostgreSQL - Results database
  - `rook-ceph-cluster` - PVC for PostgreSQL
- **Soft**:
  - Container registry (Harbor) - Image push/pull

---

### 31. tekton-dashboard
**Purpose**: Web UI for Tekton Pipelines
**Namespace**: tekton-pipelines
**External Access**: ✅ https://tekton.pnats.cloud

**Dependencies**:
- **Hard**:
  - `tekton-pipelines` - Pipeline backend
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access
- **Current Auth**: None - **OPEN ACCESS**

---

### 32. kargo
**Purpose**: Progressive delivery and promotion workflows
**Namespace**: kargo
**External Access**: ✅ https://kargo.pnats.cloud

**Dependencies**:
- **Hard**:
  - `argocd-self` - GitOps sync
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access
  - `sealed-secrets` - Admin credentials
- **Current Auth**: Basic auth (sealed secret)

---

### 33. argo-rollouts
**Purpose**: Progressive delivery (canary, blue-green deployments)
**Namespace**: argo-rollouts

**Dependencies**:
- **Soft**:
  - `prometheus` - Metrics for analysis
  - Ingress controller - Traffic splitting

---

### 34. harbor
**Purpose**: Container image registry
**Namespace**: harbor
**External Access**: ✅ https://registry.pnats.cloud

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - 4x PVCs (database, redis, trivy, jobservice)
  - Ceph RGW S3 - Image blob storage (s3.pnats.cloud)
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI and registry access
  - `external-dns` - DNS management
  - `sealed-secrets` - Admin password, S3 credentials
- **Soft**:
  - `prometheus` - Metrics collection
  - Trivy scanner - Vulnerability scanning
- **Internal Components**:
  - PostgreSQL (StatefulSet) - Metadata
  - Redis (StatefulSet) - Job queue

---

### 35. backstage
**Purpose**: Developer portal and service catalog
**Namespace**: backstage
**External Access**: ✅ https://backstage.pnats.cloud

**Dependencies**:
- **Hard**:
  - `keycloak` - OIDC authentication (✅ configured)
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access
  - `sealed-secrets` - GitHub token, Keycloak client secret
- **Soft**:
  - GitHub - Git provider
  - Kubernetes API - Service discovery
- **Current Database**: SQLite in-memory (not production-ready)

---

### 36. verdaccio
**Purpose**: Private NPM registry
**Namespace**: verdaccio
**External Access**: ✅ https://npm.pnats.cloud

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - 8Gi PVC
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Registry access
- **Current Auth**: NPM token-based

---

### 37. temporal
**Purpose**: Workflow orchestration platform
**Namespace**: temporal
**External Access**:
  - ✅ https://temporal-ui.pnats.cloud (Web UI)
  - ✅ temporal.pnats.cloud:7233 (gRPC LoadBalancer)

**Dependencies**:
- **Hard**:
  - `temporal-db` - PostgreSQL cluster (3 replicas, 2 databases)
  - `metallb-config` - LoadBalancer for gRPC
  - `cert-manager` - TLS for web UI
  - `ingress-nginx` - Web UI access
  - `external-dns` - DNS for both endpoints
  - `sealed-secrets` - PostgreSQL credentials
- **Soft**:
  - `prometheus` - Metrics collection
  - `grafana` - 3 dashboards (server, logs, PostgreSQL)
  - `loki` - Log aggregation
- **Current Auth**: None - **OPEN ACCESS**

---

## Virtualization & Compute (5 apps)

### 38. kubevirt
**Purpose**: Virtual machine management on Kubernetes
**Namespace**: kubevirt

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - VM disk storage
- **Soft**:
  - CDI (Containerized Data Importer) - Disk image import

---

### 39. kubevirt-manager
**Purpose**: Web UI for KubeVirt VM management
**Namespace**: kubevirt-manager
**External Access**: ✅ https://kubevirt.pnats.cloud

**Dependencies**:
- **Hard**:
  - `kubevirt` - VM backend
  - `cert-manager` - TLS certificate
  - `ingress-nginx` - Web UI access

---

### 40. clusterapi
**Purpose**: Kubernetes cluster lifecycle management
**Namespace**: capi-system

**Dependencies**:
- **Soft**:
  - Infrastructure provider (not configured)
  - Bootstrap provider (not configured)

---

### 41. strimzi-kafka-operator
**Purpose**: Apache Kafka operator
**Namespace**: kafka

**Dependencies**:
- **Hard**:
  - `rook-ceph-cluster` - Persistent storage (when Kafka clusters deployed)
- **Current Status**: Operator deployed, no Kafka clusters yet

---

### 42. postgres-operator-config
**Purpose**: PostgreSQL operator configuration
**Namespace**: postgres-operator

**Dependencies**:
- **Hard**:
  - `zalando-pg` - PostgreSQL operator

---

### 43. platform-app
**Purpose**: ArgoCD app-of-apps for platform components
**Namespace**: argocd

**Dependencies**:
- **Hard**:
  - `argocd-self` - ArgoCD deployment
- **Manages**: All 42 other applications

---

## Dependency Summary by Category

### Most Depended Upon (Core Infrastructure)
1. **rook-ceph-cluster** - 25+ apps (all with persistent storage)
2. **cert-manager** - 15 apps (all with HTTPS ingress)
3. **ingress-nginx** - 15 apps (all with web UI)
4. **external-dns** - 15 apps (all with external access)
5. **metallb-config** - 6 services (LoadBalancer IPs)

### Security Dependencies
- **sealed-secrets** - 4 apps (backstage, harbor, kargo, temporal)
- **vault** - 1 app (crossplane token), potential for all apps
- **keycloak** - 1 app (backstage OIDC), potential for 10+ apps

### Database Dependencies
- **zalando-pg** - 3 PostgreSQL clusters (temporal, keycloak, platform-db)
- **redis-operator** - 1 Redis cluster (platform-kv)
- **Internal databases** - 4 apps (Harbor, Keycloak, Tekton, Backstage)

### Observability Dependencies
- **prometheus** - 20+ apps (ServiceMonitors)
- **grafana** - 15+ dashboards across apps
- **loki** - All pods (via promtail DaemonSet)

---

## Critical Paths

If these fail, multiple apps are affected:

### 1. Rook Ceph Cluster Failure
**Impact**: 25+ apps lose persistent storage
- All databases become read-only or crash
- Log aggregation stops
- Metrics retention stops
- Container registry becomes unavailable

### 2. Ingress NGINX Failure
**Impact**: All 15 web UIs become inaccessible
- No access to ArgoCD, Grafana, Harbor, etc.
- API endpoints unreachable
- Certificate renewals may fail

### 3. Cert Manager Failure
**Impact**: TLS certificates expire
- HTTPS ingress stops working
- Browser warnings on all UIs
- Some apps may reject untrusted certificates

### 4. MetalLB Failure
**Impact**: LoadBalancer services lose external IPs
- Ingress NGINX unreachable
- Temporal gRPC endpoint unreachable
- Database external access fails

### 5. Zalando PostgreSQL Operator Failure
**Impact**: Database clusters stop functioning
- Temporal workflows fail
- Keycloak authentication unavailable
- Platform database unavailable

---

## Apps Without Dependencies (Safe to Deploy First)

1. cert-manager
2. rook-ceph
3. sealed-secrets
4. metallb-config (requires MetalLB operator, not listed here)

These are foundational and should be deployed in order before other apps.

---

## Recommended Deployment Order

1. **Layer 0**: MetalLB operator (not in ArgoCD)
2. **Layer 1**: cert-manager, rook-ceph, sealed-secrets
3. **Layer 2**: rook-ceph-cluster, metallb-config, external-dns
4. **Layer 3**: ingress-nginx, zalando-pg, redis-operator
5. **Layer 4**: vault, keycloak, external-secrets
6. **Layer 5**: argocd-self, prometheus, loki
7. **Layer 6**: All other apps (grafana, harbor, backstage, temporal, etc.)

---

## External Dependencies (Outside Cluster)

### DNS Provider
- **Required By**: external-dns
- **Purpose**: DNS record creation (A, CNAME, TXT)
- **Example**: Cloudflare, Route53, Google Cloud DNS

### Git Repository
- **Required By**: argocd-self, backstage
- **Purpose**: Source of truth for GitOps
- **Current**: GitHub (pnow-devsupreme/pn-infra)

### Container Registries
- **Required By**: All apps
- **Purpose**: Container image storage
- **Sources**:
  - Docker Hub (public images)
  - Quay.io (Red Hat images)
  - ghcr.io (GitHub packages)
  - registry.pnats.cloud (Harbor - internal)

### Let's Encrypt
- **Required By**: cert-manager
- **Purpose**: Free TLS certificates
- **Type**: ACME protocol (HTTP-01 or DNS-01 challenge)

### GitHub
- **Required By**: backstage (optional)
- **Purpose**: Git provider, authentication
- **API Token**: Stored in sealed secret

### Ceph RGW Object Storage
- **Required By**: harbor
- **Purpose**: Container image blob storage
- **Endpoint**: s3.pnats.cloud
- **Credentials**: Sealed secret

---

## End of Document

For integration plans with Keycloak, Vault, and Crossplane, see [PRODUCTION-READINESS-PLAN.md](PRODUCTION-READINESS-PLAN.md).
