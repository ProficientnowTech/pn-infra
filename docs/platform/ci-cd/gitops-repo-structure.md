# GitOps Configuration Repository Structure

## Complete Repository Layout

```
gitops-config/
├── README.md
├── base/
│   ├── user-service/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   ├── hpa.yaml
│   │   └── kustomization.yaml
│   ├── payment-service/
│   │   └── ...
│   └── notification-service/
│       └── ...
├── overlays/
│   ├── dev/
│   │   ├── user-service/
│   │   │   ├── kustomization.yaml
│   │   │   ├── configmap-patch.yaml
│   │   │   └── deployment-patch.yaml
│   │   ├── payment-service/
│   │   └── notification-service/
│   ├── staging/
│   │   └── ...
│   ├── uat/
│   │   └── ...
│   ├── preprod/
│   │   ├── user-service/
│   │   │   ├── kustomization.yaml
│   │   │   ├── rollout.yaml  # Canary strategy
│   │   │   └── service-canary.yaml
│   │   └── ...
│   ├── production/
│   │   ├── user-service/
│   │   │   ├── kustomization.yaml
│   │   │   ├── rollout.yaml  # Blue-green strategy
│   │   │   └── service-preview.yaml
│   │   └── ...
│   ├── preview/
│   │   └── user-service/
│   │       ├── kustomization.yaml
│   │       └── deployment-patch.yaml
│   └── sandbox/
│       └── ...
└── argocd/
    ├── applications/
    ├── projects/
    └── app-of-apps.yaml
```

---

## 1. Base Manifests

### User Service Base Deployment

```yaml
# base/user-service/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  labels:
    app: user-service
    version: v1
spec:
  replicas: 3
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
        version: v1
    spec:
      containers:
        - name: user-service
          image: harbor.yourdomain.com/services/user-service:latest
          ports:
            - containerPort: 3000
              name: http
          env:
            - name: NODE_ENV
              valueFrom:
                configMapKeyRef:
                  name: user-service-config
                  key: NODE_ENV
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: user-service-secret
                  key: DATABASE_URL
            - name: REDIS_URL
              valueFrom:
                configMapKeyRef:
                  name: user-service-config
                  key: REDIS_URL
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 5
```

### User Service Base Service

```yaml
# base/user-service/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: user-service
  labels:
    app: user-service
spec:
  selector:
    app: user-service
  ports:
    - port: 80
      targetPort: 3000
      name: http
  type: ClusterIP
```

### User Service Base ConfigMap

```yaml
# base/user-service/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: user-service-config
data:
  NODE_ENV: "production"
  LOG_LEVEL: "info"
  PORT: "3000"
  REDIS_URL: "redis://redis.default.svc:6379"
```

### User Service Base Secret

```yaml
# base/user-service/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: user-service-secret
type: Opaque
stringData:
  DATABASE_URL: "postgresql://user:pass@postgres.default.svc:5432/userdb"
  JWT_SECRET: "change-me"
  API_KEY: "change-me"
```

### User Service Base HPA

```yaml
# base/user-service/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user-service
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user-service
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

### Base Kustomization

```yaml
# base/user-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
  - secret.yaml
  - hpa.yaml

commonLabels:
  app: user-service
  managed-by: kustomize

images:
  - name: harbor.yourdomain.com/services/user-service
    newTag: latest
```

---

## 2. Development Overlay

```yaml
# overlays/dev/user-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev

bases:
  - ../../../base/user-service

namePrefix: dev-

commonLabels:
  environment: dev

# Override image tag (updated by Kargo)
images:
  - name: harbor.yourdomain.com/services/user-service
    newTag: v1.2.3-alpha.20241114153045

# Patches for dev-specific config
patchesStrategicMerge:
  - configmap-patch.yaml
  - deployment-patch.yaml

# Replicas override
replicas:
  - name: user-service
    count: 2

configMapGenerator:
  - name: user-service-config
    behavior: merge
    literals:
      - NODE_ENV=development
      - LOG_LEVEL=debug
