# Platform Application Dependency Diagram

This document contains Mermaid diagrams showing the dependency relationships between all 43 platform applications, organized by layers and categories for clarity.

---

## Complete Layered Architecture

This diagram shows the complete platform architecture in layers, from foundation to applications.

```mermaid
graph TB
    subgraph "Layer 0: Foundation"
        MetalLB[MetalLB Operator]
        CertManager[cert-manager]
        RookCeph[rook-ceph]
        SealedSecrets[sealed-secrets]
    end

    subgraph "Layer 1: Core Infrastructure"
        RookCluster[rook-ceph-cluster]
        MetalLBConfig[metallb-config]
        ExternalDNS[external-dns]
        CertConfig[cert-manager-config]
    end

    subgraph "Layer 2: Networking & Storage"
        IngressNginx[ingress-nginx]
        ZalandoPG[zalando-pg]
        RedisOp[redis-operator]
    end

    subgraph "Layer 3: Security & Identity"
        Vault[vault]
        Keycloak[keycloak]
        ExternalSecrets[external-secrets]
        Crossplane[crossplane]
    end

    subgraph "Layer 4: GitOps & Observability"
        ArgoCD[argocd-self]
        Prometheus[prometheus]
        Loki[loki]
        Tempo[tempo]
    end

    subgraph "Layer 5: Platform Services"
        Grafana[grafana]
        Harbor[harbor]
        Backstage[backstage]
        Temporal[temporal]
        Tekton[tekton-pipelines]
    end

    subgraph "Layer 6: Applications"
        Apps[All Other Apps]
    end

    %% Layer 0 → Layer 1
    MetalLB --> MetalLBConfig
    CertManager --> CertConfig
    RookCeph --> RookCluster

    %% Layer 1 → Layer 2
    RookCluster --> IngressNginx
    RookCluster --> ZalandoPG
    RookCluster --> RedisOp
    MetalLBConfig --> IngressNginx
    ExternalDNS --> IngressNginx

    %% Layer 2 → Layer 3
    RookCluster --> Vault
    RookCluster --> Keycloak
    IngressNginx --> Vault
    IngressNginx --> Keycloak
    CertManager --> Vault
    CertManager --> Keycloak
    Vault --> ExternalSecrets
    Vault --> Crossplane

    %% Layer 3 → Layer 4
    RookCluster --> ArgoCD
    RookCluster --> Prometheus
    RookCluster --> Loki
    RookCluster --> Tempo
    IngressNginx --> ArgoCD
    CertManager --> ArgoCD

    %% Layer 4 → Layer 5
    Prometheus --> Grafana
    Loki --> Grafana
    Tempo --> Grafana
    RookCluster --> Grafana
    RookCluster --> Harbor
    RookCluster --> Backstage
    RookCluster --> Temporal
    IngressNginx --> Grafana
    IngressNginx --> Harbor
    IngressNginx --> Backstage
    IngressNginx --> Temporal
    CertManager --> Grafana
    CertManager --> Harbor
    CertManager --> Backstage
    CertManager --> Temporal
    Keycloak --> Backstage
    ZalandoPG --> Temporal

    %% Layer 5 → Layer 6
    ArgoCD --> Apps
    Harbor --> Apps
    Prometheus --> Apps

    classDef foundation fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef core fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef network fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef security fill:#ffebee,stroke:#b71c1c,stroke-width:2px
    classDef observability fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef services fill:#fff9c4,stroke:#f57f17,stroke-width:2px

    class MetalLB,CertManager,RookCeph,SealedSecrets foundation
    class RookCluster,MetalLBConfig,ExternalDNS,CertConfig core
    class IngressNginx,ZalandoPG,RedisOp network
    class Vault,Keycloak,ExternalSecrets,Crossplane security
    class ArgoCD,Prometheus,Loki,Tempo observability
    class Grafana,Harbor,Backstage,Temporal,Tekton services
```

---

## Infrastructure Layer Dependencies

Shows only core infrastructure components and their relationships.

