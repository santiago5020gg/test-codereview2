# GitHub Code Review Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an automated PR code review pipeline using GitHub Actions, shell scripts, prompt templates, and Claude Code CLI that validates code changes against skill-defined rules.

**Architecture:** A GitHub Actions workflow triggers on PR events, collects changed code files, sends them through a two-stage AI pipeline (Sonnet validates against skills → Opus synthesizes and filters), then posts a bundled review to GitHub. Incremental mode re-verifies prior violations on re-push.

**Tech Stack:** GitHub Actions, Bash scripts, Claude Code CLI (`@anthropic-ai/claude-code`), Portkey gateway → AWS Bedrock, `gh` CLI, `jq`

---

## File Structure

| Path | Responsibility |
|------|---------------|
| `.github/workflows/pr-code-review-validator.yml` | GitHub Actions workflow definition — triggers, env, job steps |
| `scripts/lib/common.sh` | Shared constants: file extensions, markers, colors, helper functions |
| `scripts/lib/json-extract.sh` | Multi-strategy JSON extraction from Claude CLI output |
| `scripts/detect-review-mode.sh` | Decides FULL vs INCREMENTAL mode based on PR state |
| `scripts/cleanup-prior-reviews.sh` | Dismisses/minimizes old bot reviews before posting new one |
| `scripts/run-review-pipeline.sh` | Orchestrates file collection + validation + synthesis |
| `scripts/post-review.sh` | Posts bundled review to GitHub, writes violations artifact |
| `prompts/pipeline-full.md` | Prompt template for full validation (Sonnet) |
| `prompts/pipeline-incremental-track2.md` | Prompt template for Track 2: new files only (Sonnet) |
| `prompts/verification-track1.md` | Prompt template for Track 1: re-verify prior violations (Sonnet) |
| `prompts/synthesize.md` | Prompt template for synthesis stage (Opus) |

---

### Task 1: Shared Library — `scripts/lib/common.sh`

**Files:**
- Create: `scripts/lib/common.sh`

- [ ] **Step 1: Create the shared constants file**

```bash
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
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/lib/common.sh`
Expected: No output (clean parse)

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/common.sh
git commit -m "feat: add shared constants library (common.sh)"
```

---

### Task 2: JSON Extraction Library — `scripts/lib/json-extract.sh`

**Files:**
- Create: `scripts/lib/json-extract.sh`

The Claude CLI in `--output-format json` mode wraps output in a JSON structure. We need to extract the inner content reliably. Multiple strategies handle edge cases (raw JSON array, wrapped in `result` field, markdown fences).

- [ ] **Step 1: Create the JSON extraction script**

```bash
#!/usr/bin/env bash
# scripts/lib/json-extract.sh
#
# Extracts clean JSON from Claude CLI output.
# Claude --output-format json wraps the response in: {"type":"result","result":"<content>"}
# The inner content may be a JSON string (escaped), a raw JSON array, or wrapped in markdown fences.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Extract JSON array from Claude CLI output
# Usage: extract_json <input_file> <output_file>
extract_json() {
  local input="$1"
  local output="$2"

  if [[ ! -f "$input" ]]; then
    log_error "Input file not found: $input"
    return 1
  fi

  # Strategy 1: Try to extract .result field from Claude's JSON wrapper
  if jq -e '.result' "$input" > /dev/null 2>&1; then
    local inner
    inner=$(jq -r '.result' "$input")

    # The inner content might be a JSON string or have markdown fences
    # Strip markdown fences if present
    inner=$(echo "$inner" | sed '/^```json$/d' | sed '/^```$/d')

    # Try to parse as JSON
    if echo "$inner" | jq -e '.' > /dev/null 2>&1; then
      echo "$inner" | jq '.' > "$output"
      return 0
    fi
  fi

  # Strategy 2: File itself is valid JSON array
  if jq -e 'if type == "array" then true else false end' "$input" > /dev/null 2>&1; then
    jq '.' "$input" > "$output"
    return 0
  fi

  # Strategy 3: Extract JSON array from anywhere in the file (first [ to last ])
  if grep -q '^\[' "$input"; then
    local extracted
    extracted=$(sed -n '/^\[/,/^\]/p' "$input")
    if echo "$extracted" | jq -e '.' > /dev/null 2>&1; then
      echo "$extracted" | jq '.' > "$output"
      return 0
    fi
  fi

  # Strategy 4: Try extracting JSON object (for synthesis output)
  if jq -e 'if type == "object" then true else false end' "$input" > /dev/null 2>&1; then
    jq '.' "$input" > "$output"
    return 0
  fi

  log_error "Failed to extract valid JSON from: $input"
  return 1
}

