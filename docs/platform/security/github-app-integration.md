# GitHub App Integration (Shared Platform Credential)

Platform services (ArgoCD automations, Backstage catalog processors, future CI bots) all need
GitHub access. Instead of long-lived PATs per service, create a single organization-owned
GitHub App and reuse its installation token anywhere we currently ask for a “GitHub token”.

> **Important:** The bootstrap scripts still expect a raw token string (e.g. `BACKSTAGE_GITHUB_TOKEN`).
> Generate an installation access token from the GitHub App and paste that value into the
> corresponding environment variable. The same token can be copied to multiple variables if
> several specs reference the same credential.

## 1. Create the GitHub App
Use the template below when filling out the “New GitHub App” form. Update the org slug and contact info as needed.

```markdown
### pn-platform-bot
- **Description:** Automation identity for the PN platform (ArgoCD, Backstage, CI jobs). Grants scoped repo access without user PATs.
- **Homepage URL:** https://github.com/<your-org>
- **Callback URL:** _leave blank_ (only required if you plan to implement OAuth flows with this App).
- **Webhook URL:** https://argocd.pnats.cloud/api/webhook (optional). Disable webhooks entirely if you do not need event callbacks.
- **Webhook secret:** _leave blank_ unless you enabled webhooks.
```

Steps:
1. Navigate to **Organization Settings → Developer settings → GitHub Apps → New GitHub App**.
2. Fill in the fields above. For most platform automation, you can skip callback/webhook URLs. If you later use the App for OAuth login (e.g., Backstage SSO), set the callback URL to your OAuth handler instead.
3. Configure permissions:
   - **GitHub App name**: `pn-platform-bot` (or similar).
   - **Homepage URL**: https://github.com/<org>.
   - **Webhook**: optional (disable unless needed).
   - **Permissions** (minimum):
     - Repository → Contents: **Read & write**
     - Repository → Metadata: **Read-only** (automatic)
     - Repository → Pull requests: **Read & write** (if Backstage needs PR automation)
     - Repository → Administration: **Read & write** (only if ArgoCD auto-creates repos)
   - **Subscribe to events**: at least “Pull request” if you enabled that permission.
3. Click **Create GitHub App**.

## 2. Install the App
1. After creation, click **Install App**.
2. Choose “Only select repositories” and add every repo the platform needs (e.g. `pn-infra`).
3. Confirm installation.

## 3. Generate the Private Key & IDs
1. In the App settings, click **Generate a private key**. Save the downloaded `.pem` in your
   secure vault (1Password, Bitwarden, etc.).
2. Note the **App ID** and the **Installation ID** shown in the URL
   (`.../installations/<installation_id>`). Record both in your password manager.

## 4. Mint an Installation Token
Use the helper script (`platform/scripts/github-app-token.sh`) to exchange the private key
for a short-lived token whenever you need to refresh secrets:

```bash
platform/scripts/github-app-token.sh \
  --app-id <app-id> \
  --installation-id <installation-id> \
  --private-key /secure/path/pn-platform-bot.pem \
  --output /tmp/github-token.txt

TOKEN=$(cat /tmp/github-token.txt)
```

Copy the resulting token into every bootstrap variable that asks for a GitHub token
(currently `BACKSTAGE_GITHUB_TOKEN`). Because installation tokens expire after 60 minutes,
store the command (or script) centrally so you can mint a fresh token whenever you rerun
the bootstrap renderer.

> Tip: pipe the `token` to your clipboard tool (e.g., `pbcopy`, `xclip`) before pasting into
> `.env.local`.

## 5. Reuse Across Applications
- **Backstage** (`BACKSTAGE_GITHUB_TOKEN`)
- Any future charts that add GitHub automation (ArgoCD, Tekton, etc.) can reuse the same app;
  simply copy the same token into the requested environment variable before bootstrapping.

If you enable GitHub OAuth login for Backstage or ArgoCD, the OAuth client ID/secret can also
come from this App to keep everything centralized.

## 6. Rotation
- Regenerate the private key if compromised (GitHub App settings → “Generate new private key”).
- Installation tokens are short-lived by design; create a new one every time you re-run the
  bootstrap script or automation that needs GitHub access.
