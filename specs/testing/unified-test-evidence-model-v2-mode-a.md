# P6-T1 Unified Test Evidence Model v2 (Mode A)

Status: Normative (cross-lane evidence model)
Scope: Canonical evidence contract across all Mode A release-controlled lanes.
Depends on: release gate policy, topology gate, interaction matrix, scenario/journey catalogs.

## 1) Purpose
Define a single, canonical evidence schema and governance model so every gate decision is reproducible, cryptographically verifiable, and traceable from PRD requirement to executed gate outcomes.

## 2) Canonical Evidence Envelope
All lane artifacts MUST be representable inside a shared envelope with consistent identity, lineage, integrity, and verdict semantics.

Canonical JSON schema (normative reference model):
```json
{
  "schema_version": "unified-evidence-v2",
  "evidence_id": "uuid",
  "generated_at": "RFC3339 timestamp",
  "lane": "string",
  "environment_group": "string",
  "run_id": "string",
  "toolchain": {
    "generator": "string",
    "generator_version": "string"
  },
  "lineage": {
    "source_commit_sha": "40-char git sha",
    "release_artifact_id": "string",
    "release_artifact_checksum": "sha256:...",
    "build_id": "string"
  },
  "environment_fingerprint": {
    "cluster_id": "string",
    "namespace_set": ["string"],
    "runtime_profile": "string",
    "fingerprint_checksum": "sha256:..."
  },
  "policy_bindings": {
    "release_gate_policy_version": "string",
    "release_gate_policy_checksum": "sha256:...",
    "topology_policy_version": "string",
    "topology_policy_checksum": "sha256:...",
    "admission_policy_versions": [
      {
        "policy_name": "string",
        "version": "string",
        "checksum": "sha256:..."
      }
    ]
  },
  "linkage": {
    "prd_id": "string",
    "boundary_ids": ["string"],
    "scenario_ids": ["string"],
    "journey_ids": ["string"],
    "edge_ids": ["string"]
  },
  "gate_results": [
    {
      "gate_id": "string",
      "gate_type": "topology|functional|security|resilience|...",
      "result": "PASS|FAIL|FAIL_CLOSED",
      "hard_fail_reasons": ["string"],
      "evidence_refs": ["uri-or-artifact-id"]
    }
  ],
  "integrity": {
    "payload_checksum": "sha256:...",
    "signature": {
      "algorithm": "sigstore|cosign|x509|pgp",
      "signature_ref": "uri",
      "key_id": "string"
    },
    "immutability": {
      "storage_class": "WORM|immutable-object-lock",
      "retention_until": "RFC3339 timestamp"
    }
  }
}
```

## 3) Required Metadata (Non-Optional)
Every evidence bundle MUST include and validate:
- `source_commit_sha`
- `release_artifact_id`
- `release_artifact_checksum`
- `environment_fingerprint` + `fingerprint_checksum`
- policy versions and checksums relevant to gate decisioning

Missing any required metadata is a hard validation failure.

## 4) Linkage Model (Traceability)
Required linkage chain:
- `PRD ID -> boundary IDs -> scenario IDs -> journey IDs -> gate results`

Normative rules:
- Each `gate_results[]` entry MUST reference at least one boundary/scenario/journey ID.
- If a gate enforces runtime topology, related `edge_ids[]` MUST be present.
- The linkage graph MUST be machine-traversable (no free-text-only references).
- Evidence validation MUST ensure referenced IDs exist in authoritative catalogs for the release train.

## 5) Immutability, Checksum, and Signature Requirements
- All evidence payloads MUST be content-addressable and include `payload_checksum` (sha256 minimum).
- All release-controlled lane evidence MUST be signed before gate evaluation.
- Signature verification MUST occur during gate evaluation; unverifiable signatures are `FAIL`.
- Evidence records MUST be stored in immutable/WORM storage with retention lock.
- Mutation of previously accepted evidence invalidates associated gate decisions and forces rerun.

## 6) Missing/Invalid Evidence Fail Conditions
The unified evidence validator MUST emit `FAIL` for any of the following:
1. Missing required metadata or linkage fields.
2. Checksum mismatch (lineage, policy bindings, or payload integrity).
3. Signature missing/invalid/untrusted key.
4. Environment fingerprint mismatch against run context.
5. Unknown schema version or schema validation failure.
6. Referenced IDs (PRD/boundary/scenario/journey/edge) absent from source catalogs.
7. Evidence timestamp outside approved gate execution window.

For release-controlled lanes, these are non-waivable and must block promotion.

## 7) Retention, Access, and Audit Retrieval Expectations
Retention:
- Minimum retention for release evidence: 400 days (or stricter policy baseline).
- Security- or incident-relevant evidence MAY require extended retention per policy.

Access control:
- Read access: least privilege, role-scoped (Release, Infra, Security, Audit).
- Write access: restricted to signed pipeline identities.
- Delete/shorten retention: prohibited without dual authorization and policy exception record.

Audit retrieval:
- Evidence retrieval MUST support deterministic query by `release_artifact_id`, `source_commit_sha`, `run_id`, and `prd_id`.
- Retrieval SLA target: evidence package available for audit export within 15 minutes.
- Export package MUST include: envelope JSON, detached signatures, checksum manifest, and referenced gate artifact index.

## 8) Acceptance Criteria Status (P6-T1)
- [x] Canonical cross-lane evidence schema defined (JSON).
- [x] Required metadata (commit SHA, release artifact ID, environment fingerprint, policy versions/checksums) defined.
- [x] Linkage model (`PRD -> boundary/scenario/journey -> gate results`) defined.
- [x] Immutability/checksum/signature requirements defined.
- [x] Missing/invalid evidence fail conditions defined.
- [x] Retention/access/audit retrieval expectations defined.
