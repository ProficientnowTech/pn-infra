```
RFC-DEPLOY-0001                                              Section 7
Category: Standards Track                     Executor Specification
```

# 7. Executor Specification

[← Previous: Lifecycle Management](./06-lifecycle-management.md) | [Index](./00-index.md#table-of-contents) | [Next: Design Rationale →](./08-rationale.md)

---

This section defines the **containerized executor** interface: how it is
invoked, what inputs it accepts, what outputs it produces, and what guarantees
it provides.

---

## 7.1 Executor Contract

### Definition

The executor is a **containerized component** that provides a unified interface
for platform lifecycle operations. It can be pulled from a container registry,
configured through environment and mounted files, and invoked with specific
actions.

---

### Container Image Specification

The executor MUST be packaged as a container image that:

- Is published to a container registry accessible to the deployment context
- Contains all dependencies required for execution
- Does not require network access during execution (air-gap capable)
- Supports multiple architectures (at minimum: amd64, arm64)

---

### Entry Point Interface

The executor accepts an **action** as the primary command argument:

```
executor <action> [options]
```

Where `<action>` is one of:
- `deploy` — Execute platform deployment
- `validate` — Verify platform health
- `teardown` — Execute platform removal

---

### Environment Variables

Configuration is provided through environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `KUBECONFIG_DATA` | Yes* | Base64-encoded kubeconfig content |
| `KUBECONFIG_PATH` | Yes* | Path to mounted kubeconfig file |
| `ENVIRONMENT` | Yes | Target environment (development, staging, production) |
| `TARGET_SCOPE` | No | Deployment scope (platform, stack:<name>, app:<name>) |
| `DRY_RUN` | No | If "true", validate without executing |
| `LOG_LEVEL` | No | Logging verbosity (debug, info, warn, error) |
| `LOG_FORMAT` | No | Output format (text, json) |

*One of `KUBECONFIG_DATA` or `KUBECONFIG_PATH` MUST be provided.

---

### Mounted Configuration

Additional configuration through mounted files:

| Mount Path | Description |
|------------|-------------|
| `/config/environment.yaml` | Environment-specific configuration |
| `/secrets/` | Directory containing credential files |
| `/config/dag.yaml` | Optional custom DAG specification |

---

### Exit Codes

The executor MUST exit with defined status codes:

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | Action completed successfully |
| 1 | Failure | Action failed; see logs for details |
| 2 | Partial | Action partially completed; some components failed |
| 3 | Invalid | Invalid configuration or arguments |
| 4 | Timeout | Action exceeded maximum execution time |

---

## 7.2 Action Definitions

### Deploy Action

**Purpose**: Execute platform deployment from current state to target state.

**Behavior**:
1. Validate configuration and prerequisites
2. Determine current platform state
3. Execute bootstrap if orchestration primitives absent
4. Execute orchestration workflow
5. Verify final platform health
6. Report completion status

**Inputs**:

| Input | Source | Description |
|-------|--------|-------------|
| Kubeconfig | Environment/Mount | Cluster access credentials |
| Environment config | Mount | Target environment settings |
| Target scope | Environment | What to deploy (default: full platform) |

**Outputs**:

| Output | Format | Description |
|--------|--------|-------------|
| Exit code | Integer | 0=success, 1=failure, 2=partial |
| Status report | Structured | Per-component deployment status |
| Health report | Structured | Final health state |
| Logs | Text/JSON | Execution trace |

**Idempotency Guarantee**:
Executing deploy multiple times with identical inputs MUST produce identical
platform state. Resources that exist and match desired state MUST NOT be
recreated or modified.

---

### Validate Action

**Purpose**: Verify platform health without making changes.

**Behavior**:
1. Connect to cluster
2. Query ArgoCD Application status
3. Verify health for all Applications
4. Check resource health for critical components
5. Report validation results

**Inputs**:

| Input | Source | Description |
|-------|--------|-------------|
| Kubeconfig | Environment/Mount | Cluster access credentials |
| Target scope | Environment | What to validate (default: full platform) |
| Health criteria | Mount | Optional custom health definitions |

**Outputs**:

| Output | Format | Description |
|--------|--------|-------------|
| Exit code | Integer | 0=healthy, 1=unhealthy, 2=degraded |
| Health report | Structured | Per-component health status |
| Compliance report | Structured | Policy compliance status |
| Logs | Text/JSON | Validation trace |

**Read-Only Guarantee**:
Validate MUST NOT modify any cluster state. It is safe to run in production
at any time.

---

### Teardown Action

**Purpose**: Remove platform from cluster.

**Behavior**:
1. Validate configuration and prerequisites
2. Verify teardown is intended (confirmation mechanism)
3. Execute reverse dependency order deletion
4. Verify resource removal
5. Remove orchestration primitives
6. Report completion status

**Inputs**:

| Input | Source | Description |
|-------|--------|-------------|
| Kubeconfig | Environment/Mount | Cluster access credentials |
| Target scope | Environment | What to teardown (default: full platform) |
| PV policy | Environment | PersistentVolume handling (delete/retain) |
| Confirmation | Environment | Explicit confirmation token |

**Outputs**:

| Output | Format | Description |
|--------|--------|-------------|
| Exit code | Integer | 0=clean, 1=failure, 2=orphans |
| Removal report | Structured | Per-component removal status |
| Orphan report | Structured | Resources not removed |
| Logs | Text/JSON | Teardown trace |

**Safety Guarantee**:
Teardown requires explicit confirmation. It MUST NOT execute with default
values alone.

---

## 7.3 Idempotency Guarantees

### Definition

An operation is **idempotent** if executing it multiple times with identical
inputs produces identical results.

---

### Deploy Idempotency

The deploy action MUST satisfy:

- **Convergent**: Running deploy moves the cluster toward target state
- **Stable**: Running deploy on an already-deployed platform produces no changes
- **Deterministic**: Same inputs always produce same outputs

**What this means**:

If the platform is already deployed and healthy:
- Running deploy again MUST NOT create new resources
- Running deploy again MUST NOT restart running workloads
- Running deploy again MUST exit with success

If the platform is partially deployed:
- Running deploy again MUST continue from current state
- Running deploy again MUST NOT duplicate completed work

---

### Validate Idempotency

The validate action is inherently idempotent as it makes no changes.

Running validate multiple times MUST:
- Produce consistent results for stable platform state
- Reflect actual state changes if platform changed between runs

---

### Teardown Idempotency

The teardown action MUST satisfy:

- Running teardown on removed platform MUST succeed (nothing to do)
- Running teardown on partial platform MUST remove remaining resources
- Running teardown multiple times MUST be safe

---

### State Requirements

Idempotency requires:

- **No implicit state**: The executor MUST NOT cache state between invocations
- **Cluster as source of truth**: All state decisions based on cluster queries
- **Declarative comparison**: Desired state compared to actual state

---

## 7.4 Configuration Interface

### Environment Configuration File

The environment configuration file defines target-specific settings:

**Required Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `name` | String | Environment identifier |
| `domain` | String | Base domain for ingress |
| `gitRepository` | String | Platform manifests repository URL |
| `gitRevision` | String | Branch, tag, or commit |

**Optional Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `clusterName` | String | Kubernetes cluster identifier |
| `argocdNamespace` | String | Namespace for ArgoCD (default: argocd) |
| `workflowsNamespace` | String | Namespace for Argo Workflows |
| `timeouts.sync` | Duration | ArgoCD sync timeout |
| `timeouts.health` | Duration | Health verification timeout |
| `retries.maxAttempts` | Integer | Maximum retry attempts |
| `retries.backoff` | Duration | Retry backoff interval |

---

### Credentials

Credentials are provided through:

1. **Kubeconfig**: Cluster access (required)
2. **Git credentials**: Repository access (if private)
3. **Registry credentials**: Image pull secrets (if private)
4. **ArgoCD token**: API access for validation (generated during bootstrap)

Credentials MUST NOT be passed through environment variables in plain text.
Use mounted secrets or base64-encoded values.

---

### DAG Customization

The default platform DAG may be customized:

- **Subset deployment**: Deploy only specific stacks
- **Dependency override**: Modify dependency relationships
- **Timeout override**: Adjust per-node timeouts

Custom DAG specifications are validated before execution.

---

## 7.5 Observability

### Structured Logging

The executor produces structured logs in configurable format:

**JSON Format** (default for automation):

```
{"timestamp":"...", "level":"info", "action":"deploy", "phase":"bootstrap", "component":"argocd", "message":"..."}
```

**Text Format** (for human reading):

```
2026-01-07T10:30:00Z INFO [deploy/bootstrap/argocd] Installing ArgoCD...
```

---

### Log Levels

| Level | Use |
|-------|-----|
| error | Failures requiring attention |
| warn | Potential issues, degraded state |
| info | Normal operation progress |
| debug | Detailed execution trace |

---

### Metric Emission

The executor emits metrics for monitoring integration:

| Metric | Type | Description |
|--------|------|-------------|
| `executor_action_duration_seconds` | Histogram | Action execution time |
| `executor_action_status` | Gauge | Current action status |
| `executor_component_health` | Gauge | Per-component health |
| `executor_errors_total` | Counter | Error count by type |

Metrics are exposed through standard Prometheus format.

---

### Trace Correlation

For distributed tracing integration:

- The executor accepts trace context through environment variables
- All operations are annotated with trace and span IDs
- Traces propagate to Argo Workflows and ArgoCD

Trace headers:
- `TRACE_ID`: Parent trace identifier
- `SPAN_ID`: Parent span identifier

---

### Status Reporting

The executor outputs a structured status report on completion:

**Report Contents**:

| Section | Description |
|---------|-------------|
| Summary | Overall status, duration, action performed |
| Components | Per-component status and health |
| Failures | Failed components with diagnostics |
| Metrics | Execution statistics |
| Recommendations | Suggested actions for failures |

---

### Integration Points

The executor integrates with:

- **Prometheus**: Metric scraping
- **Loki/Elasticsearch**: Log aggregation
- **Jaeger/Tempo**: Distributed tracing
- **AlertManager**: Failure notifications

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← 6. Lifecycle Management](./06-lifecycle-management.md) | [Table of Contents](./00-index.md#table-of-contents) | [8. Design Rationale →](./08-rationale.md) |

---

*End of Section 7*
