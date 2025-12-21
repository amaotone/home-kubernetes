# Secret Management Guide

This guide explains how to securely manage secrets in this GitOps-managed Kubernetes cluster using Sealed Secrets.

## Overview

**Sealed Secrets** allows you to encrypt secrets that can be safely committed to Git. The sealed-secrets controller running in the cluster decrypts them into regular Kubernetes Secrets.

## Architecture

```
Developer                  Git Repository              Kubernetes Cluster
    |                            |                            |
    | 1. Generate secret         |                            |
    |--------------------------->|                            |
    |                            |                            |
    | 2. Seal with kubeseal      |                            |
    |<---------------------------|                            |
    |                            |                            |
    | 3. Commit SealedSecret     |                            |
    |--------------------------->|                            |
    |                            |                            |
    |                            | 4. ArgoCD syncs            |
    |                            |--------------------------->|
    |                            |                            |
    |                            |    5. Controller decrypts  |
    |                            |    (creates regular Secret)|
    |                            |                            |
```

## Prerequisites

### Install kubeseal CLI

**macOS:**
```bash
brew install kubeseal
```

**Linux:**
```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.26.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Verify sealed-secrets controller is running

```bash
kubectl get pods -n sealed-secrets
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
sealed-secrets-controller-xxx     1/1     Running   0          XXd
```

## Secret Generation Procedures

### 1. PostgreSQL Secrets

**Generate random passwords:**
```bash
# Generate strong random passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
POSTGRES_NON_ROOT_PASSWORD=$(openssl rand -base64 32)

echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "POSTGRES_NON_ROOT_PASSWORD: $POSTGRES_NON_ROOT_PASSWORD"
```

**Create and seal the secret:**
```bash
kubectl create secret generic postgres-secret \
  --namespace=n8n \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_DB=n8n \
  --from-literal=POSTGRES_NON_ROOT_USER=n8n \
  --from-literal=POSTGRES_NON_ROOT_PASSWORD="${POSTGRES_NON_ROOT_PASSWORD}" \
  --dry-run=client \
  -o yaml | \
kubeseal \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  > manifests/n8n/postgres-sealed-secret.yaml
```

**Store passwords securely:**
```bash
# Save to a password manager or secure vault
# DO NOT commit the plain passwords to Git
cat << EOF > /tmp/postgres-credentials.txt
POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
POSTGRES_NON_ROOT_PASSWORD: ${POSTGRES_NON_ROOT_PASSWORD}
EOF

# Store this file securely (e.g., 1Password, LastPass, Bitwarden)
echo "Save /tmp/postgres-credentials.txt to your password manager"
echo "Then delete the file: rm /tmp/postgres-credentials.txt"
```

### 2. n8n Encryption Key

**Generate encryption key:**
```bash
# Generate a secure 256-bit encryption key
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)

echo "N8N_ENCRYPTION_KEY: $N8N_ENCRYPTION_KEY"
```

**Create and seal the secret:**
```bash
kubectl create secret generic n8n-secret \
  --namespace=n8n \
  --from-literal=N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}" \
  --dry-run=client \
  -o yaml | \
kubeseal \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  > manifests/n8n/n8n-sealed-secret.yaml
```

**Store key securely:**
```bash
# Save to password manager
cat << EOF > /tmp/n8n-credentials.txt
N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
EOF

echo "Save /tmp/n8n-credentials.txt to your password manager"
echo "Then delete the file: rm /tmp/n8n-credentials.txt"
```

### 3. Cloudflare Tunnel Token

**Obtain token from Cloudflare Dashboard:**
1. Go to https://one.dash.cloudflare.com/
2. Navigate to Networks → Tunnels
3. Create or select your tunnel
4. Copy the tunnel token

**Create and seal the secret:**
```bash
# Replace YOUR_TUNNEL_TOKEN with the actual token
CLOUDFLARE_TOKEN="YOUR_TUNNEL_TOKEN"

kubectl create secret generic cloudflare-tunnel-token \
  --namespace=cloudflared \
  --from-literal=token="${CLOUDFLARE_TOKEN}" \
  --dry-run=client \
  -o yaml | \
kubeseal \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  > manifests/cloudflared/cloudflare-sealed-secret.yaml
```

**Store token securely:**
```bash
cat << EOF > /tmp/cloudflare-credentials.txt
CLOUDFLARE_TUNNEL_TOKEN: ${CLOUDFLARE_TOKEN}
EOF

echo "Save /tmp/cloudflare-credentials.txt to your password manager"
echo "Then delete the file: rm /tmp/cloudflare-credentials.txt"
```

## Verification

### Check SealedSecret resources

```bash
# List all SealedSecrets
kubectl get sealedsecrets -A

# Check specific SealedSecret
kubectl get sealedsecret postgres-secret -n n8n -o yaml
```

### Verify decrypted Secrets

```bash
# Check if regular Secret was created from SealedSecret
kubectl get secret postgres-secret -n n8n
kubectl get secret n8n-secret -n n8n
kubectl get secret cloudflare-tunnel-token -n cloudflared

# View secret keys (not values)
kubectl get secret postgres-secret -n n8n -o jsonpath='{.data}' | jq 'keys'
```

### Test application connectivity

```bash
# Check n8n pods
kubectl get pods -n n8n

# Check logs for authentication errors
kubectl logs -n n8n deployment/n8n
kubectl logs -n n8n deployment/postgres
```

## Secret Rotation

### Why Rotate Secrets?

- Comply with security policies
- Respond to suspected compromise
- Follow least-privilege principle
- Meet regulatory requirements

### Rotation Frequency

**Recommended schedule:**
- **Database passwords:** Every 90 days
- **API keys/tokens:** Every 90 days or when personnel changes
- **Encryption keys:** Annually (requires data re-encryption)

### Rotation Procedure

#### 1. Database Password Rotation

```bash
# Step 1: Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# Step 2: Update password in database (exec into postgres pod)
kubectl exec -n n8n deployment/postgres -- psql -U postgres -c \
  "ALTER USER n8n WITH PASSWORD '${NEW_PASSWORD}';"

