#!/usr/bin/env python3
"""Build governance artifacts: manifest, reason index, summary, trends, metadata, signing, tamper.

Extracted from corpus-evidence-ci.yml inline steps to reduce workflow complexity.
All output file paths and artifact contracts are preserved exactly.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import importlib.util
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


# ---------------------------------------------------------------------------
# 1. Build corpus artifacts integrity metadata
# ---------------------------------------------------------------------------

def build_integrity_metadata() -> None:
    output_dir = Path(_env("CORPUS_OUTPUT_DIR"))
    output_dir.mkdir(parents=True, exist_ok=True)
    out = output_dir / "corpus-artifacts-metadata.json"

    configured_runner_version = _env("UO_EVIDENCE_CORPUS_RUNNER_VERSION") or "1.0.0"
    lineage_runner_version = _env("LINEAGE_RUNNER_VERSION")
    runner_version = lineage_runner_version or configured_runner_version

    runner_candidates = [
        Path("_deps/unifyops/shared/unifyops_core/src/unifyops_core/evidence/validator/tools/corpus_runner.py"),
        Path("_deps/unifyops/shared/unifyops_core/unifyops_core/evidence/validator/tools/corpus_runner.py"),
    ]
    spec = importlib.util.find_spec("unifyops_core.evidence.validator.tools.corpus_runner")
    if spec and spec.origin:
        module_path = Path(spec.origin)
        if module_path.suffix == ".pyc":
            module_path = Path(str(module_path).replace("/__pycache__/", "/")).with_suffix(".py")
        runner_candidates.insert(0, module_path)

    runner_checksum = ""
    for candidate in runner_candidates:
        if candidate.is_file():
            runner_checksum = hashlib.sha256(candidate.read_bytes()).hexdigest()
            break

    lineage_runner_checksum = _env("LINEAGE_RUNNER_CHECKSUM")
    if not runner_checksum:
        runner_checksum = lineage_runner_checksum

    data = {
        "corpus_matrix_path": _env("CORPUS_MATRIX"),
        "corpus_matrix_sha256": _env("CORPUS_MATRIX_SHA256"),
        "runner_version": runner_version,
        "runner_checksum": runner_checksum,
        "lockfile_path": _env("LOCKFILE_PATH"),
        "lockfile_sha256": _env("LOCKFILE_SHA256"),
        "source_manifest_path": _env("SOURCE_MANIFEST_PATH"),
        "source_manifest_sha256": _env("SOURCE_MANIFEST_SHA256"),
        "policy_outcome_path": _env("POLICY_OUTCOME_JSON"),
        "artifact_manifest_path": _env("ARTIFACT_MANIFEST_JSON"),
    }
    out.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote metadata: {out}")


# ---------------------------------------------------------------------------
# 2. Build deterministic artifact manifest index
# ---------------------------------------------------------------------------

def build_artifact_manifest() -> None:
    output_dir = Path(_env("CORPUS_OUTPUT_DIR"))
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = Path(_env("ARTIFACT_MANIFEST_JSON"))
    policy_outcome_path = Path(_env("POLICY_OUTCOME_JSON"))
    release = _release_lane()
    lane = _lane_label()
    ref_mode = _env("SUMMARY_REF_MODE", "unknown")

    policy_gate_result = "unknown"
    if policy_outcome_path.is_file():
        try:
            pp = json.loads(policy_outcome_path.read_text(encoding="utf-8"))
            if isinstance(pp, dict):
                candidate = str(pp.get("gate_result", "")).strip().lower()
                if candidate:
                    policy_gate_result = candidate
        except Exception as exc:
            print(f"::warning::unable to parse policy outcome for manifest lineage context: {exc}")

    role_sources: dict[str, list[Path]] = {
        "matrix": [Path(_env("CORPUS_MATRIX"))],
        "summary": [Path(_env("CORPUS_SUMMARY"))],
        "policy_outcome": [Path(_env("POLICY_OUTCOME_JSON"))],
        "metadata": [output_dir / "corpus-artifacts-metadata.json"],
    }

    reports_dir = Path(_env("CORPUS_REPORTS_DIR"))
    case_report_files: list[Path] = []
    if reports_dir.is_dir():
        case_report_files = [p for p in reports_dir.rglob("*") if p.is_file()]
    role_sources["case_reports"] = sorted(case_report_files, key=lambda p: p.as_posix())

    entries: list[dict] = []
    for role in ("matrix", "summary", "case_reports", "policy_outcome", "metadata"):
        paths = role_sources[role]
        if role != "case_reports":
            paths = [p for p in paths if p.is_file()]
        for path in paths:
            entries.append({
                "path": path.as_posix(),
                "role": role,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            })

    entries.sort(key=lambda item: item["path"])

    payload = {
        "schema_version": "artifact-manifest-v1",
        "lane": lane,
        "ref_mode": ref_mode,
        "gate_result": policy_gate_result,
        "lineage_context": {"lane": lane, "ref_mode": ref_mode, "gate_result": policy_gate_result},
        "entries": entries,
    }
    manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote artifact manifest: {manifest_path} entries={len(entries)}")


# ---------------------------------------------------------------------------
# 3. Build deterministic reason code index artifact
# ---------------------------------------------------------------------------

def build_reason_code_index() -> None:
    release = _release_lane()
    lane = _lane_label()

    policy_path = Path(_env("POLICY_OUTCOME_JSON"))
    linkage_path = Path(_env("ARTIFACT_LINKAGE_OUTCOME_JSON"))
    out_path = Path(_env("REASON_CODES_INDEX_JSON"))

    def load_json(path: Path) -> dict:
        if not path.is_file():
            return {}
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return {}
        return payload if isinstance(payload, dict) else {}

    policy = load_json(policy_path)
    linkage = load_json(linkage_path)

    policy_gate = str(policy.get("gate_result", "")).strip().lower()
    linkage_gate = str(linkage.get("gate_result", "")).strip().lower()

    def reason_severity(source: str) -> str:
        if release:
            return "error"
        if source == "policy_outcome":
            return "error" if policy_gate == "fail" else "warning"
        if source == "artifact_linkage_outcome":
            if linkage_gate == "fail":
                return "error"
            if linkage_gate == "warn":
                return "warning"
            return "notice"
        return "warning"

    grouped: dict[str, dict] = {}
    severity_counts = {"error": 0, "warning": 0, "notice": 0}

    def ingest(source: str, payload: dict) -> None:
        reasons = payload.get("reasons", [])
        if not isinstance(reasons, list):
            return
        for item in reasons:
            if not isinstance(item, dict):
                continue
            code = str(item.get("code", "")).strip()
            if not code:
                continue
            severity = reason_severity(source)
            severity_counts[severity] = severity_counts.get(severity, 0) + 1
            entry = grouped.setdefault(code, {"code": code, "count": 0, "severity": severity, "sources": set()})
            entry["count"] += 1
            entry["sources"].add(source)
            if entry["severity"] != "error" and severity == "error":
                entry["severity"] = "error"
            elif entry["severity"] == "notice" and severity == "warning":
                entry["severity"] = "warning"

    ingest("policy_outcome", policy)
    ingest("artifact_linkage_outcome", linkage)

    reason_codes = []
    for code in sorted(grouped):
        item = grouped[code]
        reason_codes.append({"code": item["code"], "count": int(item["count"]), "severity": item["severity"], "sources": sorted(item["sources"])})

    payload = {
        "schema_version": "reason-codes-index-v1",
        "lane": lane,
        "policy_gate_result": policy_gate or "unknown",
        "artifact_linkage_gate_result": linkage_gate or "unknown",
        "source_artifacts": {"policy_outcome": policy_path.as_posix(), "artifact_linkage_outcome": linkage_path.as_posix()},
        "reason_codes": reason_codes,
        "severity_totals": {"error": int(severity_counts.get("error", 0)), "warning": int(severity_counts.get("warning", 0)), "notice": int(severity_counts.get("notice", 0))},
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print("=== reason-code-diagnostics-v1 ===")
    print(f"lane={lane}")
    print(f"policy_gate_result={payload['policy_gate_result']}")
    print(f"artifact_linkage_gate_result={payload['artifact_linkage_gate_result']}")
    print(f"severity.error={payload['severity_totals']['error']}")
    print(f"severity.warning={payload['severity_totals']['warning']}")
    print(f"severity.notice={payload['severity_totals']['notice']}")
    print(f"reason_code.unique={len(reason_codes)}")
    print("=== /reason-code-diagnostics-v1 ===")
    print(f"wrote reason code index: {out_path} entries={len(reason_codes)}")


# ---------------------------------------------------------------------------
# 4. Build governance summary artifact
# ---------------------------------------------------------------------------

def build_governance_summary() -> None:
    release = _release_lane()
    lane = _lane_label()
    out_path = Path(_env("GOVERNANCE_SUMMARY_JSON"))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    artifact_files = {
        "corpus_matrix": Path(_env("CORPUS_MATRIX")),
        "corpus_summary": Path(_env("CORPUS_SUMMARY")),
        "corpus_artifacts_metadata": Path(_env("CORPUS_OUTPUT_DIR")) / "corpus-artifacts-metadata.json",
        "policy_outcome": Path(_env("POLICY_OUTCOME_JSON")),
        "artifact_manifest": Path(_env("ARTIFACT_MANIFEST_JSON")),
        "artifact_linkage_outcome": Path(_env("ARTIFACT_LINKAGE_OUTCOME_JSON")),
        "reason_codes_index": Path(_env("REASON_CODES_INDEX_JSON")),
        "policy_drift_outcome": Path(_env("POLICY_DRIFT_OUTCOME_JSON")),
        "envelope_cohesion_outcome": Path(_env("ENVELOPE_COHESION_OUTCOME_JSON")),
        "determinism_outcome": Path(_env("DETERMINISM_OUTCOME_JSON")),
        "governance_dashboard": Path(_env("GOVERNANCE_DASHBOARD_JSON")),
    }

    artifacts = []
    for name in sorted(artifact_files):
        path = artifact_files[name]
        entry: dict[str, Any] = {"name": name, "path": path.as_posix(), "exists": path.is_file(), "sha256": ""}
        if path.is_file():
            entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        artifacts.append(entry)

    reports_dir = Path(_env("CORPUS_REPORTS_DIR"))
    if reports_dir.is_dir():
        for rp in sorted(reports_dir.rglob("*")):
            if rp.is_file():
                artifacts.append({"name": "case_report", "path": rp.as_posix(), "exists": True, "sha256": hashlib.sha256(rp.read_bytes()).hexdigest()})

    reason_source_files = [
        ("policy_outcome", Path(_env("POLICY_OUTCOME_JSON"))),
        ("artifact_linkage_outcome", Path(_env("ARTIFACT_LINKAGE_OUTCOME_JSON"))),
        ("policy_drift_outcome", Path(_env("POLICY_DRIFT_OUTCOME_JSON"))),
        ("envelope_cohesion_outcome", Path(_env("ENVELOPE_COHESION_OUTCOME_JSON"))),
        ("determinism_outcome", Path(_env("DETERMINISM_OUTCOME_JSON"))),
    ]

    all_reasons: list[dict] = []
    for source, path in reason_source_files:
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            for reason in data.get("reasons", []):
                if isinstance(reason, dict) and reason.get("code"):
                    all_reasons.append({"code": reason["code"], "message": reason.get("message", ""), "source": source})
        except Exception:
            pass

    all_reasons.sort(key=lambda r: (r.get("code", ""), r.get("source", ""), r.get("message", "")))

    gate_results_map: dict[str, str] = {}
    gate_results_list: list[str] = []
    for source, path in reason_source_files:
        if not path.is_file():
            gate_results_map[source] = "missing"
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            gr = str(data.get("gate_result", "unknown")).strip().lower()
            gate_results_map[source] = gr
            gate_results_list.append(gr)
        except Exception:
            gate_results_map[source] = "parse_error"

    if "fail" in gate_results_list:
        verdict = "fail"
    elif "warn" in gate_results_list:
        verdict = "warn"
    elif gate_results_list:
        verdict = "pass"
    else:
        verdict = "unknown"

    payload = {
        "schema_version": "governance-summary-v1",
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "lane": lane,
        "lane_context": {
            "release_controlled": release,
            "ref": _env("GH_REF"),
            "sha": _env("GH_SHA"),
            "run_id": _env("GH_RUN_ID"),
            "run_attempt": _env("GH_RUN_ATTEMPT"),
        },
        "verdict": verdict,
        "reason_count": len(all_reasons),
        "reasons": all_reasons,
        "artifacts": artifacts,
        "artifact_count": len(artifacts),
        "gate_results": gate_results_map,
    }

    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote governance summary: {out_path} verdict={verdict} artifacts={len(artifacts)} reasons={len(all_reasons)}")


# ---------------------------------------------------------------------------
# 5. Build governance trends artifact
# ---------------------------------------------------------------------------

def build_governance_trends() -> None:
    release = _release_lane()
    lane = _lane_label()
    out_path = Path(_env("GOVERNANCE_TRENDS_JSON"))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    summary_path = Path(_env("GOVERNANCE_SUMMARY_JSON"))
    verdict = "unknown"
    reason_counts_by_severity = {"error": 0, "warning": 0, "notice": 0}
    reason_counts_by_code: dict[str, int] = {}

    if summary_path.is_file():
        try:
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            verdict = str(summary.get("verdict", "unknown")).strip().lower()
            for reason in summary.get("reasons", []):
                if not isinstance(reason, dict):
                    continue
                code = str(reason.get("code", "")).strip()
                if code:
                    reason_counts_by_code[code] = reason_counts_by_code.get(code, 0) + 1
        except Exception:
            pass

    reason_index_path = Path(_env("REASON_CODES_INDEX_JSON"))
    if reason_index_path.is_file():
        try:
            ri = json.loads(reason_index_path.read_text(encoding="utf-8"))
            totals = ri.get("severity_totals", {})
            if isinstance(totals, dict):
                for sev in ("error", "warning", "notice"):
                    reason_counts_by_severity[sev] = int(totals.get(sev, 0))
        except Exception:
            pass

    run_record = {
        "run_id": _env("GH_RUN_ID"),
        "run_attempt": _env("GH_RUN_ATTEMPT"),
        "commit_sha": _env("GH_SHA"),
        "lane": lane,
        "verdict": verdict,
        "reason_counts_by_severity": reason_counts_by_severity,
        "reason_counts_by_code": dict(sorted(reason_counts_by_code.items())),
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
    }

    payload = {
        "schema_version": "governance-trends-v1",
        "mode": "baseline",
        "note": "Historical context unavailable in runner; baseline record only.",
        "runs": [run_record],
    }

    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote governance trends: {out_path} mode=baseline")


# ---------------------------------------------------------------------------
# 6. Sign governance artifacts (HMAC-SHA256)
# ---------------------------------------------------------------------------

def sign_governance_artifacts() -> None:
    signing_key_secret = _env("SIGNING_KEY_SECRET")
    gh_sha = _env("GH_SHA")

    if signing_key_secret:
        signing_key = signing_key_secret.encode("utf-8")
        key_source = "secret:GOVERNANCE_SIGNING_KEY"
    else:
        signing_key = f"governance-baseline-{gh_sha}".encode("utf-8")
        key_source = "derived:GITHUB_SHA"
        print("::notice::[SIGNING] Using GITHUB_SHA-derived signing key (Phase-2 baseline). Set GOVERNANCE_SIGNING_KEY secret for production posture.")

    artifact_paths = [
        Path(_env("CORPUS_MATRIX")),
        Path(_env("CORPUS_SUMMARY")),
        Path(_env("CORPUS_OUTPUT_DIR")) / "corpus-artifacts-metadata.json",
        Path(_env("POLICY_OUTCOME_JSON")),
        Path(_env("ARTIFACT_MANIFEST_JSON")),
        Path(_env("ARTIFACT_LINKAGE_OUTCOME_JSON")),
        Path(_env("REASON_CODES_INDEX_JSON")),
        Path(_env("POLICY_DRIFT_OUTCOME_JSON")),
        Path(_env("ENVELOPE_COHESION_OUTCOME_JSON")),
        Path(_env("DETERMINISM_OUTCOME_JSON")),
        Path(_env("GOVERNANCE_SUMMARY_JSON")),
        Path(_env("GOVERNANCE_TRENDS_JSON")),
        Path(_env("GOVERNANCE_DASHBOARD_JSON")),
    ]

    entries = []
    for artifact_path in sorted(artifact_paths, key=lambda p: p.as_posix()):
        if not artifact_path.is_file():
            continue
        content = artifact_path.read_bytes()
        sha256_digest = hashlib.sha256(content).hexdigest()
        hmac_sig = hmac.new(signing_key, content, hashlib.sha256).hexdigest()
        entries.append({"path": artifact_path.as_posix(), "sha256": sha256_digest, "hmac_sha256": hmac_sig})

    payload = {"schema_version": "artifact-signatures-v1", "key_source": key_source, "algorithm": "HMAC-SHA256", "entries": entries}

    out_path = Path(_env("ARTIFACT_SIGNATURES_JSON"))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote artifact signatures: {out_path} entries={len(entries)} key_source={key_source}")


# ---------------------------------------------------------------------------
# 7. Validate artifact tamper evidence
# ---------------------------------------------------------------------------

def validate_tamper_evidence() -> None:
    release = _release_lane()
    sig_path = Path(_env("ARTIFACT_SIGNATURES_JSON"))

    if not sig_path.is_file():
        msg = "artifact-signatures-v1.json missing; cannot validate tamper evidence"
        if release:
            print(f"::error::[TAMPER] {msg}")
            raise SystemExit(1)
        else:
            print(f"::warning::[TAMPER] {msg}")
            return

    sig_data = json.loads(sig_path.read_text(encoding="utf-8"))

    signing_key_secret = _env("SIGNING_KEY_SECRET")
    gh_sha = _env("GH_SHA")
    if signing_key_secret:
        signing_key = signing_key_secret.encode("utf-8")
    else:
        signing_key = f"governance-baseline-{gh_sha}".encode("utf-8")

    mismatches = []
    verified = 0

    for entry in sig_data.get("entries", []):
        artifact_path = Path(entry["path"])
        if not artifact_path.is_file():
            mismatches.append(f"{artifact_path.as_posix()}: file missing")
            continue
        content = artifact_path.read_bytes()
        actual_sha256 = hashlib.sha256(content).hexdigest()
        actual_hmac = hmac.new(signing_key, content, hashlib.sha256).hexdigest()
        if actual_sha256 != entry["sha256"]:
            mismatches.append(f"{artifact_path.as_posix()}: sha256 mismatch (expected={entry['sha256']} actual={actual_sha256})")
        elif actual_hmac != entry["hmac_sha256"]:
            mismatches.append(f"{artifact_path.as_posix()}: HMAC mismatch (expected={entry['hmac_sha256']} actual={actual_hmac})")
        else:
            verified += 1

    print(f"tamper validation: verified={verified} mismatches={len(mismatches)}")

    if mismatches:
        for m in mismatches:
            if release:
                print(f"::error::[TAMPER][RELEASE] {m}")
            else:
                print(f"::warning::[TAMPER][NON-RELEASE] {m}")
        if release:
            raise SystemExit(1)
    else:
        print("::notice::[TAMPER] All governance artifacts verified — no tampering detected.")



# ---------------------------------------------------------------------------
# 8. Build governance dashboard artifact (Phase-2 Slice 3)
# ---------------------------------------------------------------------------

def build_governance_dashboard() -> None:
    """Produce governance-dashboard-v1.json with trend deltas and verdict history."""
    release = _release_lane()
    lane = _lane_label()
    out_path = Path(_env("GOVERNANCE_DASHBOARD_JSON"))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    summary_path = Path(_env("GOVERNANCE_SUMMARY_JSON"))
    trends_path = Path(_env("GOVERNANCE_TRENDS_JSON"))

    # --- load governance summary ---
    summary: dict = {}
    if summary_path.is_file():
        try:
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
        except Exception:
            pass

    verdict = str(summary.get("verdict", "unknown")).strip().lower()
    gate_results: dict = summary.get("gate_results", {})
    artifacts: list = summary.get("artifacts", [])
    reason_count: int = int(summary.get("reason_count", 0))

    # --- load governance trends ---
    trends: dict = {}
    if trends_path.is_file():
        try:
            trends = json.loads(trends_path.read_text(encoding="utf-8"))
        except Exception:
            pass

    runs: list[dict] = trends.get("runs", [])
    current_run: dict = runs[0] if runs else {}

    # --- verdict history (from available trend runs) ---
    verdict_history: list[dict] = []
    for run in runs:
        verdict_history.append({
            "run_id": str(run.get("run_id", "")),
            "run_attempt": str(run.get("run_attempt", "")),
            "commit_sha": str(run.get("commit_sha", "")),
            "verdict": str(run.get("verdict", "unknown")),
            "timestamp": str(run.get("timestamp", "")),
        })
    verdict_history.sort(key=lambda v: (v.get("timestamp", ""), v.get("run_id", "")))

    # --- trend deltas (current vs previous if available) ---
    current_severity = current_run.get("reason_counts_by_severity", {}) if current_run else {}
    # With baseline mode there's no previous run; deltas are identity
    previous_severity: dict = {}
    if len(runs) > 1:
        previous_severity = runs[1].get("reason_counts_by_severity", {})

    def _delta(key: str) -> dict:
        cur = int(current_severity.get(key, 0))
        prev = int(previous_severity.get(key, 0)) if previous_severity else cur
        return {"current": cur, "previous": prev, "delta": cur - prev}

    trend_deltas = {
        "error": _delta("error"),
        "warning": _delta("warning"),
        "notice": _delta("notice"),
    }

    # --- artifact inventory summary ---
    artifact_count = len(artifacts)
    artifacts_present = sum(1 for a in artifacts if a.get("exists"))
    artifacts_missing = artifact_count - artifacts_present

    # --- gate results breakdown ---
    gate_breakdown: dict[str, str] = {}
    for source in sorted(gate_results):
        gate_breakdown[source] = str(gate_results[source])

    # --- assemble dashboard ---
    payload = {
        "schema_version": "governance-dashboard-v1",
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "lane": lane,
        "lane_context": {
            "release_controlled": release,
            "ref": _env("GH_REF"),
            "sha": _env("GH_SHA"),
            "run_id": _env("GH_RUN_ID"),
            "run_attempt": _env("GH_RUN_ATTEMPT"),
        },
        "verdict": verdict,
        "reason_count": reason_count,
        "trend_deltas": trend_deltas,
        "verdict_history": verdict_history,
        "gate_results": gate_breakdown,
        "artifact_inventory": {
            "total": artifact_count,
            "present": artifacts_present,
            "missing": artifacts_missing,
        },
    }

    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote governance dashboard: {out_path} verdict={verdict}")



# ---------------------------------------------------------------------------
# CLI dispatcher
# ---------------------------------------------------------------------------

COMMANDS = {
    "build-integrity-metadata": build_integrity_metadata,
    "build-artifact-manifest": build_artifact_manifest,
    "build-reason-code-index": build_reason_code_index,
    "build-governance-summary": build_governance_summary,
    "build-governance-trends": build_governance_trends,
    "sign-governance-artifacts": sign_governance_artifacts,
    "validate-tamper-evidence": validate_tamper_evidence,
    "build-governance-dashboard": build_governance_dashboard,
    "all-build": None,   # build all artifacts in order
    "all-sign": None,    # sign + tamper validate
}


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Governance artifact builder suite")
    parser.add_argument("command", choices=list(COMMANDS.keys()), help="Builder to run")
    args = parser.parse_args()

    if args.command == "all-build":
        build_integrity_metadata()
        build_artifact_manifest()
        build_reason_code_index()
        build_governance_summary()
        build_governance_trends()
        build_governance_dashboard()
    elif args.command == "all-sign":
        sign_governance_artifacts()
        validate_tamper_evidence()
    else:
        COMMANDS[args.command]()


if __name__ == "__main__":
    main()
