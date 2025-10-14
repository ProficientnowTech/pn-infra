# Cert-Manager Chart

ArgoCD Application for cert-manager TLS certificate management.

## Purpose

Deploys cert-manager for automatic TLS certificate provisioning and management using Let's Encrypt and other certificate authorities.

## Configuration

### Chart Values (`values.yaml`)

```yaml
# Global repository settings  
global:
  name: cert-manager
  targetNamespace: argocd
  syncWave: "-2"              # Deploy after MetalLB, before applications
  project: platform
  server: https://kubernetes.default.svc

# Labels configuration
labels:
  component: infrastructure    # Component type for Kubernetes labels
  managed-by: argocd          # Override default Helm with ArgoCD

# Cert-Manager configuration
chart:
  version: 'v1.16.1'          # Cert-manager Helm chart version

namespace: 'cert-manager'     # Target deployment namespace
```

## Key Features

- **Automatic Certificate Provisioning**: ACME/Let's Encrypt integration
- **Multiple CA Support**: Let's Encrypt, private CAs, Vault integration
- **Certificate Lifecycle Management**: Automatic renewal and rotation
- **Kubernetes Integration**: Certificate resources and annotations

## Generated Application

**Sync Wave**: `-2` - Deploys after MetalLB (-4) and before applications
**Target Namespace**: `cert-manager`
**Dependencies**: Kubernetes cluster, ingress controller for HTTP-01 challenges

## Integration

Used by:
- **ArgoCD**: TLS certificates for web UI
- **Ingress Controllers**: Automatic certificate provisioning
- **Application Services**: TLS termination

## Troubleshooting

```bash
kubectl get pods -n cert-manager
kubectl get certificates --all-namespaces
kubectl describe clusterissuer letsencrypt-prod
```