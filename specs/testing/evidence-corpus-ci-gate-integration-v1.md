# INF-1 / INF-2 Evidence Corpus CI Wiring Spec (v1)

Status: Proposed (docs-level CI wiring)
Scope: CI lane for evidence corpus determinism checks using `uo-evidence-corpus-runner`.
Depends on: `unified-test-evidence-model-v2-mode-a.md`, `release-gate-policy-mode-a-v2.md`.

## 1) Required CI Step

Pipeline MUST execute the corpus runner in the backend validation lane:

```bash
uo-evidence-corpus-runner \
  --corpus-root evidence/validator/testdata/evidence-corpus \
  --matrix-out evidence/validator/test-output/corpus-matrix-report-v1.json \
  --reports-dir evidence/validator/test-output/corpus-reports \
  --summary-md-out evidence/validator/test-output/corpus-summary.md
```

If runner invocation uses module form in bootstrap environments, it MUST be behaviorally equivalent and produce the same artifacts.

## 2) Required Output Contract (Lineage + Integrity)

The matrix JSON/report emitted by the runner MUST include a top-level `lineage` block with all fields present and non-empty:

- `source_commit_sha`
- `release_artifact_id`
- `release_artifact_checksum`
- `runner_version`
- `runner_checksum`

Runner metadata controls:
- CI MUST pin an explicit runner version (no floating tags).
- CI MUST capture dependency lockfile evidence used to execute the runner (for example `poetry.lock`, `requirements.txt` with hashes, or equivalent lock artifact).
- CI gate MUST fail if `lineage.runner_version` is missing.

Integrity requirements:
- CI MUST emit a SHA-256 digest for `corpus-matrix-report-v1.json` in CI logs.
- For release-controlled lanes, corpus artifacts MUST be included in the unified evidence envelope/bundle for that release.

## 3) Required Artifacts (Upload)

CI MUST upload these artifacts for every run (pass or fail):

1. Matrix JSON: `evidence/validator/test-output/corpus-matrix-report-v1.json`
2. Summary Markdown: `evidence/validator/test-output/corpus-summary.md`
3. Per-case reports directory: `evidence/validator/test-output/corpus-reports/**`
4. Dependency lockfile evidence used by the runner runtime (path depends on environment)

Retention MUST align with the unified evidence model and release evidence bundle retention policy for release-controlled lanes. If lane-specific retention differs, the workflow MUST link to the governing release evidence retention policy and enforce at least that minimum.

## 4) Gate Condition (Blocking Mode)

Primary fail conditions:
- Parse matrix JSON and read `totals.fail`.
- CI gate MUST fail when `totals.fail > 0`.
- CI gate MUST fail when `totals.skipped != 0`.
- CI gate MUST fail if `lineage.runner_version` is absent.

Coverage/completeness conditions (at least one required):
- Validate expected corpus case-count equals matrix executed case-count, and fail on mismatch; and/or
- Validate corpus manifest checksum against expected checksum, and fail on mismatch.

Reference blocking rule:
- pass only when all are true:
  - `totals.fail == 0`
  - `totals.skipped == 0`
  - lineage fields are complete
  - coverage/completeness assertion passes

## 5) Optional Staged Non-Blocking Toggle (Guardrails)

A temporary staged mode MAY be used during rollout only for non-release-controlled lanes:
- Config key example: `EVIDENCE_CORPUS_NON_BLOCKING=true`
- In staged mode, pipeline reports non-zero fail count but does not block merge/promotion in that lane.

Non-blocking mode guardrails:
- MUST NOT be enabled in release-controlled lanes.
- MUST declare explicit expiry date and owner in CI config.
- MUST display a visible CI banner/warning when active.
- MUST still:
  - run corpus runner,
  - upload artifacts,
  - emit explicit warning with fail/skipped counts,
  - emit matrix SHA-256 digest.

Default policy remains blocking mode.

## 6) Minimal CI Pseudocode

```bash
set -euo pipefail

uo-evidence-corpus-runner ...

# always upload artifacts here

MATRIX_PATH='evidence/validator/test-output/corpus-matrix-report-v1.json'
sha256sum "${MATRIX_PATH}" | awk '{print "corpus_matrix_sha256=" $1}'

python3 - <<'PY'
import json
import sys

matrix_path = 'evidence/validator/test-output/corpus-matrix-report-v1.json'
with open(matrix_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

totals = data.get('totals', {})
lineage = data.get('lineage', {})

fail_count = int(totals.get('fail', 0))
skipped_count = int(totals.get('skipped', 0))
runner_version = lineage.get('runner_version')

# TODO: add expected case-count and/or manifest checksum validation in workflow.
coverage_ok = True

import os
non_blocking = (os.getenv("EVIDENCE_CORPUS_NON_BLOCKING", "false").lower() == "true")
release_controlled = (os.getenv("RELEASE_CONTROLLED_LANE", "false").lower() == "true")

if release_controlled and non_blocking:
    print("Invalid config: non-blocking mode is prohibited in release-controlled lanes")
    sys.exit(1)

if not runner_version:
    print("Evidence corpus gate failed: lineage.runner_version missing")
    sys.exit(1)

if fail_count > 0 or skipped_count != 0 or not coverage_ok:
    if non_blocking:
        print(f"[NON-BLOCKING EVIDENCE CORPUS] fail={fail_count} skipped={skipped_count}")
        sys.exit(0)
    print(f"Evidence corpus gate failed: fail={fail_count} skipped={skipped_count} coverage_ok={coverage_ok}")
    sys.exit(1)

print("Evidence corpus gate passed")
PY
```

## 7) Acceptance Criteria

- [x] CI run command for `uo-evidence-corpus-runner` is specified.
- [x] Matrix + summary (+ per-case) artifacts are specified for upload.
- [x] Lineage block fields required in matrix/report output.
- [x] Matrix SHA-256 log emission required.
- [x] Runner version pin + lockfile capture required; missing `runner_version` fails gate.
- [x] Deterministic blocking fail conditions include `totals.fail` and `totals.skipped == 0`.
- [x] Coverage/completeness assertion requirement defined.
- [x] Non-blocking mode guardrails defined (prohibited in release-controlled lanes + expiry/owner + visible banner).
- [x] Retention aligned to unified evidence/release evidence bundle policy.
