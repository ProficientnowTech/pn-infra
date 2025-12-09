# ArgoCD Notifications Setup Guide

This guide will help you set up Slack and email notifications for ArgoCD.

---

## Overview

ArgoCD notifications are now configured to send alerts for:
- ✅ Successful deployments
- ⚠️ Health degradation
- ❌ Sync failures
- 🔄 Sync operations in progress
- ❓ Unknown sync status

**Notification channels configured:**
- **Slack**: `platform-alerts` channel
- **Email**: `platform-team@pnats.cloud`

---

## Step 1: Create Slack Bot

### 1.1 Create Slack App

1. Go to https://api.slack.com/apps
2. Click **"Create New App"** → **"From scratch"**
3. App Name: `ArgoCD Notifications`
4. Workspace: Select your workspace
5. Click **"Create App"**

### 1.2 Configure Bot Permissions

1. Navigate to **"OAuth & Permissions"** in the left sidebar
2. Scroll to **"Scopes"** → **"Bot Token Scopes"**
3. Add the following scopes:
   - `chat:write` - Send messages
   - `chat:write.public` - Send messages to public channels
   - `channels:read` - View basic channel info

### 1.3 Install App to Workspace

1. Scroll up to **"OAuth Tokens for Your Workspace"**
2. Click **"Install to Workspace"**
3. Review permissions and click **"Allow"**
4. **Copy the Bot User OAuth Token** (starts with `xoxb-`)
   - Keep this secure! You'll need it in Step 3

### 1.4 Create Slack Channel

1. In Slack, create a new channel: `#platform-alerts`
2. Invite the bot to the channel:
   ```
   /invite @ArgoCD Notifications
   ```

---

## Step 2: Configure Email (Gmail Example)

### 2.1 Create App Password (Gmail)

If using Gmail with 2FA enabled:

1. Go to https://myaccount.google.com/apppasswords
2. Sign in to your Google Account
3. Select app: **Mail**
4. Select device: **Other** (enter "ArgoCD")
5. Click **Generate**
6. **Copy the 16-character password** (no spaces)

### 2.2 Alternative: Use Generic SMTP

If not using Gmail, you'll need:
- SMTP host (e.g., `smtp.example.com`)
- SMTP port (usually `587` for TLS)
- SMTP username
- SMTP password

Update the values.yaml `service.email` section with your SMTP details.

---

## Step 3: Create Kubernetes Secret

You have two options: **Sealed Secrets** (recommended) or **Manual Secret**

### Option A: Using Sealed Secrets (Recommended)

#### 3.1 Create Secret Manifest

```bash
# Create a temporary secret file
cat > argocd-notifications-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
type: Opaque
stringData:
  slack-token: "xoxb-YOUR-SLACK-BOT-TOKEN"
  email-username: "your-email@gmail.com"
  email-password: "YOUR-16-CHAR-APP-PASSWORD"
EOF
```

#### 3.2 Seal the Secret

```bash
# Seal the secret
kubeseal --controller-namespace=sealed-secrets \
  --controller-name=sealed-secrets \
  --format=yaml \
  < argocd-notifications-secret.yaml \
  > argocd-notifications-sealed-secret.yaml

# Delete the plaintext file
rm argocd-notifications-secret.yaml
```

#### 3.3 Apply Sealed Secret

```bash
# Apply the sealed secret
kubectl apply -f argocd-notifications-sealed-secret.yaml

# Store in Git
mv argocd-notifications-sealed-secret.yaml \
  v0.2.0/platform/charts/argocd-self/sealed-secrets/
```

### Option B: Manual Secret (Testing Only)

**WARNING: Only use this for testing. Never commit to Git!**

```bash
kubectl create secret generic argocd-notifications-secret \
  --namespace=argocd \
  --from-literal=slack-token="xoxb-YOUR-SLACK-BOT-TOKEN" \
  --from-literal=email-username="your-email@gmail.com" \
  --from-literal=email-password="YOUR-16-CHAR-APP-PASSWORD"
```

---

## Step 4: Update ArgoCD Values

The notifications configuration is already in `values.yaml`. You just need to update:

### 4.1 Update Slack Channel

If you named your Slack channel something other than `platform-alerts`, update line 330:

```yaml
subscriptions:
  - recipients:
    - slack:your-channel-name  # Change this to match your channel
```

### 4.2 Update Email Address

Update line 338 with your team email:

```yaml
  - recipients:
    - slack:platform-alerts
    - email:your-team@your-domain.com  # Change this
```

### 4.3 Update ArgoCD URL (if different)

Update line 323 if your ArgoCD URL is different:

```yaml
context:
  argocdUrl: https://argocd.pnats.cloud  # Update if different
```

---

## Step 5: Deploy ArgoCD with Notifications

```bash
# From the platform directory
cd v0.2.0/platform

# Update ArgoCD
helm upgrade --install argocd-self charts/argocd-self \
  --namespace argocd \
  --create-namespace \
  --values charts/argocd-self/values.yaml

# Or use ArgoCD to sync itself
kubectl patch application argocd-self -n argocd \
  --type merge \
  -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {"revision": "HEAD"}}}'
```

