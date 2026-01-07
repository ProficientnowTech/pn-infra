```
RFC-DEPLOY-0001                                           Appendix A
Category: Standards Track                      Glossary and Indexes
```

# Appendix A: Glossary and Indexes

[← Previous: Future Considerations](./09-evolution.md) | [Index](./00-index.md#table-of-contents) | [Next: References →](./appendix-b-references.md)

---

This appendix applies to **Sections 1 through 9** of this RFC.

It introduces **no new behavior**. Its purpose is **reference, traceability,
and longevity**.

---

## A.1 Glossary of Terms

This glossary defines terms **as used in this RFC**, not in general industry
usage.

---

### Core Concepts

---

#### Application (ArgoCD)

A Kubernetes custom resource that defines a set of Kubernetes resources to be
deployed from a Git repository source. ArgoCD Applications are the primary
unit of deployment management.

---

#### Bootstrap

The initial setup phase (Day 0-1) where orchestration primitives are installed
on a bare Kubernetes cluster. Bootstrap transforms a cluster into one capable
of self-managing through GitOps.

---

#### DAG (Directed Acyclic Graph)

A graph structure where edges have direction and no cycles exist. In this RFC,
DAGs represent dependency relationships between deployment nodes.

---

#### Dependency

A relationship where one component requires another to be operational before
it can function. Dependencies are explicitly declared and enforced during
deployment.

---

#### Executor

The containerized component providing a unified interface for platform
lifecycle operations (deploy, validate, teardown). The executor is stateless
and idempotent.

---

#### GitOps Handoff

The point in the deployment lifecycle where authority transitions from
imperative bootstrap to declarative GitOps management. Marked by creation
of the Root Application.

---

#### Health Status

The operational state of a resource. Standard statuses include Healthy,
Progressing, Degraded, Suspended, and Missing.

---

#### Idempotency

The property where an operation produces the same result regardless of how
many times it is executed with the same inputs.

---

#### Invariant

A rule that MUST always hold true. Violating an invariant invalidates the
architecture.

---

#### Layer

A conceptual grouping of components with related responsibilities and
authority. The four layers are: Bootstrap, Orchestration, Deployment,
Promotion.

---

#### Orchestration

The coordination of multiple deployments in correct dependency order with
health verification. Orchestration determines *when* things deploy, not
*what* deploys.

---

#### Phase

A stage in the deployment lifecycle with defined pre-conditions, actions,
and transition criteria. The five phases are: Pre-Bootstrap, Bootstrap,
Orchestration, Steady-State, Teardown.

---

#### Stack

A logical grouping of related Applications that deploy together. Examples:
infrastructure stack, security stack, monitoring stack.

---

#### Sync Wave

An integer annotation on Kubernetes resources that determines ordering
**within a single ArgoCD Application**. Sync waves do not order across
Applications.

---

#### Target Chart

A Helm chart that generates ArgoCD Application resources. Used in the
App-of-Apps pattern to create Applications from templates.

---

### Status Terms

---

#### Healthy

A resource that is fully operational, serving traffic (if applicable), and
passing all health checks.

---

#### Progressing

A resource that is transitioning toward desired state. Not yet healthy but
making progress.

---

#### Degraded

A resource that is partially operational. Some functionality may be impaired.

---

#### Suspended

A resource that is intentionally paused. Not an error state.

---

#### Missing

An expected resource that does not exist in the cluster.

---

#### Synced

An ArgoCD Application where the live state matches the desired state from Git.

---

#### OutOfSync

An ArgoCD Application where the live state differs from the desired state.

---

### Phase Terms

---

#### Day 0

Infrastructure provisioning. Creating the Kubernetes cluster itself.

---

#### Day 1

Initial application deployment. Installing platform components on the cluster.

---

#### Day 2+

Ongoing operations. Maintenance, updates, and continuous operation of the
platform.

---

### Technical Terms

---

#### ClusterWorkflowTemplate

An Argo Workflows resource defining a reusable workflow template available
cluster-wide.

---

#### EventBus

An Argo Events resource providing message transport between EventSources
and Sensors.

---

#### EventSource

An Argo Events resource that produces events from external sources (webhooks,
schedules, Kubernetes events).

---

#### Freight (Kargo)

A versioned bundle of artifacts (Git commits, container images) that can be
promoted through Stages.

---

#### Health Propagation

The mechanism by which health status flows from child resources to parent
resources, enabling aggregate health assessment.

---

#### PreSync Hook

An ArgoCD resource annotation causing a Job to run before Application sync.
This RFC prohibits using PreSync hooks for dependency orchestration.

---

#### Six-Phase Task Structure

The mandatory structure for Ansible bootstrap tasks: pre-check, apply, test,
validate, rollback, result. Each phase has defined responsibilities ensuring
tasks are reproducible, deterministic, and revertable.

---

#### Sensor

An Argo Events resource that evaluates events and triggers workflows when
conditions match.

---

#### Stage (Kargo)

A Kargo resource representing an environment (dev, staging, prod) through
which Freight is promoted.

---

#### Warehouse (Kargo)

A Kargo resource that monitors sources (Git, images) and creates Freight
when changes are detected.

---

## A.2 Architecture Decision Record (ADR) Index

This index summarizes **key architectural decisions**, their rationale, and
where they are defined.

---

### ADR-001 — DAG-Based Orchestration Over Hooks

- **Decision**: Use Argo Workflows DAGs for cross-application orchestration
- **Rationale**: Hooks have race conditions; DAGs provide deterministic ordering
- **Defined In**: [Section 2](./02-requirements.md), [Section 8](./08-rationale.md)

---

### ADR-002 — Layered Authority Model

- **Decision**: Separate bootstrap, orchestration, deployment, and promotion layers
- **Rationale**: Clear boundaries prevent authority conflicts
- **Defined In**: [Section 3](./03-architecture.md)

---

### ADR-009 — Deployment-Time Only Dependency Enforcement

- **Decision**: Dependencies are enforced at deployment time, not runtime
- **Rationale**: Cascading deletions are dangerous; applications should be resilient
- **Defined In**: [Section 3.7](./03-architecture.md#37-runtime-dependency-failure-semantics)

---

### ADR-010 — Helm-Only Installation Method

- **Decision**: All bootstrap installations MUST use Helm charts exclusively
- **Rationale**: Consistent templating, upgrade/rollback capability, release tracking
- **Defined In**: [Section 6.2.1](./06-lifecycle-management.md#621-ansible-bootstrap-standards)

---

### ADR-011 — Six-Phase Task Structure

- **Decision**: Every Ansible task MUST implement pre-check, apply, test, validate, rollback, result phases
- **Rationale**: Ensures reproducibility, determinism, and recoverability
- **Defined In**: [Section 6.2.1](./06-lifecycle-management.md#621-ansible-bootstrap-standards)

---

### ADR-012 — Single Production Environment Scope

- **Decision**: This RFC addresses single-cluster, production-only deployment
- **Rationale**: Multi-environment platform promotion is deferred to future evolution
- **Defined In**: [Section 3.9](./03-architecture.md#39-environment-scope)

---

### ADR-003 — Ansible-Recommended Bootstrap

- **Decision**: Recommend Ansible for bootstrap, remain technology-agnostic
- **Rationale**: Idempotent, declarative, Kubernetes-native modules
- **Defined In**: [Section 4](./04-components.md)

---

### ADR-004 — Containerized Executor

- **Decision**: Package deployment interface as container image
- **Rationale**: Portable, reproducible, air-gap capable
- **Defined In**: [Section 7](./07-executor-specification.md)

---

### ADR-005 — Health-Gated Progression

- **Decision**: Require explicit health verification before proceeding
- **Rationale**: Sync completion alone does not indicate operational readiness
- **Defined In**: [Section 2](./02-requirements.md), [Section 5](./05-orchestration-mechanics.md)

---

### ADR-006 — PreSync Hook Prohibition

- **Decision**: Prohibit PreSync/PostSync hooks for dependency logic
- **Rationale**: Race conditions make hooks unreliable for this purpose
- **Defined In**: [Section 2](./02-requirements.md), [Section 8](./08-rationale.md)

---

### ADR-007 — Single-Cluster Initial Scope

- **Decision**: Focus on single-cluster deployment; defer multi-cluster
- **Rationale**: Solve core problem first; multi-cluster is additive
- **Defined In**: [Section 2](./02-requirements.md), [Section 9](./09-evolution.md)

---

### ADR-008 — Argo Ecosystem Adoption

- **Decision**: Use Argo Workflows, ArgoCD, Argo Events, Kargo together
- **Rationale**: Consistent patterns, tight integration, proven at scale
- **Defined In**: [Section 3](./03-architecture.md), [Section 4](./04-components.md)

---

## A.3 Diagram Index

This index lists **all Mermaid diagrams** in the RFC, with their purpose and
location.

---

### Architecture Diagrams

| Diagram                              | Section |
| ------------------------------------ | ------- |
| Four-Layer Architecture              | [3.1](./03-architecture.md#31-architectural-overview) |
| Trust Boundary - Bootstrap           | [3.4](./03-architecture.md#34-trust-boundaries) |
| Trust Boundary - Orchestration       | [3.4](./03-architecture.md#34-trust-boundaries) |
| Trust Boundary - External            | [3.4](./03-architecture.md#34-trust-boundaries) |
| High-Level Control Flow Sequence     | [3.5](./03-architecture.md#35-high-level-control-flow) |

---

### Dependency Diagrams

| Diagram                              | Section |
| ------------------------------------ | ------- |
| Platform Dependency Layers           | [5.2](./05-orchestration-mechanics.md#52-platform-dependency-layers) |

---

### Status Diagrams

| Diagram                              | Section |
| ------------------------------------ | ------- |
| Health Status State Machine          | [5.5](./05-orchestration-mechanics.md#55-health-propagation-contracts) |

---

### Evolution Diagrams

| Diagram                              | Section |
| ------------------------------------ | ------- |
| Hub-Spoke Multi-Cluster Model        | [9.2](./09-evolution.md#92-multi-cluster-federation) |

---

## A.4 Invariant Index

| ID | Invariant | Section |
|----|-----------|---------|
| INV-1 | Dependency Satisfaction Before Execution | [2.4](./02-requirements.md#24-architectural-invariants) |
| INV-2 | Idempotency of All Operations | [2.4](./02-requirements.md#24-architectural-invariants) |
| INV-3 | State Explicitness | [2.4](./02-requirements.md#24-architectural-invariants) |
| INV-4 | Failure Propagation | [2.4](./02-requirements.md#24-architectural-invariants) |
| INV-5 | Health Verification Explicitness | [2.4](./02-requirements.md#24-architectural-invariants) |
| INV-6 | Teardown Order Enforcement | [2.4](./02-requirements.md#24-architectural-invariants) |
| INV-7 | Authority Boundary Enforcement | [2.4](./02-requirements.md#24-architectural-invariants) |
| INV-8 | Hook Prohibition | [2.4](./02-requirements.md#24-architectural-invariants) |

---

## A.5 Reading Paths

### For New Platform Engineers

1. [1. Introduction](./01-introduction.md)
2. [2. Requirements](./02-requirements.md)
3. [3. Architecture](./03-architecture.md)
4. [4. Components](./04-components.md)
5. [5. Orchestration Mechanics](./05-orchestration-mechanics.md)

---

### For Operators and SRE

1. [1. Introduction](./01-introduction.md)
2. [2. Requirements](./02-requirements.md)
3. [5. Orchestration Mechanics](./05-orchestration-mechanics.md)
4. [6. Lifecycle Management](./06-lifecycle-management.md)
5. [7. Executor Specification](./07-executor-specification.md)

---

### For Security Review

1. [2. Requirements](./02-requirements.md)
2. [3. Architecture](./03-architecture.md)
3. [7. Executor Specification](./07-executor-specification.md)

---

### For Future Architects

1. [2. Requirements](./02-requirements.md)
2. [8. Design Rationale](./08-rationale.md)
3. [9. Future Considerations](./09-evolution.md)

---

## A.6 Final Note

This appendix exists to ensure that:

- architectural intent does not decay,
- decisions are not re-litigated without context,
- and the system remains understandable long after its original authors move on.

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← 9. Future Considerations](./09-evolution.md) | [Table of Contents](./00-index.md#table-of-contents) | [Appendix B: References →](./appendix-b-references.md) |

---

*End of Appendix A*
