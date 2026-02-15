# Phase 1 Kickoff: Unified Evidence Envelope Validator

Status: In Progress (BE-1/BE-2 foundations completed)
Owner: Infra (primary), Backend + QA (co-owners)
Last Updated: 2026-02-15

## 1) Objective

Stand up the first executable component for O2 evidence hardening: a unified evidence envelope validator available as both:
- CLI (`uo-evidence-validate`)
- Service/library entrypoint (reusable in CI and future gate orchestration)

Phase 1 goal is **non-blocking validation in CI** with clear contracts, telemetry, and rollout path to blocking enforcement.

## 2) Build Scope (Phase 1)

In scope:
- Parse and validate `unified-evidence-v2` envelope payloads.
- Validate referenced metadata required for Mode A flake/governance workflows.
- Perform schema conformance checks.
- Verify signature presence/verification status and signer identity constraints.
- Verify policy checksum declarations and consistency against expected policy bundle set.
- Emit structured validation report (machine-readable + human-readable summary).
- Integrate into CI as non-blocking job (warn/report only).

Out of scope (Phase 1):
- Hard gate blocking behavior.
- Full historical backfill/reprocessing.
- Automatic remediation of malformed envelopes.

## 3) Input Contract

Accepted inputs:
1. `--evidence <path-or-uri>`: unified evidence envelope JSON (`unified-evidence-v2`).
2. `--policy-checksum-set <path>`: expected checksum set for active policy bundle(s).
3. `--schema-version <version>`: expected schema version (default `v2`).
4. `--mode <ci|local|service>`: execution mode for output formatting/exit behavior.

Required evidence fields validated in Phase 1:
- Envelope identifiers: `candidate_id`, `release_id`, `lane_id`, `run_id`
- Canonical hash components (where present): source commit, artifact checksum, scope digest, policy checksum(s), environment fingerprint checksum, fixture version hash
- Digest/signature metadata fields and references to lane artifacts

## 4) Output Contract

CLI exits and artifacts:
- Exit code `0`: validation passed
- Exit code `2`: validation warnings only (non-blocking in CI)
- Exit code `3`: validation errors (still non-blocking during Phase 1 CI rollout, but flagged)

Machine-readable output (`validation-report-v1.json`):
- `status`: `pass|warn|fail`
- `schema_validation`: result + violations[]
- `signature_validation`: result + signer/check details
- `policy_checksum_validation`: expected vs observed + mismatch details
- `evidence_ref_validation`: referenced artifact availability/hash checks
- `timestamp`, `validator_version`, `ruleset_version`

Human summary output:
- concise table of pass/warn/fail checks
- remediation hints per failed control

## 5) Validation Pipeline (Phase 1)

1. **Schema validation**
   - Validate envelope against `unified-evidence-v2` JSON schema.
   - Reject unknown critical fields and missing required fields.

2. **Signature validation**
   - Verify signature block presence.
   - Verify cryptographic signature and trusted signer identity profile.
   - Ensure digest-to-payload integrity check succeeds.

3. **Policy checksum validation**
   - Compare envelope-declared policy checksum(s) to expected checksum set.
   - Require deterministic ordering and exact set equality.

4. **Evidence reference checks**
   - Validate referenced artifacts resolve and match declared digests.
   - Record unresolved references as warnings/errors per severity map.

5. **Result emission**
   - Emit JSON report + human summary.
   - Publish CI annotations (non-blocking in Phase 1).

## 6) CI Integration (Initial Non-Blocking)

Initial insertion point:
- Add job to existing Mode A test/evidence workflow after evidence generation and before dashboard normalization publish.

Behavior in Phase 1:
- Job always uploads validation report artifact.
- Job posts annotations/comments for warnings and failures.
- Pipeline does not fail on validator failures yet (soft enforcement).

Required telemetry:
- pass/warn/fail counts
- most-common failure categories
- time-to-validate and artifact size stats

## 7) Rollout Path to Blocking Mode

- **Phase 1 (current):** Validate + report only (non-blocking).
- **Phase 2:** Blocking for schema/signature failures on protected branches; checksum mismatches still warn.
- **Phase 3:** Blocking for schema/signature/policy checksum failures in release candidate flows.
- **Phase 4:** Full blocking in all required Mode A release lanes, with exception process tied to signed waiver evidence.

Promotion criteria between phases:
- stable false-positive rate below agreed threshold
- documented operator runbook
- QA sign-off on test corpus coverage
- infra readiness for CI/runtime capacity

## 8) Task Breakdown and Ownership

### Backend
1. Define validator domain model + report schema (`validation-report-v1`).
2. Implement parser + schema validation module.
3. Implement signature verification adapter interface.
4. Implement policy checksum comparator with deterministic set handling.

### QA
1. Build conformance test corpus (valid/malformed/tampered/edge cases).
2. Define expected results matrix for pass/warn/fail.
3. Add regression scenarios for known flake/evidence anomalies.
4. Validate non-blocking CI annotation quality and triage usability.

### Infra
1. Add CI job integration and artifact retention wiring.
2. Provide trusted key material/config injection mechanism.
3. Add telemetry export and dashboard starter panels.
4. Draft operational runbook and phase-promotion checklist.

## 9) Initial Milestones

- M1: Spec + contracts approved (this document).
- M2: CLI skeleton + schema validation + JSON report emission.
- M3: Signature + policy checksum validation integrated.
- M4: CI non-blocking rollout enabled on main integration workflow.
- M5: 2-week data review and Phase 2 go/no-go decision.

## 10) Dependencies / Open Questions

- Final trusted signer source of truth location.
- Canonical policy checksum source endpoint/file and update cadence.
- Severity mapping for unresolved evidence refs (warn vs fail).
- Versioning policy for validator ruleset.

---

Implementation starts at M2 immediately after owner acknowledgment.


## 11) Locked Phase-1 Decisions (Approved)

The following decisions are now locked for Phase 1 implementation and must be treated as normative:

1. **Signer source of truth:** repo-managed trust bundle (Phase 1).
2. **Policy checksum set source:** CI file artifact `policy-checksum-set.json`.
3. **Resolver scope:** local paths + `file://` only (Phase 1).
4. **Unknown critical-field handling:** block unknown critical fields via explicit post-check with clear error text.

## 12) Completed Slice Update (BE-1 + BE-2 Foundations)

Completed in canonical repo (`/workspace/repos/unifyops`):
- Added implementation tracker: `evidence/validator/IMPLEMENTATION_STATUS.md`
- Added report schema artifact: `evidence/validator/schemas/validation-report-v1.schema.json`
- Added check-ID taxonomy doc and constants scaffold
- Added CLI scaffold entrypoint: `uo-evidence-validate`
  - supports modes `ci|local|service`
  - emits machine-readable JSON report path
  - emits human-readable stdout summary
  - uses Phase-1 exit code contract (`0` pass / `2` warn / `3` fail)
- Added minimal skeleton tests for resolver scope and unknown critical-field blocking behavior

Deferred to next backend slice:
- BE-3 signature verification implementation against repo-managed trust bundle
- BE-4 policy checksum set enforcement against `policy-checksum-set.json` semantics