```mermaid
graph LR
    subgraph "Storage Foundation"
        RookCeph[rook-ceph<br/>Operator]
        RookCluster[rook-ceph-cluster<br/>Storage Backend]
        RookCeph --> RookCluster
    end

    subgraph "Network Foundation"
        MetalLB[MetalLB Operator]
        MetalLBConfig[metallb-config<br/>IP Pool]
        ExternalDNS[external-dns<br/>DNS Automation]
        IngressNginx[ingress-nginx<br/>HTTP/HTTPS Gateway]

        MetalLB --> MetalLBConfig
        MetalLBConfig --> IngressNginx
        ExternalDNS --> IngressNginx
    end

    subgraph "Security Foundation"
        CertManager[cert-manager<br/>TLS Certificates]
        SealedSecrets[sealed-secrets<br/>Encrypted Secrets]
        CertManager --> IngressNginx
    end

    RookCluster -.->|storage| IngressNginx
    RookCluster -.->|storage| ExternalDNS

    classDef storage fill:#e3f2fd,stroke:#1565c0,stroke-width:3px
    classDef network fill:#fff3e0,stroke:#ef6c00,stroke-width:3px
    classDef security fill:#fce4ec,stroke:#c2185b,stroke-width:3px

    class RookCeph,RookCluster storage
    class MetalLB,MetalLBConfig,ExternalDNS,IngressNginx network
    class CertManager,SealedSecrets security
```

---

## Database & Storage Layer

Shows all database operators and storage services.

```mermaid
graph TB
    RookCluster[rook-ceph-cluster<br/>Storage Backend]

    subgraph "Database Operators"
        ZalandoPG[zalando-pg<br/>PostgreSQL Operator]
        RedisOp[redis-operator<br/>Redis Operator]
        StrimziKafka[strimzi-kafka-operator<br/>Kafka Operator]
    end

    subgraph "Database Instances"
        TemporalDB[temporal-db<br/>3-node PostgreSQL]
        PlatformDB[platform-db-cluster<br/>5-node PostgreSQL]
        KeycloakDB[keycloak-postgresql<br/>Internal PostgreSQL]
        HarborDB[harbor-postgresql<br/>Internal PostgreSQL]
        PlatformKV[platform-kv<br/>Redis Cluster]
    end

    subgraph "Object Storage"
        CephRGW[Ceph RGW<br/>S3 Compatible]
    end

    RookCluster --> ZalandoPG
    RookCluster --> RedisOp
    RookCluster --> StrimziKafka
    RookCluster --> CephRGW

    ZalandoPG --> TemporalDB
    ZalandoPG --> PlatformDB
    RookCluster --> KeycloakDB
    RookCluster --> HarborDB
    RedisOp --> PlatformKV
    RookCluster --> PlatformKV

    TemporalDB -.->|used by| Temporal[temporal]
    KeycloakDB -.->|used by| Keycloak[keycloak]
    HarborDB -.->|used by| Harbor[harbor]
    CephRGW -.->|used by| Harbor

    classDef storage fill:#e8eaf6,stroke:#3f51b5,stroke-width:2px
    classDef operator fill:#fff9c4,stroke:#f57f17,stroke-width:2px
    classDef instance fill:#e0f2f1,stroke:#00695c,stroke-width:2px
    classDef object fill:#fce4ec,stroke:#c2185b,stroke-width:2px

    class RookCluster storage
    class ZalandoPG,RedisOp,StrimziKafka operator
    class TemporalDB,PlatformDB,KeycloakDB,HarborDB,PlatformKV instance
    class CephRGW object
```

---

## Security & Authentication Flow

Shows authentication and secrets management relationships.

```mermaid
graph TB
    subgraph "Secrets Management"
        SealedSecrets[sealed-secrets<br/>Git-stored Encrypted Secrets]
        Vault[vault<br/>HashiCorp Vault<br/>Central Secret Store]
        ExternalSecrets[external-secrets<br/>Vault → K8s Sync]

        Vault --> ExternalSecrets
    end

    subgraph "Identity & Access"
        Keycloak[keycloak<br/>SSO Provider<br/>OIDC/SAML]
        GitHub[GitHub<br/>OAuth Provider]

        GitHub --> Keycloak
    end

    subgraph "Infrastructure Provisioning"
        Crossplane[crossplane<br/>Infrastructure as Code]

        Vault -.->|token| Crossplane
    end

    subgraph "Applications Using Auth"
        Backstage[backstage<br/>✅ Keycloak OIDC]
        ArgoCD[argocd<br/>⏳ Dex + Keycloak]
        Grafana[grafana<br/>⏳ Keycloak OAuth]
        Harbor[harbor<br/>⏳ Keycloak OIDC]
        VaultUI[vault-ui<br/>⏳ Keycloak OIDC]
        Kargo[kargo<br/>⏳ Keycloak OIDC]
    end

    subgraph "Apps Using Sealed Secrets"
        BS_SS[backstage]
        Harbor_SS[harbor]
        Kargo_SS[kargo]
        Temporal_SS[temporal]
    end

    Keycloak -.->|auth| Backstage
    Keycloak -.->|planned| ArgoCD
    Keycloak -.->|planned| Grafana
    Keycloak -.->|planned| Harbor
    Keycloak -.->|planned| VaultUI
    Keycloak -.->|planned| Kargo

    SealedSecrets -.->|secrets| BS_SS
    SealedSecrets -.->|secrets| Harbor_SS
    SealedSecrets -.->|secrets| Kargo_SS
    SealedSecrets -.->|secrets| Temporal_SS

    ExternalSecrets -.->|planned migration| BS_SS
    ExternalSecrets -.->|planned migration| Harbor_SS

    classDef secrets fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef identity fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef infra fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    classDef authenticated fill:#c8e6c9,stroke:#388e3c,stroke-width:2px
    classDef planned fill:#ffecb3,stroke:#f57c00,stroke-width:2px,stroke-dasharray: 5 5

    class SealedSecrets,Vault,ExternalSecrets secrets
    class Keycloak,GitHub identity
    class Crossplane infra
    class Backstage authenticated
    class ArgoCD,Grafana,Harbor,VaultUI,Kargo planned
```

