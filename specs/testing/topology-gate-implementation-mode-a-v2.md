# P5-T4 Topology Gate Implementation Spec v2 (Mode A)

Status: Normative (implementation spec)
Scope: Runtime topology enforcement and gate evidence for Mode A release qualification.
Depends on: `release-gate-policy-mode-a-v2.md`, interaction matrix runtime-edge contract (service allow/deny matrix), and stack identity derivation controls.

## 1) Purpose
Define how topology policy is implemented, verified, and enforced in CI so forbidden runtime edges are blocked and allowed edges are provably reachable, with non-waivable fail semantics for release gating.

## 2) Runtime-Edge and Stack Identity Alignment
Runtime edge is defined as:
- `source_stack_identity` (workload/service account/pod identity),
- `destination_stack_identity` (service FQDN/IP class/external endpoint identity),
- protocol + port + direction,
- policy context (`environment_group`, lane, policy version).

Stack identity derivation MUST be deterministic and evidence-backed:
- Source identity derived from signed workload metadata (namespace, serviceAccount, workload labels, image digest).
- Destination identity derived from service registry + interaction matrix canonical IDs.
- Identity derivation output MUST be included in topology evidence and bound to commit/artifact checksum.

Identity derivation drift mitigation (required):
- Derivation inputs for the run MUST be immutable and pinned at execution time, including image digests (not tags), release artifact checksums, and validated workload labels.
- Compile-stage identity snapshots and run-stage identity snapshots MUST match exactly for all probe subjects; mismatch is `FAIL`.
- Admission policy / validation checks MUST reject ambiguous identity labels (duplicate canonical service labels, missing ownership labels, conflicting app identity keys). Enforcement references MUST be captured in evidence (`admission_policy_refs[]`, `validation_results[]`).

## 3) Implementation Options
### Option A: Kubernetes NetworkPolicy (L3/L4)
Pros: native, simple, low overhead.  
Cons: limited service identity semantics, harder cross-namespace intent mapping, weak external egress attribution.

### Option B: Service Mesh Authorization (L7 identity-aware)
Pros: strong workload identity, explicit allow/deny policy, rich telemetry for proof.  
Cons: operational overhead, mesh dependency, migration complexity.

### Option C: Runtime Egress Audit + Passive Validation
Pros: easy adoption, good observability.  
Cons: detect-only by default, enforcement lag, insufficient for hard gate alone.

## 4) Selected Primary Path
Primary enforcement path: **Option B (Service Mesh Authorization)**.
Secondary corroboration: NetworkPolicy baseline deny + runtime egress audit for evidence completeness.

Rationale:
- Gate requires machine-verifiable deny semantics at runtime edge granularity.
- Mesh identity maps directly to interaction matrix edge definitions.
- Audit-only approaches are insufficient for non-waivable release blocking.

## 5) Enforcement Model
- Default deny at namespace/workload boundary.
- Explicit allow edges sourced from interaction matrix and compiled into mesh authorization policies.
- NetworkPolicy maintains coarse-grain deny/egress guardrails.
- Runtime egress audit must observe allowed/forbidden probe outcomes and policy hit/miss traces.

Compiler requirements:
- Input: canonical interaction matrix + stack identity map.
- Output: signed policy bundle with `policy_version` and `policy_checksum` (sha256).
- Deterministic build: same input set MUST produce identical checksum.

Mesh dependency operational controls (required):
- Mesh control/data-plane versions MUST be pinned for gate runs (`mesh_control_plane_version`, `mesh_data_plane_version`) and included in evidence.
- Gate execution order is deterministic and MUST be: **compile -> policy bundle sign/checksum -> apply -> convergence verify -> probe execute -> verdict materialize**.
- Gate run MUST verify policy convergence before probes (all targeted workloads report expected policy generation / xDS version).
- If mesh control plane is degraded/unavailable (xDS push failures, stale config, or health below defined threshold), gate status is `FAIL_CLOSED` for release-controlled lanes; no pass decision may be issued from stale policy state.

## 6) Machine-Verifiable Acceptance Checks
For each gated topology run:
1. Generate probe plan from interaction matrix:
   - `forbidden_edges[]` (must fail)
   - `allowed_edges[]` (must pass)
2. Execute probes from real workload identities, not synthetic admin identities.
3. Capture verdict and telemetry linkage per probe.

Acceptance logic:
- Every forbidden edge probe MUST fail with policy-denied reason code.
- Every allowed edge probe MUST succeed within deterministic reachability timeout.
- Any unknown/unclassified runtime edge observed during run is `FAIL` unless explicitly covered by governed platform/system allowlist.

Allowed-edge probe timeout guardrail:
- Probe timeout is a deterministic **reachability validation timeout**, not an application latency/performance SLA metric.
- Reachability validation results MUST be evaluated separately from performance assertions.
- Performance SLO/SLA failures MAY be reported in companion artifacts but MUST NOT relabel topology reachability semantics.

Unknown runtime edge detection precision:
- Unknown-edge detection telemetry sources are strictly:
  1. mesh authorization decision logs,
  2. mesh L7 access logs,
  3. CNI/NetworkPolicy flow logs for corroboration,
  4. probe-runner execution logs tied by `run_id`.
