```
                                                            RFC-DEPLOY-0001
                                                            Category: Standards Track
                                                            Status: Draft
                                                            Platform Engineering
                                                            January 2026
```

# A GitOps-Native, Argo-First Platform Deployment Orchestration Architecture

---

## Status of This Memo

This document specifies a standards-track architecture for deterministic platform
deployment orchestration within Kubernetes-based infrastructure. Distribution of
this memo is unlimited within the organization and to authorized external reviewers.

This document is a DRAFT and is subject to change based on review feedback.

---

## Abstract

This Request for Comments (RFC) defines a comprehensive, GitOps-native,
Argo-first architecture for platform deployment orchestration in Kubernetes
environments. The architecture addresses the fundamental challenges of deploying
complex, interdependent platform stacks consisting of 40+ applications with
intricate dependency relationships.

The system establishes a phase-driven model where deployment progresses through
well-defined stages: bootstrap, orchestration, steady-state, and teardown. Each
phase has explicit authority boundaries and deterministic transition criteria.
The architecture eliminates human-in-the-loop operations for nominal deployments
through DAG-based dependency resolution using Argo Workflows, replacing
error-prone bash scripts and race-condition-susceptible PreSync hooks.

The system treats deployment ordering as a first-class concern with defined
dependency graphs, health propagation contracts, and explicit failure semantics.
A containerized executor provides a unified interface for deploy, validate, and
teardown actions, guaranteeing idempotency across all operations.

---

## Copyright Notice

Copyright (c) 2026 Platform Engineering. All rights reserved.

---

## Document Information

| Attribute            | Value                                              |
| -------------------- | -------------------------------------------------- |
| RFC Number           | RFC-DEPLOY-0001                                    |
| Status               | Draft                                              |
| Version              | 1.0                                                |
| Created              | 2026-01-07                                         |
| Last Updated         | 2026-01-07                                         |
| Authors              | Shaik Noorullah Shareef (Platform Engineering)     |
| Reviewers            | Infrastructure, SRE, Security (TBD)                |
| Application Domain   | Platform Engineering, GitOps, Deployment           |

---

## Intended Audience

This document is written for:

- Platform & Infrastructure Engineers
- Cloud / Kubernetes / GitOps Architects
- Site Reliability Engineers
- Security & Compliance Reviewers
- Broader Engineering Organization
- Open-source contributors and external auditors

No prior knowledge of the internal system is assumed.

---

