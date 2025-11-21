# Complete Secret Management Strategy
## Vault + External Secrets Operator + KubeVirt Virtual Clusters

## Overview

This document describes the complete secret management strategy using HashiCorp Vault as the central source of truth, with External Secrets Operator (ESO) syncing secrets to both the primary cluster and all KubeVirt virtual clusters.

---

## Architecture Diagram

```mermaid
graph TB
    subgraph "Primary Cluster"
        subgraph "Vault Cluster - HA"
            VAULT_0[Vault Pod 0<br/>Active]
            VAULT_1[Vault Pod 1<br/>Standby]
            VAULT_2[Vault Pod 2<br/>Standby]
            VAULT_STORAGE[(Raft Storage<br/>Encrypted)]
        end

        subgraph "Secret Engines"
            KV[KV v2 Engine<br/>Static Secrets]
            DB_ENGINE[Database Engine<br/>Dynamic Credentials]
            PKI_ENGINE[PKI Engine<br/>Certificates]
            TRANSIT[Transit Engine<br/>Encryption as Service]
        end

        subgraph "Authentication"
            K8S_AUTH[Kubernetes Auth<br/>Primary Cluster]
            OIDC_AUTH[OIDC Auth<br/>Keycloak Integration]
        end

        subgraph "Primary Cluster ESO"
            ESO_PRIMARY[External Secrets Operator<br/>Primary]
            SS_ARGOCD[SecretStore: ArgoCD]
            SS_TEKTON[SecretStore: Tekton]
            SS_HARBOR[SecretStore: Harbor]
            SS_CROSSPLANE[SecretStore: Crossplane]
        end

        subgraph "Shared Services"
            POSTGRES[(PostgreSQL<br/>Multi-tenant)]
            KAFKA[Kafka]
            REDIS[Redis]
        end
    end

    subgraph "Virtual Cluster - Dev"
        subgraph "Dev vCluster ESO"
            ESO_DEV[External Secrets Operator<br/>Dev vCluster]
            SS_DEV[SecretStore: Dev Apps]
        end

        subgraph "Dev Applications"
            APP_DEV_USER[user-service<br/>Pods]
            APP_DEV_PAYMENT[payment-service<br/>Pods]
        end
    end

    subgraph "Virtual Cluster - Staging"
        ESO_STAGING[External Secrets Operator<br/>Staging vCluster]
        SS_STAGING[SecretStore: Staging Apps]
        APP_STAGING[Application Pods]
    end

    subgraph "Virtual Cluster - Production"
        ESO_PROD[External Secrets Operator<br/>Production vCluster]
        SS_PROD[SecretStore: Prod Apps]
        APP_PROD[Application Pods]
    end

    subgraph "Crossplane Infrastructure"
        XP[Crossplane Controller]
        XP_DB_CLAIM[PostgreSQL Instance Claim]
        XP_VCLUSTER_CLAIM[VirtualCluster Claim]
    end

    %% Vault HA
    VAULT_0 --> VAULT_STORAGE
    VAULT_1 --> VAULT_STORAGE
    VAULT_2 --> VAULT_STORAGE

    %% Vault Engines
    VAULT_0 --> KV
    VAULT_0 --> DB_ENGINE
    VAULT_0 --> PKI_ENGINE
    VAULT_0 --> TRANSIT

    %% Auth
    K8S_AUTH --> VAULT_0
    OIDC_AUTH --> VAULT_0

    %% Primary Cluster Secret Sync
    ESO_PRIMARY --> K8S_AUTH
    SS_ARGOCD --> ESO_PRIMARY
    SS_TEKTON --> ESO_PRIMARY
    SS_HARBOR --> ESO_PRIMARY
    SS_CROSSPLANE --> ESO_PRIMARY

    %% Virtual Cluster Secret Sync
    ESO_DEV --> K8S_AUTH
    ESO_STAGING --> K8S_AUTH
    ESO_PROD --> K8S_AUTH

    SS_DEV --> ESO_DEV
    SS_STAGING --> ESO_STAGING
    SS_PROD --> ESO_PROD

    %% Applications consume secrets
    SS_DEV --> APP_DEV_USER
    SS_DEV --> APP_DEV_PAYMENT
    SS_STAGING --> APP_STAGING
    SS_PROD --> APP_PROD

    %% Crossplane provisions and stores credentials
    XP --> XP_DB_CLAIM
    XP --> XP_VCLUSTER_CLAIM
    XP_DB_CLAIM -.->|Register Creds| KV
    XP_VCLUSTER_CLAIM -.->|Register Kubeconfig| KV

    %% Dynamic DB credentials
    DB_ENGINE --> POSTGRES
    DB_ENGINE -.->|Dynamic Creds| ESO_DEV
    DB_ENGINE -.->|Dynamic Creds| ESO_STAGING
    DB_ENGINE -.->|Dynamic Creds| ESO_PROD

    %% Service access
    APP_DEV_USER -.->|Access| POSTGRES
    APP_DEV_USER -.->|Access| KAFKA
    APP_DEV_USER -.->|Access| REDIS

    style VAULT_0 fill:#000000,color:#ffffff
    style VAULT_1 fill:#333333,color:#ffffff
    style VAULT_2 fill:#333333,color:#ffffff
    style ESO_PRIMARY fill:#4285f4
    style ESO_DEV fill:#00c853
    style ESO_STAGING fill:#ff9800
    style ESO_PROD fill:#f44336
```

