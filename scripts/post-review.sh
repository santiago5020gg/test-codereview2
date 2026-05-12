#!/usr/bin/env bash
# scripts/post-review.sh
#
# Posts the pipeline result as a GitHub PR review and saves the artifact.
#
# Inputs (env vars):
#   PR_NUMBER       — PR number
#   REPO            — owner/repo
#   HEAD_SHA        — commit SHA to attach review to
#   PIPELINE_OUTPUT — path to pipeline result JSON
#   PUSH_COUNT      — current push count (from artifact or 1)
#
# Outputs:
#   - GitHub PR review posted
#   - .review-artifacts/violations.json updated

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PR_NUMBER="${PR_NUMBER:?PR_NUMBER is required}"
REPO="${REPO:?REPO is required}"
HEAD_SHA="${HEAD_SHA:?HEAD_SHA is required}"
PIPELINE_OUTPUT="${PIPELINE_OUTPUT:-/tmp/pipeline-result.json}"
PUSH_COUNT="${PUSH_COUNT:-1}"

post_review() {
  if [[ ! -f "$PIPELINE_OUTPUT" ]]; then
    log_error "Pipeline output not found: $PIPELINE_OUTPUT"
    exit 1
  fi

  local verdict summary
  verdict=$(jq -r '.verdict' "$PIPELINE_OUTPUT")
  summary=$(jq -r '.summary' "$PIPELINE_OUTPUT")

  # Determine review event
  local event
  case "$verdict" in
    fail) event="REQUEST_CHANGES" ;;
    *)    event="COMMENT" ;;
  esac

  # Build review body with marker
  local body="${REVIEW_MARKER}"$'\n\n'"${summary}"

  # Build inline comments array for gh API
  local comments
  comments=$(jq -c '.inline_comments // []' "$PIPELINE_OUTPUT")
  local comment_count
  comment_count=$(echo "$comments" | jq 'length')

  log_info "Posting review: verdict=${verdict}, event=${event}, comments=${comment_count}"

  # Build the review payload
  local payload
  payload=$(jq -n \
    --arg body "$body" \
    --arg event "$event" \
    --arg commit_id "$HEAD_SHA" \
    --argjson comments "$comments" \
    '{
      body: $body,
      event: $event,
      commit_id: $commit_id,
      comments: $comments
    }')

  # Post the review
  echo "$payload" | gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" \
    --input - \
    --silent

  if [[ $? -eq 0 ]]; then
    log_info "Review posted successfully."
  else
    log_error "Failed to post review."
    exit 1
  fi
}

save_artifact() {
  mkdir -p "$ARTIFACTS_DIR"

  # Build active violations from inline_comments
  local active_violations
  active_violations=$(jq '[.inline_comments[] | {
    path: .path,
    line: .line,
    skill: ((.body | capture("\\[(?<s>[^|]+)") // {s: "unknown"}).s | gsub("^\\*\\*\\[?|\\]?\\*\\*$"; "")),
    rule: ((.body | capture("\\| (?<r>[^\\]]+)") // {r: "unknown"}).r),
    description: .body,
    suggestion: "",
    found_in_push: '"$PUSH_COUNT"',
    body: .body
  }]' "$PIPELINE_OUTPUT")

  local artifact
  artifact=$(jq -n \
    --argjson pr_number "$PR_NUMBER" \
    --arg last_push_sha "$HEAD_SHA" \
    --argjson push_count "$PUSH_COUNT" \
    --argjson active_violations "$active_violations" \
    '{
      pr_number: $pr_number,
      last_push_sha: $last_push_sha,
      push_count: $push_count,
      active_violations: $active_violations
    }')

  echo "$artifact" > "${ARTIFACTS_DIR}/violations.json"
  log_info "Artifact saved to ${ARTIFACTS_DIR}/violations.json"
}

post_review
save_artifact
