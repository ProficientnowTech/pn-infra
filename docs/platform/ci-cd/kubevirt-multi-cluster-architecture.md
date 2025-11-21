# KubeVirt Multi-Cluster Architecture with GitOps

## Overview

This architecture uses KubeVirt to create isolated virtual Kubernetes clusters for each environment (dev, staging, uat, preprod, production, sandbox) running on baremetal servers. Business application workloads run in these virtual clusters while shared infrastructure services (databases, Kafka, Redis, etc.) run in the primary cluster and are accessed from virtual clusters.

---

## Architecture Diagram

```mermaid
graph TB
    subgraph "Baremetal Servers - Primary Cluster"
        subgraph "Platform Namespace"
            ARGOCD[ArgoCD<br/>Primary Instance]
            KARGO[Kargo<br/>Progressive Delivery]
            TEKTON[Tekton<br/>CI Pipeline]
            HARBOR[Harbor Registry]
            VAULT[Vault<br/>Secret Management]
            KC[Keycloak<br/>SSO/OIDC]
            CROSSPLANE[Crossplane<br/>Infrastructure Provider]
            BACKSTAGE[Backstage<br/>Developer Portal]
        end

        subgraph "Shared Services Namespace"
            POSTGRES[(PostgreSQL<br/>Multi-tenant)]
            KAFKA[Kafka Cluster]
            REDIS[Redis Cluster]
            TEMPORAL[Temporal]
            MONITORING[Prometheus/Grafana]
        end

        subgraph "KubeVirt Infrastructure"
            KUBEVIRT[KubeVirt Operator]
            CDI[Containerized Data Importer]

            subgraph "Virtual Clusters"
                VM_DEV[Dev vCluster<br/>K8s VM]
                VM_STAGING[Staging vCluster<br/>K8s VM]
                VM_UAT[UAT vCluster<br/>K8s VM]
                VM_PREPROD[PreProd vCluster<br/>K8s VM]
                VM_PROD[Production vCluster<br/>K8s VM]
                VM_SANDBOX[Sandbox vCluster<br/>K8s VM]
            end
        end
    end

    subgraph "Inside Each Virtual Cluster"
        direction TB
        VCLUSTER_INGRESS[Ingress Controller<br/>per vCluster]
        VCLUSTER_ARGOCD[ArgoCD Agent<br/>Managed by Primary]
        VCLUSTER_APPS[Business Applications<br/>user-service, payment-service, etc.]
    end

    subgraph "GitOps Repositories"
        APP_REPO[Application Monorepo<br/>Code + Dockerfiles]
        CONFIG_REPO[GitOps Config Repo<br/>Manifests + Kustomize]
        INFRA_REPO[Infrastructure Repo<br/>Crossplane Claims]
    end

    %% CI/CD Flow
    APP_REPO -->|Webhook| TEKTON
    TEKTON -->|Build & Push| HARBOR
    HARBOR -->|Update Version| CONFIG_REPO
    CONFIG_REPO -->|Watch| KARGO
    KARGO -->|Progressive Promotion| ARGOCD

    %% Infrastructure Provisioning
    INFRA_REPO -->|Crossplane Claims| CROSSPLANE
    CROSSPLANE -->|Provision| POSTGRES
    CROSSPLANE -->|Provision| REDIS
    CROSSPLANE -->|Register Credentials| VAULT

    %% Virtual Cluster Management
    ARGOCD -->|Manages| KUBEVIRT
    KUBEVIRT -->|Creates| VM_DEV
    KUBEVIRT -->|Creates| VM_STAGING
    KUBEVIRT -->|Creates| VM_UAT
    KUBEVIRT -->|Creates| VM_PREPROD
    KUBEVIRT -->|Creates| VM_PROD
    KUBEVIRT -->|Creates| VM_SANDBOX

    %% Application Deployment to vClusters
    ARGOCD -->|Deploy Apps via Agent| VCLUSTER_ARGOCD
    VCLUSTER_ARGOCD -->|Deploy| VCLUSTER_APPS

    %% Service Access
    VCLUSTER_APPS -.->|Access via Service Mesh| POSTGRES
    VCLUSTER_APPS -.->|Access via Service Mesh| KAFKA
    VCLUSTER_APPS -.->|Access via Service Mesh| REDIS
    VCLUSTER_APPS -.->|Fetch Secrets| VAULT
    VCLUSTER_APPS -.->|Authenticate| KC

    %% Developer Portal
    BACKSTAGE -->|Provision Resources| CROSSPLANE
    BACKSTAGE -->|Trigger Pipelines| TEKTON
    BACKSTAGE -->|View Deployments| ARGOCD
    BACKSTAGE -->|Authenticate| KC

    style VM_DEV fill:#e3f2fd
    style VM_STAGING fill:#fff3e0
    style VM_UAT fill:#f3e5f5
    style VM_PREPROD fill:#fff9c4
    style VM_PROD fill:#c8e6c9
    style VM_SANDBOX fill:#ffccbc
    style VAULT fill:#000000,color:#ffffff
    style KC fill:#008aaa
    style BACKSTAGE fill:#9d4edd
```

