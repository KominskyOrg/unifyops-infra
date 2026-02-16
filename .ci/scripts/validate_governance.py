#!/usr/bin/env python3
"""Governance validation: linkage, drift, cohesion, determinism, role presence, self-check.

Extracted from corpus-evidence-ci.yml inline steps to reduce workflow complexity.
All lane semantics and reason-code outputs are preserved exactly.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _env(key: str, default: str = "") -> str:
    return os.environ.get(key, default).strip()


def _env_bool(key: str) -> bool:
    return _env(key).lower() in {"true", "1", "yes", "on"}


def _release_lane() -> bool:
    return _env("RELEASE_CONTROLLED_LANE").lower() == "true"


def _lane_label() -> str:
    return "release" if _release_lane() else "non-release"


def _normalize_lane(value: object) -> str:
    token = str(value or "").strip().lower()
    if token in {"release", "release-controlled", "release_controlled", "true", "1", "yes", "on"}:
        return "release"
    if token in {"non-release", "non_release", "false", "0", "no", "off"}:
        return "non-release"
    return "unknown" if token == "" else token


def _load_json(path: Path, label: str, reasons: list[dict]) -> dict:
    if not path.is_file():
        reasons.append({"code": f"CMX_DRIFT_ARTIFACT_MISSING", "message": f"{label} artifact missing: {path.as_posix()}"})
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        reasons.append({"code": "CMX_DRIFT_ARTIFACT_INVALID", "message": f"{label} artifact parse failure: {exc}"})
        return {}
    if not isinstance(payload, dict):
        reasons.append({"code": "CMX_DRIFT_ARTIFACT_INVALID", "message": f"{label} artifact must be a JSON object"})
        return {}
    return payload


def _emit_reasons(reasons: list[dict], release: bool) -> None:
    for r in reasons:
        code, msg = r["code"], r["message"]
        if release:
            print(f"::error::[POLICY][RELEASE][{code}] {msg}")
        else:
            print(f"::warning::[POLICY][NON-RELEASE][{code}] {msg}")


def _sort_reasons(reasons: list[dict]) -> list[dict]:
    return sorted(reasons, key=lambda r: (r.get("code", ""), r.get("message", "")))


def _gate(reasons: list[dict], release: bool) -> str:
    if not reasons:
        return "pass"
    return "fail" if release else "warn"


# ---------------------------------------------------------------------------
# 1. Self-check policy outcome artifact JSON
# ---------------------------------------------------------------------------

def self_check_policy_outcome() -> None:
    policy_path = Path(_env("POLICY_OUTCOME_JSON"))
    ref_mode = _env("SUMMARY_REF_MODE", "unknown")
    lockfile_present = _env("SUMMARY_LOCKFILE_PRESENT", "false")
    lane = _env("SUMMARY_LANE", _env("RELEASE_CONTROLLED_LANE"))

    if not policy_path.is_file():
        print(f"::warning::policy outcome JSON missing at {policy_path}; writing deterministic fallback artifact")
        policy_path.parent.mkdir(parents=True, exist_ok=True)
        fallback = {
            "lane": lane,
            "ref_mode": ref_mode,
            "lockfile_present": lockfile_present.lower() == "true",
            "completeness_mode": "none",
            "gate_result": "unknown",
            "reasons": [
                {
                    "code": "CMX_POLICY_OUTCOME_ABSENT",
                    "message": "policy outcome artifact was not generated before self-check",
                }
            ],
        }
        policy_path.write_text(json.dumps(fallback, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    payload = json.loads(policy_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit(f"policy outcome payload must be object: {policy_path}")
    print(f"policy outcome JSON validated: {policy_path}")


# ---------------------------------------------------------------------------
# 2. Enforce artifact role presence by lane
# ---------------------------------------------------------------------------

def enforce_artifact_role_presence() -> None:
    manifest_path = Path(_env("ARTIFACT_MANIFEST_JSON"))
    release = _release_lane()
    required_roles = {"matrix", "summary", "case_reports", "policy_outcome", "metadata"}

    present_roles: set[str] = set()
    if manifest_path.is_file():
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        for entry in data.get("entries", []):
            role = str(entry.get("role", "")).strip()
            if role:
                present_roles.add(role)

    missing = sorted(required_roles - present_roles)
    if not missing:
        print("artifact role presence check: all required roles present")
    elif release:
        for role in missing:
            print(f"::error::[POLICY][RELEASE][ARTIFACT_ROLE_MISSING] required artifact role missing from manifest: {role}")
        raise SystemExit(1)
    else:
        for role in missing:
            print(f"::warning::[POLICY][NON-RELEASE] required artifact role missing from manifest (warning-only in non-release lane): {role}")


# ---------------------------------------------------------------------------
# 3. Validate cross-artifact linkage integrity
# ---------------------------------------------------------------------------

def validate_linkage_integrity() -> None:
    release = _release_lane()
    expected_lane = _lane_label()
    expected_ref_mode = _env("SUMMARY_REF_MODE", "unknown")

    matrix_path = Path(_env("CORPUS_MATRIX"))
    policy_path = Path(_env("POLICY_OUTCOME_JSON"))
    metadata_path = Path(_env("CORPUS_OUTPUT_DIR")) / "corpus-artifacts-metadata.json"
    manifest_path = Path(_env("ARTIFACT_MANIFEST_JSON"))
    outcome_path = Path(_env("ARTIFACT_LINKAGE_OUTCOME_JSON"))

    reasons: list[dict] = []

    # metadata ref checks
    metadata: dict = {}
    if metadata_path.is_file():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    else:
        reasons.append({"code": "CMX_LINKAGE_METADATA_MISSING", "message": f"metadata artifact missing: {metadata_path.as_posix()}"})

    if metadata:
        expected_refs = {
            "corpus_matrix_path": matrix_path.as_posix(),
            "policy_outcome_path": policy_path.as_posix(),
            "artifact_manifest_path": manifest_path.as_posix(),
        }
        for key, expected in expected_refs.items():
            actual = str(metadata.get(key, "")).strip()
            if actual != expected:
                reasons.append({
                    "code": "CMX_LINKAGE_METADATA_REF_MISMATCH",
                    "message": f'metadata.{key} mismatch: expected={expected} actual={actual or "<empty>"}',
                })

    # policy outcome parse
    policy: dict = {}
    if policy_path.is_file():
        try:
            payload = json.loads(policy_path.read_text(encoding="utf-8"))
            if isinstance(payload, dict):
                policy = payload
            else:
                reasons.append({"code": "CMX_LINEAGE_POLICY_OUTCOME_INVALID", "message": "policy outcome artifact must be a JSON object"})
        except Exception as exc:
            reasons.append({"code": "CMX_LINEAGE_POLICY_OUTCOME_INVALID", "message": f"policy outcome artifact parse failure: {exc}"})
    else:
        reasons.append({"code": "CMX_LINEAGE_POLICY_OUTCOME_MISSING", "message": f"policy outcome artifact missing: {policy_path.as_posix()}"})

    policy_lane = _normalize_lane(policy.get("lane")) if policy else "unknown"
    policy_ref_mode = str(policy.get("ref_mode", "")).strip().lower() if policy else ""
    policy_gate_result = str(policy.get("gate_result", "")).strip().lower() if policy else ""

    # manifest parse
    manifest: dict = {}
    manifest_entries: dict[str, str] = {}
    if manifest_path.is_file():
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            manifest = payload
            for entry in payload.get("entries", []):
                p = str(entry.get("path", "")).strip()
                if p:
                    manifest_entries[p] = str(entry.get("sha256", "")).strip().lower()
        else:
            reasons.append({"code": "CMX_LINKAGE_MANIFEST_INVALID", "message": "artifact manifest must be a JSON object"})
    else:
        reasons.append({"code": "CMX_LINKAGE_MANIFEST_MISSING", "message": f"artifact manifest missing: {manifest_path.as_posix()}"})

    manifest_lane = _normalize_lane(manifest.get("lane")) if manifest else "unknown"
    manifest_ref_mode = str(manifest.get("ref_mode", "")).strip().lower() if manifest else ""
    manifest_gate_result = str(manifest.get("gate_result", "")).strip().lower() if manifest else ""

    # field presence
    if policy and (not policy_ref_mode or not policy_gate_result or policy_lane == "unknown"):
        reasons.append({"code": "CMX_LINEAGE_POLICY_FIELDS_MISSING", "message": "policy outcome missing one or more required lineage fields: lane/ref_mode/gate_result"})
    if manifest and (not manifest_ref_mode or not manifest_gate_result or manifest_lane == "unknown"):
        reasons.append({"code": "CMX_LINEAGE_MANIFEST_FIELDS_MISSING", "message": "artifact manifest missing one or more required lineage fields: lane/ref_mode/gate_result"})

    # cross-artifact consistency
    lane_values = sorted(set(v for v in (expected_lane, policy_lane, manifest_lane) if v and v != "unknown"))
    if len(lane_values) > 1:
        reasons.append({"code": "CMX_LINEAGE_LANE_MISMATCH", "message": f"lane mismatch across artifacts: expected={expected_lane} policy={policy_lane} manifest={manifest_lane}"})

    ref_values = sorted(set(v for v in (expected_ref_mode, policy_ref_mode, manifest_ref_mode) if v))
    if len(ref_values) > 1:
        reasons.append({"code": "CMX_LINEAGE_REF_MODE_MISMATCH", "message": f'ref_mode mismatch across artifacts: expected={expected_ref_mode} policy={policy_ref_mode or "<empty>"} manifest={manifest_ref_mode or "<empty>"}'})

    gate_values = sorted(set(v for v in (policy_gate_result, manifest_gate_result) if v))
    if len(gate_values) > 1:
        reasons.append({"code": "CMX_LINEAGE_GATE_RESULT_MISMATCH", "message": f'gate_result mismatch across artifacts: policy={policy_gate_result or "<empty>"} manifest={manifest_gate_result or "<empty>"}'})

    # SHA verification against manifest
    summary_path = Path(_env("CORPUS_SUMMARY"))
    required_files = [
        ("matrix", matrix_path),
        ("summary", summary_path),
        ("policy_outcome", policy_path),
        ("metadata", metadata_path),
    ]
    reports_dir = Path(_env("CORPUS_REPORTS_DIR"))
    if reports_dir.is_dir():
        for rp in sorted((p for p in reports_dir.rglob("*") if p.is_file()), key=lambda p: p.as_posix()):
            required_files.append(("case_reports", rp))

    for role, file_path in required_files:
        if not file_path.is_file():
            continue
        key = file_path.as_posix()
        actual_sha = hashlib.sha256(file_path.read_bytes()).hexdigest()
        manifest_sha = manifest_entries.get(key, "")
        if not manifest_sha:
            reasons.append({"code": "CMX_LINKAGE_MANIFEST_ENTRY_MISSING", "message": f"manifest entry missing for emitted {role} artifact: {key}"})
        elif manifest_sha.lower() != actual_sha.lower():
            reasons.append({"code": "CMX_LINKAGE_MANIFEST_SHA_MISMATCH", "message": f"manifest sha mismatch for {key}: expected={actual_sha.lower()} actual={manifest_sha.lower()}"})

    reasons = _sort_reasons(reasons)
    gate_result = _gate(reasons, release)
    _emit_reasons(reasons, release)

    outcome = {
        "schema_version": "artifact-linkage-outcome-v1",
        "lane": expected_lane,
        "ref_mode": expected_ref_mode,
        "policy_gate_result": policy_gate_result or "unknown",
        "gate_result": gate_result,
        "reasons": reasons,
    }
    outcome_path.parent.mkdir(parents=True, exist_ok=True)
    outcome_path.write_text(json.dumps(outcome, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote artifact linkage outcome: {outcome_path}")

    if release and reasons:
        raise SystemExit(1)


# ---------------------------------------------------------------------------
# 4. Validate policy drift across governance artifacts
# ---------------------------------------------------------------------------

def validate_policy_drift() -> None:
    release = _release_lane()
    expected_lane = _lane_label()

    policy_path = Path(_env("POLICY_OUTCOME_JSON"))
    reason_index_path = Path(_env("REASON_CODES_INDEX_JSON"))
    linkage_path = Path(_env("ARTIFACT_LINKAGE_OUTCOME_JSON"))
    out_path = Path(_env("POLICY_DRIFT_OUTCOME_JSON"))

    reasons: list[dict] = []

    policy = _load_json(policy_path, "policy_outcome", reasons)
    reason_index = _load_json(reason_index_path, "reason_codes_index", reasons)
    linkage = _load_json(linkage_path, "artifact_linkage_outcome", reasons)

    policy_lane = _normalize_lane(policy.get("lane")) if policy else "unknown"
    reason_lane = _normalize_lane(reason_index.get("lane")) if reason_index else "unknown"
    linkage_lane = _normalize_lane(linkage.get("lane")) if linkage else "unknown"

    policy_gate = str(policy.get("gate_result", "")).strip().lower() if policy else ""
    reason_policy_gate = str(reason_index.get("policy_gate_result", "")).strip().lower() if reason_index else ""
    linkage_gate = str(linkage.get("gate_result", "")).strip().lower() if linkage else ""
    reason_linkage_gate = str(reason_index.get("artifact_linkage_gate_result", "")).strip().lower() if reason_index else ""
    policy_ref_mode = str(policy.get("ref_mode", "")).strip().lower() if policy else ""
    linkage_ref_mode = str(linkage.get("ref_mode", "")).strip().lower() if linkage else ""

    lane_values = sorted(set(v for v in (expected_lane, policy_lane, reason_lane, linkage_lane) if v and v != "unknown"))
    if len(lane_values) > 1:
        reasons.append({"code": "CMX_DRIFT_LANE_MISMATCH", "message": f"lane mismatch across artifacts: expected={expected_lane} policy={policy_lane} reason_index={reason_lane} linkage={linkage_lane}"})

    if policy_gate and reason_policy_gate and policy_gate != reason_policy_gate:
        reasons.append({"code": "CMX_DRIFT_POLICY_GATE_RESULT_MISMATCH", "message": f"policy gate_result mismatch: policy_outcome={policy_gate} reason_codes_index.policy_gate_result={reason_policy_gate}"})

    if linkage_gate and reason_linkage_gate and linkage_gate != reason_linkage_gate:
        reasons.append({"code": "CMX_DRIFT_LINKAGE_GATE_RESULT_MISMATCH", "message": f"artifact linkage gate_result mismatch: artifact_linkage_outcome={linkage_gate} reason_codes_index.artifact_linkage_gate_result={reason_linkage_gate}"})

    ref_values = sorted(set(v for v in (policy_ref_mode, linkage_ref_mode) if v))
    if len(ref_values) > 1:
        reasons.append({"code": "CMX_DRIFT_REF_MODE_MISMATCH", "message": f'ref_mode mismatch across artifacts: policy_outcome={policy_ref_mode or "<empty>"} artifact_linkage_outcome={linkage_ref_mode or "<empty>"}'})

    if reason_index:
        if not isinstance(reason_index.get("reason_codes"), list):
            reasons.append({"code": "CMX_DRIFT_REASON_INDEX_SHAPE_INVALID", "message": "reason_codes_index.reason_codes must be an array"})
        if not isinstance(reason_index.get("severity_totals"), dict):
            reasons.append({"code": "CMX_DRIFT_REASON_INDEX_SHAPE_INVALID", "message": "reason_codes_index.severity_totals must be an object"})

    reasons = _sort_reasons(reasons)
    gate_result = _gate(reasons, release)
    _emit_reasons(reasons, release)

    out_payload = {
        "schema_version": "policy-drift-outcome-v1",
        "lane": expected_lane,
        "gate_result": gate_result,
        "reasons": reasons,
        "source_artifacts": {
            "policy_outcome": policy_path.as_posix(),
            "reason_codes_index": reason_index_path.as_posix(),
            "artifact_linkage_outcome": linkage_path.as_posix(),
        },
        "policy_fields": {
            "policy_gate_result": policy_gate or "unknown",
            "reason_index_policy_gate_result": reason_policy_gate or "unknown",
            "artifact_linkage_gate_result": linkage_gate or "unknown",
            "reason_index_artifact_linkage_gate_result": reason_linkage_gate or "unknown",
            "policy_ref_mode": policy_ref_mode or "unknown",
            "artifact_linkage_ref_mode": linkage_ref_mode or "unknown",
        },
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote policy drift outcome: {out_path}")

    if release and reasons:
        raise SystemExit(1)


# ---------------------------------------------------------------------------
# 5. Validate evidence envelope cohesion
# ---------------------------------------------------------------------------

def validate_envelope_cohesion() -> None:
    release = _release_lane()
    lane = _lane_label()
    output_path = Path(_env("ENVELOPE_COHESION_OUTCOME_JSON"))
    output_path.parent.mkdir(parents=True, exist_ok=True)

    governance_artifacts = {
        "matrix": Path(_env("CORPUS_MATRIX")),
        "metadata": Path(_env("CORPUS_OUTPUT_DIR")) / "corpus-artifacts-metadata.json",
        "manifest": Path(_env("ARTIFACT_MANIFEST_JSON")),
        "policy_outcome": Path(_env("POLICY_OUTCOME_JSON")),
        "artifact_linkage_outcome": Path(_env("ARTIFACT_LINKAGE_OUTCOME_JSON")),
        "reason_codes_index": Path(_env("REASON_CODES_INDEX_JSON")),
        "policy_drift_outcome": Path(_env("POLICY_DRIFT_OUTCOME_JSON")),
    }

    envelope_mapping = {
        "matrix": "evidence/envelope-inputs/corpus-matrix-report-v1.json",
        "metadata": "evidence/envelope-inputs/integrity-metadata.json",
        "manifest": "evidence/envelope-inputs/artifact-manifest-v1.json",
        "policy_outcome": "evidence/envelope-inputs/policy-outcome-v1.json",
        "artifact_linkage_outcome": "evidence/envelope-inputs/artifact-linkage-outcome-v1.json",
        "reason_codes_index": "evidence/envelope-inputs/reason-codes-index-v1.json",
        "policy_drift_outcome": "evidence/envelope-inputs/policy-drift-outcome-v1.json",
    }

    reasons: list[dict] = []

    produced = {name: path for name, path in governance_artifacts.items() if path.is_file()}
    missing = {name: path for name, path in governance_artifacts.items() if not path.is_file()}

    for name, path in sorted(missing.items()):
        reasons.append({"code": "CMX_ENVELOPE_ARTIFACT_MISSING", "message": f"governance artifact missing for envelope cohesion: {name} -> {path.as_posix()}"})

    planned_inputs = {name: target for name, target in envelope_mapping.items() if governance_artifacts[name].is_file()}

    for name in sorted(produced):
        if name not in planned_inputs:
            reasons.append({"code": "CMX_ENVELOPE_INPUT_MISSING_FOR_ARTIFACT", "message": f"produced governance artifact is not mapped into envelope inputs: {name}"})

    for name in sorted(planned_inputs):
        if name not in produced:
            reasons.append({"code": "CMX_ENVELOPE_INPUT_WITHOUT_ARTIFACT", "message": f"envelope input mapping exists without emitted artifact: {name}"})

    reasons = _sort_reasons(reasons)
    gate_result = _gate(reasons, release)
    _emit_reasons(reasons, release)

    payload = {
        "schema_version": "envelope-cohesion-outcome-v1",
        "lane": lane,
        "gate_result": gate_result,
        "reasons": reasons,
        "governance_artifacts": {
            name: {
                "path": governance_artifacts[name].as_posix(),
                "exists": governance_artifacts[name].is_file(),
                "envelope_input_path": envelope_mapping[name],
                "included_in_envelope_when_present": name in planned_inputs,
            }
            for name in sorted(governance_artifacts)
        },
        "source_artifacts": {name: governance_artifacts[name].as_posix() for name in sorted(governance_artifacts)},
    }

    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote envelope cohesion outcome: {output_path}")

    if release and reasons:
        raise SystemExit(1)


# ---------------------------------------------------------------------------
# 6. Validate deterministic replay-proof governance digests
# ---------------------------------------------------------------------------

def validate_determinism() -> None:
    release = _release_lane()
    lane = _lane_label()

    targets = [
        ("policy_outcome", Path(_env("POLICY_OUTCOME_JSON"))),
        ("artifact_manifest", Path(_env("ARTIFACT_MANIFEST_JSON"))),
        ("artifact_linkage_outcome", Path(_env("ARTIFACT_LINKAGE_OUTCOME_JSON"))),
        ("reason_codes_index", Path(_env("REASON_CODES_INDEX_JSON"))),
        ("policy_drift_outcome", Path(_env("POLICY_DRIFT_OUTCOME_JSON"))),
        ("envelope_cohesion_outcome", Path(_env("ENVELOPE_COHESION_OUTCOME_JSON"))),
    ]
    out_path = Path(_env("DETERMINISM_OUTCOME_JSON"))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    reasons: list[dict] = []

    def canonical_sha(path: Path) -> str:
        payload = json.loads(path.read_text(encoding="utf-8"))
        canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    first_pass: dict[str, str] = {}
    second_pass: dict[str, str] = {}

    for name, path in targets:
        if not path.is_file():
            reasons.append({"code": "CMX_DETERMINISM_ARTIFACT_MISSING", "message": f"missing required governance artifact for determinism check: {name} -> {path.as_posix()}"})
            continue
        try:
            first_pass[name] = canonical_sha(path)
        except Exception as exc:
            reasons.append({"code": "CMX_DETERMINISM_ARTIFACT_INVALID", "message": f"failed canonical digest on first pass for {name} ({path.as_posix()}): {exc}"})

    for name, path in targets:
        if name not in first_pass:
            continue
        try:
            second_pass[name] = canonical_sha(path)
        except Exception as exc:
            reasons.append({"code": "CMX_DETERMINISM_ARTIFACT_INVALID", "message": f"failed canonical digest on second pass for {name} ({path.as_posix()}): {exc}"})
            continue
        if first_pass[name] != second_pass[name]:
            reasons.append({"code": "CMX_DETERMINISM_DIGEST_MISMATCH", "message": f"determinism digest mismatch within same run for {name}: pass1={first_pass[name]} pass2={second_pass[name]}"})

    reasons = _sort_reasons(reasons)
    gate_result = _gate(reasons, release)
    _emit_reasons(reasons, release)

    payload = {
        "schema_version": "determinism-outcome-v1",
        "lane": lane,
        "gate_result": gate_result,
        "reasons": reasons,
        "source_artifacts": {name: path.as_posix() for name, path in targets},
        "digest_replay": {
            "pass1": {k: first_pass[k] for k in sorted(first_pass)},
            "pass2": {k: second_pass[k] for k in sorted(second_pass)},
        },
    }

    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote determinism outcome: {out_path}")

    if release and reasons:
        raise SystemExit(1)


# ---------------------------------------------------------------------------
# CLI dispatcher
# ---------------------------------------------------------------------------

COMMANDS = {
    "self-check-policy-outcome": self_check_policy_outcome,
    "enforce-artifact-role-presence": enforce_artifact_role_presence,
    "validate-linkage-integrity": validate_linkage_integrity,
    "validate-policy-drift": validate_policy_drift,
    "validate-envelope-cohesion": validate_envelope_cohesion,
    "validate-determinism": validate_determinism,
    "all": None,  # sentinel
}


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Governance validation suite")
    parser.add_argument("command", choices=list(COMMANDS.keys()), help="Validation to run")
    args = parser.parse_args()

    if args.command == "all":
        # Run in canonical order matching original workflow step sequence
        self_check_policy_outcome()
        enforce_artifact_role_presence()
        validate_linkage_integrity()
        validate_policy_drift()
        validate_envelope_cohesion()
        validate_determinism()
    else:
        COMMANDS[args.command]()


if __name__ == "__main__":
    main()
