# P5-T3 CI Resource Isolation & Parallelism Policy v2 (Mode A)

Status: Normative (policy/spec)
Scope: CI execution-lane isolation, parallelism governance, and release gating controls for Mode A.
Depends on: `release-gate-policy-mode-a-v2.md`, `test-data-environment-determinism-mode-a-v2.md`, `contract-gate-integration-mode-a-v2.md`.

## 1) Purpose
Define deterministic CI lane isolation and bounded parallelism rules that prevent cross-run interference, hidden contention, and non-reproducible gate outcomes.

## 2) Namespace/Database Isolation Policy
Each CI run MUST execute in isolated tenancy scope by lane.

Required controls:
- Unique namespace per run ID for Kubernetes-scoped workloads.
- Unique database/schema per run ID.
- Prohibit shared mutable schemas/tables between concurrent release-gated runs.
- Run-scoped queue/topic naming with enforced prefixes (e.g., `run-{id}-*`).
- Ephemeral credentials scoped to run namespace + DB/schema; credentials revoked at teardown.

### 2.1 DB Isolation Escalation Policy (Schema -> Isolated DB Instance)
Schema-per-run is the minimum baseline. Escalation to isolated DB instance is REQUIRED when any escalation trigger is true:
- Lane is `release-controlled` (always isolated instance, no exception).
- Lane is `concurrency` and profile is `HIGH` (>=2 concurrent determinism-sensitive jobs in same environment group).
- Suite requires DB-level operations not safely namespaced by schema (global extensions, collation/locale mutation, replication slots, WAL/archive settings, DB-level locks).
- Historical contention exceeds lane threshold in two consecutive evaluation windows (see Section 4.1).
- Data-governance policy requires physical/logical data-plane separation for controlled lanes.

If required escalation cannot be provisioned, lane status is `FAIL` for release-gated evaluation.

## 3) Max Parallelism and Queue Strategy by Lane
Parallelism must be explicit and bounded with queue backpressure.

| Lane | Max Parallel Jobs | Queue Strategy | Admission Rule |
|---|---:|---|---|
| `fast-feedback` (lint/unit) | 20 | Shared high-throughput queue | Admit until max; preemptible |
| `integration` | 8 | Weighted fair queue | Cap per repo/service to avoid starvation |
| `contract` | 6 | FIFO per interface domain | Block on dependency lock conflicts |
| `e2e` | 4 | Priority queue (P0 > P1 > P2) | P0 always admitted first |
| `concurrency` | 2 | Serialized by shared-resource class | One job per resource class unless fully isolated |
| `release-controlled` | 1 | Strict single-flight queue | No parallel peer in same environment group |

Rules:
- Queue policy and effective max parallelism MUST be emitted in run metadata.
- Scheduler MUST reject over-cap submissions (no silent bursting).
- Release candidate runs have priority over non-release workloads in constrained lanes.

## 4) Shared Resource Contention Mitigation Controls
CI platform MUST enforce the following controls for shared infra dependencies:
- Resource class locks for scarce dependencies (DB clusters, message brokers, external sandboxes).
- Token-bucket limits for external APIs to avoid retry storms and coupled failures.
- Mandatory fixture partition keys for caches/object stores.
- No shared dead-letter queues between concurrently executing release-gated runs.
- Run teardown verification to ensure resource reclamation before next admission.

### 4.1 Contention Signal Tuning Semantics
Signals are machine-evaluated with lane-specific thresholds and rolling windows:

| Lane | Evaluation Window | Lock Wait Saturation | Queue Lag Breach | CPU/Mem Steal | Cross-Run Collision |
|---|---|---|---|---|---|
| `release-controlled` | 5m rolling, sampled every 15s | > 0.10 for 2 samples | p95 > 30s for 2 samples | > 10% for 2 samples | any event |
| `concurrency` | 10m rolling, sampled every 30s | > 0.15 for 3 samples | p95 > 45s for 3 samples | > 15% for 3 samples | any event |
| `e2e` / `contract` / `integration` | 15m rolling, sampled every 30s | > 0.20 for 3 samples | p95 > 60s for 3 samples | > 20% for 3 samples | any event |
| `fast-feedback` | 15m rolling, sampled every 60s | > 0.30 for 3 samples | p95 > 120s for 3 samples | > 30% for 3 samples | any event |

Signal classification:
- Gated P0 lanes (`release-controlled`, P0 `concurrency`) treat threshold breach as HARD-FAIL.
- Non-gated lanes treat breaches as diagnostic unless cross-run collision occurs; collision is always `FAIL`.

Anti-false-positive guidance (mandatory):
- Require N-consecutive samples as above before declaring breach (no single-sample fail).
- Exclude known maintenance windows and infra incidents labeled by platform incident ID.
- Normalize queue lag by admitted concurrency and resource class to avoid penalizing intentional throttling.
- Use monotonic clocks and synchronized timestamps (NTP-verified drift <= 100ms) for all sampled signals.