---

## 1. Primary Cluster Components

### 1.1 Platform Services (Always on Primary)

```yaml
# Primary cluster services that serve ALL environments
Platform Services:
  - ArgoCD (primary instance managing all clusters)
  - Kargo (progressive delivery orchestrator)
  - Tekton (CI pipeline builder)
  - Harbor (container registry)
  - Vault (secret management)
  - Keycloak (SSO/authentication)
  - Crossplane (infrastructure provisioner)
  - Backstage (developer portal)
  - KubeVirt (VM orchestrator)

Shared Infrastructure:
  - PostgreSQL (multi-tenant with per-env databases)
  - Kafka (with per-env topics)
  - Redis (with per-env key prefixes)
  - Temporal (workflow engine)
  - Prometheus/Grafana (monitoring)
  - Loki (logging aggregation)
```

### 1.2 KubeVirt Virtual Cluster Setup

```yaml
# kubevirt/virtual-clusters/dev-cluster.yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: dev-k8s-cluster
  namespace: kubevirt-vms
  labels:
    environment: dev
    cluster-type: kubernetes
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: dev-k8s-cluster
    spec:
      domain:
        cpu:
          cores: 8
        devices:
          disks:
            - name: containerdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
        resources:
          requests:
            memory: 32Gi
      networks:
        - name: default
          pod: {}
      volumes:
        - name: containerdisk
          containerDisk:
            image: quay.io/kubevirtci/k8s-cluster:v1.30.0
        - name: cloudinitdisk
          cloudInitNoCloud:
            networkData: |
              version: 2
              ethernets:
                enp1s0:
                  dhcp4: true
            userData: |
              #cloud-config
              hostname: dev-k8s-master
              users:
                - name: kube
                  sudo: ALL=(ALL) NOPASSWD:ALL
                  groups: sudo
                  shell: /bin/bash
                  ssh_authorized_keys:
                    - ${SSH_PUBLIC_KEY}
              runcmd:
                - curl -sfL https://get.k3s.io | sh -s - server --cluster-init
                - export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
                - kubectl apply -f https://github.com/argoproj/argo-cd/releases/latest/download/install.yaml
---
# Service for accessing the vCluster API
apiVersion: v1
kind: Service
metadata:
  name: dev-k8s-api
  namespace: kubevirt-vms
spec:
  selector:
    kubevirt.io/vm: dev-k8s-cluster
  ports:
    - name: api
      port: 6443
      targetPort: 6443
      protocol: TCP
  type: LoadBalancer
```

### 1.3 Crossplane Virtual Cluster Composition