# Extract JSON object (for synthesis/pipeline output)
# Usage: extract_json_object <input_file> <output_file>
extract_json_object() {
  local input="$1"
  local output="$2"

  if [[ ! -f "$input" ]]; then
    log_error "Input file not found: $input"
    return 1
  fi

  # Strategy 1: Extract from .result field
  if jq -e '.result' "$input" > /dev/null 2>&1; then
    local inner
    inner=$(jq -r '.result' "$input")
    inner=$(echo "$inner" | sed '/^```json$/d' | sed '/^```$/d')

    if echo "$inner" | jq -e 'if type == "object" then true else false end' > /dev/null 2>&1; then
      echo "$inner" | jq '.' > "$output"
      return 0
    fi
  fi

  # Strategy 2: File itself is valid JSON object
  if jq -e 'if type == "object" then true else false end' "$input" > /dev/null 2>&1; then
    jq '.' "$input" > "$output"
    return 0
  fi

  log_error "Failed to extract valid JSON object from: $input"
  return 1
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/lib/json-extract.sh`
Expected: No output (clean parse)

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/json-extract.sh
git commit -m "feat: add multi-strategy JSON extraction library"
```

---

### Task 3: Review Mode Detection — `scripts/detect-review-mode.sh`

**Files:**
- Create: `scripts/detect-review-mode.sh`

This script determines whether to run a FULL or INCREMENTAL review. FULL is triggered when: first push on the PR, force-push, `full-review` label present, or no prior violations artifact exists.

- [ ] **Step 1: Create the detection script**

```bash
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
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/detect-review-mode.sh`
Expected: No output (clean parse)

- [ ] **Step 3: Make executable and commit**

```bash
chmod +x scripts/detect-review-mode.sh
git add scripts/detect-review-mode.sh
git commit -m "feat: add review mode detection script (FULL vs INCREMENTAL)"
```

---

### Task 4: Cleanup Prior Reviews — `scripts/cleanup-prior-reviews.sh`

**Files:**
- Create: `scripts/cleanup-prior-reviews.sh`

Before posting a new review, dismiss any previous bot reviews (REQUEST_CHANGES) and minimize old COMMENT reviews so the PR doesn't accumulate stale feedback.

- [ ] **Step 1: Create the cleanup script**

```bash
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
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/cleanup-prior-reviews.sh`
Expected: No output (clean parse)

- [ ] **Step 3: Make executable and commit**

```bash
chmod +x scripts/cleanup-prior-reviews.sh
git add scripts/cleanup-prior-reviews.sh
git commit -m "feat: add cleanup script to dismiss/minimize stale bot reviews"
```

---

### Task 5: Prompt Templates

**Files:**
- Create: `prompts/pipeline-full.md`
- Create: `prompts/pipeline-incremental-track2.md`
- Create: `prompts/verification-track1.md`
- Create: `prompts/synthesize.md`

- [ ] **Step 1: Create the full validation prompt template**

```markdown
# prompts/pipeline-full.md

You are a code reviewer. Review the following changed files against ALL skills defined below.

## Skills (Review Rules)

{{SKILLS_CONTENT}}

## Changed Files

{{FILES_CONTENT}}

## Instructions

1. Read each skill carefully. Each skill defines rules with specific criteria.
2. For each changed file, check every rule from every skill.
3. Only report ACTUAL violations — code that clearly breaks a rule.
4. Do NOT report style preferences, suggestions, or improvements not covered by a skill.
5. If no violations exist, return an empty array.

## Output Format

Return a JSON array (no markdown fences, no explanation, ONLY the JSON):

```json
[
  {
    "skill": "<skill-name>",
    "rule": "<rule/category name>",
    "path": "relative/path.ts",
    "line": 15,
    "description": "What violates the rule and why",
    "suggestion": "Specific, actionable fix",
    "severity": "Critical | Recommended"
  }
]
```

If no violations are found, return exactly: `[]`
```

- [ ] **Step 2: Create the Track 2 incremental prompt template**

```markdown
# prompts/pipeline-incremental-track2.md

You are a code reviewer. Review ONLY the following newly changed files against ALL skills defined below.

These files had no prior violations — this is their first review in this PR.

## Skills (Review Rules)

{{SKILLS_CONTENT}}

## Newly Changed Files (no prior violations)

{{FILES_CONTENT}}

## Instructions

1. Read each skill carefully. Each skill defines rules with specific criteria.
2. For each file, check every rule from every skill.
3. Only report ACTUAL violations — code that clearly breaks a rule.
4. Do NOT report style preferences, suggestions, or improvements not covered by a skill.
5. If no violations exist, return an empty array.

## Output Format

Return a JSON array (no markdown fences, no explanation, ONLY the JSON):

```json
[
  {
    "skill": "<skill-name>",
    "rule": "<rule/category name>",
    "path": "relative/path.ts",
    "line": 15,
    "description": "What violates the rule and why",
    "suggestion": "Specific, actionable fix",
    "severity": "Critical | Recommended"
  }
]
```

If no violations are found, return exactly: `[]`
```

- [ ] **Step 3: Create the Track 1 verification prompt template**

```markdown
# prompts/verification-track1.md

You are verifying whether previously detected violations still exist in the code after changes.

## Prior Violations to Verify

{{VIOLATIONS_JSON}}

## Current File Contents

{{FILES_CONTENT}}

## Instructions

For each violation listed above:
1. Find the file and line referenced.
2. Determine if the violation STILL EXISTS in the current code or has been RESOLVED.
3. A violation is "resolved" if the code has been changed to no longer break the rule.
4. A violation is "still_present" if the problematic code remains unchanged or the issue persists.
5. Line numbers may have shifted — match by the code pattern and context, not exact line number.

## Output Format

Return a JSON array (no markdown fences, no explanation, ONLY the JSON):

```json
[
  {
    "skill": "<skill-name>",
    "rule": "<rule/category name>",
    "path": "relative/path.ts",
    "line": 15,
    "status": "still_present | resolved",
    "description": "Original violation description",
    "suggestion": "Original suggestion (if still_present)",
    "severity": "Critical | Recommended"
  }
]
```
```

- [ ] **Step 4: Create the synthesis prompt template**

```markdown
# prompts/synthesize.md

You are a senior code reviewer performing final synthesis. Your job is to filter false positives and format the final review.

## Violations Detected by Validator

{{VIOLATIONS_JSON}}

## Changed Files (for context)

{{FILES_CONTENT}}

## Instructions

1. Review each violation against the actual code.
2. REMOVE false positives — violations that are:
   - Not actually violating the rule when you read the full context
   - Referring to code that doesn't exist at the stated line
   - Duplicates of another violation (keep the better-described one)
   - Based on misunderstanding of the code's intent
3. KEEP true positives — violations that clearly break a stated rule.
4. Format inline comments to be helpful and specific.
5. Determine the verdict:
   - "fail" if ANY Critical violations remain after filtering
   - "pass" if only Recommended violations remain (or none)
   - "skip" if all violations were false positives

## Output Format

Return a JSON object (no markdown fences, no explanation, ONLY the JSON):

```json
{
  "verdict": "pass | fail | skip",
  "summary": "Markdown summary of findings (2-3 sentences)",
  "inline_comments": [
    {
      "path": "relative/path.ts",
      "line": 15,
      "side": "RIGHT",
      "body": "**[skill-name | Rule Name]** (Critical/Recommended)\n\nDescription of the issue.\n\n**Suggestion:** How to fix it."
    }
  ],
  "stats": {
    "files_checked": 5,
    "files_changed": 3,
    "skills_applied": ["skill-name-1", "skill-name-2"],
    "violations_found": 4,
    "false_positives_filtered": 1
  }
}
```
```

- [ ] **Step 5: Commit all prompts**

```bash
git add prompts/pipeline-full.md prompts/pipeline-incremental-track2.md prompts/verification-track1.md prompts/synthesize.md
git commit -m "feat: add all prompt templates (validation, verification, synthesis)"
```

---

### Task 6: Main Pipeline Orchestrator — `scripts/run-review-pipeline.sh`

**Files:**
- Create: `scripts/run-review-pipeline.sh`

This is the core script that: collects files, reads skills, builds prompts, invokes Claude CLI for validation, and (if violations found) invokes synthesis.

- [ ] **Step 1: Create the pipeline orchestrator**

```bash
#!/usr/bin/env bash
# scripts/run-review-pipeline.sh
#
# Orchestrates the full review pipeline:
#   1. Collect changed code files
#   2. Read all skills from .claude/skills/
#   3. Build prompt (from template + files + skills)
#   4. Invoke Sonnet for validation
#   5. If violations found → invoke Opus for synthesis
#   6. Output final pipeline result as JSON
#
# Inputs (env vars):
#   MODE          — FULL or INCREMENTAL
#   PR_NUMBER     — PR number
#   BASE_SHA      — Base commit SHA for diff
#   HEAD_SHA      — Head commit SHA
#   TIMEOUT       — Pipeline timeout in seconds (default: 540)
#
# Outputs: writes final result to $PIPELINE_OUTPUT (default: /tmp/pipeline-result.json)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/json-extract.sh"

MODE="${MODE:?MODE is required (FULL or INCREMENTAL)}"
PR_NUMBER="${PR_NUMBER:?PR_NUMBER is required}"
BASE_SHA="${BASE_SHA:?BASE_SHA is required}"
HEAD_SHA="${HEAD_SHA:?HEAD_SHA is required}"
TIMEOUT="${TIMEOUT:-540}"
PIPELINE_OUTPUT="${PIPELINE_OUTPUT:-/tmp/pipeline-result.json}"
ARTIFACT_PATH="${ARTIFACTS_DIR}/violations.json"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Step 1: Collect changed code files ---

collect_files() {
  log_info "Collecting changed code files (${BASE_SHA}..${HEAD_SHA})..."

  local all_changed
  all_changed=$(git diff --name-only --diff-filter=ACMR "${BASE_SHA}...${HEAD_SHA}" || true)

  local code_files=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if is_code_file "$file" && [[ -f "$file" ]]; then
      code_files+=("$file")
    fi
  done <<< "$all_changed"

  if [[ ${#code_files[@]} -eq 0 ]]; then
    log_info "No code files changed."
    echo ""
    return
  fi

  log_info "Found ${#code_files[@]} code file(s) to review."
  printf '%s\n' "${code_files[@]}"
}

# --- Step 2: Read all skills ---

collect_skills() {
  log_info "Collecting skills from ${SKILLS_DIR}/..."

  local skills_content=""
  if [[ -d "$SKILLS_DIR" ]]; then
    for skill_dir in "$SKILLS_DIR"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_file="${skill_dir}SKILL.md"
      if [[ -f "$skill_file" ]]; then
        local skill_name
        skill_name=$(basename "$skill_dir")
        skills_content+="### Skill: ${skill_name}"$'\n\n'
        skills_content+=$(cat "$skill_file")
        skills_content+=$'\n\n---\n\n'
      fi
    done
  fi

  if [[ -z "$skills_content" ]]; then
    log_warn "No skills found. Pipeline will have no rules to validate against."
    skills_content="(No review skills defined)"
  fi

  echo "$skills_content"
}

# --- Step 3: Build file contents block ---

build_files_content() {
  local files=("$@")
  local content=""

  for file in "${files[@]}"; do
    content+="#### File: ${file}"$'\n\n'
    content+='```'"${file##*.}"$'\n'
    content+=$(cat "$file")
    content+=$'\n```\n\n'
  done

  echo "$content"
}

