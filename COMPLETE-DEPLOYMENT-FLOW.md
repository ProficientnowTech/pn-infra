# 🚀 **Complete Deployment Flow - Everything Automated!**

## ✅ **What `./run.sh deploy` Will Do**

### **🔑 Step 1: Secret Setup (Interactive)**
The script will prompt for:

1. **Cloudflare API Token**:
   ```
   🔑 Cert-Manager requires a Cloudflare API token for DNS01 challenges.
   The token needs the following permissions:
   - Zone:Zone:Read
   - Zone:DNS:Edit  
   - Include: All zones
   
   Enter your Cloudflare API token (or 'skip' to continue without):
   ```

2. **GitHub Personal Access Token**:
   ```
   🔑 ArgoCD may require a GitHub Personal Access Token for private repositories.
   The token needs the following permissions:
   - repo (Full control of private repositories)
   - read:org (Read org and team membership)
   
   Enter your GitHub Personal Access Token (or 'skip' to continue without):
   ```

### **🎯 Step 2: Automatic Deployment Sequence**

| **Sync Wave** | **Component** | **What It Does** |
|---------------|---------------|------------------|
| **-4** | **MetalLB** | Creates IP pool `192.168.101.121-125` for LoadBalancers |
| **-3** | **Ingress-NGINX** | Deploys ingress controller, gets IP from MetalLB |
| **-2** | **Cert-Manager** | Sets up Let's Encrypt with Cloudflare DNS01 |
| **-1** | **External-DNS** | Watches ingresses, creates DNS records automatically |
| **0** | **ArgoCD** | Self-managed ArgoCD with ingress for `argocd.pnats.cloud` |

### **🌐 Step 3: Automatic DNS & SSL**

1. **MetalLB assigns IP** (e.g., `192.168.101.123`) to ingress-nginx LoadBalancer
2. **External-DNS detects** ArgoCD ingress with annotation:
   ```yaml
   external-dns.alpha.kubernetes.io/hostname: argocd.pnats.cloud
   ```
3. **External-DNS creates** Cloudflare DNS A record:
   ```
   argocd.pnats.cloud → 192.168.101.123
   ```
4. **Cert-Manager requests** SSL certificate via DNS01 challenge
5. **Certificate issued** and applied to ingress

## 🔐 **Repository Access & Permissions**

### **✅ ArgoCD Repository Configuration**
- **Protocol**: HTTPS (not SSH)
- **Authentication**: GitHub Personal Access Token
- **Repository**: `https://github.com/pnow-devsupreme/pn-infra.git`
- **Secret Reference**: `$github-token:token`

### **✅ Project Permissions**
ArgoCD is configured with:

1. **Default Project**: Has access to all applications
2. **Source Repositories**:
   - Your private repo: `https://github.com/pnow-devsupreme/pn-infra.git`
   - All Helm repositories (public)
3. **Destination Clusters**: `https://kubernetes.default.svc`
4. **Namespaces**: All namespaces (`*`)
5. **Resources**: All Kubernetes resources (`*`)

### **✅ RBAC Configuration**
```yaml
policy.csv: |
  p, role:admin, applications, *, */*, allow
  p, role:admin, clusters, *, *, allow  
  p, role:admin, repositories, *, *, allow
  g, argocd-admins, role:admin
```

## 🎯 **End Result**

After successful deployment:

### **🌐 DNS (Automatic)**
- `argocd.pnats.cloud` → Points to your MetalLB IP
- **No manual DNS configuration needed!**

### **🔒 SSL (Automatic)**  
- Valid Let's Encrypt certificate for `argocd.pnats.cloud`
- **No manual certificate management needed!**

### **📱 ArgoCD Access**
- **URL**: `https://argocd.pnats.cloud`
- **Admin Password**: 
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
  ```

### **📊 Repository Access**
- ArgoCD can access your private repo with GitHub token
- All charts and applications will sync automatically
- Target-chart will deploy all platform components

## 🚀 **Single Command Deployment**

```bash
cd v0.2.0/platform
./run.sh deploy
```

**Enter your tokens when prompted, then sit back and watch everything deploy automatically!**

## 🔍 **Monitoring Deployment**

```bash
# Watch ArgoCD applications
kubectl get applications -n argocd -w

# Check DNS records created
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Check certificates
kubectl get certificates -n argocd

# Check LoadBalancer IP
kubectl get svc -n ingress-nginx
```

## 🎉 **What You Get**

- ✅ **Fully automated DNS management**
- ✅ **Automatic SSL certificates** 
- ✅ **Load balancing** via MetalLB
- ✅ **Private repository access** via GitHub token
- ✅ **Self-managed ArgoCD** at `https://argocd.pnats.cloud`
- ✅ **Complete GitOps platform** ready for application deployment

**Everything is automated - no manual configuration required!** 🎯