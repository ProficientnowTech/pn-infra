The Tekton + Kargo + ArgoCD combination does make sense and is becoming increasingly popular for sophisticated GitOps workflows. Here's what each handles:
The Stack Breakdown
Tekton - CI/Build pipeline

Runs your build, test, and image creation pipelines
Native Kubernetes CRDs (very k8s-native)
Produces artifacts and container images

ArgoCD - GitOps deployment engine

Syncs manifests from Git to clusters
Manages the actual deployment to your staging/production clusters
Provides visualization and sync status

Kargo - Progressive delivery/promotion orchestrator

Automates promotion between environments (staging → production)
Handles more complex deployment strategies (blue/green, canary)
Manages "freight" (collection of artifacts) across stages
Newer tool specifically designed to bridge the gap between CI and CD

Does This Make Sense for You?
Yes, if:

You need automated promotion workflows (e.g., auto-promote from staging to prod after tests pass)
You want sophisticated deployment strategies beyond basic sync
You need to coordinate deployments across your two regions
You want to track what versions are in each environment

The value: Kargo fills a gap that ArgoCD alone doesn't handle well - intelligent promotion logic. ArgoCD syncs what's in Git, but Kargo decides when and how to update Git with new versions.
Alternatives to Consider
1. Flux + Flagger (Instead of ArgoCD + Kargo)
Tekton (CI) → Flux (CD) + Flagger (Progressive Delivery)
```
- **Flux**: ArgoCD's main competitor, more GitOps-purist
- **Flagger**: Mature progressive delivery tool (canary, blue/green, A/B)
- All CNCF projects, well-maintained
- Flux has better multi-tenancy

### 2. **Jenkins X / Keptn** (All-in-one)
- More opinionated, less modular
- Probably overkill for your setup

### 3. **Simpler: Just ArgoCD + ArgoCD Image Updater**
```
Tekton (CI) → ArgoCD + Image Updater
```
- ArgoCD Image Updater auto-updates image tags in Git
- Good enough for simpler promotion workflows
- Less complexity than adding Kargo

### 4. **GitLab CI/CD + ArgoCD**
- Replace Tekton with GitLab CI (if you use GitLab)
- More integrated experience
- GitLab can be self-hosted

## My Recommendation for Your Setup

Given your requirements (on-prem, two regions, HA production, staging):
```
Tekton → Kargo → ArgoCD (one per region)
```

**Why this works:**
1. **Tekton**: Perfect for self-hosted CI, pure K8s-native
2. **Kargo**: Handles promotion from staging → production intelligently
3. **ArgoCD per region**: Deploy one ArgoCD instance per cluster/region for true HA

**Architecture:**
```
┌─────────┐
│ Tekton  │ (builds & tests in staging cluster)
└────┬────┘
     │ publishes images
     ↓
┌─────────┐
│  Kargo  │ (promotion orchestrator)
└────┬────┘
     │ updates Git manifests
     ↓
┌──────────────────────────────┐
│  Git Repository (manifests)  │
└──────────┬───────────────────┘
           │
     ┌─────┴──────┐
     ↓            ↓
┌─────────┐  ┌─────────┐
│ ArgoCD  │  │ ArgoCD  │
│ Region1 │  │ Region2 │
│ (prod)  │  │ (prod)  │
└─────────┘  └─────────┘
Alternative if you want simpler:
Skip Kargo initially, use ArgoCD ApplicationSets for multi-cluster deployment, and manually promote by updating Git tags/branches.
Would you like me to help you design the specific architecture for your two-region setup, or dive deeper into any of these tools?NHow to deploy tekton via charts to argocdHere's how to deploy Tekton via ArgoCD using Helm charts:
Option 1: Using Community Helm Chart (Recommended)
The cdfoundation/tekton-helm-chart is the most maintained community chart.
Step 1: Create ArgoCD Application
yaml# argocd/apps/tekton-pipelines.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tekton-pipelines
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://cdfoundation.github.io/tekton-helm-chart
    chart: tekton-pipelines
    targetRevision: 0.59.0  # Check latest version
    helm:
      values: |
        # Enable HA for production
        controller:
          replicas: 2
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
        
        webhook:
          replicas: 2
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
        
        # Storage for pipeline artifacts
        persistence:
          enabled: true
          storageClass: "local-path"  # Adjust for your storage
          size: 10Gi

  destination:
    server: https://kubernetes.default.svc
    namespace: tekton-pipelines

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
Step 2: Deploy Additional Tekton Components
Tekton Triggers (for webhooks):
yaml# argocd/apps/tekton-triggers.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tekton-triggers
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://cdfoundation.github.io/tekton-helm-chart
    chart: tekton-triggers
    targetRevision: 0.25.0
    helm:
      values: |
        controller:
          replicas: 2
        webhook:
          replicas: 2
        interceptors:
          replicas: 2

  destination:
    server: https://kubernetes.default.svc
    namespace: tekton-pipelines

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Tekton Dashboard (optional but useful):
yaml# argocd/apps/tekton-dashboard.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tekton-dashboard
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://cdfoundation.github.io/tekton-helm-chart
    chart: tekton-dashboard
    targetRevision: 0.41.0
    helm:
      values: |
        dashboard:
          replicas: 1
          ingress:
            enabled: true
            className: nginx
            hosts:
              - host: tekton.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix

  destination:
    server: https://kubernetes.default.svc
    namespace: tekton-pipelines

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
Option 2: Using Official YAML Manifests (More Control)
If you prefer the official releases:
yaml# argocd/apps/tekton-pipelines.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tekton-pipelines
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/tektoncd/pipeline
    targetRevision: v0.59.0  # Pin to specific version
    path: config
    directory:
      recurse: true

  destination:
    server: https://kubernetes.default.svc
    namespace: tekton-pipelines

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

## Option 3: Create Your Own Helm Chart Wrapper (Most Flexible)

For better control in your GitOps repo:

### Repository Structure:
```
gitops-repo/
├── charts/
│   └── tekton/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-staging.yaml
│       └── values-production.yaml
└── apps/
    └── tekton.yaml
Chart.yaml:
yaml# charts/tekton/Chart.yaml
apiVersion: v2
name: tekton
version: 1.0.0
dependencies:
  - name: tekton-pipelines
    version: 0.59.0
    repository: https://cdfoundation.github.io/tekton-helm-chart
  - name: tekton-triggers
    version: 0.25.0
    repository: https://cdfoundation.github.io/tekton-helm-chart
  - name: tekton-dashboard
    version: 0.41.0
    repository: https://cdfoundation.github.io/tekton-helm-chart
values.yaml:
yaml# charts/tekton/values.yaml
tekton-pipelines:
  controller:
    replicas: 1
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
  
  webhook:
    replicas: 1

tekton-triggers:
  controller:
    replicas: 1
  webhook:
    replicas: 1

tekton-dashboard:
  dashboard:
    replicas: 1
values-production.yaml:
yaml# charts/tekton/values-production.yaml
tekton-pipelines:
  controller:
    replicas: 3  # HA for production
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 2000m
        memory: 2Gi
    
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: tekton-pipelines-controller
              topologyKey: kubernetes.io/hostname
  
  webhook:
    replicas: 3

tekton-triggers:
  controller:
    replicas: 2
  webhook:
    replicas: 2
  interceptors:
    replicas: 2

tekton-dashboard:
  dashboard:
    replicas: 2
ArgoCD Application:
yaml# apps/tekton.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tekton
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/yourorg/gitops-repo
    targetRevision: main
    path: charts/tekton
    helm:
      valueFiles:
        - values-production.yaml  # or values-staging.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: tekton-pipelines

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
Multi-Region Deployment with ApplicationSet
For deploying to both regions:
yaml# argocd/appsets/tekton-appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tekton
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: staging
            url: https://kubernetes.default.svc
            values: values-staging.yaml
          - cluster: production-region1
            url: https://prod-region1.k8s.local
            values: values-production.yaml
          - cluster: production-region2
            url: https://prod-region2.k8s.local
            values: values-production.yaml
  
  template:
    metadata:
      name: 'tekton-{{cluster}}'
      labels:
        environment: '{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/yourorg/gitops-repo
        targetRevision: main
        path: charts/tekton
        helm:
          valueFiles:
            - '{{values}}'
      
      destination:
        server: '{{url}}'
        namespace: tekton-pipelines
      
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
Apply to ArgoCD
bash# Apply the application
kubectl apply -f argocd/apps/tekton-pipelines.yaml

# Or if using ApplicationSet
kubectl apply -f argocd/appsets/tekton-appset.yaml

# Check sync status
argocd app get tekton-pipelines

# Manual sync if needed
argocd app sync tekton-pipelines
Post-Deployment Configuration
After Tekton is deployed, you'll want to configure:

Service Account with registry access:

yaml# tekton-config/service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-builder
  namespace: tekton-pipelines
secrets:
  - name: docker-registry-secret

PVC for workspace storage:

yaml# tekton-config/storage.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tekton-workspace
  namespace: tekton-pipelines
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 50Gi
Monitoring & Verification
bash# Check pods
kubectl get pods -n tekton-pipelines

# Check webhooks are ready
kubectl get mutatingwebhookconfigurations
kubectl get validatingwebhookconfigurations

# Access dashboard (if deployed)
kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097
Would you like me to help you set up the actual Tekton pipelines for your CI workflows, or configure the integration with your container registry?NHow to deploy kargoHere's how to deploy Kargo via ArgoCD for your setup:
Option 1: Using Official Helm Chart (Recommended)
Step 1: Basic Kargo Deployment
yaml# argocd/apps/kargo.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kargo
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://charts.kargo.io
    chart: kargo
    targetRevision: 0.9.0  # Check for latest version
    helm:
      values: |
        # API Server configuration
        api:
          enabled: true
          replicas: 2  # HA setup
          
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          
          # Ingress for Kargo UI
          ingress:
            enabled: true
            className: nginx
            host: kargo.yourdomain.local
            tls:
              enabled: true
              secretName: kargo-tls
          
          # Admin account
          adminAccount:
            enabled: true
            passwordHash: "$2a$10$..."  # bcrypt hash of your password
            tokenSigningKey: "your-secure-random-key"  # Generate with: openssl rand -base64 32

        # Controller configuration
        controller:
          enabled: true
          replicas: 2  # HA setup
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          
          # ArgoCD integration
          argocd:
            urls:
              - https://argocd.yourdomain.local
            watchArgocdNamespace: argocd
          
          # Git credentials for promotion commits
          gitClient:
            signingKeyType: gpg  # or 'ssh'
          
          # Webhook configuration
          webhooks:
            enabled: true

        # Management controller (handles garbage collection, etc)
        managementController:
          enabled: true
          replicas: 1
          
          resources:
            requests:
              cpu: 50m
              memory: 128Mi

        # Webhooks server
        webhooksServer:
          enabled: true
          replicas: 2
          
          resources:
            requests:
              cpu: 50m
              memory: 128Mi

        # Database (PostgreSQL for production)
        postgresql:
          enabled: true
          auth:
            password: "your-secure-password"
            database: kargo
          
          primary:
            persistence:
              enabled: true
              storageClass: "local-path"  # Adjust for your storage
              size: 10Gi
            
            resources:
              requests:
                cpu: 100m
                memory: 256Mi

        # RBAC
        rbac:
          installClusterRoles: true
          installClusterRoleBindings: true

  destination:
    server: https://kubernetes.default.svc
    namespace: kargo

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # Allow HPA to manage replicas
```

## Option 2: Using Your Own Chart Wrapper

For better control across environments:

