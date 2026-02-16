# P5-T1 Security Test Gate Spec v2 (Mode A)

Status: Normative (infra/spec)
Scope: Security test gating policy for Mode A release decisions in CI and staging.
Depends on: `release-gate-policy-mode-a-v2.md`, `contract-gate-integration-mode-a-v2.md`, `test-data-environment-determinism-mode-a-v2.md`.

## 1) Objective
Define mandatory security gate controls that convert security test outcomes into deterministic pass/fail release decisions for Mode A.

## 2) Security Test Inputs (Required)
Each gated run MUST execute and record at least:
- Static/code/dependency/container/infra security scans applicable to changed scope.
- Mandatory authN negative tests (invalid token, expired token, malformed token, missing credentials).
- Mandatory authZ negative tests (cross-tenant access attempt, privilege escalation attempt, denied resource action).
- Runtime policy validation checks (where applicable): network/egress policy conformance for tested paths.

### 2.1 Deterministic changed-scope classifier (required)
Changed scope MUST be machine-resolved and emitted as `security-scope.json` before threshold evaluation.

`security-scope.json` MUST include at minimum:
- `commitSha`, `baseSha`, `pipelineRunId`
- `services[]` (service IDs)
- `images[]` (image names/tags/digests)
- `charts[]` (chart IDs/versions)
- `dependencies[]` (name, ecosystem, version)
- `scopeHash` (stable hash over canonicalized scope payload)

Threshold evaluation in `security-gate-decision.json` MUST reference `security-scope.json` via `scopeHash` and artifact digest. A run with missing or mismatched scope artifact is `FAIL`.

If a required test family is not executed, gate status is `FAIL`.

## 3) Severity Thresholds (Pass/Fail)
Default threshold policy for Mode A:
- `CRITICAL`: 0 allowed (hard fail).
- `HIGH`: 0 allowed in changed scope; existing accepted-risk HIGH findings must have active waiver.
- `MEDIUM`: allowed only up to approved lane threshold (default 0 for auth components, <=2 for non-auth changed scope with owner sign-off).
- `LOW/INFO`: do not independently fail unless tied to policy rule marked hard-fail.

Threshold profiles must be versioned in repo and referenced by gate evidence (`security-threshold-profile-id`).
Threshold evaluation MUST be executed only against findings whose scope matches `security-scope.json`; out-of-scope findings MUST be tagged `scope=out_of_change` and excluded from changed-scope threshold counts while still recorded in evidence.

## 4) Mandatory authN/authZ Negative Test Requirements
The following are hard requirements for gate eligibility:

### 4.1 authN negative baseline
- Reject missing authentication header/credential.
- Reject expired/invalid signature token.
- Reject wrong audience/issuer token.
- Reject replayed token where nonce/jti policy exists.

### 4.2 authZ negative baseline
- Deny resource/action without required role/scope.
- Deny cross-tenant data access.
- Deny privilege escalation attempt (user->admin path).
- Deny access via indirect path bypass attempts (e.g., service-to-service endpoint not exposed to caller role).

Any missing authN/authZ baseline case is `FAIL`.

### 4.3 authZ bypass harness standardization (required)
The authZ negative harness MUST provide and record:
- Direct endpoint probing for protected API/service routes (no UI-only proxy checks).
- Role/token variants per case: valid least-privilege, over-privileged, cross-tenant token, expired/invalid token.
- Cross-tenant fixtures with deterministic tenant A/B resources and ownership metadata.
- Expected denial reason assertions (`statusCode`, `errorCode`, `policyReason`) per denied request.

Harness output MUST include request ID, principal fixture ID, tenant fixture ID, target resource ID, and assertion result per probe. Missing required harness capability or output fields is `FAIL`.

## 5) Explicit Hard-Fail Conditions
Security gate MUST hard-fail when any of the following occur:
1. One or more `CRITICAL` findings in tested scope.
2. Unauthorized access confirmed (authZ breach) in any mandatory negative test.
3. Authentication bypass or token acceptance flaw in mandatory authN tests.
4. Evidence artifact tampering, mismatch, or missing binding metadata.
5. Required security test family skipped without approved exception.
6. Policy requires hard fail (no warn-only allowed for this condition).

## 6) Waivers / Exceptions
Waivers are permitted only for non-critical findings and never for confirmed authN/authZ breach.

Waiver rules:
- Must include: finding ID(s), scope, compensating controls, risk rationale, expiry timestamp, and rollback/remediation plan.
- Required approvers: Security owner + service owner + release authority.
- Max waiver duration: 14 days unless policy file explicitly grants shorter cap.
- Expired waiver is treated as absent and causes gate failure if finding remains.
- Waiver IDs must be referenced in gate evidence and linked to immutable approval record.