```yaml
# crossplane/compositions/vcluster-composition.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: vcluster-k8s
  labels:
    crossplane.io/xrd: xvirtualclusters.compute.pnats.cloud
spec:
  writeConnectionSecretsToNamespace: crossplane-system

  compositeTypeRef:
    apiVersion: compute.pnats.cloud/v1alpha1
    kind: XVirtualCluster

  resources:
    # KubeVirt VirtualMachine
    - name: vm
      base:
        apiVersion: kubevirt.io/v1
        kind: VirtualMachine
        spec:
          running: true
          template:
            spec:
              domain:
                devices:
                  disks:
                    - name: containerdisk
                      disk:
                        bus: virtio
                  interfaces:
                    - name: default
                      masquerade: {}
              networks:
                - name: default
                  pod: {}
              volumes:
                - name: containerdisk
                  containerDisk:
                    image: quay.io/kubevirtci/k8s-cluster:v1.30.0
      patches:
        - fromFieldPath: spec.parameters.environment
          toFieldPath: metadata.name
          transforms:
            - type: string
              string:
                fmt: "%s-k8s-cluster"

        - fromFieldPath: spec.parameters.cpuCores
          toFieldPath: spec.template.spec.domain.cpu.cores

        - fromFieldPath: spec.parameters.memoryGi
          toFieldPath: spec.template.spec.domain.resources.requests.memory
          transforms:
            - type: string
              string:
                fmt: "%dGi"

    # Service for API access
    - name: api-service
      base:
        apiVersion: v1
        kind: Service
        spec:
          type: LoadBalancer
          ports:
            - name: api
              port: 6443
              targetPort: 6443
              protocol: TCP
      patches:
        - fromFieldPath: spec.parameters.environment
          toFieldPath: metadata.name
          transforms:
            - type: string
              string:
                fmt: "%s-k8s-api"

    # Register with ArgoCD
    - name: argocd-cluster
      base:
        apiVersion: kubernetes.crossplane.io/v1alpha1
        kind: Object
        spec:
          forProvider:
            manifest:
              apiVersion: v1
              kind: Secret
              metadata:
                namespace: argocd
                labels:
                  argocd.argoproj.io/secret-type: cluster
              type: Opaque
      patches:
        - fromFieldPath: spec.parameters.environment
          toFieldPath: spec.forProvider.manifest.metadata.name
          transforms:
            - type: string
              string:
                fmt: "%s-cluster-secret"

    # Register credentials in Vault
    - name: vault-kv
      base:
        apiVersion: kubernetes.crossplane.io/v1alpha1
        kind: Object
        spec:
          forProvider:
            manifest:
              apiVersion: batch/v1
              kind: Job
              spec:
                template:
                  spec:
                    containers:
                      - name: vault-register
                        image: vault:latest
                        command:
                          - /bin/sh
                          - -c
                          - |
                            vault kv put secret/clusters/${ENVIRONMENT} \
                              api-url=${API_URL} \
                              kubeconfig=${KUBECONFIG_B64}
      patches:
        - fromFieldPath: spec.parameters.environment
          toFieldPath: spec.forProvider.manifest.spec.template.spec.containers[0].env[0].value
```

### 1.4 Virtual Cluster Resource Claims

```yaml
# infrastructure/overlays/dev/vcluster.yaml
apiVersion: compute.pnats.cloud/v1alpha1
kind: VirtualCluster
metadata:
  name: dev-cluster
  namespace: kubevirt-vms
spec:
  parameters:
    environment: dev
    cpuCores: 8
    memoryGi: 32
    diskGb: 100
    k8sVersion: "1.30.0"
    ingressClass: nginx
  compositionSelector:
    matchLabels:
      crossplane.io/xrd: xvirtualclusters.compute.pnats.cloud
  writeConnectionSecretToRef:
    name: dev-cluster-kubeconfig
    namespace: argocd
---
# infrastructure/overlays/staging/vcluster.yaml
apiVersion: compute.pnats.cloud/v1alpha1
kind: VirtualCluster
metadata:
  name: staging-cluster
  namespace: kubevirt-vms
spec:
  parameters:
    environment: staging
    cpuCores: 12
    memoryGi: 48
    diskGb: 200
    k8sVersion: "1.30.0"
  writeConnectionSecretToRef:
    name: staging-cluster-kubeconfig
    namespace: argocd
---
# infrastructure/overlays/production/vcluster.yaml
apiVersion: compute.pnats.cloud/v1alpha1
kind: VirtualCluster
metadata:
  name: production-cluster
  namespace: kubevirt-vms
spec:
  parameters:
    environment: production
    cpuCores: 32
    memoryGi: 128
    diskGb: 500
    k8sVersion: "1.30.0"
    highAvailability: true
  writeConnectionSecretToRef:
    name: production-cluster-kubeconfig
    namespace: argocd
```

---

## 2. Secret Management with Vault

### 2.1 Vault Secret Structure