### Repository Structure:
```
gitops-repo/
├── charts/
│   └── kargo/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-staging.yaml
│       └── values-production.yaml
└── apps/
    └── kargo.yaml
Chart.yaml:
yaml# charts/kargo/Chart.yaml
apiVersion: v2
name: kargo
version: 1.0.0
dependencies:
  - name: kargo
    version: 0.9.0
    repository: https://charts.kargo.io
values.yaml (base):
yaml# charts/kargo/values.yaml
kargo:
  api:
    enabled: true
    replicas: 1
    
    adminAccount:
      enabled: true
      passwordHash: "$2a$10$Vj7kBz8nF9xq4HqYxB7wH.XqZQp8YqXJ5Zf1J9xq4HqYxB7wH.XqZ"
      tokenSigningKey: "change-this-in-production"
    
    ingress:
      enabled: false  # Enable per environment

  controller:
    enabled: true
    replicas: 1
    
    argocd:
      urls:
        - https://argocd.yourdomain.local
      watchArgocdNamespace: argocd

  managementController:
    enabled: true
    replicas: 1

  webhooksServer:
    enabled: true
    replicas: 1

  postgresql:
    enabled: true
    auth:
      password: "changeme"
      database: kargo
    primary:
      persistence:
        enabled: true
        size: 5Gi
values-staging.yaml:
yaml# charts/kargo/values-staging.yaml
kargo:
  api:
    replicas: 1
    ingress:
      enabled: true
      className: nginx
      host: kargo-staging.yourdomain.local
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-staging

  controller:
    replicas: 1
    argocd:
      urls:
        - https://argocd-staging.yourdomain.local

  postgresql:
    primary:
      persistence:
        storageClass: "local-path"
        size: 5Gi
values-production.yaml:
yaml# charts/kargo/values-production.yaml
kargo:
  api:
    replicas: 3  # HA
    
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 1Gi
    
    ingress:
      enabled: true
      className: nginx
      host: kargo.yourdomain.local
      tls:
        enabled: true
        secretName: kargo-tls
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
    
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/component: api
              topologyKey: kubernetes.io/hostname

  controller:
    replicas: 3  # HA
    
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 2000m
        memory: 2Gi
    
    argocd:
      urls:
        - https://argocd-region1.yourdomain.local
        - https://argocd-region2.yourdomain.local
      watchArgocdNamespace: argocd

  managementController:
    replicas: 2
    
    resources:
      requests:
        cpu: 100m
        memory: 256Mi

  webhooksServer:
    replicas: 3
    
    resources:
      requests:
        cpu: 100m
        memory: 128Mi

  postgresql:
    enabled: true
    auth:
      existingSecret: kargo-postgres-secret  # Create separately
      database: kargo
    
    primary:
      persistence:
        enabled: true
        storageClass: "ceph-rbd"  # Use your HA storage
        size: 20Gi
      
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 1000m
          memory: 1Gi
      
      # PostgreSQL HA
      standby:
        enabled: true
        replicaCount: 2
Step 2: Create Required Secrets
Git Credentials for Kargo:
yaml# kargo-config/git-credentials.yaml
apiVersion: v1
kind: Secret
metadata:
  name: kargo-git-credentials
  namespace: kargo
  labels:
    kargo.akuity.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/yourorg/gitops-repo
  username: your-username
  password: your-pat-token  # Personal Access Token
PostgreSQL Secret (for production):
yaml# kargo-config/postgres-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: kargo-postgres-secret
  namespace: kargo
type: Opaque
stringData:
  password: "your-very-secure-password"
Container Registry Credentials:
yaml# kargo-config/registry-credentials.yaml
apiVersion: v1
kind: Secret
metadata:
  name: kargo-registry-credentials
  namespace: kargo
  labels:
    kargo.akuity.io/secret-type: repository
type: Opaque
stringData:
  type: image
  url: registry.yourdomain.local
  username: kargo
  password: registry-token
Step 3: Deploy with ArgoCD
yaml# apps/kargo.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kargo
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/yourorg/gitops-repo
    targetRevision: main
    path: charts/kargo
    helm:
      valueFiles:
        - values-production.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: kargo

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true

  # Sync waves for ordered deployment
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
Step 4: Multi-Region with ApplicationSet
yaml# argocd/appsets/kargo-appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: kargo
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: staging
            url: https://kubernetes.default.svc
            values: values-staging.yaml
            argocdUrl: https://argocd-staging.yourdomain.local
          
          # Production regions - deploy Kargo in one cluster only
          # to manage both production clusters
          - cluster: production-management
            url: https://prod-mgmt.k8s.local
            values: values-production.yaml
            argocdUrl: https://argocd-region1.yourdomain.local,https://argocd-region2.yourdomain.local
  
  template:
    metadata:
      name: 'kargo-{{cluster}}'
      labels:
        environment: '{{cluster}}'
    spec:
      project: default
      
      source:
        repoURL: https://github.com/yourorg/gitops-repo
        targetRevision: main
        path: charts/kargo
        helm:
          valueFiles:
            - '{{values}}'
          parameters:
            - name: kargo.controller.argocd.urls[0]
              value: '{{argocdUrl}}'
      
      destination:
        server: '{{url}}'
        namespace: kargo
      
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
Step 5: Configure Kargo RBAC
yaml# kargo-config/rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kargo-controller
  namespace: kargo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kargo-controller
rules:
  # Kargo resources
  - apiGroups: ["kargo.akuity.io"]
    resources: ["*"]
    verbs: ["*"]
  
  # ArgoCD integration
  - apiGroups: ["argoproj.io"]
    resources: ["applications", "applicationsets"]
    verbs: ["get", "list", "watch", "update", "patch"]
  
  # Secrets for credentials
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kargo-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kargo-controller
subjects:
  - kind: ServiceAccount
    name: kargo-controller
    namespace: kargo
Step 6: Deploy Everything
bash# 1. Create secrets first
kubectl create namespace kargo
kubectl apply -f kargo-config/git-credentials.yaml
kubectl apply -f kargo-config/registry-credentials.yaml
kubectl apply -f kargo-config/postgres-secret.yaml

# 2. Deploy Kargo via ArgoCD
kubectl apply -f apps/kargo.yaml

# Or with ApplicationSet
kubectl apply -f argocd/appsets/kargo-appset.yaml

# 3. Check deployment
argocd app get kargo
kubectl get pods -n kargo

# 4. Apply RBAC
kubectl apply -f kargo-config/rbac.yaml
Step 7: Access Kargo UI
bash# Port forward (for testing)
kubectl port-forward -n kargo svc/kargo-api 8080:80

# Or via ingress (production)
# Access at: https://kargo.yourdomain.local

# Login with admin credentials
# Username: admin
# Password: (the one you set in passwordHash)
Step 8: Configure ArgoCD Integration
Kargo needs permissions to update ArgoCD Applications:
yaml# argocd-config/kargo-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kargo-argocd-integration
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kargo-argocd-integration
  namespace: argocd
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["applications"]
    verbs: ["get", "list", "watch", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kargo-argocd-integration
  namespace: argocd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kargo-argocd-integration
subjects:
  - kind: ServiceAccount
    name: kargo-controller
    namespace: kargo
Example Kargo Project Setup
After deployment, create a Kargo project:
yaml# kargo-projects/myapp.yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: myapp
spec:
  promotionPolicies:
    - stage: staging
      autoPromotionEnabled: true
    - stage: production
      autoPromotionEnabled: false  # Manual approval for prod
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: myapp
  namespace: myapp
spec:
  subscriptions:
    - image:
        repoURL: registry.yourdomain.local/myapp
        semverConstraint: ^1.0.0
    - git:
        repoURL: https://github.com/yourorg/myapp-config
        branch: main
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: staging
  namespace: myapp
spec:
  subscriptions:
    warehouse: myapp
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: https://github.com/yourorg/gitops-repo
        writeBranch: main
        kustomize:
          images:
            - image: registry.yourdomain.local/myapp
              path: environments/staging
    argoCDAppUpdates:
      - appName: myapp-staging
        appNamespace: argocd
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: production
  namespace: myapp
spec:
  subscriptions:
    upstreamStages:
      - name: staging
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: https://github.com/yourorg/gitops-repo
        writeBranch: main
        kustomize:
          images:
            - image: registry.yourdomain.local/myapp
              path: environments/production
    argoCDAppUpdates:
      - appName: myapp-production-region1
        appNamespace: argocd
      - appName: myapp-production-region2
        appNamespace: argocd
Verification
bash# Check Kargo is running
kubectl get pods -n kargo

# Check CRDs are installed
kubectl get crds | grep kargo

# Create a test project
kubectl apply -f kargo-projects/myapp.yaml

# Check Kargo resources
kubectl get warehouses,stages,freights -n myapp

# View Kargo logs
kubectl logs -n kargo -l app.kubernetes.io/component=controller -f
Monitoring & Troubleshooting
bash# Check controller logs
kubectl logs -n kargo deployment/kargo-controller -f

# Check API logs
kubectl logs -n kargo deployment/kargo-api -f

# Check ArgoCD integration
kubectl get applications -n argocd

# Verify webhooks
kubectl get mutatingwebhookconfigurations | grep kargo
kubectl get validatingwebhookconfigurations | grep kargo
Would you like me to help you set up a complete example workflow showing Tekton building → Kargo promoting → ArgoCD deploying across your two regions?NHow to deploy amd use infisical for secrets and use it for kargoHere's how to deploy Infisical and integrate it with Kargo for secrets management:
Part 1: Deploy Infisical via ArgoCD
Option 1: Full Self-Hosted Stack (Recommended for Production)
yaml# argocd/apps/infisical.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infisical
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts
    chart: infisical
    targetRevision: 0.6.0  # Check latest version
    helm:
      values: |
        # Main Infisical backend
        backend:
          replicaCount: 2  # HA setup
          
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          
          # Database configuration
          postgresql:
            enabled: true
            host: ""  # Will use internal postgres
            port: 5432
            database: infisical
          
          # Redis for caching/sessions
          redis:
            enabled: true
            host: ""  # Will use internal redis
            port: 6379
          
          # Email configuration (optional)
          smtp:
            enabled: false
            host: smtp.yourdomain.local
            port: 587
            secure: true
            from: infisical@yourdomain.local
          
          # Ingress
          ingress:
            enabled: true
            className: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
              nginx.ingress.kubernetes.io/ssl-redirect: "true"
            hosts:
              - host: infisical.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix
            tls:
              - secretName: infisical-tls
                hosts:
                  - infisical.yourdomain.local
        
        # Frontend (UI)
        frontend:
          replicaCount: 2
          
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          
          ingress:
            enabled: true
            className: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
            hosts:
              - host: infisical.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix
            tls:
              - secretName: infisical-tls
                hosts:
                  - infisical.yourdomain.local
        
        # PostgreSQL
        postgresql:
          enabled: true
          auth:
            username: infisical
            password: "change-this-password"  # Use sealed-secrets or external-secrets
            database: infisical
          
          primary:
            persistence:
              enabled: true
              storageClass: "local-path"
              size: 20Gi
            
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
              limits:
                cpu: 1000m
                memory: 1Gi
        
        # Redis
        redis:
          enabled: true
          master:
            persistence:
              enabled: true
              storageClass: "local-path"
              size: 5Gi
            
            resources:
              requests:
                cpu: 50m
                memory: 128Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: infisical

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
Part 2: Deploy Infisical Secrets Operator
The operator syncs secrets from Infisical to Kubernetes:
yaml# argocd/apps/infisical-secrets-operator.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infisical-secrets-operator
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts
    chart: secrets-operator
    targetRevision: 0.8.0
    helm:
      values: |
        # Controller configuration
        controllerManager:
          manager:
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                cpu: 500m
                memory: 512Mi
          
          replicas: 2  # HA
        
        # Webhook for validation
        webhook:
          enabled: true
          replicas: 2

  destination:
    server: https://kubernetes.default.svc
    namespace: infisical-operator-system

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
Part 3: Initial Infisical Setup
Access Infisical and Create Organization:
bash# Port forward (for initial setup)
kubectl port-forward -n infisical svc/infisical-frontend 8080:80

# Access at http://localhost:8080
# Create admin account
# Create organization
# Create your first project (e.g., "kargo-secrets")
Create Machine Identity (Service Account) for Kubernetes:
bash# Via Infisical UI:
# 1. Go to Project Settings → Machine Identities
# 2. Create new Machine Identity: "kubernetes-operator"
# 3. Generate a Universal Auth Client ID and Client Secret
# 4. Note these down - you'll need them
Part 4: Configure Infisical Authentication for Kubernetes
Create Authentication Secret:
yaml# infisical-config/auth-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: infisical-universal-auth
  namespace: kargo  # Deploy in each namespace that needs secrets
type: Opaque
stringData:
  clientId: "your-client-id-from-infisical"
  clientSecret: "your-client-secret-from-infisical"
Better approach using SealedSecrets:
bash# Install kubeseal if not already
# Create the secret
kubectl create secret generic infisical-universal-auth \
  --from-literal=clientId="your-client-id" \
  --from-literal=clientSecret="your-client-secret" \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > infisical-config/sealed-auth-secret.yaml

# Apply sealed secret
kubectl apply -f infisical-config/sealed-auth-secret.yaml -n kargo
```

## Part 5: Integrate Infisical with Kargo

### Store Kargo Secrets in Infisical:

In Infisical UI, create these secrets in your project (e.g., "kargo-secrets" project):

