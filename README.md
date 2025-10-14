
# ProficientNow Infrastructure

**Currently Under Development Version: v0.2.0**
**Future Version: v1.2.0** (not to be worked on)

GitOps-driven infrastructure for ProficientNow using Kubespray, ArgoCD, and Kubernetes.

## Overview

This repository contains the infrastructure-as-code for deploying and managing ProficientNow's Kubernetes platform with enhanced ArgoCD hooks integration for comprehensive validation and monitoring.

## Key Features

- ✅ **Hybrid Deployment**: Ansible bootstrap + ArgoCD GitOps workflows
- ✅ **ArgoCD-Native Validation**: PreSync/PostSync hooks for infrastructure validation
- ✅ **Production Ready**: SSL/TLS, monitoring, storage, secrets management
- ✅ **Zero-Surprise Deployment**: Comprehensive validation at every phase
- ✅ **Self-Healing**: Automated failure detection and recovery

## Getting Started

See the **[v0.2.0 documentation](./v0.2.0/README.md)** for comprehensive deployment instructions, architecture details, and ArgoCD hooks integration guide.

## Project Structure

- `v0.2.0/`: Current development version with ArgoCD hooks integration
  - `bootstrap/`: Tools and scripts for initial cluster setup
  - `applications/`: ArgoCD application definitions with validation hooks
  - `utils/hooks/`: ArgoCD PreSync/PostSync validation hooks
  - `docs/`: Comprehensive documentation
- `v1.2.0/`: Future architecture (not active)

## Quick Start

```bash
# Navigate to current development version
cd v0.2.0

# Run complete bootstrap with validation hooks
cd bootstrap/scripts
./bootstrap.sh

# Monitor hook execution
kubectl get jobs -n argocd -l argocd.argoproj.io/hook
```

## Documentation

- **[v0.2.0 Bootstrap System](./v0.2.0/README.md)**: Complete deployment guide with ArgoCD hooks
- **[ArgoCD Hooks Integration](./v0.2.0/#-argocd-hooks-integration)**: Native validation and health checking
- **[Architecture Deep Dive](./v0.2.0/#-architecture-deep-dive)**: System components and workflows