---

## Observability Stack

Shows monitoring, logging, and tracing relationships.

```mermaid
graph LR
    subgraph "Metrics Collection"
        Prometheus[prometheus<br/>Metrics Database]
        ServiceMonitors[ServiceMonitors<br/>43 apps]
    end

    subgraph "Logging"
        Loki[loki<br/>Log Aggregation]
        Promtail[promtail<br/>Log Shipper<br/>DaemonSet]
    end

    subgraph "Tracing"
        Tempo[tempo<br/>Distributed Traces]
    end

    subgraph "Visualization"
        Grafana[grafana<br/>Dashboards & Queries]
    end

    subgraph "Cost & Status"
        Kubecost[kubecost<br/>Cost Analysis]
        UptimeKuma[uptime-kuma<br/>Uptime Monitoring]
    end

    ServiceMonitors --> Prometheus
    Promtail --> Loki

    Prometheus --> Grafana
    Loki --> Grafana
    Tempo --> Grafana
    Prometheus --> Kubecost

    AllPods[All Application Pods] -.->|metrics| ServiceMonitors
    AllPods -.->|logs| Promtail
    AllPods -.->|traces| Tempo

    classDef metrics fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef logs fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef traces fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    classDef viz fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef cost fill:#ffebee,stroke:#c62828,stroke-width:2px

    class Prometheus,ServiceMonitors metrics
    class Loki,Promtail logs
    class Tempo traces
    class Grafana viz
    class Kubecost,UptimeKuma cost
```

---

## CI/CD Pipeline Architecture

Shows the complete CI/CD and deployment workflow.

```mermaid
graph TB
    subgraph "Source Control"
        Git[Git Repository<br/>GitHub]
    end

    subgraph "GitOps Controller"
        ArgoCD[argocd-self<br/>Continuous Deployment]
        ArgoConfig[argocd-config<br/>Ingress & Settings]
        ArgoCD --> ArgoConfig
    end

    subgraph "CI/CD Pipeline"
        TektonOp[tekton-operator<br/>Operator]
        TektonPipelines[tekton-pipelines<br/>Pipeline Engine]
        TektonDashboard[tekton-dashboard<br/>Web UI]
        TektonOp --> TektonPipelines
        TektonPipelines --> TektonDashboard
    end

    subgraph "Progressive Delivery"
        Kargo[kargo<br/>Promotion Workflows]
        ArgoRollouts[argo-rollouts<br/>Canary/Blue-Green]
    end

    subgraph "Container Registry"
        Harbor[harbor<br/>Image Registry<br/>Vulnerability Scanning]
    end

    subgraph "Artifact Registry"
        Verdaccio[verdaccio<br/>NPM Registry]
    end

    subgraph "Developer Portal"
        Backstage[backstage<br/>Service Catalog<br/>Self-Service]
    end

    Git --> ArgoCD
    Git --> TektonPipelines
    TektonPipelines --> Harbor
    Harbor --> ArgoCD
    ArgoCD --> Kargo
    Kargo --> ArgoCD
    ArgoRollouts -.->|deployment strategy| ArgoCD
    Backstage -.->|service discovery| ArgoCD

    classDef source fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef gitops fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef cicd fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef progressive fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    classDef registry fill:#ffebee,stroke:#c62828,stroke-width:2px
    classDef portal fill:#e0f2f1,stroke:#00695c,stroke-width:2px

    class Git source
    class ArgoCD,ArgoConfig gitops
    class TektonOp,TektonPipelines,TektonDashboard cicd
    class Kargo,ArgoRollouts progressive
    class Harbor,Verdaccio registry
    class Backstage portal
```

