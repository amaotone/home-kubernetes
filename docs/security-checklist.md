# Security Checklist for Home Kubernetes Cluster

This checklist helps ensure your cluster follows security best practices. Review and update regularly.

## Secret Management

### Initial Setup
- [ ] sealed-secrets controller deployed and running
- [ ] kubeseal CLI installed on all developer machines
- [ ] Sealed-secrets master key backed up to secure offline storage
- [ ] All plain Secret resources replaced with SealedSecrets
- [ ] No secrets committed to Git in plain text

### PostgreSQL Secrets
- [ ] `postgres-secret` converted to SealedSecret
- [ ] Strong passwords generated (32+ characters, random)
- [ ] Passwords stored in password manager (1Password/Bitwarden/etc.)
- [ ] Non-root user (n8n) has limited database permissions
- [ ] Root postgres password never used by applications

### n8n Secrets
- [ ] `n8n-secret` converted to SealedSecret
- [ ] Encryption key generated with sufficient entropy (256-bit)
- [ ] Encryption key stored in password manager
- [ ] Encryption key never logged or exposed

### Cloudflare Secrets
- [ ] `cloudflare-tunnel-token` converted to SealedSecret
- [ ] Token stored in password manager
- [ ] Old tokens revoked when rotated
- [ ] Tunnel configured with least privilege access

### Secret Rotation
- [ ] Rotation schedule documented (every 90 days recommended)
- [ ] Calendar reminders set for rotation dates
- [ ] Rotation procedure tested at least once
- [ ] Team members trained on rotation process
- [ ] Rotation script (`scripts/rotate-secrets.sh`) tested

### Access Control
- [ ] RBAC policies limit secret access to necessary ServiceAccounts
- [ ] Secrets not exposed via environment variables in logs
- [ ] Secret values never printed in application logs
- [ ] Audit logging enabled for secret access (if available)

## Pod Security

### Security Contexts
- [ ] All pods run as non-root users
- [ ] User IDs explicitly set (not default to 0)
- [ ] File system permissions properly configured
- [ ] `runAsNonRoot: true` enforced on all deployments
- [ ] `allowPrivilegeEscalation: false` where applicable
- [ ] Read-only root filesystem where applicable

### Current Deployments
- [ ] n8n: runAsUser=1000, runAsGroup=1000, runAsNonRoot=true
- [ ] PostgreSQL: runAsUser=999, runAsGroup=999, runAsNonRoot=true
- [ ] cloudflared: Security context configured

### Pod Security Standards
- [ ] Pod Security Admission configured (if K8s 1.23+)
- [ ] Baseline or Restricted policy enforced on namespaces
- [ ] Privileged pods explicitly documented and justified
- [ ] Host network/IPC/PID namespaces not used without justification

## Network Security

### External Access
- [ ] Cloudflare Tunnels configured (no direct port exposure)
- [ ] No LoadBalancer services with public IPs
- [ ] No NodePort services exposed to internet
- [ ] TLS/HTTPS enforced for all external endpoints

### Internal Network
- [ ] NetworkPolicies defined for sensitive workloads
- [ ] Default deny policy considered for namespaces
- [ ] Intra-namespace communication restricted where needed
- [ ] Database only accessible from application pods

### DNS and Service Discovery
- [ ] Service names follow naming conventions
- [ ] DNS policies configured appropriately
- [ ] External DNS resolution restricted if needed

## Resource Management

### Resource Limits
- [ ] All containers have CPU requests and limits
- [ ] All containers have memory requests and limits
- [ ] Limits aligned with actual usage patterns
- [ ] No containers with unlimited resources

### Current Deployments
- [ ] n8n: requests (200m CPU, 512Mi mem), limits (1000m CPU, 1Gi mem)
- [ ] PostgreSQL: requests (200m CPU, 512Mi mem), limits (1000m CPU, 1Gi mem)
- [ ] cloudflared: Resource limits configured

### Resource Quotas
- [ ] ResourceQuotas defined per namespace (if multi-tenant)
- [ ] LimitRanges configured for default resource constraints
- [ ] Resource usage monitored and alerted

## Storage Security

### Persistent Volumes
- [ ] PVCs use appropriate StorageClass
- [ ] Sensitive data encrypted at rest (if supported by storage backend)
- [ ] Access modes correctly configured (ReadWriteOnce vs ReadWriteMany)
- [ ] Volume permissions match pod security context

### Current PVCs
- [ ] n8n-pvc: 10Gi, ReadWriteOnce, appropriate for application data
- [ ] postgres-pvc: 10Gi, ReadWriteOnce, appropriate for database

### Backup Security
- [ ] Backups encrypted in transit
- [ ] Backups encrypted at rest
- [ ] Backup storage access restricted
- [ ] Backup restoration tested regularly

## Container Image Security

### Image Sources
- [ ] Only trusted registries used (Docker Hub official, ghcr.io, etc.)
- [ ] Image tags pinned to specific versions (not :latest)
- [ ] Image digests used for critical deployments (optional)
- [ ] Private images pulled using ImagePullSecrets

### Current Images
- [ ] n8n: n8nio/n8n:2.1.1 (pinned version)
- [ ] PostgreSQL: postgres:15 (pinned major version)
- [ ] cloudflared: cloudflare/cloudflared:latest ⚠️ (consider pinning)
- [ ] kotatsu-news: ghcr.io/amaotone/kotatsu-news (private registry)

### Image Scanning
- [ ] CI/CD pipeline includes image vulnerability scanning
- [ ] Critical vulnerabilities block deployments
- [ ] Regular rescanning of deployed images
- [ ] Renovate bot updates dependencies automatically

## Application Security

