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


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _parse_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Validate evidence corpus matrix and policy gates")
    p.add_argument("--matrix", required=True, help="Path to corpus matrix JSON")
    p.add_argument("--release-controlled", default="false", help="Whether current lane is release-controlled")
    p.add_argument("--non-blocking", default="false", help="Enable temporary non-blocking mode")
    p.add_argument("--non-blocking-owner", default="", help="Required owner when non-blocking=true")
    p.add_argument("--non-blocking-expiry", default="", help="Required ISO date YYYY-MM-DD when non-blocking=true")
    p.add_argument("--expected-case-count", type=int, default=None, help="Expected total executed case count")
    p.add_argument("--manifest-path", default="", help="Manifest file path for checksum completeness assertion")
    p.add_argument("--expected-manifest-sha256", default="", help="Expected SHA256 for manifest-path")
    return p.parse_args()


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    args = _parse_args()
    matrix_path = Path(args.matrix)
    if not matrix_path.exists():
        print(f"ERROR: matrix file not found: {matrix_path}")
        return 1

    data = _load_json(matrix_path)
    totals = data.get("totals") or {}
    lineage = data.get("lineage") or {}

    fail_count = int(totals.get("fail", 0))
    skipped_count = int(totals.get("skipped", 0))

    # Useful CI outputs for downstream steps.
    print(f"corpus.fail_count={fail_count}")
    print(f"corpus.skipped_count={skipped_count}")

    missing_lineage = [k for k in REQUIRED_LINEAGE_FIELDS if not str(lineage.get(k, "")).strip()]

    errors: list[str] = []
    warnings: list[str] = []

    if missing_lineage:
        errors.append(f"missing lineage fields: {', '.join(missing_lineage)}")

    release_controlled = _parse_bool(args.release_controlled)
    non_blocking = _parse_bool(args.non_blocking)

    lane_label = "RELEASE" if release_controlled else "NON-RELEASE"
    print(f"policy.lane={lane_label}")
    print(f"policy.non_blocking_requested={str(non_blocking).lower()}")

    if release_controlled and non_blocking:
        errors.append("non-blocking mode is prohibited in release-controlled lanes")

    if non_blocking:
        if not args.non_blocking_owner.strip() or not args.non_blocking_expiry.strip():
            errors.append("non-blocking mode requires explicit owner and expiry")
        else:
            try:
                expiry = dt.date.fromisoformat(args.non_blocking_expiry.strip())
                today = dt.datetime.now(dt.timezone.utc).date()
                if expiry < today:
                    errors.append(
                        f"non-blocking expiry has passed ({args.non_blocking_expiry}); blocking is required"
                    )
                else:
                    warnings.append(
                        "NON-BLOCKING EVIDENCE CORPUS MODE ACTIVE "
                        f"owner={args.non_blocking_owner.strip()} expiry={args.non_blocking_expiry.strip()}"
                    )
            except ValueError:
                errors.append("non-blocking expiry must be ISO date YYYY-MM-DD")

    # Completeness assertion: require expected case count and/or manifest checksum assertion.
    completeness_provided = False
    if args.expected_case_count is not None:
        completeness_provided = True
        observed_total = totals.get("total")
        if observed_total is None:
            observed_total = totals.get("pass", 0) + totals.get("fail", 0) + totals.get("skipped", 0)
        observed_total = int(observed_total)
        if observed_total != int(args.expected_case_count):
            errors.append(
                f"case-count completeness failed: expected={args.expected_case_count} observed={observed_total}"
            )

    if args.manifest_path or args.expected_manifest_sha256:
        completeness_provided = True
        if not args.manifest_path or not args.expected_manifest_sha256:
            errors.append("manifest completeness requires both --manifest-path and --expected-manifest-sha256")
        else:
            mp = Path(args.manifest_path)
            if not mp.exists():
                errors.append(f"manifest file not found: {mp}")
            else:
                actual = _sha256_file(mp)
                expected = args.expected_manifest_sha256.strip().lower()
                if actual.lower() != expected:
                    errors.append(
                        "manifest checksum completeness failed: "
                        f"expected={expected} actual={actual.lower()}"
                    )

    if not completeness_provided:
        msg = (
            "completeness assertion missing: provide --expected-case-count and/or "
            "--manifest-path with --expected-manifest-sha256"
        )
        if release_controlled:
            errors.append(msg)
        else:
            warnings.append(msg)

    # Blocking fail conditions.
    if fail_count > 0:
        errors.append(f"totals.fail must be 0 in blocking policy; found {fail_count}")

    if skipped_count != 0:
        errors.append(f"totals.skipped must be 0 in blocking policy; found {skipped_count}")

    if warnings:
        for w in warnings:
            print(f"::warning::{w}")
            print(f"WARNING: {w}")

    if errors:
        print(f"Corpus gate evaluation: FAIL ({lane_label})")
        for e in errors:
            print(f"ERROR: {e}")

        # Non-blocking can only soften policy outcome for fail/skipped/completeness issues,
        # never for invalid lane policy or lineage integrity.
        hard_policy_errors = [
            e
            for e in errors
            if "prohibited in release-controlled" in e
            or "requires explicit owner and expiry" in e
            or e.startswith("missing lineage fields")
            or "expiry" in e
        ]

        if non_blocking and not release_controlled and not hard_policy_errors:
            print("NON-BLOCKING MODE: allowing pipeline continuation despite corpus gate failures")
            return 0
        return 1

    print(f"Corpus gate evaluation: PASS ({lane_label})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
