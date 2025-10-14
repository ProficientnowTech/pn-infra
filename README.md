
# ProficientNow Infrastructure

**Currently Under Development Version: v0.2.0**
**Future Version: v1.2.0** (not to be worked on)

GitOps-driven infrastructure for ProficientNow using a revolutionary 2-phase deployment architecture with Kubespray and ArgoCD.

## Overview

This repository contains the infrastructure-as-code for deploying and managing ProficientNow's Kubernetes platform using a revolutionary 2-phase deployment architecture that eliminates complexity while providing enterprise-grade reliability.

## Key Features

- ✅ **2-Phase Architecture**: Docker-based Kubespray + Template-driven ArgoCD applications
- ✅ **Zero Local Dependencies**: Docker-only deployment with complete infrastructure
- ✅ **Application Factory**: Template-driven application deployment via Helm charts
- ✅ **Production Ready**: SSL/TLS, monitoring, storage, secrets management
- ✅ **Modular Deployment**: Base, monitoring, and ML stacks deployable independently
- ✅ **Self-Healing**: GitOps automated drift detection and recovery

## Getting Started

See the **[v0.2.0 documentation](./v0.2.0/README.md)** for comprehensive deployment instructions, architecture details, and ArgoCD hooks integration guide.

## Project Structure

- `v0.2.0/`: Current development version with 2-phase deployment
  - `cluster/`: Docker-based Kubespray deployment system
  - `platform/`: Template-driven ArgoCD application factory
  - `openspec/`: Architecture specifications and change management
- `v1.2.0/`: Future architecture (not active)

## Quick Start

```bash
# Phase 1: Deploy complete Kubernetes cluster
cd v0.2.0/cluster
./kubespray.sh deploy

# Phase 2: Deploy platform applications via templates
cd v0.2.0/platform/bootstrap
./bootstrap-template-driven.sh deploy --stack all

# Monitor application deployment
kubectl get applications -n argocd
```

## Documentation

- **[v0.2.0 Deployment Guide](./v0.2.0/README.md)**: Complete 2-phase deployment architecture
- **[Application Factory Pattern](./v0.2.0/#-phase-2-template-driven-platform-applications)**: Template-driven application deployment
- **[Architecture Benefits](./v0.2.0/#-architecture-benefits)**: Revolutionary simplification and benefits
