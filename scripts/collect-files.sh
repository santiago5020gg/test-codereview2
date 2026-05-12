#!/usr/bin/env bash
# collect-files.sh — Collects code files changed in a PR
# Usage: ./scripts/collect-files.sh <base_ref> <head_ref>
# Output: Newline-separated list of changed code files (stdout)
# Exit 0 with empty output if no reviewable files changed.

set -euo pipefail

BASE_REF="${1:?Usage: collect-files.sh <base_ref> <head_ref>}"
HEAD_REF="${2:?Usage: collect-files.sh <base_ref> <head_ref>}"

EXTENSIONS="ts|tsx|js|jsx|prisma|sql"

git diff --name-only --diff-filter=ACMR "${BASE_REF}...${HEAD_REF}" \
  | grep -E "\.(${EXTENSIONS})$" \
  || true
