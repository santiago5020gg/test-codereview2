# Code Review Skill Factory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code skill (`.claude/skills/create-review-skill/SKILL.md`) that interactively guides developers through creating new code review skills for the PR pipeline.

**Architecture:** A single SKILL.md file that acts as an interactive prompt template. When invoked via `/create-review-skill`, Claude follows the skill's instructions to brainstorm, refine, and generate a new review skill file placed directly into `.claude/skills/<name>/SKILL.md`. No scripts or infrastructure — just a well-structured skill document that leverages Claude's conversational abilities.

**Tech Stack:** Claude Code skills (Markdown with YAML frontmatter), `.claude/skills/` directory convention

---

## File Structure

| File | Responsibility |
|------|---------------|
| `.claude/skills/create-review-skill/SKILL.md` | The factory skill — contains all instructions for interactive skill creation |

This is a single-file deliverable. The factory produces new files at runtime (`.claude/skills/<generated-name>/SKILL.md`), but the factory itself is one file.

---

### Task 1: Create the Factory Skill File with Frontmatter

**Files:**
- Create: `.claude/skills/create-review-skill/SKILL.md`

- [ ] **Step 1: Create the skill directory and file with frontmatter**

```markdown
---
name: create-review-skill
description: Interactively creates new code review skills for the PR pipeline
when_to_use: "TRIGGER when: user wants to add a new code review rule, create a review skill, or define PR validation criteria. SKIP when: user wants to edit an existing skill, run a review, or work on pipeline infrastructure."
effort: medium
user-invocable: true
---
```

- [ ] **Step 2: Verify the file exists and frontmatter is valid YAML**

Run: `head -7 .claude/skills/create-review-skill/SKILL.md`
Expected: The frontmatter block with all fields present

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/create-review-skill/SKILL.md
git commit -m "feat: scaffold create-review-skill factory skill"
```

---

### Task 2: Write the Introduction and Phase 1 (Intent Gathering)

**Files:**
- Modify: `.claude/skills/create-review-skill/SKILL.md`

- [ ] **Step 1: Add the skill title and introduction section**

Append after the frontmatter closing `---`:

```markdown
# Create Review Skill

You are guiding a developer through creating a new code review skill for the automated PR pipeline. The skill you produce will be read by Claude (Sonnet) during code review and used to detect violations in changed files.

## Your Responsibilities

1. **Gather intent** — understand what the developer wants to enforce
2. **Ask clarifying questions** — minimum 2 questions to refine the scope
3. **Propose the skill structure** — present the plan for confirmation
4. **Generate the skill file** — write a complete, valid SKILL.md
5. **Save it** — place it in `.claude/skills/<name>/SKILL.md`

## Phase 1: Gather Intent

Ask the developer:

> What coding rule or pattern would you like to enforce in code reviews?

Wait for their response. Do NOT proceed until they provide a description of what they want to check for.

After they respond, move to Phase 2.
```

- [ ] **Step 2: Verify the content reads correctly**

Run: `cat .claude/skills/create-review-skill/SKILL.md`
Expected: Frontmatter + title + introduction + Phase 1 instructions

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/create-review-skill/SKILL.md
git commit -m "feat: add intent gathering phase to skill factory"
```

---

### Task 3: Write Phase 2 (Mandatory Clarifying Questions)

**Files:**
- Modify: `.claude/skills/create-review-skill/SKILL.md`

- [ ] **Step 1: Add Phase 2 section**

Append to the file:

```markdown
## Phase 2: Clarifying Questions (MANDATORY)

You MUST ask at least 2 clarifying questions before generating the skill. Initial descriptions are always incomplete — assumptions lead to overly broad or narrow rules.

Ask questions from this list (pick the most relevant ones):

1. **File scope** — "Which file types should this rule apply to? (e.g., `.ts/.tsx` only, all code files, only test files)"
2. **Violation boundary** — "Can you give me a specific example of code that SHOULD trigger this rule?"
3. **Correct pattern** — "What does the correct/fixed version look like?"
4. **Exceptions** — "Are there cases where this pattern is acceptable? (e.g., in tests, in generated code, in specific directories)"
5. **Severity** — "Should violations block the PR (`Critical`) or just warn (`Recommended`)?"
6. **Existing conventions** — "Is this rule documented anywhere else (style guide, linting config)? If so, why add it as a review skill too?"

### Rules for this phase:
- Ask 2-4 questions at once (not one at a time — that's tedious)
- Choose questions based on what's ambiguous in their description
- If the developer's initial description already covers scope and examples clearly, you may ask fewer questions — but never zero
- Wait for answers before proceeding to Phase 3
```

- [ ] **Step 2: Verify Phase 2 reads correctly**