---

## Application Services

Shows higher-level application services and their dependencies.

```mermaid
graph TB
    subgraph "Workflow & Orchestration"
        Temporal[temporal<br/>Workflow Engine]
        TemporalUI[temporal-ui<br/>Web Interface]
        TemporalDB[temporal-db<br/>PostgreSQL 3-node]

        TemporalDB --> Temporal
        Temporal --> TemporalUI
    end

    subgraph "Virtualization"
        KubeVirt[kubevirt<br/>VM Management]
        KubeVirtManager[kubevirt-manager<br/>Web UI]
        CDI[CDI<br/>Disk Import]

        KubeVirt --> KubeVirtManager
        CDI --> KubeVirt
    end

    subgraph "Cluster Management"
        ClusterAPI[clusterapi<br/>Cluster Lifecycle]
    end

    subgraph "Storage Dependencies"
        RookCluster[rook-ceph-cluster]
    end

    subgraph "Network Dependencies"
        IngressNginx[ingress-nginx]
        MetalLB[metallb-config]
    end

    RookCluster -.->|storage| Temporal
    RookCluster -.->|storage| KubeVirt
    IngressNginx -.->|ingress| TemporalUI
    IngressNginx -.->|ingress| KubeVirtManager
    MetalLB -.->|LoadBalancer| Temporal

    classDef workflow fill:#e8eaf6,stroke:#3f51b5,stroke-width:2px
    classDef vm fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    classDef cluster fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef infra fill:#e0f2f1,stroke:#00695c,stroke-width:2px

    class Temporal,TemporalUI,TemporalDB workflow
    class KubeVirt,KubeVirtManager,CDI vm
    class ClusterAPI cluster
    class RookCluster,IngressNginx,MetalLB infra
```

---

## Web UI Access Flow

Shows how users access various web interfaces through the platform.

```mermaid
graph TD
    User[User Browser]
    DNS[external-dns<br/>DNS Records]
    LB[MetalLB<br/>103.110.174.18]
    Ingress[ingress-nginx<br/>HTTP/HTTPS Gateway]
    CertManager[cert-manager<br/>TLS Certificates]

    subgraph "Authenticated UIs"
        Backstage[backstage.pnats.cloud<br/>✅ Keycloak SSO]
        ArgoCD[argocd.pnats.cloud<br/>⏳ Built-in + Dex]
        Grafana[grafana.pnats.cloud<br/>⚠️ admin/changeme]
        Harbor[registry.pnats.cloud<br/>⏳ Built-in]
        Kargo[kargo.pnats.cloud<br/>⏳ Basic Auth]
        Vault[vault.pnats.cloud<br/>⏳ Token]
    end

    subgraph "Unauthenticated UIs ⚠️"
        TemporalUI[temporal-ui.pnats.cloud<br/>❌ No Auth]
        TektonUI[tekton.pnats.cloud<br/>❌ No Auth]
        Kubecost[cost.pnats.cloud<br/>❌ No Auth]
    end

    subgraph "Built-in Auth"
        Keycloak[keycloak.pnats.cloud<br/>Admin/Admin]
        UptimeKuma[status.pnats.cloud<br/>Built-in Users]
        CephDash[ceph.pnats.cloud<br/>Ceph Credentials]
        KubeVirtMgr[kubevirt.pnats.cloud<br/>Token Auth]
    end

    User --> DNS
    DNS --> LB
    LB --> Ingress
    CertManager --> Ingress

    Ingress --> Backstage
    Ingress --> ArgoCD
    Ingress --> Grafana
    Ingress --> Harbor
    Ingress --> Kargo
    Ingress --> Vault
    Ingress --> TemporalUI
    Ingress --> TektonUI
    Ingress --> Kubecost
    Ingress --> Keycloak
    Ingress --> UptimeKuma
    Ingress --> CephDash
    Ingress --> KubeVirtMgr

    Keycloak -.->|SSO| Backstage

    classDef user fill:#e8f5e9,stroke:#2e7d32,stroke-width:3px
    classDef infra fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef authenticated fill:#c8e6c9,stroke:#388e3c,stroke-width:2px
    classDef unauth fill:#ffcdd2,stroke:#c62828,stroke-width:2px
    classDef builtin fill:#fff9c4,stroke:#f57f17,stroke-width:2px

    class User user
    class DNS,LB,Ingress,CertManager infra
    class Backstage,ArgoCD,Grafana,Harbor,Kargo,Vault authenticated
    class TemporalUI,TektonUI,Kubecost unauth
    class Keycloak,UptimeKuma,CephDash,KubeVirtMgr builtin
```

