#!/usr/bin/env python3
"""emit_lineage.py — Consolidated lineage/digest emission for corpus-evidence-ci.

Replaces 7 inline workflow steps:
  1. Emit corpus matrix SHA-256
  2. Hydrate corpus matrix lineage defaults
  3. Extract required lineage outputs
  4. Emit runner lineage audit fields
  5. Emit lockfile SHA-256 (if present)
  6. Resolve expected corpus case count
  7. Emit deterministic preflight summary

All GITHUB_OUTPUT keys are preserved exactly.

Required env vars:
  CORPUS_MATRIX, CORPUS_ROOT, GH_SHA, GH_RUN_ID, GH_RUN_ATTEMPT,
  UO_EVIDENCE_CORPUS_RUNNER_VERSION, RELEASE_CONTROLLED_LANE,
  EXPECTED_CORPUS_CASE_COUNT, GITHUB_OUTPUT
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path


def _env(key: str, default: str = "") -> str:
    return os.environ.get(key, default).strip()


def _output(key: str, value: str) -> None:
    """Append key=value to $GITHUB_OUTPUT and print."""
    print(f"{key}={value}")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
        f.write(f"{key}={value}\n")


def _annotation(level: str, msg: str) -> None:
    print(f"::{level}::{msg}")


# ---------------------------------------------------------------------------
# 1. Corpus matrix SHA-256
# ---------------------------------------------------------------------------
def emit_matrix_digest(matrix_path: Path) -> str:
    if not matrix_path.is_file() or matrix_path.stat().st_size == 0:
        return ""
    digest = hashlib.sha256(matrix_path.read_bytes()).hexdigest()
    _output("corpus_matrix_sha256", digest)
    return digest


# ---------------------------------------------------------------------------
# 2+3. Hydrate lineage defaults + extract required lineage outputs
# ---------------------------------------------------------------------------
def hydrate_and_extract_lineage(matrix_path: Path) -> dict[str, str]:
    if not matrix_path.is_file():
        return {}

    data = json.loads(matrix_path.read_text(encoding="utf-8"))
    lineage = data.get("lineage")
    if not isinstance(lineage, dict):
        lineage = {}
        data["lineage"] = lineage

    gh_sha = _env("GH_SHA")

    # Resolve source commit SHA (prefer _deps/unifyops HEAD)
    source_commit_sha = gh_sha
    try:
        dep_sha = subprocess.check_output(
            ["git", "-C", "_deps/unifyops", "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if dep_sha:
            source_commit_sha = dep_sha
    except Exception:
        pass

    run_id = _env("GH_RUN_ID")
    run_attempt = _env("GH_RUN_ATTEMPT")
    release_artifact_id = f"{run_id}-{run_attempt}".strip("-")
    release_artifact_checksum = hashlib.sha256(gh_sha.encode()).hexdigest() if gh_sha else ""
    runner_version = _env("UO_EVIDENCE_CORPUS_RUNNER_VERSION") or "1.0.0"

    # Find runner module for checksum
    runner_candidates = [
        Path("_deps/unifyops/shared/unifyops_core/src/unifyops_core/evidence/validator/tools/corpus_runner.py"),
        Path("_deps/unifyops/shared/unifyops_core/unifyops_core/evidence/validator/tools/corpus_runner.py"),
        Path("shared/unifyops_core/src/unifyops_core/evidence/validator/tools/corpus_runner.py"),
        Path("shared/unifyops_core/unifyops_core/evidence/validator/tools/corpus_runner.py"),
    ]
    spec = importlib.util.find_spec("unifyops_core.evidence.validator.tools.corpus_runner")
    if spec and spec.origin:
        mp = Path(spec.origin)
        if mp.suffix == ".pyc":
            mp = Path(str(mp).replace("/__pycache__/", "/")).with_suffix(".py")
        runner_candidates.insert(0, mp)

    runner_checksum = ""
    for candidate in runner_candidates:
        if candidate.is_file():
            runner_checksum = hashlib.sha256(candidate.read_bytes()).hexdigest()
            break

    # Set defaults (missing-only)
    defaults = {
        "source_commit_sha": source_commit_sha,
        "release_artifact_id": release_artifact_id,
        "release_artifact_checksum": release_artifact_checksum,
        "runner_version": runner_version,
        "runner_checksum": runner_checksum,
    }
    for key, value in defaults.items():
        existing = lineage.get(key)
        if not (isinstance(existing, str) and existing.strip()):
            lineage[key] = value

    matrix_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("hydrated lineage defaults (missing-only)")

    # Extract and emit outputs
    result = {}
    for key in ("source_commit_sha", "release_artifact_id", "release_artifact_checksum", "runner_version", "runner_checksum"):
        val = str(lineage.get(key, "")).strip()
        _output(key, val)
        result[key] = val

    return result


# ---------------------------------------------------------------------------
# 4. Emit runner lineage audit fields (just logging, no new outputs)
# ---------------------------------------------------------------------------
def emit_runner_audit(lineage_outputs: dict[str, str], matrix_digest: str) -> None:
    rv = lineage_outputs.get("runner_version") or _env("UO_EVIDENCE_CORPUS_RUNNER_VERSION") or "1.0.0"
    print(f"runner_version={rv}")
    print(f"runner_checksum={lineage_outputs.get('runner_checksum', '')}")
    print(f"corpus_matrix_sha256={matrix_digest}")


# ---------------------------------------------------------------------------
# 5. Emit lockfile SHA-256 (if present)
# ---------------------------------------------------------------------------
def emit_lockfile_digest() -> dict[str, str]:
    import glob

    result: dict[str, str] = {}
    lockfile_patterns = ["poetry.lock", "requirements*.txt", "_deps/unifyops/poetry.lock", "_deps/unifyops/requirements*.txt"]
    all_candidates: list[str] = []
    for pat in lockfile_patterns:
        all_candidates.extend(sorted(glob.glob(pat)))
    lockfiles = sorted(set(all_candidates))
    searched = ", ".join(lockfiles) if lockfiles else ", ".join(lockfile_patterns)
    _output("searched_lockfile_paths", searched)

    valid = [lf for lf in lockfiles if os.path.isfile(lf)]

    # Source manifest
    manifest_path = "_deps/unifyops/shared/unifyops_core/pyproject.toml"
    manifest_sha = ""
    if os.path.isfile(manifest_path):
        manifest_sha = hashlib.sha256(Path(manifest_path).read_bytes()).hexdigest()
        _output("source_manifest_path", manifest_path)
        _output("source_manifest_sha256", manifest_sha)
    else:
        _output("source_manifest_path", "")
        _output("source_manifest_sha256", "")

    if not valid:
        _annotation("warning", f"No lockfile evidence present; searched paths: {searched}.")
        if manifest_sha:
            print(f"Supplemental source dependency manifest detected: {manifest_path} (sha256={manifest_sha})")
        _output("lockfile_present", "false")
        _output("lockfile_path", "")
        _output("lockfile_sha256", "")
        result["lockfile_present"] = "false"
        return result

    primary = valid[0]
    primary_sha = hashlib.sha256(Path(primary).read_bytes()).hexdigest()
    _output("lockfile_present", "true")
    _output("lockfile_path", primary)
    _output("lockfile_sha256", primary_sha)
    result["lockfile_present"] = "true"

    for lf in valid:
        sha = hashlib.sha256(Path(lf).read_bytes()).hexdigest()
        print(f"lockfile_sha256[{lf}]={sha}")

    return result


# ---------------------------------------------------------------------------
# 6. Resolve expected corpus case count
# ---------------------------------------------------------------------------
def resolve_expected_case_count() -> dict[str, str]:
    expected = _env("EXPECTED_CORPUS_CASE_COUNT")
    corpus_root = _env("CORPUS_ROOT")

    if expected:
        source_label = "configured:EXPECTED_CORPUS_CASE_COUNT"
        print(f"Using configured EXPECTED_CORPUS_CASE_COUNT={expected}")
    elif not os.path.isdir(corpus_root):
        expected = "0"
        source_label = "fallback:missing_corpus_root"
        _annotation("warning", f"Corpus root not found at {corpus_root}; expected case count defaults to 0 for deterministic reporting.")
    else:
        count = 0
        for root, _dirs, files in os.walk(corpus_root):
            count += sum(1 for f in files if f == "expected-result.json")
        expected = str(count)
        source_label = f"auto-derived:{corpus_root}"
        print(f"Auto-derived expected corpus case count={expected} from {corpus_root}")

    _output("expected_count", expected)
    _output("expected_count_source", source_label)
    return {"expected_count_source": source_label}


# ---------------------------------------------------------------------------
# 7. Emit deterministic preflight summary
# ---------------------------------------------------------------------------
def emit_preflight_summary(lockfile_present: str = "", expected_count_source: str = "") -> None:
    print("=== corpus-preflight-summary-v1 ===")
    print(f"lane={_env('SUMMARY_LANE')}")
    print(f"source_repo={_env('SUMMARY_SOURCE_REPO')}")
    print(f"source_ref={_env('SUMMARY_SOURCE_REF') or 'unset'}")
    print(f"resolved_ref_mode={_env('SUMMARY_REF_MODE') or 'unset'}")
    print(f"preflight_status={_env('SUMMARY_PREFLIGHT_OK') or 'false'}")
    print(f"lockfile_present={lockfile_present or _env('SUMMARY_LOCKFILE_PRESENT') or 'false'}")
    print(f"expected_case_count_source={expected_count_source or _env('SUMMARY_EXPECTED_CASE_COUNT_SOURCE') or 'unset'}")
    print("=== /corpus-preflight-summary-v1 ===")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    matrix_path = Path(_env("CORPUS_MATRIX"))

    # Phase 1: matrix digest + lineage (requires matrix file)
    matrix_digest = emit_matrix_digest(matrix_path)
    lineage_outputs = hydrate_and_extract_lineage(matrix_path)
    emit_runner_audit(lineage_outputs, matrix_digest)

    # Phase 2: lockfile + case count (always run)
    lockfile_result = emit_lockfile_digest()
    case_count_result = resolve_expected_case_count()

    # Phase 3: preflight summary (always run — uses env vars set by caller + computed values)
    emit_preflight_summary(
        lockfile_present=lockfile_result.get("lockfile_present", ""),
        expected_count_source=case_count_result.get("expected_count_source", ""),
    )


if __name__ == "__main__":
    main()
