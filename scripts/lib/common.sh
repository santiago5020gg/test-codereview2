#!/usr/bin/env bash
# scripts/lib/common.sh

set -euo pipefail

# File extensions to review
CODE_EXTENSIONS=("ts" "tsx" "js" "jsx" "prisma" "sql")

# Bot review marker (HTML comment embedded in every review)
REVIEW_MARKER="<!-- pr-code-review-validator -->"

# Skills directory
SKILLS_DIR=".claude/skills"

# Artifacts directory
ARTIFACTS_DIR=".review-artifacts"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging helpers
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Build glob pattern for code extensions (e.g., "*.ts *.tsx *.js ...")
build_extension_glob() {
  local patterns=()
  for ext in "${CODE_EXTENSIONS[@]}"; do
    patterns+=("*.${ext}")
  done
  echo "${patterns[*]}"
}

# Check if a file matches code extensions
is_code_file() {
  local file="$1"
  local ext="${file##*.}"
  for code_ext in "${CODE_EXTENSIONS[@]}"; do
    if [[ "$ext" == "$code_ext" ]]; then
      return 0
    fi
  done
  return 1
}
