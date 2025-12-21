# Bitwarden Secrets Manager Setup Guide

Complete guide for migrating from SealedSecrets to Bitwarden Secrets Manager for centralized, secure secret management.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Initial Setup](#initial-setup)
4. [Kubernetes Operator Installation](#kubernetes-operator-installation)
5. [Creating and Managing Secrets](#creating-and-managing-secrets)
6. [Migration from SealedSecrets](#migration-from-sealedsecrets)
7. [Secret Rotation](#secret-rotation)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

## Overview

### Why Bitwarden Secrets Manager?

**Advantages over SealedSecrets:**
- ✅ Centralized web UI for secret management
- ✅ Automated synchronization to Kubernetes (180s interval)
- ✅ Built-in audit logging and access control
- ✅ Easy secret rotation without Git commits
- ✅ Team collaboration features
- ✅ Version history and rollback
- ✅ Free tier for small teams (up to 2 users, unlimited secrets)

**Trade-offs:**
- ⚠️ Requires external dependency (Bitwarden cloud or self-hosted)
- ⚠️ Internet connectivity required
- ⚠️ Minimum 180-second sync interval
- ⚠️ Not stored in Git (secrets live in Bitwarden)

### Architecture

```
Bitwarden Cloud
     │
     │ (API)
     ▼
Kubernetes Operator (sm-operator)
     │
     │ (watches BitwardenSecret CRDs)
     ▼
Kubernetes Secrets (auto-created)
     │
     ▼
Application Pods
```

## Prerequisites

### 1. Bitwarden Account Setup

**Create organization:**
```
1. Sign up at https://vault.bitwarden.com/
2. Create an organization (free tier is sufficient for home lab)
3. Enable Secrets Manager in organization settings
```

**Pricing (as of 2025):**
- **Free**: Unlimited secrets, 2 users, 3 projects, 3 machine accounts
- **Teams**: $6/user/month, up to 20 machine accounts
- **Enterprise**: $12/user/month, up to 50 machine accounts

For home Kubernetes clusters, **the free tier is typically sufficient**.

### 2. Required Tools

```bash
# Bitwarden CLI (optional but recommended)
brew install bitwarden-cli

# Or download from https://bitwarden.com/download/

# Helm (for operator installation)
brew install helm

# kubectl
brew install kubectl
```

### 3. Kubernetes Requirements

- Kubernetes 1.19+ (or compatible distribution)
- Helm 3+
- ArgoCD (already installed in this cluster)

## Initial Setup

### Step 1: Create a Secrets Manager Project

```
1. Log in to Bitwarden web vault (https://vault.bitwarden.com/)
2. Navigate to your organization
3. Go to Secrets Manager
4. Create a new project (e.g., "home-kubernetes")
5. Note the Organization ID (Settings → Organization ID)
```

### Step 2: Create Machine Account

```
1. In Secrets Manager, go to Machine Accounts
2. Create a new machine account (e.g., "k8s-cluster")
3. Grant access to the "home-kubernetes" project
4. Generate an access token
5. **IMPORTANT**: Copy and save the access token securely (shown only once)
```

**Access token format:**
```
0.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.yyyyyyyyyyyyyyyyyyyyyyyyyyyy...
```

### Step 3: Create Secrets in Bitwarden

**Using Web UI:**
```
1. Navigate to Secrets Manager → Secrets
2. Click "New Secret"
3. Fill in:
   - Name: postgres-password
   - Value: [your secure password]
   - Project: home-kubernetes
4. Save
```

**Using CLI (alternative):**
```bash
# Login to Bitwarden CLI
bw login

# Set session (optional for convenience)
export BW_SESSION="$(bw unlock --raw)"

# Create a secret
bw create secret \
  --organizationId <ORG_ID> \
  --projectId <PROJECT_ID> \
  --key postgres-password \
  --value "your-secure-password"
```

**Recommended secrets to create:**
- `postgres-password` (PostgreSQL root password)
- `postgres-non-root-password` (n8n database user password)
- `n8n-encryption-key` (n8n encryption key)
- `cloudflare-tunnel-token` (Cloudflare tunnel token)

## Kubernetes Operator Installation

### Option A: ArgoCD Application (Recommended)

**1. Create operator namespace:**
```bash
kubectl create namespace sm-operator-system
```

**2. Create access token secret:**
```bash
kubectl create secret generic bw-auth-token \
  -n sm-operator-system \
  --from-literal=token="<YOUR_ACCESS_TOKEN>"
```

**3. Create Helm values file:**

Create `manifests/bitwarden-operator/values.yaml`:

```yaml
# Bitwarden Secrets Manager Operator Configuration
# Organization ID from Bitwarden
organizationId: "your-org-id-here"

# Sync interval (minimum 180 seconds)
syncInterval: 300

# Cloud region (US or EU)
cloudRegion: "US"

# For self-hosted Bitwarden (optional)
# apiUrl: "https://your-bitwarden-server.com"
# identityUrl: "https://your-bitwarden-server.com/identity"

# Resource limits
resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

# Security context
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  allowPrivilegeEscalation: false
```

**4. Create ArgoCD Application:**

Create `manifests/applications/bitwarden-operator.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bitwarden-operator
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.bitwarden.com/
    chart: sm-operator
    targetRevision: 0.5.0
    helm:
      valuesObject:
        organizationId: "your-org-id-here"
        syncInterval: 300
        cloudRegion: "US"
        resources:
          limits:
            cpu: 500m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: sm-operator-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**5. Apply the application:**
```bash
kubectl apply -f manifests/applications/bitwarden-operator.yaml
```

### Option B: Manual Helm Installation

```bash
# Add Bitwarden Helm repository
helm repo add bitwarden https://charts.bitwarden.com/
helm repo update

# Install operator
helm install sm-operator bitwarden/sm-operator \
  --namespace sm-operator-system \
  --create-namespace \
  --set organizationId="<YOUR_ORG_ID>" \
  --set syncInterval=300
```

### Verify Installation

```bash
# Check operator pod
kubectl get pods -n sm-operator-system

# Expected output:
# NAME                                   READY   STATUS    RESTARTS   AGE
# sm-operator-controller-manager-xxx     2/2     Running   0          1m

# Check operator logs
kubectl logs -n sm-operator-system deployment/sm-operator-controller-manager -c manager
```

## Creating and Managing Secrets

### Step 1: Get Secret IDs from Bitwarden

**Using Web UI:**
```
1. Navigate to Secrets Manager → Secrets
2. Click on a secret
3. Copy the Secret ID from the URL or details panel
   Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**Using CLI:**
```bash
# List all secrets
bw list items --organizationid <ORG_ID>

# Get specific secret
bw get item <SECRET_NAME>
```

### Step 2: Create BitwardenSecret Custom Resource

**Example: PostgreSQL secrets**

Create `manifests/n8n/postgres-bitwarden-secret.yaml`:

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: postgres-secret
  namespace: n8n
spec:
  organizationId: "your-org-id-here"

  # Reference to the access token secret
  authToken:
    secretName: bw-auth-token
    secretNamespace: sm-operator-system

  # Target Kubernetes secret to create
  secretName: postgres-secret

  # Map Bitwarden secrets to Kubernetes secret keys
  map:
    - bwSecretId: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # postgres-user secret ID
      secretKeyName: POSTGRES_USER
    - bwSecretId: "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"  # postgres-password secret ID
      secretKeyName: POSTGRES_PASSWORD
    - bwSecretId: "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"  # postgres-db secret ID
      secretKeyName: POSTGRES_DB
    - bwSecretId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"  # non-root user secret ID
      secretKeyName: POSTGRES_NON_ROOT_USER
    - bwSecretId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"  # non-root password secret ID
      secretKeyName: POSTGRES_NON_ROOT_PASSWORD
```

**Example: n8n secrets**

Create `manifests/n8n/n8n-bitwarden-secret.yaml`:

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: n8n-secret
  namespace: n8n
spec:
  organizationId: "your-org-id-here"

  authToken:
    secretName: bw-auth-token
    secretNamespace: sm-operator-system

  secretName: n8n-secret

  map:
    - bwSecretId: "cccccccc-cccc-cccc-cccc-cccccccccccc"  # n8n-encryption-key secret ID
      secretKeyName: N8N_ENCRYPTION_KEY
```

**Example: Cloudflare tunnel**

Create `manifests/cloudflared/cloudflare-bitwarden-secret.yaml`:

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: cloudflare-tunnel-token
  namespace: cloudflared
spec:
  organizationId: "your-org-id-here"

  authToken:
    secretName: bw-auth-token
    secretNamespace: sm-operator-system

  secretName: cloudflare-tunnel-token

  map:
    - bwSecretId: "dddddddd-dddd-dddd-dddd-dddddddddddd"  # cloudflare-token secret ID
      secretKeyName: token
```

### Step 3: Apply BitwardenSecret Resources

```bash
# Apply all BitwardenSecret manifests
kubectl apply -f manifests/n8n/postgres-bitwarden-secret.yaml
kubectl apply -f manifests/n8n/n8n-bitwarden-secret.yaml
kubectl apply -f manifests/cloudflared/cloudflare-bitwarden-secret.yaml

# Verify secrets were created
kubectl get secrets -n n8n
kubectl get secrets -n cloudflared

# Check BitwardenSecret status
kubectl get bitwardensecrets -A
```

### Step 4: Verify Secret Synchronization

```bash
# Check if Kubernetes secret was created
kubectl get secret postgres-secret -n n8n

# View secret keys (not values)
kubectl get secret postgres-secret -n n8n -o jsonpath='{.data}' | jq 'keys'

# Check BitwardenSecret resource status
kubectl describe bitwardensecret postgres-secret -n n8n
```

## Migration from SealedSecrets

### Migration Strategy

**Parallel operation approach (recommended):**

1. Install Bitwarden Operator alongside SealedSecrets
2. Create secrets in Bitwarden
3. Deploy BitwardenSecret resources
4. Update deployments to use new secrets (or keep same secret names)
5. Verify all applications work correctly
6. Remove SealedSecret resources
7. (Optional) Uninstall sealed-secrets controller

### Step-by-Step Migration

#### 1. Extract Current Secret Values

**For PostgreSQL:**
```bash
# Extract current secret values
kubectl get secret postgres-secret -n n8n -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'

# Save these values to create in Bitwarden
```

**For n8n:**
```bash
kubectl get secret n8n-secret -n n8n -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'
```

**For Cloudflare:**
```bash
kubectl get secret cloudflare-tunnel-token -n cloudflared -o json | \
  jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'
```

#### 2. Create Secrets in Bitwarden

Using the extracted values, create corresponding secrets in Bitwarden Secrets Manager:

```
1. Log in to Bitwarden web vault
2. Navigate to Secrets Manager
3. For each extracted value, create a new secret:
   - Name: descriptive name (e.g., "postgres-password")
   - Value: the extracted value
   - Project: home-kubernetes
4. Note the secret IDs for each created secret
```

#### 3. Create BitwardenSecret Resources

Create BitwardenSecret manifests (as shown in previous section) with the noted secret IDs.

#### 4. Deploy BitwardenSecret Resources

```bash
# Apply BitwardenSecret manifests
kubectl apply -f manifests/n8n/postgres-bitwarden-secret.yaml
kubectl apply -f manifests/n8n/n8n-bitwarden-secret.yaml
kubectl apply -f manifests/cloudflared/cloudflare-bitwarden-secret.yaml

# Wait for synchronization (default 300s, or check status)
kubectl get bitwardensecrets -A

# Verify new secrets exist
kubectl get secrets -n n8n
kubectl get secrets -n cloudflared
```

#### 5. Test Applications

```bash
# Restart deployments to pick up new secrets
kubectl rollout restart deployment/postgres -n n8n
kubectl rollout restart deployment/n8n -n n8n
kubectl rollout restart deployment/cloudflared -n cloudflared

# Check pod status
kubectl get pods -n n8n
kubectl get pods -n cloudflared

# Check application logs for errors
kubectl logs -n n8n deployment/n8n --tail=50
kubectl logs -n n8n deployment/postgres --tail=50
kubectl logs -n cloudflared deployment/cloudflared --tail=50
```

#### 6. Remove SealedSecrets (after verification)

```bash
# Delete SealedSecret manifests from Git
git rm manifests/n8n/postgres-sealed-secret.yaml
git rm manifests/n8n/n8n-sealed-secret.yaml
git rm manifests/cloudflared/cloudflare-sealed-secret.yaml

# Commit changes
git add -A
git commit -m "chore: migrate secrets to Bitwarden Secrets Manager"
git push

# (Optional) Uninstall sealed-secrets controller
kubectl delete -f manifests/applications/sealed-secrets.yaml
```

## Secret Rotation

### Rotating Secrets via Bitwarden Web UI

**Advantage:** No Kubernetes commands needed, no Git commits required.

**Steps:**
```
1. Log in to Bitwarden web vault
2. Navigate to Secrets Manager → Secrets
3. Find the secret to rotate (e.g., "postgres-password")
4. Click "Edit"
5. Update the "Value" field with new password/key
6. Save
7. Wait for sync interval (default: 300 seconds)
   - Or force sync by restarting operator:
     kubectl rollout restart deployment/sm-operator-controller-manager -n sm-operator-system
8. Kubernetes secret is automatically updated
```

**For database passwords, update the database first:**
```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# Update password in database
kubectl exec -n n8n deployment/postgres -- \
  psql -U postgres -c "ALTER USER n8n WITH PASSWORD '${NEW_PASSWORD}';"

# Update in Bitwarden UI with the new password
# Wait for sync
# Restart application pods
kubectl rollout restart deployment/n8n -n n8n
```

### Rotating Secrets via Bitwarden CLI

```bash
# Login
bw login
export BW_SESSION="$(bw unlock --raw)"

# Get secret ID
SECRET_ID=$(bw list items --organizationid <ORG_ID> | \
  jq -r '.[] | select(.name=="postgres-password") | .id')

# Update secret value
NEW_PASSWORD=$(openssl rand -base64 32)
bw edit item $SECRET_ID --value "$NEW_PASSWORD"

# Sync will happen automatically within 300 seconds
```

### Emergency Secret Rotation

If a secret is compromised:

```bash
# 1. Immediately update in Bitwarden (Web UI or CLI)

# 2. Force immediate sync by restarting operator
kubectl rollout restart deployment/sm-operator-controller-manager -n sm-operator-system

# 3. Wait for operator to restart (usually < 30 seconds)
kubectl rollout status deployment/sm-operator-controller-manager -n sm-operator-system

# 4. Verify secret updated
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d

# 5. Restart affected applications
kubectl rollout restart deployment/<app-name> -n <namespace>
```

## Troubleshooting

### Operator Not Syncing Secrets

**Check operator logs:**
```bash
kubectl logs -n sm-operator-system deployment/sm-operator-controller-manager -c manager --tail=100
```

**Common issues:**
- Invalid access token: Recreate token and update secret
- Network connectivity: Check cluster internet access
- Incorrect organization ID: Verify in Bitwarden settings
- Secret ID not found: Verify secret exists and ID is correct

### BitwardenSecret Shows Error Status

```bash
# Check detailed status
kubectl describe bitwardensecret <name> -n <namespace>

# Look for error messages in Events section
```

**Common errors:**
- `Secret not found`: Secret ID doesn't exist in Bitwarden
- `Unauthorized`: Access token invalid or expired
- `Organization mismatch`: Organization ID incorrect

### Secret Not Updating After Change

**Possible causes:**
1. Sync interval not elapsed (wait 300 seconds)
2. Operator pod crashed (check with `kubectl get pods -n sm-operator-system`)
3. Network issue (check operator logs)

**Solutions:**
```bash
# Force sync by restarting operator
kubectl rollout restart deployment/sm-operator-controller-manager -n sm-operator-system

# Or delete and recreate BitwardenSecret
kubectl delete bitwardensecret <name> -n <namespace>
kubectl apply -f manifests/<app>/bitwarden-secret.yaml
```

### Access Token Expired

**Symptoms:**
- Operator logs show authentication errors
- BitwardenSecret resources show "Unauthorized" status

**Solution:**
```bash
# 1. Generate new access token in Bitwarden web UI
# 2. Update Kubernetes secret
kubectl create secret generic bw-auth-token \
  -n sm-operator-system \
  --from-literal=token="<NEW_TOKEN>" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart operator
kubectl rollout restart deployment/sm-operator-controller-manager -n sm-operator-system
```

## Best Practices

### 1. Secret Organization

**Use descriptive names:**
```
✅ Good: postgres-n8n-password, n8n-encryption-key-prod
❌ Bad: secret1, password, key
```

**Group by project:**
- Create separate projects for different environments (if applicable)
- Use consistent naming conventions

### 2. Access Control

**Principle of least privilege:**
- Create separate machine accounts for different clusters/environments
- Grant each machine account access only to necessary projects
- Regularly audit machine account access

**Machine account naming:**
```
✅ Good: k8s-home-cluster, k8s-prod-cluster
❌ Bad: machine1, account
```

### 3. Secret Rotation Schedule

**Recommended rotation intervals:**
- Database passwords: Every 90 days
- API keys/tokens: Every 90 days or on personnel changes
- Encryption keys: Annually (requires application migration)

**Set calendar reminders:**
```bash
# Example: Add to cron for monthly reminder
# 0 9 1 * * echo "Reminder: Rotate Kubernetes secrets" | mail -s "Secret Rotation" admin@example.com
```

### 4. Monitoring and Auditing

**Monitor operator health:**
```bash
# Create alert for operator pod crashes
kubectl get events -n sm-operator-system --watch

# Monitor sync errors
kubectl get bitwardensecrets -A -o json | \
  jq -r '.items[] | select(.status.conditions[]?.status=="False") | "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[].message)"'
```

**Audit secret access:**
- Regularly review Bitwarden audit logs (Enterprise feature)
- Monitor Kubernetes secret access via audit logs (if enabled)

### 5. Backup and Disaster Recovery

**Back up Bitwarden data:**
- Enable Bitwarden export feature
- Store exports in secure, encrypted location
- Test restoration procedures

**Maintain emergency access:**
- Keep sealed-secrets master key backup (during migration)
- Document manual secret creation process
- Maintain offline copy of critical credentials

### 6. Documentation

**Document all secrets:**
- Maintain inventory of secrets and their purposes
- Document secret rotation procedures
- Keep machine account and token information secure

**Update runbooks:**
- Include Bitwarden-specific troubleshooting steps
- Document emergency procedures
- Train team members on new workflow

## Comparison: SealedSecrets vs Bitwarden

| Aspect | SealedSecrets | Bitwarden Secrets Manager |
|--------|---------------|---------------------------|
| **Cost** | Free (open source) | Free (2 users) / $6/user/month |
| **Deployment** | In-cluster only | Cloud or self-hosted |
| **UI** | None (CLI only) | Web UI + CLI |
| **Audit Logs** | Git history only | Built-in (Enterprise) |
| **Rotation** | Manual (Git commit) | Web UI (no Git) |
| **Team Collaboration** | Git-based | Native features |
| **Offline Operation** | ✅ Fully supported | ❌ Requires internet |
| **Learning Curve** | Low | Medium |
| **External Dependencies** | None | Bitwarden service |
| **Auto-sync** | On Git push | Every 180-300s |
| **Backup** | Git repository | Bitwarden export |

## References

- [Bitwarden Secrets Manager Documentation](https://bitwarden.com/help/secrets-manager-kubernetes-operator/)
- [Bitwarden Secrets Manager Pricing](https://bitwarden.com/help/secrets-manager-plans/)
- [Bitwarden CLI Documentation](https://bitwarden.com/help/cli/)
- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/)