---

## Critical Dependency Paths

Shows the most critical dependency chains - if any of these fail, multiple apps are affected.

```mermaid
graph TD
    subgraph "Critical Path 1: Storage Failure"
        RookCeph1[rook-ceph FAILS] -.->|no storage| Apps1[25+ Apps FAIL]
    end

    subgraph "Critical Path 2: Ingress Failure"
        IngressNginx1[ingress-nginx FAILS] -.->|no access| WebUIs[15 Web UIs UNREACHABLE]
    end

    subgraph "Critical Path 3: Certificate Failure"
        CertManager1[cert-manager FAILS] -.->|TLS expires| HTTPSApps[15 Apps TLS ERRORS]
    end

    subgraph "Critical Path 4: MetalLB Failure"
        MetalLB1[metallb FAILS] -.->|no LoadBalancer| LBServices[6 Services UNREACHABLE<br/>including ingress-nginx]
    end

    subgraph "Critical Path 5: PostgreSQL Operator Failure"
        ZalandoPG1[zalando-pg FAILS] -.->|DB clusters stop| DBApps[Temporal, Keycloak,<br/>Platform Apps FAIL]
    end

    MetalLB1 --> IngressNginx1

    classDef critical fill:#ffcdd2,stroke:#b71c1c,stroke-width:3px
    classDef impact fill:#ffebee,stroke:#c62828,stroke-width:2px

    class RookCeph1,IngressNginx1,CertManager1,MetalLB1,ZalandoPG1 critical
    class Apps1,WebUIs,HTTPSApps,LBServices,DBApps impact
```

---

## Recommended Deployment Order

Shows the correct sequence for deploying the platform from scratch.

```mermaid
graph TD
    Start[Start Fresh Cluster]

    subgraph "Phase 1: Foundation"
        P1A[1. MetalLB Operator]
        P1B[2. cert-manager]
        P1C[3. rook-ceph]
        P1D[4. sealed-secrets]
    end

    subgraph "Phase 2: Core Infrastructure"
        P2A[5. rook-ceph-cluster]
        P2B[6. metallb-config]
        P2C[7. external-dns]
        P2D[8. cert-manager-config]
    end

    subgraph "Phase 3: Networking"
        P3A[9. ingress-nginx]
        P3B[10. zalando-pg]
        P3C[11. redis-operator]
    end

    subgraph "Phase 4: Security & Identity"
        P4A[12. vault]
        P4B[13. keycloak]
        P4C[14. external-secrets]
        P4D[15. crossplane]
    end

    subgraph "Phase 5: GitOps & Observability"
        P5A[16. argocd-self]
        P5B[17. prometheus]
        P5C[18. loki]
        P5D[19. tempo]
    end

    subgraph "Phase 6: Platform Services"
        P6A[20. grafana]
        P6B[21. harbor]
        P6C[22. backstage]
        P6D[23. temporal]
        P6E[24. tekton]
    end

    subgraph "Phase 7: Applications"
        P7[25-43. All other apps]
    end

    Start --> P1A
    P1A --> P1B
    P1B --> P1C
    P1C --> P1D

    P1D --> P2A
    P2A --> P2B
    P2B --> P2C
    P2C --> P2D

    P2D --> P3A
    P3A --> P3B
    P3B --> P3C

    P3C --> P4A
    P4A --> P4B
    P4B --> P4C
    P4C --> P4D

    P4D --> P5A
    P5A --> P5B
    P5B --> P5C
    P5C --> P5D

    P5D --> P6A
    P6A --> P6B
    P6B --> P6C
    P6C --> P6D
    P6D --> P6E

    P6E --> P7

    classDef phase1 fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef phase2 fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef phase3 fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef phase4 fill:#ffebee,stroke:#b71c1c,stroke-width:2px
    classDef phase5 fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef phase6 fill:#fff9c4,stroke:#f57f17,stroke-width:2px
    classDef phase7 fill:#e0f2f1,stroke:#004d40,stroke-width:2px

    class P1A,P1B,P1C,P1D phase1
    class P2A,P2B,P2C,P2D phase2
    class P3A,P3B,P3C phase3
    class P4A,P4B,P4C,P4D phase4
    class P5A,P5B,P5C,P5D phase5
    class P6A,P6B,P6C,P6D,P6E phase6
    class P7 phase7
```