```
vault/
├── secret/
│   ├── clusters/
│   │   ├── dev/              # vCluster credentials
│   │   ├── staging/
│   │   ├── uat/
│   │   ├── preprod/
│   │   ├── production/
│   │   └── sandbox/
│   ├── shared-services/
│   │   ├── postgres/         # Shared DB credentials
│   │   ├── kafka/
│   │   ├── redis/
│   │   └── temporal/
│   ├── apps/
│   │   ├── dev/
│   │   │   ├── user-service/
│   │   │   ├── payment-service/
│   │   │   └── notification-service/
│   │   ├── staging/
│   │   ├── production/
│   │   └── sandbox/
│   └── ci-cd/
│       ├── harbor/
│       ├── github/
│       └── verdaccio/
├── database/
│   ├── config/
│   │   ├── postgres-dev
│   │   ├── postgres-staging
│   │   └── postgres-production
│   └── creds/               # Dynamic DB credentials
│       ├── dev-readwrite
│       ├── staging-readwrite
│       └── production-readwrite
└── pki/
    ├── ca                   # Root CA
    └── roles/
        ├── dev-cert
        ├── staging-cert
        └── production-cert
```

### 2.2 External Secrets Operator per vCluster

```yaml
# Each vCluster gets its own SecretStore
# This runs INSIDE the virtual cluster

# dev-vcluster/secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"  # Primary cluster Vault
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "vcluster-dev"
          serviceAccountRef:
            name: "external-secrets-sa"
---
# App secret sync INSIDE vCluster
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: user-service-secret
  namespace: default
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: vault-backend
    kind: SecretStore

  target:
    name: user-service-secret
    creationPolicy: Owner

  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: apps/dev/user-service
        property: database-url

    - secretKey: KAFKA_BROKERS
      remoteRef:
        key: shared-services/kafka
        property: brokers

    - secretKey: REDIS_URL
      remoteRef:
        key: shared-services/redis
        property: url
```

### 2.3 Cross-Cluster Service Access via Vault

```yaml
# Applications in vClusters fetch shared service endpoints from Vault

# Example: user-service deployment in dev-vcluster
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: default
spec:
  template:
    spec:
      containers:
        - name: user-service
          image: harbor.pnats.cloud/services/user-service:v1.2.3-alpha.123
          env:
            # Fetched from Vault via ExternalSecret
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: user-service-secret
                  key: DATABASE_URL

            # Points to primary cluster PostgreSQL service
            # Format: postgresql://username:password@postgres.shared-services.svc.cluster.local:5432/dev_userdb

            - name: KAFKA_BROKERS
              valueFrom:
                secretKeyRef:
                  name: user-service-secret
                  key: KAFKA_BROKERS

            # Points to primary cluster Kafka
            # Format: kafka.shared-services.svc.cluster.local:9092
```

---

## 3. Networking Between Primary and Virtual Clusters

### 3.1 Service Mesh (Istio/Linkerd) Configuration

```yaml
# Primary cluster - Shared services are exposed via ServiceMesh

# shared-services/postgres-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: shared-services
  annotations:
    service.istio.io/canonical-name: postgres
spec:
  type: ClusterIP
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
  selector:
    app: postgresql
---
# ServiceEntry to expose to vClusters
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: postgres-shared
  namespace: istio-system
spec:
  hosts:
    - postgres.shared-services.svc.cluster.local
  addresses:
    - 10.96.0.100  # ClusterIP
  ports:
    - number: 5432
      name: postgres
      protocol: TCP
  location: MESH_INTERNAL
  resolution: STATIC
  endpoints:
    - address: 10.96.0.100
```

### 3.2 Virtual Cluster Service Discovery

```yaml
# Inside dev-vCluster - CoreDNS configuration to resolve primary cluster services

# dev-vcluster/coredns-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  shared-services.server: |
    shared-services.svc.cluster.local:53 {
        forward . 10.96.0.10  # Primary cluster CoreDNS IP
    }
```

### 3.3 Network Policies

```yaml
# Primary cluster - Allow vCluster traffic to shared services

# shared-services/network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-vcluster-access
  namespace: shared-services
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    # Allow from all vCluster VMs
    - from:
        - namespaceSelector:
            matchLabels:
              kubevirt.io/vm: "*-k8s-cluster"
      ports:
        - protocol: TCP
          port: 5432  # PostgreSQL
        - protocol: TCP
          port: 9092  # Kafka
        - protocol: TCP
          port: 6379  # Redis
```

---

## 4. ArgoCD Multi-Cluster Management

### 4.1 ArgoCD Cluster Registration

```bash
# Automatically registered via Crossplane composition
# Manual registration example:

# Get vCluster kubeconfig
kubectl get secret dev-cluster-kubeconfig -n argocd -o jsonpath='{.data.kubeconfig}' | base64 -d > dev-kubeconfig.yaml

# Register with ArgoCD
argocd cluster add dev-context \
  --kubeconfig dev-kubeconfig.yaml \
  --name dev-cluster \
  --namespace argocd \
  --label environment=dev \
  --label cluster-type=virtual

# Verify
argocd cluster list
```

