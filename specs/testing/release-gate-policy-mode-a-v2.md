# Release Gate Policy - Mode A v2

## Purpose
Define objective gate criteria for release candidates using Mode A Gateway-orchestrated test evidence.

## Gate Inputs
- Test lane results: unit, contract, integration, e2e, security, concurrency, topology
- Environment fingerprint and drift check
- Dataset/version metadata
- Run artifacts and logs

## Policy Rules

### Hard Fail Conditions
- Topology lane failure (including any denied runtime edge per interaction matrix); no warn-only outcome is permitted.
- Contract lane failure in any required interface; no warn-only outcome is permitted.
- Any P0 requirement failing its mapped required test lane
- Security critical finding unresolved
- Environment drift hard-fail signal detected (see Environment Drift Signals)

### Pass Conditions
- All required lanes completed and passing for P0 mappings
- P1 mappings completed with no unresolved failures, unless release is in Conditional Hold with all required guardrails satisfied
- NFR thresholds satisfied (latency, error rate, availability, deterministic rerun stability)
- Evidence bundle complete, immutable, and artifact-ID bound

### Conditional Hold
- P1 and/or P2 failures may enter hold/review only when no P0 impact exists and no topology/contract/security-critical hard-fail condition exists
- Holds require a documented risk assessment (owner, impact scope, mitigation, expiry, rollback trigger)
- Explicit owner signoff required for any temporary waiver
- Waivers are time-bounded and tracked

## Environment Drift Signals
Drift checks are machine-evaluated against the approved pre-run fingerprint for the same candidate artifact.

Hard-fail drift signals:
- Container image digest delta for any required lane workload
- Helm values checksum delta for any required chart/release
- Topology policy checksum delta
- Dataset seed ID or dataset version mismatch
- Clock mode mismatch (expected deterministic/frozen clock mode vs observed mode)

Reviewable drift signals (Conditional Hold eligible only when all hard-fail signals are absent):
- Non-topology observability-only config checksum delta with unchanged lane binaries and manifests

## Evidence Requirements
- Requirement traceability matrix
- Lane-level summaries with timestamps, commit SHA, and release artifact ID
- Artifact checksums and retention references
- Policy version and evaluator outcome
- Evidence bundle manifest checksum; any checksum mutation invalidates prior gate evidence

## Metrics Threshold Baseline (v2)
- Deterministic rerun stability:
  - integration/contract/topology lanes: >=99% rerun stability on unchanged commit + environment + dataset/profile
  - P0 E2E journeys: flake rate <=1.0% per journey over rolling last 200 executions (equivalent stability >=99%)
- E2E critical path success: 100% for P0 flows
- Contract compatibility: 100% for required interfaces
- Security critical/high unresolved: 0
- Latency regression tolerance: <=10% p95 degradation versus approved baseline for the same journey; orchestration start <=30s p95
- Availability/error-rate ceiling: run completion event emitted 100% for required lanes; P0 mapped flow error rate = 0
- Maximum allowed E2E duration window: full required-lane execution <=45 min p95 per release candidate

## Governance
- Policy changes require architecture + QA approval
- Versioned policy must be attached to each release decision