# --- Step 4: Build and send validation prompt ---

run_validation() {
  local files=("$@")
  local template
  local prompt

  if [[ "$MODE" == "FULL" ]]; then
    template=$(cat "${SCRIPT_DIR}/../prompts/pipeline-full.md")
  else
    template=$(cat "${SCRIPT_DIR}/../prompts/pipeline-incremental-track2.md")
  fi

  local skills_content
  skills_content=$(collect_skills)

  local files_content
  files_content=$(build_files_content "${files[@]}")

  # Replace placeholders
  prompt="${template//\{\{SKILLS_CONTENT\}\}/$skills_content}"
  prompt="${prompt//\{\{FILES_CONTENT\}\}/$files_content}"

  echo "$prompt" > "${WORK_DIR}/validation-prompt.txt"

  log_info "Running validation (Sonnet)..."
  local raw_output="${WORK_DIR}/validation-raw.json"

  timeout 180 claude --print --model sonnet --output-format json \
    < "${WORK_DIR}/validation-prompt.txt" \
    > "$raw_output" 2>/dev/null

  local violations="${WORK_DIR}/violations.json"
  if ! extract_json "$raw_output" "$violations"; then
    log_error "Failed to extract validation output."
    echo "[]" > "$violations"
  fi

  cat "$violations"
}