### 4.2 ArgoCD ApplicationSet for Multi-Cluster

```yaml
# argocd/applicationsets/user-service.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: user-service
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: dev-cluster
            url: https://dev-k8s-api.kubevirt-vms.svc:6443
            environment: dev
            replicas: "2"
            resources: "requests.cpu=100m,requests.memory=256Mi"

          - cluster: staging-cluster
            url: https://staging-k8s-api.kubevirt-vms.svc:6443
            environment: staging
            replicas: "3"
            resources: "requests.cpu=200m,requests.memory=512Mi"

          - cluster: production-cluster
            url: https://production-k8s-api.kubevirt-vms.svc:6443
            environment: production
            replicas: "5"
            resources: "requests.cpu=500m,requests.memory=1Gi"

  template:
    metadata:
      name: '{{cluster}}-user-service'
      labels:
        environment: '{{environment}}'
    spec:
      project: default

      source:
        repoURL: https://github.com/yourorg/gitops-config.git
        targetRevision: main
        path: 'overlays/{{environment}}/user-service'

        kustomize:
          commonAnnotations:
            deployed-to: '{{cluster}}'
          replicas:
            - name: user-service
              count: '{{replicas}}'

      destination:
        server: '{{url}}'
        namespace: default

      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### 4.3 Kargo Multi-Cluster Progressive Delivery

```yaml
# kargo/stages/user-service-stages.yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: user-service-dev
  namespace: kargo
spec:
  requestedFreight:
    - origin:
        kind: Warehouse
        name: user-service-warehouse
      sources:
        direct: true

  promotionMechanisms:
    argoCDAppUpdates:
      - appName: dev-cluster-user-service
        appNamespace: argocd
        sourceUpdates:
          - kustomize:
              images:
                - image: harbor.pnats.cloud/services/user-service
                  useDigest: true
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: user-service-staging
  namespace: kargo
spec:
  requestedFreight:
    - origin:
        kind: Stage
        name: user-service-dev
      sources:
        stages:
          - user-service-dev

  promotionMechanisms:
    argoCDAppUpdates:
      - appName: staging-cluster-user-service
        appNamespace: argocd
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: user-service-production
  namespace: kargo
spec:
  requestedFreight:
    - origin:
        kind: Stage
        name: user-service-preprod
      sources:
        stages:
          - user-service-preprod

  promotionMechanisms:
    argoCDAppUpdates:
      - appName: production-cluster-user-service
        appNamespace: argocd

  # Production requires manual approval
  promotionTemplate:
    spec:
      steps:
        - uses: git-clone
        - uses: git-clear
        - uses: kustomize-set-image
        - uses: git-commit
        - uses: argocd-update
          config:
            apps:
              - name: production-cluster-user-service
                namespace: argocd
```

---

## 5. Crossplane Infrastructure Provisioning

### 5.1 Per-Environment Database Provisioning

```yaml
# infrastructure/dev/database.yaml
apiVersion: database.pnats.cloud/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: dev-database
  namespace: dev
spec:
  parameters:
    environment: dev
    size: small
    storageGB: 20
    enableBackup: false
    vaultPath: secret/database/dev
    # Database will be created in primary cluster PostgreSQL
    primaryClusterDB: true
    multiTenant: true
  compositionSelector:
    matchLabels:
      crossplane.io/xrd: xpostgresqlinstances.database.pnats.cloud
  writeConnectionSecretToRef:
    name: postgres-connection
    namespace: vault  # Stored in Vault, then synced to vCluster