---

## 1. Vault HA Deployment

### 1.1 Vault StatefulSet with Raft Storage

```yaml
# vault/vault-ha.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault
  namespace: vault
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-server-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault
    namespace: vault
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-config
  namespace: vault
data:
  vault.hcl: |
    ui = true

    listener "tcp" {
      address = "[::]:8200"
      cluster_address = "[::]:8201"
      tls_disable = "true"
    }

    storage "raft" {
      path = "/vault/data"

      retry_join {
        leader_api_addr = "http://vault-0.vault-internal:8200"
      }
      retry_join {
        leader_api_addr = "http://vault-1.vault-internal:8200"
      }
      retry_join {
        leader_api_addr = "http://vault-2.vault-internal:8200"
      }
    }

    service_registration "kubernetes" {}

    seal "transit" {
      address = "https://vault-auto-unseal.pnats.cloud:8200"
      disable_renewal = "false"
      key_name = "autounseal"
      mount_path = "transit/"
      tls_skip_verify = "true"
    }
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: vault
spec:
  serviceName: vault-internal
  replicas: 3
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      serviceAccountName: vault
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: vault
              topologyKey: kubernetes.io/hostname
      containers:
        - name: vault
          image: hashicorp/vault:1.17.2
          command:
            - "/bin/sh"
            - "-ec"
          args:
            - |
              vault server -config=/vault/config/vault.hcl
          env:
            - name: VAULT_ADDR
              value: "http://127.0.0.1:8200"
            - name: VAULT_API_ADDR
              value: "http://$(POD_IP):8200"
            - name: VAULT_CLUSTER_ADDR
              value: "https://$(POD_IP):8201"
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: SKIP_SETCAP
              value: "true"
          ports:
            - containerPort: 8200
              name: http
            - containerPort: 8201
              name: https-internal
            - containerPort: 8202
              name: http-rep
          readinessProbe:
            httpGet:
              path: /v1/sys/health?standbyok=true
              port: 8200
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /v1/sys/health?standbyok=true
              port: 8200
            initialDelaySeconds: 60
            periodSeconds: 5
          volumeMounts:
            - name: data
              mountPath: /vault/data
            - name: config
              mountPath: /vault/config
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 4Gi
      volumes:
        - name: config
          configMap:
            name: vault-config
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: ceph-block
        resources:
          requests:
            storage: 50Gi
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: vault
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 8200
      targetPort: 8200
    - name: https-internal
      port: 8201
      targetPort: 8201
  selector:
    app: vault
---
apiVersion: v1
kind: Service
metadata:
  name: vault-internal
  namespace: vault
spec:
  type: ClusterIP
  clusterIP: None
  ports:
    - name: http
      port: 8200
      targetPort: 8200
    - name: https-internal
      port: 8201
      targetPort: 8201
  selector:
    app: vault
```

### 1.2 Initialize and Unseal Vault