# --- Step 5: Run Track 1 verification (incremental only) ---

run_track1_verification() {
  local artifact="$1"

  local prior_violations
  prior_violations=$(jq -r '.active_violations' "$artifact")

  if [[ "$prior_violations" == "[]" || "$prior_violations" == "null" ]]; then
    log_info "No prior violations to re-verify."
    echo "[]"
    return
  fi

  # Get files referenced by prior violations
  local violation_files
  violation_files=$(echo "$prior_violations" | jq -r '.[].path' | sort -u)

  local files_to_check=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if [[ -f "$file" ]]; then
      files_to_check+=("$file")
    fi
  done <<< "$violation_files"

  if [[ ${#files_to_check[@]} -eq 0 ]]; then
    log_info "Prior violation files no longer exist — marking all resolved."
    echo "$prior_violations" | jq '[.[] | . + {"status": "resolved"}]'
    return
  fi

  local template
  template=$(cat "${SCRIPT_DIR}/../prompts/verification-track1.md")

  local files_content
  files_content=$(build_files_content "${files_to_check[@]}")

  local prompt="${template//\{\{VIOLATIONS_JSON\}\}/$prior_violations}"
  prompt="${prompt//\{\{FILES_CONTENT\}\}/$files_content}"

  echo "$prompt" > "${WORK_DIR}/track1-prompt.txt"

  log_info "Running Track 1 verification (Sonnet)..."
  local raw_output="${WORK_DIR}/track1-raw.json"

  timeout 180 claude --print --model sonnet --output-format json \
    < "${WORK_DIR}/track1-prompt.txt" \
    > "$raw_output" 2>/dev/null

  local result="${WORK_DIR}/track1-result.json"
  if ! extract_json "$raw_output" "$result"; then
    log_error "Failed to extract Track 1 output. Treating all as still_present."
    echo "$prior_violations" | jq '[.[] | . + {"status": "still_present"}]'
    return
  fi

  cat "$result"
}

# --- Step 6: Run synthesis (Opus) ---

run_synthesis() {
  local violations="$1"
  shift
  local files=("$@")

  local template
  template=$(cat "${SCRIPT_DIR}/../prompts/synthesize.md")

  local files_content
  files_content=$(build_files_content "${files[@]}")

  local prompt="${template//\{\{VIOLATIONS_JSON\}\}/$violations}"
  prompt="${prompt//\{\{FILES_CONTENT\}\}/$files_content}"

  echo "$prompt" > "${WORK_DIR}/synthesis-prompt.txt"

  log_info "Running synthesis (Opus)..."
  local raw_output="${WORK_DIR}/synthesis-raw.json"

  timeout 300 claude --print --model opus --output-format json \
    < "${WORK_DIR}/synthesis-prompt.txt" \
    > "$raw_output" 2>/dev/null

  local result="${WORK_DIR}/synthesis-result.json"
  if ! extract_json_object "$raw_output" "$result"; then
    log_error "Failed to extract synthesis output. Using fail-closed default."
    cat <<FAILSAFE > "$result"
{
  "verdict": "fail",
  "summary": "Synthesis stage failed to produce valid output. Review manually.",
  "inline_comments": [],
  "stats": {"files_checked": 0, "files_changed": 0, "skills_applied": [], "violations_found": 0, "false_positives_filtered": 0}
}
FAILSAFE
  fi

  cat "$result"
}

# --- Main orchestration ---

main() {
  log_info "Starting pipeline in ${MODE} mode for PR #${PR_NUMBER}..."

  # Collect files
  local changed_files_str
  changed_files_str=$(collect_files)

  if [[ -z "$changed_files_str" ]]; then
    log_info "No code files to review. Outputting skip."
    cat <<EOF > "$PIPELINE_OUTPUT"
{
  "verdict": "skip",
  "summary": "No reviewable code files changed in this PR.",
  "inline_comments": [],
  "stats": {"files_checked": 0, "files_changed": 0, "skills_applied": [], "violations_found": 0, "false_positives_filtered": 0}
}
EOF
    return 0
  fi

  local files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done <<< "$changed_files_str"

  local all_violations="[]"

  if [[ "$MODE" == "INCREMENTAL" && -f "$ARTIFACT_PATH" ]]; then
    # Track 1: Re-verify prior violations
    local track1_result
    track1_result=$(run_track1_verification "$ARTIFACT_PATH")

    # Keep only still_present violations from Track 1
    local still_present
    still_present=$(echo "$track1_result" | jq '[.[] | select(.status == "still_present") | del(.status)]')

    # Track 2: Validate new files (files NOT in prior violations)
    local prior_files
    prior_files=$(jq -r '.active_violations[].path' "$ARTIFACT_PATH" 2>/dev/null | sort -u)

    local track2_files=()
    for file in "${files[@]}"; do
      if ! echo "$prior_files" | grep -qx "$file"; then
        track2_files+=("$file")
      fi
    done

    if [[ ${#track2_files[@]} -gt 0 ]]; then
      local track2_result
      track2_result=$(run_validation "${track2_files[@]}")
      # Merge Track 1 + Track 2
      all_violations=$(jq -s '.[0] + .[1]' <(echo "$still_present") <(echo "$track2_result"))
    else
      all_violations="$still_present"
    fi
  else
    # FULL mode: validate all files
    all_violations=$(run_validation "${files[@]}")
  fi

  # Check if we have violations
  local violation_count
  violation_count=$(echo "$all_violations" | jq 'length')

  if [[ "$violation_count" -eq 0 ]]; then
    log_info "No violations found. Pipeline passes."
    cat <<EOF > "$PIPELINE_OUTPUT"
{
  "verdict": "pass",
  "summary": "No violations detected. All code changes comply with review rules.",
  "inline_comments": [],
  "stats": {"files_checked": ${#files[@]}, "files_changed": ${#files[@]}, "skills_applied": [], "violations_found": 0, "false_positives_filtered": 0}
}
EOF
    return 0
  fi

  log_info "Found ${violation_count} violation(s). Running synthesis..."

  # Run synthesis
  local final_result
  final_result=$(run_synthesis "$all_violations" "${files[@]}")

  echo "$final_result" > "$PIPELINE_OUTPUT"
  log_info "Pipeline complete. Verdict: $(echo "$final_result" | jq -r '.verdict')"
}

main
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/run-review-pipeline.sh`
Expected: No output (clean parse)

- [ ] **Step 3: Make executable and commit**

```bash
chmod +x scripts/run-review-pipeline.sh
git add scripts/run-review-pipeline.sh
git commit -m "feat: add main review pipeline orchestrator"
```

---

### Task 7: Post Review Script — `scripts/post-review.sh`

**Files:**
- Create: `scripts/post-review.sh`

This script reads the pipeline output, posts a bundled review to GitHub using `gh` CLI, and saves the violations artifact for future incremental runs.

- [ ] **Step 1: Create the post-review script**

```bash
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
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/post-review.sh`
Expected: No output (clean parse)

- [ ] **Step 3: Make executable and commit**

```bash
chmod +x scripts/post-review.sh
git add scripts/post-review.sh
git commit -m "feat: add post-review script (GitHub review + artifact persistence)"
```

---

### Task 8: GitHub Actions Workflow — `.github/workflows/pr-code-review-validator.yml`

**Files:**
- Create: `.github/workflows/pr-code-review-validator.yml`

- [ ] **Step 1: Create the workflow file**

```yaml
# .github/workflows/pr-code-review-validator.yml
name: PR Code Review Validator

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write

env:
  ANTHROPIC_BEDROCK_BASE_URL: "${{ secrets.BEDROCK_BASE_URL }}"
  ANTHROPIC_CUSTOM_HEADERS: "x-portkey-api-key:${{ secrets.PORTKEY_API_KEY }}\nx-portkey-provider:@aws-bedrock-use2"
  CLAUDE_CODE_USE_BEDROCK: "1"
  CLAUDE_CODE_SKIP_BEDROCK_AUTH: "1"

jobs:
  review:
    name: AI Code Review
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install Claude Code CLI
        run: npm install -g @anthropic-ai/claude-code

      - name: Install jq
        run: sudo apt-get install -y jq

      - name: Download prior artifact
        uses: actions/download-artifact@v4
        with:
          name: review-violations-pr-${{ github.event.pull_request.number }}
          path: .review-artifacts/
        continue-on-error: true

      - name: Detect review mode
        id: detect-mode
        env:
          PR_NUMBER: "${{ github.event.pull_request.number }}"
          FORCED: "${{ github.event.forced }}"
          LABELS: "${{ join(github.event.pull_request.labels.*.name, ',') }}"
          GITHUB_OUTPUT: "${{ github.output }}"
        run: |
          chmod +x scripts/detect-review-mode.sh
          bash scripts/detect-review-mode.sh

      - name: Cleanup prior reviews
        env:
          PR_NUMBER: "${{ github.event.pull_request.number }}"
          REPO: "${{ github.repository }}"
          GH_TOKEN: "${{ github.token }}"
        run: |
          chmod +x scripts/cleanup-prior-reviews.sh
          bash scripts/cleanup-prior-reviews.sh

      - name: Run review pipeline
        env:
          MODE: "${{ steps.detect-mode.outputs.MODE }}"
          PR_NUMBER: "${{ github.event.pull_request.number }}"
          BASE_SHA: "${{ github.event.pull_request.base.sha }}"
          HEAD_SHA: "${{ github.event.pull_request.head.sha }}"
          PIPELINE_OUTPUT: "/tmp/pipeline-result.json"
          TIMEOUT: "540"
        run: |
          chmod +x scripts/run-review-pipeline.sh
          timeout ${TIMEOUT}s bash scripts/run-review-pipeline.sh

      - name: Determine push count
        id: push-count
        run: |
          if [[ -f ".review-artifacts/violations.json" ]]; then
            CURRENT=$(jq -r '.push_count // 0' .review-artifacts/violations.json)
            echo "count=$((CURRENT + 1))" >> "$GITHUB_OUTPUT"
          else
            echo "count=1" >> "$GITHUB_OUTPUT"
          fi

      - name: Post review to GitHub
        env:
          PR_NUMBER: "${{ github.event.pull_request.number }}"
          REPO: "${{ github.repository }}"
          HEAD_SHA: "${{ github.event.pull_request.head.sha }}"
          PIPELINE_OUTPUT: "/tmp/pipeline-result.json"
          PUSH_COUNT: "${{ steps.push-count.outputs.count }}"
          GH_TOKEN: "${{ github.token }}"
        run: |
          chmod +x scripts/post-review.sh
          bash scripts/post-review.sh

      - name: Upload violations artifact
        uses: actions/upload-artifact@v4
        with:
          name: review-violations-pr-${{ github.event.pull_request.number }}
          path: .review-artifacts/violations.json
          overwrite: true
        if: always()
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pr-code-review-validator.yml'))"`
Expected: No output (valid YAML)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/pr-code-review-validator.yml
git commit -m "feat: add GitHub Actions workflow for PR code review"
```

---

### Task 9: Example Skill (for testing)

**Files:**
- Create: `.claude/skills/example-naming/SKILL.md`

A simple skill so the pipeline has at least one rule to test against.

- [ ] **Step 1: Create an example skill**

```markdown
# Naming Conventions

## Rules

### Rule 1: No single-letter variables

Variables must have descriptive names. Single-letter variable names (except `i`, `j`, `k` in loops, or `e` in catch blocks) are not allowed.

**Severity:** Recommended

**Applies to:** All code files

**Example violation:**
```typescript
const x = getUser();
const d = new Date();
```

**Example fix:**
```typescript
const user = getUser();
const currentDate = new Date();
```

### Rule 2: Boolean variables must use is/has/should/can prefix

Boolean variables and function return values should use a prefix that indicates they are boolean.

**Severity:** Recommended

**Applies to:** `.ts`, `.tsx`, `.js`, `.jsx`

**Example violation:**
```typescript
const loading = true;
const admin = user.role === 'admin';
```

**Example fix:**
```typescript
const isLoading = true;
const isAdmin = user.role === 'admin';
```
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/example-naming/SKILL.md
git commit -m "feat: add example naming conventions skill for pipeline testing"
```

---

### Task 10: Update `.gitignore` and Final Verification

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Update `.gitignore` to exclude artifacts from repo**

Add to `.gitignore`:
```
video steps/
.review-artifacts/
```

- [ ] **Step 2: Run full syntax check on all scripts**

Run:
```bash
for script in scripts/lib/common.sh scripts/lib/json-extract.sh scripts/detect-review-mode.sh scripts/cleanup-prior-reviews.sh scripts/run-review-pipeline.sh scripts/post-review.sh; do
  echo "Checking $script..."
  bash -n "$script" && echo "  OK" || echo "  FAIL"
done
```
Expected: All OK

- [ ] **Step 3: Verify directory structure matches spec**

Run:
```bash
find . -not -path './.git/*' -not -path './video*' -type f | sort
```

Expected output should match:
```
./.claude/settings.json
./.claude/skills/example-naming/SKILL.md
./.github/workflows/pr-code-review-validator.yml
./.gitignore
./docs/superpowers/plans/2026-05-12-github-code-review-pipeline.md
./prompts/pipeline-full.md
./prompts/pipeline-incremental-track2.md
./prompts/synthesize.md
./prompts/verification-track1.md
./scripts/cleanup-prior-reviews.sh
./scripts/detect-review-mode.sh
./scripts/lib/common.sh
./scripts/lib/json-extract.sh
./scripts/post-review.sh
./scripts/run-review-pipeline.sh
./specs/github-code-review-integration-spec.md
```

- [ ] **Step 4: Commit .gitignore update**

```bash
git add .gitignore
git commit -m "chore: update .gitignore to exclude review artifacts"
```

---

## Summary

| Task | What it builds | Depends on |
|------|---------------|------------|
| 1 | `scripts/lib/common.sh` — shared constants | — |
| 2 | `scripts/lib/json-extract.sh` — JSON extraction | Task 1 |
| 3 | `scripts/detect-review-mode.sh` — mode detection | Task 1 |
| 4 | `scripts/cleanup-prior-reviews.sh` — review cleanup | Task 1 |
| 5 | All prompt templates | — |
| 6 | `scripts/run-review-pipeline.sh` — orchestrator | Tasks 1, 2, 5 |
| 7 | `scripts/post-review.sh` — posting | Task 1 |
| 8 | `.github/workflows/pr-code-review-validator.yml` | All scripts |
| 9 | Example skill for testing | — |
| 10 | Final verification | All tasks |
