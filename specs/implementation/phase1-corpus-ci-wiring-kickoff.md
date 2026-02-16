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