```bash
#!/bin/bash
# vault/init-vault.sh

# Initialize Vault (only run once)
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > vault-keys.json

# Extract unseal keys and root token
UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' vault-keys.json)
UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' vault-keys.json)
UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' vault-keys.json)
ROOT_TOKEN=$(jq -r '.root_token' vault-keys.json)

# Unseal all Vault pods
for i in 0 1 2; do
  kubectl exec -n vault vault-$i -- vault operator unseal $UNSEAL_KEY_1
  kubectl exec -n vault vault-$i -- vault operator unseal $UNSEAL_KEY_2
  kubectl exec -n vault vault-$i -- vault operator unseal $UNSEAL_KEY_3
done

# Store root token in Kubernetes secret (for automation)
kubectl create secret generic vault-root-token \
  -n vault \
  --from-literal=token=$ROOT_TOKEN

echo "Vault initialized and unsealed!"
echo "Root token stored in vault-root-token secret"
echo "IMPORTANT: Store vault-keys.json in a secure location!"
```

---

## 2. Vault Secret Structure

### 2.1 Hierarchical Secret Organization

```
vault kv metadata list secret/

secret/
├── ci-cd/                           # CI/CD tool credentials
│   ├── github/
│   │   ├── webhook-secret           # GitHub webhook secret
│   │   ├── token                    # GitHub API token
│   │   └── ssh-key                  # Deploy key
│   ├── harbor/
│   │   ├── admin-password           # Harbor admin
│   │   ├── robot-accounts/          # Robot accounts per project
│   │   │   ├── tekton
│   │   │   ├── kargo
│   │   │   └── argocd
│   ├── verdaccio/
│   │   └── auth-token
│   ├── argocd/
│   │   ├── admin-password
│   │   ├── github-repo-creds
│   │   └── cluster-credentials/     # Registered cluster kubeconfigs
│   │       ├── dev-vcluster
│   │       ├── staging-vcluster
│   │       └── production-vcluster
│   ├── kargo/
│   │   └── admin-credentials
│   └── tekton/
│       └── pipeline-secrets
│
├── shared-services/                 # Shared infrastructure credentials
│   ├── postgres/
│   │   ├── admin-password           # PostgreSQL superuser
│   │   ├── replication-password     # Replication user
│   │   └── connection-url           # Admin connection string
│   ├── kafka/
│   │   ├── admin-credentials
│   │   ├── sasl-credentials
│   │   └── brokers                  # Broker list
│   ├── redis/
│   │   ├── password
│   │   └── url
│   ├── temporal/
│   │   ├── admin-password
│   │   └── encryption-key
│   └── monitoring/
│       ├── prometheus-admin
│       └── grafana-admin
│
├── clusters/                        # Virtual cluster metadata
│   ├── dev/
│   │   ├── kubeconfig               # Base64 encoded kubeconfig
│   │   ├── api-url
│   │   ├── ca-cert
│   │   └── admin-token
│   ├── staging/
│   ├── uat/
│   ├── preprod/
│   ├── production/
│   └── sandbox/
│
├── apps/                            # Application secrets per environment
│   ├── dev/
│   │   ├── user-service/
│   │   │   ├── api-key
│   │   │   ├── jwt-secret
│   │   │   ├── encryption-key
│   │   │   └── external-api-keys/
│   │   │       ├── stripe
│   │   │       ├── sendgrid
│   │   │       └── twilio
│   │   ├── payment-service/
│   │   └── notification-service/
│   ├── staging/
│   │   ├── user-service/
│   │   ├── payment-service/
│   │   └── notification-service/
│   └── production/
│       ├── user-service/
│       ├── payment-service/
│       └── notification-service/
│
└── infrastructure/                  # Infrastructure secrets (Crossplane-managed)
    ├── databases/
    │   ├── dev/
    │   │   ├── user-service-db-creds
    │   │   └── payment-service-db-creds
    │   ├── staging/
    │   └── production/
    └── certificates/
        ├── dev-wildcard-cert
        ├── staging-wildcard-cert
        └── production-wildcard-cert
```

### 2.2 Initialize Vault Secrets via Script

