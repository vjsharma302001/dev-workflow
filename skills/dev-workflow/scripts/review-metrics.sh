#!/usr/bin/env bash
# review-metrics.sh — deterministic review gates for dev-workflow step 6.
#
#   stdout: a compact `| check | status |` table (and nothing else).
#   stderr: all diagnostics / tool output.
#   exit  : non-zero if any HARD gate that could run FAILED. Advisory never fails.
#
# HARD gates: build, tests, lint, dependency CVEs (osv-scanner).
# Advisory:   structural duplication hint (ast-grep).
#
# Build/test/lint commands are repo-specific, so they are NOT guessed — pass them as
# env vars (calibration knobs). Unset => that gate is SKIPped, and the reviewer runs
# the repo's own command (known from orientation) instead of this script hanging on a
# wrong guess:
#   REVIEW_BUILD_CMD   e.g. "./gradlew build -x test"   or  "npm run -s build"
#   REVIEW_TEST_CMD    e.g. "./gradlew test"            or  "npm test -- --run"
#   REVIEW_LINT_CMD    e.g. "npx --no-install eslint ." (auto-detected for frontend if unset)
#
# ponytail: osv-scanner result is exit-code based (coarse). If you need a HIGH/CRITICAL-only
#           gate, parse `--format json` and filter severity — upgrade when it matters.

set -uo pipefail
root="$(pwd)"
fail=0
rows=()

row()  { rows+=("| $1 | $2 |"); }
skip() { row "$1" "SKIP — $2"; }
hard() { # label, shell-command
  local label="$1" cmd="$2"
  echo ">> [$label] $cmd" >&2
  if bash -c "$cmd" >&2 2>&1; then row "$label" "PASS"; else row "$label" "FAIL"; fail=1; fi
}

# --- build -------------------------------------------------------------------
if   [ -n "${REVIEW_BUILD_CMD:-}" ]; then hard "build" "$REVIEW_BUILD_CMD"
elif [ -x "$root/gradlew" ];         then skip "build" "set REVIEW_BUILD_CMD (e.g. ./gradlew build -x test)"
elif [ -f "$root/package.json" ];    then skip "build" "set REVIEW_BUILD_CMD (e.g. npm run -s build)"
else skip "build" "no build detected"; fi

# --- tests -------------------------------------------------------------------
if   [ -n "${REVIEW_TEST_CMD:-}" ]; then hard "tests" "$REVIEW_TEST_CMD"
elif [ -x "$root/gradlew" ];        then skip "tests" "set REVIEW_TEST_CMD (e.g. ./gradlew test)"
elif [ -f "$root/package.json" ];   then skip "tests" "set REVIEW_TEST_CMD (e.g. npm test -- --run)"
else skip "tests" "no test runner detected"; fi

# --- lint --------------------------------------------------------------------
# A gate must only run when it CAN run: use the repo-local eslint (never npx-install),
# and SKIP (not FAIL) when node_modules is absent — a tooling gap isn't a lint failure.
have_glob() { compgen -G "$1" >/dev/null 2>&1; }
if [ -n "${REVIEW_LINT_CMD:-}" ]; then
  hard "lint" "$REVIEW_LINT_CMD"
elif [ -f "$root/package.json" ] && { have_glob "$root/.eslintrc*" || have_glob "$root/eslint.config.*"; }; then
  if [ -x "$root/node_modules/.bin/eslint" ]; then
    if grep -q '"lint"' "$root/package.json"; then
      pm=npm; [ -f "$root/yarn.lock" ] && pm=yarn; [ -f "$root/pnpm-lock.yaml" ] && pm=pnpm
      hard "lint" "$pm run lint"
    else
      hard "lint" "$root/node_modules/.bin/eslint ."
    fi
  else
    skip "lint" "eslint config present but node_modules missing — install deps, or set REVIEW_LINT_CMD"
  fi
else
  skip "lint" "no lint command (set REVIEW_LINT_CMD; JVM has no local linter)"
fi

# --- dependency CVEs (HARD on HIGH/CRITICAL only) ----------------------------
# ponytail: gate = max CVSS >= 7.0 (HIGH/CRITICAL). Lower vulns WARN, so a
# pre-existing moderate doesn't spuriously trigger the executor fix loop.
if command -v osv-scanner >/dev/null 2>&1; then
  echo ">> [deps-osv] osv-scanner scan --recursive --format json ." >&2
  j="$(mktemp)"
  osv-scanner scan --recursive --format json "$root" >"$j" 2>/dev/null || true
  sev="$(python3 - "$j" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("ERR"); sys.exit()
mx = 0.0
for r in d.get("results", []):
    for p in r.get("packages", []):
        for g in p.get("groups", []):
            try:
                mx = max(mx, float(g.get("max_severity", "") or 0))
            except ValueError:
                pass
print(f"{mx:.1f}")
PY
)"
  rm -f "$j"
  if   [ "$sev" = "ERR" ] || [ -z "$sev" ];      then skip "deps-osv" "osv-scanner output unparseable"
  elif awk "BEGIN{exit !($sev>=7.0)}";           then row "deps-osv" "FAIL (max CVSS $sev)"; fail=1
  elif awk "BEGIN{exit !($sev>0)}";              then row "deps-osv" "WARN (max CVSS $sev, <HIGH — advisory)"
  else row "deps-osv" "PASS"; fi
else
  skip "deps-osv" "osv-scanner not installed"
fi

# --- structural duplication hint (ADVISORY, never fails) ---------------------
SG="$(command -v ast-grep || command -v sg || true)"
if [ -n "$SG" ]; then
  tmp="$(mktemp)"
  # name a static method, per language; $NAME is captured as the metavariable NAME.
  "$SG" run -l ts   -p 'static $NAME($$$) { $$$ }'    --json=stream "$root" 2>/dev/null >>"$tmp" || true
  "$SG" run -l tsx  -p 'static $NAME($$$) { $$$ }'    --json=stream "$root" 2>/dev/null >>"$tmp" || true
  "$SG" run -l java -p 'static $T $NAME($$$) { $$$ }' --json=stream "$root" 2>/dev/null >>"$tmp" || true
  hint="$(python3 - "$tmp" <<'PY'
import json, sys, collections
IGNORE = {"main", "toString", "equals", "hashCode", "values", "valueOf"}  # entrypoints/boilerplate
names = collections.defaultdict(set)   # method name -> set of files
perfile = collections.Counter()        # file -> count of static methods
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        m = json.loads(line)
    except Exception:
        continue
    f = m.get("file", "")
    nm = ((m.get("metaVariables") or {}).get("single") or {}).get("NAME", {}).get("text")
    if nm and nm not in IGNORE:
        names[nm].add(f)
        perfile[f] += 1
dups  = sorted(n for n, fs in names.items() if len(fs) >= 2)
heavy = sorted(f for f, c in perfile.items() if c >= 4)
out = []
if dups:
    out.append("dup across classes: " + ", ".join(dups[:8]))
if heavy:
    out.append(">=4 static methods: " + ", ".join(heavy[:5]))
print(" ; ".join(out))
PY
)"
  rm -f "$tmp"
  if [ -n "$hint" ]; then row "structural (advisory)" "HINT — $hint"; else row "structural (advisory)" "PASS"; fi
else
  skip "structural (advisory)" "ast-grep not installed"
fi

# --- emit table --------------------------------------------------------------
echo "| check | status |"
echo "|---|---|"
printf '%s\n' "${rows[@]}"
exit "$fail"