```

### Dev ConfigMap Patch

```yaml
# overlays/dev/user-service/configmap-patch.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: user-service-config
data:
  NODE_ENV: "development"
  LOG_LEVEL: "debug"
  FEATURE_FLAGS: '{"newFeature": true, "betaFeature": true}'
```

### Dev Deployment Patch

```yaml
# overlays/dev/user-service/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
spec:
  template:
    spec:
      containers:
        - name: user-service
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
```

---

## 3. Staging Overlay

```yaml
# overlays/staging/user-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: staging

bases:
  - ../../../base/user-service

namePrefix: staging-

commonLabels:
  environment: staging

images:
  - name: harbor.yourdomain.com/services/user-service
    newTag: v1.2.3-alpha.20241114153045

patchesStrategicMerge:
  - configmap-patch.yaml

replicas:
  - name: user-service
    count: 3

configMapGenerator:
  - name: user-service-config
    behavior: merge
    literals:
      - NODE_ENV=staging
      - LOG_LEVEL=info
      - DATABASE_URL=postgresql://postgres.staging.svc:5432/userdb
```

---

## 4. UAT Overlay

```yaml
# overlays/uat/user-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: uat

bases:
  - ../../../base/user-service

namePrefix: uat-

commonLabels:
  environment: uat

images:
  - name: harbor.yourdomain.com/services/user-service
    newTag: v1.2.3-beta.1

patchesStrategicMerge:
  - configmap-patch.yaml

replicas:
  - name: user-service
    count: 5

configMapGenerator:
  - name: user-service-config
    behavior: merge
    literals:
      - NODE_ENV=uat
      - LOG_LEVEL=info
```

---

## 5. Pre-Production Overlay (Canary)

```yaml
# overlays/preprod/user-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: preprod

# Don't use base deployment - use Rollout instead
resources:
  - ../../../base/user-service/service.yaml
  - ../../../base/user-service/configmap.yaml
  - ../../../base/user-service/secret.yaml
  - rollout.yaml  # Custom Argo Rollouts resource
  - service-canary.yaml
  - service-stable.yaml

namePrefix: preprod-

commonLabels:
  environment: preprod

images:
  - name: harbor.yourdomain.com/services/user-service
    newTag: v1.2.3-beta.1

configMapGenerator:
  - name: user-service-config
    behavior: merge
    literals:
      - NODE_ENV=preprod
      - LOG_LEVEL=info
```

### Pre-Prod Rollout

```yaml
# overlays/preprod/user-service/rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: user-service
spec:
  replicas: 10
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
        - name: user-service
          image: harbor.yourdomain.com/services/user-service:v1.2.3-beta.1
          ports:
            - containerPort: 3000
              name: http
          envFrom:
            - configMapRef:
                name: user-service-config
            - secretRef:
                name: user-service-secret
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
  strategy:
    canary:
      canaryService: user-service-canary
      stableService: user-service-stable
      steps:
        - setWeight: 10
        - pause: {duration: 5m}
        - setWeight: 25
        - pause: {duration: 10m}
        - setWeight: 50
        - pause: {duration: 10m}
        - setWeight: 75
        - pause: {duration: 10m}
        - setWeight: 100
```

---

## 6. Production Overlay (Blue-Green)

```yaml
# overlays/production/user-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

resources:
  - ../../../base/user-service/service.yaml
  - ../../../base/user-service/configmap.yaml
  - ../../../base/user-service/secret.yaml
  - rollout.yaml
  - service-preview.yaml
  - hpa.yaml

namePrefix: prod-

commonLabels:
  environment: production

images:
  - name: harbor.yourdomain.com/services/user-service
    newTag: v1.2.3  # Stable version only

configMapGenerator:
  - name: user-service-config
    behavior: merge
    literals:
      - NODE_ENV=production
      - LOG_LEVEL=warn
```

### Production Rollout

```yaml
# overlays/production/user-service/rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: user-service
spec:
  replicas: 20
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
        - name: user-service
          image: harbor.yourdomain.com/services/user-service:v1.2.3
          ports:
            - containerPort: 3000
              name: http
          envFrom:
            - configMapRef:
                name: user-service-config
            - secretRef:
                name: user-service-secret
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
  strategy:
    blueGreen:
      activeService: user-service
      previewService: user-service-preview
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 600
      prePromotionAnalysis:
        templates:
          - templateName: bluegreen-verification
