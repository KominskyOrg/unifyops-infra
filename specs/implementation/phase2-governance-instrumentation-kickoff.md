# Phase-2: Governance Instrumentation — Kickoff

Status: In-progress
Branch: `agent/forge/20260216-phase2-governance-instrumentation`
Depends on: Phase-1 (corpus CI wiring + evidence validator gate)

## Scope & Order

### Slice 1 — Historical Trend Tracking (this PR)
- Emit `governance-trends-v1.json` with per-run record: run_id, run_attempt, commit_sha, lane, verdict, reason counts by severity/code, timestamp.
- Baseline mode (`mode: baseline`) when no prior history available in runner context.
- Upload as artifact; include in release envelope inputs when present.
- No gate semantic changes.

### Slice 2 — Artifact Signing & Tamper Evidence (future)
- Introduce HMAC or cosign-based signatures for governance artifacts.
- Tamper-evidence validation step that verifies signatures before gate evaluation.
- Acceptance: release lane rejects unsigned/tampered artifacts.

### Slice 3 — Dashboard Summary Integration (future)
- Emit machine-readable dashboard payload (`governance-dashboard-v1.json`).
- Include trend deltas, artifact counts, verdict history for external consumption.
- Acceptance: dashboard payload validates against published JSON schema.

## Acceptance Criteria (Slice 1)
1. `governance-trends-v1.json` emitted every CI run with deterministic fields.
2. Artifact uploaded alongside existing governance artifacts.
3. Included in unified evidence envelope inputs on release lane.
4. All existing gates pass unchanged.
5. Static checks (yaml lint) pass.
