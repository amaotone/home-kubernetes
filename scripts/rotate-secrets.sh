#!/usr/bin/env bash
# Secret Rotation Script for Home Kubernetes Cluster
# Usage: ./scripts/rotate-secrets.sh [postgres|n8n|cloudflare|all]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SEALED_SECRETS_CONTROLLER_NAME="sealed-secrets"
SEALED_SECRETS_CONTROLLER_NAMESPACE="sealed-secrets"
MANIFESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/manifests"

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v kubeseal &> /dev/null; then
        missing_tools+=("kubeseal")
    fi

    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install them using:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                kubectl)
                    echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
                    ;;
                kubeseal)
                    echo "  - kubeseal: brew install kubeseal (macOS) or see https://github.com/bitnami-labs/sealed-secrets"
                    ;;
                openssl)
                    echo "  - openssl: brew install openssl (macOS) or apt-get install openssl (Linux)"
                    ;;
            esac
        done
        exit 1
    fi

    # Check if sealed-secrets controller is running
    if ! kubectl get deployment -n "${SEALED_SECRETS_CONTROLLER_NAMESPACE}" "${SEALED_SECRETS_CONTROLLER_NAME}" &> /dev/null; then
        log_error "sealed-secrets controller not found in namespace ${SEALED_SECRETS_CONTROLLER_NAMESPACE}"
        log_info "Deploy it first: kubectl apply -f manifests/applications/sealed-secrets.yaml"
        exit 1
    fi

    log_info "All prerequisites met ✓"
}

# Generate strong random password
generate_password() {
    openssl rand -base64 32
}

# Generate strong random encryption key (hex format)
generate_encryption_key() {
    openssl rand -hex 32
}

# Rotate PostgreSQL passwords
rotate_postgres() {
    log_info "Rotating PostgreSQL secrets..."

    # Generate new passwords
    local postgres_password=$(generate_password)
    local non_root_password=$(generate_password)

    log_warn "New passwords generated. SAVE THESE IMMEDIATELY to your password manager:"
    echo ""
    echo "POSTGRES_PASSWORD: ${postgres_password}"
    echo "POSTGRES_NON_ROOT_PASSWORD: ${non_root_password}"
    echo ""

    read -p "Have you saved the passwords to your password manager? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_error "Aborted. Please save the passwords and try again."
        exit 1
    fi

    # Update password in running database (non-root user only)
    log_info "Updating non-root password in database..."
    if kubectl get deployment postgres -n n8n &> /dev/null; then
        kubectl exec -n n8n deployment/postgres -- \
            psql -U postgres -c "ALTER USER n8n WITH PASSWORD '${non_root_password}';" || {
            log_error "Failed to update password in database"
            exit 1
        }
        log_info "Database password updated ✓"
    else
        log_warn "PostgreSQL deployment not found. Skip database update (will apply on next deployment)"
    fi

    # Create sealed secret
    log_info "Creating SealedSecret..."
    kubectl create secret generic postgres-secret \
        --namespace=n8n \
        --from-literal=POSTGRES_USER=postgres \
        --from-literal=POSTGRES_PASSWORD="${postgres_password}" \
        --from-literal=POSTGRES_DB=n8n \
        --from-literal=POSTGRES_NON_ROOT_USER=n8n \
        --from-literal=POSTGRES_NON_ROOT_PASSWORD="${non_root_password}" \
        --dry-run=client \
        -o yaml | \
    kubeseal \
        --controller-name="${SEALED_SECRETS_CONTROLLER_NAME}" \
        --controller-namespace="${SEALED_SECRETS_CONTROLLER_NAMESPACE}" \
        --format=yaml \
        > "${MANIFESTS_DIR}/n8n/postgres-sealed-secret.yaml"

    log_info "SealedSecret created at: ${MANIFESTS_DIR}/n8n/postgres-sealed-secret.yaml"

    # Commit to Git
    read -p "Commit changes to Git? (yes/no): " commit_confirm
    if [ "$commit_confirm" = "yes" ]; then
        git add "${MANIFESTS_DIR}/n8n/postgres-sealed-secret.yaml"
        git commit -m "chore: rotate PostgreSQL passwords"
        log_info "Changes committed ✓"

        read -p "Push to remote? (yes/no): " push_confirm
        if [ "$push_confirm" = "yes" ]; then
            git push
            log_info "Changes pushed ✓"
        fi
    fi

    # Restart pods
    read -p "Restart n8n pods to apply new secrets? (yes/no): " restart_confirm
    if [ "$restart_confirm" = "yes" ]; then
        kubectl rollout restart deployment/n8n -n n8n
        log_info "n8n deployment restarted ✓"
        log_info "Wait for rollout to complete..."
        kubectl rollout status deployment/n8n -n n8n
    fi

    log_info "PostgreSQL secret rotation complete ✓"
}

