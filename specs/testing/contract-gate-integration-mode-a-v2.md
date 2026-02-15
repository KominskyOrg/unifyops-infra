# P3-T4 Contract Gate Integration Spec - Mode A v2

Status: Normative (integration/spec)
Scope: CI/CD integration contract gate behavior for Mode A release candidates.
Depends on: `contract-suite-design-v2-mode-a.md` (P3-T2), `release-gate-policy-mode-a-v2.md`.

## 1) Stage Placement (required ordering)
Contract gate stage MUST execute:
1. After build/package and artifact publication.
2. Before any deploy/promotion stage (including staging/prod promotion).
3. Before deep E2E environment provisioning and deep E2E lane execution.

Normative ordering:
`build -> artifact sign -> contract-gate -> (deploy/promotion eligible) -> deep-e2e-provision -> deep-e2e`

Any pipeline template that places deploy/promotion or deep E2E provisioning before contract gate is non-compliant and MUST fail policy validation.

Anti-bypass policy:
- No promotion path MAY bypass contract gate for Mode A candidates.
- All pipeline definitions that can trigger deploy/promotion MUST be version-controlled and protected (required reviews + protected branch policy + immutable run metadata).
- Any unprotected or out-of-band pipeline path detected for promotion MUST hard-fail policy validation.

## 2) Required Inputs
Contract gate invocation MUST include:
- Commit SHA (immutable VCS ref).
- Release artifact ID (immutable build artifact identity).
- Release artifact checksum/digest.
- Boundary catalog reference + version.
- Supported version set manifest for each gated boundary.
- Centrally declared migration window state snapshot (state, approval ref, expiry).
- Contract suite definitions and fixtures.
- Environment classification marker (`controlled` or `non-controlled`) for SLA semantics.
- Canonical contract replay runner version identifier.
- Canonical replay runner package checksum/digest.

Controlled-environment classification criteria:
- `controlled` MUST be set only when all of the following are true for the run: fixed instance class, CPU/memory pinning, controlled load profile, isolation from non-test traffic/noisy-neighbor workloads, and deterministic dataset/version pinning.
- If any required control criterion is absent, environment classification MUST be `non-controlled`.

Missing any required input MUST hard-fail gate initialization.

## 3) Required Outputs and Artifacts
Contract gate MUST emit:
- Boundary pass/fail ledger.
- Signed compatibility matrix artifacts per boundary.
- Replay artifact bundles per boundary with checksum manifest.
- SLA assertion report with control-mode marker.
- Gate decision document (`pass` or `fail`) with reason codes.

Evidence binding requirement:
- Every gate artifact MUST bind and repeat: commit SHA, release artifact ID, and artifact checksum.
- Evidence bundle manifest checksum MUST be generated; checksum mutation invalidates prior gate evidence.
- Replay runner evidence MUST include immutable runner version + runner checksum; compatibility evidence generated under a different runner version/checksum is invalid.

## 4) Fail-Fast and Stop-Ship Policy
Fail-fast behavior:
- On first hard-fail condition, pipeline MUST terminate contract lane immediately and mark candidate as `stop-ship`.
- Downstream deploy/promotion/deep-E2E-provision stages MUST be blocked automatically.

Stop-ship conditions include (non-exhaustive):
- Any mandatory contract case failure.
- Missing or invalid signed compatibility matrix.
- Missing replay artifact package/manifest.
- Contract evidence binding mismatch (commit SHA, release artifact ID, checksum).
- Migration window metadata inconsistency or invalid expiry.
- Required dual approval absent/stale.
- Controlled-environment SLA hard-threshold failure.
- Approval timeout reached while status is `blocked-pending-dual-approval`.

Warn-only prohibition:
- Contract lane has no warn-only mode.
- Any contract gate hard-fail MUST produce `fail` decision and promotion block.

SLA enforcement mode:
- Hard SLA thresholds MUST be enforced only when environment classification is `controlled`.
- In `non-controlled` mode, SLA observations MUST be emitted as informational telemetry and MUST NOT independently fail contract gate.

## 5) Rollback / Block Behavior
When contract gate fails:
- Candidate promotion MUST remain blocked until a new passing candidate is produced.
- If failure occurs after a provisional deployment in pre-prod, automated rollback to last known-good artifact MUST execute before further promotion attempts.
- `known-good` artifact MUST be selected from the most recent artifact that has a recorded `pass` contract-gate decision with matching target environment class and immutable evidence linkage.
- Rollback action itself MUST run contract gate checks before it can be promoted beyond pre-prod.
- Rollback event MUST reference failed candidate commit SHA, failed release artifact ID, and rollback target artifact ID.
- Rollback evidence (decision + execution logs + target artifact digest) MUST be attached to the release audit record and linked to gate/audit IDs.
- Manual override that bypasses contract gate is prohibited for Mode A.

## 6) Approval Trigger Model (aligned to tightened P3-T2)
Dual provider/consumer approval requirements:
- Default: approvals required per release candidate.
- Escalated cadence: approvals required per commit only when contract support/version set changes for a boundary.

Staleness, timeout, and escalation:
- Approval record timeout: max 72h from first approval timestamp.
- Max blocking window for `blocked-pending-dual-approval`: 72h from first approval timestamp or 24h from block state entry when no first approval exists, whichever is earlier.
- Stale approvals are invalid for gate decisions.
- On stale/missing second approval, gate MUST set `blocked-pending-dual-approval` and auto-escalate to boundary owner group + release manager in the same CI cycle.
- If blocking window expires, gate MUST transition to terminal `fail` (MUST NOT remain `pending`).
- Retry/retrigger behavior: a new gate attempt MAY be triggered only after a fresh dual-approval cycle; retrigger MUST preserve prior failed/expired records as immutable audit history.
- Escalation chain for unresolved blocks: boundary owner group -> release manager -> engineering manager on-call (at timeout) -> change advisory owner (at +24h post-timeout if still unresolved).

## 7) Retention and Auditability
Retention requirements:
- Contract gate evidence bundle retention MUST meet or exceed release audit retention policy.
- Evidence references MUST be immutable and retrievable by commit SHA or release artifact ID.
- Artifact checksums MUST be preserved alongside storage references.

Audit query minimum:
- Given commit SHA + release artifact ID, system MUST return: gate decision, boundary ledger, signed matrices, replay manifests, and checksum proofs.

Replay runner immutability governance:
- Canonical replay runner version MUST be immutable and checksum-addressed.
- Upgrading canonical replay runner version/checksum MUST invalidate prior compatibility decisions/evidence for new gate decisions; prior evidence remains historical only and MUST NOT be reused as current release-gating proof.

## 8) Acceptance Criteria (P3-T4)
- [x] Contract stage placement is explicitly defined before deploy/promotion and deep E2E provisioning.
- [x] Required inputs/outputs/artifacts are fully specified.
- [x] Controlled vs non-controlled environment criteria and SLA semantics are explicitly defined.
- [x] Fail-fast behavior and stop-ship conditions are defined.
- [x] Approval timeout, terminal-state, retrigger, and escalation behavior are defined.
- [x] Artifact retention and evidence binding are defined (commit SHA + release artifact ID + checksum).
- [x] Replay runner immutability and upgrade invalidation behavior are defined.
- [x] Rollback/block behavior on contract failures is defined, including known-good source and audit linkage.
- [x] Anti-bypass pipeline protection requirements are defined.
- [x] No warn-only mode is allowed for contract lane.
- [x] Approval trigger model is aligned to tightened P3-T2 cadence/timeout/escalation.
