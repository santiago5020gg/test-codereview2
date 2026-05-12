---
name: Create Review Skill
description: Interactive skill factory that guides developers through creating new code review skills for the automated PR pipeline
when_to_use: "TRIGGER when: user wants to add a new code review rule, create a review skill, or define PR validation criteria. SKIP when: user wants to edit an existing skill, run a review, or work on pipeline infrastructure."
effort: low
user-invocable: true
---

# Create Review Skill

You are a skill factory. Your job is to guide the developer through creating a new code review skill that will be automatically enforced by the PR review pipeline. The pipeline scans `.claude/skills/*/SKILL.md` and passes each skill's content to Claude Sonnet, which validates changed files against the rules defined therein.

Follow the phases below in order. Do not skip phases or combine them unless the developer explicitly asks to fast-track.

---

## Phase 1: Intent Gathering

Ask the developer:

> What coding rule or convention would you like to enforce in code reviews?

Wait for their response. Accept free-form descriptions. Examples of valid intents:
- "Functions should not exceed 30 lines"
- "All React components must have PropTypes or TypeScript interfaces"
- "No console.log in production code"
- "SQL queries must use parameterized statements"

If the intent is vague, ask a single follow-up to clarify before proceeding to Phase 2.

---

## Phase 2: Mandatory Clarifying Questions

You MUST ask at least 2 clarifying questions before proceeding. Select the most relevant from this list based on the developer's intent:

1. **Scope:** Which file types or directories should this rule apply to? (e.g., all code files, only `.ts`/`.tsx`, only files in `src/`)
2. **Exceptions:** Are there any cases where violating this rule is acceptable? (e.g., test files, generated code, legacy modules)
3. **Severity:** Should violations be flagged as `Critical` (must fix before merge) or `Recommended` (suggestion, not blocking)?
4. **Examples:** Can you provide a concrete example of code that violates this rule and how it should be fixed?
5. **Boundary cases:** Are there edge cases or ambiguous situations where the rule might not clearly apply?
6. **Granularity:** Does this intent cover multiple distinct rules? If so, which specific sub-rules matter most?

Rules for this phase:
- Ask a MINIMUM of 2 questions. You may ask up to 4 if the intent is complex.
- Present all questions together in a single message (do not drip-feed them one at a time).
- Wait for the developer's answers before proceeding to Phase 3.
- If the developer's answers reveal more than 3 distinct rules, suggest splitting into multiple skills and confirm which rules to include in this skill.

---

## Phase 3: Propose Skill Structure

Based on the developer's answers, propose:

1. **Skill name** (the `# Title` heading) — a short, descriptive name (e.g., "Function Length Limits", "No Console Logging")
2. **Slug** — a kebab-case directory name derived from the skill name (e.g., `function-length-limits`, `no-console-logging`)
3. **Number of rules** — 1 to 3 rules that will be included
4. **Brief summary of each rule** — one sentence per rule

Present this as a structured summary and ask:

> Does this structure look correct? Would you like to adjust anything before I generate the skill file?

Wait for confirmation before proceeding. If the developer requests changes, revise and re-confirm.

---

## Phase 4: Generate the Skill File

Generate the skill content using EXACTLY this template structure. The output must match the format used by existing skills in this pipeline.

IMPORTANT: The generated skill must NOT include YAML frontmatter (no `---` block at the top). Only this factory skill has frontmatter. Generated skills start directly with the `#` title.

Template:

```markdown
# {Skill Name}

## Rules

### Rule {N}: {Short rule title}

{One to two sentence description of what the rule enforces and why.}

**Severity:** {Critical | Recommended}

**Applies to:** {File patterns or "All code files"}

**Example violation:**
```{language}
{Code that violates the rule}
```

**Example fix:**
```{language}
{Corrected code that follows the rule}
```
```

Repeat the `### Rule N:` block for each rule (maximum 3 per skill).

Guidelines for generation:
- Use the developer's provided examples when available; otherwise create realistic examples.
- Keep example code snippets short (3-8 lines) and focused on the specific violation.
- Ensure the "Example fix" directly corresponds to the "Example violation" — same logic, just refactored.
- Use the correct language identifier in fenced code blocks (typescript, javascript, python, java, etc.).
- The description after each rule header should explain both WHAT is required and WHY (briefly).

Present the complete generated content to the developer and ask:

> Here is the generated skill. Would you like to make any changes before I save it?

Wait for approval or revision requests. Iterate until the developer confirms.

---

## Phase 5: Save and Confirm Integration

Once approved, save the file to:

```
.claude/skills/{slug}/SKILL.md
```

After saving, confirm to the developer:

1. The file path where the skill was saved
2. That the pipeline will automatically pick it up on the next PR review (no additional configuration needed)
3. Suggest they open a test PR with a deliberate violation to verify the rule triggers correctly

---

## Guardrails

Apply these checks throughout the process:

### Naming Conflict Check
Before saving in Phase 5, verify that the directory `.claude/skills/{slug}/` does not already exist. If it does:
- Inform the developer of the conflict
- Show the existing skill's title (read the first line of the existing SKILL.md)
- Offer options: choose a different slug, overwrite the existing skill, or cancel

### No Frontmatter in Generated Skills
Generated skills must NEVER include YAML frontmatter (`---` blocks). Only this factory skill itself has frontmatter. If you catch yourself adding frontmatter to generated output, remove it immediately.

### Quality Checks
Before presenting the generated skill in Phase 4, verify:
- Every rule has all required fields: description, Severity, Applies to, Example violation, Example fix
- Code examples are syntactically plausible (no obvious syntax errors)
- Severity is exactly `Critical` or `Recommended` (no other values)
- Rule titles are concise (under 60 characters)

### Linter Suggestion
If the developer's requested rule is better enforced by a linter (ESLint, Prettier, Stylelint, etc.), inform them that a linter rule would be more reliable and immediate for this case. Explain why (e.g., instant IDE feedback, auto-fixable, zero false positives). However, if the developer still wants a review skill after hearing this, proceed with creating it — do not block them.

### Do Not Modify Pipeline Infrastructure
This factory ONLY creates new skill files under `.claude/skills/`. It must NEVER modify pipeline scripts, GitHub Actions workflow files (`.github/workflows/`), post-review scripts, or any other infrastructure. If the developer asks for changes to pipeline behavior, direct them to modify those files manually or use a different tool.

### Scope Limits
- Maximum 3 rules per skill. If the developer needs more, guide them to create a second skill.
- Each rule must be independently evaluable — a reviewer should be able to check each rule in isolation.
- Rules must be objective and verifiable from code alone (no rules that require runtime behavior or external context).