```

### 5.2 Crossplane PostgreSQL Composition (Multi-tenant)

```yaml
# crossplane/compositions/postgres-multitenant-composition.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: postgres-multitenant
spec:
  compositeTypeRef:
    apiVersion: database.pnats.cloud/v1alpha1
    kind: XPostgreSQLInstance

  resources:
    # Create database in existing PostgreSQL instance
    - name: database
      base:
        apiVersion: postgresql.sql.crossplane.io/v1alpha1
        kind: Database
        spec:
          forProvider:
            encoding: UTF8
          providerConfigRef:
            name: postgres-provider  # Points to primary cluster PostgreSQL
      patches:
        - fromFieldPath: spec.parameters.environment
          toFieldPath: metadata.name
          transforms:
            - type: string
              string:
                fmt: "%s_userdb"

    # Create dedicated user
    - name: user
      base:
        apiVersion: postgresql.sql.crossplane.io/v1alpha1
        kind: Role
        spec:
          forProvider:
            login: true
          writeConnectionSecretToRef:
            namespace: crossplane-system
      patches:
        - fromFieldPath: spec.parameters.environment
          toFieldPath: spec.forProvider.name
          transforms:
            - type: string
              string:
                fmt: "%s_user"

    # Store credentials in Vault
    - name: vault-secret
      base:
        apiVersion: kubernetes.crossplane.io/v1alpha1
        kind: Object
        spec:
          forProvider:
            manifest:
              apiVersion: batch/v1
              kind: Job
              spec:
                template:
                  spec:
                    serviceAccountName: crossplane-vault-sa
                    containers:
                      - name: vault-store
                        image: vault:latest
                        env:
                          - name: VAULT_ADDR
                            value: "http://vault.vault.svc:8200"
                        command:
                          - /bin/sh
                          - -c
                          - |
                            export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login role=crossplane jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token)

                            vault kv put secret/apps/${ENVIRONMENT}/database \
                              host=postgres.shared-services.svc.cluster.local \
                              port=5432 \
                              database=${DB_NAME} \
                              username=${DB_USER} \
                              password=${DB_PASSWORD}
