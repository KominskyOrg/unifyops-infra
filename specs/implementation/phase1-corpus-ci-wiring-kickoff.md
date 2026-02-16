# Phase 1 Kickoff: Corpus CI Workflow Wiring (INF-1 / INF-2)

Status: Draft implementation note
Owner: Infra

## Objective
Wire CI workflow steps so corpus runner outputs are parsed and enforced with lineage + digest checks required by `evidence-corpus-ci-gate-integration-v1.md`.

## Expected Runner Output Contract (required by workflow)
Matrix file: `evidence/validator/test-output/corpus-matrix-report-v1.json`

Required top-level blocks/fields:
- `totals.fail` (integer)
- `totals.skipped` (integer)
- `lineage.source_commit_sha` (string)
- `lineage.release_artifact_id` (string)
- `lineage.release_artifact_checksum` (string)
- `lineage.runner_version` (string)
- `lineage.runner_checksum` (string)

Workflow MUST fail if any required lineage field is missing, with explicit hard-fail on missing `lineage.runner_version`.

## CI Wiring Tasks (Phase 1)

1) **Runner execution + artifact paths**
- Add or confirm corpus runner step in backend validation workflow.
- Ensure output paths match spec and are uploaded even on failure.

2) **Digest emission**
- Add step to emit matrix SHA-256 to logs:
  - `sha256sum evidence/validator/test-output/corpus-matrix-report-v1.json`

3) **Gate parser step**
- Add script step to parse matrix JSON and enforce:
  - `totals.fail == 0`
  - `totals.skipped == 0` (blocking mode)
  - lineage completeness (including `runner_version` present)

4) **Coverage/completeness hook**
- Add one of:
  - expected case-count check vs executed count, or
  - corpus manifest checksum validation.
- Keep this check blocking in release-controlled lanes.

5) **Non-blocking guardrails**
- Reject workflow config enabling non-blocking mode in release-controlled lanes.
- If non-blocking is used in non-release lanes, require expiry + owner metadata and emit visible CI banner.

6) **Evidence envelope integration**
- In release-controlled lanes, include matrix/report artifacts in unified evidence envelope/bundle publication step.

7) **Version drift controls**
- Pin runner version in workflow references.
- Capture and upload dependency lockfile evidence (e.g., `poetry.lock` or equivalent).

## Suggested Initial Workflow Snippet (pseudo)

```bash
uo-evidence-corpus-runner ...
sha256sum evidence/validator/test-output/corpus-matrix-report-v1.json
python3 .ci/scripts/validate_corpus_matrix.py \
  --matrix evidence/validator/test-output/corpus-matrix-report-v1.json \
  --expected-case-count "$EXPECTED_CORPUS_CASE_COUNT"
```

## INF-1 / INF-2 Next Concrete Commands

INF-1 (workflow wiring skeleton):
1. `cd /workspace/repos/unifyops-infra`
2. `git checkout -b agent/forge/20260215-inf1-corpus-ci-wiring`
3. `ls .github/workflows`
4. `grep -R "uo-evidence-corpus-runner\|evidence/validator/test-output" -n .github/workflows`
5. Edit target workflow to add runner, artifact upload, sha256 emission, and guardrail env checks.

INF-2 (gate parser + completeness checks):
1. `mkdir -p .ci/scripts`
2. `cat > .ci/scripts/validate_corpus_matrix.py` (enforce fail/skipped/lineage/completeness)
3. `python3 .ci/scripts/validate_corpus_matrix.py --help`
4. Wire script invocation in workflow with blocking/non-blocking policy gates.
5. Add/update docs linking workflow evidence artifacts to unified evidence envelope step.

## Exit Criteria for Phase 1
- Workflow emits matrix SHA-256.
- Workflow fails on missing `lineage.runner_version`.
- Blocking mode enforces `totals.fail == 0` and `totals.skipped == 0`.
- Non-blocking mode cannot run in release-controlled lanes.
- Release-controlled workflow uploads/includes corpus artifacts in evidence envelope path.

## Hardening Note (2026-02-16)
- Workflow now resolves `runner_checksum` using the installed runner module origin first, then known source paths, to avoid empty lineage checksums in local-source install contexts.
- Lineage hydration remains missing-only (`set_default`), preserving any runner-provided lineage values.
- Lockfile evidence warning is deterministic and now prints explicit searched paths.
- When lockfiles are absent, workflow captures supplemental source dependency manifest evidence from `_deps/unifyops/shared/unifyops_core/pyproject.toml` (path + sha256) without changing gate fail-open behavior.