---

## Production Readiness Integration Flow

Shows how Keycloak, Vault, and Crossplane will integrate with existing applications.

```mermaid
graph TB
    subgraph "Identity Provider"
        GitHub[GitHub OAuth]
        Keycloak[Keycloak<br/>SSO Provider]
        GitHub --> Keycloak
    end

    subgraph "Secrets Management"
        Vault[Vault<br/>Secret Store]
        ExternalSecrets[external-secrets<br/>Operator]
        K8sSecrets[Kubernetes Secrets]

        Vault --> ExternalSecrets
        ExternalSecrets --> K8sSecrets
    end

    subgraph "Infrastructure Provisioning"
        Crossplane[Crossplane<br/>IaC Engine]
        Compositions[XRDs & Compositions<br/>PostgreSQL, Redis, S3]
        Resources[Provisioned Resources]

        Crossplane --> Compositions
        Compositions --> Resources
    end

    subgraph "Apps with Keycloak SSO"
        direction LR
        App1[✅ Backstage]
        App2[⏳ ArgoCD]
        App3[⏳ Grafana]
        App4[⏳ Harbor]
        App5[⏳ Vault]
        App6[⏳ Kargo]
    end

    subgraph "Apps Using Vault Secrets"
        direction LR
        VApp1[⏳ All Apps<br/>via External Secrets]
    end

    subgraph "Apps Using Crossplane"
        direction LR
        CApp1[⏳ Temporal<br/>PostgreSQL Claim]
        CApp2[⏳ Harbor<br/>S3 Bucket Claim]
        CApp3[⏳ New Apps<br/>Self-Service]
    end

    Keycloak -.->|OIDC| App1
    Keycloak -.->|planned| App2
    Keycloak -.->|planned| App3
    Keycloak -.->|planned| App4
    Keycloak -.->|planned| App5
    Keycloak -.->|planned| App6

    K8sSecrets -.->|used by| VApp1

    Resources -.->|claimed by| CApp1
    Resources -.->|claimed by| CApp2
    Resources -.->|claimed by| CApp3

    classDef identity fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef secrets fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef infra fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    classDef ready fill:#c8e6c9,stroke:#388e3c,stroke-width:2px
    classDef planned fill:#ffecb3,stroke:#f57c00,stroke-width:2px,stroke-dasharray: 5 5

    class GitHub,Keycloak identity
    class Vault,ExternalSecrets,K8sSecrets secrets
    class Crossplane,Compositions,Resources infra
    class App1 ready
    class App2,App3,App4,App5,App6,VApp1,CApp1,CApp2,CApp3 planned
```

---

## Legend

### Node Colors and Meanings

- **Blue** (Foundation): Core infrastructure components that must be deployed first
- **Orange** (Core Infrastructure): Essential services that depend on foundation
- **Purple** (Network): Networking and ingress components
- **Red** (Security): Authentication, authorization, and secrets management
- **Green** (Observability): Monitoring, logging, and tracing
- **Yellow** (Services): Platform services and applications
- **Teal** (Specialized): Databases, storage, and specialized services

### Connection Types

- **Solid line** (→): Direct hard dependency
- **Dotted line** (-.->): Soft dependency or usage relationship
- **Dashed line** (⏳): Planned but not yet implemented

### Status Indicators

- ✅ **Deployed and Operational**
- ⏳ **Planned / In Progress**
- ⚠️ **Security Risk / Needs Attention**
- ❌ **Not Configured / Missing**

---

## Notes

1. **Scalability**: This dependency structure is designed to scale horizontally. Most components support multiple replicas.

2. **High Availability**: Critical paths (storage, ingress, certificates) should have redundancy configured.

3. **GitOps**: All applications managed by ArgoCD, enabling declarative infrastructure and easy rollbacks.

4. **Security**: Current state has security gaps (hardcoded passwords, open UIs). See [PRODUCTION-READINESS-PLAN.md](PRODUCTION-READINESS-PLAN.md) for remediation.

5. **Observability**: Complete metrics/logs/traces stack deployed and operational.

---

For detailed dependency information, see [APP-DEPENDENCIES.md](APP-DEPENDENCIES.md).
For production readiness plans, see [PRODUCTION-READINESS-PLAN.md](PRODUCTION-READINESS-PLAN.md).