```bash
#!/bin/bash
# vault/scripts/populate-vault.sh

export VAULT_ADDR="http://vault.vault.svc:8200"
export VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)

# Function to generate random password
gen_password() {
  openssl rand -base64 32
}

# Function to generate API key
gen_api_key() {
  openssl rand -hex 32
}

# 1. CI/CD Secrets
echo "Storing CI/CD secrets..."

vault kv put secret/ci-cd/github \
  webhook-secret="$(gen_password)" \
  token="${GITHUB_TOKEN}" \
  ssh-key="$(cat ~/.ssh/github_deploy_key)"

vault kv put secret/ci-cd/harbor \
  admin-password="${HARBOR_ADMIN_PASSWORD}" \
  url="https://harbor.pnats.cloud"

vault kv put secret/ci-cd/harbor/robot-accounts/tekton \
  username="robot\$tekton" \
  password="${HARBOR_ROBOT_TEKTON_PASSWORD}"

vault kv put secret/ci-cd/argocd \
  admin-password="${ARGOCD_ADMIN_PASSWORD}" \
  url="https://argocd.pnats.cloud"

# 2. Shared Services
echo "Storing shared service credentials..."

vault kv put secret/shared-services/postgres \
  admin-password="$(gen_password)" \
  host="postgres.shared-services.svc.cluster.local" \
  port="5432"

vault kv put secret/shared-services/kafka \
  admin-password="$(gen_password)" \
  brokers="kafka-0.kafka.shared-services.svc.cluster.local:9092,kafka-1.kafka.shared-services.svc.cluster.local:9092,kafka-2.kafka.shared-services.svc.cluster.local:9092"

vault kv put secret/shared-services/redis \
  password="$(gen_password)" \
  url="redis://redis.shared-services.svc.cluster.local:6379"

# 3. Application Secrets (per environment)
for ENV in dev staging production; do
  echo "Storing $ENV application secrets..."

  vault kv put secret/apps/$ENV/user-service \
    api-key="$(gen_api_key)" \
    jwt-secret="$(gen_password)" \
    encryption-key="$(gen_password)"

  vault kv put secret/apps/$ENV/payment-service \
    api-key="$(gen_api_key)" \
    stripe-api-key="${STRIPE_API_KEY_${ENV^^}}" \
    encryption-key="$(gen_password)"

  vault kv put secret/apps/$ENV/notification-service \
    api-key="$(gen_api_key)" \
    sendgrid-api-key="${SENDGRID_API_KEY}" \
    twilio-account-sid="${TWILIO_ACCOUNT_SID}" \
    twilio-auth-token="${TWILIO_AUTH_TOKEN}"
done

echo "Vault secrets populated successfully!"
```

---

## 3. Vault Kubernetes Authentication

### 3.1 Enable and Configure Kubernetes Auth

```bash
#!/bin/bash
# vault/scripts/configure-k8s-auth.sh

export VAULT_ADDR="http://vault.vault.svc:8200"
export VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)

# Enable Kubernetes auth method
vault auth enable kubernetes

# Configure Kubernetes auth for primary cluster
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

# Create roles for primary cluster services
vault write auth/kubernetes/role/external-secrets-primary \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets-system \
  policies=external-secrets-primary \
  ttl=1h

vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-server,argocd-application-controller \
  bound_service_account_namespaces=argocd \
  policies=argocd \
  ttl=1h

vault write auth/kubernetes/role/tekton \
  bound_service_account_names=tekton-triggers-sa,tekton-pipelines-sa \
  bound_service_account_namespaces=tekton-pipelines \
  policies=tekton \
  ttl=1h

vault write auth/kubernetes/role/crossplane \
  bound_service_account_names=crossplane \
  bound_service_account_namespaces=crossplane-system \
  policies=crossplane \
  ttl=1h

vault write auth/kubernetes/role/backstage \
  bound_service_account_names=backstage \
  bound_service_account_namespaces=backstage \
  policies=backstage \
  ttl=24h

# Create roles for vCluster service accounts
# These will authenticate from inside vClusters to primary Vault
for ENV in dev staging uat preprod production sandbox; do
  vault write auth/kubernetes/role/vcluster-${ENV} \
    bound_service_account_names=external-secrets,default \
    bound_service_account_namespaces=default,kube-system \
    policies=vcluster-${ENV} \
    ttl=1h
done
```

### 3.2 Vault Policies