## Conventions and Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in
[BCP 14](https://www.rfc-editor.org/info/bcp14)
[[RFC2119](https://datatracker.ietf.org/doc/html/rfc2119)]
[[RFC8174](https://datatracker.ietf.org/doc/html/rfc8174)]
when, and only when, they appear in all capitals, as shown here.

---

## Table of Contents

### Part 1: Foundation

1. [Introduction and Motivation](./01-introduction.md)
   - 1.1 Background and Context
   - 1.2 The Initial System (Pre-Architecture State)
   - 1.3 Operational Shortcomings
   - 1.4 The Cost of Hook-Driven Orchestration
   - 1.5 Why Incremental Fixes Failed
   - 1.6 Why Dedicated Orchestration Became Necessary

2. [Requirements and Invariants](./02-requirements.md)
   - 2.1 Core Problem Restatement
   - 2.2 Design Goals
   - 2.3 Non-Goals
   - 2.4 Architectural Invariants
   - 2.5 Operational Philosophy
   - 2.6 Success Criteria

### Part 2: Architecture

3. [System Architecture](./03-architecture.md)
   - 3.1 Architectural Overview
   - 3.2 Phase Model Overview
   - 3.3 Authority Domains
   - 3.4 Trust Boundaries
   - 3.5 High-Level Control Flow
   - 3.6 Failure Domains and Recovery

4. [System Components](./04-components.md)
   - 4.1 Component Taxonomy
   - 4.2 Bootstrap Controller
   - 4.3 Argo Workflows DAG Orchestrator
   - 4.4 ArgoCD Application Controller
   - 4.5 Containerized Executor
   - 4.6 Argo Events Trigger System
   - 4.7 Kargo Promotion Controller
   - 4.8 Health Propagation System
   - 4.9 Phase-to-Component Mapping
   - 4.10 Failure and Recovery Scenarios

5. [Orchestration Mechanics](./05-orchestration-mechanics.md)
   - 5.1 Dependency DAG Specification
   - 5.2 Platform Dependency Layers
   - 5.3 Execution Semantics
   - 5.4 Sync Wave Consolidation
   - 5.5 Health Propagation Contracts

### Part 3: Operations

6. [Lifecycle Management](./06-lifecycle-management.md)
   - 6.1 Phase 0: Pre-Bootstrap
   - 6.2 Phase 1: Bootstrap (Day 0-1)
   - 6.3 Phase 2: Orchestration (DAG Execution)
   - 6.4 Phase 3: Steady-State (Day 2+)
   - 6.5 Phase 4: Teardown
   - 6.6 Recovery Procedures

7. [Executor Specification](./07-executor-specification.md)
   - 7.1 Executor Contract
   - 7.2 Action Definitions
   - 7.3 Idempotency Guarantees
   - 7.4 Configuration Interface
   - 7.5 Observability

### Part 4: Rationale and Evolution

8. [Design Rationale](./08-rationale.md)
   - 8.1 Why This Section Exists
   - 8.2 Bash Scripts for Orchestration
   - 8.3 ArgoCD PreSync Hooks for Dependencies
   - 8.4 Sync Waves Only for All Ordering
   - 8.5 Custom Controller for Orchestration
   - 8.6 Tekton Pipelines for Orchestration
   - 8.7 Helm Hooks for Dependencies
   - 8.8 Script-Based Wait Loops
   - 8.9 Why Incremental Improvements Were Insufficient

9. [Future Considerations](./09-evolution.md)
   - 9.1 Design for Change
   - 9.2 Multi-Cluster Federation
   - 9.3 Scale Considerations
   - 9.4 Extensibility Points
   - 9.5 Integration Roadmap
   - 9.6 What Does Not Need to Change
   - 9.7 Anticipated Trade-offs and Limits

### Appendices

- [Appendix A: Glossary and Indexes](./appendix-a-glossary.md)
- [Appendix B: References](./appendix-b-references.md)

---

## Quick Navigation

| Section | Description | Audience |
|---------|-------------|----------|
| [1. Introduction](./01-introduction.md) | Problem space and motivation | All |
| [2. Requirements](./02-requirements.md) | Design constraints and invariants | All |
| [3. Architecture](./03-architecture.md) | Phase model and authority domains | Engineers, Architects |
| [4. Components](./04-components.md) | System building blocks | Engineers |
| [5. Orchestration](./05-orchestration-mechanics.md) | DAG modeling and execution | Engineers |
| [6. Lifecycle](./06-lifecycle-management.md) | Bootstrap, steady-state, teardown | Engineers, SRE |
| [7. Executor](./07-executor-specification.md) | Container interface specification | Engineers |
| [8. Rationale](./08-rationale.md) | Rejected alternatives | Architects |
| [9. Evolution](./09-evolution.md) | Future scalability | Architects |

---

## Reading Paths

**New to the Platform?**
Start with [Introduction](./01-introduction.md) → [Requirements](./02-requirements.md) → [Architecture](./03-architecture.md)

**Operators and SRE?**
Focus on [Introduction](./01-introduction.md) → [Requirements](./02-requirements.md) → [Orchestration](./05-orchestration-mechanics.md) → [Lifecycle](./06-lifecycle-management.md)

**Security Review?**
Read [Requirements](./02-requirements.md) → [Architecture](./03-architecture.md) → [Executor](./07-executor-specification.md)

**Understanding Design Decisions?**
Read [Requirements](./02-requirements.md) → [Rationale](./08-rationale.md) → [Evolution](./09-evolution.md)

---

*RFC-DEPLOY-0001 — Index*
