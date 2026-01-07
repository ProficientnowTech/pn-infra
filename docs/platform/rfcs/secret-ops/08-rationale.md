```
RFC-SECOPS-0001                                              Section 8
Category: Standards Track                          Design Rationale
```

# 8. Design Rationale

[← Previous: Security](./07-security.md) | [Index](./00-index.md#table-of-contents) | [Next: Evolution →](./09-evolution.md)

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

All alternatives discussed here were **seriously considered**.

---

## 8.2 Sealed Secrets–First Architectures

### Description

Secrets are encrypted using a cluster-specific public key and committed to
Git as Kubernetes Secret objects.

At runtime:

- a controller decrypts them,
- Kubernetes becomes the primary secret store.

---

### Why It Was Attractive

- Simple mental model
- Kubernetes-native
- No external dependency
- Easy early adoption

---

### Why It Was Rejected

1. **Cluster-Coupled Encryption**
   - Secrets are bound to a single cluster
   - Disaster recovery requires resealing
   - Multi-cluster reuse is fragile

2. **Kubernetes Becomes the Authority**
   - Violates the invariant that Kubernetes MUST be a consumer
   - No native rotation or TTL handling

3. **Rotation Requires Git Changes**
   - Forces runtime operations into Git
   - Breaks automation guarantees

---

### Conclusion

Sealed Secrets is suitable for **small or static systems**.
It does not meet the lifecycle, rotation, or scalability requirements of this
platform.

---

## 8.3 argocd-vault-plugin–Centric Designs

### Description

Secrets are pulled directly from a runtime authority and injected into
manifests during GitOps render time.

---

### Why It Was Attractive

- No secrets in Git
- Direct Vault integration
- Minimal moving parts

---

### Why It Was Rejected

1. **Render-Time Only**
   - Secrets are resolved once
   - No native runtime refresh

2. **ArgoCD Becomes a Privileged Secret Broker**
   - Enlarges blast radius
   - Violates separation of duties

3. **Rotation Is Indirect and Implicit**
   - Requires resyncs
   - Hard to audit

---

### Conclusion

This approach works for **simple workloads**, but does not support:

- robust rotation,
- explicit authority boundaries,
- or long-lived operational safety.

---

## 8.4 CI/CD–Driven Secret Injection

### Description

CI pipelines fetch secrets from external stores and inject them into the
cluster during deployment.

---

### Why It Was Attractive

- Familiar workflow
- Easy integration with SaaS providers
- Minimal cluster-side complexity

---

### Why It Was Rejected

1. **CI Becomes a Hidden Control Plane**
2. **Cluster Is Not Rebuildable from Git**
3. **Auditability Is Split Across Systems**
4. **Operational Correctness Depends on Pipeline Health**

---

### Conclusion

CI/CD is a delivery mechanism, **NOT a source of truth**.
Using it as one violates GitOps principles.

---

## 8.5 GitHub Environments as Source of Truth

### Description

Secrets are stored in GitHub Environments and synchronized into the cluster.

---

### Why It Was Attractive

- Managed secret storage
- Good UX
- Easy rotation

---

### Why It Was Rejected

1. **External System Dependency**
2. **State Lives Outside Git**
3. **Platform Is Not Self-Contained**
4. **Disaster Recovery Requires Manual Reconciliation**

---

### Conclusion

This approach optimizes convenience at the cost of **reproducibility and
independence**.

---

## 8.6 "Just Use Vault" (No GitOps Bootstrap)

### Description

Vault is manually initialized and populated.
GitOps assumes Vault always exists.

---

### Why It Was Attractive

- Clean runtime model
- No bootstrap secrets

---

### Why It Was Rejected

1. **Bootstrap Paradox Ignored**
2. **Human Dependency at Initialization**
3. **No Deterministic Recovery**

---

### Conclusion

Vault is a **runtime authority**, not a bootstrap solution.

---

## 8.7 Kubernetes Secrets as the Authority

### Description

Secrets are created and managed directly in Kubernetes.

---

### Why It Was Attractive

- Native API
- Simple consumption

---

### Why It Was Rejected

1. **No Rotation Semantics**
2. **Weak Access Control Model**
3. **Poor Auditability**
4. **Secrets Become Deployment Artifacts**

---

### Conclusion

Kubernetes Secrets are **delivery mechanisms**, not lifecycle managers.

---

## 8.8 Bash-Driven Orchestration

### Description

Scripts coordinate secret generation, encryption, and deployment.

---

### Why It Was Attractive

- Fast to implement
- Flexible
- No new infrastructure

---

### Why It Was Rejected

1. **Implicit State**
2. **Non-Reproducibility**
3. **Opaque Failures**
4. **Human-Coupled Execution**

---

### Conclusion

Scripts do not scale as control planes.
They inevitably become undocumented infrastructure.

---

## 8.9 Why Incremental Improvements Were Insufficient

Each rejected approach failed for the same reason:

> **They attempted to fix symptoms without correcting authority and lifecycle
> boundaries.**

The chosen architecture succeeds because it:

- models bootstrap explicitly,
- assigns single authority at every phase,
- and treats rotation as a system responsibility.

---

## 8.10 Summary

The final architecture is not the simplest possible solution.
It is the **simplest solution that satisfies all invariants simultaneously**.

Every rejected alternative violated at least one invariant defined in
[Section 2](./02-requirements.md).

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← 7. Security](./07-security.md) | [Table of Contents](./00-index.md#table-of-contents) | [9. Evolution →](./09-evolution.md) |

---

*End of Section 8*