```hcl
# vault/policies/external-secrets-primary.hcl
# Policy for ESO in primary cluster

path "secret/data/ci-cd/*" {
  capabilities = ["read", "list"]
}

path "secret/data/shared-services/*" {
  capabilities = ["read", "list"]
}

path "secret/data/clusters/*" {
  capabilities = ["read", "list"]
}

path "database/creds/*" {
  capabilities = ["read"]
}
```

```hcl
# vault/policies/vcluster-dev.hcl
# Policy for ESO in dev vCluster

path "secret/data/apps/dev/*" {
  capabilities = ["read", "list"]
}

path "secret/data/shared-services/postgres" {
  capabilities = ["read"]
}

path "secret/data/shared-services/kafka" {
  capabilities = ["read"]
}

path "secret/data/shared-services/redis" {
  capabilities = ["read"]
}

path "database/creds/dev-*" {
  capabilities = ["read"]
}

path "pki/issue/dev-cert" {
  capabilities = ["create", "update"]
}
```

```hcl
# vault/policies/vcluster-production.hcl
# Policy for ESO in production vCluster

path "secret/data/apps/production/*" {
  capabilities = ["read", "list"]
}

path "secret/data/shared-services/postgres" {
  capabilities = ["read"]
}

path "secret/data/shared-services/kafka" {
  capabilities = ["read"]
}

path "secret/data/shared-services/redis" {
  capabilities = ["read"]
}

path "database/creds/production-*" {
  capabilities = ["read"]
}

path "pki/issue/production-cert" {
  capabilities = ["create", "update"]
}
```

```bash
# Apply policies
vault policy write external-secrets-primary vault/policies/external-secrets-primary.hcl
vault policy write argocd vault/policies/argocd.hcl
vault policy write tekton vault/policies/tekton.hcl
vault policy write crossplane vault/policies/crossplane.hcl
vault policy write backstage vault/policies/backstage.hcl

for ENV in dev staging uat preprod production sandbox; do
  vault policy write vcluster-${ENV} vault/policies/vcluster-${ENV}.hcl
done
```

---

## 4. External Secrets Operator Setup

### 4.1 Install ESO in Primary Cluster

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true \
  --set webhook.port=9443
```

### 4.2 ClusterSecretStore for Primary Cluster

```yaml
# vault/eso/cluster-secretstore-primary.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets-primary"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets-system"
```

### 4.3 SecretStore per Namespace in Primary Cluster

```yaml
# argocd/secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: argocd
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "argocd"
          serviceAccountRef:
            name: "argocd-server"
---
# tekton-pipelines/secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: tekton-pipelines
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "tekton"
          serviceAccountRef:
            name: "tekton-triggers-sa"
```

### 4.4 ExternalSecret Examples (Primary Cluster)

```yaml
# argocd/externalsecrets/github-repo-creds.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: github-repo-creds
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore

  target:
    name: github-repo-secret
    creationPolicy: Owner
    template:
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      type: Opaque
      data:
        type: git
        url: "https://github.com/yourorg/gitops-config.git"
        username: "git"
        password: "{{ .githubToken }}"

  data:
    - secretKey: githubToken
      remoteRef:
        key: ci-cd/github
        property: token
---
# argocd/externalsecrets/dev-cluster-kubeconfig.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: dev-cluster-kubeconfig
  namespace: argocd
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend
    kind: SecretStore

  target:
    name: dev-cluster-secret
    creationPolicy: Owner
    template:
      metadata:
        labels:
          argocd.argoproj.io/secret-type: cluster
      type: Opaque
      data:
        name: dev-vcluster
        server: "{{ .apiUrl }}"
        config: "{{ .kubeconfig | b64dec }}"

  data:
    - secretKey: apiUrl
      remoteRef:
        key: clusters/dev
        property: api-url

    - secretKey: kubeconfig
      remoteRef:
        key: clusters/dev
        property: kubeconfig
---
# tekton-pipelines/externalsecrets/harbor-creds.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: harbor-robot-tekton
  namespace: tekton-pipelines
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore

  target:
    name: harbor-robot-tekton
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {
            "auths": {
              "{{ .harborUrl }}": {
                "username": "{{ .username }}",
                "password": "{{ .password }}",
                "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
              }
            }
          }

  data:
    - secretKey: harborUrl
      remoteRef:
        key: ci-cd/harbor
        property: url

    - secretKey: username
      remoteRef:
        key: ci-cd/harbor/robot-accounts/tekton
        property: username

    - secretKey: password
      remoteRef:
        key: ci-cd/harbor/robot-accounts/tekton
        property: password