# Rotate n8n encryption key
rotate_n8n() {
    log_error "n8n encryption key rotation requires careful planning!"
    log_warn "Rotating this key will make existing encrypted credentials unreadable."
    log_warn "You must migrate existing credentials using n8n's migration tools."
    log_warn "See: https://docs.n8n.io/hosting/environment-variables/configuration-methods/#encryption-key"
    echo ""

    read -p "Have you backed up the n8n database and read the documentation? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_error "Aborted. Please back up the database and read the documentation first."
        exit 1
    fi

    # Generate new encryption key
    local encryption_key=$(generate_encryption_key)

    log_warn "New encryption key generated. SAVE THIS IMMEDIATELY to your password manager:"
    echo ""
    echo "N8N_ENCRYPTION_KEY: ${encryption_key}"
    echo ""

    read -p "Have you saved the key to your password manager? (yes/no): " key_confirm
    if [ "$key_confirm" != "yes" ]; then
        log_error "Aborted. Please save the key and try again."
        exit 1
    fi

    # Create sealed secret
    log_info "Creating SealedSecret..."
    kubectl create secret generic n8n-secret \
        --namespace=n8n \
        --from-literal=N8N_ENCRYPTION_KEY="${encryption_key}" \
        --dry-run=client \
        -o yaml | \
    kubeseal \
        --controller-name="${SEALED_SECRETS_CONTROLLER_NAME}" \
        --controller-namespace="${SEALED_SECRETS_CONTROLLER_NAMESPACE}" \
        --format=yaml \
        > "${MANIFESTS_DIR}/n8n/n8n-sealed-secret.yaml"

    log_info "SealedSecret created at: ${MANIFESTS_DIR}/n8n/n8n-sealed-secret.yaml"

    log_warn "IMPORTANT: You must now migrate existing credentials in n8n before deploying this change!"
    log_warn "Follow the n8n encryption key migration procedure."

    log_info "n8n secret rotation preparation complete ✓"
}

# Rotate Cloudflare tunnel token
rotate_cloudflare() {
    log_info "Rotating Cloudflare tunnel token..."

    log_warn "Before proceeding, create a new tunnel token:"
    log_info "1. Go to https://one.dash.cloudflare.com/"
    log_info "2. Navigate to Networks → Tunnels"
    log_info "3. Create or select your tunnel"
    log_info "4. Generate a new token"
    echo ""

    read -p "Enter the new Cloudflare tunnel token: " cloudflare_token

    if [ -z "$cloudflare_token" ]; then
        log_error "Token cannot be empty"
        exit 1
    fi

    log_warn "Token received. SAVE THIS to your password manager:"
    echo ""
    echo "CLOUDFLARE_TUNNEL_TOKEN: ${cloudflare_token}"
    echo ""

    read -p "Have you saved the token to your password manager? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_error "Aborted. Please save the token and try again."
        exit 1
    fi

    # Create sealed secret
    log_info "Creating SealedSecret..."
    kubectl create secret generic cloudflare-tunnel-token \
        --namespace=cloudflared \
        --from-literal=token="${cloudflare_token}" \
        --dry-run=client \
        -o yaml | \
    kubeseal \
        --controller-name="${SEALED_SECRETS_CONTROLLER_NAME}" \
        --controller-namespace="${SEALED_SECRETS_CONTROLLER_NAMESPACE}" \
        --format=yaml \
        > "${MANIFESTS_DIR}/cloudflared/cloudflare-sealed-secret.yaml"

    log_info "SealedSecret created at: ${MANIFESTS_DIR}/cloudflared/cloudflare-sealed-secret.yaml"

    # Commit to Git
    read -p "Commit changes to Git? (yes/no): " commit_confirm
    if [ "$commit_confirm" = "yes" ]; then
        git add "${MANIFESTS_DIR}/cloudflared/cloudflare-sealed-secret.yaml"
        git commit -m "chore: rotate Cloudflare tunnel token"
        log_info "Changes committed ✓"

        read -p "Push to remote? (yes/no): " push_confirm
        if [ "$push_confirm" = "yes" ]; then
            git push
            log_info "Changes pushed ✓"
        fi
    fi

    # Restart pods
    read -p "Restart cloudflared pods to apply new token? (yes/no): " restart_confirm
    if [ "$restart_confirm" = "yes" ]; then
        kubectl rollout restart deployment/cloudflared -n cloudflared
        log_info "cloudflared deployment restarted ✓"
        log_info "Wait for rollout to complete..."
        kubectl rollout status deployment/cloudflared -n cloudflared
    fi

    log_warn "IMPORTANT: Revoke the old token in Cloudflare Dashboard to complete rotation!"

    log_info "Cloudflare secret rotation complete ✓"
}

# Main script
main() {
    if [ $# -eq 0 ]; then
        log_error "Usage: $0 [postgres|n8n|cloudflare|all]"
        exit 1
    fi

    check_prerequisites

    case "$1" in
        postgres)
            rotate_postgres
            ;;
        n8n)
            rotate_n8n
            ;;
        cloudflare)
            rotate_cloudflare
            ;;
        all)
            log_warn "Rotating all secrets. This is a significant operation!"
            read -p "Are you sure? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                rotate_postgres
                echo ""
                rotate_cloudflare
                echo ""
                log_info "All secrets rotated (except n8n - requires manual migration)"
            fi
            ;;
        *)
            log_error "Unknown option: $1"
            log_error "Usage: $0 [postgres|n8n|cloudflare|all]"
            exit 1
            ;;
    esac
}

main "$@"
