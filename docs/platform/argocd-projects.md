# ArgoCD Projects Architecture

## Overview

The platform uses ArgoCD AppProjects to provide multi-tenant governance, RBAC, and resource isolation across 11 distinct platform layers. Each project represents a logical grouping of applications with shared concerns, dependencies, and deployment characteristics.

## Architecture Principles

### Layered Deployment Model

The platform follows a strict layered architecture where each layer builds upon the foundation provided by lower layers:

```
Layer 11: Backup & DR (600-700)
Layer 10: Application Infrastructure (525-530)
Layer 9: ML Infrastructure (6-8)
Layer 8: Data Streaming (500-510)
Layer 7: Development Workloads (510-520)
Layer 6: Developer Platform (0-390)
Layer 5: Monitoring & Observability (400-800)
Layer 4: Security & Secrets (320-360)
Layer 3: Databases (320-340)
Layer 2: Storage Foundation (100-200)
Layer 1: Infrastructure Foundation (-100 to 10)
```

### Sync Wave Ranges

Each project operates within a specific sync wave range that determines deployment order:
- **Negative waves (-100 to 0)**: Core infrastructure that must exist first
- **Low waves (0-200)**: Foundation services (networking, storage, ingress)
- **Mid waves (200-400)**: Data and security layer
- **High waves (400-600)**: Platform services and observability
- **Very high waves (600+)**: Operational tooling

### Dependency Model

Projects explicitly declare dependencies on other projects, ensuring correct deployment order:
- Infrastructure has no dependencies (foundation)
- Storage depends on infrastructure
- Databases depend on storage
- Security depends on infrastructure + databases
- All higher layers depend on appropriate lower layers

## Project Definitions

### Layer 1: Infrastructure Foundation

**Project:** `infrastructure`

**Purpose:** Core platform infrastructure providing networking, ingress, certificates, and DNS services.

**Sync Wave Range:** -100 to 10

**Dependencies:** None (foundation layer)

**Key Components:**
- **Ingress NGINX** (wave -5): HTTP/HTTPS routing and load balancing
- **Cert-Manager** (wave 0): Automated TLS certificate management with Let's Encrypt
- **External DNS** (wave 5): Automatic DNS record management for exposed services
- **MetalLB** (bootstrap): LoadBalancer implementation for bare-metal

**Namespaces:**
- `ingress-nginx`
- `cert-manager`
- `external-dns`
- `metallb-system`

**Critical Resources:**
- ClusterIssuers (cert-manager)
- IngressClasses
- IPAddressPools (MetalLB)

---

### Layer 2: Storage Foundation

**Project:** `storage`

**Purpose:** Distributed storage, database operators, and container registries.

**Sync Wave Range:** 100 to 200

**Dependencies:** infrastructure

**Key Components:**
- **Rook-Ceph Operator** (wave 100): Distributed storage orchestration
- **Rook-Ceph Cluster** (wave 110): Storage cluster with OSDs, monitors, managers
- **CloudNativePG Operator** (wave 150): PostgreSQL operator for database management
- **Redis Operator** (wave 160): Redis cluster operator
- **Harbor Registry** (wave 180): Container image registry

**Namespaces:**
- `rook-ceph` (operator and cluster)
- `cnpg-system` (CloudNativePG operator)
- `redis-operator`
- `harbor`

**Critical Resources:**
- CephCluster
- StorageClasses (Ceph RBD, CephFS)
- Clusters (PostgreSQL operator CRD)
- RedisCluster CRDs

---

### Layer 3: Databases

**Project:** `databases`

**Purpose:** Platform database instances managed by operators from storage layer.

**Sync Wave Range:** 320 to 340

**Dependencies:** storage

**Key Components:**
- **Keycloak PostgreSQL** (wave 320): Database for identity management
- **Harbor PostgreSQL** (wave 325): Database for container registry
- **Temporal PostgreSQL** (wave 330): Database for workflow engine
- **GitLab PostgreSQL** (wave 335): Database for GitLab platform
- **Platform Redis Cluster** (wave 340): Shared Redis for caching