```

---

## 5. ESO in Virtual Clusters

### 5.1 Install ESO in Each vCluster (via ArgoCD)

```yaml
# argocd/applications/dev-vcluster-eso.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-vcluster-external-secrets
  namespace: argocd
spec:
  project: default

  source:
    chart: external-secrets
    repoURL: https://charts.external-secrets.io
    targetRevision: 0.9.11
    helm:
      values: |
        installCRDs: true
        webhook:
          port: 9443

  destination:
    server: https://dev-k8s-api.kubevirt-vms.svc:6443
    namespace: external-secrets-system

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 5.2 SecretStore in vCluster (Points to Primary Vault)

```yaml
# This manifest is deployed INSIDE dev-vcluster via ArgoCD

# dev-vcluster/secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      # Access Vault in primary cluster via service DNS
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "vcluster-dev"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets-system"
```

### 5.3 ExternalSecret in vCluster for Applications

```yaml
# Deployed INSIDE dev-vcluster

# dev-vcluster/user-service-secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: user-service-secrets
  namespace: default
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: vault-backend
    kind: SecretStore

  target:
    name: user-service-secrets
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        # Application secrets
        API_KEY: "{{ .apiKey }}"
        JWT_SECRET: "{{ .jwtSecret }}"
        ENCRYPTION_KEY: "{{ .encryptionKey }}"

        # Database connection (points to primary cluster PostgreSQL)
        DATABASE_URL: "postgresql://{{ .dbUsername }}:{{ .dbPassword }}@postgres.shared-services.svc.cluster.local:5432/dev_userdb"

        # Kafka connection (points to primary cluster Kafka)
        KAFKA_BROKERS: "{{ .kafkaBrokers }}"

        # Redis connection (points to primary cluster Redis)
        REDIS_URL: "redis://:{{ .redisPassword }}@redis.shared-services.svc.cluster.local:6379"

        # External API keys
        STRIPE_API_KEY: "{{ .stripeApiKey }}"
        SENDGRID_API_KEY: "{{ .sendgridApiKey }}"

  dataFrom:
    - extract:
        key: apps/dev/user-service

  data:
    # Dynamic database credentials
    - secretKey: dbUsername
      remoteRef:
        key: database/creds/dev-userservice
        property: username

    - secretKey: dbPassword
      remoteRef:
        key: database/creds/dev-userservice
        property: password

    # Shared service credentials
    - secretKey: kafkaBrokers
      remoteRef:
        key: shared-services/kafka
        property: brokers

    - secretKey: redisPassword
      remoteRef:
        key: shared-services/redis
        property: password
```

---

## 6. Dynamic Database Credentials

### 6.1 Enable Database Secrets Engine

```bash
# vault/scripts/configure-database-engine.sh

export VAULT_ADDR="http://vault.vault.svc:8200"
export VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)

# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL connection
POSTGRES_PASSWORD=$(vault kv get -field=admin-password secret/shared-services/postgres)

vault write database/config/postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="dev-*,staging-*,production-*" \
  connection_url="postgresql://{{username}}:{{password}}@postgres.shared-services.svc.cluster.local:5432/postgres?sslmode=disable" \
  username="postgres" \
  password="$POSTGRES_PASSWORD"

# Create dynamic roles for each environment and service
vault write database/roles/dev-userservice \
  db_name=postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT CONNECT ON DATABASE dev_userdb TO \"{{name}}\"; \
    GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

vault write database/roles/production-userservice \
  db_name=postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT CONNECT ON DATABASE production_userdb TO \"{{name}}\"; \
    GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="8h"

# Test dynamic credential generation
vault read database/creds/dev-userservice
```

### 6.2 Automatic Credential Rotation

