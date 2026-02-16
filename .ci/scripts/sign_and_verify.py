#!/usr/bin/env python3
"""sign_and_verify.py — Sign governance artifacts and validate tamper evidence.

Consolidates the two inline workflow steps (sign + verify) into a single invocation.
Delegates to build_governance_artifacts.py subcommands internally.

Required env vars: GH_SHA, SIGNING_KEY_SECRET (+ all governance artifact env vars)
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
GOV_SCRIPT = SCRIPT_DIR / "build_governance_artifacts.py"


def main() -> None:
    # Step 1: Sign
    print("=== Signing governance artifacts ===")
    rc = subprocess.call([sys.executable, str(GOV_SCRIPT), "sign-governance-artifacts"])
    if rc != 0:
        print(f"::error::Signing step failed with exit code {rc}")
        sys.exit(rc)

    # Step 2: Verify tamper evidence
    print("=== Validating artifact tamper evidence ===")
    rc = subprocess.call([sys.executable, str(GOV_SCRIPT), "validate-tamper-evidence"])
    if rc != 0:
        print(f"::error::Tamper validation failed with exit code {rc}")
        sys.exit(rc)

    print("Sign and verify completed successfully.")


if __name__ == "__main__":
    main()