## Release-lane enforcement slice (2026-02-16, Mode A Phase-1 continuation)
- Release-controlled lanes now hard-fail corpus evidence posture when either condition is unmet: (a) source ref-integrity is not immutable/preflight-validated, or (b) lockfile evidence is absent from the supported search set (`poetry.lock`, `requirements*.txt`, and `_deps/unifyops` equivalents).
- Supplemental manifest evidence (`_deps/unifyops/shared/unifyops_core/pyproject.toml` + SHA-256) remains collected but is not accepted as a lockfile substitute in release lanes.
- Non-release behavior is intentionally unchanged for pass/fail gating: mutable refs and missing lockfiles remain warning-only during rollout.
- Workflow now emits deterministic lane-scoped diagnostics (`[POLICY][RELEASE]` vs `[POLICY][NON-RELEASE]`) so operators can distinguish hard enforcement from rollout warnings.
- Migration expectation: release-tag pipelines must pin immutable source refs (tag/SHA) and ensure lockfile artifacts are committed/available before enabling release promotion.
- New deterministic operator artifact `evidence/validator/test-output/policy-outcome-v1.json` is generated by `validate_corpus_matrix.py` and uploaded with corpus matrix artifacts (`lane`, `ref_mode`, `lockfile_present`, `completeness_mode`, `gate_result`, `reasons[]`).
- Release-lane hard-fail diagnostics now require explicit reason codes for each enforcement path (`RLP_REF_PREFLIGHT_FAILED`, `RLP_REF_NOT_IMMUTABLE`, `RLP_LOCKFILE_REQUIRED`) and the validator emits coded gate reasons (e.g., `CMX_*`) instead of generic failure-only output.
- Validator guardrail normalization is now deterministic and logged for malformed/empty booleans and lane inputs (normalization events emitted as `policy.normalized.*`).

## Rollout slice update (2026-02-16, Mode A Phase-1 next)
- Added deterministic workflow summary block `corpus-preflight-summary-v1` that logs lane, source repo/ref, resolved ref mode, preflight status, lockfile presence, and expected-case-count source.
- Introduced explicit expected-case-count resolver step with stable provenance labels (`configured`, `auto-derived`, `fallback`) and wired validator invocation to consume the resolved value.
- Added policy outcome artifact self-check before upload to guarantee `policy-outcome-v1.json` exists and parses as valid JSON in both release and non-release lanes; missing artifact is materialized as deterministic fallback JSON with coded reason `CMX_POLICY_OUTCOME_ABSENT`.
- Validator now enforces deterministic reason ordering by sorting gate reason entries by `(code, message)` before emitting logs/artifacts, reducing diff churn in CI outputs.

## Rollout slice update (2026-02-16, Mode A Phase-1 artifact-manifest hardening)
- Workflow now generates deterministic artifact index `evidence/validator/test-output/artifact-manifest-v1.json` with sorted entries (`path`, `sha256`, `role`) across matrix, summary, case reports, policy outcome, and metadata outputs.
- Manifest generation is order-stable by sorting case-report paths and globally sorting manifest entries by path before emission.
- Added lane-aware artifact-role presence check keyed off the manifest: release-controlled lanes hard-fail only when required roles are missing, while non-release lanes emit warning-only diagnostics (existing non-release gate semantics preserved).
- Artifact manifest is uploaded with corpus matrix artifacts and included in release-lane unified evidence envelope inputs when present.

## Rollout slice update (2026-02-16, Mode A Phase-1 artifact-linkage integrity)
- Added deterministic cross-artifact linkage validation step that compares metadata references against canonical workflow artifact paths for `corpus_matrix_path`, `policy_outcome_path`, and `artifact_manifest_path`.
- Added deterministic linkage outcome artifact `evidence/validator/test-output/artifact-linkage-outcome-v1.json` (`schema_version`, `lane`, `ref_mode`, `policy_gate_result`, `gate_result`, `reasons[]`) and uploaded it with corpus artifacts; release lanes also include it in unified evidence envelope inputs.
- Added deterministic lineage-context fields to `artifact-manifest-v1.json` (`lane`, `ref_mode`, `gate_result`, plus mirrored `lineage_context`) so policy/manifest/linkage artifacts carry consistent identity material.
- Added coded linkage diagnostics with stable sort order `(code, message)` for deterministic logs/artifacts: `CMX_LINKAGE_METADATA_MISSING`, `CMX_LINKAGE_METADATA_REF_MISMATCH`, `CMX_LINKAGE_MANIFEST_MISSING`, `CMX_LINKAGE_MANIFEST_ENTRY_MISSING`, `CMX_LINKAGE_MANIFEST_SHA_MISMATCH`.
- Added deterministic lineage consistency mismatch codes across policy/manifest/linkage fields: `CMX_LINEAGE_POLICY_OUTCOME_MISSING`, `CMX_LINEAGE_POLICY_OUTCOME_INVALID`, `CMX_LINEAGE_POLICY_FIELDS_MISSING`, `CMX_LINEAGE_MANIFEST_FIELDS_MISSING`, `CMX_LINEAGE_LANE_MISMATCH`, `CMX_LINEAGE_REF_MODE_MISMATCH`, `CMX_LINEAGE_GATE_RESULT_MISMATCH`.
- Linkage semantics by lane: release-controlled lanes treat any linkage reason as hard-fail (`gate_result=fail` + step exit non-zero), while non-release lanes emit warning-only diagnostics (`gate_result=warn`) and preserve non-blocking pass posture.
- Metadata artifact now records explicit linkage references for downstream checks (`policy_outcome_path`, `artifact_manifest_path`) in addition to matrix/ref/lockfile fields.

