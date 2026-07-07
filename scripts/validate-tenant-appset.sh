#!/usr/bin/env bash
# UO-P6 slice 4: guardrail checks for the dev tenant ApplicationSet.
#
# Proves, without a cluster:
#   1. the git files generator watches EXACTLY
#      tenants/default/dev/*/values.yaml (no tenants/** breadth, no
#      staging/prod match, no non-values files, single-segment glob);
#   2. a sample tenant values path templates into a valid, DNS-safe,
#      deterministic Application targeting t-default-dev in the
#      `tenants` project;
#   3. the `tenants` AppProject stays narrow (only the t-default-dev
#      destination; cluster-scoped whitelist = Namespace only; no
#      Secret/Job/Ingress in the namespaced whitelist).
#
# Run from the repo root: ./scripts/validate-tenant-appset.sh
set -euo pipefail

cd "$(dirname "$0")/.."

python3 - <<'PY'
import re
import sys

import yaml

APPSET_PATH = "clusters/unifyops-home/apps/appset-tenant-apps-dev.yaml"
PROJECT_PATH = "clusters/unifyops-home/projects/tenants-project.yaml"

failures = []


def check(condition, message):
    if condition:
        print(f"  ok: {message}")
    else:
        failures.append(message)
        print(f"  FAIL: {message}")


with open(APPSET_PATH, encoding="utf-8") as fh:
    appset = yaml.safe_load(fh)
with open(PROJECT_PATH, encoding="utf-8") as fh:
    project = yaml.safe_load(fh)

print("[1] generator narrowness")
generators = appset["spec"]["generators"]
check(len(generators) == 1, "exactly one generator")
git_gen = generators[0].get("git", {})
check(git_gen.get("revision") == "dev", "generator revision is dev")
files = git_gen.get("files", [])
check(len(files) == 1, "exactly one files pattern")
pattern = files[0].get("path", "")
check(
    pattern == "tenants/default/dev/*/values.yaml",
    f"pattern is exactly tenants/default/dev/*/values.yaml (got {pattern!r})",
)
raw_code_lines = [
    line
    for line in open(APPSET_PATH, encoding="utf-8").read().splitlines()
    if not line.lstrip().startswith("#")
]
check(
    all("**" not in line for line in raw_code_lines),
    "no ** glob anywhere in the appset (comments excluded)",
)

print("[2] glob semantics (segment-wise, * must not cross /)")
import fnmatch


def glob_matches(pattern: str, candidate: str) -> bool:
    p_parts = pattern.split("/")
    c_parts = candidate.split("/")
    if len(p_parts) != len(c_parts):
        return False
    return all(fnmatch.fnmatchcase(c, p) for p, c in zip(p_parts, c_parts))


must_match = ["tenants/default/dev/p6s4-demo/values.yaml"]
must_not_match = [
    "tenants/default/staging/p6s4-demo/values.yaml",
    "tenants/default/prod/p6s4-demo/values.yaml",
    "tenants/other-org/dev/p6s4-demo/values.yaml",
    "tenants/default/dev/p6s4-demo/extra/values.yaml",
    "tenants/default/dev/p6s4-demo/config.json",
    "tenants/default/dev/values.yaml",
    "clusters/unifyops-home/apps/unifyops/portal/values-dev.yaml",
]
for candidate in must_match:
    check(glob_matches(pattern, candidate), f"matches {candidate}")
for candidate in must_not_match:
    check(not glob_matches(pattern, candidate), f"does NOT match {candidate}")

print("[3] template renders a valid dev-only Application")
template_raw = yaml.safe_dump(appset["spec"]["template"])
sample_dir = "tenants/default/dev/p6s4-demo"
rendered_raw = (
    template_raw.replace("{{path.basename}}", sample_dir.rsplit("/", 1)[-1])
    .replace("{{path}}", sample_dir)
)
check("{{" not in rendered_raw, "no unsubstituted template params for file generator paths")
app = yaml.safe_load(rendered_raw)
name = app["metadata"]["name"]
check(name == "t-default-dev-p6s4-demo", f"deterministic name (got {name!r})")
check(
    re.fullmatch(r"[a-z0-9]([-a-z0-9]*[a-z0-9])?", name) is not None,
    "Application name is DNS-safe",
)
dest = app["spec"]["destination"]
check(dest["namespace"] == "t-default-dev", "destination namespace is exactly t-default-dev")
check(app["spec"]["project"] == "tenants", "project is tenants")
sources = app["spec"]["sources"]
chart_sources = [s for s in sources if s.get("chart") == "unifyops-stack"]
check(len(chart_sources) == 1, "one unifyops-stack chart source")
check(
    isinstance(chart_sources[0]["targetRevision"], str),
    "chart version pinned as a string",
)
value_files = chart_sources[0]["helm"]["valueFiles"]
check(
    value_files == [f"$values/{sample_dir}/values.yaml"],
    "values file comes from the matched tenant path",
)
ref_sources = [s for s in sources if s.get("ref") == "values"]
check(
    len(ref_sources) == 1 and ref_sources[0]["targetRevision"] == "dev",
    "$values ref source pinned to the dev branch",
)
sync_options = app["spec"]["syncPolicy"].get("syncOptions", [])
check("CreateNamespace=true" in sync_options, "CreateNamespace=true present")

print("[4] tenants AppProject narrowness")
destinations = project["spec"]["destinations"]
check(
    destinations == [{"namespace": "t-default-dev", "server": "https://kubernetes.default.svc"}],
    "project destinations are exactly [t-default-dev] (no wildcard)",
)
cluster_wl = project["spec"]["clusterResourceWhitelist"]
check(
    cluster_wl == [{"group": "", "kind": "Namespace"}],
    "cluster-scoped whitelist is Namespace only",
)
ns_kinds = {entry["kind"] for entry in project["spec"]["namespaceResourceWhitelist"]}
check("*" not in ns_kinds, "no wildcard kind in the namespaced whitelist")
for forbidden in ("Secret", "Job", "Ingress"):
    check(forbidden not in ns_kinds, f"{forbidden} not deployable by tenant apps")

print()
if failures:
    print(f"{len(failures)} check(s) FAILED")
    sys.exit(1)
print("all tenant-appset guardrail checks passed")
PY