**Namespaces:**
- `keycloak`
- `harbor`
- `temporal`
- `gitlab`
- `redis-cluster`

**Critical Resources:**
- Cluster (CloudNativePG CRD) - PostgreSQL instances
- RedisCluster - Redis cluster instances
- PersistentVolumeClaims backed by Ceph

---

### Layer 4: Security & Secrets

**Project:** `security`

**Purpose:** Identity management, secret management, and access control.

**Sync Wave Range:** 320 to 360

**Dependencies:** infrastructure, databases

**Key Components:**
- **Keycloak** (wave 320): Identity and access management (IAM)
- **Keycloak Realm Configuration** (wave 325): Realms, clients, roles
- **External Secrets Operator** (wave 330): Secret synchronization from external sources
- **Sealed Secrets** (wave 335): Encrypted secrets for GitOps
- **HashiCorp Vault** (wave 340): Secret storage and management
- **Policy Engine (OPA/Kyverno)** (wave 350): Policy enforcement

**Namespaces:**
- `keycloak`
- `external-secrets`
- `sealed-secrets`
- `vault`
- `policy-system`

**Critical Resources:**
- KeycloakRealm, KeycloakClient CRDs
- SecretStore, ExternalSecret CRDs
- SealedSecret CRDs
- ClusterPolicy, Policy CRDs

**Integration Points:**
- Keycloak integrates with ArgoCD for SSO
- External Secrets pulls from Vault
- Policy engine validates all resources

---

### Layer 5: Monitoring & Observability

**Project:** `monitoring`

**Purpose:** Observability platform for metrics, logs, traces, and dashboards.

**Sync Wave Range:** 400 to 800

**Dependencies:** storage, databases

**Key Components:**
- **Prometheus Operator** (wave 400): Metrics collection and storage
- **Prometheus Instances** (wave 410): Cluster and application monitoring
- **Grafana** (wave 420): Visualization and dashboards
- **Loki** (wave 430): Log aggregation
- **Promtail** (wave 435): Log shipping to Loki
- **Tempo** (wave 440): Distributed tracing
- **Alert Manager** (wave 450): Alert routing and notification
- **ServiceMonitors** (wave 460): Prometheus scrape targets

**Namespaces:**
- `monitoring` (Prometheus, Grafana, AlertManager)
- `loki`
- `tempo`

**Critical Resources:**
- Prometheus CRD instances
- ServiceMonitor, PodMonitor CRDs
- PrometheusRule (alerts)
- Grafana dashboards (ConfigMaps)

**Storage Requirements:**
- Prometheus: Ceph RBD (metrics storage)
- Loki: Ceph RBD (log storage)
- Tempo: Ceph RBD (trace storage)

---

### Layer 6: Developer Platform

**Project:** `developer-platform`

**Purpose:** Developer experience platform with IDP, virtualization, and cluster management.

**Sync Wave Range:** 0 to 390

**Dependencies:** infrastructure, storage, databases

**Key Components:**
- **Backstage** (wave 350): Internal Developer Portal (IDP)
- **Backstage PostgreSQL** (wave 345): Backstage database
- **KubeVirt Operator** (wave 360): Virtual machine orchestration
- **Cluster API** (wave 365): Kubernetes cluster lifecycle management
- **Crossplane** (wave 370): Infrastructure as Code operator
- **Tekton Operator** (wave 380): CI/CD pipeline operator

**Namespaces:**
- `backstage`
- `kubevirt`
- `cluster-api-system`
- `crossplane-system`
- `tekton-pipelines`

**Critical Resources:**
- VirtualMachine CRDs (KubeVirt)
- Cluster CRDs (Cluster API)
- XRDs (Crossplane resource definitions)
- Pipeline, Task CRDs (Tekton)

