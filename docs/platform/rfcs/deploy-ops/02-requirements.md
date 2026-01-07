```
RFC-DEPLOY-0001                                              Section 2
Category: Standards Track                    Requirements and Invariants
```

# 2. Requirements and Invariants

[← Previous: Introduction](./01-introduction.md) | [Index](./00-index.md#table-of-contents) | [Next: Architecture →](./03-architecture.md)

---

This section defines requirements that any deployment orchestration solution
MUST satisfy. Designs in subsequent sections are evaluated against these
requirements.

---

## 2.1 Problem Statement

The platform requires a system that:

1. Deploys 40+ applications in correct dependency order
2. Verifies each application is healthy before deploying dependents
3. Operates without human intervention for normal deployments
4. Supports clean teardown in reverse dependency order
5. Integrates with ArgoCD as the deployment layer
6. Can be invoked from a single containerized entry point

---

## 2.2 Design Goals

### 2.2.1 Dependency-Ordered Deployment

Applications MUST deploy in an order that satisfies their dependencies.

If Application B depends on Application A, then:
- A MUST be deployed before B
- A MUST report healthy status before B deployment begins
- If A fails, B MUST NOT attempt deployment

### 2.2.2 Health-Gated Progression

Deployment MUST NOT proceed based solely on sync completion.

ArgoCD "Synced" status means resources were applied. It does not mean:
- Pods are running
- Services are reachable
- Operators have reconciled their instances
- Databases are accepting connections

The system MUST verify actual health, not just sync status.

### 2.2.3 Elimination of PreSync Hooks for Dependencies

PreSync hooks MUST NOT be used for cross-Application dependency enforcement.

Hooks are appropriate for:
- Database migrations before deployment
- Schema updates
- One-time initialization tasks

Hooks are NOT appropriate for:
- Waiting for other Applications
- Verifying prerequisites exist
- Blocking on external dependencies

All cross-Application dependency logic MUST move to the orchestration layer.

### 2.2.4 Deterministic Execution

Given identical inputs:
- The same applications MUST deploy
- In the same order
- With the same health checks
- Producing the same cluster state

Non-determinism from race conditions, timing, or implicit ordering is
forbidden.

### 2.2.5 Idempotent Operations

Running deployment multiple times with identical inputs MUST:
- Produce identical cluster state
- Not create duplicate resources
- Not fail due to existing resources
- Be safe to retry after partial failure

### 2.2.6 Containerized Executor

A container image MUST exist that:
- Accepts an action (deploy, validate, teardown)
- Accepts configuration (environment, scope, credentials)
- Executes the requested action
- Exits with status indicating success or failure

This enables invocation from any context: CI/CD, manual execution, automation
systems.

---

## 2.3 Non-Goals

### 2.3.1 Replacing ArgoCD

ArgoCD remains the system that applies manifests to clusters. This RFC does
not propose replacing ArgoCD with another GitOps tool.

### 2.3.2 Application-Level Deployment Strategies

How individual applications roll out (canary, blue-green) is handled by Argo
Rollouts at the application level. This RFC addresses platform-level
orchestration, not application delivery.

### 2.3.3 Multi-Cluster Orchestration

Coordinating deployment across multiple clusters is out of scope. This RFC
addresses single-cluster deployment. Multi-cluster patterns may be addressed
in future RFCs.

### 2.3.4 CI/CD Pipeline Design

The executor can be invoked from CI/CD, but designing CI/CD pipelines is not
part of this RFC.

---

## 2.4 Invariants

The following invariants MUST hold. Any design that violates these invariants
is rejected.

---

### INV-1: Dependency Satisfaction

An application MUST NOT begin deployment until all applications it depends on
report Healthy status.

"Healthy" means the application is fully operational, not merely synced.

---

### INV-2: Single Deployment Path

All platform deployments MUST flow through the orchestration system.

Direct ArgoCD sync operations that bypass orchestration MAY leave the platform
in inconsistent state and are not supported.

---

### INV-3: No Implicit State

The orchestration system MUST NOT depend on state outside:
- Kubernetes cluster resources
- Git repository contents
- Explicitly provided configuration

Local files, environment variables not passed to the executor, or cached
state from previous runs MUST NOT affect behavior.

---

### INV-4: Failure Visibility

If any application fails to deploy or become healthy:
- The failure MUST be reported
- Dependent applications MUST NOT attempt deployment
- The system MUST NOT mask the failure as success

---

### INV-5: Reverse Order Teardown

Teardown MUST proceed in reverse dependency order.

An application MUST NOT be removed while applications depending on it exist.

---

### INV-6: Idempotent Execution

Running the same action multiple times with identical inputs MUST produce
identical results.

This includes:
- Deploy on already-deployed platform: no changes
- Teardown on already-removed platform: no errors
- Validate on healthy platform: reports healthy

---

### INV-7: Health Verification Accuracy

Health status MUST reflect actual operational state.

Custom health checks MUST be defined for:
- CephCluster (Ceph operator)
- PostgreSQL clusters (Zalando operator)
- Vault (sealed vs unsealed)
- Any CRD where sync completion does not indicate readiness

---

### INV-8: Hook Prohibition

PreSync and PostSync hooks MUST NOT be used for dependency orchestration.

Existing hooks for this purpose MUST be removed.

Hooks MAY remain for application-internal tasks (migrations, initialization).

---

## 2.5 Success Criteria

The system is successful if:

1. **Full deployment succeeds without intervention**
   Starting from an empty cluster, the executor deploys all 40+ applications
   without any manual steps.

2. **Deployment is reproducible**
   Multiple deployments to identical clusters produce identical results.

3. **Partial failure is recoverable**
   If deployment fails at application N, resuming deployment continues from
   N without re-deploying 1 through N-1.

4. **Teardown leaves clean cluster**
   After teardown, no platform resources remain (excluding PersistentVolumes
   if retention is configured).

5. **New engineers can deploy**
   An engineer unfamiliar with the platform can execute deployment using
   only documented procedures.

6. **Dependency violations are caught**
   Attempting to deploy an application before its dependencies fails with
   a clear error, not silent misbehavior.

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← 1. Introduction](./01-introduction.md) | [Table of Contents](./00-index.md#table-of-contents) | [3. Architecture →](./03-architecture.md) |

---

*End of Section 2*
