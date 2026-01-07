```
RFC-DEPLOY-0001                                              Section 4
Category: Standards Track                          System Components
```

# 4. System Components

[← Previous: Architecture](./03-architecture.md) | [Index](./00-index.md#table-of-contents) | [Next: Orchestration Mechanics →](./05-orchestration-mechanics.md)

---

This section defines the **system building blocks**: what each component does,
what it is responsible for, and where its authority ends. Component interaction
patterns and failure scenarios are also specified.

---

## 4.1 Component Taxonomy

The deployment orchestration system comprises seven primary components:

| Component                  | Layer         | Primary Responsibility                      |
| -------------------------- | ------------- | ------------------------------------------- |
| Bootstrap Controller       | Bootstrap     | Day 0-1 cluster setup and primitive install |
| Argo Workflows Orchestrator| Orchestration | DAG execution and health-gated progression  |
| ArgoCD Application Controller | Deployment | Application sync and drift correction       |
| Containerized Executor     | All           | Unified interface for deploy/validate/teardown |
| Argo Events System         | Orchestration | Event-driven workflow triggers              |
| Kargo Promotion Controller | Promotion     | Environment-to-environment progression      |
| Health Propagation System  | Deployment    | Custom health checks and status aggregation |

Each component has:

- defined responsibilities,
- explicit interfaces,
- clear authority boundaries,
- and documented failure modes.

---

## 4.2 Bootstrap Controller

### Responsibility

The bootstrap controller establishes the foundation for GitOps-managed
deployment by installing orchestration primitives that do not yet exist.

### What It Does

- Verifies cluster prerequisites (API accessibility, required CRDs)
- Installs ArgoCD with required configuration
- Installs Argo Workflows controller
- Installs Argo Events components (EventBus, controller)
- Creates automation credentials for cross-system integration
- Applies ClusterWorkflowTemplates for reusable workflows
- Creates the Root Application that defines GitOps handoff

### What It Does NOT Do

- Manage application state after handoff
- Execute deployment ordering logic
- Handle runtime failures or drift
- Manage environment promotions

### Inputs

- Cluster kubeconfig with administrative access
- Environment configuration (domain, namespace conventions)
- Git repository references
- Container registry credentials (if private)

### Outputs

- Operational ArgoCD instance
- Operational Argo Workflows controller
- Operational Argo Events system
- Root Application pointing to platform manifests

### Technology Recommendation

Ansible with the `kubernetes.core` collection is RECOMMENDED due to:

- idempotent task execution,
- declarative role-based structure,
- native Kubernetes module support,
- and explicit state verification.

Alternative technologies MAY be used if they satisfy the same invariants.

### Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Cluster unreachable | API connection timeout | Verify network, retry |
| CRD installation failed | Resource creation error | Check RBAC, retry |
| ArgoCD not becoming ready | Pod health timeout | Check resources, logs |
| Workflow controller failed | Deployment status | Check images, RBAC |

---

## 4.3 Argo Workflows DAG Orchestrator

### Responsibility

The Argo Workflows orchestrator executes the platform deployment DAG, ensuring
applications deploy in correct dependency order with health verification
between nodes.

### What It Does

- Accepts DAG specification as workflow definition
- Executes nodes in topological order
- Invokes ArgoCD sync for each Application
- Waits for health status before proceeding to dependents
- Handles transient failures with configurable retry
- Reports workflow status and logs

### What It Does NOT Do

- Define application configurations
- Manage application state after deployment
- Handle drift detection or self-healing
- Manage environment promotions

### Interfaces

**Input: Workflow Definition**

A Workflow or WorkflowTemplate resource defining:

- DAG structure with node dependencies
- ArgoCD Application references for each node
- Timeout and retry policies
- Health verification criteria

**Output: Workflow Status**

- Phase (Running, Succeeded, Failed)
- Per-node status and duration
- Failure reasons and logs
- Resume capability from failure point

### Authority Boundary

Argo Workflows has authority over **deployment ordering**.

It MUST NOT:

- modify Application specifications,
- bypass ArgoCD for resource application,
- or assume Application health without verification.

### Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Workflow timeout | Phase timeout exceeded | Increase timeout or investigate |
| ArgoCD sync failed | Sync operation error | Check Application, retry |
| Health check failed | Health status not Healthy | Investigate application |
| Node dependency failed | Predecessor node failed | Fix predecessor, resume |

---

## 4.4 ArgoCD Application Controller

### Responsibility

ArgoCD manages the declarative state of Applications, ensuring cluster state
matches Git-defined intent.

### What It Does

- Syncs Application resources from Git sources
- Detects drift between desired and live state
- Corrects drift through reconciliation
- Reports health and sync status
- Propagates health through nested Applications (when configured)

### What It Does NOT Do

- Determine deployment order across Applications
- Wait for dependencies before syncing
- Manage cross-Application health gates
- Handle promotion between environments

### Health Propagation Contract

For the deployment orchestration system to function correctly, ArgoCD MUST
be configured to:

- Propagate health status for nested Applications
- Support custom health checks for CRDs
- Report accurate health for operator-managed resources

This requires specific ConfigMap customizations documented in
[Section 5.5](./05-orchestration-mechanics.md#55-health-propagation-contracts).

### Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Sync failed | Application sync status | Check manifests, resources |
| Health degraded | Health status Degraded | Investigate application |
| Out of sync | Sync status OutOfSync | Manual sync or auto-sync |
| Missing resources | Health status Missing | Verify source repository |

---

## 4.5 Containerized Executor

### Responsibility

The containerized executor provides a unified interface for invoking deployment
actions, enabling automation from any context that can run containers.

### What It Does

- Accepts action parameter (deploy, validate, teardown)
- Accepts target scope (full platform, specific stack, specific application)
- Invokes appropriate layer based on action and platform state
- Reports action status and diagnostic information

### What It Does NOT Do

- Store state between invocations
- Make decisions based on previous runs
- Maintain persistent connections
- Define deployment configuration

### Interface Contract

The executor MUST:

- Be packaged as a container image
- Accept configuration through environment variables
- Accept credentials through mounted secrets
- Support deploy, validate, and teardown actions
- Exit with defined status codes
- Produce structured logs

Full specification in [Section 7](./07-executor-specification.md).

### Statelessness Requirement

The executor MUST NOT maintain state between invocations.

All state required for operation MUST be:

- passed as input parameters,
- queried from Kubernetes resources,
- or read from mounted configuration.

This ensures idempotency and reproducibility.

### Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Configuration invalid | Startup validation error | Fix configuration |
| Credentials invalid | Authentication error | Rotate credentials |
| Target not found | Resource query failure | Verify target exists |
| Action failed | Non-zero exit code | Check logs, retry |

---

## 4.6 Argo Events Trigger System

### Responsibility

Argo Events enables event-driven workflow execution, allowing external events
to trigger deployment workflows.

### What It Does

- Receives events from configured sources (Git webhooks, schedules, manual)
- Evaluates trigger conditions
- Submits workflows with event-derived parameters
- Provides event delivery guarantees through EventBus

### What It Does NOT Do

- Execute deployment logic
- Manage workflow state
- Define deployment ordering
- Handle workflow failures

### Components

**EventBus**

Message transport providing reliable event delivery between EventSources
and Sensors.

**EventSource**

Produces events from external sources:

- Git repository webhooks
- Scheduled triggers (cron)
- Manual triggers (API)
- Kubernetes resource events

**Sensor**

Evaluates events against triggers and submits workflows when conditions match.

### Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| EventBus unavailable | Event delivery failed | Check EventBus health |
| Webhook not received | Missing workflow trigger | Verify webhook config |
| Trigger condition error | Sensor error logs | Fix trigger definition |
| Workflow submission failed | Sensor action error | Check workflow template |

---

## 4.7 Kargo Promotion Controller

### Responsibility

Kargo manages promotion of changes between environments (development, staging,
production) with verification gates.

### What It Does

- Monitors Warehouses for new artifacts (Git commits, images)
- Creates Freight representing promotable artifact bundles
- Promotes Freight through defined Stages
- Executes verification steps before promotion completes
- Enforces soak times between environments

### What It Does NOT Do

- Deploy applications (delegated to ArgoCD)
- Define application configurations
- Manage deployment ordering
- Handle cross-application dependencies

### Authority Boundary

Kargo has authority over **environment progression**.

It MUST NOT:

- bypass ArgoCD for application sync,
- modify application configurations directly,
- or deploy applications outside the promotion pipeline.

### Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Verification failed | Stage status Failed | Investigate, re-promote |
| Promotion blocked | Stage status Blocked | Check prerequisites |
| Freight creation failed | Warehouse error | Check subscriptions |
| ArgoCD update failed | Promotion step error | Check ArgoCD, retry |

---

## 4.8 Health Propagation System

### Responsibility

The health propagation system ensures accurate health status for all resources,
including custom resources that require specialized health checks.

### What It Does

- Defines custom health checks for CRDs
- Aggregates health across nested Applications
- Reports health status through ArgoCD
- Enables health-gated deployment progression

### What It Does NOT Do

- Fix unhealthy resources
- Make deployment decisions
- Manage resource lifecycle
- Store health history

### Custom Health Definitions Required

The following resource types require custom health checks:

| Resource Type | Health Criteria |
|---------------|-----------------|
| CephCluster | Phase equals Ready, health status HEALTH_OK |
| PostgreSQL (Zalando) | Cluster status Running, replicas ready |
| Vault | Initialized, unsealed, active |
| Temporal | Frontend service healthy |
| ArgoCD Application | Health status Healthy (nested) |

### Configuration Location

Custom health checks are defined in the ArgoCD ConfigMap under
`resource.customizations.health.<group>_<kind>`.

---

## 4.9 Phase-to-Component Mapping

| Phase | Primary Component | Supporting Components |
|-------|-------------------|----------------------|
| Pre-Bootstrap | Executor | — |
| Bootstrap | Bootstrap Controller | Executor |
| Orchestration | Argo Workflows | ArgoCD, Executor, Health System |
| Steady-State | ArgoCD | Argo Events, Kargo, Argo Rollouts |
| Teardown | Argo Workflows | ArgoCD, Bootstrap Controller |

---

## 4.10 Failure and Recovery Scenarios

### Scenario 1: Bootstrap Failure

**Situation**: ArgoCD installation fails due to resource constraints.

**Detection**: Bootstrap controller reports installation error.

**Recovery**:
1. Investigate resource constraints (memory, CPU, storage)
2. Adjust cluster resources or installation values
3. Re-run bootstrap (idempotent operation)

**Impact**: Orchestration cannot start; no platform applications affected.

---

### Scenario 2: DAG Node Failure

**Situation**: Ceph cluster fails health check during orchestration.

**Detection**: Argo Workflow node reports health verification failure.

**Recovery**:
1. Investigate Ceph cluster status
2. Fix underlying issue (storage, network, configuration)
3. Resume workflow from failed node

**Impact**: Dependent applications (databases, stateful workloads) not deployed.

---

### Scenario 3: ArgoCD Sync Failure

**Situation**: Application sync fails due to invalid manifest.

**Detection**: ArgoCD reports sync error; health status Degraded.

**Recovery**:
1. Identify invalid manifest from ArgoCD error
2. Fix manifest in Git repository
3. ArgoCD auto-syncs corrected manifest

**Impact**: Specific application degraded; workflow waits for health.

---

### Scenario 4: Promotion Verification Failure

**Situation**: Staging promotion fails verification tests.

**Detection**: Kargo Stage status shows Failed.

**Recovery**:
1. Investigate verification test failures
2. Fix application issues in development
3. New Freight created and promoted

**Impact**: Staging not updated; production unaffected.

---

### Scenario 5: Complete Cluster Loss

**Situation**: Cluster is destroyed or unrecoverable.

**Detection**: External monitoring; unable to connect to API.

**Recovery**:
1. Provision new cluster
2. Run executor with deploy action
3. Bootstrap establishes primitives
4. Orchestration deploys platform from Git

**Impact**: Full outage during recovery; no data loss if storage is external.

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← 3. Architecture](./03-architecture.md) | [Table of Contents](./00-index.md#table-of-contents) | [5. Orchestration Mechanics →](./05-orchestration-mechanics.md) |

---

*End of Section 4*