**Purpose:**
- Backstage serves as central developer portal
- KubeVirt enables VM workloads alongside containers
- Cluster API manages downstream Kubernetes clusters
- Crossplane provisions cloud resources

---

### Layer 7: Development Workloads

**Project:** `development-workloads`

**Purpose:** CI/CD pipelines and progressive delivery tooling.

**Sync Wave Range:** 510 to 520

**Dependencies:** developer-platform, storage

**Key Components:**
- **Tekton Pipelines** (wave 510): Pipeline definitions
- **Tekton Triggers** (wave 512): Event-driven pipeline execution
- **Argo Rollouts** (wave 515): Progressive delivery (canary, blue-green)
- **Kargo** (wave 518): Multi-stage promotion workflows

**Namespaces:**
- `tekton-pipelines`
- `argo-rollouts`
- `kargo`

**Critical Resources:**
- Pipeline, PipelineRun CRDs
- Rollout CRDs (progressive delivery)
- Kargo Stage, Freight CRDs

**Integration:**
- Tekton pipelines build and test
- Argo Rollouts deploy with progressive strategies
- Kargo manages promotion across environments

---

### Layer 8: Data Streaming

**Project:** `data-streaming`

**Purpose:** Event streaming, message brokers, and change data capture.

**Sync Wave Range:** 500 to 510

**Dependencies:** storage, monitoring

**Key Components:**
- **Strimzi Operator** (wave 500): Kafka operator
- **Kafka Clusters** (wave 502): Event streaming clusters
- **Kafka Connect** (wave 504): Connector framework
- **Debezium** (wave 506): Change Data Capture (CDC)
- **RabbitMQ Operator** (wave 508): Message broker operator
- **RabbitMQ Clusters** (wave 509): Message broker instances

**Namespaces:**
- `kafka`
- `kafka-connect`
- `rabbitmq-system`

**Critical Resources:**
- Kafka, KafkaTopic, KafkaUser CRDs
- KafkaConnect, KafkaConnector CRDs
- RabbitmqCluster CRDs

**Storage Requirements:**
- Kafka: Ceph RBD for persistent logs
- RabbitMQ: Ceph RBD for message persistence

**Use Cases:**
- Event-driven architectures
- Database change streams (Debezium)
- Asynchronous messaging

---

### Layer 9: ML Infrastructure

**Project:** `ml-infra`

**Purpose:** Machine learning infrastructure with GPU support and distributed computing.

**Sync Wave Range:** 6 to 8

**Dependencies:** infrastructure, monitoring

**Key Components:**
- **NVIDIA GPU Operator** (wave 6): GPU device management
- **KubeRay Operator** (wave 7): Ray distributed computing
- **Ray Clusters** (wave 8): ML training and serving clusters

**Namespaces:**
- `gpu-operator`
- `kuberay-system`
- `ray-clusters`

**Critical Resources:**
- RayCluster CRDs
- GPU device plugins
- RuntimeClasses for GPU workloads

**Purpose:**
- GPU scheduling and device management
- Distributed ML training with Ray
- ML model serving infrastructure

---

### Layer 10: Application Infrastructure

**Project:** `application-infra`

**Purpose:** Application-level infrastructure services like workflow orchestration.

**Sync Wave Range:** 525 to 530

**Dependencies:** databases, storage, monitoring

**Key Components:**
- **Temporal** (wave 525): Durable workflow orchestration
- **Temporal Web UI** (wave 527): Workflow visualization
- **Temporal Workers** (wave 528): Workflow execution workers

**Namespaces:**
- `temporal`

**Critical Resources:**
- Temporal service deployments
- PostgreSQL database (from databases layer)
- Elasticsearch for visibility (optional)

**Use Cases:**
- Long-running workflows
- Saga orchestration
- Reliable task execution

---

### Layer 11: Backup & Disaster Recovery

**Project:** `backup-disaster-recovery`

**Purpose:** Backup policies, disaster recovery procedures, and cluster snapshots.

