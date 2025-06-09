# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a GitOps-managed home Kubernetes cluster using ArgoCD. All cluster state is defined declaratively in Git, with ArgoCD automatically syncing and maintaining the desired state.

## Key Architecture Patterns

1. **App of Apps Pattern**: The root application (`manifests/applications/root.yaml`) manages all other applications
2. **No Traditional Ingress**: Uses Cloudflare Tunnels (cloudflared) for external access instead of Ingress resources
3. **Sealed Secrets**: All secrets must be encrypted using kubeseal before committing. Never commit plain Secret resources
4. **Namespace Isolation**: Each application runs in its own namespace

## Development Commands

### Python Application (kotatsu-news)
When working in `src/kotatsu-news/`:
```bash
# Install dependencies
rye sync

# Run tests
rye run pytest

# Lint code
rye run ruff check

# Format code
rye run ruff format

# Build Docker image
docker build -t kotatsu-news .
```

### Kubernetes Operations
```bash
# Apply ArgoCD applications
kubectl apply -f manifests/applications/

# Encrypt a secret (example)
echo -n "mysecret" | kubectl create secret generic my-secret --dry-run=client --from-file=password=/dev/stdin -o yaml | kubeseal -o yaml > my-sealed-secret.yaml
```

## Important Conventions

1. **ArgoCD Applications**: All applications in `manifests/applications/` should have:
   - `automated.prune: true` and `automated.selfHeal: true` for automatic sync
   - Proper namespace configuration
   - Clear source repository paths

2. **Helm Values**: When modifying Helm charts (like n8n), update the `values.yaml` file, not the deployment directly

3. **Renovate**: Dependency updates are automated. Check `renovate.json5` before manually updating versions

4. **Security Contexts**: All pods should run as non-root users with appropriate security contexts

## File Structure

- `manifests/applications/`: ArgoCD Application definitions
- `manifests/<app-name>/`: Application-specific manifests or Helm configurations
- `src/`: Source code for custom applications
- `docs/`: Documentation including design philosophy