Run: `grep -c "Phase 2" .claude/skills/create-review-skill/SKILL.md`
Expected: 1

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/create-review-skill/SKILL.md
git commit -m "feat: add mandatory clarifying questions phase"
```

---

### Task 4: Write Phase 3 (Skill Proposal and Confirmation)

**Files:**
- Modify: `.claude/skills/create-review-skill/SKILL.md`

- [ ] **Step 1: Add Phase 3 section**

Append to the file:

```markdown
## Phase 3: Propose Skill Structure

Based on the developer's answers, present a structured proposal:

```
📋 Proposed Skill: <display-name>

Slug: <kebab-case-name>
Scope: <file patterns>
Rules: <number of rules>

Rule 1: <rule-name>
  Severity: <Critical|Recommended>
  Checks for: <one line>

Rule 2: <rule-name> (if applicable)
  Severity: <Critical|Recommended>
  Checks for: <one line>

Exceptions: <list or "none">
```

Then ask:

> Does this look right? Want to adjust anything before I generate the skill file?

### Rules for this phase:
- Keep it to 1-3 rules per skill. If the developer describes more, suggest splitting into multiple skills.
- The slug must be valid as a directory name (lowercase, hyphens, no spaces)
- Wait for explicit confirmation ("yes", "looks good", "go ahead", etc.) before proceeding to Phase 4
- If they want changes, revise the proposal and ask again
```

- [ ] **Step 2: Verify Phase 3 reads correctly**

Run: `grep -c "Phase 3" .claude/skills/create-review-skill/SKILL.md`
Expected: 1

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/create-review-skill/SKILL.md
git commit -m "feat: add skill proposal confirmation phase"
```

---

### Task 5: Write Phase 4 (Skill Generation with Template)

**Files:**
- Modify: `.claude/skills/create-review-skill/SKILL.md`

- [ ] **Step 1: Add Phase 4 section**

Append to the file:

````markdown
## Phase 4: Generate the Skill File

Generate the skill file following this exact template. Every section is required.

### Output path: `.claude/skills/<slug>/SKILL.md`

### Template:

```markdown
# <Display Name>

## Scope
Applies to files matching: <glob patterns, e.g., `*.ts`, `*.tsx`, `*.js`, `*.jsx`>

## Rules

### Rule N: <Rule Name>

**Severity:** Critical | Recommended

**Applies to:** <file patterns or "All code files">

**Description:** <What this rule checks — one paragraph max>

**Violation:** <What specifically triggers a finding — be precise>

**Correct:** <What the code should look like instead>

**Example violation:**
\```<language>
// code that violates this rule
\```

**Example fix:**
\```<language>
// corrected code
\```
```

### Generation rules:
- Use the EXACT structure above — the pipeline parser depends on `### Rule N:` headers and `**Severity:**` fields
- Every rule MUST include both an example violation AND an example fix with realistic code
- Examples should be 2-6 lines — enough to show the pattern, short enough to scan quickly
- The `Scope` section defines which files the pipeline should check this skill against
- Do NOT add frontmatter to the generated skill — only the factory skill itself has frontmatter
- The `Applies to` field within each rule allows per-rule scoping (can differ from the top-level Scope)
````

- [ ] **Step 2: Verify Phase 4 reads correctly**

Run: `grep -c "Phase 4" .claude/skills/create-review-skill/SKILL.md`
Expected: 1

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/create-review-skill/SKILL.md
git commit -m "feat: add skill generation template and rules"
```

---

### Task 6: Write Phase 5 (Save and Integration Confirmation)

**Files:**
- Modify: `.claude/skills/create-review-skill/SKILL.md`

- [ ] **Step 1: Add Phase 5 section**

Append to the file:

````markdown
## Phase 5: Save and Confirm

1. Write the generated skill to `.claude/skills/<slug>/SKILL.md`
2. Confirm to the developer:

```
✅ Skill created: .claude/skills/<slug>/SKILL.md

The skill is now active. On the next PR that changes files matching
<scope>, the pipeline will check for violations of:
  - Rule 1: <name>
  - Rule 2: <name> (if applicable)

To test it locally: make a PR with a deliberate violation and check
that the review bot flags it.

To modify: edit .claude/skills/<slug>/SKILL.md directly.
To remove: delete the .claude/skills/<slug>/ directory.
```

3. Ask if they want to commit the new skill:

> Want me to commit this skill file so it's active on the next push?
````

- [ ] **Step 2: Verify Phase 5 reads correctly**

Run: `grep -c "Phase 5" .claude/skills/create-review-skill/SKILL.md`
Expected: 1

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/create-review-skill/SKILL.md
git commit -m "feat: add save and integration confirmation phase"
```

---

### Task 7: Add Quality Guardrails and Edge Case Handling

**Files:**
- Modify: `.claude/skills/create-review-skill/SKILL.md`

