# Harbor Operations Runbook

## Daily Operations

### Check System Health
```bash
# Overall health
curl -k https://harbor.local/api/v2.0/health

# Check all components
kubectl get pods -n harbor
kubectl top pods -n harbor
```

### Monitor Storage Usage
```bash
# Check PVC usage
kubectl get pvc -n harbor
kubectl exec -n harbor deployment/harbor-registry -- df -h /storage

# Database size
kubectl exec -n harbor deployment/harbor-database -- \
  psql -U postgres -c "SELECT pg_database_size('registry');"
```

## Common Tasks

### Create New Project
```bash
curl -X POST https://harbor.local/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345!" \
  -d '{"project_name": "new-project", "public": false}'
```

### Create Robot Account
```bash
# Via UI: Projects → Select Project → Robot Accounts → New Robot Account
# Via API:
curl -X POST https://harbor.local/api/v2.0/robots \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345!" \
  -d @robot-account.json
```

### Manual Garbage Collection
```bash
# Trigger GC via UI: Administration → Garbage Collection → GC Now
# Or via API:
curl -X POST https://harbor.local/api/v2.0/system/gc/schedule \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345!" \
  -d '{"schedule": {"type": "Manual"}}'
```

### Export Audit Logs
```bash
# Get audit logs
curl https://harbor.local/api/v2.0/audit-logs \
  -u "admin:Harbor12345!" \
  > audit-logs-$(date +%Y%m%d).json
```

## Backup Procedures

### Daily Backup Script
```bash
#!/bin/bash
BACKUP_DIR="/backup/harbor/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup database
kubectl exec -n harbor deployment/harbor-database -- \
  pg_dump -U postgres registry | gzip > $BACKUP_DIR/database.sql.gz

# Backup configuration
kubectl get configmap -n harbor -o yaml > $BACKUP_DIR/configmaps.yaml
kubectl get secret -n harbor -o yaml > $BACKUP_DIR/secrets.yaml

# List images for reference
curl -s https://harbor.local/api/v2.0/projects \
  -u "admin:Harbor12345!" > $BACKUP_DIR/projects.json
```

### Restore from Backup
```bash
# Restore database
kubectl exec -n harbor deployment/harbor-database -i -- \
  psql -U postgres registry < database.sql

# Restore configurations
kubectl apply -f configmaps.yaml
kubectl apply -f secrets.yaml

# Restart Harbor
kubectl rollout restart deployment -n harbor
```

## Performance Tuning

### Increase Registry Workers
```yaml
# Edit apps/harbor/values/values.pvc.yaml
registry:
  controller:
    workers: 10  # Default is 5
```

### Database Connection Pool
```yaml
database:
  internal:
    maxIdleConns: 50
    maxOpenConns: 100
```

### Redis Memory Limit
```yaml
redis:
  internal:
    resources:
      limits:
        memory: 1Gi  # Increase if needed
```

## Security Tasks

### Rotate Admin Password
```bash
# Via UI: User Profile → Change Password
# Via API:
curl -X PUT https://harbor.local/api/v2.0/users/1/password \
  -H "Content-Type: application/json" \
  -u "admin:OldPassword" \
  -d '{"old_password": "OldPassword", "new_password": "NewPassword"}'
```

### Rotate Robot Tokens
```bash
# Delete old robot account
curl -X DELETE https://harbor.local/api/v2.0/robots/{robot_id} \
  -u "admin:Harbor12345!"

# Create new one with same permissions
./apps/harbor/setup/bootstrap-harbor.sh
```

### Update TLS Certificate
```bash
# Update certificate secret
kubectl create secret tls harbor-tls \
  --cert=new-cert.pem \
  --key=new-key.pem \
  --dry-run=client -o yaml | kubectl apply -n harbor -f -

# Restart Harbor
kubectl rollout restart deployment -n harbor
```

## Troubleshooting

### Pod CrashLoopBackOff
```bash
# Check logs
kubectl logs -n harbor <pod-name> --previous

# Common issues:
# - PVC not bound: Check storage class
# - Database connection: Check postgres pod
# - Certificate issues: Verify TLS secret
```

### Slow Image Push/Pull
```bash
# Check network
kubectl exec -n harbor deployment/harbor-core -- ping registry

# Check disk I/O
kubectl exec -n harbor deployment/harbor-registry -- iostat -x 1

# Increase nginx timeout
kubectl edit configmap -n harbor harbor-nginx
# proxy_read_timeout 3600;
# proxy_send_timeout 3600;
```

### Database Issues
```bash
# Connect to database
kubectl exec -n harbor deployment/harbor-database -it -- \
  psql -U postgres registry

# Check connections
SELECT count(*) FROM pg_stat_activity;

# Kill long-running queries
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE state = 'active' AND query_start < now() - interval '1 hour';
```

### Storage Full
```bash
# Run garbage collection
curl -X POST https://harbor.local/api/v2.0/system/gc/schedule \
  -u "admin:Harbor12345!"

# Check blob storage
kubectl exec -n harbor deployment/harbor-registry -- \
  find /storage -type f -size +1G

# Expand PVC if needed
kubectl edit pvc -n harbor harbor-registry
```

## Monitoring Alerts

### Prometheus Alerts
```yaml
- alert: HarborDown
  expr: up{job="harbor"} == 0
  for: 5m
  annotations:
    summary: "Harbor is down"

- alert: HarborStorageFull
  expr: kubelet_volume_stats_available_bytes{namespace="harbor"} < 10737418240
  for: 10m
  annotations:
    summary: "Harbor storage < 10GB free"

- alert: HarborHighErrorRate
  expr: rate(harbor_http_request_errors_total[5m]) > 0.05
  for: 10m
  annotations:
    summary: "Harbor error rate > 5%"
```

## Compliance & Retention

### Set Retention Policy
```bash
# Via UI: Projects → Select Project → Policy → TAG RETENTION
# Keep last 20 tags, keep release-* tags forever

curl -X POST https://harbor.local/api/v2.0/projects/{project}/retentions \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345!" \
  -d '{
    "rules": [{
      "template": "latestK",
      "tag_selectors": [{"kind": "doublestar", "pattern": "**"}],
      "scope_selectors": {"repository": [{"kind": "doublestar", "pattern": "**"}]},
      "params": {"latestK": 20}
    }]
  }'
```

### Export CVE Report
```bash
# Get vulnerability report for all images
for project in dev staging prod; do
  curl https://harbor.local/api/v2.0/projects/$project/repositories \
    -u "admin:Harbor12345!" | \
  jq -r '.[] | .name' | \
  while read repo; do
    curl "https://harbor.local/api/v2.0/projects/$project/repositories/${repo##*/}/artifacts?with_scan_overview=true" \
      -u "admin:Harbor12345!" > "cve-report-$project-$repo.json"
  done
done
```

## Disaster Recovery

### Full System Restore
1. Deploy fresh Harbor via ArgoCD
2. Restore database from backup
3. Restore image blobs from backup storage
4. Recreate projects and robot accounts
5. Update all services with new credentials

### Failover Procedure
1. Update DNS to point to backup Harbor instance
2. Sync registries using replication
3. Update all CI/CD with backup instance URL
4. Monitor for missed pushes during failover

## Contact & Escalation

- **Harbor Admin**: admin@unifyops.io
- **Platform Team**: platform-team@unifyops.io
- **On-Call**: Use PagerDuty escalation
- **Harbor Support**: https://github.com/goharbor/harbor/issues