# Step 3: Create new SealedSecret with new password
kubectl create secret generic postgres-secret \
  --namespace=n8n \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD="$(kubectl get secret postgres-secret -n n8n -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)" \
  --from-literal=POSTGRES_DB=n8n \
  --from-literal=POSTGRES_NON_ROOT_USER=n8n \
  --from-literal=POSTGRES_NON_ROOT_PASSWORD="${NEW_PASSWORD}" \
  --dry-run=client \
  -o yaml | \
kubeseal \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  > manifests/n8n/postgres-sealed-secret.yaml

# Step 4: Commit and push
git add manifests/n8n/postgres-sealed-secret.yaml
git commit -m "chore: rotate PostgreSQL non-root password"
git push

# Step 5: Wait for ArgoCD to sync (or manually sync)
argocd app sync n8n

# Step 6: Restart n8n to pick up new secret
kubectl rollout restart deployment/n8n -n n8n

# Step 7: Store new password in password manager
```

#### 2. Cloudflare Token Rotation

```bash
# Step 1: Create new tunnel token in Cloudflare Dashboard

# Step 2: Create new SealedSecret
kubectl create secret generic cloudflare-tunnel-token \
  --namespace=cloudflared \
  --from-literal=token="${NEW_CLOUDFLARE_TOKEN}" \
  --dry-run=client \
  -o yaml | \
kubeseal \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  > manifests/cloudflared/cloudflare-sealed-secret.yaml

# Step 3: Commit and push
git add manifests/cloudflared/cloudflare-sealed-secret.yaml
git commit -m "chore: rotate Cloudflare tunnel token"
git push

# Step 4: Sync and restart
argocd app sync cloudflared
kubectl rollout restart deployment/cloudflared -n cloudflared

# Step 5: Revoke old token in Cloudflare Dashboard
```

#### 3. n8n Encryption Key Rotation

⚠️ **WARNING:** Rotating the n8n encryption key requires re-encrypting all workflow credentials. This is a complex operation.

**Recommended approach:**
1. Back up the n8n database
2. Migrate credentials using n8n's built-in migration tools
3. Follow n8n documentation: https://docs.n8n.io/hosting/environment-variables/configuration-methods/#encryption-key

## Troubleshooting

### SealedSecret not creating Secret

**Check controller logs:**
```bash
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller
```

**Common issues:**
- Wrong namespace in SealedSecret
- Mismatched controller name/namespace in kubeseal command
- SealedSecret created with different cluster's public key

### Re-seal with correct parameters

```bash
# Fetch current controller public key
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  > /tmp/sealed-secrets-cert.pem

# Re-seal using saved cert
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --dry-run=client \
  -o yaml | \
kubeseal --cert=/tmp/sealed-secrets-cert.pem \
  --format=yaml
```

### Secret exists but pods can't use it

**Check RBAC permissions:**
```bash
kubectl auth can-i get secrets --as=system:serviceaccount:n8n:default -n n8n
```

**Check secret mount in pod:**
```bash
kubectl get pod <pod-name> -n n8n -o yaml | grep -A 10 volumes
```

### Backup sealed-secrets controller key

⚠️ **CRITICAL:** Back up the sealed-secrets master key. Without it, you cannot decrypt SealedSecrets after cluster rebuild.

```bash
# Export master key
kubectl get secret -n sealed-secrets sealed-secrets-key -o yaml > sealed-secrets-master-key.yaml

# Store this file in a secure location (NOT in Git)
# Recommended: encrypted USB drive, secure vault, offline storage
```

**Restore master key:**
```bash
# On new cluster, restore before deploying SealedSecrets
kubectl apply -f sealed-secrets-master-key.yaml
```

## Security Best Practices

### DO

✅ Always use `kubeseal` to encrypt secrets before committing
✅ Store plain secrets in a password manager
✅ Rotate secrets regularly (every 90 days minimum)
✅ Back up the sealed-secrets controller master key
✅ Use strong random passwords (32+ characters)
✅ Limit secret access with RBAC
✅ Use separate secrets for different environments (dev/staging/prod)
✅ Audit secret access logs

### DON'T

❌ Never commit plain Kubernetes Secret resources to Git
❌ Never hardcode secrets in deployment manifests
❌ Never share secrets via email or chat
❌ Never reuse passwords across services
❌ Never skip secret rotation after personnel changes
❌ Never store backup keys in the same location as the cluster
❌ Never use weak or predictable passwords

## Emergency Procedures

### Suspected Secret Compromise

1. **Immediately rotate affected secret**
2. **Check audit logs for unauthorized access**
3. **Review recent Git commits for leaked secrets**
4. **Scan for malicious pods/containers**
5. **Notify security team**
6. **Document incident in post-mortem**

### Lost sealed-secrets Master Key

If you lose the sealed-secrets master key:

1. **All SealedSecrets become undecryptable**
2. **Must regenerate all secrets from password manager**
3. **Must re-seal all secrets with new controller**
4. **Update all SealedSecret manifests in Git**

**Prevention:** Always maintain offline backups of the master key.

## References

- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [kubeseal CLI Reference](https://github.com/bitnami-labs/sealed-secrets#usage)
- [n8n Security Best Practices](https://docs.n8n.io/hosting/environment-variables/security/)
- [OWASP Secret Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
