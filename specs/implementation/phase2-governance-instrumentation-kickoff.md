# Phase-2: Governance Instrumentation — Kickoff

Status: In-progress
Branch: `agent/forge/20260216-phase2-governance-instrumentation`
Depends on: Phase-1 (corpus CI wiring + evidence validator gate)

## Scope & Order

### Slice 1 — Historical Trend Tracking ✅
- Emit `governance-trends-v1.json` with per-run record: run_id, run_attempt, commit_sha, lane, verdict, reason counts by severity/code, timestamp.
- Baseline mode (`mode: baseline`) when no prior history available in runner context.
- Upload as artifact; include in release envelope inputs when present.
- No gate semantic changes.

### Slice 2 — Artifact Signing & Tamper Evidence ✅
- **Signing step**: computes HMAC-SHA256 signatures for all governance artifacts using a workflow-scoped signing key.
  - Baseline posture: derives key from `GITHUB_SHA` when `GOVERNANCE_SIGNING_KEY` secret is not set.
  - Upgrade path: set `GOVERNANCE_SIGNING_KEY` secret for production-grade HMAC integrity.
- **Artifact contract**: `artifact-signatures-v1.json` containing:
  - `schema_version`: `"artifact-signatures-v1"`
  - `key_source`: `"secret:GOVERNANCE_SIGNING_KEY"` or `"derived:GITHUB_SHA"`
  - `algorithm`: `"HMAC-SHA256"`
  - `entries[]`: `{ path, sha256, hmac_sha256 }` — sorted deterministically by path.
- **Tamper validation gate**: re-reads artifacts and verifies signatures match.
  - Release lane: tamper mismatch → hard-fail.
  - Non-release lane: tamper mismatch → warning-only.
- Signatures artifact uploaded alongside existing governance artifacts.
- Included in unified evidence envelope inputs on release lane.

### Slice 3 — Dashboard Summary Integration (future)
- Emit machine-readable dashboard payload (`governance-dashboard-v1.json`).
- Include trend deltas, artifact counts, verdict history for external consumption.
- Acceptance: dashboard payload validates against published JSON schema.

## Acceptance Criteria (Slice 2)
1. `artifact-signatures-v1.json` emitted every CI run with deterministic HMAC-SHA256 entries.
2. Tamper validation gate verifies all signatures; hard-fails on release lane, warns on non-release.
3. Signatures artifact uploaded alongside existing governance artifacts.
4. Included in unified evidence envelope inputs on release lane.
5. All existing gates pass unchanged.
6. Static checks (yaml lint) pass.
