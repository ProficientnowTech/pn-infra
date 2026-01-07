```
RFC-DEPLOY-0001                                              Section 2
Category: Standards Track                    Requirements and Invariants
```

# 2. Requirements and Invariants

[← Previous: Introduction](./01-introduction.md) | [Index](./00-index.md#table-of-contents) | [Next: Architecture →](./03-architecture.md)

---

This section defines the **constraints and invariants** that shape all
subsequent architectural and implementation decisions. No design presented
in later sections MAY violate the principles established here.

---

## 2.1 Core Problem Restatement

The platform REQUIRES a deployment orchestration system that:

- deploys 40+ interdependent applications in correct dependency order,
- operates without human intervention for nominal deployments,
- produces deterministic, reproducible platform states,
- fails explicitly with actionable diagnostics when errors occur,
- supports both initial deployment and clean teardown,
- and integrates with GitOps workflows.

The system MUST work under the assumption that:

- networks MAY experience transient failures,
- resources MAY take variable time to become healthy,
- clusters MAY be destroyed and rebuilt,
- and operators will change over time.

The architecture MUST therefore be **resilient by construction**, not by
discipline or tribal knowledge.

---

## 2.2 Design Goals

### 2.2.1 Deterministic Deployment Ordering

Deployments MUST execute in a deterministic order based on declared dependencies.

Given:

- a dependency graph,
- a cluster state,
- and deployment inputs,

the system MUST produce the same deployment sequence. Non-deterministic
behaviors such as race conditions or timing-dependent ordering are forbidden.

---

### 2.2.2 Idempotent Operations

All deployment operations MUST be idempotent.

Executing the same deployment action multiple times with identical inputs MUST:

- produce identical observable platform state,
- not create duplicate resources,
- not cause errors on subsequent executions,
- and be safe to retry after failures.

---

### 2.2.3 Explicit Dependency Modeling

Dependencies MUST be modeled as first-class entities, not inferred from
deployment order or validated through runtime checks.

The system MUST support:

- declaration of dependencies between stacks,
- declaration of dependencies between applications within stacks,
- declaration of dependencies on specific resource types,
- and validation that dependency graphs are acyclic.

---

### 2.2.4 Health-Gated Progression

Deployment MUST NOT progress to a subsequent phase until all resources in the
current phase report healthy status.

Health verification MUST:

- use explicit health checks, not sync completion status,
- support custom health definitions for CRDs,
- propagate health status through nested Application hierarchies,
- and distinguish between healthy, progressing, degraded, and failed states.

---

### 2.2.5 Zero Human-In-The-Loop for Nominal Operations

After initial configuration, the system MUST deploy the complete platform
without requiring humans to:

- monitor deployment progress,
- restart stuck components,
- delete failed Jobs,
- or manually verify health status.

Human involvement is permitted only for:

- initial trust establishment and configuration,
- policy changes,
- and exceptional recovery scenarios.

---

### 2.2.6 Explicit Failure Semantics

When failures occur, the system MUST:

- halt progression of dependent deployments,
- report failure state through observable interfaces,
- provide diagnostic information sufficient for troubleshooting,
- and support resumption from the failure point.

Failures MUST NOT:

- be masked or ignored,
- cause cascading failures in unrelated components,
- or leave the system in an indeterminate state.

---

### 2.2.7 GitOps-Native Integration

The deployment system MUST integrate with GitOps workflows:

- deployment intent MUST be declaratively specified in Git,
- the orchestration system MUST trigger ArgoCD syncs,
- and steady-state reconciliation MUST be handled by ArgoCD.

The system MUST NOT bypass or replace ArgoCD for application state management.

---

### 2.2.8 Containerized Execution

The deployment executor MUST be packaged as a container image that:

- can be pulled from a container registry,
- accepts configuration through environment variables and mounted files,
- supports deploy, validate, and teardown actions,
- and can be executed in any Kubernetes cluster.

---

## 2.3 Non-Goals

The following are explicitly **out of scope** for this architecture:

### 2.3.1 Application Workload Orchestration

How individual applications deploy their workloads (canary, blue-green,
rolling updates) is handled by Argo Rollouts and application-specific
configuration.

The deployment orchestration system handles platform infrastructure, not
application release strategies.

---

### 2.3.2 CI/CD Pipeline Replacement

CI/CD systems MAY exist alongside this architecture, but:

- they MUST NOT be required for platform deployment,
- they MUST NOT be the source of truth for platform state,
- and they MUST NOT control deployment ordering.

The platform MUST be deployable without CI/CD systems.

---

### 2.3.3 Multi-Cluster Federation

Deployment orchestration across multiple clusters is deferred to
[Section 9: Evolution](./09-evolution.md).

This architecture focuses on single-cluster deployment. Multi-cluster
patterns MUST be additive, not changes to the core architecture.

---

### 2.3.4 Real-Time Deployment Status UI

The system provides deployment status through standard Kubernetes and Argo
interfaces. Building custom dashboards or UIs is not part of this architecture.

---

### 2.3.5 Automatic Dependency Discovery

Dependencies MUST be explicitly declared. The system does not infer
dependencies from resource references, network policies, or runtime behavior.

---

## 2.4 Architectural Invariants

The following rules are **non-negotiable invariants**.
Violating any of these invalidates the design.

---

### Invariant 1 — Dependency Satisfaction Before Execution

A deployment node MUST NOT begin execution until **all** predecessor nodes in
the dependency DAG report Healthy status.

Progressing, degraded, or unknown status MUST be treated as not satisfied.

---

### Invariant 2 — Idempotency of All Operations

Executing the same deployment action with identical inputs MUST produce
identical observable platform state.

The system MUST NOT:

- create duplicate resources on repeated execution,
- fail on subsequent executions of successful operations,
- or produce different ordering on repeated runs.

---

### Invariant 3 — State Explicitness

The system MUST NOT rely on implicit state.

All state required for deployment decisions MUST be:

- queryable from Kubernetes resources,
- stored in Git repositories,
- or passed explicitly as inputs.

State from local files, environment variables not passed to the executor,
or external systems not declared as inputs is forbidden.

---

### Invariant 4 — Failure Propagation

A failure in any deployment node MUST:

- prevent all dependent nodes from executing,
- be distinguishable from in-progress status,
- and be observable through standard interfaces.

Silent failures or failures masked as success are forbidden.

---

### Invariant 5 — Health Verification Explicitness

Health status MUST be determined through explicit health checks.

Sync completion, resource existence, or pod readiness alone do not constitute
health. Custom resources MUST have defined health checks that verify actual
operational status.

---

### Invariant 6 — Teardown Order Enforcement

Teardown MUST execute in reverse dependency order.

A resource MUST NOT be removed while resources depending on it still exist.

The system MUST verify absence of dependents before removal.

---

### Invariant 7 — Authority Boundary Enforcement

Each layer in the architecture has exclusive authority over its domain:

- Bootstrap layer: cluster prerequisites and orchestration primitives
- Orchestration layer: cross-application dependency resolution
- Deployment layer: application state reconciliation
- Promotion layer: environment progression

No layer MUST bypass or override another's authority.

---

### Invariant 8 — Hook Prohibition

PreSync and PostSync hooks MUST NOT be used for dependency validation or
cross-application ordering.

All dependency logic MUST be expressed in the orchestration layer, not through
ArgoCD hooks or Helm hooks.

---

## 2.5 Operational Philosophy

The system is designed around the following operational beliefs:

- **Automation is a correctness requirement** — not a convenience. Manual steps
  are failure modes.

- **Human memory is not a dependency**. The system MUST operate correctly
  regardless of operator experience.

- **Failures will happen**; recovery MUST be routine. The system MUST assume
  failures and provide clear recovery paths.

- **Determinism enables trust**. Engineers MUST be able to predict deployment
  outcomes.

- **Observability is non-optional**. Every state transition MUST be logged and
  queryable.

- **Complexity is not excused by scale**. A 40-application platform MUST be
  as predictable as a 4-application platform.

This philosophy informs every tradeoff made later in the design.

---

## 2.6 Success Criteria

This architecture is considered successful if:

- Full platform deployment completes without human intervention.

- Deployment produces identical results across repeated executions.

- Failure in any component prevents dependent deployments and reports clearly.

- Platform teardown completes cleanly without orphaned resources.

- Engineers not involved in architecture design can operate the system from
  documentation alone.

- Mean time to recovery from deployment failures decreases by an order of
  magnitude.

- The system remains understandable years after its creation.

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← 1. Introduction](./01-introduction.md) | [Table of Contents](./00-index.md#table-of-contents) | [3. Architecture →](./03-architecture.md) |

---

*End of Section 2*