## 5) Controlled-Lane Requirements for Determinism-Sensitive Suites
Determinism-sensitive suites (`concurrency`, ordering-heavy integration, replay/idempotency validation) MUST execute only in controlled lanes with:
- fixed replica counts,
- pinned CPU/memory requests and limits,
- autoscaling disabled during run window,
- isolated DB/schema (or isolated DB instance when escalation triggers apply) and dedicated queues/topics,
- fixed clock/source-of-time mode per suite contract,
- deterministic seed binding in manifest.

Suites marked determinism-sensitive are non-passable when executed outside controlled lanes.

## 6) Scheduler/Lock Governance Hardening
- A single source-of-truth scheduler policy document/version (`scheduler_policy_version`) MUST govern lane admission, parallelism caps, and lock ordering.
- All runners MUST fetch and attest to the same policy checksum before admission decisions.
- Ad-hoc, local, or runner-side config overlays that alter scheduling/locking behavior are explicitly prohibited.
- Any run detected using non-authoritative scheduler settings is `FAIL` for gated lanes and `INVALID` for evidence reuse.

## 7) External Sandbox Governance
External sandbox dependencies MUST be controlled via allowlisted inventory and capacity model.

Required controls:
- Maintain `external-sandbox-inventory.json` with immutable IDs, owner, endpoint class, auth scope, and max concurrent leases.
- Capacity model MUST define per-lane lease quotas and hard caps; scheduler denies admissions that exceed allowlisted capacity.
- Lease allocation MUST be lock-backed and time-bounded with heartbeat + expiry.

Deadlock prevention and escalation:
- Lock acquisition order MUST be deterministic (`db` -> `broker` -> `sandbox`).
- If lock wait exceeds lane threshold window twice, trigger deadlock breaker: release partial leases, backoff with jitter, retry once.
- On repeated deadlock (2 breaker failures), escalate to `sandbox-capacity-exhausted` violation and hard-fail gated lanes.

## 8) Evidence Outputs for Isolation Compliance
Each run MUST publish the following evidence artifacts:
- `ci-isolation-manifest.json`:
  - run ID, lane, namespace, DB/schema IDs (or DB instance ID), queue/topic IDs, resource class locks
  - configured max parallelism + observed parallelism
  - scheduler policy version/checksum and admission decision
- `ci-resource-fingerprint.json`:
  - replicas, requests/limits, autoscaling state, node pool class
- `ci-contention-signals.json`:
  - queue lag, lock waits, throttle events, collision detections, evaluated window and threshold profile
- `ci-isolation-verdict.json`:
  - pass/fail per control, violation codes, release-gate impact

### 8.1 Evidence Binding Tightening
All isolation evidence artifacts MUST bind to:
- `commit_sha`
- `release_artifact_id`
- `release_artifact_checksum` (sha256)
- `scheduler_policy_version` + `scheduler_policy_checksum`

Rebuild rule:
- Evidence generated for one artifact checksum MUST NOT be reused for a different rebuild, even if `commit_sha` is unchanged.
- Reused evidence across rebuilds is explicitly invalid and treated as tampering (`FAIL`).

Missing or inconsistent evidence artifacts produce `FAIL` for gated lanes.

## 9) Release-Blocking Conditions (Isolation Violations)
Release MUST be blocked when any of the following occur in required lanes:
1. Namespace/database isolation violation (shared mutable scope across concurrent runs).
2. Required DB escalation trigger met but run executed without isolated DB instance.
3. Observed parallelism exceeds lane max or scheduler bursts beyond declared cap.
4. Determinism-sensitive suite executed outside controlled lane.
5. Shared resource contention mitigation control missing or bypassed.
6. Cross-run queue/topic/key collision detected.
7. Autoscaling enabled during controlled-lane run window.
8. Non-authoritative scheduler policy/config used for decisioning.
9. Required isolation evidence artifact missing, tampered, or unbound to run ID/commit SHA/release artifact checksum.

No warn-only mode is allowed for P0-mapped lane isolation failures.

## 10) Governance and Change Control
- Parallelism caps and lane policies are versioned and reviewed by Infra + QA.
- Any policy relaxation requires explicit risk approval and expiry timestamp.
- Policy version/checksum used for decisioning MUST be embedded in `ci-isolation-verdict.json`.

## 11) Acceptance Criteria Status (P5-T3)
- [x] Namespace/database isolation policy defined with escalation-to-instance triggers.
- [x] Max parallelism and queue strategy by lane defined.
- [x] Contention signal semantics defined: lane thresholds, windows, hard-fail vs diagnostic behavior.
- [x] Scheduler/lock governance hardened with single source-of-truth policy and no ad-hoc bypass.
- [x] External sandbox allowlist, capacity model, and deadlock escalation behavior defined.
- [x] Evidence outputs and release-blocking conditions tightened with commit/artifact/checksum binding and rebuild invalidation.
