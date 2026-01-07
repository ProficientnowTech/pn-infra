```
RFC-DEPLOY-0001                                              Section 6
Category: Standards Track                       Lifecycle Management
```

# 6. Lifecycle Management

[← Previous: Orchestration Mechanics](./05-orchestration-mechanics.md) | [Index](./00-index.md#table-of-contents) | [Next: Executor Specification →](./07-executor-specification.md)

---

This section defines the **lifecycle phases** of the deployment system: what
happens in each phase, what transitions between phases, and how the system
behaves during steady-state and teardown.

---

## 6.1 Phase 0: Pre-Bootstrap

### Purpose

Verify that the target cluster is ready to receive the platform and validate
all prerequisites before beginning deployment.

---

### Pre-Conditions

The following conditions MUST be satisfied before proceeding:

| Condition | Verification |
|-----------|--------------|
| Kubernetes API accessible | API server responds to requests |
| Authentication valid | kubeconfig credentials accepted |
| Required permissions | ServiceAccount or user has cluster-admin or equivalent |
| Container runtime operational | Pods can be scheduled and run |
| Network connectivity | Cluster can reach container registries |
| Storage available | Nodes have sufficient disk space |

---

### Actions

1. **Connectivity verification**: Test Kubernetes API accessibility
2. **Permission verification**: Validate required RBAC permissions
3. **Resource verification**: Check available cluster resources
4. **Registry verification**: Test container image pull capability
5. **Prerequisite CRD check**: Identify any pre-existing CRDs

---

### Outputs

- Validation report indicating readiness
- List of any blocking issues
- Cluster state snapshot for comparison

---

### Transition Criteria

Proceed to Phase 1 when:
- All pre-conditions are satisfied
- No blocking issues identified
- Executor receives positive validation result

---

### Failure Handling

If pre-conditions are not met:
- Report specific failures
- Do not proceed to Phase 1
- Exit with diagnostic information

---

## 6.2 Phase 1: Bootstrap (Day 0-1)

### Purpose

Establish the orchestration primitives that enable GitOps-managed deployment.
This phase transforms a bare Kubernetes cluster into one capable of
self-managing platform applications.

---

### Pre-Conditions

- Phase 0 completed successfully
- Bootstrap configuration available
- Container images accessible

---

### Actions

**Step 1: Namespace Preparation**

Create namespaces for orchestration components:
- ArgoCD namespace
- Argo Workflows namespace
- Argo Events namespace

**Step 2: ArgoCD Installation**

Install ArgoCD with required configuration:
- High-availability configuration (if specified)
- Custom health checks for Application resources
- CRD-specific health check definitions
- Resource customizations

**Step 3: ArgoCD Readiness Verification**

Wait for ArgoCD components to become operational:
- API server responding
- Application controller running
- Repo server running

**Step 4: Argo Workflows Installation**

Install Argo Workflows controller:
- Controller deployment
- Required CRDs
- RBAC configuration

**Step 5: ClusterWorkflowTemplate Installation**

Apply reusable workflow templates:
- sync-and-wait template for ArgoCD operations
- validation templates for health checks
- teardown templates for cleanup

**Step 6: Argo Events Installation**

Install Argo Events components:
- EventBus (Jetstream or NATS)
- Event controller
- Sensor controller

**Step 7: Automation Credential Creation**

Create credentials for cross-system integration:
- ArgoCD API token for Argo Workflows
- ServiceAccount for workflow execution

**Step 8: Root Application Creation**

Create the Root Application that defines the GitOps handoff:
- Points to platform manifests in Git
- Configured for auto-sync (or manual, based on policy)
- Defines the entry point for declarative management

**Step 9: Orchestration Workflow Trigger**

Submit the platform-bootstrap workflow:
- Passes configuration parameters
- Initiates Phase 2 (Orchestration)

---

### Outputs

- Operational ArgoCD instance
- Operational Argo Workflows controller
- Operational Argo Events system
- Running platform-bootstrap workflow

---

### Transition Criteria

Proceed to Phase 2 when:
- All bootstrap components report Ready
- Root Application created
- Platform-bootstrap workflow submitted

---

### Failure Handling

If bootstrap fails:
- Report failure point and diagnostics
- Do not proceed to Phase 2
- Support re-execution (idempotent)

---

## 6.3 Phase 2: Orchestration (DAG Execution)

### Purpose

Execute the platform deployment DAG, deploying all applications in correct
dependency order with health verification between nodes.

---

### Pre-Conditions

- Phase 1 completed successfully
- Argo Workflows operational
- ArgoCD operational
- DAG specification available

---

### Execution Model

The orchestration workflow:

1. **Receives** the platform DAG specification
2. **Computes** topological order of nodes
3. **Groups** nodes into execution waves
4. **Iterates** through waves sequentially:
   - Executes all nodes in current wave (parallel where possible)
   - Waits for all nodes to complete
   - Verifies health status
   - Proceeds only if all nodes Healthy
5. **Reports** final status

---

### Per-Node Execution

For each node in the DAG:

1. **Sync Application**: Invoke ArgoCD sync for the Application
2. **Wait for Sync**: Wait for sync operation to complete
3. **Verify Health**: Query Application health status
4. **Output Status**: Record health for downstream dependencies

---

### Health Verification

Health verification occurs after each wave:

| Status | Behavior |
|--------|----------|
| Healthy | Proceed to next wave |
| Progressing | Wait with timeout |
| Degraded | Halt and report |
| Failed | Halt and report |
| Unknown | Treat as failure |

---

### Timeout Handling

Each node has configurable timeouts:

| Timeout Type | Purpose |
|--------------|---------|
| Sync timeout | Maximum time for ArgoCD sync operation |
| Health timeout | Maximum time waiting for Healthy status |
| Overall timeout | Maximum time for entire workflow |

When timeout is exceeded:
- Node is marked as failed
- Dependent nodes are skipped
- Workflow reports partial completion

---

### Outputs

- Workflow status (Succeeded, Failed, Partial)
- Per-node execution results
- Health status at completion
- Execution logs

---

### Transition Criteria

Proceed to Phase 3 when:
- All DAG nodes completed successfully
- All Applications report Healthy
- Workflow reports Succeeded

---

### Failure Handling

If orchestration fails:
- Report failed node and diagnostics
- Preserve workflow state for resume
- Support resumption from failure point

---

## 6.4 Phase 3: Steady-State (Day 2+)

### Purpose

Maintain the deployed platform through continuous reconciliation, enabling
GitOps-driven changes and environment promotions.

---

### Characteristics

Phase 3 is the **normal operating mode**. The platform remains in this phase
indefinitely unless teardown is initiated.

---

### ArgoCD Behavior

In steady-state, ArgoCD:

- Continuously reconciles Application state
- Detects drift between Git and cluster
- Corrects drift through auto-sync (if enabled)
- Reports health and sync status
- Triggers alerts on degradation

---

### Argo Events Behavior

Event-driven automation handles:

- Git webhook triggers for deployment updates
- Scheduled triggers for maintenance tasks
- Manual triggers for on-demand operations

---

### Kargo Behavior

Environment promotion:

- Monitors Warehouses for new artifacts
- Creates Freight for promotable changes
- Promotes through Stages (dev → staging → prod)
- Executes verification at each Stage
- Enforces soak times between environments

---

### Argo Rollouts Behavior

Progressive delivery for workloads:

- Canary deployments with traffic shifting
- Blue-green deployments with instant cutover
- Analysis runs for automated rollback decisions

---

### Health Monitoring

Continuous health verification:

- Prometheus metrics for Application health
- Alerts for Degraded or Failed status
- Dashboard visibility into platform state

---

### Human Intervention Points

In steady-state, human intervention MAY be required for:

- Policy changes (RBAC, network policies)
- Significant upgrades (Kubernetes version)
- Disaster recovery scenarios
- Manual promotion approvals (if configured)

---

## 6.5 Phase 4: Teardown

### Purpose

Gracefully remove the platform from the cluster, ensuring no orphaned
resources remain.

---

### Pre-Conditions

- Platform in steady-state (Phase 3)
- Teardown explicitly requested
- Confirmation of data handling policy

---

### Execution Model

Teardown executes in **reverse dependency order**:

1. **Reverse DAG**: Compute reverse topological order
2. **Stop promotions**: Disable Kargo promotions
3. **Delete Applications**: Remove in reverse order
4. **Verify deletion**: Confirm resources removed
5. **Remove orchestration**: Delete Argo components
6. **Clean namespaces**: Remove platform namespaces

---

### Dependency Reversal

If deployment order was: A → B → C

Teardown order is: C → B → A

A resource MUST NOT be removed while dependents exist.

---

### Deletion Verification

For each deleted Application:

1. **Delete Application resource**: Remove from ArgoCD
2. **Wait for cascade**: Allow cascading delete to complete
3. **Verify absence**: Confirm managed resources removed
4. **Report orphans**: Identify any remaining resources

---

### PersistentVolume Handling

Storage cleanup requires explicit policy:

| Policy | Behavior |
|--------|----------|
| Delete | Remove PVCs and allow PV reclaim |
| Retain | Leave PVCs for data preservation |
| Snapshot | Create snapshots before deletion |

Default policy SHOULD be Retain to prevent accidental data loss.

---

### Orchestration Primitive Removal

After all Applications are removed:

1. Remove Argo Events components
2. Remove Argo Workflows controller
3. Remove ClusterWorkflowTemplates
4. Remove ArgoCD
5. Remove CRDs (optional, may affect other clusters)

---

### Outputs

- Teardown status (Complete, Partial, Failed)
- List of removed resources
- List of retained resources (if any)
- Orphan report

---

### Failure Handling

If teardown fails:
- Report blocking resources
- Provide manual cleanup guidance
- Support retry from failure point

---

## 6.6 Recovery Procedures

### Partial Deployment Recovery

When orchestration fails partway:

1. **Identify failure point**: Review workflow status
2. **Diagnose root cause**: Check failed Application
3. **Fix underlying issue**: Correct configuration or resources
4. **Resume workflow**: Restart from failed node

Argo Workflows supports workflow resume, preserving completed node state.

---

### Application Recovery

When individual Application is degraded:

1. **Check ArgoCD status**: Review sync and health
2. **Review events**: Check Application events
3. **Manual sync**: Trigger sync if auto-sync disabled
4. **Rollback if needed**: Revert to previous revision

---

### Cluster Recovery

After cluster loss:

1. **Provision new cluster**: Create replacement cluster
2. **Run executor deploy**: Execute from Phase 0
3. **Verify restoration**: Compare to expected state
4. **Restore data**: Apply backup restoration (if applicable)

The platform is fully reconstructable from:
- Git repositories (configuration)
- Container registries (images)
- External backup systems (data)

---

### Emergency Procedures

For critical failures:

**Force sync all Applications**:
Trigger immediate sync of all Applications, bypassing normal reconciliation
intervals.

**Restart operators**:
Delete operator pods to trigger restart and re-reconciliation.

**Manual resource cleanup**:
Directly delete stuck resources blocking deployment.

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← 5. Orchestration Mechanics](./05-orchestration-mechanics.md) | [Table of Contents](./00-index.md#table-of-contents) | [7. Executor Specification →](./07-executor-specification.md) |

---

*End of Section 6*
