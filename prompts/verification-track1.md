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
