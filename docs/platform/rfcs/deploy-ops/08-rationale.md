```
RFC-DEPLOY-0001                                              Section 8
Category: Standards Track                          Design Rationale
```

# 8. Design Rationale

[← Previous: Executor Specification](./07-executor-specification.md) | [Index](./00-index.md#table-of-contents) | [Next: Future Considerations →](./09-evolution.md)

---

This section documents **explicit architectural decisions** and the
**rationale for rejecting alternatives**.

---

## 8.1 Why This Section Exists

Architectures rarely fail because they were wrong at inception.
They fail because **future changes violate original assumptions**.

This section exists to:

- make trade-offs explicit,
- record historical context,
- prevent architectural regression,
- and explain *why* certain seemingly simpler approaches were rejected.

All alternatives discussed here were **seriously considered** and, in many
cases, **actually implemented** before being replaced.

---

## 8.2 Bash Scripts for Orchestration

### Description

Deployment orchestration through bash scripts that:

- install components in sequence,
- use shell loops for health checking,
- implement retry logic through sleep and polling,
- pass state through environment variables and files.

---

### Why It Was Attractive

- Fast to implement for initial prototype
- Flexible and easy to modify
- No additional infrastructure required
- Engineers already familiar with bash

---

### Why It Was Rejected

1. **Implicit State**
   Script behavior depended on local files, environment state, and execution
   context that was not versioned or reproducible.

2. **Non-Idempotency**
   Running the same script multiple times could produce different results.
   Scripts often assumed clean state or failed on existing resources.

3. **Opaque Failure Modes**
   When scripts failed partway, the system state was indeterminate. Debugging
   required reading through script execution to understand what happened.

4. **Human-Coupled Execution**
   Correct operation required tribal knowledge about execution order, required
   environment variables, and recovery procedures.

5. **No Built-In Observability**
   Script execution was difficult to monitor, trace, or audit. Log output was
   unstructured and inconsistent.

---

### Conclusion

Bash scripts are suitable for **simple, one-time operations**.

They do not meet the reliability, reproducibility, or observability
requirements of a production platform deployment system.

**Invariants Violated**: INV-2 (Idempotency), INV-3 (State Explicitness),
INV-4 (Failure Propagation)

---

## 8.3 ArgoCD PreSync Hooks for Dependencies

### Description

Kubernetes Jobs configured as ArgoCD PreSync hooks that:

- execute before Application sync,
- check if dependencies exist and are healthy,
- block sync until checks pass,
- use deletion policies for cleanup.

---

### Why It Was Attractive

- Native ArgoCD feature
- Declarative (defined in manifests)
- Could express any validation logic
- Kept dependency logic with Application

---

### Why It Was Rejected

1. **Race Conditions with ttlSecondsAfterFinished**
   Jobs configured with short TTL values could be garbage-collected before
   ArgoCD marked the hook as complete, causing indefinite sync hangs.

2. **BeforeHookCreation Deletion Policy Races**
   When a new sync triggered, the previous hook Job was deleted before the
   new one started, creating temporal gaps where no validation occurred.

3. **Execution on Every Reconciliation**
   Hooks executed on every ArgoCD reconciliation cycle, not just initial
   deployment. A platform with 40+ Applications reconciling every 3 minutes
   generated thousands of unnecessary Job executions daily.

4. **Resource Exhaustion**
   Hook Jobs consumed cluster resources even when dependencies were stable.
   Each execution created pods, consumed CPU/memory, and generated log data.

5. **Limited Cross-Application Visibility**
   Hooks could only see their own Application context. Cross-Application
   dependencies required external coordination.

6. **Stuck Jobs Required Manual Intervention**
   When hooks failed or hung, manual deletion of Job pods was required to
   unblock deployment. This violated zero-human-intervention requirements.

---

### Conclusion

PreSync hooks are appropriate for **application-internal setup tasks**
(database migrations, one-time initialization).

They are NOT appropriate for cross-application dependency orchestration.

**Invariants Violated**: INV-1 (Dependency Satisfaction), INV-5 (Health
Verification), INV-8 (Hook Prohibition)

---

## 8.4 Sync Waves Only for All Ordering

### Description

Using ArgoCD sync waves to order all deployments by:

- assigning large negative waves to foundational components,
- assigning zero to normal priority,
- assigning large positive waves to dependent applications.

---

### Why It Was Attractive

- Built-in ArgoCD feature
- Simple integer-based ordering
- No additional components required
- Familiar to ArgoCD users

---

### Why It Was Rejected

1. **Sync Waves Are Intra-Application Only**
   Sync waves order resources **within a single Application**. They do not
   order **across Applications**, even in App-of-Apps patterns.

2. **No Health-Based Gating**
   Sync waves proceed based on sync completion, not health status. An
   Application could have synced but be degraded or failing.

3. **ArgoCD Issue #7437**
   This limitation is well-documented. The ArgoCD community has been
   requesting native cross-Application dependency support since 2020.
   The issue has 280+ reactions.

4. **No DAG Support**
   Sync waves are linear (ordered integers). Complex dependency graphs
   cannot be expressed as linear orderings.

5. **Inconsistent Behavior with App-of-Apps**
   When using App-of-Apps, child Applications are separate reconciliation
   contexts. Parent sync wave has no effect on child ordering.

---

### Conclusion

Sync waves remain appropriate for **intra-Application resource ordering**
(Namespace before Deployment, CRD before instance).

They are NOT appropriate for cross-Application or cross-stack dependencies.

**Invariants Violated**: INV-1 (Dependency Satisfaction), INV-5 (Health
Verification Explicitness)

---

## 8.5 Custom Controller for Orchestration

### Description

Building a custom Kubernetes controller that:

- watches Application resources,
- tracks dependencies through annotations or CRDs,
- blocks Application sync until dependencies healthy,
- manages deployment ordering.

---

### Why It Was Attractive

- Full control over orchestration logic
- Native Kubernetes patterns
- Could integrate tightly with platform
- No dependency on external workflow system

---

### Why It Was Rejected

1. **Reinventing DAG Execution**
   A dependency orchestration controller is essentially a workflow engine.
   Building one duplicates work already done by Argo Workflows.

2. **Operational Burden**
   Custom controllers require ongoing maintenance, upgrades, and operational
   expertise. The platform team would become responsible for core
   orchestration infrastructure.

3. **Testing Complexity**
   Custom controllers require extensive testing for correctness, failure
   modes, and edge cases. Argo Workflows is battle-tested at scale.

4. **Community Support**
   A custom controller has no community. Issues require internal resolution.
   Argo Workflows has extensive community documentation and support.

5. **Feature Completeness**
   Argo Workflows provides DAG execution, retry policies, timeout handling,
   artifact passing, UI, API, and CLI out of the box.

---

### Conclusion

Custom controllers are appropriate when existing solutions do not meet
requirements.

For DAG-based orchestration, Argo Workflows provides a complete, proven
solution.

**Invariants Violated**: None directly, but violates engineering efficiency
principles.

---

## 8.6 Tekton Pipelines for Orchestration

### Description

Using Tekton Pipelines for deployment orchestration:

- Tekton Tasks for individual deployments,
- Tekton Pipelines for sequencing,
- Tekton Triggers for event-driven execution.

---

### Why It Was Attractive

- Already deployed in the platform (for CI/CD)
- Kubernetes-native
- Good community support
- Handles sequential execution

---

### Why It Was Rejected

1. **Task-Based vs DAG-Based**
   Tekton Pipelines are primarily linear task sequences. While parallelism
   is supported, complex DAGs are harder to express than in Argo Workflows.

2. **ArgoCD Integration**
   Argo Workflows has tighter integration with ArgoCD through shared Argo
   project ecosystem. Common patterns, CLI tooling, and API conventions.

3. **Different Primary Use Case**
   Tekton is designed for CI/CD pipelines (build, test, deploy artifacts).
   Argo Workflows is designed for general workflow orchestration.

4. **Two Systems Doing Similar Things**
   Using Tekton for both CI/CD and deployment orchestration creates
   conceptual overlap. Separating CI (Tekton) from CD orchestration
   (Argo Workflows) maintains clearer boundaries.

---

### Conclusion

Tekton remains appropriate for **CI/CD pipelines** (build, test, package).

Argo Workflows is preferred for **deployment orchestration** due to better
DAG support and Argo ecosystem integration.

**Invariants Violated**: None directly, but suboptimal for use case.

---

## 8.7 Helm Hooks for Dependencies

### Description

Using Helm hooks (pre-install, post-install, pre-upgrade) to:

- check dependencies before chart installation,
- run setup tasks,
- validate state.

---

### Why It Was Attractive

- Native Helm feature
- Defined alongside chart
- Familiar to Helm users
- No ArgoCD-specific configuration

---

### Why It Was Rejected

1. **Same Issues as ArgoCD Hooks**
   Helm hooks suffer from similar race conditions and cleanup issues as
   ArgoCD PreSync hooks.

2. **ArgoCD Renders Helm**
   When using ArgoCD with Helm charts, ArgoCD renders the chart and manages
   the resulting manifests. Helm hooks become ArgoCD hooks, inheriting all
   associated problems.

3. **Chart-Scoped Only**
   Helm hooks cannot see resources from other charts. Cross-chart
   dependencies require external coordination.

4. **Limited Visibility**
   Helm hook execution is less visible than ArgoCD hooks. Debugging requires
   examining Helm release history and pod logs.

---

### Conclusion

Helm hooks are appropriate for **chart-internal setup** (database creation,
migration).

They are NOT appropriate for cross-chart or cross-application dependencies.

**Invariants Violated**: INV-1 (Dependency Satisfaction), INV-8 (Hook
Prohibition by extension)

---

## 8.8 Script-Based Wait Loops

### Description

Embedding wait loops in deployment scripts or hooks:

- Poll for resource existence,
- Check health status periodically,
- Proceed when conditions met,
- Timeout after maximum duration.

---

### Why It Was Attractive

- Simple to implement
- No additional dependencies
- Flexible condition checking
- Easy to understand

---

### Why It Was Rejected

1. **Non-Deterministic Timing**
   Poll intervals and timeouts create race conditions. Resources might
   become ready between polls, or timeout might occur just before readiness.

2. **Resource Consumption**
   Polling consumes resources (API calls, CPU, network) continuously during
   wait periods.

3. **No Progress Visibility**
   External observers cannot see wait progress. Is it waiting? Stuck?
   Making progress?

4. **Compounding Delays**
   Multiple wait loops in sequence compound delays. A chain of 10 waits
   with 60-second poll intervals adds 10+ minutes even when resources are
   ready.

5. **Error Handling Complexity**
   Distinguishing between "not ready yet" and "will never be ready" is
   difficult with simple polling.

---

### Conclusion

Wait loops are a symptom of missing orchestration infrastructure.

Proper orchestration uses event-driven progression, not polling.

**Invariants Violated**: INV-5 (Health Verification Explicitness)

---

## 8.9 Why Incremental Improvements Were Insufficient

Each rejected approach failed for the same fundamental reason:

> **They attempted to add dependency logic to systems designed for other
> purposes.**

- Bash scripts are for automation, not orchestration.
- ArgoCD hooks are for application setup, not cross-app coordination.
- Sync waves are for resource ordering, not Application ordering.
- Helm hooks are for chart lifecycle, not platform lifecycle.

The chosen architecture succeeds because it:

- uses a **purpose-built workflow engine** (Argo Workflows) for DAG execution,
- separates **bootstrap authority** (Ansible) from **orchestration authority**
  (Argo Workflows) from **deployment authority** (ArgoCD),
- and treats dependencies as **structural constraints** rather than runtime
  checks.

---

## 8.10 Summary

The final architecture is not the simplest possible solution.

It is the **simplest solution that satisfies all invariants simultaneously**.

Every rejected alternative violated at least one invariant defined in
[Section 2](./02-requirements.md).

| Alternative | Primary Invariant(s) Violated |
|-------------|------------------------------|
| Bash Scripts | INV-2, INV-3, INV-4 |
| PreSync Hooks | INV-1, INV-5, INV-8 |
| Sync Waves Only | INV-1, INV-5 |
| Custom Controller | Engineering efficiency |
| Tekton Pipelines | Suboptimal for use case |
| Helm Hooks | INV-1, INV-8 |
| Wait Loops | INV-5 |

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← 7. Executor Specification](./07-executor-specification.md) | [Table of Contents](./00-index.md#table-of-contents) | [9. Future Considerations →](./09-evolution.md) |

---

*End of Section 8*