**Sync Wave Range:** 600 to 700

**Dependencies:** storage

**Key Components:**
- **Velero** (wave 600): Backup and restore operator
- **Backup Schedules** (wave 610): Automated backup policies
- **Volume Snapshot Classes** (wave 620): Storage snapshot configuration
- **Restore Procedures** (wave 630): DR runbooks and automation

**Namespaces:**
- `velero`

**Critical Resources:**
- Backup, Schedule CRDs (Velero)
- VolumeSnapshotClass
- BackupStorageLocation (S3/Ceph)

**Backup Targets:**
- Kubernetes resources (all namespaces)
- Persistent volumes (via snapshots)
- Cluster configuration

**Storage:**
- Backup storage: S3-compatible (Ceph Object Gateway)

---

## RBAC Model

Each project defines three standard roles:

### Admin Role

**Permissions:**
- Full access to all applications in the project
- Can create, update, delete applications
- Can manage repositories and clusters
- Can view sync status and logs

**Group Assignment:** `platform-admins`

**Policy Example:**
```
p, proj:infrastructure:admin, applications, *, infrastructure/*, allow
p, proj:infrastructure:admin, repositories, *, *, allow
p, proj:infrastructure:admin, clusters, *, *, allow
```

### Developer Role

**Permissions:**
- View applications in the project
- Trigger manual syncs
- View repositories

**Group Assignment:** `{project-name}-developers`

**Policy Example:**
```
p, proj:infrastructure:developer, applications, get, infrastructure/*, allow
p, proj:infrastructure:developer, applications, sync, infrastructure/*, allow
p, proj:infrastructure:developer, repositories, get, *, allow
```

### Viewer Role

**Permissions:**
- Read-only access to applications
- Read-only access to repositories
- Cannot trigger syncs or make changes

**Group Assignment:** `{project-name}-viewers`, `platform-viewers`

**Policy Example:**
```
p, proj:infrastructure:viewer, applications, get, infrastructure/*, allow
p, proj:infrastructure:viewer, repositories, get, *, allow
```

## Resource Permissions

All projects currently use unrestricted permissions for operational flexibility:

```yaml
sourceRepos:
  - '*'  # Allow any Git repository

destinations:
  - namespace: '*'  # Allow deployment to any namespace
    server: https://kubernetes.default.svc

clusterResources:
  - group: '*'  # Allow any cluster-scoped resource
    kind: '*'

namespaceResources:
  - group: '*'  # Allow any namespace-scoped resource
    kind: '*'
```

This configuration provides maximum flexibility but should be refined for production environments to enforce stricter boundaries based on security requirements.

## Deployment Order

Applications are deployed in strict wave order across projects:

1. **Infrastructure (-100 to 10)**: MetalLB, Ingress, Cert-Manager, DNS
2. **ML Infra (6-8)**: GPU Operator, KubeRay (parallel with infrastructure)
3. **Storage (100-200)**: Rook-Ceph, Operators, Harbor
4. **Databases (320-340)**: PostgreSQL, Redis instances
5. **Security (320-360)**: Keycloak, Vault, External Secrets (parallel with databases)
6. **Developer Platform (0-390)**: Backstage, KubeVirt, Cluster API
7. **Monitoring (400-800)**: Prometheus, Grafana, Loki, Tempo
8. **Data Streaming (500-510)**: Kafka, RabbitMQ
9. **Development Workloads (510-520)**: Tekton, Argo Rollouts, Kargo
10. **Application Infra (525-530)**: Temporal
11. **Backup & DR (600-700)**: Velero, backup schedules

## Using the Project Chart

### Installation

Deploy all projects using Helm:

```bash
helm install argocd-projects ./platform/project-chart \
  -n argocd \
  -f ./platform/project-chart/values-production.yaml
```

### Deploying Applications to Projects

When creating ArgoCD Applications, reference the appropriate project:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "410"
spec:
  project: monitoring  # Reference the project
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 55.5.0
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Project Metadata Annotations

