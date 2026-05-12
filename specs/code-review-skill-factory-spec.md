# Code Review Skill Factory — Design Spec

> **Purpose:** This spec is the blueprint for building a Claude Code skill that follows the [Agent Skills](https://agentskills.io) open standard (ref: https://code.claude.com/docs/en/skills). Give this document to Claude and it should produce: a skill file (`.claude/skills/create-review-skill/SKILL.md`) that, when invoked via `/create-review-skill`, interactively guides any developer through creating new code review skills for the pipeline.
>
> **Prerequisite:** The code review pipeline from `github-code-review-integration-spec.md` must already be built and running. This skill produces review rules that plug into that pipeline.
>
> **Related:** Build the pipeline first using `github-code-review-integration-spec.md`, then use this spec to create the skill factory.

## Problem

Creating review skills manually is error-prone and requires intimate knowledge of the pipeline's internal structure (JSON schemas, sub-agent configuration). This makes it inaccessible to most developers on the team who want to add review rules but don't maintain the pipeline infrastructure.

## Goals

1. **Democratized skill creation** — Any developer on the team can create a new review skill without understanding pipeline internals.
2. **Guided refinement** — Initial rule descriptions are always incomplete. The factory must ask clarifying questions **one at a time** before generating a skill (mandatory brainstorming). One question per message, prefer multiple-choice format, wait for the user's answer before proceeding.
3. **Correct by construction** — Generated skills must conform to the exact schema the pipeline expects. No manual JSON wiring.
4. **Automatic integration** — Once a skill is created, it's immediately active on the next PR. No separate deployment step.

## Non-Goals

- **Does not execute reviews** — The factory creates rules; the pipeline enforces them. Separate concerns.
- **Does not modify existing skills** — Scope is limited to creating new skills. Editing existing ones is a different workflow.
- **Does not manage deployment/CI** — No workflow modifications, no secret management, no infrastructure changes.
- **Does not validate skill quality over time** — No metrics on false-positive rates per skill. That's a future concern.

## Architecture

### Factory Flow

```
User describes intent (natural language)
  │
  ├─ Clarifying questions (minimum 2, one at a time, multiple-choice)
  │     What file types? What counts as violation?
  │     What severity? What exceptions?
  │
  ├─ Propose skill structure
  │     Name, slug, rules, examples → user confirms
  │
  ├─ Generate SKILL.md (Agent Skills open standard)
  │     YAML frontmatter (name, description, when_to_use, paths)
  │     + rules + examples + scope
  │
  └─ Integration
        Skill file placed in .claude/skills/{slug}/ → active on next PR
```


## Interfaces

### 1. Input: User Intent

Free-text description of what the review should check for. Examples:
- "I want to ensure all API calls use error boundaries"
- "No console.log in production code"
- "Database queries must use parameterized queries"

### 2. Output: Skill File (`.claude/skills/<name>/SKILL.md`)

Generated skills follow the [Agent Skills](https://agentskills.io) open standard used by Claude Code (ref: https://code.claude.com/docs/en/skills).

#### Frontmatter (YAML)

All fields below are required unless marked otherwise:

| Field | Required | Constraints | Description |
|-------|----------|-------------|-------------|
| `name` | Yes | Lowercase letters, numbers, hyphens only. Max 64 chars. | Kebab-case slug matching the directory name. |
| `description` | Yes | Key use case first. Combined with `when_to_use`, truncated at 1,536 chars in skill listing. | What the skill does. |
| `when_to_use` | Yes | Include both TRIGGER and SKIP conditions. | Tells Claude when to auto-invoke the skill. |
| `user-invocable` | Yes | Must be `false` for review skills. | Review skills are background knowledge, not user commands. |
| `paths` | Recommended | YAML list of glob patterns. | Limits activation to files matching the patterns. |

```yaml
---
name: <kebab-case-name>
description: "Code review skill that enforces <brief rule summary>"
when_to_use: "TRIGGER when: reviewing files matching <scope>. SKIP when: file is outside scope or in an excluded path."
user-invocable: false
paths:
  - "<glob pattern>"
---
```

#### Body structure (all sections required)

```markdown
# <Skill Display Name>

## Rules

### Rule 1: <Name>

<One to two sentence description of what the rule enforces and why.>

**Severity:** Critical | Recommended

**Applies to:** <File patterns or "All code files">

**Example violation:**
\```<language>
// bad code
\```

**Example fix:**
\```<language>
// good code
\```
```

#### Constraints

- Each rule must include: description, Severity, Applies to, Example violation, Example fix.
- Maximum 3 rules per skill. If more are needed, create additional skills.
- Total skill content must stay under 500 lines (move lengthy reference to supporting files in the skill directory).
- State what to do, not how or why — skills stay in context across turns (recurring token cost).
- `name` in frontmatter must match the directory slug exactly.

### 3. Relationship to Pipeline

```
┌─────────────────────────────┐
│     Skill Factory           │  ← Creates skills
│  (interactive, one-time)    │
└──────────────┬──────────────┘
               │ produces
               ▼
┌─────────────────────────────┐
│   .claude/skills/<name>/    │  ← Skill files (static)
│         SKILL.md            │
└──────────────┬──────────────┘
               │ read by
               ▼
┌─────────────────────────────┐
│   Code Review Pipeline      │  ← Runs on every PR
│  (automated, continuous)    │
└─────────────────────────────┘
```

