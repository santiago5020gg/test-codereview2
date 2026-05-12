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