```

---

## 6. Backstage Developer Portal Integration

### 6.1 Backstage Software Catalog

```yaml
# backstage/catalog/user-service.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: user-service
  description: User management microservice
  tags:
    - typescript
    - microservice
    - backend
  annotations:
    github.com/project-slug: yourorg/application-monorepo
    backstage.io/techdocs-ref: dir:.
    argocd/app-selector: app.kubernetes.io/name=user-service
    vault/secret-path: apps/*/user-service
    crossplane/managed: "true"
spec:
  type: service
  lifecycle: production
  owner: backend-team
  system: user-management
  providesApis:
    - user-api
  consumesApis:
    - auth-api
  dependsOn:
    - resource:postgres-dev
    - resource:postgres-staging
    - resource:postgres-production
---
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: postgres-dev
  description: Development PostgreSQL database
spec:
  type: database
  owner: platform-team
  system: user-management
  dependsOn:
    - component:crossplane
```

### 6.2 Backstage Templates (Software Templates)

```yaml
# backstage/templates/new-microservice.yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: typescript-microservice
  title: Create a new TypeScript Microservice
  description: Scaffold a new TypeScript microservice with GitOps config
spec:
  owner: platform-team
  type: service

  parameters:
    - title: Service Information
      required:
        - name
        - description
        - owner
      properties:
        name:
          title: Service Name
          type: string
          description: Name of the microservice
          pattern: '^[a-z0-9-]+$'
        description:
          title: Description
          type: string
        owner:
          title: Owner
          type: string
          ui:field: OwnerPicker

    - title: Infrastructure Requirements
      properties:
        needsDatabase:
          title: Needs Database?
          type: boolean
          default: true
        needsRedis:
          title: Needs Redis?
          type: boolean
          default: false
        needsKafka:
          title: Needs Kafka?
          type: boolean
          default: false

  steps:
    # 1. Fetch base template
    - id: fetch
      name: Fetch Base Template
      action: fetch:template
      input:
        url: ./skeleton
        values:
          name: ${{ parameters.name }}
          description: ${{ parameters.description }}
          owner: ${{ parameters.owner }}

    # 2. Create GitHub repository
    - id: publish
      name: Publish to GitHub
      action: publish:github
      input:
        repoUrl: github.com?owner=yourorg&repo=${{ parameters.name }}
        description: ${{ parameters.description }}
        defaultBranch: main

    # 3. Provision infrastructure with Crossplane
    - id: provision-database
      if: ${{ parameters.needsDatabase }}
      name: Provision Database
      action: crossplane:create
      input:
        apiVersion: database.pnats.cloud/v1alpha1
        kind: PostgreSQLInstance
        metadata:
          name: ${{ parameters.name }}-dev-db
          namespace: dev
        spec:
          parameters:
            environment: dev
            size: small
            storageGB: 20

    # 4. Create GitOps manifests
    - id: create-gitops
      name: Create GitOps Config
      action: fetch:template
      input:
        url: ./gitops-skeleton
        targetPath: ./gitops
        values:
          name: ${{ parameters.name }}
          repository: ${{ steps.publish.output.remoteUrl }}

    # 5. Publish GitOps config
    - id: publish-gitops
      name: Publish GitOps Config
      action: publish:github:pull-request
      input:
        repoUrl: github.com?owner=yourorg&repo=gitops-config
        title: 'Add ${{ parameters.name }} service'
        branchName: add-${{ parameters.name }}
        description: |
          # New Service: ${{ parameters.name }}

          ${{ parameters.description }}

          Infrastructure provisioned:
          - Database: ${{ parameters.needsDatabase }}
          - Redis: ${{ parameters.needsRedis }}
          - Kafka: ${{ parameters.needsKafka }}

    # 6. Register with Backstage catalog
    - id: register
      name: Register Component
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
        catalogInfoPath: '/catalog-info.yaml'

    # 7. Store secrets in Vault
    - id: vault-secrets
      name: Initialize Vault Secrets
      action: vault:write
      input:
        path: secret/apps/dev/${{ parameters.name }}
        data:
          database-url: "postgresql://postgres.shared-services.svc.cluster.local:5432/${{ parameters.name }}-dev-db"
          api-key: ${{ secrets.generateApiKey() }}

  output:
    links:
      - title: Repository
        url: ${{ steps.publish.output.remoteUrl }}
      - title: GitOps PR
        url: ${{ steps['publish-gitops'].output.remoteUrl }}
      - title: ArgoCD
        url: https://argocd.pnats.cloud/applications/${{ parameters.name }}
      - title: Vault Secrets
        url: https://vault.pnats.cloud/ui/vault/secrets/secret/show/apps/dev/${{ parameters.name }}
```

### 6.3 Backstage Plugins Configuration

```typescript
// backstage/packages/app/src/App.tsx
import { ArgoCD Plugin } from '@backstage/plugin-argocd';
import { Kubernetes Plugin } from '@backstage/plugin-kubernetes';
import { Vault Plugin } from '@backstage/plugin-vault';
import { Crossplane Plugin } from '@internal/backstage-plugin-crossplane';
import { Tekton Plugin } from '@backstage/plugin-tekton';

const app = createApp({
  plugins: [
    // ... other plugins

    // ArgoCD - show deployments across all vClusters
    createPlugin({
      id: 'argocd',
      register({ router }) {
        router.addRoute({
          path: '/argocd',
          Component: ArgoCDOverviewPage,
        });
      },
    }),

    // Kubernetes - show pods in all vClusters
    createPlugin({
      id: 'kubernetes',
      register({ router }) {
        router.addRoute({
          path: '/kubernetes',
          Component: KubernetesOverviewPage,
        });
      },
    }),

    // Vault - show and manage secrets
    createPlugin({
      id: 'vault',
      register({ router }) {
        router.addRoute({
          path: '/vault',
          Component: VaultSecretsPage,
        });
      },
    }),

    // Crossplane - provision infrastructure
    createPlugin({
      id: 'crossplane',
      register({ router }) {
        router.addRoute({
          path: '/infrastructure',
          Component: CrossplaneResourcesPage,
        });
      },
    }),

    // Tekton - view CI pipeline runs
    createPlugin({
      id: 'tekton',
      register({ router }) {
        router.addRoute({
          path: '/ci-pipelines',
          Component: TektonPipelineRunsPage,
        });
      },
    }),
  ],
});
```

### 6.4 Backstage Kubernetes Cluster Configuration

```yaml
# backstage/app-config.yaml
kubernetes:
  serviceLocatorMethod:
    type: 'multiTenant'
  clusterLocatorMethods:
    - type: 'config'
      clusters:
        - name: primary
          url: https://kubernetes.default.svc
          authProvider: 'serviceAccount'
          serviceAccountToken: ${K8S_SA_TOKEN}
          dashboardUrl: https://dashboard.pnats.cloud
          dashboardApp: primary

        - name: dev-vcluster
          url: https://dev-k8s-api.kubevirt-vms.svc:6443
          authProvider: 'serviceAccount'
          serviceAccountToken: ${DEV_VCLUSTER_TOKEN}
          dashboardUrl: https://dashboard.pnats.cloud
          dashboardApp: dev

        - name: staging-vcluster
          url: https://staging-k8s-api.kubevirt-vms.svc:6443
          authProvider: 'serviceAccount'
          serviceAccountToken: ${STAGING_VCLUSTER_TOKEN}

        - name: production-vcluster
          url: https://production-k8s-api.kubevirt-vms.svc:6443
          authProvider: 'serviceAccount'
          serviceAccountToken: ${PRODUCTION_VCLUSTER_TOKEN}

argocd:
  username: ${ARGOCD_USERNAME}
  password: ${ARGOCD_PASSWORD}
  appLocatorMethods:
    - type: 'config'
      instances:
        - name: primary
          url: https://argocd.pnats.cloud
          token: ${ARGOCD_TOKEN}

vault:
  baseUrl: https://vault.pnats.cloud
  token: ${VAULT_TOKEN}
  secretEngine: kv-v2
  kvVersion: 2

crossplane:
  baseUrl: https://kubernetes.default.svc
  token: ${K8S_SA_TOKEN}

auth:
  environment: production
  providers:
    oidc:
      production:
        clientId: ${KEYCLOAK_CLIENT_ID}
        clientSecret: ${KEYCLOAK_CLIENT_SECRET}
        metadataUrl: https://keycloak.pnats.cloud/realms/pnats/.well-known/openid-configuration
        prompt: auto
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityProfileEmail
            - resolver: emailLocalPartMatchingUserEntityName
```

---

## 7. Environment Matrix

| Environment | vCluster Resources | App Replicas | Database | Ingress Domain | Auto-Deploy | Maturity |
|-------------|-------------------|--------------|----------|----------------|-------------|----------|
| **Dev** | 8 CPU, 32Gi RAM | 2 | dev_* (shared PG) | *.dev.pnats.cloud | ✅ Auto | Alpha |
| **Staging** | 12 CPU, 48Gi RAM | 3 | staging_* (shared PG) | *.staging.pnats.cloud | ✅ Auto | Alpha |
| **UAT** | 12 CPU, 48Gi RAM | 3 | uat_* (shared PG) | *.uat.pnats.cloud | ❌ Manual | Beta |
| **PreProd** | 24 CPU, 96Gi RAM | 4 | preprod_* (shared PG) | *.preprod.pnats.cloud | ❌ Manual | Beta |
| **Production** | 32 CPU, 128Gi RAM | 5+ (HPA) | prod_* (shared PG) | *.pnats.cloud | ❌ Manual | Stable |
| **Sandbox** | 16 CPU, 64Gi RAM | 2 | sandbox_* (test data) | *.sandbox.pnats.cloud | ⏰ Daily | Stable Clone |

---

## 8. GitOps Repository Structure

```
gitops-config/
├── infrastructure/           # Crossplane claims
│   ├── vclusters/
│   │   ├── dev.yaml
│   │   ├── staging.yaml
│   │   ├── uat.yaml
│   │   ├── preprod.yaml
│   │   ├── production.yaml
│   │   └── sandbox.yaml
│   ├── databases/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   └── shared-services/
│       ├── postgres.yaml
│       ├── kafka.yaml
│       └── redis.yaml
├── base/                    # Base application manifests
│   ├── user-service/
│   ├── payment-service/
│   └── notification-service/
├── overlays/                # Environment-specific overlays
│   ├── dev/
│   ├── staging/
│   ├── uat/
│   ├── preprod/
│   ├── production/
│   └── sandbox/
├── argocd/
│   ├── projects/
│   ├── applications/
│   └── applicationsets/
└── kargo/
    ├── warehouses/
    ├── stages/
    └── promotions/
```

---

## Summary

This architecture provides:

✅ **Isolated Virtual Clusters** - Per-environment K8s clusters on KubeVirt VMs
✅ **Shared Infrastructure** - Databases, Kafka, Redis in primary cluster
✅ **Centralized GitOps** - Single ArgoCD managing all clusters
✅ **Secret Management** - Vault with per-cluster secret stores
✅ **Infrastructure as Code** - Crossplane provisioning vClusters and databases
✅ **Developer Portal** - Backstage for self-service infrastructure
✅ **SSO/OIDC** - Keycloak for authentication across all tools
✅ **Progressive Delivery** - Kargo orchestrating promotions across vClusters
✅ **Network Isolation** - Virtual clusters with controlled access to shared services
✅ **Cost Efficiency** - Right-sized VMs per environment
✅ **Scalability** - Baremetal resources efficiently utilized
✅ **Strict GitOps** - All changes through Git, no manual kubectl
