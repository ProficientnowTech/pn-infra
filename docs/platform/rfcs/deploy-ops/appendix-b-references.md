```
RFC-DEPLOY-0001                                           Appendix B
Category: Standards Track                              References
```

# Appendix B: References

[← Previous: Glossary and Indexes](./appendix-a-glossary.md) | [Index](./00-index.md#table-of-contents)

---

This appendix lists all references cited in or relevant to this RFC.

---

## B.1 Normative References

The following references are essential to understanding and implementing
this specification.

---

### RFC Standards

[RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement
Levels", BCP 14, RFC 2119, March 1997.
<https://datatracker.ietf.org/doc/html/rfc2119>

[RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key
Words", BCP 14, RFC 8174, May 2017.
<https://datatracker.ietf.org/doc/html/rfc8174>

---

### Kubernetes Specifications

[K8S-API] Kubernetes Authors, "Kubernetes API Conventions", Kubernetes
Documentation.
<https://kubernetes.io/docs/reference/using-api/api-concepts/>

[K8S-HEALTH] Kubernetes Authors, "Configure Liveness, Readiness and Startup
Probes", Kubernetes Documentation.
<https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/>

---

### ArgoCD Specifications

[ARGOCD-APP] Argo Project, "Application Specification", ArgoCD Documentation.
<https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/>

[ARGOCD-SYNC] Argo Project, "Sync Waves and Resource Hooks", ArgoCD
Documentation.
<https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/>

[ARGOCD-HEALTH] Argo Project, "Resource Health", ArgoCD Documentation.
<https://argo-cd.readthedocs.io/en/stable/operator-manual/health/>

---

### Argo Workflows Specifications

[ARGO-WF-SPEC] Argo Project, "Workflow Specification", Argo Workflows
Documentation.
<https://argoproj.github.io/argo-workflows/workflow-concepts/>

[ARGO-WF-DAG] Argo Project, "DAG Templates", Argo Workflows Documentation.
<https://argoproj.github.io/argo-workflows/walk-through/dag/>

---

## B.2 Technology Documentation

The following references provide documentation for technologies specified
in this architecture.

---

### Argo Project

[ARGOCD] Argo Project, "Argo CD - Declarative GitOps CD for Kubernetes".
<https://argo-cd.readthedocs.io/>

[ARGO-WORKFLOWS] Argo Project, "Argo Workflows - Container-native Workflow
Engine".
<https://argoproj.github.io/argo-workflows/>

[ARGO-EVENTS] Argo Project, "Argo Events - Event-driven Workflow Automation".
<https://argoproj.github.io/argo-events/>

[ARGO-ROLLOUTS] Argo Project, "Argo Rollouts - Progressive Delivery Controller".
<https://argoproj.github.io/argo-rollouts/>

---

### Kargo

[KARGO] Akuity, "Kargo - GitOps Continuous Promotion".
<https://kargo.io/>

[KARGO-DOCS] Akuity, "Kargo Documentation".
<https://docs.kargo.io/>

---

### Ansible

[ANSIBLE] Red Hat, "Ansible Documentation".
<https://docs.ansible.com/>

[ANSIBLE-K8S] Red Hat, "kubernetes.core Ansible Collection".
<https://docs.ansible.com/ansible/latest/collections/kubernetes/core/>

---

### Helm

[HELM] CNCF, "Helm - The Kubernetes Package Manager".
<https://helm.sh/>

[HELM-HOOKS] CNCF, "Chart Hooks", Helm Documentation.
<https://helm.sh/docs/topics/charts_hooks/>

---

## B.3 Informative References

The following references provide context and background for architectural
decisions.

---

### ArgoCD Feature Requests

[ARGOCD-7437] Argo Project, "Feature Request: Application Dependencies",
GitHub Issue #7437.
<https://github.com/argoproj/argo-cd/issues/7437>

This issue documents the community request for native cross-Application
dependency support. It has 280+ reactions and significant discussion.

---

### CNOE Benchmarks

[CNOE-BENCH] Cloud Native Operational Excellence, "ArgoCD at Scale Benchmarks".
<https://cnoe.io/>

Documents ArgoCD performance at 50,000+ Applications across 500 clusters.

---

### GitOps Principles

[GITOPS-PRINCIPLES] OpenGitOps, "GitOps Principles".
<https://opengitops.dev/>

Defines the four principles of GitOps:
1. Declarative
2. Versioned and Immutable
3. Pulled Automatically
4. Continuously Reconciled

---

### Platform Engineering

[PLATFORM-ENG] Team Topologies, "What is Platform Engineering?".
<https://platformengineering.org/>

Background on platform engineering practices and patterns.

---

## B.4 Internal References

The following internal documents are referenced by or related to this RFC.

---

### Platform Documentation

[APP-DEPS] Platform Engineering, "Application Dependencies Matrix",
Internal Documentation.
`docs/platform/platform-status/APP-DEPENDENCIES.md`

Documents the dependency relationships between all platform applications.

---

### Research Documents

[DEPLOY-RESEARCH] Platform Engineering, "Deterministic Platform Deployment
Research", Internal Documentation.
`docs/research/deterministic_platform_deployment.md`

Initial research document exploring deployment orchestration patterns.

---

### Related RFCs

[RFC-SECOPS] Platform Engineering, "RFC-SECOPS-0001: A GitOps-Native,
Vault-First Secret Management Architecture", Internal RFC.
`docs/platform/rfcs/secret-ops/`

Defines the secret management architecture that this deployment system
must integrate with.

---

## B.5 Further Reading

The following resources provide additional context for readers seeking
deeper understanding.

---

### GitOps and ArgoCD

Chou, J. and Salituro, J. "GitOps and Kubernetes", O'Reilly Media, 2021.

Argo Project, "Argo CD Best Practices", ArgoCD Documentation.
<https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/>

---

### Kubernetes Patterns

Burns, B. et al. "Kubernetes Patterns", O'Reilly Media, 2019.

Burns, B. et al. "Designing Distributed Systems", O'Reilly Media, 2018.

---

### Platform Engineering

Skelton, M. and Pais, M. "Team Topologies", IT Revolution Press, 2019.

Forsgren, N. et al. "Accelerate", IT Revolution Press, 2018.

---

### Workflow Orchestration

"Temporal Documentation", Temporal Technologies.
<https://docs.temporal.io/>

"Airflow Documentation", Apache Software Foundation.
<https://airflow.apache.org/docs/>

---

## B.6 Acknowledgments

This RFC builds upon:

- The Argo Project and its maintainers
- The Kargo project and Akuity team
- The Ansible community and Red Hat
- The Kubernetes community and CNCF
- The GitOps community and OpenGitOps working group
- Internal platform engineering team discussions and learnings

---

## Document Navigation

| Previous | Index |
|----------|-------|
| [← Appendix A: Glossary](./appendix-a-glossary.md) | [Table of Contents](./00-index.md#table-of-contents) |

---

*End of Appendix B*

---

*End of RFC-DEPLOY-0001*