### 6.1 Machine-readable waiver workflow (required)
Canonical waiver store for Mode A is `waivers/security-waivers.json` in repo.
- CI retrieval source is repository HEAD at evaluated commit; external mutable stores are non-authoritative.
- Each waiver record MUST include: `waiverId`, `findingKey`, `scopeHash`, `status`, `approvedBy[]`, `approvedAt`, `expiresAt`, `ticketRef`.
- `status` allowed values: `active|revoked|expired`.
- Auto-expiry enforcement is mandatory: CI MUST mark waiver `expired` when `expiresAt < evaluationTime` and MUST NOT count expired waivers toward pass criteria.
- Resolution behavior: if no active waiver matches (`findingKey` + `scopeHash`), threshold/hard-fail evaluation proceeds unwaived and may fail the gate.


## 7) Evidence Artifact Requirements and Binding Rules
A Mode A security gate run MUST produce and bind:
- `security-scope.json` (machine-resolved changed scope and `scopeHash`).
- `security-scan-results.json` (normalized findings with canonical severities, tool versions, scope markers).
- `authn-negative-tests.json` and `authz-negative-tests.json` (case list, expected/actual, pass/fail, timestamps).
- `runtime-policy-validation.json` (policy probe/audit/alignment results where policy applies).
- `security-gate-decision.json` (threshold evaluation, hard-fail checks, final status).
- `security-evidence-manifest.json` including checksums/digests for all above artifacts.

Binding rules:
- Every artifact MUST include commit SHA, pipeline run ID, environment lane, and timestamp.
- Manifest digest is immutable and stored with release evidence bundle.
- Gate decision MUST reference exact manifest digest (`evidenceDigest`), threshold profile ID, and `scopeHash` from `security-scope.json`.
- Any digest mismatch between manifest and artifact set is hard fail.

### 7.1 Tool normalization contract (required)
`security-scan-results.json` MUST normalize tool-native severities to canonical severities using:
- `critical|blocker -> CRITICAL`
- `high|important -> HIGH`
- `medium|moderate -> MEDIUM`
- `low -> LOW`
- `info|unknown|negligible -> INFO`

For each finding, evidence MUST capture `toolName`, `toolVersion`, `ruleId`/`cveId`, `packageOrAsset`, and canonical severity.
Deduplication MUST use stable key `findingKey = <cveOrRule>::<packageOrAsset>::<fixedVersionOrNone>::<location>`.
If a CVE is reclassified upstream between runs, CI MUST recalculate canonical severity from current mapping and evaluate using current severity; prior-run severity labels are non-authoritative.

### 7.2 Runtime policy validation enforcement (required where policy applies)
Where NetworkPolicy/egress/topology policy applies to changed scope, `runtime-policy-validation.json` is mandatory and MUST include:
- `networkPolicyProbes` (allowed/denied probe matrix and pass/fail)
- `egressAudit` (observed destinations, denied destinations, policy match result)
- `topologyPolicyAlignment` (alignment output keyed to declared topology/policy artifacts)

`topologyPolicyAlignment` MUST reference the topology/policy evidence artifacts already required by Mode A policy docs. Missing required runtime policy evidence where applicable is `FAIL`.

## 8) No Warn-Only Mode for Hard-Fail Policies
Where policy marks a condition as hard fail, implementation MUST enforce fail-closed behavior.
- Warn-only/report-only modes are prohibited for:
  - `CRITICAL` findings,
  - authN bypass findings,
  - authZ breach findings,
  - evidence binding failures.
- Pipelines may emit warnings for informational findings, but final gate outcome cannot be `PASS` when hard-fail conditions are present.

## 9) Gate Outcome Contract
`security-gate-decision.json` outcome values:
- `PASS`: all required test families executed; thresholds satisfied; no hard-fail condition; any waivers valid and unexpired.
- `FAIL`: any hard-fail condition, threshold breach without valid waiver, missing required tests, or evidence binding failure.

No intermediate result can override a `FAIL` from hard-fail policy checks.

## 10) Acceptance Criteria Status (P5-T1)
- [x] Fail/pass severity thresholds defined.
- [x] Mandatory authN/authZ negative tests defined.
- [x] Explicit hard-fail conditions defined (critical findings + authZ breach).
- [x] Waiver/exception rules with expiry + approvers defined.
- [x] Evidence artifact requirements and binding rules defined.
- [x] No warn-only mode where policy requires hard fail defined.
