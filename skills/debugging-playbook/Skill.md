---
name: debugging-playbook
description: Find the real cause of a running-system failure — a 500 / opaque error, a wrong or empty result, a flow that fails only in the deployed env. A symptom→source→command decision tree that ties the log sources together (local mirrord run console, AKS kubectl logs, KQL/App Insights, EventStoreDB, SQL schema). Use whenever a service misbehaves at runtime and the cause isn't obvious from the code: the verifier runs it before bouncing a red run, the executor runs it to reproduce a loop-back it can't explain, and anyone can run it for an ad-hoc "why is X failing".
---

# Debugging playbook

Diagnose from **the running system**, not by re-reading the code and guessing. The
first move on any runtime failure is to get the **real error** — the stack trace, the
rejected query, the failed request — from the right log source. A hypothesis formed
before you have the exception is a guess.

## Three laws

1. **Get the real exception before theorising.** A generic `ProblemDetail`
   (`"An unexpected error occurred"`, `title: Internal Server Error`) is *designed* to
   hide the cause — it is not a clue. Go to the logs for the actual stack trace.
2. **Isolate one variable.** Don't change two things between two runs. A hand-built
   token, a tweaked config, a second edit — each can manufacture a *new* failure that
   masquerades as the one you're chasing (a malformed hand-built token can read as
   "Malformed JWT" and send the hunt the wrong way). Reproduce the real
   client's call first; synthesise inputs only when you must, and label them.
3. **Suspect drift between the code and the environment it's running against.** The
   code is new; the deployed DB / config / contract may be old. A read that selects a
   column the devtest table doesn't have yet, a migration not applied, a feature flag
   off, a stale image — all surface as a generic 500 with nothing wrong in the code.

## Symptom → source → command

### 500 / opaque error body
Get the stack trace from wherever your request is actually being handled:

| You are running… | The real log is… | How |
|---|---|---|
| local backend under **mirrord** (stole the pod's traffic) | **your own run console** — the request executes locally | read the IDE/terminal run output; the exception is right there. This is the fast path — check it *first*. |
| the **deployed devtest pod** (no mirrord, or traffic not stolen) | `kubectl logs` on the pod | **`aks`** skill, context `k8s-devtest`: `kubectl logs deploy/<app> --since=10m` (or `-f` while you reproduce). `your-app` / `your-app-projector` are the deployables. |
| a past incident / prod / "it happened an hour ago" | **App Insights / Log Analytics** | **`kql-logs`** skill: `exceptions`/`traces`/`requests` by time window, `operation_Id`, or tenant. Trace one request across services by its correlation id. |

Read the **topmost application frame** (`com.acme…`), not the framework
wrapper. `SQLException` / "Invalid column name" → schema drift (below). Auth/JWT →
check the token is the *real* client's, not a synthesised one (law 2).

### Wrong or empty result (no error)
- **Empty when you expect rows, multi-tenant service:** almost always the tenant
  identity / RLS. The query runs but `SESSION_CONTEXT('tenantId')` is unset or wrong →
  RLS returns zero rows, fails closed. Confirm the request carries the tenant and the
  session context is set. (`service-database-engineer` for RLS depth.)
- **Wrong data shape / stale read model:** for an event-projected read model, the
  projector may not have applied the event yet (eventual consistency), or the
  projection is wrong. Check the projector logs and the read-model row directly.
- **Verify the data actually exists:** query the table directly (**`sql-query`**) for
  the ids you expect, scoped to the tenant, before blaming the code.

### Schema / contract drift
- **"Invalid column name X" / SQL error on a column the code selects:** the deployed
  DB predates the migration that adds it. Compare the code's expectation to the live
  schema: `sql-query` `SELECT ... FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME=…`,
  or introspect via the IDE DB tools. Fix by applying the migration / an `ALTER` to the
  non-prod DB — never by removing the column from the read.
- **Response/consumer mismatch:** the running JSON doesn't match what a caller expects.
  Diff the actual response (curl + token) against the agreed contract
  (`backstage-catalog` for the registered spec), not against memory.

### Fails only in the deployed env (not locally)
Env, not logic: a secret/config/flag/image that differs. Check the pod's env and image
(`aks`: `kubectl describe pod`, `kubectl get deploy -o yaml`), the feature flags
(`configcat`), and that the image is the build you think it is.

## mirrord note
Under `mirrord` **steal**, the deployed frontend's calls hit *your* local process, so
**your run console is the primary log** — read it before reaching for `kubectl`. If a
call clearly isn't reaching you (no log line), traffic isn't being stolen (wrong
target, header filter, or the pod handled it) — then read the pod with `kubectl logs`.
Run-path mechanics live in `verifier.md`; this file is about *reading the failure*.

## Report
State the **evidence** (the exact log line / stack frame / failed query / mismatched
field), then the cause, then the fix. "500 → `SQLException: Invalid column name
'reason'` in `OrderReadRepository` → devtest table predates the migration →
`ALTER TABLE order_line ADD reason …`" beats "probably the reason column". No
evidence line = not diagnosed yet.
