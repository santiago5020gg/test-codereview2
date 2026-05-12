#!/usr/bin/env bash
# scripts/cleanup-prior-reviews.sh
#
# Dismisses pending REQUEST_CHANGES reviews from the bot and
# minimizes old COMMENT reviews to reduce noise.
#
# Requires: gh CLI authenticated, PR_NUMBER set

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PR_NUMBER="${PR_NUMBER:?PR_NUMBER is required}"
REPO="${REPO:?REPO is required}"

cleanup_reviews() {
  log_info "Cleaning up prior bot reviews on PR #${PR_NUMBER}..."

  # Get all reviews on the PR
  local reviews
  reviews=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate 2>/dev/null || echo "[]")

  # Find bot reviews (those containing our marker in their body)
  local review_ids
  review_ids=$(echo "$reviews" | jq -r '.[] | select(.body | contains("pr-code-review-validator")) | .id')

  if [[ -z "$review_ids" ]]; then
    log_info "No prior bot reviews found."
    return 0
  fi

  local count=0
  while IFS= read -r review_id; do
    [[ -z "$review_id" ]] && continue

    local state
    state=$(echo "$reviews" | jq -r ".[] | select(.id == ${review_id}) | .state")

    if [[ "$state" == "CHANGES_REQUESTED" ]]; then
      # Dismiss REQUEST_CHANGES reviews
      log_info "Dismissing review ${review_id} (CHANGES_REQUESTED)..."
      gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews/${review_id}/dismissals" \
        -f message="Superseded by new review run." \
        --silent 2>/dev/null || log_warn "Failed to dismiss review ${review_id}"
    fi

    # Minimize all bot review comments (collapse them)
    local comment_node_id
    comment_node_id=$(echo "$reviews" | jq -r ".[] | select(.id == ${review_id}) | .node_id")

    if [[ -n "$comment_node_id" && "$comment_node_id" != "null" ]]; then
      gh api graphql -f query="
        mutation {
          minimizeComment(input: {subjectId: \"${comment_node_id}\", classifier: OUTDATED}) {
            minimizedComment { isMinimized }
          }
        }
      " --silent 2>/dev/null || log_warn "Failed to minimize review ${review_id}"
    fi

    count=$((count + 1))
  done <<< "$review_ids"

  log_info "Cleaned up ${count} prior bot review(s)."
}

cleanup_reviews
