#!/usr/bin/env bash
# source_preflight.sh — Preflight source repo access/ref for corpus runner checkout.
# Extracted from corpus-evidence-ci.yml inline step to reduce workflow complexity.
#
# Required env vars:
#   UO_EVIDENCE_CORPUS_SOURCE_REPO, UO_EVIDENCE_CORPUS_DEFAULT_REF,
#   UO_EVIDENCE_SOURCE_TOKEN, RELEASE_CONTROLLED_LANE,
#   CURRENT_REPO, CURRENT_SHA, INPUT_SOURCE_REF, VAR_SOURCE_REF, VAR_DEFAULT_REF
#
# Outputs (via GITHUB_OUTPUT):
#   preflight_ok, error_type, error_message, effective_ref, ref_mode,
#   cross_repo, ref_origin, token_present, repo_endpoint_status, ref_check_status

set -euo pipefail

repo="${UO_EVIDENCE_CORPUS_SOURCE_REPO}"
input_source_ref="${INPUT_SOURCE_REF:-}"
var_source_ref="${VAR_SOURCE_REF:-}"
var_default_ref="${VAR_DEFAULT_REF:-}"
default_ref="${UO_EVIDENCE_CORPUS_DEFAULT_REF:-e65ef29bc36ad65b641a903a6b23f488a95c3f3f}"
token="${UO_EVIDENCE_SOURCE_TOKEN:-}"
current_repo="${CURRENT_REPO}"
release_lane="${RELEASE_CONTROLLED_LANE,,}"

preflight_ok="false"
error_type=""
error_message=""
effective_ref=""
ref_mode="mutable"
cross_repo="false"
ref_origin=""

if [[ "${repo}" != "${current_repo}" ]]; then
  cross_repo="true"
fi

# --- Resolve effective ref ---
if [[ -n "${input_source_ref}" ]]; then
  effective_ref="${input_source_ref}"
  ref_origin="input:UO_EVIDENCE_CORPUS_SOURCE_REF"
elif [[ -n "${var_source_ref}" ]]; then
  effective_ref="${var_source_ref}"
  ref_origin="repo_var:UO_EVIDENCE_CORPUS_SOURCE_REF"
elif [[ "${cross_repo}" == "true" ]]; then
  effective_ref="${default_ref}"
  if [[ -n "${var_default_ref}" ]]; then
    ref_origin="repo_var:UO_EVIDENCE_CORPUS_DEFAULT_REF"
  else
    ref_origin="default_literal:e65ef29bc36ad65b641a903a6b23f488a95c3f3f"
  fi
else
  effective_ref="${CURRENT_SHA}"
  ref_origin="same_repo_default:github.sha"
fi

if [[ -z "${effective_ref}" ]]; then
  error_type="missing_ref"
  if [[ "${cross_repo}" == "true" ]]; then
    error_message="Unable to resolve cross-repo source ref. Set UO_EVIDENCE_CORPUS_SOURCE_REF input/repo var or define UO_EVIDENCE_CORPUS_DEFAULT_REF (stable branch/tag)."
  else
    error_message="Unable to resolve same-repo source ref from github.sha."
  fi
fi