Applications inherit project metadata through annotations:

```yaml
annotations:
  platform.pnats.cloud/stack: monitoring
  platform.pnats.cloud/layer: observability
  platform.pnats.cloud/sync-wave-range: "400 to 800"
  platform.pnats.cloud/depends-on: storage,databases
```

## Best Practices

### 1. Respect Sync Wave Ranges

Always deploy applications within the sync wave range defined by their project:
- Infrastructure project: -100 to 10
- Applications in infrastructure should use waves within this range
- Never use sync waves outside project boundaries

### 2. Honor Dependencies

Ensure applications only depend on projects listed in their project's dependencies:
- Security project depends on infrastructure + databases
- Security applications can safely consume services from these projects
- Don't create circular dependencies

### 3. Use Appropriate Projects

Choose projects based on application characteristics:
- **Infrastructure**: Networking, ingress, certificates (affects all layers)
- **Storage**: Operators and storage backends (shared foundation)
- **Databases**: Database instances (data layer)
- **Monitoring**: Observability tools (operational visibility)
- **Application Infra**: Workflow engines, service mesh (app-level services)

### 4. RBAC Alignment

Assign users to appropriate groups based on their role:
- `platform-admins`: Full access to all projects
- `{project}-developers`: Development access to specific projects
- `{project}-viewers`: Read-only access to specific projects
- `platform-viewers`: Read-only access to all projects

### 5. Namespace Strategy

While projects allow deployment to any namespace (`namespace: '*'`):
- Prefer dedicated namespaces per stack (e.g., `monitoring`, `kafka`)
- Use namespace labels to track project ownership
- Avoid sharing namespaces across projects unless necessary

## Troubleshooting

### Application Not Syncing

**Symptom:** Application stuck in "OutOfSync" or "Unknown" state

**Diagnosis:**
1. Check if application is in correct project
2. Verify sync wave is within project's range
3. Check project RBAC permissions
4. Verify dependencies are deployed

**Solution:**
```bash
# Check project status
kubectl get appproject -n argocd infrastructure -o yaml

# Check application status
argocd app get infrastructure/cert-manager

# Check sync waves
argocd app list -p infrastructure --output wide
```

### Permission Denied Errors

**Symptom:** "permission denied" when syncing applications

**Diagnosis:**
1. Check user's group membership in Keycloak
2. Verify project role bindings
3. Check ArgoCD RBAC policy

**Solution:**
```bash
# Check user permissions
argocd account get-user-info

# Check project roles
kubectl get appproject infrastructure -n argocd -o yaml | grep -A 10 roles

# Test access
argocd app sync infrastructure/cert-manager --dry-run
```

### Dependency Issues

**Symptom:** Applications fail because dependencies aren't ready

**Diagnosis:**
1. Check sync wave ordering
2. Verify dependency projects are healthy
3. Check for circular dependencies

**Solution:**
- Ensure lower layers (infrastructure, storage) are healthy before deploying higher layers
- Use ArgoCD sync waves to enforce ordering
- Check `platform.pnats.cloud/depends-on` annotations

### Resource Conflicts

**Symptom:** Resource already exists errors

**Diagnosis:**
1. Check if resource is managed by multiple applications
2. Verify namespace ownership
3. Check for orphaned resources

**Solution:**
```bash
# Find all apps managing a resource
argocd app list --output wide | grep <resource-name>

# Check resource ownership
kubectl get <resource> -n <namespace> -o yaml | grep ownerReferences

# Clean up orphaned resources
argocd app delete <app-name> --cascade=false  # Remove app without deleting resources
kubectl delete <resource> -n <namespace>      # Manually remove resource
```

## Further Reading

- [ArgoCD Projects Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
- [ArgoCD RBAC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [ArgoCD Sync Waves and Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Multi-Tenancy with ArgoCD](https://argo-cd.readthedocs.io/en/stable/operator-manual/multi-tenancy/)
