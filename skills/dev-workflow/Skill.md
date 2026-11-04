---
name: dev-workflow
version: 1.4.2
description: The order of work for any feature or bug fix in Acme code, backend or frontend. The main session ORCHESTRATES; the detail lives in role agents — planner (orient, grill, plan, contract), executor (tests, implement, verify, devtest), reviewer (guardrails + bounded fix loop). Use whenever the user asks to build, add, implement, change, or fix behaviour; not for small tasks (rename, typo, config tweak, one-line fix, docs), which start at step 3.
allowed-tools: Read, Grep, Glob, Task, mcp__developer-portal__list_guidelines, mcp__developer-portal__search_best_practices, mcp__developer-portal__get_examples, mcp__developer-portal__validate_openapi_spec, mcp__developer-portal__search_knowledge_base
when_to_use: Any feature or bug-fix request, in any language or layer. Small mechanical tasks skip steps 1 and 2 and start at step 3.
---

# dev-workflow

You are the **orchestrator**. You sequence the work and delegate each phase to the
role agent that owns it; the detailed instructions live in those agent files, not
here. Say which step you are on. Do not start editing code at step 0. You **route
and relay** — you don't re-reason a delegated agent's work. Keep yourself light: the
plan model runs *inside* the planner, the execute model inside the executor; you are
not that expensive model running the whole way through.

A role agent is a shortcut, not a prerequisite: if an agent file or a named skill is
missing, do the step yourself from the agent's intent and carry on — never stop to
wait for an install, never skip a step because its helper is absent.

## Model split — pick plan / execute / review each time
Three phases, each on its own model. After orienting, before the deep grill, ask in
one line and proceed on defaults if no preference:

> Models — plan / execute / review? (default: Opus 4.8 / Sonnet / Opus 4.8)

Available: `opus` (4.8, highest), `fable`, `sonnet`, `haiku`. Name the model as you
enter each phase. Review runs on a **different** model from the implementer where
possible — a real independent pass. Cheap execution is only safe with a smart review;
never skip it.

## Split assessment — first
Before grilling, judge whether the task breaks into **independent slices**. If it
does, propose the split (parallel subagents for independent slices, sequential for
dependent) and surface it to the user. The planner owns this (and re-checks during
planning) and also flags an **EGM candidate** — a rare, high-stakes, ADR-worthy
design — as a *suggestion*, never auto-invoked.

## Steps — each owned by a role agent
| # | step | owner | delegate |
|---|------|-------|----------|
| 0 | **Orient** (always) | `planner` | in-session; fan out `Explore` if scope is wide |
| 1 | **Grill** (features/bugs) | `planner` | in-session — interactive, never delegated |
| 2 | **Plan + contract + test cases** | `planner` | in-session; plan write-up may go to a `Plan` subagent on the plan model. **Wait for the user's go.** |
| 3 | **Tests before code** | `executor` (`grunt` for mechanical slices) | delegate after approval, on the execute model |
| 4 | **Implement** | `executor` | executor confirms suite + build green, then hands off |
| 5 | **Verify by running it** — real run, mutation, break-it-red | `verifier` | fresh run-it agent; mirrord/devtest, local-CDN override, monolith, API curl; loops failures back to `executor` (max 2) |
| 6 | **Document + review** (guardrails, bounded loop) | `reviewer` | fresh eyes, review model ≠ implementer |

Delegate only independent, well-scoped work; a design still in flux stays in this
session. Say when you delegate, to which agent, and on which model. A step you
skipped (including which of 1–2 a small task skipped) is something to say out loud.

## Fast path — small, safe changes skip the fan-out
A trivial change (rename, typo, config tweak, one-liner, docs) that touches **no
trust boundary** goes straight to the `executor`: it makes the change, runs the
suite, does one **break-it-red**, and stops. No grill, no verifier run-path, no
reviewer — waking all three for a one-liner costs more than the change. Spin up the
full machine (verifier + reviewer and their loops) only for a real feature/bug or
**anything touching a trust boundary**: auth/authz, SQL or a DB migration, money, a
security control, a published API contract, or deleting data. Unsure → treat it as a
real feature.

## Plan file — the contract between phases
Subagents are isolated: each sees only the prompt you hand it, and this session's
context can compact mid-task (losing the plan). So the planner writes the **frozen
plan** — files, per-file behaviour, **test cases with expected answers**, out-of-scope,
contract — to one scratch file at `<scratch>/dev-workflow/plan.md`, and you pass its
**absolute path** to every agent you delegate to. They read it first; **expected
answers come from this file, never from the code**. It is local scratch, never
checked in.

**Fix-attempts ledger (shared).** The verifier→executor and reviewer→executor loops
both append to a `## Fix attempts` list in that same file — one line per bounce
(which loop, what failed, attempt N). The executor reads it on entry so it never
rediscovers a dead end, and the two loops **share one budget: stop at 4 total
executor re-entries** (max 2 per loop), then escalate to the user, converged or not.

