# dev-workflow

A disciplined order-of-work for features and bug fixes in [Claude Code](https://claude.com/claude-code), built as a **thin orchestrator skill + role sub-agents**. The main session orchestrates; each phase is delegated to the role agent that owns it, on a model suited to that phase.

> Org-specific details (internal hostnames, credentials, skill namespaces) are masked with placeholders — `example.com`, `org:`, `${DEVTEST_USER}` / `${DEVTEST_PASS}`, `your-org/…`. Adapt them to your own environment.

## The idea

Cheap execution is only safe behind a smart, independent review. So the work is split by phase, each on its own model, with the expensive model reserved for judgement (planning + final review) and objective checks pushed to `$0`-token CLIs.

| Phase | Agent | Typical model | Owns |
|---|---|---|---|
| Orient · grill · plan · contract | `planner` | strongest | steps 0–2, writes the frozen plan |
| Tests-first · implement | `executor` | mid | steps 3–4 |
| Mechanical slices | `grunt` | cheapest | bulk renames, boilerplate |
| Verify by running it | `verifier` | mid | step 5 — proves it against reality |
| Review guardrails | `reviewer` | strongest, ≠ implementer | step 6 |

## What makes it tick

- **Plan file is the contract.** The planner writes the frozen plan (files, per-file behaviour, test cases with expected answers, contract) to a scratch `plan.md`; every isolated sub-agent reads it. Expected answers come from the plan, **never from the code**.
- **Verifier designs a test matrix first** — equivalence partitioning, boundary value analysis, state transition, decision table — then runs every row and marks PASS/FAIL.
- **Three laws:** work out the expected answer from the requirements, never the code · before calling it done, break the code and watch a test go red · never weaken or disable a test to make it pass.
- **Bounded, anti-gaming fix loops.** Verifier→executor and reviewer→executor share one budget (max 2 per loop, 4 total) via a `## Fix attempts` ledger; a gate must be made green by fixing the code, not by defeating the check.
- **Deterministic-first.** `review-metrics.sh` runs build/tests/lint + an OSV dependency scan + a structural-duplication hint and emits a compact pass/fail table — the model reads the table, not raw tool output.
- **Fast path.** A trivial change touching no trust boundary skips the fan-out — executor only (change + suite + break-it-red).

## Install

Copy into your Claude Code config:

```sh
cp -r skills/dev-workflow ~/.claude/skills/
cp agents/*.md ~/.claude/agents/
chmod +x ~/.claude/skills/dev-workflow/scripts/review-metrics.sh
```

Then adapt the placeholders (`org:`, `example.com`, `${DEVTEST_*}`) and the skill-routing tables to your own skills and environment.

## Requirements (optional, for the full machine)

`ast-grep`, `osv-scanner` for `review-metrics.sh`; `playwright-cli`, `odiff` for the verifier's run/visual paths. Each is a shortcut, not a prerequisite — if a tool is absent the step degrades gracefully.
