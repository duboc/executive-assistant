#!/usr/bin/env bash
# SessionEnd hook — write a daily snapshot, reset per-day counters,
# schedule next morning's brief expectation.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

cat >/dev/null

if [ ! -f "$EA_STATE" ]; then ea_passthrough; exit 0; fi

today="$(ea_today)"
now_iso="$(ea_now_iso)"

# Persist a one-page EOD note
eod_dir="${EA_ROOT}/state/rituals/daily"
mkdir -p "$eod_dir"
out="${eod_dir}/${today}-eod.md"

{
  printf '# EOD — %s\n\n' "$today"
  printf '## Modo final\n%s\n\n' "$(jq -r '.mode.current' "$EA_STATE")"
  printf '## Skills/Subagents invocados\n'
  jq -r '.stats.skills_invoked_today | to_entries[]? | "- skill \(.key): \(.value)x"' "$EA_STATE"
  jq -r '.stats.subagents_invoked_today | to_entries[]? | "- agent \(.key): \(.value)x"' "$EA_STATE"
  printf '\n## Top 3 que estavam definidas\n'
  jq -r '.today.top_3_priorities[]? | "- \(.)"' "$EA_STATE"
  printf '\n## Commitments due amanhã\n'
  tomorrow="$(date -d 'tomorrow' +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d)"
  jq -r --arg t "$tomorrow" '.commitments[]? | select(.status == "open" and (.due.declared // "") <= $t) | "- [\(.id)] \(.description)"' \
    "${EA_ROOT}/state/commitments/made-by-operator.json" 2>/dev/null || true
} >"$out"

ea_state_patch ".rituals.last_eod_snapshot = \"$now_iso\"
              | .stats.skills_invoked_today = {}
              | .stats.subagents_invoked_today = {}
              | .mode.previous = .mode.current
              | .mode.current = \"active_day\"
              | .mode.since = \"$now_iso\""

ea_log "eod snapshot saved: $out"
ea_passthrough
