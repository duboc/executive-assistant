#!/usr/bin/env bash
# SessionStart hook — load state, infer mode from time of day, emit
# additionalContext so the orchestrator wakes up oriented.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

# Read stdin (event payload — we mostly ignore it but consume it)
cat >/dev/null

if [ ! -f "$EA_STATE" ]; then
  ea_inject_context "Estado EA não inicializado em state/ea-state.json. Rode setup antes de prosseguir."
  exit 0
fi

now_iso="$(ea_now_iso)"
today="$(ea_today)"
hour="$(date +%H)"

# Infer mode by time of day if not recently set
mode_current="$(jq -r '.mode.current // "active_day"' "$EA_STATE")"
mode_since="$(jq -r '.mode.since // ""' "$EA_STATE")"

# If first prompt of the day (last_morning_brief != today) and hour < 11 → morning_brief
last_brief="$(jq -r '.rituals.last_morning_brief // ""' "$EA_STATE")"
last_brief_date="${last_brief%%T*}"

new_mode="$mode_current"
if [ "$last_brief_date" != "$today" ] && [ "$hour" -lt 11 ]; then
  new_mode="morning_brief"
elif [ "$hour" -ge 18 ]; then
  new_mode="end_of_day"
fi

if [ "$new_mode" != "$mode_current" ]; then
  ea_state_patch ".mode.previous = .mode.current
                | .mode.current = \"$new_mode\"
                | .mode.since = \"$now_iso\"
                | .today.date = \"$today\""
  ea_log "mode change: $mode_current -> $new_mode"
fi

# Build context summary
ctx="$(jq -r --arg today "$today" '
  "EA bootstrap. Modo atual: \(.mode.current). Hoje: \($today).\n" +
  "Top 3 prioridades de ontem: \((.today.top_3_priorities // []) | join(", "))\n" +
  "Último weekly review: \(.rituals.last_weekly_review // "nunca").\n" +
  "Próximo weekly due: \(.rituals.next_weekly_due // "n/a").\n" +
  "Operador: \(.operator.name) (\(.operator.role)). Estilo: \(.operator.communication_style)."
' "$EA_STATE")"

ea_inject_context "$ctx"
