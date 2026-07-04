# RESTORE.md — Disaster Recovery Runbook

Phase 0 (UO-P0-05) recovery procedures for the unifyops-home cluster.
Three protected assets: **Postgres data** (logical dumps), **Longhorn
volumes** (snapshots), and the **sealed-secrets controller keys**
(offline escrow). If you can only save one thing, save the sealed-secrets
keys — everything else is rebuildable from git + Harbor.

## 1. PostgreSQL — logical dump restore

### What exists
- Each dev database release (`auth-service-postgresql`,
  `user-service-postgresql` in `uo-dev`) runs a `*-pgdumpall` CronJob
  (`@daily`, Bitnami chart `backup.enabled`), writing
  `pg_dumpall-YYYY-MM-DD-HH-MM.pgdump` files to a dedicated 2Gi Longhorn
  PVC (`<release>-pgdumpall`), 14-day retention.
- Enabled via `postgresql.backup.*` in
  `clusters/unifyops-home/apps/unifyops/identity/{stack}/{stack}-service/values-dev.yaml`
  (dev branch).

### Take an ad-hoc dump now
```bash
kubectl create job --from=cronjob/auth-service-postgresql-pgdumpall \
  manual-dump-$(date +%s) -n uo-dev
kubectl wait --for=condition=complete job/manual-dump-<ts> -n uo-dev --timeout=120s
```

### Restore procedure (rehearsed 2026-07-04, see §1.1)
1. Find the newest dump on the backup PVC (mount it from a helper pod, or
   exec into a running backup job pod):
   ```bash
   kubectl run pg-restore --rm -it -n uo-dev \
     --image=harbor.unifyops.io/library/bitnami/postgresql:16.4.0-debian-12-r13 \
     --overrides='{"spec":{"containers":[{"name":"pg-restore","image":"harbor.unifyops.io/library/bitnami/postgresql:16.4.0-debian-12-r13","command":["sleep","3600"],"volumeMounts":[{"name":"dumps","mountPath":"/backup"}],"env":[{"name":"PGPASSWORD","valueFrom":{"secretKeyRef":{"name":"auth-postgresql-secret","key":"postgres-password"}}}]}],"volumes":[{"name":"dumps","persistentVolumeClaim":{"claimName":"auth-service-postgresql-pgdumpall"}}]}}'
   ```
2. Inside the pod, restore (pg_dumpall dumps are cluster-wide SQL with
   `--clean --if-exists`, so they drop/recreate objects):
   ```bash
   ls -lt /backup            # pick the dump
   psql -h auth-service-postgresql -U postgres -f /backup/<dump>.pgdump postgres
   ```
3. Restart the consuming service so connections re-establish cleanly:
   ```bash
   kubectl rollout restart deploy/auth-service -n uo-dev
   ```
4. Smoke: `curl https://dev.unifyops.io/service/auth/health` (or
   port-forward) and a login round-trip.

### 1.1 Rehearsal record
- 2026-07-04: full cycle rehearsed in `uo-dev` — ad-hoc dump job →
  helper pod mounting the backup PVC → dump restored into a **throwaway
  Postgres instance inside the pod** (initdb + `psql -f`): `auth_db`
  recreated with `auth.users` (16 rows) and `alembic_version` intact.
  Rehearsals restore into a throwaway instance to avoid touching live
  data; §1 step 2's live restore is for real incidents only.
  Bitnami-image note: run initdb/pg_ctl with the bundled nss_wrapper
  (`LD_PRELOAD=/opt/bitnami/common/lib/libnss_wrapper.so` +
  `NSS_WRAPPER_PASSWD`/`NSS_WRAPPER_GROUP` mapping uid 1001).

## 2. Longhorn — volume snapshots

### What exists
- `RecurringJob` `daily-snapshot` (`longhorn-system`): daily at 03:00,
  `retain: 14`, group `default` → applies to **every** volume without an
  explicit job assignment (includes both Postgres data PVCs and the
  backup PVCs).
- Manifest: `clusters/unifyops-home/apps/longhorn/recurringjob-daily-snapshot.yaml`.

### Restore from a snapshot
Longhorn snapshots restore by rolling the volume back or by creating a
new volume from a snapshot:
1. Longhorn UI (`https://longhorn.unifyops.io`) → Volume → Snapshots.
2. Preferred (non-destructive): create a **new PVC from snapshot**, then
   point the workload at it (edit the release values / PVC name), keeping
   the damaged volume for forensics.
3. In-place revert requires the volume detached (scale the StatefulSet to
   0 first), then Revert in the UI, then scale back up.

Note: snapshots live on the same node/disk as the volume — they protect
against application-level corruption and accidental deletion, **not**
disk loss. Off-cluster `backupTarget` (S3/NFS) is a follow-up (currently
empty in the longhorn app values).

## 3. Sealed-secrets — controller key escrow

### Why this matters most
Every secret in git is encrypted against the controller's key set. Lose
the cluster **and** the keys → every sealed secret in git is permanently
undecryptable; you would have to rotate/re-seal every credential.

### Escrow procedure (run after every key rotation — keys auto-rotate ~30d)
```bash
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-keys-$(date +%Y%m%d).yaml
chmod 600 sealed-secrets-keys-*.yaml
# Move the file to offline storage (password manager attachment,
# encrypted USB, etc.). NEVER commit it to git.
```
Escrow performed 2026-07-04: all 6 key-pair secrets exported to offline
storage (see §3.2). Add a calendar reminder or automate re-escrow.

### Restore keys into a fresh cluster
```bash
kubectl create ns sealed-secrets || true
kubectl apply -f sealed-secrets-keys-<date>.yaml
kubectl delete pod -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
# Controller restarts, loads all historical keys, and every SealedSecret
# in git decrypts again.
```

### 3.2 Escrow location
The exported key file is stored **outside this repo** on the admin
workstation at `~/UnifyOpsSource-escrow/` pending transfer to offline
storage. Jared: move it to the password manager / encrypted media and
delete the local copy.

## 4. Full-cluster rebuild order

1. k3s + `bootstrap/` (Argo CD).
2. Restore sealed-secrets keys (§3) **before** syncing apps.
3. Argo root-apps sync (`main` branch) — infra + appsets come back.
4. Postgres data: restore newest dumps (§1) or Longhorn snapshots (§2).
5. Verify: Argo all Synced/Healthy, `/health` endpoints, one login.
