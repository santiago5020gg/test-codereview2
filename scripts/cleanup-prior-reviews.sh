#!/usr/bin/env bash
# cleanup-prior-reviews.sh — Minimizes prior bot review comments on a PR
# Usage: ./scripts/cleanup-prior-reviews.sh
# Requires env: PR_NUMBER, GITHUB_REPOSITORY
# Requires: gh CLI authenticated

set -euo pipefail

PR_NUMBER="${PR_NUMBER:?PR_NUMBER is required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

MARKER="<!-- pr-code-review-validator -->"

# Get all reviews on this PR
REVIEWS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate --jq '.[].id')

if [[ -z "${REVIEWS}" ]]; then
  echo "No prior reviews found."
  exit 0
fi

# Get review comments and minimize those with our marker
COMMENTS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/comments" --paginate \
  --jq ".[] | select(.body | contains(\"${MARKER}\")) | .node_id")

MINIMIZED=0
for NODE_ID in ${COMMENTS}; do
  gh api graphql -f query="
    mutation {
      minimizeComment(input: {subjectId: \"${NODE_ID}\", classifier: OUTDATED}) {
        minimizedComment { isMinimized }
      }
    }
  " --silent 2>/dev/null && ((MINIMIZED++)) || true
done

# Dismiss prior REQUEST_CHANGES reviews from the bot
BOT_REVIEWS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
  --jq '.[] | select(.state == "CHANGES_REQUESTED") | select(.body | contains("'"${MARKER}"'")) | .id')

DISMISSED=0
for REVIEW_ID in ${BOT_REVIEWS}; do
  gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews/${REVIEW_ID}/dismissals" \
    -f message="Superseded by new review run." \
    --silent 2>/dev/null && ((DISMISSED++)) || true
done

echo "Minimized ${MINIMIZED} comments, dismissed ${DISMISSED} reviews."
