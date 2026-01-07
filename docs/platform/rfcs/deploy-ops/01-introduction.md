```
RFC-DEPLOY-0001                                              Section 1
Category: Standards Track                                 Introduction
```

# 1. Introduction and Motivation

[Index](./00-index.md#table-of-contents) | [Next: Requirements →](./02-requirements.md)

---

## 1.1 The Deployment Orchestration Problem

Deploying a platform with 40+ interdependent applications requires solving a
constraint satisfaction problem: applications must deploy in an order that
respects their dependencies, and each application must be healthy before its
dependents can start.

This platform comprises 11 stacks:

- Infrastructure (MetalLB, ingress-nginx, cert-manager, external-dns, sealed-secrets)
- Storage (Ceph operator, Ceph cluster, Zalando PostgreSQL operator, Redis operator)
- Monitoring (Prometheus, Grafana, Loki, Tempo)
- Security (Vault, External Secrets, Keycloak, Kyverno, Falco)
- Platform Data (PostgreSQL clusters, Redis clusters)
- Data Streaming (Strimzi Kafka)
- Developer Platform (Harbor, Backstage, Tekton, KubeVirt)
- Development Workloads (Argo Rollouts, Kargo)
- Application Infrastructure (Temporal)

The dependency chain is deep. Temporal requires PostgreSQL databases. PostgreSQL
requires the Zalando operator. The operator requires storage classes. Storage
classes require Ceph. Ceph requires the Ceph operator. The operator requires
MetalLB for service exposure. This single chain spans six layers.

Multiply this across all stacks, and the result is a directed acyclic graph
with dozens of nodes and complex cross-stack relationships.

---

## 1.2 Current Deployment Mechanisms

### 1.2.1 Bootstrap Scripts

Platform deployment currently relies on bash scripts that:

- Install ArgoCD via Helm
- Wait for ArgoCD pods to become ready
- Apply the Root Application manifest
- Poll ArgoCD for Application health status

These scripts handle the chicken-and-egg problem: ArgoCD cannot manage its own
installation. However, the scripts have grown to include workarounds, reset
mechanisms, and conditional logic accumulated over time.

### 1.2.2 ArgoCD Sync Waves

Resources within Applications use sync waves ranging from -30 to +50. The
original intent was to sequence operators before instances (wave -10 for
operator, wave 0 for instance).

Over time, sync waves were stretched to attempt cross-Application ordering.
Foundational stacks received large negative waves (-30), while dependent
stacks received positive waves (+40, +50). This approach assumes ArgoCD
processes Applications in sync wave order, which it does not guarantee.

### 1.2.3 PreSync Validation Jobs

To enforce cross-Application dependencies, PreSync hooks were added. Each
stack deploys a Kubernetes Job before sync that checks:

- Do required CRDs exist?
- Are prerequisite Deployments ready?
- Are required Services reachable?

The Job blocks Application sync until all checks pass.

### 1.2.4 App-of-Apps Structure

The platform uses a hierarchical Application structure:

```
platform-root
├── stack-orchestrator
│   ├── infrastructure-stack
│   │   ├── metallb
│   │   ├── ingress-nginx
│   │   └── ...
│   ├── storage-stack
│   │   ├── ceph-operator
│   │   ├── ceph-cluster
│   │   └── ...
│   └── ...
```

Each stack is an Application that generates child Applications through a
target-chart pattern.

---

## 1.3 Why the Current System Fails

### 1.3.1 PreSync Jobs Get Stuck

The most acute problem is stuck PreSync Jobs. The failure pattern:

1. Job runs and completes successfully
2. Kubernetes garbage-collects the Job pod (ttlSecondsAfterFinished)
3. ArgoCD queries Job status but finds no pod
4. ArgoCD cannot determine hook completion
5. Sync hangs indefinitely

The workaround is manual deletion of the Job resource, which triggers ArgoCD
to recreate it. This requires human intervention on nearly every deployment.

A related issue: Jobs configured with `hook-delete-policy: BeforeHookCreation`
are deleted when a new sync starts. If the new Job fails to create immediately,
there is a window where no Job exists, and ArgoCD may proceed incorrectly.

### 1.3.2 Jobs Execute on Every Reconciliation

ArgoCD reconciles Applications every 3 minutes by default. PreSync hooks
execute on every reconciliation, not just initial deployment.

With 40+ Applications, each with PreSync Jobs, the cluster runs thousands of
validation Jobs daily. These Jobs:

- Consume CPU and memory
- Generate logs requiring storage
- Create pod churn affecting scheduler
- Produce noise in monitoring systems

The Jobs serve no purpose during steady-state operation—dependencies do not
change between reconciliations.

### 1.3.3 Sync Waves Cannot Express the Dependency Graph

The platform dependency graph is not linear. Consider:

- Vault depends on storage classes AND ingress
- Keycloak depends on PostgreSQL cluster AND ingress
- Harbor depends on PostgreSQL AND Redis AND storage

Sync waves are integers. They express total ordering, not partial ordering.
There is no sync wave value that correctly expresses "after both PostgreSQL
and Redis but before Temporal."

ArgoCD issue #7437 documents this limitation. The community has requested
cross-Application dependency support since 2020. The issue has 280+ reactions.

### 1.3.4 Failure Recovery Requires Deep Knowledge

When deployment fails partway:

- Which Applications succeeded?
- Which failed?
- What is the correct order to resume?
- Which Jobs need manual cleanup?

Answering these questions requires understanding the entire dependency graph,
the current cluster state, and the specific failure mode. New engineers cannot
safely recover deployments without guidance from experienced team members.

### 1.3.5 Teardown Is Worse Than Deployment

Teardown must happen in reverse dependency order. Deleting storage before
deleting databases causes data loss. Deleting operators before instances
leaves orphaned resources.

The current scripts attempt reverse ordering but frequently leave:

- Finalizers blocking namespace deletion
- PersistentVolumes without claims
- CRDs without controllers
- Services with stale endpoints

Manual cleanup after teardown is routine.

---

## 1.4 Constraints on Solutions

Any solution must work within these constraints:

**ArgoCD remains the deployment layer.** The platform has significant
investment in ArgoCD Applications, ApplicationSets, and the App-of-Apps
pattern. Replacing ArgoCD is not feasible.

**GitOps principles apply.** Deployment intent must be declared in Git.
Runtime systems should reconcile toward declared state. Human operators
should not directly manipulate cluster resources.

**Bootstrap must handle the chicken-and-egg.** Before ArgoCD exists, something
must install it. This cannot be ArgoCD itself.

**The solution must be deterministic.** Given the same inputs, deployment
must produce the same outcome. Non-determinism from race conditions is
unacceptable.

---

## 1.5 Why This RFC Exists

This RFC proposes replacing ad-hoc orchestration mechanisms with a dedicated
orchestration layer:

- **Argo Workflows** for DAG-based execution with explicit dependencies
- **Ansible** (recommended) for idempotent bootstrap operations
- **Argo Events** for event-driven workflow triggers
- **A containerized executor** providing deploy/validate/teardown actions

The orchestration layer sits between bootstrap and ArgoCD. It invokes ArgoCD
syncs in dependency order, waits for health, and proceeds only when safe.

PreSync Jobs are eliminated entirely. Dependency logic moves from hooks to
workflow DAGs where it can be:

- Explicitly modeled
- Validated before execution
- Observed during execution
- Resumed after failure

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| — | [Table of Contents](./00-index.md#table-of-contents) | [2. Requirements →](./02-requirements.md) |

---

*End of Section 1*
