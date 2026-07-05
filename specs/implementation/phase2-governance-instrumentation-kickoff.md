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

### Slice 3 — Dashboard Summary Integration ✅
- `governance-dashboard-v1.json` emitted with trend deltas, verdict history, artifact inventory.
- Included in unified evidence envelope inputs on release lane.
- Dashboard reads from governance-trends and governance-summary artifacts.

### Slice 4 — Historical Trend Accumulation ✅
- **Workflow upgrade**: new step `Fetch prior governance trends from recent successful runs` uses `gh api` to download `governance-trends-v1.json` from prior successful `corpus-evidence-ci` artifacts (bounded by `GOVERNANCE_TRENDS_LOOKBACK_RUNS`, default 5).
- **Trend builder upgrade**: `build_governance_trends()` merges prior run records with current run deterministically:
  - Deduplicates by `(run_id, run_attempt)` — current run wins on collision.
  - Sorts by timestamp descending for stable ordering.
  - Caps total records at `GOVERNANCE_TRENDS_MAX_RUNS` (default 20) to prevent unbounded growth.
- **Mode field**: `mode` switches from `"baseline"` to `"historical"` when prior records are successfully ingested.
- **Graceful degradation**: if fetch step fails, is skipped, or yields no valid records, trends artifact degrades to `mode: "baseline"` with explicit `baseline_reason` field and log annotation (reason codes: `no_prior_runs`, `no_artifacts`, `skipped`, etc.).
- **Gate semantics unchanged**: trends artifact is informational; no new gate failures introduced.
- **New env vars / repo vars**:
  - `GOVERNANCE_TRENDS_PRIOR_DIR` — working directory for fetched prior trends files.
  - `GOVERNANCE_TRENDS_MAX_RUNS` (repo var, default `20`) — cap on accumulated run records.
  - `GOVERNANCE_TRENDS_LOOKBACK_RUNS` (repo var, default `5`) — how many prior successful runs to fetch.
- **Artifact contract addition**: `governance-trends-v1.json` now includes `max_runs` field and optional `baseline_reason` field.

## Acceptance Criteria (Slice 4)
1. Prior trend records fetched from recent successful CI runs when available.
2. Deterministic merge: dedup by `(run_id, run_attempt)`, timestamp-descending sort, capped at `max_runs`.
3. `mode: "historical"` when prior records merged; `mode: "baseline"` with `baseline_reason` when degraded.
4. Fetch failure → clean degradation with annotation, no gate failure.
5. All existing gates pass unchanged.
6. Static checks pass.

### Slice 5 — Workflow Refactor: Extract Remaining Inline Logic ✅
- **Source preflight**: extracted ~160-line inline bash block into `.ci/scripts/source_preflight.sh`.
  - Workflow step now invokes `bash .ci/scripts/source_preflight.sh` (1 line vs ~160 inline).
  - All outputs preserved: `preflight_ok`, `error_type`, `error_message`, `effective_ref`, `ref_mode`, `cross_repo`, `ref_origin`, `token_present`, `repo_endpoint_status`, `ref_check_status`.
- **Lineage/digest emission**: consolidated 7 inline steps into `.ci/scripts/emit_lineage.py`.
  - Single `python3 .ci/scripts/emit_lineage.py` invocation replaces: matrix SHA-256, hydrate lineage, extract lineage, runner audit, lockfile digest, expected case count, preflight summary.
  - Step id `lineage_digests` replaces former `matrix_digest`, `lineage`, `lockfile_digest`, `expected_case_count` ids. All downstream `${{ steps.*.outputs.* }}` references updated.
- **Signing/tamper**: consolidated 2 separate steps into `.ci/scripts/sign_and_verify.py`.
  - Single step `sign_and_verify` replaces former `artifact_signing` + `tamper_validation` steps.
  - Internally delegates to `build_governance_artifacts.py sign-governance-artifacts` then `validate-tamper-evidence`.
- **Envelope builder**: simplified verbose per-file `if/cp` pattern into a loop.
- **Net result**: workflow reduced from 909 → 509 lines (44% reduction, -400 lines).
- All env var contracts, output paths, and lane semantics unchanged.

## Acceptance Criteria (Slice 5)
1. All three extraction scripts pass static checks (bash -n, py_compile).
2. Workflow YAML valid, line count ≤ 520.
3. All existing step output contracts preserved (downstream refs updated).
4. CI run passes green on branch push.

## Remaining Phase-2 Work
- No further slices planned. Phase-2 governance instrumentation is feature-complete.
- Future improvements: consider extracting the `release_posture_policy` step and the `gate semantics` step into Python scripts for further reduction (optional, diminishing returns).
