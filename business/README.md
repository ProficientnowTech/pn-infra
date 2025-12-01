# Business Module

Contains tenant/business application manifests, Helm charts, and delivery pipelines. The `business/charts/cluster-apps` Helm chart is an app-of-apps that ArgoCD uses to deploy all registered workloads after the platform layer finishes bootstrapping.

## Workflow

1. Define app manifests under `business/apps/<name>/` (Helm chart, Kustomize, or plain YAML).
2. Update `business/charts/cluster-apps/values.yaml` (or environment overrides) with a new `applications` entry.
3. Deploy via ArgoCD/GitOps:
   ```bash
   helm upgrade --install cluster-apps charts/cluster-apps -f environments/development.yaml
   ```

### Notes
- Business apps depend on namespaces/secrets exposed by `platform/`; coordinate schema changes through `openspec`.
- Config packages live under `config/`; `business/environments/*.yaml` references the package ID to stay aligned with the rest of the repo.