**Environment: Production**
```
GIT_USERNAME=kargo-bot
GIT_TOKEN=ghp_xxxxxxxxxxxx
GIT_SIGNING_KEY=-----BEGIN PGP PRIVATE KEY BLOCK-----...
REGISTRY_USERNAME=kargo
REGISTRY_PASSWORD=xxxxx
POSTGRES_PASSWORD=secure-password
ARGOCD_TOKEN=xxxxx
WEBHOOK_SECRET=random-secret
Create InfisicalSecret CRD for Kargo:
yaml# kargo-config/infisical-secrets.yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: kargo-secrets
  namespace: kargo
spec:
  # Host URL for self-hosted Infisical
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  
  # Reference to authentication secret
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: kargo
  
  # Infisical project configuration
  projectId: "your-project-id-from-infisical"  # Get from Infisical UI
  environment: "production"  # or "staging"
  secretsPath: "/"  # Root path, or specify like "/kargo"
  
  # Managed Kubernetes secret
  managedSecretReference:
    secretName: kargo-infisical-secrets
    secretNamespace: kargo
    creationPolicy: "Orphan"  # Keep secret if InfisicalSecret is deleted
  
  # Resync interval
  resyncInterval: 60  # seconds
Multiple Secrets for Different Components:
yaml# kargo-config/infisical-git-secrets.yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: kargo-git-credentials
  namespace: kargo
spec:
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: kargo
  
  projectId: "your-project-id"
  environment: "production"
  secretsPath: "/git"
  
  managedSecretReference:
    secretName: kargo-git-credentials
    secretNamespace: kargo
    creationPolicy: "Orphan"
  
  resyncInterval: 60
---
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: kargo-registry-credentials
  namespace: kargo
spec:
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: kargo
  
  projectId: "your-project-id"
  environment: "production"
  secretsPath: "/registry"
  
  managedSecretReference:
    secretName: kargo-registry-credentials
    secretNamespace: kargo
    creationPolicy: "Orphan"
  
  resyncInterval: 60
---
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: kargo-postgres-secret
  namespace: kargo
spec:
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: kargo
  
  projectId: "your-project-id"
  environment: "production"
  secretsPath: "/database"
  
  managedSecretReference:
    secretName: kargo-postgres-secret
    secretNamespace: kargo
    creationPolicy: "Orphan"
  
  resyncInterval: 60
Part 6: Update Kargo Deployment to Use Infisical Secrets
Update your Kargo values to reference the synced secrets:
yaml# charts/kargo/values-production.yaml
kargo:
  api:
    adminAccount:
      enabled: true
      # Reference secret from Infisical
      passwordHash: ""  # Will be populated from secret
      tokenSigningKey: ""
      existingSecret: kargo-infisical-secrets
      existingSecretKeys:
        passwordHash: ADMIN_PASSWORD_HASH
        tokenSigningKey: TOKEN_SIGNING_KEY
  
  controller:
    argocd:
      # Use token from Infisical
      tokenSecret:
        name: kargo-infisical-secrets
        key: ARGOCD_TOKEN
  
  postgresql:
    auth:
      existingSecret: kargo-postgres-secret
      secretKeys:
        password: POSTGRES_PASSWORD
Part 7: Configure Git Credentials via Infisical
Create a Kargo-compatible secret format:
yaml# kargo-config/git-secret-template.yaml
apiVersion: v1
kind: Secret
metadata:
  name: kargo-git-credentials
  namespace: kargo
  labels:
    kargo.akuity.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/yourorg/gitops-repo
  # These will be populated by InfisicalSecret
  username: ""  
  password: ""
Update InfisicalSecret to use specific key mapping:
yaml# kargo-config/infisical-git-mapped.yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: kargo-git-credentials
  namespace: kargo
  labels:
    kargo.akuity.io/secret-type: repository
spec:
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: kargo
  
  projectId: "your-project-id"
  environment: "production"
  secretsPath: "/git"
  
  managedSecretReference:
    secretName: kargo-git-credentials
    secretNamespace: kargo
    creationPolicy: "Owner"
  
  # Map Infisical keys to Kubernetes secret keys
  secretsScope:
    envScope: "production"
    secretsPath: "/"
    recursive: true
Part 8: Use Infisical CLI in Tekton Pipelines
Install Infisical CLI in Tekton Tasks:
yaml# tekton-pipelines/infisical-task.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: build-with-infisical
  namespace: tekton-pipelines
spec:
  params:
    - name: image-name
      type: string
    - name: infisical-project-id
      type: string
    - name: infisical-env
      type: string
      default: "production"
  
  workspaces:
    - name: source
    - name: dockerconfig
  
  steps:
    - name: install-infisical
      image: alpine:3.18
      script: |
        #!/bin/sh
        apk add --no-cache curl bash
        curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.alpine.sh' | bash
        apk add infisical
        infisical --version
    
    - name: fetch-secrets
      image: alpine:3.18
      env:
        - name: INFISICAL_TOKEN
          valueFrom:
            secretKeyRef:
              name: tekton-infisical-token
              key: token
        - name: INFISICAL_PROJECT_ID
          value: $(params.infisical-project-id)
        - name: INFISICAL_ENV
          value: $(params.infisical-env)
      script: |
        #!/bin/sh
        # Export secrets as environment variables
        infisical export --env=$INFISICAL_ENV --projectId=$INFISICAL_PROJECT_ID > /workspace/.env
        
        # Or fetch specific secrets
        REGISTRY_PASSWORD=$(infisical secrets get REGISTRY_PASSWORD --env=$INFISICAL_ENV --projectId=$INFISICAL_PROJECT_ID --plain)
        echo "Registry password retrieved"
    
    - name: build-image
      image: gcr.io/kaniko-project/executor:latest
      env:
        - name: DOCKER_CONFIG
          value: /workspace/dockerconfig
      script: |
        #!/busybox/sh
        # Source secrets from .env
        . /workspace/.env
        
        # Use secrets in build
        /kaniko/executor \
          --dockerfile=/workspace/source/Dockerfile \
          --context=/workspace/source \
          --destination=$(params.image-name) \
          --build-arg REGISTRY_PASSWORD=$REGISTRY_PASSWORD
      workingDir: /workspace/source
      volumeMounts:
        - name: dockerconfig
          mountPath: /workspace/dockerconfig
Part 9: Multi-Environment Setup
Staging Environment:
yaml# infisical-config/staging-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: infisical-universal-auth
  namespace: kargo
type: Opaque
stringData:
  clientId: "staging-client-id"
  clientSecret: "staging-client-secret"
---
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: kargo-secrets-staging
  namespace: kargo
spec:
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: kargo
  
  projectId: "your-project-id"
  environment: "staging"  # Different environment
  secretsPath: "/"
  
  managedSecretReference:
    secretName: kargo-secrets-staging
    secretNamespace: kargo
  
  resyncInterval: 60
Part 10: Complete Integration Example
Full Kargo Project with Infisical:
yaml# kargo-projects/myapp-with-infisical.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
---
# Infisical auth for this project
apiVersion: v1
kind: Secret
metadata:
  name: infisical-auth
  namespace: myapp
type: Opaque
stringData:
  clientId: "myapp-client-id"
  clientSecret: "myapp-client-secret"
---
# Sync secrets from Infisical
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: myapp-secrets
  namespace: myapp
spec:
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-auth
        secretNamespace: myapp
  
  projectId: "myapp-project-id"
  environment: "production"
  secretsPath: "/"
  
  managedSecretReference:
    secretName: myapp-secrets
    secretNamespace: myapp
  
  resyncInterval: 60
---
# Kargo Project
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: myapp
spec:
  promotionPolicies:
    - stage: staging
      autoPromotionEnabled: true
    - stage: production
      autoPromotionEnabled: false
---
# Warehouse subscribes to image updates
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: myapp
  namespace: myapp
spec:
  subscriptions:
    - image:
        repoURL: registry.yourdomain.local/myapp
        semverConstraint: ^1.0.0
        # Use credentials from Infisical
        repoURLIsRegExp: false
        discoveryLimit: 10
---
# Staging Stage
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: staging
  namespace: myapp
spec:
  requestedFreight:
    - origin:
        kind: Warehouse
        name: myapp
      sources:
        direct: true
  
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: https://github.com/yourorg/gitops-repo
        writeBranch: main
        kustomize:
          images:
            - image: registry.yourdomain.local/myapp
              path: environments/staging
    
    argoCDAppUpdates:
      - appName: myapp-staging
        appNamespace: argocd
---
# Production Stage
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: production
  namespace: myapp
spec:
  requestedFreight:
    - origin:
        kind: Warehouse
        name: myapp
      sources:
        stages:
          - staging
  
  promotionMechanisms:
    gitRepoUpdates:
      - repoURL: https://github.com/yourorg/gitops-repo
        writeBranch: main
        kustomize:
          images:
            - image: registry.yourdomain.local/myapp
              path: environments/production
    
    argoCDAppUpdates:
      - appName: myapp-production-region1
        appNamespace: argocd
      - appName: myapp-production-region2
        appNamespace: argocd
Part 11: Deployment Order
bash# 1. Deploy Infisical
kubectl apply -f argocd/apps/infisical.yaml

# Wait for it to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/infisical-backend -n infisical

# 2. Deploy Infisical Secrets Operator
kubectl apply -f argocd/apps/infisical-secrets-operator.yaml

# 3. Setup Infisical (via UI)
# - Create organization
# - Create projects
# - Add secrets
# - Create machine identities

# 4. Deploy authentication secrets
kubectl apply -f infisical-config/sealed-auth-secret.yaml

# 5. Deploy InfisicalSecret CRDs
kubectl apply -f kargo-config/infisical-secrets.yaml

# 6. Verify secrets are synced
kubectl get secrets -n kargo
kubectl get infisicalsecrets -n kargo

# 7. Deploy/Update Kargo with new secret references
kubectl apply -f apps/kargo.yaml
Part 12: Backup & Disaster Recovery
Backup Infisical PostgreSQL:
yaml# infisical-config/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: infisical-postgres-backup
  namespace: infisical
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: postgres:15-alpine
              env:
                - name: PGHOST
                  value: infisical-postgresql
                - name: PGDATABASE
                  value: infisical
                - name: PGUSER
                  value: infisical
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: infisical-postgresql
                      key: password
              command:
                - /bin/sh
                - -c
                - |
                  pg_dump -Fc > /backup/infisical-$(date +%Y%m%d-%H%M%S).dump
              volumeMounts:
                - name: backup
                  mountPath: /backup
          volumes:
            - name: backup
              persistentVolumeClaim:
                claimName: infisical-backups
          restartPolicy: OnFailure
Monitoring & Troubleshooting
bash# Check Infisical pods
kubectl get pods -n infisical

# Check operator
kubectl get pods -n infisical-operator-system

# Check InfisicalSecret status
kubectl get infisicalsecrets -n kargo
kubectl describe infisicalsecret kargo-secrets -n kargo

# Check if secrets are synced
kubectl get secret kargo-infisical-secrets -n kargo -o yaml

# Operator logs
kubectl logs -n infisical-operator-system \
  deployment/secrets-operator-controller-manager -f

# Force resync
kubectl annotate infisicalsecret kargo-secrets \
  secrets.infisical.com/last-applied-timestamp=$(date +%s) -n kargo
Would you like me to help you set up a complete example with all three components (Tekton building, Infisical managing secrets, Kargo promoting, ArgoCD deploying) working together?NI have a working ceph cluster. How can I provision storage for and deploy mongodb (HA), Stackgres, and kafa (stimzi) and Authentik and then configure Authentik for argocd, ceph amd other web panels' loginsHere's a comprehensive guide to set up Ceph storage, deploy all your stateful applications in HA, and configure Authentik SSO:
Part 1: Ceph CSI Driver & Storage Classes
Deploy Ceph CSI Driver via ArgoCD
yaml# argocd/apps/ceph-csi-rbd.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ceph-csi-rbd
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://ceph.github.io/csi-charts
    chart: ceph-csi-rbd
    targetRevision: 3.11.0
    helm:
      values: |
        csiConfig:
          - clusterID: "your-ceph-cluster-fsid"  # Get with: ceph fsid
            monitors:
              - "10.0.1.10:6789"  # Your Ceph monitor IPs
              - "10.0.1.11:6789"
              - "10.0.1.12:6789"
        
        # Storage class configuration
        storageClass:
          create: true
          name: ceph-rbd
          clusterID: "your-ceph-cluster-fsid"
          pool: kubernetes  # Create this pool in Ceph first
          
          # RBD image features
          imageFeatures: layering
          
          # Set as default storage class
          annotations:
            storageclass.kubernetes.io/is-default-class: "true"
          
          # Volume parameters
          parameters:
            imageFormat: "2"
            imageFeatures: layering
            csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
            csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi-rbd
            csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
            csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi-rbd
            csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
            csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi-rbd
            csi.storage.k8s.io/fstype: ext4
          
          # Allow volume expansion
          allowVolumeExpansion: true
          
          # ReclaimPolicy
          reclaimPolicy: Retain  # or Delete
          
          # Volume binding mode
          volumeBindingMode: Immediate
        
        # Provisioner configuration
        provisioner:
          name: rbd.csi.ceph.com
          replicaCount: 3  # HA
          
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
        
        # Node plugin
        nodeplugin:
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: ceph-csi-rbd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Deploy CephFS CSI Driver (for shared storage)
yaml# argocd/apps/ceph-csi-cephfs.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ceph-csi-cephfs
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://ceph.github.io/csi-charts
    chart: ceph-csi-cephfs
    targetRevision: 3.11.0
    helm:
      values: |
        csiConfig:
          - clusterID: "your-ceph-cluster-fsid"
            monitors:
              - "10.0.1.10:6789"
              - "10.0.1.11:6789"
              - "10.0.1.12:6789"
        
        storageClass:
          create: true
          name: ceph-fs
          clusterID: "your-ceph-cluster-fsid"
          fsName: cephfs  # Your CephFS name
          pool: cephfs_data  # Data pool
          
          parameters:
            csi.storage.k8s.io/provisioner-secret-name: csi-cephfs-secret
            csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi-cephfs
            csi.storage.k8s.io/controller-expand-secret-name: csi-cephfs-secret
            csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi-cephfs
            csi.storage.k8s.io/node-stage-secret-name: csi-cephfs-secret
            csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi-cephfs
          
          allowVolumeExpansion: true
          reclaimPolicy: Retain
          volumeBindingMode: Immediate
        
        provisioner:
          name: cephfs.csi.ceph.com
          replicaCount: 3

  destination:
    server: https://kubernetes.default.svc
    namespace: ceph-csi-cephfs

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Create Ceph Secrets
First, create Ceph user and get keys:
bash# On Ceph cluster, create Kubernetes user
ceph auth get-or-create client.kubernetes \
  mon 'profile rbd' \
  ocp 'profile rbd pool=kubernetes' \
  mgr 'profile rbd pool=kubernetes'

# Get the key
ceph auth get-key client.kubernetes

# For CephFS
ceph auth get-or-create client.kubernetes-cephfs \
  mon 'allow r' \
  mds 'allow rw' \
  ocp 'allow rw pool=cephfs_data'

ceph auth get-key client.kubernetes-cephfs
Create secrets in Kubernetes:
yaml# ceph-config/rbd-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: ceph-csi-rbd
type: Opaque
stringData:
  userID: kubernetes
  userKey: AQD... # Your key from above
---
# ceph-config/cephfs-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-cephfs-secret
  namespace: ceph-csi-cephfs
type: Opaque
stringData:
  adminID: kubernetes-cephfs
  adminKey: AQD...  # Your CephFS key
Store in Infisical and sync:
yaml# ceph-config/infisical-ceph-secrets.yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: ceph-rbd-secret
  namespace: ceph-csi-rbd
spec:
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: ceph-csi-rbd
  projectId: "your-project-id"
  environment: "production"
  secretsPath: "/ceph/rbd"
  managedSecretReference:
    secretName: csi-rbd-secret
    secretNamespace: ceph-csi-rbd
Create Storage Classes for Different Use Cases
yaml# ceph-config/storage-classes.yaml
---
# Fast RBD for databases (SSD pool)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "your-ceph-cluster-fsid"
  pool: kubernetes-ssd  # Create SSD pool
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: Immediate
---
# Standard RBD (HDD pool)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd-hdd
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "your-ceph-cluster-fsid"
  pool: kubernetes-hdd
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer  # Better pod placement
---
# CephFS for shared storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-fs-shared
provisioner: cephfs.csi.ceph.com
parameters:
  clusterID: "your-ceph-cluster-fsid"
  fsName: cephfs
  pool: cephfs_data
  csi.storage.k8s.io/provisioner-secret-name: csi-cephfs-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi-cephfs
  csi.storage.k8s.io/controller-expand-secret-name: csi-cephfs-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi-cephfs
  csi.storage.k8s.io/node-stage-secret-name: csi-cephfs-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi-cephfs
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: Immediate
Part 2: Deploy MongoDB (HA)
Using Percona MongoDB Operator (Recommended)
yaml# argocd/apps/percona-mongodb-operator.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: percona-mongodb-operator
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://percona.github.io/percona-helm-charts
    chart: psmdb-operator
    targetRevision: 1.15.0
    helm:
      values: |
        # Operator configuration
        replicaCount: 1
        
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        
        # Webhook
        webhook:
          enabled: true

  destination:
    server: https://kubernetes.default.svc
    namespace: mongodb-operator

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Deploy MongoDB Cluster
yaml# charts/mongodb-cluster/values-production.yaml
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: mongodb-cluster
  namespace: mongodb
  finalizers:
    - delete-psmdb-pods-in-order
spec:
  crVersion: 1.15.0
  
  # MongoDB image
  image: percona/percona-server-mongodb:6.0.9-7
  imagePullPolicy: IfNotPresent
  
  # Upgrade strategy
  updateStrategy: SmartUpdate
  upgradeOptions:
    versionServiceEndpoint: https://check.percona.com
    apply: recommended
    schedule: "0 2 * * *"
  
  # Secrets
  secrets:
    users: mongodb-users-secret  # Create this
    encryptionKey: mongodb-encryption-key
  
  # PMM (monitoring) - optional
  pmm:
    enabled: false
  
  # Replica set configuration - 3 nodes for HA
  replsets:
    - name: rs0
      size: 3  # HA: 3 replicas
      
      # Anti-affinity for HA
      affinity:
        antiAffinityTopologyKey: "kubernetes.io/hostname"
      
      # Resources
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 2000m
          memory: 4Gi
      
      # Storage
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: ceph-rbd-ssd
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 50Gi
      
      # Expose externally (optional)
      expose:
        enabled: false
        exposeType: ClusterIP
      
      # MongoDB configuration
      configuration: |
        operationProfiling:
          mode: slowOp
          slowOpThresholdMs: 100
        storage:
          engine: wiredTiger
          wiredTiger:
            engineConfig:
              cacheSizeGB: 2
        net:
          compression:
            compressors: snappy,zstd
  
  # Backup configuration
  backup:
    enabled: true
    image: percona/percona-backup-mongodb:2.3.0
    
    # S3-compatible storage (can use Ceph RGW)
    storages:
      ceph-s3:
        type: s3
        s3:
          bucket: mongodb-backups
          region: us-east-1  # Not used for Ceph but required
          endpointUrl: http://ceph-rgw.ceph.svc.cluster.local:8080
          credentialsSecret: mongodb-backup-s3-credentials
    
    # Backup tasks
    tasks:
      - name: daily-backup
        enabled: true
        schedule: "0 3 * * *"
        keep: 7
        storageName: ceph-s3
        compressionType: gzip
        compressionLevel: 6
  
  # Sharding (optional, for very large datasets)
  sharding:
    enabled: false

---
# MongoDB users secret
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-users-secret
  namespace: mongodb
type: Opaque
stringData:
  MONGODB_BACKUP_USER: backup
  MONGODB_BACKUP_PASSWORD: backuppass123
  MONGODB_CLUSTER_ADMIN_USER: clusteradmin
  MONGODB_CLUSTER_ADMIN_PASSWORD: adminpass123
  MONGODB_CLUSTER_MONITOR_USER: clustermonitor
  MONGODB_CLUSTER_MONITOR_PASSWORD: monitorpass123
  MONGODB_USER_ADMIN_USER: useradmin
  MONGODB_USER_ADMIN_PASSWORD: useradminpass123
---
# Encryption key
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-encryption-key
  namespace: mongodb
type: Opaque
stringData:
  encryption-key: "32-byte-base64-encoded-key-here=="
Create ArgoCD Application for MongoDB
yaml# argocd/apps/mongodb-cluster.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mongodb-cluster
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/yourorg/gitops-repo
    targetRevision: main
    path: charts/mongodb-cluster
  
  destination:
    server: https://kubernetes.default.svc
    namespace: mongodb
  
  syncPolicy:
    automated:
      prune: false  # Don't auto-prune databases!
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Part 3: Deploy StackGres (PostgreSQL Operator)
yaml# argocd/apps/stackgres-operator.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: stackgres-operator
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://stackgres.io/downloads/stackgres-k8s/stackgres/helm
    chart: stackgres-operator
    targetRevision: 1.10.0
    helm:
      values: |
        # Operator configuration
        operator:
          replicaCount: 2  # HA
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 512Mi
        
        # REST API
        restapi:
          replicaCount: 2
          
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
        
        # Admin UI
        adminui:
          enabled: true
          replicaCount: 1
          
          service:
            type: ClusterIP
          
          # Ingress for UI
          ingress:
            enabled: true
            className: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
            hosts:
              - host: stackgres.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix
            tls:
              - secretName: stackgres-tls
                hosts:
                  - stackgres.yourdomain.local
        
        # Prometheus integration
        prometheus:
          allowAutobind: true

  destination:
    server: https://kubernetes.default.svc
    namespace: stackgres

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
Create StackGres PostgreSQL Cluster
yaml# charts/postgres-cluster/stackgres-cluster.yaml
apiVersion: stackgres.io/v1
kind: SGCluster
metadata:
  name: postgres-ha
  namespace: postgres
spec:
  instances: 3  # HA: 3 instances
  
  postgres:
    version: '15.5'
    extensions:
      - name: pg_repack
      - name: pgcrypto
      - name: uuid-ossp
  
  # Pod configuration
  pods:
    persistentVolume:
      storageClass: ceph-rbd-ssd
      size: 50Gi
    
    scheduling:
      nodeSelector: {}
      tolerations: []
      
      # Anti-affinity for HA
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: kubernetes.io/hostname
                  operator: In
                  values:
                    - node1
                    - node2
                    - node3
    
    # Resources
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2000m
        memory: 4Gi
    
    # Connection pooling
    disableConnectionPooling: false
    disableMetricsExporter: false
    disablePostgresUtil: false
  
  # Connection pooling configuration
  configurations:
    sgPostgresConfig: pgconfig-ha
    sgPoolingConfig: poolconfig-ha
    sgBackupConfig: backupconfig-ha
  
  # Replication
  replication:
    mode: async  # or 'sync' for synchronous replication
    role: ha-read
  
  # Distributed logs
  distributedLogs:
    sgDistributedLogs: distributedlogs
  
  # Monitoring
  prometheusAutobind: true
  
  # Non-production options
  nonProductionOptions: {}

---
# PostgreSQL configuration
apiVersion: stackgres.io/v1
kind: SGPostgresConfig
metadata:
  name: pgconfig-ha
  namespace: postgres
spec:
  postgresVersion: "15"
  postgresql.conf:
    shared_buffers: '512MB'
    effective_cache_size: '2GB'
    maintenance_work_mem: '256MB'
    checkpoint_completion_target: '0.9'
    wal_buffers: '16MB'
    default_statistics_target: '100'
    random_page_cost: '1.1'
    effective_io_concurrency: '200'
    work_mem: '5MB'
    huge_pages: 'try'
    min_wal_size: '1GB'
    max_wal_size: '4GB'
    max_worker_processes: '4'
    max_parallel_workers_per_gather: '2'
    max_parallel_workers: '4'
    max_parallel_maintenance_workers: '2'

---
# Connection pooling config
apiVersion: stackgres.io/v1
kind: SGPoolingConfig
metadata:
  name: poolconfig-ha
  namespace: postgres
spec:
  pgBouncer:
    pgbouncer.ini:
      pool_mode: transaction
      max_client_conn: '1000'
      default_pool_size: '25'
      reserve_pool_size: '5'
      reserve_pool_timeout: '5'

---
# Backup configuration
apiVersion: stackgres.io/v1
kind: SGBackupConfig
metadata:
  name: backupconfig-ha
  namespace: postgres
spec:
  baseBackups:
    cronSchedule: '0 3 * * *'  # Daily at 3 AM
    retention: 7  # Keep 7 backups
    compression: lz4
    performance:
      maxNetworkBandwidth: 104857600  # 100MB/s
      maxDiskBandwidth: 104857600
      uploadDiskConcurrency: 1
  
  storage:
    type: s3Compatible
    s3Compatible:
      bucket: postgres-backups
      region: us-east-1
      endpoint: http://ceph-rgw.ceph.svc.cluster.local:8080
      enablePathStyleAddressing: true
      storageClass: STANDARD
      awsCredentials:
        secretKeySelectors:
          accessKeyId:
            name: postgres-backup-s3-creds
            key: accessKeyId
          secretAccessKey:
            name: postgres-backup-s3-creds
            key: secretAccessKey

---
# Distributed logs
apiVersion: stackgres.io/v1
kind: SGDistributedLogs
metadata:
  name: distributedlogs
  namespace: postgres
spec:
  persistentVolume:
    size: 20Gi
    storageClass: ceph-rbd-ssd
  
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
Part 4: Deploy Kafka (Strimzi)
yaml# argocd/apps/strimzi-operator.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: strimzi-operator
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://strimzi.io/charts
    chart: strimzi-kafka-operator
    targetRevision: 0.39.0
    helm:
      values: |
        # Operator configuration
        replicas: 2  # HA
        
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 512Mi
        
        # Watch all namespaces
        watchAnyNamespace: true
        
        # Feature gates
        featureGates: "+UseKRaft,+KafkaNodePools"
        
        # Logging
        logLevel: INFO

  destination:
    server: https://kubernetes.default.svc
    namespace: kafka-operator

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Deploy Kafka Cluster (KRaft mode - no Zookeeper)
yaml# charts/kafka-cluster/kafka-ha.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: controller
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-ha
spec:
  replicas: 3  # HA controllers
  roles:
    - controller
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 20Gi
        class: ceph-rbd-ssd
        deleteClaim: false
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi

---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: broker
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-ha
spec:
  replicas: 3  # HA brokers
  roles:
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 100Gi
        class: ceph-rbd-ssd
        deleteClaim: false
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 4000m
      memory: 8Gi

---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: kafka-ha
  namespace: kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.6.1
    
    # Use KRaft mode (no Zookeeper)
    metadataVersion: 3.6-IV2
    
    # Listeners
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication:
          type: tls
      - name: external
        port: 9094
        type: loadbalancer  # or nodeport
        tls: true
        authentication:
          type: scram-sha-512
    
    # Authorization
    authorization:
      type: simple
      superUsers:
        - admin
        - CN=kafka-admin
    
    # Configuration
    config:
      # Replication settings
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
      
      # Performance
      num.network.threads: 8
      num.io.threads: 8
      socket.send.buffer.bytes: 102400
      socket.receive.buffer.bytes: 102400
      socket.request.max.bytes: 104857600
      
      # Log settings
      log.retention.hours: 168  # 7 days
      log.segment.bytes: 1073741824
      log.retention.check.interval.ms: 300000
      
      # Auto create topics
      auto.create.topics.enable: false
      
      # Compression
      compression.type: snappy
    
    # Rack awareness for HA
    rack:
      topologyKey: kubernetes.io/hostname
    
    # Metrics
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
  
  # Entity Operator
  entityOperator:
    topicOperator:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    
    userOperator:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
  
  # Kafka Exporter for metrics
  kafkaExporter:
    topicRegex: ".*"
    groupRegex: ".*"
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi
  
  # Cruise Control for rebalancing
  cruiseControl:
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi

---
# Kafka metrics config
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-metrics
  namespace: kafka
data:
  kafka-metrics-config.yml: |
    lowercaseOutputName: true
    rules:
      - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), topic=(.+), partition=(.*)><>Value
        name: kafka_server_$1_$2
        type: GAUGE
        labels:
          clientId: "$3"
          topic: "$4"
          partition: "$5"
Create Kafka Users and Topics
yaml# charts/kafka-cluster/kafka-resources.yaml
---
# Admin user
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: admin
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-ha
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: "*"
          patternType: literal
        operations:
          - All
      - resource:
          type: group
          name: "*"
          patternType: literal
        operations:
          - All
      - resource:
          type: cluster
        operations:
          - All

---
# Application user
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: myapp-user
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-ha
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: myapp-
          patternType: prefix
        operations:
          - Read
          - Write
          - Describe
      - resource:
          type: group
          name: myapp-
          patternType: prefix
        operations:
          - Read

---
# Example topic
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: events
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-ha
spec:
  partitions: 12
  replicas: 3
  config:
    retention.ms: 604800000  # 7 days
    segment.ms: 86400000  # 1 day
    compression.type: snappy
    min.insync.replicas: 2
Part 5: Deploy Authentik
yaml# argocd/apps/authentik.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: authentik
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://charts.goauthentik.io
    chart: authentik
    targetRevision: 2024.2.0
    helm:
      values: |
        # Global settings
        global:
          env:
            - name: AUTHENTIK_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: authentik-secrets
                  key: secret_key
            - name: AUTHENTIK_ERROR_REPORTING__ENABLED
              value: "false"
            - name: AUTHENTIK_LOG_LEVEL
              value: "info"
        
        # Server configuration
        server:
          replicas: 2  # HA
          
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
          
          # Ingress
          ingress:
            enabled: true
            ingressClassName: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
              nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
            hosts:
              - host: auth.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix
            tls:
              - secretName: authentik-tls
                hosts:
                  - auth.yourdomain.local
          
          # Metrics
          metrics:
            enabled: true
            serviceMonitor:
              enabled: true
        
        # Worker configuration
        worker:
          replicas: 2
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
        
        # PostgreSQL (use StackGres cluster)
        postgresql:
          enabled: false  # Use external
        
        # External PostgreSQL connection
        env:
          AUTHENTIK_POSTGRESQL__HOST: "postgres-ha-primary.postgres.svc.cluster.local"
          AUTHENTIK_POSTGRESQL__NAME: "authentik"
          AUTHENTIK_POSTGRESQL__USER: "authentik"
          AUTHENTIK_POSTGRESQL__PASSWORD:
            secretKeyRef:
              name: authentik-postgres
              key: password
          AUTHENTIK_POSTGRESQL__PORT: "5432"
        
        # Redis
        redis:
          enabled: true
          architecture: standalone
          auth:
            enabled: true
            existingSecret: authentik-redis
            existingSecretPasswordKey: password
          master:
            persistence:
              enabled: true
              storageClass: ceph-rbd-ssd
              size: 5Gi
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                cpu: 500m
                memory: 512Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: authentik

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Create Authentik Secrets
yaml# authentik-config/secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: authentik-secrets
  namespace: authentik
type: Opaque
stringData:
  # Generate with: openssl rand -base64 60
  secret_key: "your-secret-key-here"
---
apiVersion: v1
kind: Secret
metadata:
  name: authentik-postgres
  namespace: authentik
type: Opaque
stringData:
  password: "your-postgres-password"
---
apiVersion: v1
kind: Secret
metadata:
  name: authentik-redis
  namespace: authentik
type: Opaque
stringData:
  password: "your-redis-password"
Store in Infisical:
yaml# authentik-config/infisical-secrets.yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: authentik-secrets
  namespace: authentik
spec:
  hostAPI: http://infisical-backend.infisical.svc.cluster.local:8080
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: authentik
  projectId: "your-project-id"
  environment: "production"
  secretsPath: "/authentik"
  managedSecretReference:
    secretName: authentik-secrets
    secretNamespace: authentik
Part 6: Configure Authentik SSO
Initial Authentik Setup
bash# Port forward to access UI
kubectl port-forward -n authentik svc/authentik-server 9000:80

# Access at http://localhost:9000/if/flow/initial-setup/
# Create admin account
Configure OIDC Provider for ArgoCD
In Authentik UI:

Create OAuth2/OIDC Provider:

Navigate to: Applications → Providers → Create
Type: OAuth2/OpenID Connect Provider
Name: ArgoCD
Authorization flow: default-provider-authorization-implicit-consent
Redirect URIs: https://argocd.yourdomain.local/auth/callback
Signing Key: Select or create a key


Create Application:

Navigate to: Applications → Create
Name: ArgoCD
Slug: argocd
Provider: Select the ArgoCD provider created above


Get Client ID and Secret:

Go to provider settings
Note the Client ID and Client Secret



Configure ArgoCD to use Authentik
yaml# argocd-config/authentik-sso.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.yourdomain.local
  
  # OIDC configuration
  oidc.config: |
    name: Authentik
    issuer: https://auth.yourdomain.local/application/o/argocd/
    clientID: your-client-id-from-authentik
    clientSecret: $oidc.authentik.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
      - groups
    requestedIDTokenClaims:
      groups:
        essential: true

---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
stringData:
  oidc.authentik.clientSecret: "your-client-secret-from-authentik"

---
# RBAC configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    # Admin group from Authentik
    g, authentik Admins, role:admin
    
    # Developers group
    g, authentik Developers, role:developer
    
    # Developer role
    p, role:developer, applications, *, */*, allow
    p, role:developer, repositories, *, *, allow
    p, role:developer, clusters, get, *, allow
    p, role:developer, projects, get, *, allow
  
  scopes: '[groups, email]'
Configure Ceph Dashboard SSO
In Authentik UI, create provider for Ceph:

Create SAML Provider:

Type: SAML Provider
Name: Ceph Dashboard
ACS URL: https://ceph-dashboard.yourdomain.local/auth/saml2/sso
Issuer: https://auth.yourdomain.local
Service Provider Binding: Post
Audience: https://ceph-dashboard.yourdomain.local
Signing Certificate: Select or create


Create Application:

Name: Ceph Dashboard
Provider: Ceph SAML provider



On Ceph Dashboard:
bash# Configure SAML on Ceph
ceph dashboard sso setup saml2 \
  https://auth.yourdomain.local/application/saml/ceph/metadata/ \
  https://ceph-dashboard.yourdomain.local \
  ceph-dashboard \
  'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST'

# Set username attribute
ceph dashboard sso set username_attribute email

# Enable SSO
ceph dashboard sso enable saml2
Configure StackGres UI SSO
StackGres supports OIDC:
yaml# Update StackGres operator values
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: stackgres-operator
  namespace: argocd
spec:
  source:
    helm:
      values: |
        adminui:
          oidc:
            enabled: true
            issuer: https://auth.yourdomain.local/application/o/stackgres/
            clientId: your-stackgres-client-id
            clientSecret: your-stackgres-client-secret
            redirectUri: https://stackgres.yourdomain.local/admin/oidc/callback
Configure Infisical SSO
In Authentik, create OIDC provider for Infisical:
yaml# Update Infisical deployment
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infisical
  namespace: argocd
spec:
  source:
    helm:
      values: |
        backend:
          env:
            # SSO Configuration
            - name: AUTH_SECRET
              value: "your-secret"
            - name: SITE_URL
              value: "https://infisical.yourdomain.local"
            
            # OIDC
            - name: CLIENT_ID_OIDC
              value: "your-infisical-client-id"
            - name: CLIENT_SECRET_OIDC
              valueFrom:
                secretKeyRef:
                  name: infisical-oidc
                  key: client-secret
            - name: AUTH_URL_OIDC
              value: "https://auth.yourdomain.local/application/o/infisical/"
Configure Kargo UI SSO
In Authentik, create OIDC provider for Kargo:
yaml# Update Kargo values
kargo:
  api:
    oidc:
      enabled: true
      issuerURL: https://auth.yourdomain.local/application/o/kargo/
      clientID: your-kargo-client-id
      clientSecret: your-kargo-client-secret
      cliClientID: kargo-cli
Part 7: Deploy Everything in Order
Create deployment script:
bash#!/bin/bash
# deploy-all.sh

set -e

echo "=== Deploying Ceph CSI Drivers ==="
kubectl apply -f ceph-config/rbd-secret.yaml
kubectl apply -f ceph-config/cephfs-secret.yaml
kubectl apply -f argocd/apps/ceph-csi-rbd.yaml
kubectl apply -f argocd/apps/ceph-csi-cephfs.yaml

# Wait for CSI drivers
kubectl wait --for=condition=available --timeout=300s \
  deployment/ceph-csi-rbd-provisioner -n ceph-csi-rbd

echo "=== Creating Storage Classes ==="
kubectl apply -f ceph-config/storage-classes.yaml

echo "=== Deploying Percona MongoDB Operator ==="
kubectl apply -f argocd/apps/percona-mongodb-operator.yaml
sleep 30

echo "=== Deploying MongoDB Cluster ==="
kubectl apply -f charts/mongodb-cluster/values-production.yaml

echo "=== Deploying StackGres Operator ==="
kubectl apply -f argocd/apps/stackgres-operator.yaml
sleep 30

echo "=== Deploying PostgreSQL Cluster ==="
kubectl apply -f charts/postgres-cluster/stackgres-cluster.yaml

echo "=== Deploying Strimzi Operator ==="
kubectl apply -f argocd/apps/strimzi-operator.yaml
sleep 30

echo "=== Deploying Kafka Cluster ==="
kubectl apply -f charts/kafka-cluster/kafka-ha.yaml
kubectl apply -f charts/kafka-cluster/kafka-resources.yaml

echo "=== Deploying Authentik ==="
kubectl apply -f authentik-config/infisical-secrets.yaml
sleep 10
kubectl apply -f argocd/apps/authentik.yaml

echo "=== Waiting for Authentik to be ready ==="
kubectl wait --for=condition=available --timeout=600s \
  deployment/authentik-server -n authentik

echo "==="
echo "Deployment complete!"
echo "Access Authentik at: https://auth.yourdomain.local"
echo "Complete initial setup and configure SSO providers"
echo "==="
Verification Commands
bash# Check Ceph CSI
kubectl get csidriver
kubectl get storageclass

# Check MongoDB
kubectl get psmdb -n mongodb
kubectl get pods -n mongodb
kubectl exec -it mongodb-cluster-rs0-0 -n mongodb -- mongo --eval "rs.status()"

# Check PostgreSQL
kubectl get sgclusters -n postgres
kubectl get pods -n postgres

# Check Kafka
kubectl get kafka -n kafka
kubectl get kafkatopics -n kafka
kubectl get kafkausers -n kafka

# Check Authentik
kubectl get pods -n authentik
kubectl logs -n authentik deployment/authentik-server -f

# Test connections
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h postgres-ha-primary.postgres.svc.cluster.local -U authentik -d authentik

kubectl run -it --rm debug --image=mongodb:6.0 --restart=Never -- \
  mongosh mongodb://mongodb-cluster-rs0-0.mongodb-cluster-rs0.mongodb.svc.cluster.local:27017
This gives you a complete HA setup with:

Ceph-backed storage for all stateful apps
MongoDB 3-replica cluster
PostgreSQL 3-instance HA cluster
Kafka 3-broker + 3-controller cluster
Authentik for centralized SSO
All integrated via OIDC/SAML

Would you like me to help you configure specific SSO flows, set up monitoring for these components, or create backup/restore procedures?NSorry. I forgot to mention I already have rook-ceph-cluster working and healthy worh 1.5Tb storagePerfect! Since you already have Rook-Ceph running, let's skip the CSI driver setup and use your existing Rook-Ceph cluster. Here's the updated guide:
Part 1: Verify & Configure Rook-Ceph Storage Classes
Check Your Existing Rook-Ceph Setup
bash# Verify Rook-Ceph cluster health
kubectl get cephcluster -n rook-ceph
kubectl exec -it -n rook-ceph deploy/rook-ceph-tools -- ceph status
kubectl exec -it -n rook-ceph deploy/rook-ceph-tools -- ceph df

# Check existing storage classes
kubectl get storageclass

# Check CSI drivers
kubectl get csidriver
Create Storage Classes for Your Use Cases
yaml# rook-ceph-config/storage-classes.yaml
---
# RBD Storage Class for Databases (block storage)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph  # Your Rook-Ceph namespace
  pool: replicapool  # Default Rook pool, or create a new one
  imageFormat: "2"
  imageFeatures: layering
  
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
  
  csi.storage.k8s.io/fstype: ext4

allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate

---
# RBD Storage Class for Databases (retain policy for production)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block-retain
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
  
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
  
  csi.storage.k8s.io/fstype: ext4

allowVolumeExpansion: true
reclaimPolicy: Retain  # Don't delete data if PVC is deleted
volumeBindingMode: WaitForFirstConsumer  # Better pod placement

---
# CephFS Storage Class for Shared Storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: myfs  # Check your CephFS name with: kubectl get cephfilesystem -n rook-ceph
  pool: myfs-replicated  # Data pool
  
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph

allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
Optional: Create Dedicated Ceph Pools
yaml# rook-ceph-config/database-pool.yaml
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: database-pool
  namespace: rook-ceph
spec:
  # Failure domain - adjust based on your setup
  failureDomain: host  # or 'osd' for smaller clusters
  
  # Replication
  replicated:
    size: 3  # 3 replicas for HA
    requireSafeReplicaSize: true
  
  # Mirroring (optional, for disaster recovery)
  mirroring:
    enabled: false
  
  # Status check
  statusCheck:
    mirror:
      disabled: false
      interval: 60s

---
# If you need CephFS
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: shared-fs
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 3
  dataPools:
    - name: replicated
      replicated:
        size: 3
  preserveFilesystemOnDelete: true
  metadataServer:
    activeCount: 1
    activeStandby: true
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 1Gi
Apply these:
bash# Create pools (optional)
kubectl apply -f rook-ceph-config/database-pool.yaml

# Create storage classes
kubectl apply -f rook-ceph-config/storage-classes.yaml

# Verify
kubectl get storageclass
kubectl get cephblockpool -n rook-ceph
Part 2: Deploy MongoDB (HA) with Rook-Ceph
yaml# argocd/apps/percona-mongodb-operator.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: percona-mongodb-operator
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://percona.github.io/percona-helm-charts
    chart: psmdb-operator
    targetRevision: 1.15.0
    helm:
      values: |
        replicas: 1
        
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: mongodb-operator

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
MongoDB Cluster with Rook-Ceph Storage
yaml# mongodb/mongodb-cluster.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mongodb
---
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-users
  namespace: mongodb
type: Opaque
stringData:
  MONGODB_BACKUP_USER: backup
  MONGODB_BACKUP_PASSWORD: backupSecure123!
  MONGODB_CLUSTER_ADMIN_USER: clusteradmin
  MONGODB_CLUSTER_ADMIN_PASSWORD: adminSecure123!
  MONGODB_CLUSTER_MONITOR_USER: monitor
  MONGODB_CLUSTER_MONITOR_PASSWORD: monitorSecure123!
  MONGODB_USER_ADMIN_USER: useradmin
  MONGODB_USER_ADMIN_PASSWORD: useradminSecure123!
---
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-encryption-key
  namespace: mongodb
type: Opaque
stringData:
  encryption-key: "MTIzNDU2Nzg5MGFiY2RlZjEyMzQ1Njc4OTBhYmNkZWY="  # 32 bytes base64
---
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: mongodb-ha
  namespace: mongodb
  finalizers:
    - delete-psmdb-pods-in-order
spec:
  crVersion: 1.15.0
  image: percona/percona-server-mongodb:6.0.9-7
  imagePullPolicy: IfNotPresent
  
  updateStrategy: SmartUpdate
  upgradeOptions:
    versionServiceEndpoint: https://check.percona.com
    apply: disabled  # Manual upgrades for production
  
  secrets:
    users: mongodb-users
    encryptionKey: mongodb-encryption-key
  
  # 3-node replica set for HA
  replsets:
    - name: rs0
      size: 3
      
      # Anti-affinity for HA
      affinity:
        antiAffinityTopologyKey: "kubernetes.io/hostname"
      
      # Resources per pod
      resources:
        requests:
          cpu: 500m
          memory: 2Gi
        limits:
          cpu: 2000m
          memory: 4Gi
      
      # Rook-Ceph storage
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: rook-ceph-block-retain
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 100Gi  # Adjust based on your needs
      
      # MongoDB configuration
      configuration: |
        operationProfiling:
          mode: slowOp
          slowOpThresholdMs: 100
        storage:
          engine: wiredTiger
          wiredTiger:
            engineConfig:
              cacheSizeGB: 1.5
            collectionConfig:
              blockCompressor: snappy
            indexConfig:
              prefixCompression: true
        net:
          compression:
            compressors: snappy,zstd
  
  # Backup to Ceph RGW or local PVC
  backup:
    enabled: true
    image: percona/percona-backup-mongodb:2.3.0
    
    pitr:
      enabled: false  # Point-in-time recovery (optional)
    
    # Tasks
    tasks:
      - name: daily-backup
        enabled: true
        schedule: "0 2 * * *"  # 2 AM daily
        keep: 7  # Keep 7 backups
        storageName: rook-ceph-fs
        compressionType: gzip
        compressionLevel: 6
    
    # Storage - using CephFS
    storages:
      rook-ceph-fs:
        type: filesystem
        volume:
          persistentVolumeClaim:
            storageClassName: rook-cephfs
            accessModes:
              - ReadWriteMany
            resources:
              requests:
                storage: 200Gi  # Backup storage
  
  # PMM monitoring (optional)
  pmm:
    enabled: false
Deploy MongoDB:
bashkubectl apply -f mongodb/mongodb-cluster.yaml

# Wait for MongoDB to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=percona-server-mongodb -n mongodb --timeout=600s

# Check status
kubectl get psmdb -n mongodb
kubectl get pods -n mongodb

# Connect to MongoDB
kubectl exec -it mongodb-ha-rs0-0 -n mongodb -- mongosh \
  --username clusteradmin \
  --password adminSecure123! \
  --authenticationDatabase admin

# Check replica set status
kubectl exec -it mongodb-ha-rs0-0 -n mongodb -- mongosh \
  --username clusteradmin \
  --password adminSecure123! \
  --authenticationDatabase admin \
  --eval "rs.status()"
Part 3: Deploy StackGres PostgreSQL with Rook-Ceph
yaml# argocd/apps/stackgres-operator.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: stackgres-operator
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://stackgres.io/downloads/stackgres-k8s/stackgres/helm
    chart: stackgres-operator
    targetRevision: 1.10.0
    helm:
      values: |
        operator:
          replicaCount: 1
        
        restapi:
          replicaCount: 1
        
        adminui:
          enabled: true
          service:
            type: ClusterIP
          
          ingress:
            enabled: true
            className: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
            hosts:
              - host: stackgres.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix
            tls:
              - secretName: stackgres-tls
                hosts:
                  - stackgres.yourdomain.local

  destination:
    server: https://kubernetes.default.svc
    namespace: stackgres

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
PostgreSQL Cluster with Rook-Ceph
yaml# postgres/postgres-cluster.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: postgres
---
apiVersion: stackgres.io/v1
kind: SGPostgresConfig
metadata:
  name: pgconfig-ha
  namespace: postgres
spec:
  postgresVersion: "15"
  postgresql.conf:
    shared_buffers: '512MB'
    effective_cache_size: '2GB'
    maintenance_work_mem: '256MB'
    checkpoint_completion_target: '0.9'
    wal_buffers: '16MB'
    default_statistics_target: '100'
    random_page_cost: '1.1'
    effective_io_concurrency: '200'
    work_mem: '5MB'
    huge_pages: 'try'
    min_wal_size: '1GB'
    max_wal_size: '4GB'
    max_worker_processes: '4'
    max_parallel_workers_per_gather: '2'
    max_parallel_workers: '4'

---
apiVersion: stackgres.io/v1
kind: SGPoolingConfig
metadata:
  name: poolconfig-ha
  namespace: postgres
spec:
  pgBouncer:
    pgbouncer.ini:
      pool_mode: transaction
      max_client_conn: '1000'
      default_pool_size: '25'
      reserve_pool_size: '5'

---
apiVersion: stackgres.io/v1
kind: SGBackupConfig
metadata:
  name: backupconfig-ceph
  namespace: postgres
spec:
  baseBackups:
    cronSchedule: '0 3 * * *'
    retention: 7
    compression: lz4
  
  storage:
    type: persistentVolume
    persistentVolume:
      size: 200Gi
      storageClass: rook-cephfs  # Shared filesystem for backups

---
apiVersion: stackgres.io/v1
kind: SGDistributedLogs
metadata:
  name: distributedlogs
  namespace: postgres
spec:
  persistentVolume:
    size: 20Gi
    storageClass: rook-ceph-block

---
apiVersion: stackgres.io/v1
kind: SGCluster
metadata:
  name: postgres-ha
  namespace: postgres
spec:
  instances: 3  # 3 PostgreSQL instances
  
  postgres:
    version: '15.5'
    extensions:
      - name: pg_repack
      - name: pgcrypto
      - name: uuid-ossp
      - name: pg_stat_statements
  
  pods:
    # Rook-Ceph storage
    persistentVolume:
      storageClass: rook-ceph-block-retain
      size: 100Gi
    
    # Anti-affinity
    scheduling:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: kubernetes.io/hostname
                  operator: Exists
    
    # Resources
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi
    
    disableConnectionPooling: false
    disableMetricsExporter: false
  
  configurations:
    sgPostgresConfig: pgconfig-ha
    sgPoolingConfig: poolconfig-ha
    sgBackupConfig: backupconfig-ceph
  
  replication:
    mode: async
    role: ha-read
  
  distributedLogs:
    sgDistributedLogs: distributedlogs
  
  prometheusAutobind: true
  
  # Initial databases
  initialData:
    restore:
      fromBackup:
        name: ""  # Leave empty for new cluster
Deploy PostgreSQL:
bashkubectl apply -f postgres/postgres-cluster.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=ready pod -l app=StackGresCluster -n postgres --timeout=600s

# Check status
kubectl get sgclusters -n postgres
kubectl get pods -n postgres

# Get credentials
kubectl get secret postgres-ha -n postgres -o jsonpath='{.data.superuser-password}' | base64 -d

# Connect
kubectl exec -it postgres-ha-0 -n postgres -c postgres-util -- psql
Part 4: Deploy Kafka (Strimzi) with Rook-Ceph
yaml# argocd/apps/strimzi-operator.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: strimzi-operator
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://strimzi.io/charts
    chart: strimzi-kafka-operator
    targetRevision: 0.39.0
    helm:
      values: |
        replicas: 1
        watchAnyNamespace: true
        featureGates: "+UseKRaft,+KafkaNodePools"

  destination:
    server: https://kubernetes.default.svc
    namespace: kafka-operator

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Kafka Cluster with Rook-Ceph
yaml# kafka/kafka-cluster.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kafka
---
# KRaft Controllers
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: controller
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-ha
spec:
  replicas: 3
  roles:
    - controller
  
  # Rook-Ceph storage
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 20Gi
        class: rook-ceph-block-retain
        deleteClaim: false
  
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi

---
# Kafka Brokers
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: broker
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-ha
spec:
  replicas: 3
  roles:
    - broker
  
  # Rook-Ceph storage
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 200Gi  # Adjust based on your needs
        class: rook-ceph-block-retain
        deleteClaim: false
  
  resources:
    requests:
      cpu: 1000m
      memory: 4Gi
    limits:
      cpu: 4000m
      memory: 8Gi

---
# Kafka Cluster
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: kafka-ha
  namespace: kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.6.1
    metadataVersion: 3.6-IV2
    
    # Listeners
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication:
          type: tls
      - name: external
        port: 9094
        type: nodeport
        tls: true
        authentication:
          type: scram-sha-512
    
    authorization:
      type: simple
      superUsers:
        - admin
    
    # Configuration
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
      num.network.threads: 8
      num.io.threads: 8
      log.retention.hours: 168
      log.segment.bytes: 1073741824
      auto.create.topics.enable: false
      compression.type: snappy
    
    # Rack awareness
    rack:
      topologyKey: kubernetes.io/hostname
    
    # Metrics
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
  
  entityOperator:
    topicOperator:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
    userOperator:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
  
  kafkaExporter:
    topicRegex: ".*"
    groupRegex: ".*"

---
# Kafka metrics ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-metrics
  namespace: kafka
data:
  kafka-metrics-config.yml: |
    lowercaseOutputName: true
    rules:
      - pattern: kafka.server<type=(.+), name=(.+)><>Value
        name: kafka_server_$1_$2
        type: GAUGE
Deploy Kafka:
bashkubectl apply -f kafka/kafka-cluster.yaml

# Wait for Kafka
kubectl wait --for=condition=ready kafka kafka-ha -n kafka --timeout=600s

# Check status
kubectl get kafka -n kafka
kubectl get pods -n kafka

# Create a test topic
cat <<EOF | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: test-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-ha
spec:
  partitions: 3
  replicas: 3
  config:
    retention.ms: 604800000
    min.insync.replicas: 2
EOF
Part 5: Deploy Authentik with Rook-Ceph
yaml# argocd/apps/authentik.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: authentik
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://charts.goauthentik.io
    chart: authentik
    targetRevision: 2024.2.0
    helm:
      values: |
        global:
          env:
            - name: AUTHENTIK_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: authentik-secrets
                  key: secret_key
            - name: AUTHENTIK_ERROR_REPORTING__ENABLED
              value: "false"
        
        server:
          replicas: 2
          
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
          
          ingress:
            enabled: true
            ingressClassName: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
              nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
            hosts:
              - host: auth.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix
            tls:
              - secretName: authentik-tls
                hosts:
                  - auth.yourdomain.local
        
        worker:
          replicas: 2
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
        
        # Use existing PostgreSQL from StackGres
        postgresql:
          enabled: false
        
        authentik:
          postgresql:
            host: "postgres-ha-primary.postgres.svc.cluster.local"
            name: "authentik"
            user: "authentik"
            password: "authentik_password"  # Create this user in PostgreSQL
            port: 5432
        
        # Redis with Rook-Ceph storage
        redis:
          enabled: true
          architecture: standalone
          auth:
            enabled: true
            password: "redis-password-here"
          master:
            persistence:
              enabled: true
              storageClass: rook-ceph-block
              size: 5Gi
            resources:
              requests:
                cpu: 100m
                memory: 128Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: authentik

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Prepare PostgreSQL for Authentik
bash# Create Authentik database in PostgreSQL
kubectl exec -it postgres-ha-0 -n postgres -c postgres-util -- psql << EOF
CREATE DATABASE authentik;
CREATE USER authentik WITH ENCRYPTED PASSWORD 'authentik_password';
GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;
\c authentik
GRANT ALL ON SCHEMA public TO authentik;
EOF
Create Authentik Secrets
yaml# authentik/secrets.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: authentik
---
apiVersion: v1
kind: Secret
metadata:
  name: authentik-secrets
  namespace: authentik
type: Opaque
stringData:
  # Generate with: openssl rand -base64 60
  secret_key: "your-generated-secret-key-here-make-it-long-and-random"
Deploy Authentik:
bash# Create secrets first
kubectl apply -f authentik/secrets.yaml

# Deploy Authentik
kubectl apply -f argocd/apps/authentik.yaml

# Wait for it
kubectl wait --for=condition=available deployment/authentik-server -n authentik --timeout=600s

# Access it
kubectl port-forward -n authentik svc/authentik-server 9000:80
# Open: http://localhost:9000/if/flow/initial-setup/
Part 6: Configure Authentik SSO
Initial Setup

Access Authentik at https://auth.yourdomain.local or port-forward
Complete initial setup wizard
Create admin account
Log in to admin interface

Configure ArgoCD OIDC
In Authentik UI:

Applications → Providers → Create

Type: OAuth2/OpenID Connect Provider
Name: ArgoCD
Authorization flow: default-provider-authorization-implicit-consent
Client type: Confidential
Redirect URIs: https://argocd.yourdomain.local/auth/callback
Scopes: openid, profile, email, groups


Applications → Create

Name: ArgoCD
Slug: argocd
Provider: Select the ArgoCD provider


Note the Client ID and Client Secret

Configure ArgoCD:
yaml# argocd/argocd-cm-patch.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.yourdomain.local
  
  oidc.config: |
    name: Authentik
    issuer: https://auth.yourdomain.local/application/o/argocd/
    clientID: YOUR_CLIENT_ID_FROM_AUTHENTIK
    clientSecret: $oidc.authentik.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
      - groups
    requestedIDTokenClaims:
      groups:
        essential: true

---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
stringData:
  oidc.authentik.clientSecret: "YOUR_CLIENT_SECRET_FROM_AUTHENTIK"

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    # Authentik Admins group gets admin role
    g, authentik Admins, role:admin
    
    # Developers group
    g, Developers, role:developer
    
    # Developer role definition
    p, role:developer, applications, *, */*, allow
    p, role:developer, repositories, *, *, allow
    p, role:developer, clusters, get, *, allow
  
  scopes: '[groups, email]'
Apply:
bashkubectl apply -f argocd/argocd-cm-patch.yaml
kubectl rollout restart deployment argocd-server -n argocd
Configure Ceph Dashboard SAML
In Authentik:

Providers → Create

Type: SAML Provider
Name: Ceph Dashboard
ACS URL: https://ceph-dashboard.yourdomain.local/auth/saml2/acs
Issuer: https://auth.yourdomain.local
Service Provider Binding: Post
Audience: ceph-dashboard


Create Application for Ceph

On Ceph:
bash# Enter toolbox
kubectl exec -it -n rook-ceph deploy/rook-ceph-tools -- bash

# Configure SAML
ceph dashboard sso setup saml2 \
  https://auth.yourdomain.local/application/saml/ceph-dashboard/metadata/ \
  https://ceph-dashboard.yourdomain.local \
  ceph-dashboard \
  'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST'

# Set username attribute
ceph dashboard sso set username_attribute username

# Enable SSO
ceph dashboard sso enable saml2

# Restart dashboard
ceph mgr module disable dashboard
ceph mgr module enable dashboard
Configure Other Services
StackGres:
yaml# Update StackGres operator
adminui:
  oidc:
    enabled: true
    issuer: https://auth.yourdomain.local/application/o/stackgres/
    clientId: YOUR_CLIENT_ID
    clientSecret: YOUR_CLIENT_SECRET
Kargo:
yamlkargo:
  api:
    oidc:
      enabled: true
      issuerURL: https://auth.yourdomain.local/application/o/kargo/
      clientID: YOUR_CLIENT_ID
      clientSecret: YOUR_CLIENT_SECRET
Infisical:
yamlbackend:
  env:
    - name: CLIENT_ID_OIDC
      value: "YOUR_CLIENT_ID"
    - name: CLIENT_SECRET_OIDC
      value: "YOUR_CLIENT_SECRET"
    - name: AUTH_URL_OIDC
      value: "https://auth.yourdomain.local/application/o/infisical/"
Part 7: Complete Deployment Script
bash#!/bin/bash
# deploy-all-rook.sh

set -e

echo "=== Checking Rook-Ceph Status ==="
kubectl get cephcluster -n rook-ceph
kubectl exec -it -n rook-ceph deploy/rook-ceph-tools -- ceph status

echo "=== Creating Storage Classes ==="
kubectl apply -f rook-ceph-config/storage-classes.yaml

echo "=== Deploying MongoDB ==="
kubectl apply -f argocd/apps/percona-mongodb-operator.yaml
sleep 30
kubectl apply -f mongodb/mongodb-cluster.yaml

echo "=== Deploying StackGres ==="
kubectl apply -f argocd/apps/stackgres-operator.yaml
sleep 30
kubectl apply -f postgres/postgres-cluster.yaml

echo "=== Deploying Kafka ==="
kubectl apply -f argocd/apps/strimzi-operator.yaml
sleep 30
kubectl apply -f kafka/kafka-cluster.yaml

echo "=== Preparing PostgreSQL for Authentik ==="
kubectl wait --for=condition=ready pod/postgres-ha-0 -n postgres --timeout=600s
kubectl exec -it postgres-ha-0 -n postgres -c postgres-util -- psql << EOF
CREATE DATABASE authentik;
CREATE USER authentik WITH ENCRYPTED PASSWORD 'authentik_password';
GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;
\c authentik
GRANT ALL ON SCHEMA public TO authentik;
EOF

echo "=== Deploying Authentik ==="
kubectl apply -f authentik/secrets.yaml
kubectl apply -f argocd/apps/authentik.yaml

echo "==="
echo "Deployment Complete!"
echo ""
echo "Access:"
echo "  Authentik:  https://auth.yourdomain.local"
echo "  StackGres:  https://stackgres.yourdomain.local"
echo "  ArgoCD:     https://argocd.yourdomain.local"
echo ""
echo "Check status:"
echo "  kubectl get psmdb -n mongodb"
echo "  kubectl get sgcluster -n postgres"
echo "  kubectl get kafka -n kafka"
echo "  kubectl get pods -n authentik"
echo "==="
Verification
bash# Check storage
kubectl get pv
kubectl get pvc --all-namespaces

# Check MongoDB
kubectl get psmdb -n mongodb
kubectl exec -it mongodb-ha-rs0-0 -n mongodb -- mongosh --eval "rs.status()" --quiet

# Check PostgreSQL
kubectl get sgcluster -n postgres
kubectl exec -it postgres-ha-0 -n postgres -c postgres-util -- psql -c "\l"

# Check Kafka
kubectl get kafka -n kafka
kubectl get kafkatopics -n kafka

# Check Authentik
kubectl get pods -n authentik
curl -k https://auth.yourdomain.local/.well-known/openid-configuration
This gives you a complete HA setup using your existing Rook-Ceph cluster! Would you like help with monitoring, backups, or specific SSO configuration for any service?NI also want to deploy a complete monitoring and observability setup with status pages as well. I want it to be comprehensive.Here's a comprehensive monitoring and observability setup for your infrastructure:
Part 1: Deploy Kube-Prometheus Stack
This includes Prometheus, Grafana, Alertmanager, and essential exporters.
yaml# argocd/apps/kube-prometheus-stack.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 55.5.0
    helm:
      values: |
        # Global settings
        global:
          rbac:
            create: true
        
        # Prometheus Operator
        prometheusOperator:
          enabled: true
          
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 512Mi
        
        # Prometheus
        prometheus:
          enabled: true
          
          prometheusSpec:
            # Retention
            retention: 30d
            retentionSize: "45GB"
            
            # Resources
            resources:
              requests:
                cpu: 500m
                memory: 2Gi
              limits:
                cpu: 2000m
                memory: 8Gi
            
            # Storage - Rook-Ceph
            storageSpec:
              volumeClaimTemplate:
                spec:
                  storageClassName: rook-ceph-block-retain
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 50Gi
            
            # Replicas for HA
            replicas: 2
            
            # Service monitors - auto-discover
            serviceMonitorSelectorNilUsesHelmValues: false
            podMonitorSelectorNilUsesHelmValues: false
            ruleSelectorNilUsesHelmValues: false
            
            # External labels for multi-cluster
            externalLabels:
              cluster: production
              region: region1
            
            # Remote write to Thanos (we'll set this up)
            # remoteWrite: []
            
            # Additional scrape configs
            additionalScrapeConfigs:
              - job_name: 'kubernetes-pods'
                kubernetes_sd_configs:
                  - role: pod
                relabel_configs:
                  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                    action: keep
                    regex: true
                  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
                    action: replace
                    target_label: __metrics_path__
                    regex: (.+)
                  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
                    action: replace
                    regex: ([^:]+)(?::\d+)?;(\d+)
                    replacement: $1:$2
                    target_label: __address__
        
        # Grafana
        grafana:
          enabled: true
          
          replicas: 2
          
          adminPassword: "admin"  # Change this!
          
          # Persistence
          persistence:
            enabled: true
            storageClassName: rook-ceph-block
            size: 10Gi
          
          # Resources
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          
          # Ingress
          ingress:
            enabled: true
            ingressClassName: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
              nginx.ingress.kubernetes.io/auth-url: "https://auth.yourdomain.local/outpost.goauthentik.io/auth/nginx"
              nginx.ingress.kubernetes.io/auth-signin: "https://auth.yourdomain.local/outpost.goauthentik.io/start?rd=$escaped_request_uri"
              nginx.ingress.kubernetes.io/auth-response-headers: "Set-Cookie,X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid"
              nginx.ingress.kubernetes.io/auth-snippet: |
                proxy_set_header X-Forwarded-Host $http_host;
            hosts:
              - grafana.yourdomain.local
            tls:
              - secretName: grafana-tls
                hosts:
                  - grafana.yourdomain.local
          
          # Grafana configuration
          grafana.ini:
            server:
              root_url: https://grafana.yourdomain.local
            
            # Authentik OAuth
            auth.generic_oauth:
              enabled: true
              name: Authentik
              client_id: YOUR_GRAFANA_CLIENT_ID
              client_secret: $__file{/etc/secrets/auth_generic_oauth/client_secret}
              scopes: openid profile email groups
              auth_url: https://auth.yourdomain.local/application/o/authorize/
              token_url: https://auth.yourdomain.local/application/o/token/
              api_url: https://auth.yourdomain.local/application/o/userinfo/
              role_attribute_path: contains(groups[*], 'Grafana Admins') && 'Admin' || contains(groups[*], 'Grafana Editors') && 'Editor' || 'Viewer'
            
            analytics:
              check_for_updates: false
              reporting_enabled: false
            
            log:
              mode: console
              level: info
          
          # Additional data sources
          additionalDataSources:
            - name: Loki
              type: loki
              url: http://loki-gateway.monitoring.svc.cluster.local
              access: proxy
              isDefault: false
            
            - name: Tempo
              type: tempo
              url: http://tempo.monitoring.svc.cluster.local:3100
              access: proxy
              isDefault: false
            
            - name: Alertmanager
              type: alertmanager
              url: http://kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093
              access: proxy
              isDefault: false
          
          # Dashboards
          dashboardProviders:
            dashboardproviders.yaml:
              apiVersion: 1
              providers:
                - name: 'default'
                  orgId: 1
                  folder: ''
                  type: file
                  disableDeletion: false
                  editable: true
                  options:
                    path: /var/lib/grafana/dashboards/default
                
                - name: 'infrastructure'
                  orgId: 1
                  folder: 'Infrastructure'
                  type: file
                  disableDeletion: false
                  editable: true
                  options:
                    path: /var/lib/grafana/dashboards/infrastructure
                
                - name: 'applications'
                  orgId: 1
                  folder: 'Applications'
                  type: file
                  disableDeletion: false
                  editable: true
                  options:
                    path: /var/lib/grafana/dashboards/applications
          
          # Pre-load dashboards
          dashboards:
            default:
              kubernetes-cluster:
                gnetId: 7249
                revision: 1
                datasource: Prometheus
              
              node-exporter:
                gnetId: 1860
                revision: 31
                datasource: Prometheus
              
              kubernetes-resources:
                gnetId: 13770
                revision: 1
                datasource: Prometheus
            
            infrastructure:
              ceph-cluster:
                gnetId: 2842
                revision: 16
                datasource: Prometheus
              
              ceph-pools:
                gnetId: 5342
                revision: 9
                datasource: Prometheus
              
              rook-ceph:
                gnetId: 12114
                revision: 1
                datasource: Prometheus
            
            applications:
              mongodb:
                gnetId: 2583
                revision: 2
                datasource: Prometheus
              
              postgresql:
                gnetId: 9628
                revision: 7
                datasource: Prometheus
              
              kafka:
                gnetId: 7589
                revision: 5
                datasource: Prometheus
              
              argocd:
                gnetId: 14584
                revision: 1
                datasource: Prometheus
          
          # Plugins
          plugins:
            - grafana-piechart-panel
            - grafana-clock-panel
            - grafana-simple-json-datasource
            - grafana-worldmap-panel
          
          # SMTP for alerts (optional)
          smtp:
            enabled: false
            host: smtp.yourdomain.local:587
            user: grafana@yourdomain.local
            password: your-password
            from_address: grafana@yourdomain.local
        
        # Alertmanager
        alertmanager:
          enabled: true
          
          alertmanagerSpec:
            replicas: 3  # HA
            
            # Storage
            storage:
              volumeClaimTemplate:
                spec:
                  storageClassName: rook-ceph-block
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 10Gi
            
            # Resources
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                cpu: 500m
                memory: 512Mi
          
          # Ingress
          ingress:
            enabled: true
            ingressClassName: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
            hosts:
              - alertmanager.yourdomain.local
            tls:
              - secretName: alertmanager-tls
                hosts:
                  - alertmanager.yourdomain.local
          
          # Configuration
          config:
            global:
              resolve_timeout: 5m
            
            route:
              group_by: ['alertname', 'cluster', 'service']
              group_wait: 10s
              group_interval: 10s
              repeat_interval: 12h
              receiver: 'null'
              routes:
                - match:
                    alertname: Watchdog
                  receiver: 'null'
                
                - match:
                    severity: critical
                  receiver: critical
                  continue: true
                
                - match:
                    severity: warning
                  receiver: warning
            
            receivers:
              - name: 'null'
              
              - name: critical
                slack_configs:
                  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
                    channel: '#critical-alerts'
                    title: '{{ .GroupLabels.alertname }}'
                    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
                
                email_configs:
                  - to: 'ops-team@yourdomain.local'
                    from: 'alertmanager@yourdomain.local'
                    smarthost: 'smtp.yourdomain.local:587'
                    auth_username: 'alertmanager@yourdomain.local'
                    auth_password: 'your-password'
              
              - name: warning
                slack_configs:
                  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
                    channel: '#alerts'
                    title: '{{ .GroupLabels.alertname }}'
                    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        
        # Node Exporter
        nodeExporter:
          enabled: true
        
        # Kube State Metrics
        kubeStateMetrics:
          enabled: true
        
        # Additional components
        kubeControllerManager:
          enabled: true
        
        kubeScheduler:
          enabled: true
        
        kubeProxy:
          enabled: true
        
        kubeEtcd:
          enabled: true
        
        coreDns:
          enabled: true

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
Part 2: Deploy Loki Stack (Logging)
yaml# argocd/apps/loki-stack.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki-stack
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: loki
    targetRevision: 5.41.0
    helm:
      values: |
        # Deployment mode
        deploymentMode: SimpleScalable
        
        loki:
          # Authentication
          auth_enabled: false
          
          # Common config
          commonConfig:
            replication_factor: 3
          
          # Storage
          storage:
            type: s3
            bucketNames:
              chunks: loki-chunks
              ruler: loki-ruler
              admin: loki-admin
            s3:
              endpoint: rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local
              region: us-east-1
              secretAccessKey: ${S3_SECRET_KEY}
              accessKeyId: ${S3_ACCESS_KEY}
              s3ForcePathStyle: true
              insecure: true
          
          # Schema config
          schemaConfig:
            configs:
              - from: 2024-01-01
                store: tsdb
                object_store: s3
                schema: v12
                index:
                  prefix: loki_index_
                  period: 24h
          
          # Limits
          limits_config:
            retention_period: 30d
            ingestion_rate_mb: 10
            ingestion_burst_size_mb: 20
            max_cache_freshness_per_query: 10m
            split_queries_by_interval: 15m
            reject_old_samples: true
            reject_old_samples_max_age: 168h
          
          # Compactor for retention
          compactor:
            retention_enabled: true
            retention_delete_delay: 2h
            retention_delete_worker_count: 150
        
        # Components
        backend:
          replicas: 3
          
          persistence:
            enabled: true
            storageClass: rook-ceph-block
            size: 10Gi
          
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
        
        read:
          replicas: 3
          
          persistence:
            enabled: true
            storageClass: rook-ceph-block
            size: 10Gi
          
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
        
        write:
          replicas: 3
          
          persistence:
            enabled: true
            storageClass: rook-ceph-block
            size: 10Gi
          
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
        
        # Gateway
        gateway:
          enabled: true
          replicas: 2
          
          ingress:
            enabled: true
            ingressClassName: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
            hosts:
              - host: loki.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix
            tls:
              - secretName: loki-tls
                hosts:
                  - loki.yourdomain.local
        
        # Monitoring
        monitoring:
          selfMonitoring:
            enabled: true
            grafanaAgent:
              installOperator: false
          
          serviceMonitor:
            enabled: true
          
          lokiCanary:
            enabled: true

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
Deploy Promtail (Log Collector)
yaml# argocd/apps/promtail.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: promtail
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: promtail
    targetRevision: 6.15.0
    helm:
      values: |
        # DaemonSet on every node
        daemonset:
          enabled: true
        
        # Configuration
        config:
          clients:
            - url: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
          
          snippets:
            pipelineStages:
              - cri: {}
              - json:
                  expressions:
                    level: level
                    logger: logger
                    message: message
              - labels:
                  level:
                  logger:
              - output:
                  source: message
        
        # Resources
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        
        # Service Monitor
        serviceMonitor:
          enabled: true

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
Part 3: Deploy Tempo (Distributed Tracing)
yaml# argocd/apps/tempo.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tempo
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: tempo-distributed
    targetRevision: 1.7.0
    helm:
      values: |
        # Global config
        tempo:
          retention: 720h  # 30 days
          
          # Storage
          storage:
            trace:
              backend: s3
              s3:
                bucket: tempo-traces
                endpoint: rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local:80
                region: us-east-1
                access_key: ${S3_ACCESS_KEY}
                secret_key: ${S3_SECRET_KEY}
                insecure: true
          
          # Receivers
          receivers:
            jaeger:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:14250
                thrift_http:
                  endpoint: 0.0.0.0:14268
                thrift_binary:
                  endpoint: 0.0.0.0:6832
            otlp:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:4317
                http:
                  endpoint: 0.0.0.0:4318
            zipkin:
              endpoint: 0.0.0.0:9411
        
        # Components
        distributor:
          replicas: 3
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
        
        ingester:
          replicas: 3
          
          persistence:
            enabled: true
            storageClass: rook-ceph-block
            size: 10Gi
          
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
        
        querier:
          replicas: 2
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
        
        queryFrontend:
          replicas: 2
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
        
        compactor:
          replicas: 1
          
          persistence:
            enabled: true
            storageClass: rook-ceph-block
            size: 10Gi
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
        
        # Monitoring
        serviceMonitor:
          enabled: true
        
        # Gateway
        gateway:
          enabled: true
          replicas: 2
          
          ingress:
            enabled: true
            ingressClassName: nginx
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
            hosts:
              - host: tempo.yourdomain.local
                paths:
                  - path: /
                    pathType: Prefix
            tls:
              - secretName: tempo-tls
                hosts:
                  - tempo.yourdomain.local

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
Part 4: Deploy OpenTelemetry Collector
yaml# argocd/apps/opentelemetry-collector.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: opentelemetry-collector
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts
    chart: opentelemetry-collector
    targetRevision: 0.79.0
    helm:
      values: |
        mode: daemonset
        
        # Configuration
        config:
          receivers:
            otlp:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:4317
                http:
                  endpoint: 0.0.0.0:4318
            
            prometheus:
              config:
                scrape_configs:
                  - job_name: 'otel-collector'
                    scrape_interval: 10s
                    static_configs:
                      - targets: ['0.0.0.0:8888']
            
            jaeger:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:14250
                thrift_http:
                  endpoint: 0.0.0.0:14268
          
          processors:
            batch:
              timeout: 10s
              send_batch_size: 1024
            
            memory_limiter:
              check_interval: 1s
              limit_mib: 512
            
            resource:
              attributes:
                - key: cluster
                  value: production
                  action: insert
          
          exporters:
            # Prometheus
            prometheus:
              endpoint: "0.0.0.0:8889"
            
            # Loki for logs
            loki:
              endpoint: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
            
            # Tempo for traces
            otlp/tempo:
              endpoint: tempo-distributor.monitoring.svc.cluster.local:4317
              tls:
                insecure: true
            
            # Debug
            logging:
              loglevel: info
          
          service:
            pipelines:
              traces:
                receivers: [otlp, jaeger]
                processors: [memory_limiter, batch]
                exporters: [otlp/tempo, logging]
              
              metrics:
                receivers: [otlp, prometheus]
                processors: [memory_limiter, batch]
                exporters: [prometheus]
              
              logs:
                receivers: [otlp]
                processors: [memory_limiter, batch]
                exporters: [loki, logging]
        
        # Resources
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        
        # Service Monitor
        serviceMonitor:
          enabled: true

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
Part 5: Deploy Blackbox Exporter (Probes)
yaml# argocd/apps/blackbox-exporter.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: blackbox-exporter
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: prometheus-blackbox-exporter
    targetRevision: 8.8.0
    helm:
      values: |
        # Configuration
        config:
          modules:
            http_2xx:
              prober: http
              timeout: 5s
              http:
                valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
                valid_status_codes: [200, 301, 302]
                method: GET
                preferred_ip_protocol: "ip4"
            
            http_post_2xx:
              prober: http
              timeout: 5s
              http:
                method: POST
                valid_status_codes: [200, 201]
            
            tcp_connect:
              prober: tcp
              timeout: 5s
            
            icmp:
              prober: icmp
              timeout: 5s
            
            dns:
              prober: dns
              timeout: 5s
              dns:
                query_name: "kubernetes.default.svc.cluster.local"
                query_type: "A"
        
        # Service Monitor
        serviceMonitor:
          enabled: true
          defaults:
            labels:
              release: kube-prometheus-stack
            interval: 30s
            scrapeTimeout: 30s
          
          targets:
            # Web endpoints
            - name: argocd
              url: https://argocd.yourdomain.local
              module: http_2xx
            
            - name: grafana
              url: https://grafana.yourdomain.local
              module: http_2xx
            
            - name: authentik
              url: https://auth.yourdomain.local
              module: http_2xx
            
            - name: stackgres
              url: https://stackgres.yourdomain.local
              module: http_2xx
            
            # Internal services
            - name: prometheus
              url: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
              module: http_2xx
            
            - name: loki
              url: http://loki-gateway.monitoring.svc.cluster.local
              module: http_2xx

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
Part 6: Deploy Uptime Kuma (Status Page)
yaml# argocd/apps/uptime-kuma.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: uptime-kuma
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/yourorg/gitops-repo
    targetRevision: main
    path: charts/uptime-kuma
  
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
Uptime Kuma Chart
yaml# charts/uptime-kuma/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: uptime-kuma
  namespace: monitoring
spec:
  replicas: 1  # Uptime Kuma doesn't support HA
  selector:
    matchLabels:
      app: uptime-kuma
  template:
    metadata:
      labels:
        app: uptime-kuma
    spec:
      containers:
        - name: uptime-kuma
          image: louislam/uptime-kuma:1.23.11
          ports:
            - containerPort: 3001
              name: http
          
          env:
            - name: UPTIME_KUMA_PORT
              value: "3001"
          
          volumeMounts:
            - name: data
              mountPath: /app/data
          
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          
          livenessProbe:
            httpGet:
              path: /
              port: 3001
            initialDelaySeconds: 60
            periodSeconds: 30
          
          readinessProbe:
            httpGet:
              path: /
              port: 3001
            initialDelaySeconds: 30
            periodSeconds: 10
      
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: uptime-kuma-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: uptime-kuma-data
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: rook-ceph-block-retain
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: uptime-kuma
  namespace: monitoring
spec:
  selector:
    app: uptime-kuma
  ports:
    - port: 3001
      targetPort: 3001
      name: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: uptime-kuma
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/websocket-services: uptime-kuma
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - status.yourdomain.local
      secretName: uptime-kuma-tls
  rules:
    - host: status.yourdomain.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: uptime-kuma
                port:
                  number: 3001
Part 7: Deploy Gatus (Alternative/Additional Status Page)
yaml# argocd/apps/gatus.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatus
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/yourorg/gitops-repo
    targetRevision: main
    path: charts/gatus
  
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
Gatus Configuration
yaml# charts/gatus/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gatus-config
  namespace: monitoring
data:
  config.yaml: |
    # Storage
    storage:
      type: postgres
      path: postgres://gatus:password@postgres-ha-primary.postgres.svc.cluster.local:5432/gatus?sslmode=disable
    
    # Metrics
    metrics: true
    
    # Web configuration
    web:
      port: 8080
    
    # Alerting
    alerting:
      slack:
        webhook-url: "YOUR_SLACK_WEBHOOK"
        default-alert:
          description: "Health check failed"
          send-on-resolved: true
          failure-threshold: 3
          success-threshold: 2
      
      email:
        from: "gatus@yourdomain.local"
        username: "gatus@yourdomain.local"
        password: "your-password"
        host: "smtp.yourdomain.local"
        port: 587
        to: "ops-team@yourdomain.local"
        default-alert:
          description: "Health check failed"
          send-on-resolved: true
          failure-threshold: 5
          success-threshold: 2
    
    # Endpoints to monitor
    endpoints:
      # ArgoCD
      - name: ArgoCD UI
        group: GitOps
        url: "https://argocd.yourdomain.local"
        interval: 60s
        conditions:
          - "[STATUS] == 200"
          - "[RESPONSE_TIME] < 1000"
        alerts:
          - type: slack
          - type: email
      
      - name: ArgoCD API
        group: GitOps
        url: "https://argocd.yourdomain.local/api/version"
        interval: 60s
        conditions:
          - "[STATUS] == 200"
          - "[BODY].Version != \"\""
      
      # Grafana
      - name: Grafana
        group: Monitoring
        url: "https://grafana.yourdomain.local/api/health"
        interval: 60s
        conditions:
          - "[STATUS] == 200"
          - "[BODY].database == \"ok\""
        alerts:
          - type: slack
          - type: email
      
      # Authentik
      - name: Authentik
        group: Authentication
        url: "https://auth.yourdomain.local/-/health/ready/"
        interval: 60s
        conditions:
          - "[STATUS] == 200"
        alerts:
          - type: slack
          - type: email
      
      # StackGres
      - name: StackGres UI
        group: Databases
        url: "https://stackgres.yourdomain.local"
        interval: 60s
        conditions:
          - "[STATUS] == 200"
      
      # PostgreSQL
      - name: PostgreSQL (Primary)
        group: Databases
        url: "postgres://gatus:password@postgres-ha-primary.postgres.svc.cluster.local:5432/postgres?sslmode=disable"
        interval: 60s
        conditions:
          - "[CONNECTED] == true"
        alerts:
          - type: slack
            failure-threshold: 2
      
      # MongoDB
      - name: MongoDB
        group: Databases
        url: "mongodb://clusteradmin:adminSecure123!@mongodb-ha-rs0-0.mongodb-ha-rs0.mongodb.svc.cluster.local:27017/admin"
        interval: 60s
        conditions:
          - "[CONNECTED] == true"
        alerts:
          - type: slack
            failure-threshold: 2
      
      # Kafka
      - name: Kafka Broker
        group: Messaging
        url: "kafka-ha-kafka-bootstrap.kafka.svc.cluster.local:9092"
        interval: 60s
        conditions:
          - "[CONNECTED] == true"
        alerts:
          - type: slack
            failure-threshold: 2
      
      # Prometheus
      - name: Prometheus
        group: Monitoring
        url: "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/-/healthy"
        interval: 30s
        conditions:
          - "[STATUS] == 200"
        alerts:
          - type: slack
            failure-threshold: 3
      
      # Loki
      - name: Loki
        group: Monitoring
        url: "http://loki-gateway.monitoring.svc.cluster.local/ready"
        interval: 60s
        conditions:
          - "[STATUS] == 200"
      
      # Tempo
      - name: Tempo
        group: Monitoring
        url: "http://tempo-query-frontend.monitoring.svc.cluster.local:3100/ready"
        interval: 60s
        conditions:
          - "[STATUS] == 200"
      
      # Rook-Ceph
      - name: Ceph Health
        group: Storage
        url: "http://rook-ceph-mgr-dashboard.rook-ceph.svc.cluster.local:7000/api/health/minimal"
        interval: 60s
        conditions:
          - "[STATUS] == 200"
        alerts:
          - type: slack
            failure-threshold: 2
          - type: email
            failure-threshold: 3
      
      # DNS
      - name: Internal DNS
        group: Infrastructure
        url: "8.8.8.8"
        interval: 60s
        dns:
          query-name: "kubernetes.default.svc.cluster.local"
          query-type: "A"
        conditions:
          - "[DNS_RCODE] == NOERROR"
      
      # Kubernetes API
      - name: Kubernetes API
        group: Infrastructure
        url: "https://kubernetes.default.svc.cluster.local/healthz"
        interval: 30s
        conditions:
          - "[STATUS] == 200"
        alerts:
          - type: slack
            failure-threshold: 2
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gatus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gatus
  template:
    metadata:
      labels:
        app: gatus
    spec:
      containers:
        - name: gatus
          image: twinproduction/gatus:v5.8.0
          ports:
            - containerPort: 8080
              name: http
          
          volumeMounts:
            - name: config
              mountPath: /config
          
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
      
      volumes:
        - name: config
          configMap:
            name: gatus-config
---
apiVersion: v1
kind: Service
metadata:
  name: gatus
  namespace: monitoring
spec:
  selector:
    app: gatus
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gatus
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - health.yourdomain.local
      secretName: gatus-tls
  rules:
    - host: health.yourdomain.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: gatus
                port:
                  number: 8080
Part 8: Service Monitors for All Components
yaml# monitoring/servicemonitors/argocd.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: argocd
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
  endpoints:
    - port: metrics
---
# monitoring/servicemonitors/mongodb.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-metrics
  namespace: mongodb
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: percona-server-mongodb
  endpoints:
    - port: metrics
---
# monitoring/servicemonitors/stackgres.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: stackgres-metrics
  namespace: postgres
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: StackGresCluster
  endpoints:
    - port: postgres-exporter
---
# monitoring/servicemonitors/kafka.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kafka-metrics
  namespace: kafka
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      strimzi.io/kind: Kafka
  endpoints:
    - port: tcp-prometheus
---
# monitoring/servicemonitors/authentik.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: authentik-metrics
  namespace: authentik
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: authentik
  endpoints:
    - port: http
      path: /metrics
---
# monitoring/servicemonitors/kargo.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kargo-metrics
  namespace: kargo
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: kargo
  endpoints:
    - port: metrics
---
# monitoring/servicemonitors/rook-ceph.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rook-ceph-mgr
  namespace: rook-ceph
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: rook-ceph-mgr
  endpoints:
    - port: http-metrics
Part 9: Custom Alerts
yaml# monitoring/alerts/infrastructure.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: infrastructure-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: infrastructure
      interval: 30s
      rules:
        # Node alerts
        - alert: NodeDown
          expr: up{job="node-exporter"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Node {{ $labels.instance }} is down"
            description: "Node {{ $labels.instance }} has been down for more than 5 minutes"
        
        - alert: NodeHighCPU
          expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage on {{ $labels.instance }}"
            description: "CPU usage is above 80% on {{ $labels.instance }}"
        
        - alert: NodeHighMemory
          expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High memory usage on {{ $labels.instance }}"
            description: "Memory usage is above 85% on {{ $labels.instance }}"
        
        - alert: NodeDiskSpaceLow
          expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Low disk space on {{ $labels.instance }}"
            description: "Disk space is below 15% on {{ $labels.instance }}"
---
# monitoring/alerts/storage.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: storage-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: ceph
      interval: 30s
      rules:
        - alert: CephHealthError
          expr: ceph_health_status == 2
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Ceph cluster health is ERROR"
            description: "Ceph cluster has been in ERROR state for more than 5 minutes"
        
        - alert: CephHealthWarning
          expr: ceph_health_status == 1
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Ceph cluster health is WARNING"
            description: "Ceph cluster has been in WARNING state for more than 15 minutes"
        
        - alert: CephOSDDown
          expr: ceph_osd_up == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Ceph OSD {{ $labels.ceph_daemon }} is down"
            description: "OSD {{ $labels.ceph_daemon }} has been down for more than 5 minutes"
        
        - alert: CephPoolNearFull
          expr: ceph_pool_percent_used > 85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Ceph pool {{ $labels.name }} is nearly full"
            description: "Pool {{ $labels.name }} is {{ $value }}% full"
---
# monitoring/alerts/databases.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: database-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: mongodb
      interval: 30s
      rules:
        - alert: MongoDBDown
          expr: mongodb_up == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "MongoDB instance {{ $labels.instance }} is down"
            description: "MongoDB has been down for more than 5 minutes"
        
        - alert: MongoDBReplicationLag
          expr: mongodb_mongod_replset_member_replication_lag > 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "MongoDB replication lag on {{ $labels.instance }}"
            description: "Replication lag is {{ $value }} seconds"
    
    - name: postgresql
      interval: 30s
      rules:
        - alert: PostgreSQLDown
          expr: pg_up == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "PostgreSQL instance {{ $labels.instance }} is down"
            description: "PostgreSQL has been down for more than 5 minutes"
        
        - alert: PostgreSQLReplicationLag
          expr: pg_replication_lag > 30
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "PostgreSQL replication lag on {{ $labels.instance }}"
            description: "Replication lag is {{ $value }} seconds"
        
        - alert: PostgreSQLConnectionsHigh
          expr: sum(pg_stat_activity_count) by (instance) / pg_settings_max_connections > 0.8
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High connection usage on {{ $labels.instance }}"
            description: "Connection usage is above 80%"
---
# monitoring/alerts/applications.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: application-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: kafka
      interval: 30s
      rules:
        - alert: KafkaBrokerDown
          expr: kafka_server_kafkaserver_brokerstate != 3
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Kafka broker {{ $labels.instance }} is down"
            description: "Broker has been in non-running state for more than 5 minutes"
        
        - alert: KafkaUnderReplicatedPartitions
          expr: kafka_server_replicamanager_underreplicatedpartitions > 0
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Kafka has under-replicated partitions"
            description: "{{ $value }} partitions are under-replicated"
    
    - name: argocd
      interval: 30s
      rules:
        - alert: ArgoCDAppOutOfSync
          expr: argocd_app_info{sync_status="OutOfSync"} == 1
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "ArgoCD application {{ $labels.name }} is out of sync"
            description: "Application has been out of sync for more than 15 minutes"
        
        - alert: ArgoCDAppUnhealthy
          expr: argocd_app_info{health_status!="Healthy"} == 1
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "ArgoCD application {{ $labels.name }} is unhealthy"
            description: "Application health status is {{ $labels.health_status }}"
Part 10: Deployment Script
bash#!/bin/bash
# deploy-monitoring.sh

set -e

echo "=== Deploying Monitoring Stack ==="

# Create namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "=== Deploying Kube-Prometheus Stack ==="
kubectl apply -f argocd/apps/kube-prometheus-stack.yaml

echo "Waiting for Prometheus Operator..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/kube-prometheus-stack-operator -n monitoring

echo "=== Deploying Loki Stack ==="
kubectl apply -f argocd/apps/loki-stack.yaml

echo "=== Deploying Promtail ==="
kubectl apply -f argocd/apps/promtail.yaml

echo "=== Deploying Tempo ==="
kubectl apply -f argocd/apps/tempo.yaml

echo "=== Deploying OpenTelemetry Collector ==="
kubectl apply -f argocd/apps/opentelemetry-collector.yaml

echo "=== Deploying Blackbox Exporter ==="
kubectl apply -f argocd/apps/blackbox-exporter.yaml

echo "=== Deploying Status Pages ==="
kubectl apply -f argocd/apps/uptime-kuma.yaml
kubectl apply -f argocd/apps/gatus.yaml

echo "=== Deploying Service Monitors ==="
kubectl apply -f monitoring/servicemonitors/

echo "=== Deploying Custom Alerts ==="
kubectl apply -f monitoring/alerts/

echo "==="
echo "Monitoring Stack Deployed!"
echo ""
echo "Access URLs:"
echo "  Grafana:         https://grafana.yourdomain.local"
echo "  Prometheus:      https://prometheus.yourdomain.local"
echo "  Alertmanager:    https://alertmanager.yourdomain.local"
echo "  Uptime Kuma:     https://status.yourdomain.local"
echo "  Gatus:           https://health.yourdomain.local"
echo ""
echo "Default Grafana credentials: admin / admin (change immediately!)"
echo "==="
Verification Commands
bash# Check all monitoring pods
kubectl get pods -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/targets

# Check Grafana
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Check Loki
kubectl logs -n monitoring -l app.kubernetes.io/name=loki -f

# Check metrics collection
kubectl top nodes
kubectl top pods -A

# Test alerting
kubectl delete pod <some-critical-pod>  # Should trigger alerts
This gives you a complete observability stack with:

Metrics: Prometheus + Thanos for long-term storage
Logs: Loki + Promtail
Traces: Tempo + OpenTelemetry
Visualization: Grafana with pre-loaded dashboards
Alerting: Alertmanager with Slack/Email
Status Pages: Uptime Kuma + Gatus
Probes: Blackbox exporter for endpoint monitoring
All integrated with your existing infrastructure

Would you like me to help you configure specific dashboards, set up alert routing, or integrate monitoring with your CI/CD pipeline?