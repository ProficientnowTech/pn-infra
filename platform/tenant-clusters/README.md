
# Tenant Clusters

This module deploys virtual kubernetes clusters onto an existing baremetal k8s cluster
These clusters are occupied by tenant business application workloads. Which in our case, is the ProficientNow ATS

## Clusters

The clusters are divided by environments they represent.
For ProficientNow Cloud Platform, we have 4 environments namely:

1. Production
2. Pre-Production
3. UAT
4. Staging
5. Development

### Production Cluster

The production cluster runs all production workloads in HA mode.
The promotion mechanism to promote workloads and changes to production are discussed in CI/CD
