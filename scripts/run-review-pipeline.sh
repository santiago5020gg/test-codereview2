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