```yaml
# ESO automatically refreshes dynamic credentials before expiry

# dev-vcluster/user-service-db-creds.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: user-service-db-dynamic
  namespace: default
spec:
  refreshInterval: 30m  # Refresh every 30 minutes (before 1h TTL expires)
  secretStoreRef:
    name: vault-backend
    kind: SecretStore

  target:
    name: user-service-db-creds
    creationPolicy: Owner
    deletionPolicy: Retain  # Keep old secret during rotation

    template:
      type: Opaque
      data:
        DATABASE_URL: "postgresql://{{ .username }}:{{ .password }}@postgres.shared-services.svc.cluster.local:5432/dev_userdb?sslmode=require"
        DB_USERNAME: "{{ .username }}"
        DB_PASSWORD: "{{ .password }}"

  data:
    - secretKey: username
      remoteRef:
        key: database/creds/dev-userservice
        property: username

    - secretKey: password
      remoteRef:
        key: database/creds/dev-userservice
        property: password
```

### 6.3 Application Deployment with Dynamic Credentials

```yaml
# dev-vcluster/user-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: default
  annotations:
    # Reloader will restart pods when secret changes
    reloader.stakater.com/auto: "true"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
        - name: user-service
          image: harbor.pnats.cloud/services/user-service:v1.2.3
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: user-service-db-creds
                  key: DATABASE_URL

            - name: API_KEY
              valueFrom:
                secretKeyRef:
                  name: user-service-secrets
                  key: API_KEY

            - name: KAFKA_BROKERS
              valueFrom:
                secretKeyRef:
                  name: user-service-secrets
                  key: KAFKA_BROKERS

          # Health checks that validate DB connection
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10

          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
```

---

## 7. Crossplane Integration with Vault

### 7.1 Crossplane Stores Provisioned Credentials in Vault

```yaml
# crossplane/compositions/postgres-with-vault-composition.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: postgres-with-vault
spec:
  compositeTypeRef:
    apiVersion: database.pnats.cloud/v1alpha1
    kind: XPostgreSQLInstance

  resources:
    # Create database
    - name: database
      base:
        apiVersion: postgresql.sql.crossplane.io/v1alpha1
        kind: Database
        spec:
          forProvider:
            encoding: UTF8
          providerConfigRef:
            name: postgres-provider

    # Create user with password
    - name: user
      base:
        apiVersion: postgresql.sql.crossplane.io/v1alpha1
        kind: Role
        spec:
          forProvider:
            login: true
          writeConnectionSecretToRef:
            namespace: crossplane-system

    # Grant permissions
    - name: grant
      base:
        apiVersion: postgresql.sql.crossplane.io/v1alpha1
        kind: Grant
        spec:
          forProvider:
            privileges:
              - ALL

    # Store credentials in Vault via Job
    - name: vault-registration
      base:
        apiVersion: kubernetes.crossplane.io/v1alpha1
        kind: Object
        spec:
          forProvider:
            manifest:
              apiVersion: batch/v1
              kind: Job
              metadata:
                namespace: crossplane-system
              spec:
                template:
                  spec:
                    serviceAccountName: crossplane
                    restartPolicy: OnFailure
                    containers:
                      - name: vault-register
                        image: vault:latest
                        env:
                          - name: VAULT_ADDR
                            value: "http://vault.vault.svc:8200"
                        command:
                          - /bin/sh
                          - -c
                          - |
                            # Authenticate with Vault
                            export VAULT_TOKEN=$(vault write -field=token \
                              auth/kubernetes/login \
                              role=crossplane \
                              jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token)

                            # Store database credentials
                            vault kv put secret/infrastructure/databases/${ENVIRONMENT}/${SERVICE_NAME} \
                              host=postgres.shared-services.svc.cluster.local \
                              port=5432 \
                              database=${DB_NAME} \
                              username=${DB_USER} \
                              password=${DB_PASSWORD}

                            echo "Credentials stored in Vault at secret/infrastructure/databases/${ENVIRONMENT}/${SERVICE_NAME}"
```

---

## 8. Secret Rotation Strategy

### 8.1 Automatic Secret Rotation Schedule

| Secret Type | Rotation Frequency | Method |
|-------------|-------------------|--------|
| Dynamic DB Credentials | 1 hour | Vault Database Engine auto-rotation |
| Application API Keys | 90 days | Manual rotation + notification |
| JWT Secrets | 180 days | Manual rotation + notification |
| TLS Certificates | 30 days (auto-renewal at 15 days) | Vault PKI Engine |
| Service Account Tokens | 24 hours | Kubernetes auto-rotation |
| External API Keys (Stripe, etc.) | Managed by provider | N/A |