## Rollout slice update (2026-02-16, Mode A Phase-1 reason-code catalog + trend-ready diagnostics)
- Added deterministic reason-code catalog artifact `evidence/validator/test-output/reason-codes-index-v1.json` generated on every run from emitted `policy-outcome-v1.json` and `artifact-linkage-outcome-v1.json` reasons.
- Artifact contract (v1): `schema_version`, `lane`, `policy_gate_result`, `artifact_linkage_gate_result`, `source_artifacts`, `reason_codes[]`, and `severity_totals`.
- `reason_codes[]` is stable and trend-ready: entries are grouped by `code`, include `count`, `severity`, and sorted `sources`; list ordering is deterministic (`code` ascending).
- Severity semantics are lane-aware without changing gate outcomes: release lanes classify emitted reasons as `error`; non-release lanes classify by source gate posture (`policy fail => error, else warning`; linkage `fail => error`, `warn => warning`, otherwise `notice`).
- Workflow now emits deterministic diagnostics block `reason-code-diagnostics-v1` summarizing lane + severity counts (`error|warning|notice`) for both release and non-release operator triage.
- `reason-codes-index-v1.json` is uploaded with corpus artifacts and included in release-lane unified evidence envelope inputs when present.

## Rollout slice update (2026-02-16, Mode A Phase-1 policy-drift guardrails)
- Added deterministic cross-artifact policy-drift check across `policy-outcome-v1.json`, `reason-codes-index-v1.json`, and `artifact-linkage-outcome-v1.json`.
- New deterministic drift artifact: `evidence/validator/test-output/policy-drift-outcome-v1.json` with contract fields: `schema_version`, `lane`, `gate_result`, `reasons[]`, `source_artifacts`, and normalized `policy_fields` snapshots.
- Added deterministic drift reason codes (`CMX_DRIFT_*`) for mismatch classes:
  - `CMX_DRIFT_ARTIFACT_MISSING`
  - `CMX_DRIFT_ARTIFACT_INVALID`
  - `CMX_DRIFT_LANE_MISMATCH`
  - `CMX_DRIFT_POLICY_GATE_RESULT_MISMATCH`
  - `CMX_DRIFT_LINKAGE_GATE_RESULT_MISMATCH`
  - `CMX_DRIFT_REF_MODE_MISMATCH`
  - `CMX_DRIFT_REASON_INDEX_SHAPE_INVALID`
- Lane semantics:
  - release lanes: any drift reason triggers hard-fail (`gate_result=fail`, step exits non-zero)
  - non-release lanes: drift emits warning-only diagnostics (`gate_result=warn`) and preserves rollout posture
- Drift artifact is now uploaded with corpus artifacts and included in release-lane unified evidence envelope inputs when present.

## Rollout slice update (2026-02-16, Mode A Phase-1 envelope-cohesion contract)
- Added deterministic evidence-envelope cohesion validation step that reconciles release envelope input mapping against emitted governance artifacts (`matrix`, `metadata`, `artifact-manifest`, `policy-outcome`, `artifact-linkage-outcome`, `reason-codes-index`, `policy-drift-outcome`).
- New deterministic artifact: `evidence/validator/test-output/envelope-cohesion-outcome-v1.json`.
- Artifact contract (v1): `schema_version`, `lane`, `gate_result`, `reasons[]`, `governance_artifacts` (path/existence/envelope mapping), and `source_artifacts` path index.
- Deterministic coded outcomes (`CMX_ENVELOPE_*`):
  - `CMX_ENVELOPE_ARTIFACT_MISSING`
  - `CMX_ENVELOPE_INPUT_MISSING_FOR_ARTIFACT`
  - `CMX_ENVELOPE_INPUT_WITHOUT_ARTIFACT`
- Lane semantics:
  - release lanes: envelope-cohesion mismatch hard-fails (`gate_result=fail`, step exits non-zero)
  - non-release lanes: warning-only posture (`gate_result=warn`) with no pass/fail tightening.
- `envelope-cohesion-outcome-v1.json` is uploaded with corpus artifacts and included in release-lane unified evidence envelope inputs when present.