# --- Classify ref mode ---
if [[ -z "${error_type}" ]]; then
  if [[ "${effective_ref}" =~ ^refs/tags/.+ ]] || [[ "${effective_ref}" =~ ^[A-Fa-f0-9]{7,40}$ ]] || [[ "${effective_ref}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$ ]]; then
    ref_mode="immutable"
  fi

  if [[ "${release_lane}" == "true" && "${ref_mode}" != "immutable" ]]; then
    error_type="mutable_ref_disallowed"
    error_message="Release-controlled lane requires immutable source ref (tag or commit SHA), got '${effective_ref}'."
  elif [[ "${release_lane}" != "true" && "${ref_mode}" != "immutable" ]]; then
    echo "::warning::Selected source ref '${effective_ref}' is mutable in a non-release lane. Prefer a tag or commit SHA for immutable provenance."
  fi
fi

# --- Cross-repo token check ---
if [[ -z "${error_type}" && "${cross_repo}" == "true" && -z "${token}" ]]; then
  error_type="missing_cross_repo_token"
  error_message="Cross-repo source checkout requires secrets.UO_EVIDENCE_SOURCE_TOKEN with read access to '${repo}'."
fi

# --- API validation ---
token_present="false"
repo_endpoint_status="not_checked"
ref_check_status="not_checked"
if [[ -n "${token}" ]]; then
  token_present="true"
fi

if [[ -z "${error_type}" ]]; then
  auth_args=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  if [[ -n "${token}" ]]; then
    auth_args+=(-H "Authorization: Bearer ${token}")
  fi

  api_base="https://api.github.com/repos/${repo}"
  repo_resp_file="$(mktemp)"
  set +e
  repo_endpoint_status="$(curl -sS -L -o "${repo_resp_file}" -w '%{http_code}' "${auth_args[@]}" "${api_base}")"
  curl_rc=$?
  set -e

  if [[ ${curl_rc} -ne 0 ]]; then
    error_type="checkout_preflight_failed"
    error_message="Unable to validate source repo '${repo}' via GitHub API (transport error)."
  elif [[ "${repo_endpoint_status}" == "200" ]]; then
    :
  elif [[ "${repo_endpoint_status}" == "401" || "${repo_endpoint_status}" == "403" ]]; then
    error_type="auth_denied"
    error_message="Authentication denied for source repo '${repo}'. Verify UO_EVIDENCE_SOURCE_TOKEN read access."
  elif [[ "${repo_endpoint_status}" == "404" ]]; then
    error_type="repo_not_found"
    error_message="Source repo '${repo}' was not found. Verify UO_EVIDENCE_CORPUS_SOURCE_REPO value."
  else
    error_type="checkout_preflight_failed"
    error_message="Unable to validate source repo '${repo}' via GitHub API (status=${repo_endpoint_status})."
  fi
  rm -f "${repo_resp_file}"

  # --- Ref validation ---
  if [[ -z "${error_type}" ]]; then
    ref_endpoint=""
    if [[ "${effective_ref}" =~ ^refs/tags/(.+)$ ]]; then
      ref_endpoint="${api_base}/git/ref/tags/${BASH_REMATCH[1]}"
    elif [[ "${effective_ref}" =~ ^[A-Fa-f0-9]{7,40}$ ]]; then
      ref_endpoint="${api_base}/commits/${effective_ref}"
    elif [[ "${effective_ref}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$ ]]; then
      ref_endpoint="${api_base}/git/ref/tags/${effective_ref}"
    else
      ref_endpoint="${api_base}/git/ref/heads/${effective_ref}"
    fi

    ref_resp_file="$(mktemp)"
    set +e
    ref_check_status="$(curl -sS -L -o "${ref_resp_file}" -w '%{http_code}' "${auth_args[@]}" "${ref_endpoint}")"
    curl_rc=$?
    set -e

    if [[ ${curl_rc} -ne 0 ]]; then
      error_type="checkout_preflight_failed"
      error_message="Unable to validate source ref '${effective_ref}' in repo '${repo}' via GitHub API (transport error)."
    elif [[ "${ref_check_status}" == "200" ]]; then
      preflight_ok="true"
    elif [[ "${ref_check_status}" == "404" ]]; then
      error_type="ref_missing"
      error_message="Configured ref '${effective_ref}' was not found in source repo '${repo}'."
    elif [[ "${ref_check_status}" == "401" || "${ref_check_status}" == "403" ]]; then
      error_type="auth_denied"
      error_message="Authentication denied for source repo '${repo}'. Verify UO_EVIDENCE_SOURCE_TOKEN read access."
    else
      error_type="checkout_preflight_failed"
      error_message="Unable to validate source ref '${effective_ref}' in repo '${repo}' via GitHub API (status=${ref_check_status})."
    fi
    rm -f "${ref_resp_file}"
  fi
fi

# --- Summary + outputs ---
echo "Source selection: repo='${repo}' cross_repo='${cross_repo}' ref='${effective_ref:-<unset>}' origin='${ref_origin:-<unset>}' mode='${ref_mode}' release_lane='${release_lane}' token_present='${token_present:-false}' repo_endpoint_status='${repo_endpoint_status:-not_checked}' ref_check_status='${ref_check_status:-not_checked}'"

echo "preflight_ok=${preflight_ok}" >> "$GITHUB_OUTPUT"
echo "error_type=${error_type}" >> "$GITHUB_OUTPUT"
echo "error_message=${error_message}" >> "$GITHUB_OUTPUT"
echo "effective_ref=${effective_ref}" >> "$GITHUB_OUTPUT"
echo "ref_mode=${ref_mode}" >> "$GITHUB_OUTPUT"
echo "cross_repo=${cross_repo}" >> "$GITHUB_OUTPUT"
echo "ref_origin=${ref_origin}" >> "$GITHUB_OUTPUT"
echo "token_present=${token_present:-false}" >> "$GITHUB_OUTPUT"
echo "repo_endpoint_status=${repo_endpoint_status:-not_checked}" >> "$GITHUB_OUTPUT"
echo "ref_check_status=${ref_check_status:-not_checked}" >> "$GITHUB_OUTPUT"

if [[ "${preflight_ok}" == "true" ]]; then
  echo "Source preflight passed for ${repo}@${effective_ref} (mode=${ref_mode})."
else
  echo "::warning::Source preflight failed (${error_type}): ${error_message}"
  exit 1
fi