### 8.2 Rotation Monitoring with Prometheus

```yaml
# monitoring/prometheusrules/secret-rotation-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: secret-rotation-alerts
  namespace: monitoring
spec:
  groups:
    - name: vault-secret-rotation
      interval: 1h
      rules:
        - alert: VaultSecretExpiringRev
          expr: |
            (vault_secret_lease_expiration_time_seconds - time()) < 86400
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Vault secret expiring in less than 24 hours"
            description: "Secret {{ $labels.path }} will expire in {{ $value | humanizeDuration }}"

        - alert: ExternalSecretSyncFailed
          expr: |
            external_secrets_sync_calls_error > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "External Secret sync failed"
            description: "ExternalSecret {{ $labels.name }} in namespace {{ $labels.namespace }} failed to sync"
```

---

## 9. Backup and Disaster Recovery

### 9.1 Vault Snapshot Backup

```yaml
# vault/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vault-snapshot-backup
  namespace: vault
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3

  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: vault
          restartPolicy: OnFailure

          containers:
            - name: backup
              image: hashicorp/vault:1.17.2
              env:
                - name: VAULT_ADDR
                  value: "http://vault.vault.svc:8200"
                - name: VAULT_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: vault-root-token
                      key: token

              command:
                - /bin/sh
                - -c
                - |
                  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                  BACKUP_FILE="/backups/vault-snapshot-${TIMESTAMP}.snap"

                  # Create Raft snapshot
                  vault operator raft snapshot save $BACKUP_FILE

                  # Upload to S3 (or other backup location)
                  aws s3 cp $BACKUP_FILE s3://vault-backups/snapshots/

                  # Keep only last 30 days locally
                  find /backups -name "vault-snapshot-*.snap" -mtime +30 -delete

                  echo "Vault snapshot backed up to $BACKUP_FILE"

              volumeMounts:
                - name: backup-storage
                  mountPath: /backups

          volumes:
            - name: backup-storage
              persistentVolumeClaim:
                claimName: vault-backup-pvc
```

### 9.2 Restore from Snapshot

```bash
#!/bin/bash
# vault/scripts/restore-snapshot.sh

SNAPSHOT_FILE="$1"

if [ -z "$SNAPSHOT_FILE" ]; then
  echo "Usage: $0 <snapshot-file>"
  exit 1
fi

# Stop Vault (requires majority of pods to be stopped for Raft)
kubectl scale statefulset vault -n vault --replicas=0

# Wait for pods to terminate
kubectl wait --for=delete pod -l app=vault -n vault --timeout=60s

# Start Vault pods one by one
kubectl scale statefulset vault -n vault --replicas=1

# Wait for vault-0 to be ready
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s

# Unseal vault-0
vault operator unseal <unseal-key-1>
vault operator unseal <unseal-key-2>
vault operator unseal <unseal-key-3>

# Restore snapshot
kubectl cp $SNAPSHOT_FILE vault/vault-0:/tmp/restore.snap
kubectl exec -n vault vault-0 -- vault operator raft snapshot restore -force /tmp/restore.snap

# Scale back to 3 replicas
kubectl scale statefulset vault -n vault --replicas=3

echo "Vault restored from snapshot: $SNAPSHOT_FILE"
```

---

## Summary

This complete secret management strategy provides:

✅ **Centralized Secret Storage** - All secrets in Vault HA cluster
✅ **Multi-Cluster Support** - Primary + all virtual clusters access same Vault
✅ **Dynamic Credentials** - Short-lived database credentials with auto-rotation
✅ **GitOps Friendly** - Secrets never in Git, only ExternalSecret manifests
✅ **Per-Environment Isolation** - Separate policies and paths per environment
✅ **Automatic Sync** - ESO syncs secrets to Kubernetes automatically
✅ **Cross-Cluster Access** - vClusters access shared services via Vault-provided credentials
✅ **Audit Trail** - Complete secret access logging in Vault
✅ **Disaster Recovery** - Automated snapshots and restore procedures
✅ **Secure by Default** - Kubernetes auth, least privilege policies
✅ **Integration Ready** - Works with Crossplane, ArgoCD, Tekton, Backstage
