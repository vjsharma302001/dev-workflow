#!/usr/bin/env bash
# verify-report.sh — render the verifier's results (JSON) into one self-contained HTML
# report of what was tested. Deterministic: $0 model tokens for the markup.
#
#   verify-report.sh <results.json> [out.html]      # file in, file out (default: ./verify-report.html)
#   cat results.json | verify-report.sh - out.html  # stdin in
#
# JSON shape (every field optional except ticket; rows is the matrix):
# {
#   "ticket":"PROJ-123", "title":"…", "date":"2026-11-12",
#   "outcome":"converged",                 // or "stopped (budget)", "not converged"
#   "runPath":"backend → mirrord+devtest + browser",
#   "summary":["valid input → accepted ✓", "out-of-range → rejected ✓"],
#   "rows":[ {"case":"…","technique":"BVA","expected":"…","result":"PASS","automate":"automate","note":""} ],
#   "breakItRed":"flipped guard → covering test went red ✓",
#   "mutation":"no surviving mutants in changed files",
#   "tenant":"A sees only A; B isolated ✓",        // or "n/a (not tenant-scoped)"
#   "unmet":[], "manualChecklist":["one-off data check …"]
# }
set -euo pipefail
IN="${1:?usage: verify-report.sh <results.json|-> [out.html]}"
OUT="${2:-./verify-report.html}"
# stdin: slurp to a temp file first — the heredoc below occupies /dev/stdin
if [ "$IN" = "-" ]; then TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT; cat > "$TMP"; IN="$TMP"; fi
mkdir -p "$(dirname "$OUT")"

python3 - "$IN" "$OUT" <<'PY'
import json, sys, html, datetime
src, out = sys.argv[1], sys.argv[2]
d = json.load(open(src))
e = lambda x: html.escape(str(x if x is not None else ""))

ticket = e(d.get("ticket","(no ticket)"))
title  = e(d.get("title",""))
date   = e(d.get("date", datetime.date.today().isoformat()))
outcome= d.get("outcome","converged")
oc = outcome.lower()
obadge = "ok" if "converg" in oc and "not" not in oc else ("warn" if "stop" in oc or "not" in oc else "ok")
rows = d.get("rows",[]) or []
npass = sum(1 for r in rows if str(r.get("result","")).upper()=="PASS")
nfail = sum(1 for r in rows if str(r.get("result","")).upper()=="FAIL")
unmet = d.get("unmet",[]) or []

def li(items):
    items = items or []
    if not items: return "<p class=muted>—</p>"
    return "<ul>"+"".join(f"<li>{e(x)}</li>" for x in items)+"</ul>"

def section(title_, body, cls=""):
    if not body: return ""
    return f'<section class="{cls}"><h2>{e(title_)}</h2>{body}</section>'

trs=[]
for r in rows:
    res=str(r.get("result","")).upper()
    rc="pass" if res=="PASS" else ("fail" if res=="FAIL" else "")
    auto=e(r.get("automate",""))
    ac="auto" if auto.lower().startswith("auto") else "manual"
    trs.append(
      f"<tr><td>{e(r.get('case',''))}</td><td class=tech>{e(r.get('technique',''))}</td>"
      f"<td>{e(r.get('expected',''))}</td><td class='res {rc}'>{e(res)}</td>"
      f"<td class='{ac}'>{auto}</td><td class=muted>{e(r.get('note',''))}</td></tr>")
matrix = ("<table><thead><tr><th>Case / inputs</th><th>Technique</th><th>Expected</th>"
          "<th>Result</th><th>Automate?</th><th>Note</th></tr></thead><tbody>"
          +"".join(trs)+"</tbody></table>") if trs else ""

summary = d.get("summary",[]) or []
sum_html = "".join(f"<li>{e(s)}</li>" for s in summary)

doc = f"""<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Verify report · {ticket}</title>
<style>
:root{{--bg:#fff;--fg:#1a1d21;--mut:#6b7280;--line:#e5e7eb;--card:#f9fafb;
--ok:#15803d;--okbg:#dcfce7;--bad:#b91c1c;--badbg:#fee2e2;--warn:#b45309;--warnbg:#fef3c7;--accent:#2563eb}}
@media(prefers-color-scheme:dark){{:root{{--bg:#0f1114;--fg:#e5e7eb;--mut:#9ca3af;--line:#272b31;--card:#15181c;
--okbg:#052e1a;--badbg:#3a0d0d;--warnbg:#3a2a06}}}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--fg);
font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;padding:16px}}
.wrap{{max-width:1000px;margin:0 auto}}
h1{{font-size:20px;margin:0 0 2px}}h2{{font-size:15px;margin:22px 0 8px;letter-spacing:.02em;text-transform:uppercase;color:var(--mut)}}
.sub{{color:var(--mut);margin:0 0 14px}}
.badge{{display:inline-block;padding:2px 10px;border-radius:999px;font-weight:600;font-size:13px}}
.badge.ok{{background:var(--okbg);color:var(--ok)}}.badge.warn{{background:var(--warnbg);color:var(--warn)}}
.counts span{{margin-right:14px;font-weight:600}}.counts .p{{color:var(--ok)}}.counts .f{{color:var(--bad)}}
section{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 16px;margin:10px 0}}
section.flag{{border-color:var(--bad)}}
ul{{margin:4px 0;padding-left:20px}}li{{margin:2px 0}}
table{{width:100%;border-collapse:collapse;font-size:14px}}
th,td{{text-align:left;padding:7px 9px;border-bottom:1px solid var(--line);vertical-align:top}}
th{{color:var(--mut);font-size:12px;text-transform:uppercase;letter-spacing:.03em}}
.res{{font-weight:700;text-align:center;white-space:nowrap}}.res.pass{{color:var(--ok)}}.res.fail{{color:var(--bad)}}
.auto{{color:var(--accent);font-weight:600}}.manual{{color:var(--mut)}}.tech{{color:var(--mut)}}.muted{{color:var(--mut)}}
footer{{color:var(--mut);font-size:12px;margin-top:20px}}
</style></head><body><div class=wrap>
<h1>Verification report — {ticket}</h1>
<p class=sub>{title}{' · ' if title else ''}{date} · <span class="badge {obadge}">{e(outcome)}</span></p>
<p class=counts><span class=p>{npass} passed</span><span class=f>{nfail} failed</span>
<span class=muted>{len(rows)} cases · {e(d.get('runPath',''))}</span></p>
{section('Tested (summary)', '<ul>'+sum_html+'</ul>' if sum_html else '')}
{section('Test matrix', matrix)}
{section('Break-it-red', '<p>'+e(d.get('breakItRed',''))+'</p>' if d.get('breakItRed') else '')}
{section('Mutation testing', '<p>'+e(d.get('mutation',''))+'</p>' if d.get('mutation') else '')}
{section('Tenant isolation', '<p>'+e(d.get('tenant',''))+'</p>' if d.get('tenant') else '')}
{section('Unmet acceptance criteria', li(unmet), 'flag' if unmet else '')}
{section('Manual checklist (no standing test)', li(d.get('manualChecklist')))}
<footer>Generated by dev-workflow verifier · {date}</footer>
</div></body></html>"""
open(out,"w").write(doc)
print(out)
PY