```

---

## 7. Preview Overlay (PR Environments)

```yaml
# overlays/preview/user-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: pr-PLACEHOLDER  # Replaced by Tekton

bases:
  - ../../../base/user-service

# PR-specific prefix
namePrefix: pr-PLACEHOLDER-

commonLabels:
  environment: preview
  pr-number: "PLACEHOLDER"

images:
  - name: harbor.yourdomain.com/services/user-service
    newTag: pr-PLACEHOLDER-PLACEHOLDER  # Replaced by Tekton

replicas:
  - name: user-service
    count: 1

patchesStrategicMerge:
  - deployment-patch.yaml

configMapGenerator:
  - name: user-service-config
    behavior: merge
    literals:
      - NODE_ENV=preview
      - LOG_LEVEL=debug
```

### Preview Deployment Patch

```yaml
# overlays/preview/user-service/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  annotations:
    preview: "true"
    ttl: "7d"
spec:
  template:
    spec:
      containers:
        - name: user-service
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
```

---

## 8. Kustomization Best Practices

### Using Components (Reusable Pieces)

```yaml
# components/monitoring/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
  - servicemonitor.yaml
  - prometheusrule.yaml

# Then use in overlays:
# overlays/production/user-service/kustomization.yaml
components:
  - ../../../components/monitoring
```

### Using Generators

```yaml
# Generate secrets from files
secretGenerator:
  - name: user-service-tls
    files:
      - tls.crt
      - tls.key

# Generate from env files
configMapGenerator:
  - name: user-service-env
    envs:
      - .env.production
```

---

## 9. Version Management Script

```bash
#!/bin/bash
# scripts/update-image.sh
# Used by Kargo to update image tags

SERVICE=$1
ENVIRONMENT=$2
NEW_TAG=$3

KUSTOMIZATION_FILE="overlays/${ENVIRONMENT}/${SERVICE}/kustomization.yaml"

# Update image tag using kustomize edit
cd "overlays/${ENVIRONMENT}/${SERVICE}"
kustomize edit set image "harbor.yourdomain.com/services/${SERVICE}:${NEW_TAG}"

# Commit changes
git add kustomization.yaml
git commit -m "chore(${SERVICE}): update ${ENVIRONMENT} to ${NEW_TAG}"
git push origin main
```

---

## 10. Directory Structure Visualization

```
gitops-config/
│
├── base/                          # Base manifests (DRY principle)
│   ├── user-service/
│   ├── payment-service/
│   └── notification-service/
│
├── overlays/                      # Environment-specific configs
│   ├── dev/                       # Development (alpha)
│   ├── staging/                   # Staging (alpha/beta)
│   ├── uat/                       # UAT (beta)
│   ├── preprod/                   # Pre-prod (beta) - Canary
│   ├── production/                # Production (stable) - Blue-Green
│   ├── preview/                   # PR previews
│   └── sandbox/                   # Sandbox (production clone)
│
├── components/                    # Reusable components
│   ├── monitoring/
│   ├── logging/
│   └── security/
│
├── argocd/                        # ArgoCD application definitions
│   ├── applications/
│   ├── projects/
│   └── app-of-apps.yaml
│
└── scripts/                       # Helper scripts
    ├── update-image.sh
    └── validate-manifests.sh
```

---

## Summary

This GitOps repository structure provides:

✅ **DRY Principle**: Base manifests reused across environments  
✅ **Kustomize Overlays**: Environment-specific customization  
✅ **Maturity Separation**: Alpha/beta in lower environments, stable in production  
✅ **Deployment Strategies**: Standard, canary, and blue-green  
✅ **Preview Environments**: Dynamic PR-based environments  
✅ **Version Control**: All config changes tracked in Git  
✅ **Kargo Integration**: Image tags updated automatically  
✅ **ArgoCD Sync**: Declarative GitOps deployment  
✅ **Rollback Ready**: Git history enables easy rollbacks
