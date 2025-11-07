# 🔐 Platform Secret Setup Guide

This guide explains the automated secret setup functionality added to the platform deployment system.

## 🚀 Usage

### Automatic Secret Setup During Deployment
```bash
./run.sh deploy
```
- Automatically prompts for required secrets before deployment
- Validates configuration values 
- Creates missing secrets in appropriate namespaces

### Manual Secret Setup Only
```bash
./run.sh setup-secrets
```
- Sets up secrets without deploying
- Useful for preparing cluster before deployment
- Can be run multiple times (skips existing secrets)

## 🔑 Supported Secrets

### 1. Cloudflare API Token (cert-manager)
- **Purpose**: DNS01 challenge for Let's Encrypt certificates
- **Namespace**: `cert-manager`
- **Secret Name**: `cloudflare-api-token`
- **Required Permissions**:
  - Zone:Zone:Read
  - Zone:DNS:Edit
  - Include: All zones

### 2. GitHub Personal Access Token (ArgoCD)
- **Purpose**: Access to private repositories
- **Namespace**: `argocd`
- **Secret Name**: `github-token`
- **Required Permissions**:
  - repo (Full control of private repositories)
  - read:org (Read org and team membership)

## ⚠️ Configuration Warnings

The script also checks for default values that need updating:

### Cert-Manager Email
- **File**: `charts/cert-manager/values.yaml`
- **Default**: `admin@example.com`
- **Action**: Update to your actual email for Let's Encrypt notifications

### MetalLB IP Range
- **File**: `charts/metallb/values.yaml`
- **Default**: `192.168.102.50-192.168.102.80`
- **Action**: Update to match your network's available IP range

## 🔒 Security Features

- **Existing Secret Detection**: Skips secrets that already exist
- **Namespace Creation**: Automatically creates required namespaces
- **Skip Option**: Can skip any secret setup by typing 'skip'
- **Input Validation**: Checks for empty/invalid inputs
- **Error Handling**: Graceful handling of failures

## 🛠️ Adding New Secrets

To add support for additional secrets:

1. Create a new function following the pattern:
```bash
setup_your_secret() {
    local secret_name="your-secret-name"
    local namespace="target-namespace"
    
    # Check if secret exists
    if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        log_success "Your secret already exists"
        return 0
    fi
    
    # Prompt user
    read -p "Enter your secret value (or 'skip'): " secret_value
    
    # Create secret
    kubectl create secret generic "$secret_name" \
        --from-literal=key="$secret_value" \
        -n "$namespace"
}
```

2. Add the function call to `setup_required_secrets()`

## 📋 Pre-Deployment Checklist

Before running deployment:

- [ ] Cloudflare API token ready (if using cert-manager)
- [ ] GitHub PAT ready (if using private repos)
- [ ] Network IP range identified for MetalLB
- [ ] Email address for Let's Encrypt notifications
- [ ] Cluster kubectl access configured

## 🎯 Example Workflow

```bash
# 1. Setup secrets first
./run.sh setup-secrets

# 2. Update configuration files manually
vim charts/cert-manager/values.yaml  # Update email
vim charts/metallb/values.yaml       # Update IP range

# 3. Deploy platform
./run.sh deploy

# 4. Check status
./run.sh status
```

This automated approach ensures all required secrets are in place before deployment begins! 🚀