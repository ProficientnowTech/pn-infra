# Fuma Docs Application

Scaffold for the documentation site that will be deployed on the platform. The Helm chart under `chart/` packages a simple static site container and can be referenced by the business/platform app-of-apps when ready.

## Deploy

```bash
helm dependency update chart
helm upgrade --install fuma-docs chart \
  --namespace docs --create-namespace
```

Add the chart to `business/charts/cluster-apps` to include it in the GitOps flow.
