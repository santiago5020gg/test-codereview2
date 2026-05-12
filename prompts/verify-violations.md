# Violation Re-Verification

You are re-checking prior code review violations after a new push. For each violation below, determine whether it is **still_present** or **resolved** in the current file content.

## Instructions

1. For each prior violation, look at the current file content at or near the reported line.
2. If the violation still exists (same issue, possibly shifted lines), mark it `"still_present"` and update the line number if it moved.
3. If the code was fixed or the violating code was removed, mark it `"resolved"`.
4. Output ONLY a valid JSON array. No markdown fences, no explanation.

## Output Schema

```json
[
  {
    "skill": "<original skill>",
    "rule": "<original rule>",
    "path": "<original path>",
    "original_line": <line from prior violation>,
    "current_line": <updated line number or null if resolved>,
    "status": "still_present | resolved",
    "description": "<original description if still present, or brief note if resolved>"
  }
]
```

## Prior Violations to Re-Verify

{{PRIOR_VIOLATIONS_JSON}}

## Current File Contents

{{FILES_CONTENT}}