- Detection scope is limited to **application identities only**; platform/system identities are excluded from unknown-edge fail logic unless mapped as application-owned.
- Evaluation window is `[run_start - 5m, run_end + 5m]` for the target `environment_group` and `lane`.
- De-duplication key is: `(source_app_identity, destination_app_identity, protocol, port, direction, policy_version)`; repeated observations increment counters but do not create distinct unknown-edge records.
- A governed platform/system edge allowlist MUST be versioned as `topology-platform-edge-allowlist.json` and referenced in gate evidence (`platform_allowlist_version`, `platform_allowlist_checksum`).

Minimum probe coverage:
- 100% of P0/P1 classified edges.
- >= 95% of total matrix edges per release run while matrix is still evolving.
- Uncovered edges MUST be emitted in artifact `topology-uncovered-edges.json` and validated as non-P0/P1 before pass eligibility.
- When release-controlled lane edge matrix churn is <= 2% for 4 consecutive release cycles, trigger recommendation to raise overall required coverage to 100% and track transition decision in release governance notes.

## 7) Required JSON Evidence Artifacts
### 7.1 `topology-policy-bundle.json`
Required fields:
- `policy_version`
- `policy_checksum` (sha256)
- `interaction_matrix_version`
- `compiler_version`
- `generated_at`
- `source_commit_sha`
- `mesh_control_plane_version`
- `mesh_data_plane_version`

### 7.2 `topology-probe-results.json`
Required fields:
- `run_id`, `lane`, `environment_group`
- `source_commit_sha`
- `release_artifact_id`
- `release_artifact_checksum`
- `policy_version`, `policy_checksum`
- `identity_snapshot_checksum_compile`
- `identity_snapshot_checksum_runtime`
- `results[]` where each entry contains:
  - `edge_id`
  - `source_stack_identity`
  - `destination_stack_identity`
  - `protocol`, `port`, `direction`
  - `expected` (`allow|deny`)
  - `observed` (`allow|deny|timeout|error`)
  - `verdict` (`pass|fail`)
  - `reason_code`
  - `telemetry_ref` (log/trace IDs)
  - `timestamp`

### 7.3 `topology-uncovered-edges.json`
Required fields:
- `run_id`, `lane`, `environment_group`
- `interaction_matrix_version`
- `coverage_thresholds` (`p0_p1_required`, `overall_required`)
- `uncovered_edges[]` where each entry includes:
  - `edge_id`
  - `criticality` (`P0|P1|P2|P3`)
  - `reason`
  - `owner`
- `criticality_validation` (`PASS|FAIL`)

### 7.4 `topology-gate-verdict.json`
Required fields:
- `run_id`, `lane`
- `overall_verdict` (`PASS|FAIL|FAIL_CLOSED`)
- `failed_edges[]`
- `unknown_edges[]`
- `coverage_summary` (required vs executed vs passed)
- `hard_fail_reasons[]`
- `policy_version`, `policy_checksum`
- `platform_allowlist_version`, `platform_allowlist_checksum`
- `source_commit_sha`, `release_artifact_id`, `release_artifact_checksum`

## 8) CI Fail Conditions (Non-Waivable)
Topology gate MUST hard-fail CI (no warn-only, no waiver) when any occurs:
1. Any forbidden edge probe is not denied.
2. Any required allowed edge probe fails reachability validation.
3. Probe coverage requirement is not met, or uncovered-edge criticality validation fails.
4. Policy/evidence checksum mismatch or missing version binding.
5. Evidence missing required fields or unsigned/tampered payload.
6. Unknown runtime edge observed that is absent from interaction matrix and not present in governed platform/system allowlist.
7. Stack identity derivation mismatch between policy compile stage and runtime probe stage.
8. Mesh control-plane failure/degradation invalidates convergence guarantees.

These are non-waivable for P0 and release-controlled lanes.

## 9) Policy Binding to Release Evidence
All topology evidence MUST bind to:
- `source_commit_sha`
- `release_artifact_id`
- `release_artifact_checksum`
- `policy_version`
- `policy_checksum`

Evidence generated under a prior policy checksum or artifact checksum is invalid for current release decisioning.

## 10) Operational Governance
- Policy compiler and probe runner versions are controlled artifacts.
- Changes to edge semantics or identity derivation require Infra + Security review.
- Any emergency policy exception must be represented as versioned matrix change; out-of-band runtime overrides are prohibited.
- Platform/system allowlist changes require dual approval (Infra + Security), version increment, checksum update, and change-ticket reference.

## 11) Acceptance Criteria Status (P5-T4)
- [x] Implementation options evaluated and primary path selected.
- [x] Machine-verifiable allowed/forbidden edge checks defined.
- [x] Required JSON evidence formats specified.
- [x] CI hard-fail, non-waivable semantics defined.
- [x] Policy checksum/version binding to release evidence defined.
- [x] Interaction matrix runtime-edge and stack identity derivation alignment defined.
- [x] Unknown-edge detection precision and platform/system allowlist governance defined.
- [x] Coverage rigor visibility and stabilization trigger defined.
- [x] Mesh operational controls and failure-mode policy defined.
- [x] Reachability timeout guardrail separated from performance assertions.
- [x] Identity derivation drift mitigation and admission validation references defined.
