# Business Module

Contains tenant/business application manifests, Helm charts, and delivery pipelines. The `business/charts/cluster-apps` Helm chart is an app-of-apps that ArgoCD uses to deploy all registered workloads after the platform layer finishes bootstrapping.

## Workflow

1. Define app manifests under `business/apps/<name>/` (Helm chart, Kustomize, or plain YAML).
2. Update `config/packages/<package>/environments/<env>.business.yaml` with the application entry and bump the package version.
3. Materialize the config for an environment:
   ```bash
   ./api/bin/api generate env --id development --config core --skip-validate
   ```
4. Deploy via ArgoCD/GitOps using the generated artifact:
   ```bash
   helm upgrade --install cluster-apps charts/cluster-apps -f ../api/outputs/development/business.yaml
   ```

### Notes
- Business apps depend on namespaces/secrets exposed by `platform/`; coordinate schema changes through `openspec`.
- Config packages live under `config/`; `business/environments/*.yaml` now only selects the package and environment while the rendered values ship via `api/outputs/<env>/business.yaml`.

---

## Requirements

### Input Files
- **From Config**: `config/packages/core/business/apps.yaml` - Application definitions
- **From API**: `api/outputs/<env>/business.yaml` - Generated Helm values for app-of-apps
- **Module Environment**: `business/environments/<env>.yaml` - App-specific secrets, namespace configs

### Required Tools
- `kubectl` - Kubernetes CLI
- `helm` - Helm v3+
- `argocd` CLI (optional)

### Pre-requisites
- Running Kubernetes cluster
- Platform services deployed (ArgoCD, storage, secrets management)

### Folder Structure
```
business/
├── apps/                           # Application definitions
│   └── <app-name>/
│       ├── chart/                  # Helm chart
│       ├── kustomize/              # Kustomize overlays
│       └── manifests/              # Plain YAML
└── charts/
    └── cluster-apps/               # App-of-apps umbrella chart
        ├── Chart.yaml
        ├── templates/
        │   └── application.yaml
        └── values.yaml
```

---

## Outputs

### ArgoCD Applications
- One ArgoCD Application per business app
- Deployed via app-of-apps pattern
- Example: `fuma-docs` application in `docs` namespace

### Deployed Resources
- Depends on application definitions
- Deployments, Services, Ingresses, ConfigMaps, Secrets, etc.

### Application Endpoints
- Application-specific URLs based on Ingress configurations

---

## Integration
- **Depends On**: Platform Module (ArgoCD, namespaces, secrets)
- **Consumed By**: End users, external services

### Deployment
```bash
# Generate artifacts
./api/bin/api generate env --id development --config core

# Deploy app-of-apps
helm upgrade --install cluster-apps charts/cluster-apps \
  -f ../api/outputs/development/business.yaml
```