- [ ] **Step 1: Add guardrails section**

Append to the file:

```markdown
## Guardrails

### Naming conflicts
Before writing the file, check if `.claude/skills/<slug>/` already exists. If it does:
- Tell the developer the name is taken
- Show them what the existing skill does (read the first few lines)
- Suggest an alternative slug or ask if they want to pick a different name

### Rule quality checks
Before saving, verify your generated skill:
- [ ] Every rule has both a violation example AND a fix example
- [ ] Examples use realistic code (not `foo`/`bar` placeholder names)
- [ ] The severity level matches the developer's stated intent
- [ ] The scope doesn't accidentally include files that shouldn't be checked (e.g., config files, generated code)
- [ ] Rule descriptions are specific enough that another AI could consistently identify violations

### Scope of this factory
- Do NOT modify the pipeline scripts, workflow files, or other infrastructure
- Do NOT edit existing skills — only create new ones
- Do NOT add skills that duplicate what linters already catch (ESLint, Prettier, etc.) unless the developer explicitly wants defense-in-depth
- If the developer's request is better served by a linting rule, tell them so — but still create the skill if they insist
```

- [ ] **Step 2: Verify guardrails section exists**

Run: `grep -c "Guardrails" .claude/skills/create-review-skill/SKILL.md`
Expected: 1

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/create-review-skill/SKILL.md
git commit -m "feat: add quality guardrails and edge case handling"
```

---

### Task 8: Register the Skill for User Invocation

**Files:**
- Modify: `.claude/settings.json` (only if needed for skill registration)

- [ ] **Step 1: Verify skill is discoverable**

Run: `ls .claude/skills/create-review-skill/SKILL.md`
Expected: File exists

Claude Code auto-discovers skills in `.claude/skills/*/SKILL.md` — no settings.json modification is needed. The skill is invocable via `/create-review-skill` because `user-invocable: true` is set in the frontmatter.

- [ ] **Step 2: Test invocation discovery**

Run: `cat .claude/skills/create-review-skill/SKILL.md | head -6`
Expected: Frontmatter with `user-invocable: true`

- [ ] **Step 3: Final commit with all files**

```bash
git add -A
git status
git commit -m "feat: complete create-review-skill factory skill"
```

---

### Task 9: End-to-End Validation

**Files:**
- Verify: `.claude/skills/create-review-skill/SKILL.md`
- Reference: `.claude/skills/example-naming/SKILL.md` (compare format)

- [ ] **Step 1: Validate the factory skill structure**

Run: `wc -l .claude/skills/create-review-skill/SKILL.md`
Expected: Approximately 150-200 lines (full skill with all phases)

- [ ] **Step 2: Verify the generated template matches existing skill format**

Compare the template in Phase 4 against the existing example skill:

Run: `head -20 .claude/skills/example-naming/SKILL.md`

Confirm that the template's output structure (Rule headers, Severity fields, Example violation/fix blocks) matches the format that `scripts/run-review-pipeline.sh` reads via the `collect_skills()` function.

Key compatibility checks:
- Skills are read from `.claude/skills/*/SKILL.md` (line 71-79 of `run-review-pipeline.sh`)
- The pipeline reads the entire file content — no specific field parsing beyond what Sonnet interprets
- The `### Skill: <name>` header is added by the pipeline, not the skill file itself

- [ ] **Step 3: Verify no pipeline scripts were modified**

Run: `git diff --name-only scripts/ .github/`
Expected: No output (no changes to pipeline infrastructure)

- [ ] **Step 4: Final integration check**

Run: `ls .claude/skills/*/SKILL.md`
Expected: Two skills listed:
- `.claude/skills/create-review-skill/SKILL.md`
- `.claude/skills/example-naming/SKILL.md`

---

## Summary

| Task | What it produces | Time estimate |
|------|-----------------|---------------|
| 1 | Skill file scaffolded with frontmatter | 2 min |
| 2 | Introduction + Phase 1 (intent gathering) | 3 min |
| 3 | Phase 2 (clarifying questions) | 3 min |
| 4 | Phase 3 (proposal + confirmation) | 3 min |
| 5 | Phase 4 (generation template) | 5 min |
| 6 | Phase 5 (save + integration) | 3 min |
| 7 | Quality guardrails | 3 min |
| 8 | Registration verification | 2 min |
| 9 | End-to-end validation | 3 min |

**Total: ~27 minutes**

The factory produces skills that are immediately compatible with the existing `run-review-pipeline.sh` because:
1. Skills are placed in `.claude/skills/<name>/SKILL.md` (the exact path the pipeline scans)
2. The generated format uses `### Rule N:` headers and structured fields that Sonnet can interpret
3. No pipeline code changes are required — the pipeline already reads all skills dynamically