## Verification (step 5, in `verifier.md`)
The `verifier` proves the change by **running it**, cheapest real proof first — a
focused integration/component test or a plain local run — and reaching for the heavy
apparatus (mirrord+devtest, React local-CDN override, full monolith run, API curl)
only when the change genuinely needs the deployed env. It drives a **headed** browser
with `playwright-cli`. It first **designs a black-box test matrix** from the plan —
equivalence partitioning, boundary value analysis, state transition, decision table —
marks each case **PASS/FAIL**, and flags which are worth **automating** (vs one-off
manual checks) — uncovered automate-rows go to the executor, any FAIL loops back. For UI it checks **visual
fidelity to the Figma frame** (`figma` MCP screenshot + `odiff` image diff) and that
**design tokens** are used (not hardcoded); for APIs it checks the **guidelines**
(`developer-portal`). It does diff-scoped mutation testing + a mandatory
**break-it-red**, and hands failures back to the `executor` (max 2). Three laws it
enforces, true for the whole workflow:
- **Work out the expected answer from the requirements, never from the code.**
- **Before calling it done, break the code and watch a test go red.**
- **Never weaken, skip, or disable a test to make it pass** — fix the code.

## Review guardrails (step 6, in `reviewer.md`)
Reviewer runs `scripts/review-metrics.sh` (deterministic: build/tests/lint/osv-scanner
+ structural hint) then the advisory skills, and classifies findings:
- **Hard gates** (tests, build, lint, HIGH/CRITICAL CVE; plus `sonar-scanner`/`snyk`
  once per review) **drive a bounded fix loop** back to the executor — **max 2
  iterations**, and a fix must pass the gate honestly (**no** disabling checks,
  weakening tests, or raising thresholds).
- **Advisory** (`ponytail-review`, structural duplication hint) and **decisions for
  the user** (ADR-worthy choices) never loop — they go to the user.

## Parallelism
Parallelise **orientation** (Explore agents), **review dimensions**
(`/code-review` fans out; security + over-engineering alongside), and **fact-finding
during the grill**. Do NOT parallelise implementation of one feature across slices
unless the split made them genuinely independent — shared files corrupt.

## Deterministic-first (cost)
Push every *objective* check to a CLI (`review-metrics.sh`, tests, lint,
osv-scanner) — $0 model tokens. Use subagents to keep this session's context small,
not to multiply reasoning passes. Reserve the expensive model for planning judgement
and the final review. Cheap models (`executor` Sonnet, `grunt` Haiku) do the labour.

## Route to the owning skill (index — the source of truth)
This table is canonical. Each agent file lists only the few rows central to its
phase and points back here for the rest — so the full mapping is maintained **once,
here**, not copied in four places. Use the installed skill over general knowledge,
and name the one you used. A `org:` skill missing means the org plugin isn't
enabled (`claude plugin enable org@org`).

| touching | skill |
|---|---|
| Java, Spring, a satellite service | `org:backend-engineer` |
| an HTTP/async API or OpenAPI spec (how to design) | **`developer-portal` MCP** (`search_best_practices`, `get_examples`, `validate_openapi_spec`) |
| an existing/registered API spec from the catalog | **`backstage-catalog`** MCP (Software Catalog) |
| React, CSS, tokens, dark mode, a11y | `frontend-design`, `org:accessibility` |
| reuse a design-system component / verify its props | **`design-system`** Storybook MCP (MUI as fallback, never hand-roll) |
| implement or verify against a Figma design | **`figma`** MCP (`/figma-design-to-code`); verifier diffs the frame with `odiff` |
| a new micro-frontend | `create-react-micro-app` |
| Monolith schema / the shared customer DB / init.sql | `monolith-database-engineer` |
| service schema / RLS / Flyway / storage | `service-database-engineer` |
| feature toggles | `configcat` |
| SQL data | `sql-query` |
| Kubernetes / AKS / a deployed env | `aks` |
| Azure resources | `azure-context` |
| logs and telemetry | `kql-logs` |
| ticket / branch / PR | `jira-workflow`, `pr-workflow` |
| merge conflict mid-task | `resolving-merge-conflicts` |

## Rules
- `grilling`, `tdd`, `resolving-merge-conflicts` come from
  [mattpocock/skills](https://github.com/mattpocock/skills) and aren't bundled here.
  `grill-me`, `handoff`, `wayfinder` are user-typed only — suggest, don't call them.
  Install: `npx skills@latest add mattpocock/skills -g -a <agent>`.
- Grilling and planning are conversations — keep them in chat, not files, unless the
  repo has a place for specs (check its `AGENTS.md`/`CLAUDE.md`).
- The repo you are in wins over this file and over org guidance (AGENTS.md, "Order of
  authority"); flag a divergence once, don't silently fix it.
