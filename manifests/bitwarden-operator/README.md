# Bitwarden Secrets Manager Operator

This directory contains configuration for the Bitwarden Secrets Manager Kubernetes Operator.

## Setup Instructions

### 1. Create Bitwarden Organization and Machine Account

Follow the detailed setup guide: [docs/bitwarden-secrets-manager-setup.md](../../docs/bitwarden-secrets-manager-setup.md)

Summary:
1. Create Bitwarden organization
2. Enable Secrets Manager
3. Create a project (e.g., "home-kubernetes")
4. Create machine account with access to the project
5. Generate and save access token

### 2. Create Access Token Secret

**IMPORTANT**: Do this BEFORE deploying the operator application.

```bash
# Create namespace
kubectl create namespace sm-operator-system

# Create access token secret
kubectl create secret generic bw-auth-token \
  -n sm-operator-system \
  --from-literal=token="YOUR_ACCESS_TOKEN_HERE"
```

The access token format looks like:
```
0.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.yyyyyyyyyyyyyyyyyyyyyyyyyyyy...
```

### 3. Update ArgoCD Application

Edit `manifests/applications/bitwarden-operator.yaml` and replace:
```yaml
organizationId: "REPLACE_WITH_YOUR_ORG_ID"
```

Get your Organization ID from: Bitwarden Web Vault → Organization Settings → Organization ID

### 4. Deploy Operator

```bash
# Apply ArgoCD application
kubectl apply -f manifests/applications/bitwarden-operator.yaml

# Wait for deployment
kubectl wait --for=condition=available --timeout=300s \
  deployment/sm-operator-controller-manager -n sm-operator-system

# Verify installation
kubectl get pods -n sm-operator-system
```

Expected output:
```
NAME                                              READY   STATUS    RESTARTS   AGE
sm-operator-controller-manager-xxxxxxxxxx-xxxxx   2/2     Running   0          1m
```

### 5. Verify Operator

```bash
# Check operator logs
kubectl logs -n sm-operator-system \
  deployment/sm-operator-controller-manager \
  -c manager \
  --tail=50

# Should see successful startup messages without errors
```

## Usage

### Creating BitwardenSecret Resources

See example manifests in application directories:
- `manifests/n8n/postgres-bitwarden-secret.yaml`
- `manifests/n8n/n8n-bitwarden-secret.yaml`
- `manifests/cloudflared/cloudflare-bitwarden-secret.yaml`

### Basic BitwardenSecret Template

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: my-secret
  namespace: my-namespace
spec:
  organizationId: "your-org-id-here"

  authToken:
    secretName: bw-auth-token
    secretNamespace: sm-operator-system

  secretName: my-kubernetes-secret

  map:
    - bwSecretId: "secret-uuid-from-bitwarden"
      secretKeyName: MY_SECRET_KEY
```

### Verifying Secrets

```bash
# Check BitwardenSecret status
kubectl get bitwardensecrets -A

# Check generated Kubernetes secret
kubectl get secret my-kubernetes-secret -n my-namespace

# View secret keys
kubectl get secret my-kubernetes-secret -n my-namespace \
  -o jsonpath='{.data}' | jq 'keys'
```

## Troubleshooting

### Operator Not Starting

```bash
# Check pod events
kubectl describe pod -n sm-operator-system \
  $(kubectl get pod -n sm-operator-system -l app.kubernetes.io/name=sm-operator -o name)

# Common issues:
# - Access token secret missing (create it first)
# - Invalid organization ID
# - Network connectivity issues
```

### Secrets Not Syncing

```bash
# Check operator logs
kubectl logs -n sm-operator-system \
  deployment/sm-operator-controller-manager \
  -c manager \
  --tail=100

# Check BitwardenSecret resource
kubectl describe bitwardensecret <name> -n <namespace>

# Force sync by restarting operator
kubectl rollout restart deployment/sm-operator-controller-manager \
  -n sm-operator-system
```

### Access Token Expired

```bash
# Generate new token in Bitwarden web UI
# Update secret
kubectl create secret generic bw-auth-token \
  -n sm-operator-system \
  --from-literal=token="NEW_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart operator
kubectl rollout restart deployment/sm-operator-controller-manager \
  -n sm-operator-system
```

## Configuration

### Sync Interval

Default: 300 seconds (5 minutes)

To change, update `manifests/applications/bitwarden-operator.yaml`:
```yaml
syncInterval: 180  # Minimum allowed value
```

### Resource Limits

Current limits:
- CPU: 500m (limit), 100m (request)
- Memory: 256Mi (limit), 128Mi (request)

Adjust in ArgoCD application manifest if needed.

## Security Considerations

1. **Access Token Protection**
   - Access token is stored as Kubernetes secret
   - Only readable by operator pod
   - Rotate regularly (every 90 days recommended)

2. **RBAC**
   - Operator has cluster-wide read access to BitwardenSecret CRDs
   - Can create/update secrets only in specified namespaces
   - Uses ServiceAccount with limited permissions

3. **Network Security**
   - Operator communicates with Bitwarden API over HTTPS
   - No inbound network access required
   - Ensure cluster has internet connectivity (for cloud-hosted Bitwarden)

## Maintenance

### Updating Operator

```bash
# Update chart version in ArgoCD application
# Edit manifests/applications/bitwarden-operator.yaml
# Change targetRevision: "0.X.X"

# Sync via ArgoCD
kubectl patch app bitwarden-operator -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### Monitoring

```bash
# Create alert for operator health
kubectl get events -n sm-operator-system --watch

# Monitor sync errors
kubectl get bitwardensecrets -A -o json | \
  jq -r '.items[] | select(.status.conditions[]?.status=="False") |
    "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[].message)"'
```

### Backup

The operator itself is stateless. Important data:
- Access token (in `bw-auth-token` secret)
- Organization ID (in ArgoCD application)

Back up these values securely outside the cluster.

## References

- [Complete Setup Guide](../../docs/bitwarden-secrets-manager-setup.md)
- [Bitwarden Secrets Manager Docs](https://bitwarden.com/help/secrets-manager-kubernetes-operator/)
- [Operator GitHub Repository](https://github.com/bitwarden/sm-kubernetes)
