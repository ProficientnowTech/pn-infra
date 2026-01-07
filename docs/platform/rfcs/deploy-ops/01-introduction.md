```
RFC-DEPLOY-0001                                              Section 1
Category: Standards Track                                 Introduction
```

# 1. Introduction and Motivation

[Index](./00-index.md#table-of-contents) | [Next: Requirements →](./02-requirements.md)

---

## 1.1 Background and Context

Platform deployment at scale is deceptively complex.

What begins as straightforward application installation evolves into an
intricate web of dependencies, ordering constraints, and health verification
requirements. The platform described in this RFC comprises 11 logical stacks
containing over 40 interdependent applications, ranging from storage
infrastructure to application runtimes.

The dependency relationships between these applications form a directed acyclic
graph (DAG) where:

- Temporal workflow orchestration requires PostgreSQL databases, which require
  the Zalando PostgreSQL operator, which requires storage classes, which require
  the Ceph cluster, which requires the Ceph operator.

- Ingress controllers require LoadBalancer IP allocation from MetalLB, while
  applications requiring external access depend on both ingress and DNS
  configuration.

- Secret management systems must be operational before applications can retrieve
  credentials, yet those systems themselves require bootstrap secrets.

This RFC exists because the original deployment system reached a point where:

- incremental fixes no longer produced reliable outcomes,
- operational risk increased faster than platform capabilities,
- and deployment orchestration became a persistent source of incidents requiring
  human intervention.

> **The architecture proposed in this RFC was *not* designed or implemented
> from the beginning.** It emerged as a necessity, driven by accumulated
> operational failures, non-deterministic behaviors, and maintenance burden.

---

## 1.2 The Initial System (Pre-Architecture State)

The original deployment approach evolved organically alongside the platform.

At a high level, it consisted of:

- **Bash scripts** for bootstrap, deployment, and teardown:
  - reading environment configuration,
  - installing Helm charts in sequence,
  - waiting for pod readiness,
  - applying post-installation configuration.

- **ArgoCD sync waves** for resource ordering:
  - integers ranging from -30 to +50 across different stacks,
  - intended to sequence resources within Applications,
  - misapplied to express cross-Application dependencies.

- **PreSync and PostSync hooks** for dependency validation:
  - Kubernetes Jobs running before Application sync,
  - checking if prerequisite resources exist and are healthy,
  - intended to gate deployment until dependencies are satisfied.

- **App-of-Apps pattern** for hierarchical deployment:
  - root Application generating stack Applications,
  - stack Applications generating individual component Applications,
  - nested structure intended to create deployment cascades.

This system worked — until the platform grew beyond a threshold where its
assumptions no longer held.

---

## 1.3 Operational Shortcomings

As the platform expanded, several structural problems became apparent.

### 1.3.1 Bash Scripts Became Hidden Control Planes

Deployment scripts accumulated responsibilities beyond their original intent:

- validation logic,
- conditional execution paths,
- secret rendering and encryption,
- orchestration and ordering,
- error recovery and retry logic.

This introduced systemic problems:

- **Implicit state**
  Script behavior depended on local files, cached outputs, and environment
  variables that were not versioned or observable.

- **Non-reproducibility**
  Running the same script on two machines could yield different results.

- **Opaque failure modes**
  Partial failures were common and difficult to diagnose. A script could fail
  silently or succeed partially, leaving the platform in an indeterminate state.

- **Human coupling**
  Correct operation depended on tribal knowledge rather than enforced guarantees.
  New engineers could not safely execute deployments without extensive guidance.

The scripts did not merely automate work — they became an undocumented,
unversioned control plane.

---

### 1.3.2 PreSync Hooks Exhibited Race Conditions

PreSync hooks were introduced to solve the dependency problem: ensure
prerequisites exist before deploying dependent applications.

In practice, they introduced new failure modes:

- **ttlSecondsAfterFinished race conditions**
  Jobs configured with short TTL values could be garbage-collected before
  ArgoCD marked the hook as complete, causing the sync to hang indefinitely.

- **BeforeHookCreation deletion policy races**
  When a new sync triggered, the previous hook Job was deleted before the new
  one started, creating temporal gaps where no validation occurred.

- **Jobs modifying their own state**
  Some hooks attempted to create or modify resources, causing ArgoCD to detect
  drift and trigger additional reconciliation cycles.

- **Resource exhaustion**
  Hooks executed on every ArgoCD reconciliation — not just initial deployment.
  A platform with 40+ Applications reconciling every 3 minutes generated
  thousands of Job executions daily.

The hooks became a significant source of operational incidents. Engineers
regularly needed to manually delete stuck Job pods to unblock deployments.

---

### 1.3.3 Sync Waves Could Not Express Cross-Application Dependencies

ArgoCD sync waves order resources **within a single Application**.

The platform attempted to use sync waves to order **across Applications** by:

- assigning large negative waves to foundational stacks,
- assigning large positive waves to dependent stacks,
- expecting ArgoCD to process lower waves first.

This approach failed because:

- ArgoCD does not guarantee cross-Application ordering based on sync waves,
- the App-of-Apps pattern creates separate reconciliation contexts,
- and health status of one Application does not block sync of another.

This limitation is documented in ArgoCD issue #7437, which has accumulated
significant community support requesting native cross-Application dependency
support.

---

### 1.3.4 Manual Intervention Became Routine

The combination of these issues meant that:

- Full platform deployments rarely succeeded without intervention.
- Engineers needed to monitor deployment progress and manually restart stuck
  components.
- Teardown was even less reliable, often leaving orphaned resources.
- Recovery from partial failures required deep platform knowledge.

The system was not deterministic. Given the same inputs, it could produce
different outcomes depending on timing, network conditions, and resource
availability.

---

## 1.4 The Cost of Hook-Driven Orchestration

Hook-based dependency management imposed costs across multiple dimensions:

**Operational cost**
- Engineers spent significant time debugging stuck deployments.
- On-call incidents frequently traced to hook failures.
- Deployment windows extended due to unpredictable behavior.

**Resource cost**
- Thousands of Job executions consumed cluster resources.
- Each hook required its own container image, RBAC, and configuration.
- Failed Jobs persisted until manual cleanup.

**Cognitive cost**
- New engineers struggled to understand the deployment sequence.
- Documentation lagged behind workarounds.
- Tribal knowledge became a single point of failure.

**Reliability cost**
- Deployment success rate was below acceptable thresholds.
- Platform availability depended on human intervention.
- Disaster recovery could not be automated.

---

## 1.5 Why Incremental Fixes Failed

Multiple attempts were made to improve the system incrementally:

- **Longer TTL values**: Reduced garbage collection races but increased resource
  consumption.

- **Better validation scripts**: Made hooks more robust but did not address
  fundamental timing issues.

- **Documentation improvements**: Helped new engineers but did not eliminate
  human-in-the-loop requirements.

- **Monitoring and alerting**: Made failures visible faster but did not prevent
  them.

- **Sync wave reorganization**: Consolidated wave ranges but could not express
  cross-Application dependencies.

These efforts reduced symptoms but never addressed the root problem.

The underlying issue was architectural:

> **Dependencies were treated as validation checks rather than structural
> constraints in the deployment system.**

As long as dependencies were enforced through hooks rather than modeled in the
orchestration layer, non-determinism and race conditions were inevitable.

---

## 1.6 Why Dedicated Orchestration Became Necessary

At scale, platform deployment requires:

- explicit dependency graphs,
- deterministic execution ordering,
- health-gated progression between deployment phases,
- automated recovery from transient failures,
- and reproducibility from source control.

These requirements CANNOT be satisfied by:

- scripts with implicit ordering,
- hooks with race conditions,
- or sync waves that operate only within Applications.

The system described in subsequent sections represents a **structural
correction**, not an optimization.

It formalizes deployment orchestration as:

- a platform subsystem,
- with clearly defined phases,
- explicit dependency DAGs,
- and strict separation between bootstrap, orchestration, and steady-state
  operations.

Only with such a system can the platform:

- eliminate entire classes of human error,
- scale across environments,
- and remain operationally sustainable.

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| — | [Table of Contents](./00-index.md#table-of-contents) | [2. Requirements →](./02-requirements.md) |

---

*End of Section 1*