### n8n Specific
- [ ] Webhook URLs use HTTPS only
- [ ] Workflow sharing restricted appropriately
- [ ] User authentication enabled (if multi-user)
- [ ] Sensitive workflow data not logged
- [ ] External credential storage considered (Vault integration)

### PostgreSQL Specific
- [ ] SSL/TLS enabled for connections (if applicable)
- [ ] Least privilege user permissions (n8n user)
- [ ] Connection limits configured
- [ ] Query logging for audit trail
- [ ] pg_hba.conf properly configured

### kotatsu-news Specific
- [ ] Slack bot token stored as Secret
- [ ] API endpoints validate input
- [ ] Rate limiting implemented
- [ ] Error messages don't leak sensitive info

## GitOps Security

### Repository Security
- [ ] Repository access restricted to authorized users
- [ ] Branch protection rules enabled (require PR reviews)
- [ ] Signed commits encouraged or enforced
- [ ] No secrets in Git history (checked with git-secrets/trufflehog)
- [ ] .gitignore includes sensitive files

### ArgoCD Security
- [ ] ArgoCD admin password changed from default
- [ ] RBAC policies configured
- [ ] Sync policies use least privilege
- [ ] Auto-sync with prune enabled carefully reviewed
- [ ] ArgoCD UI access restricted

### CI/CD Security
- [ ] GitHub Actions secrets properly scoped
- [ ] Workflow permissions follow least privilege
- [ ] Third-party actions pinned to commit SHA
- [ ] Secrets not logged in CI/CD output
- [ ] Build artifacts scanned before deployment

## Monitoring and Auditing

### Logging
- [ ] Application logs centralized (planned: to be implemented)
- [ ] Logs include security events (auth failures, access denied, etc.)
- [ ] Log retention policy defined
- [ ] Sensitive data (passwords, tokens) not logged
- [ ] Log access restricted to authorized users

### Metrics and Monitoring
- [ ] Prometheus deployed for metrics collection (planned)
- [ ] Grafana dashboards for security metrics (planned)
- [ ] Alerting configured for security events (planned)
- [ ] Failed authentication attempts monitored
- [ ] Unusual resource usage detected

### Audit Trail
- [ ] Kubernetes audit logging enabled (if available)
- [ ] ArgoCD sync history preserved
- [ ] Git commits provide audit trail for changes
- [ ] Secret access audited (if feature available)

## Incident Response

### Preparation
- [ ] Incident response plan documented
- [ ] Team contact information up to date
- [ ] Runbooks for common security scenarios
- [ ] Backup restoration procedure tested
- [ ] Secret rotation procedure tested

### Detection
- [ ] Security alerts configured (when monitoring implemented)
- [ ] Log analysis for anomalies (when logging implemented)
- [ ] Regular security scans scheduled
- [ ] Dependency vulnerability alerts enabled (Renovate)

### Response Procedures
- [ ] Secret compromise response plan: `docs/secret-management-guide.md#emergency-procedures`
- [ ] Pod compromise isolation procedure documented
- [ ] Data breach notification plan (if applicable)
- [ ] Post-incident review template

## Compliance and Documentation

### Documentation
- [ ] Architecture diagram up to date
- [ ] Security policies documented
- [ ] Runbooks for operational tasks
- [ ] Secret management guide: `docs/secret-management-guide.md`
- [ ] PostgreSQL upgrade procedure: `docs/postgres-upgrade-procedure.md`
- [ ] Design philosophy: `docs/design-philosophy.md`

### Regular Reviews
- [ ] Monthly security checklist review
- [ ] Quarterly access review (who has cluster access)
- [ ] Quarterly secret rotation (90-day cycle)
- [ ] Annual disaster recovery drill
- [ ] Annual security audit (self or third-party)

### Dependency Management
- [ ] Renovate bot enabled and configured
- [ ] Dependency updates tested before merging
- [ ] Security advisories monitored
- [ ] End-of-life software identified and upgraded

## Future Security Enhancements

### Short-term (Next 3 months)
- [ ] Implement Prometheus + Grafana for monitoring
- [ ] Set up centralized logging (Loki or ELK)
- [ ] Configure alerting for critical events
- [ ] Complete migration to SealedSecrets for all secrets
- [ ] Implement automated backup schedule

### Medium-term (3-6 months)
- [ ] Add NetworkPolicies for pod-to-pod communication
- [ ] Implement Pod Security Standards enforcement
- [ ] Set up Vault for dynamic secret generation (optional)
- [ ] Add OPA/Gatekeeper for policy enforcement (optional)
- [ ] Implement certificate management with cert-manager

### Long-term (6-12 months)
- [ ] Consider service mesh for mTLS (Istio/Linkerd)
- [ ] Implement zero-trust networking
- [ ] Add security scanning in CI/CD pipeline
- [ ] Set up SIEM for security event correlation
- [ ] Implement automated compliance reporting

## Compliance Status

**Last Review Date:** _[Update this date after each review]_

**Reviewed By:** _[Your name or team]_

**Overall Security Posture:**
- [ ] Excellent (90%+ items completed)
- [ ] Good (70-89% items completed)
- [ ] Fair (50-69% items completed)
- [ ] Needs Improvement (<50% items completed)

**Critical Items Not Completed:**
_[List any high-priority unchecked items]_

**Action Items for Next Review:**
_[List specific tasks to complete before next review]_

## Notes

- This checklist is a living document - update as your cluster evolves
- Mark items as complete only when fully implemented and tested
- Review this checklist monthly or after significant changes
- Some items may not apply to your specific use case - document exceptions
- Share this checklist with team members for collaborative security

## References

- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Sealed Secrets Best Practices](https://github.com/bitnami-labs/sealed-secrets#best-practices)
