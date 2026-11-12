#!/usr/bin/env bash
# task-cleanup.sh — list (and, with --delete, remove) the scratch artifacts of one task:
# its task-scoped memory files and its plan file(s). Dry-run by default: it ALWAYS prints
# what it found first ("mention before deleting") and only removes when you pass --delete.
#
#   task-cleanup.sh PROJ-123              # list only — shows what would be removed
#   task-cleanup.sh PROJ-123 --delete     # remove ephemeral task memories + plans, strip index
#   task-cleanup.sh PROJ-123 --delete --all   # also remove DURABLE task memories (kept by default)
#
# A task memory is a memory whose frontmatter carries `task: <ID>`. Of those, one marked
# `ephemeral: true` is throwaway (a status snapshot, a scratch note) and is removed by default;
# one without it is a durable decision (an ADR-worthy boundary) and is kept unless --all.
#
# Overrides: MEMORY_DIR=<dir> (default: ~/.claude/projects/<cwd-slug>/memory),
#            extra plan files with one or more --plan <path>.
set -euo pipefail

TASK=""; DELETE=0; ALL=0; EXTRA_PLANS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --delete) DELETE=1 ;;
    --all) ALL=1 ;;
    --plan) shift; EXTRA_PLANS+=("$1") ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) TASK="$1" ;;
  esac; shift
done
[ -n "$TASK" ] || { echo "usage: task-cleanup.sh <TASK_ID> [--delete] [--all] [--plan <path>]" >&2; exit 2; }

slug() { pwd | sed 's#/#-#g'; }
MEM_DIR="${MEMORY_DIR:-$HOME/.claude/projects/$(slug)/memory}"
INDEX="$MEM_DIR/MEMORY.md"

# --- collect task memory files, split ephemeral vs durable ---
EPHEMERAL=(); DURABLE=()
if [ -d "$MEM_DIR" ]; then
  while IFS= read -r f; do
    [ "$(basename "$f")" = "MEMORY.md" ] && continue
    # frontmatter only (first block between the --- lines)
    fm="$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$f")"
    echo "$fm" | grep -qiE "^[[:space:]]*task:[[:space:]]*$TASK[[:space:]]*$" || continue
    if echo "$fm" | grep -qiE "^[[:space:]]*ephemeral:[[:space:]]*true[[:space:]]*$"; then
      EPHEMERAL+=("$f")
    else
      DURABLE+=("$f")
    fi
  done < <(find "$MEM_DIR" -maxdepth 1 -name '*.md' 2>/dev/null)
fi

# --- collect plan files that mention the task (scratch + repo mirror + --plan) ---
PLANS=()
add_plan() { [ -f "$1" ] && grep -qi "$TASK" "$1" 2>/dev/null && PLANS+=("$1"); return 0; }
for p in "${EXTRA_PLANS[@]:-}"; do [ -n "${p:-}" ] && add_plan "$p"; done
[ -f "$PWD/.scratch/dev-workflow-plan.md" ] && add_plan "$PWD/.scratch/dev-workflow-plan.md"
while IFS= read -r p; do add_plan "$p"; done < <(ls /private/tmp/claude-*/**/dev-workflow/plan.md 2>/dev/null || true)

# --- report (always) ---
echo "Task:        $TASK"
echo "Memory dir:  $MEM_DIR"
printf 'Ephemeral memories (remove): %s\n' "${#EPHEMERAL[@]}"; printf '  %s\n' "${EPHEMERAL[@]:-(none)}"
printf 'Durable memories (keep unless --all): %s\n' "${#DURABLE[@]}"; printf '  %s\n' "${DURABLE[@]:-(none)}"
printf 'Plan files (remove): %s\n' "${#PLANS[@]}"; printf '  %s\n' "${PLANS[@]:-(none)}"

TO_DELETE=("${EPHEMERAL[@]:-}"); [ "$ALL" = 1 ] && TO_DELETE+=("${DURABLE[@]:-}")
TO_DELETE+=("${PLANS[@]:-}")
# drop empty entries
CLEAN=(); for x in "${TO_DELETE[@]:-}"; do [ -n "${x:-}" ] && CLEAN+=("$x"); done

if [ "$DELETE" != 1 ]; then
  echo; echo "Dry run — nothing deleted. Re-run with --delete to remove the ${#CLEAN[@]} file(s) above."
  [ "$ALL" != 1 ] && [ "${#DURABLE[@]}" -gt 0 ] && echo "(Durable memories are kept; add --all to remove them too.)"
  exit 0
fi

for f in "${CLEAN[@]:-}"; do
  rm -f "$f" && echo "removed $f"
  # strip its index line from MEMORY.md (match the filename in a (link))
  if [ -f "$INDEX" ]; then
    bn="$(basename "$f")"
    tmp="$(mktemp)"; grep -vF "($bn)" "$INDEX" > "$tmp" && mv "$tmp" "$INDEX"
  fi
done
echo "Done. Removed ${#CLEAN[@]} file(s); MEMORY.md index pruned."
