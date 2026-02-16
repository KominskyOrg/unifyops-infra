#!/usr/bin/env python3
"""Validate corpus matrix contract and gating policy for CI lanes."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

REQUIRED_LINEAGE_FIELDS = (
    "source_commit_sha",
    "release_artifact_id",
    "release_artifact_checksum",
    "runner_version",
    "runner_checksum",
)

TRUE_TOKENS = {"1", "true", "yes", "on"}
FALSE_TOKENS = {"0", "false", "no", "off", ""}


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _normalize_bool(raw: str, *, field: str, default: bool = False) -> tuple[bool, list[str]]:
    token = str(raw).strip().lower()
    notes: list[str] = []
    if token in TRUE_TOKENS:
        value = True
    elif token in FALSE_TOKENS:
        value = False
        if token == "":
            notes.append(f"{field}: empty value normalized to false")
    else:
        value = default
        notes.append(f"{field}: malformed boolean '{raw}' normalized to {'true' if default else 'false'}")
    print(f"policy.normalized.{field}={str(value).lower()} raw='{raw}'")
    return value, notes


def _normalize_lane(raw_lane: str, release_controlled: bool) -> tuple[str, list[str]]:
    token = str(raw_lane).strip().lower()
    notes: list[str] = []
    if token in {"release", "release-controlled", "release_controlled", "release-controlled-lane"}:
        lane = "RELEASE"
    elif token in {"non-release", "non_release", "dev", "pr", "pull_request", ""}:
        lane = "RELEASE" if release_controlled else "NON-RELEASE"
        if token == "":
            notes.append("lane: empty value normalized from release-controlled flag")
    elif token in TRUE_TOKENS | FALSE_TOKENS:
        lane = "RELEASE" if token in TRUE_TOKENS else "NON-RELEASE"
        notes.append(f"lane: boolean-like value '{raw_lane}' normalized to {lane}")
    else:
        lane = "RELEASE" if release_controlled else "NON-RELEASE"
        notes.append(f"lane: malformed value '{raw_lane}' normalized from release-controlled flag")
    print(f"policy.normalized.lane={lane} raw='{raw_lane}'")
    return lane, notes


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Validate evidence corpus matrix and policy gates")
    p.add_argument("--matrix", required=True, help="Path to corpus matrix JSON")
    p.add_argument("--lane", default="", help="Lane hint: release/non-release (optional)")
    p.add_argument("--release-controlled", default="false", help="Whether current lane is release-controlled")
    p.add_argument("--non-blocking", default="false", help="Enable temporary non-blocking mode")
    p.add_argument("--non-blocking-owner", default="", help="Required owner when non-blocking=true")
    p.add_argument("--non-blocking-expiry", default="", help="Required ISO date YYYY-MM-DD when non-blocking=true")
    p.add_argument("--expected-case-count", type=int, default=None, help="Expected total executed case count")
    p.add_argument("--manifest-path", default="", help="Manifest file path for checksum completeness assertion")
    p.add_argument("--expected-manifest-sha256", default="", help="Expected SHA256 for manifest-path")
    p.add_argument("--ref-mode", default="", help="Source ref mode: immutable/mutable")
    p.add_argument("--lockfile-present", default="", help="Whether lockfile evidence is present")
    p.add_argument("--policy-outcome-json", default="", help="Optional path to write normalized policy outcome JSON")
    return p.parse_args()


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _write_outcome(path: str, payload: dict[str, Any]) -> None:
    if not path:
        return
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"policy.outcome_json={out}")

def _sorted_reasons(reasons: list[dict[str, str]]) -> list[dict[str, str]]:
    return sorted(reasons, key=lambda x: (x.get("code", ""), x.get("message", "")))


def main() -> int:
    args = _parse_args()
    matrix_path = Path(args.matrix)
    if not matrix_path.exists():
        print(f"ERROR[CMX_MATRIX_NOT_FOUND]: matrix file not found: {matrix_path}")
        _write_outcome(
            args.policy_outcome_json,
            {
                "lane": "UNKNOWN",
                "ref_mode": (args.ref_mode or "unknown").lower(),
                "lockfile_present": False,
                "completeness_mode": "none",
                "gate_result": "fail",
                "reasons": [{"code": "CMX_MATRIX_NOT_FOUND", "message": f"matrix file not found: {matrix_path}"}],
            },
        )
        return 1

    data = _load_json(matrix_path)
    totals = data.get("totals") or {}
    lineage = data.get("lineage") or {}

    fail_count = int(totals.get("fail", 0))
    skipped_count = int(totals.get("skipped", 0))

    print(f"corpus.fail_count={fail_count}")
    print(f"corpus.skipped_count={skipped_count}")

    missing_lineage = [k for k in REQUIRED_LINEAGE_FIELDS if not str(lineage.get(k, "")).strip()]

    errors: list[dict[str, str]] = []
    warnings: list[str] = []

    if missing_lineage:
        errors.append({"code": "CMX_LINEAGE_FIELDS_MISSING", "message": f"missing lineage fields: {', '.join(missing_lineage)}"})

    release_controlled, release_notes = _normalize_bool(args.release_controlled, field="release_controlled")
    non_blocking, non_blocking_notes = _normalize_bool(args.non_blocking, field="non_blocking")
    lane_label, lane_notes = _normalize_lane(args.lane, release_controlled)

    warnings.extend(release_notes)
    warnings.extend(non_blocking_notes)
    warnings.extend(lane_notes)

    lockfile_present, lockfile_notes = _normalize_bool(args.lockfile_present, field="lockfile_present")
    warnings.extend(lockfile_notes)

    print(f"policy.lane={lane_label}")
    print(f"policy.non_blocking_requested={str(non_blocking).lower()}")

    if release_controlled and non_blocking:
        errors.append({"code": "CMX_NONBLOCKING_RELEASE_PROHIBITED", "message": "non-blocking mode is prohibited in release-controlled lanes"})

    if non_blocking:
        if not args.non_blocking_owner.strip() or not args.non_blocking_expiry.strip():
            errors.append({"code": "CMX_NONBLOCKING_METADATA_REQUIRED", "message": "non-blocking mode requires explicit owner and expiry"})
        else:
            try:
                expiry = dt.date.fromisoformat(args.non_blocking_expiry.strip())
                today = dt.datetime.now(dt.timezone.utc).date()
                if expiry < today:
                    errors.append({
                        "code": "CMX_NONBLOCKING_EXPIRED",
                        "message": f"non-blocking expiry has passed ({args.non_blocking_expiry}); blocking is required",
                    })
                else:
                    warnings.append(
                        "NON-BLOCKING EVIDENCE CORPUS MODE ACTIVE "
                        f"owner={args.non_blocking_owner.strip()} expiry={args.non_blocking_expiry.strip()}"
                    )
            except ValueError:
                errors.append({"code": "CMX_NONBLOCKING_EXPIRY_INVALID", "message": "non-blocking expiry must be ISO date YYYY-MM-DD"})

    completeness_mode = "none"
    completeness_provided = False
    if args.expected_case_count is not None:
        completeness_provided = True
        completeness_mode = "case-count"
        observed_total = totals.get("total")
        if observed_total is None:
            observed_total = totals.get("pass", 0) + totals.get("fail", 0) + totals.get("skipped", 0)
        observed_total = int(observed_total)
        if observed_total != int(args.expected_case_count):
            errors.append({
                "code": "CMX_CASE_COUNT_MISMATCH",
                "message": f"case-count completeness failed: expected={args.expected_case_count} observed={observed_total}",
            })

    if args.manifest_path or args.expected_manifest_sha256:
        completeness_provided = True
        completeness_mode = "manifest" if completeness_mode == "none" else "case-count+manifest"
        if not args.manifest_path or not args.expected_manifest_sha256:
            errors.append({
                "code": "CMX_MANIFEST_ARGS_INCOMPLETE",
                "message": "manifest completeness requires both --manifest-path and --expected-manifest-sha256",
            })
        else:
            mp = Path(args.manifest_path)
            if not mp.exists():
                errors.append({"code": "CMX_MANIFEST_NOT_FOUND", "message": f"manifest file not found: {mp}"})
            else:
                actual = _sha256_file(mp)
                expected = args.expected_manifest_sha256.strip().lower()
                if actual.lower() != expected:
                    errors.append({
                        "code": "CMX_MANIFEST_SHA_MISMATCH",
                        "message": f"manifest checksum completeness failed: expected={expected} actual={actual.lower()}",
                    })

    if not completeness_provided:
        msg = (
            "completeness assertion missing: provide --expected-case-count and/or "
            "--manifest-path with --expected-manifest-sha256"
        )
        if release_controlled:
            errors.append({"code": "CMX_COMPLETENESS_ASSERTION_MISSING", "message": msg})
        else:
            warnings.append(msg)

    if fail_count > 0:
        errors.append({"code": "CMX_TOTALS_FAIL_NONZERO", "message": f"totals.fail must be 0 in blocking policy; found {fail_count}"})

    if skipped_count != 0:
        errors.append({"code": "CMX_TOTALS_SKIPPED_NONZERO", "message": f"totals.skipped must be 0 in blocking policy; found {skipped_count}"})

    if warnings:
        for w in warnings:
            print(f"::warning::{w}")
            print(f"WARNING: {w}")

    errors = _sorted_reasons(errors)
    gate_result = "fail" if errors else "pass"
    _write_outcome(
        args.policy_outcome_json,
        {
            "lane": lane_label,
            "ref_mode": (args.ref_mode or "unknown").strip().lower() or "unknown",
            "lockfile_present": lockfile_present,
            "completeness_mode": completeness_mode,
            "gate_result": gate_result,
            "reasons": errors,
        },
    )

    if errors:
        print(f"Corpus gate evaluation: FAIL ({lane_label})")
        for e in errors:
            print(f"ERROR[{e['code']}]: {e['message']}")

        hard_policy_error_codes = {
            "CMX_NONBLOCKING_RELEASE_PROHIBITED",
            "CMX_NONBLOCKING_METADATA_REQUIRED",
            "CMX_LINEAGE_FIELDS_MISSING",
            "CMX_NONBLOCKING_EXPIRED",
            "CMX_NONBLOCKING_EXPIRY_INVALID",
        }
        hard_policy_errors = [e for e in errors if e["code"] in hard_policy_error_codes]

        if non_blocking and not release_controlled and not hard_policy_errors:
            print("NON-BLOCKING MODE: allowing pipeline continuation despite corpus gate failures")
            return 0
        return 1

    print(f"Corpus gate evaluation: PASS ({lane_label})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
