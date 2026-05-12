#!/usr/bin/env bash
# scripts/detect-review-mode.sh
#
# Determines review mode: FULL or INCREMENTAL
# Outputs: MODE=FULL|INCREMENTAL to GITHUB_OUTPUT
#
# FULL triggers:
#   - First push (push_count would be 0 in artifact)
#   - Force push (github.event.forced == true)
#   - "full-review" label on PR
#   - No prior violations artifact
#
# INCREMENTAL triggers:
#   - Subsequent push with existing artifact

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PR_NUMBER="${PR_NUMBER:?PR_NUMBER is required}"
FORCED="${FORCED:-false}"
LABELS="${LABELS:-}"
ARTIFACT_PATH="${ARTIFACTS_DIR}/violations.json"

detect_mode() {
  # Check: force push
  if [[ "$FORCED" == "true" ]]; then
    log_info "Force push detected → FULL review"
    echo "MODE=FULL" >> "$GITHUB_OUTPUT"
    echo "REASON=force-push" >> "$GITHUB_OUTPUT"
    return
  fi

  # Check: full-review label
  if echo "$LABELS" | grep -q "full-review"; then
    log_info "'full-review' label detected → FULL review"
    echo "MODE=FULL" >> "$GITHUB_OUTPUT"
    echo "REASON=label" >> "$GITHUB_OUTPUT"
    return
  fi

  # Check: prior artifact exists (downloaded from GitHub artifacts)
  if [[ ! -f "$ARTIFACT_PATH" ]]; then
    log_info "No prior violations artifact → FULL review"
    echo "MODE=FULL" >> "$GITHUB_OUTPUT"
    echo "REASON=no-artifact" >> "$GITHUB_OUTPUT"
    return
  fi

  # Validate artifact belongs to this PR
  local artifact_pr
  artifact_pr=$(jq -r '.pr_number' "$ARTIFACT_PATH" 2>/dev/null || echo "")
  if [[ "$artifact_pr" != "$PR_NUMBER" ]]; then
    log_info "Artifact PR mismatch (artifact=${artifact_pr}, current=${PR_NUMBER}) → FULL review"
    echo "MODE=FULL" >> "$GITHUB_OUTPUT"
    echo "REASON=pr-mismatch" >> "$GITHUB_OUTPUT"
    return
  fi

  # All checks passed: incremental
  log_info "Prior artifact found for PR #${PR_NUMBER} → INCREMENTAL review"
  echo "MODE=INCREMENTAL" >> "$GITHUB_OUTPUT"
  echo "REASON=has-artifact" >> "$GITHUB_OUTPUT"
}

detect_mode