---

## Step 6: Verify Notifications

### 6.1 Check Notification Controller

```bash
# Check notifications controller is running
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-notifications-controller

# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller --tail=50
```

### 6.2 Check Secret is Loaded

```bash
# Verify secret exists
kubectl get secret argocd-notifications-secret -n argocd

# Check if notifications controller can read it
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller | grep -i "secret"
```

### 6.3 Test Notifications

#### Manual Test - Trigger a Sync

```bash
# Sync any application to trigger notifications
kubectl patch application <app-name> -n argocd \
  --type merge \
  -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {"revision": "HEAD"}}}'

# Watch for notification in Slack #platform-alerts channel
# and check your email
```

#### Check Notification Status

```bash
# View notification delivery status
kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.operationState.phase}{"\n"}{end}'
```

---

## Troubleshooting

### Issue: Notifications not sending

**Check 1: Verify Secret**
```bash
kubectl get secret argocd-notifications-secret -n argocd -o yaml
```

**Check 2: Verify ConfigMap**
```bash
kubectl get configmap argocd-notifications-cm -n argocd -o yaml
```

**Check 3: Controller Logs**
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller --tail=100
```

### Issue: Slack bot not posting

**Possible causes:**
1. Bot not invited to channel → Run `/invite @ArgoCD Notifications` in Slack
2. Invalid token → Regenerate and update secret
3. Missing permissions → Add `chat:write` and `chat:write.public` scopes

**Verify bot token:**
```bash
# Test with curl
SLACK_TOKEN=$(kubectl get secret argocd-notifications-secret -n argocd -o jsonpath='{.data.slack-token}' | base64 -d)

curl -X POST https://slack.com/api/auth.test \
  -H "Authorization: Bearer $SLACK_TOKEN"
```

### Issue: Email not sending

**Common causes:**
1. Wrong SMTP credentials
2. App password not generated (for Gmail)
3. 2FA blocking access
4. Firewall blocking port 587

**Test SMTP connection:**
```bash
# Install swaks for testing
sudo apt-get install swaks

# Test email
swaks --to recipient@example.com \
  --from argocd@pnats.cloud \
  --server smtp.gmail.com:587 \
  --auth LOGIN \
  --auth-user your-email@gmail.com \
  --auth-password "YOUR-APP-PASSWORD" \
  --tls
```

### Issue: Wrong Slack channel

**Fix channel name:**
```bash
# Edit the subscription in values.yaml
# Then update ArgoCD:
helm upgrade argocd-self charts/argocd-self \
  --namespace argocd \
  --values charts/argocd-self/values.yaml
```

---

## Notification Examples

### Slack Notification

When an application deploys successfully, you'll see:

```
[ArgoCD Notifications]
Application: grafana

✅ Sync Status: Synced
✅ Health: Healthy
📦 Revision: abc123def

View in ArgoCD →
```

### Email Notification

```
Subject: ✅ Application grafana deployed successfully

Application grafana has been successfully deployed.

Sync Status: Synced
Health: Healthy
Revision: abc123def
```

---

## Customization

### Add More Channels

To send notifications to multiple Slack channels:

```yaml
subscriptions:
  # Critical alerts to #platform-alerts
  - recipients:
    - slack:platform-alerts
    triggers:
    - on-sync-failed
    - on-health-degraded

  # All events to #platform-notifications
  - recipients:
    - slack:platform-notifications
    triggers:
    - on-deployed
    - on-sync-succeeded
    - on-sync-running
```

### Filter by Application Label

Send notifications only for production apps:

```yaml
subscriptions:
  - recipients:
    - slack:production-alerts
    selector: env=production
    triggers:
    - on-sync-failed
    - on-health-degraded
```

### Add More Email Recipients

```yaml
subscriptions:
  - recipients:
    - email:team-lead@pnats.cloud
    - email:devops@pnats.cloud
    - email:platform-team@pnats.cloud
    triggers:
    - on-sync-failed
```

---

## Security Best Practices

1. ✅ **Use Sealed Secrets** - Never commit plaintext secrets to Git
2. ✅ **Use App Passwords** - Don't use your main Gmail password
3. ✅ **Rotate Tokens** - Regularly rotate Slack tokens and email passwords
4. ✅ **Limit Permissions** - Only grant necessary Slack bot scopes
5. ✅ **Use Vault** - For production, migrate to Vault + External Secrets

---

## Next Steps

1. **Set up Vault** - Migrate from Sealed Secrets to Vault
2. **Configure External Secrets** - Auto-sync secrets from Vault
3. **Add PagerDuty** - For critical alerts
4. **Add Webhook** - Integrate with incident management
5. **Custom Templates** - Create application-specific notification templates

---

## References

- [ArgoCD Notifications Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/)
- [Slack API Documentation](https://api.slack.com/)
- [Gmail App Passwords](https://support.google.com/accounts/answer/185833)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)

---

**Last Updated**: 2025-11-20
**Status**: Ready for deployment
