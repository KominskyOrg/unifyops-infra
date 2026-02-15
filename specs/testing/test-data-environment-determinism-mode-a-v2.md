# Test Data & Environment Determinism - Mode A v2

## Purpose
Establish deterministic, reproducible test inputs and environment controls for Mode A test execution.

## Determinism Principles
- Seeded data generation for all suites
- Immutable dataset versioning and provenance
- Environment profile pinning (runtime, config, dependency versions)
- Repeatable provisioning and teardown

## Required Controls

### Data Controls
- Dataset IDs and versions tracked per run
- Tenant/user fixtures explicitly defined
- Idempotent seed and cleanup routines
- Gated runs MUST enforce seed-only DB mutation in CI (manual data edits are prohibited)

### Environment Controls
- Fingerprinted environment MUST include machine-checkable fields: Helm values checksum, image digest (not tag), DB migration version, dataset version, topology policy checksum, feature flag snapshot, and clock mode
- Drift detection MUST evaluate runtime state against the declared baseline profile artifact for the candidate
- Drift policy MUST hard-fail on deltas in: image digest, Helm values checksum, DB migration version, dataset version, topology policy checksum, feature flag snapshot, or clock mode; all other deltas are ignored unless explicitly listed as fail-on-drift in the baseline profile artifact
- Disallow mixed-profile execution in same gate cycle

### Execution Controls
- Fixed orchestration order for required lanes
- Retry policy documented and bounded
- No retries for contract/topology/security failures; retries are allowed only for explicitly classified transient failures within bounded retry cap
- Flake classification required for non-deterministic behavior
- Rebuilt artifacts invalidate prior determinism evidence

## Acceptance Criteria
- Integration/contract/topology lanes MUST achieve >=99% rerun stability for unchanged commit+environment profile
- P0 E2E lanes MUST remain <=1.0% flake rate per journey over the rolling last 200 executions (equivalently >=99% journey stability)
- Drift check failures block promotion
- Full metadata captured in evidence bundle for each candidate, bound to release artifact ID + commit SHA + checksum

## Operational Notes
- Determinism policy applies to integration/e2e/security/concurrency/topology lanes
- Unit lane may run outside full environment profile only if toolchain/version metadata is captured per run
- Unit test flakiness is not tolerated
