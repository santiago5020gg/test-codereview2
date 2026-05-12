# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

An automated PR code review pipeline that validates code changes against skill-defined rules using a multi-agent AI pipeline (Sonnet validates → Opus synthesizes). It runs as a GitHub Actions workflow on PR events and posts bundled reviews to GitHub.

The repo also contains a sample Next.js 16 app (`hello-app/`) used as a test target for the review pipeline.

## Architecture

**Pipeline flow:** PR event → detect mode (FULL/INCREMENTAL) → cleanup old reviews → collect changed files → Sonnet validates against skills → Opus filters false positives and formats review → post bundled review to GitHub.

**Two review modes:**
- **FULL** — validates all changed files from scratch (first push, force-push, `full-review` label)
- **INCREMENTAL** — Track 1 re-verifies prior violations + Track 2 validates only new files

**AI routing:** All AI traffic goes through Portkey gateway → AWS Bedrock (corporate policy). Use short model names (`sonnet`, `opus`) in CLI invocations — never full model IDs.

**Skills** (`.claude/skills/<name>/SKILL.md`) define the review rules Sonnet validates against. New skills can be added without modifying pipeline infrastructure.

## Commands

### Hello App (Next.js)

```bash
cd hello-app
npm run dev      # dev server at localhost:3000
npm run build    # production build
npm run start    # production server
```

No linter or test runner is configured.

### Pipeline Scripts

All scripts require bash and assume CI environment variables. They are not designed to run locally without the full GitHub Actions context (secrets, `gh` CLI auth, artifact download).

```bash
# Review pipeline orchestration
bash scripts/run-review-pipeline.sh   # requires MODE, PR_NUMBER, BASE_SHA, HEAD_SHA env vars

# Mode detection
bash scripts/detect-review-mode.sh    # requires PR_NUMBER, writes to GITHUB_OUTPUT

# Post review to GitHub
bash scripts/post-review.sh           # requires PR_NUMBER, REPO, HEAD_SHA, GH_TOKEN
```

## Key Conventions

- **Code file extensions reviewed:** `.ts`, `.tsx`, `.js`, `.jsx`, `.prisma`, `.sql` (defined in `scripts/lib/common.sh`)
- **Bot reviews are marked** with `<!-- pr-code-review-validator -->` HTML comment for identification/cleanup
- **Violations artifact** persisted at `.review-artifacts/violations.json` between workflow runs
- **Prompt templates** in `prompts/` use `{{PLACEHOLDER}}` syntax, replaced by bash string substitution
- **CLI invocation pattern:** `claude --print --model <model> --output-format json < prompt.txt > output.json`
- **Fail-closed:** If the pipeline errors, it blocks the PR rather than silently approving

## Adding a New Review Skill

Create `.claude/skills/<skill-name>/SKILL.md` with rules in this format:
- Rule name, severity (Critical/Recommended), applicable file types
- Example violation and example fix
- The pipeline reads all skills at runtime — no registration needed

## GitHub Secrets Required

| Secret | Purpose |
|--------|---------|
| `BEDROCK_BASE_URL` | Portkey gateway URL |
| `PORTKEY_API_KEY` | Portkey authentication |
