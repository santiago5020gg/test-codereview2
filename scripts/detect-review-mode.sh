#!/usr/bin/env bash
# detect-review-mode.sh — Determines FULL or INCREMENTAL review mode
# Usage: ./scripts/detect-review-mode.sh
# Requires env: PR_NUMBER, FORCE_PUSH, HAS_FULL_REVIEW_LABEL, ARTIFACT_PATH
# Output: Prints "FULL" or "INCREMENTAL" to stdout

set -euo pipefail

PR_NUMBER="${PR_NUMBER:?PR_NUMBER is required}"
FORCE_PUSH="${FORCE_PUSH:-false}"
HAS_FULL_REVIEW_LABEL="${HAS_FULL_REVIEW_LABEL:-false}"
ARTIFACT_PATH="${ARTIFACT_PATH:-}"

# FULL review conditions:
# 1. Force push
if [[ "${FORCE_PUSH}" == "true" ]]; then
  echo "FULL"
  exit 0
fi

# 2. full-review label present
if [[ "${HAS_FULL_REVIEW_LABEL}" == "true" ]]; then
  echo "FULL"
  exit 0
fi

# 3. No prior artifact exists
if [[ -z "${ARTIFACT_PATH}" || ! -f "${ARTIFACT_PATH}" ]]; then
  echo "FULL"
  exit 0
fi

# 4. Artifact exists but push_count is 0 (shouldn't happen, but fail-safe)
PUSH_COUNT=$(jq -r '.push_count // 0' "${ARTIFACT_PATH}")
if [[ "${PUSH_COUNT}" -eq 0 ]]; then
  echo "FULL"
  exit 0
fi

echo "INCREMENTAL"
