#!/usr/bin/env bash
# PreToolUse hook (matcher: weekly-review or quarterly-review) — flip the
# orchestrator into the review mode and lock other skills. filter-skills-by-mode
# enforces the lock; this hook just sets state.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

payload="$(cat)"
sub="$(echo "$payload" | jq -r '.tool_input.subagent_type // .tool_input.skill // empty')"

case "$sub" in
  weekly-review)   target_mode="weekly_review" ;;
  quarterly-review) target_mode="quarterly_review" ;;
  *) ea_passthrough; exit 0 ;;
esac

if [ ! -f "$EA_STATE" ]; then ea_passthrough; exit 0; fi

now_iso="$(ea_now_iso)"
current="$(jq -r '.mode.current' "$EA_STATE")"
if [ "$current" != "$target_mode" ]; then
  ea_state_patch ".mode.previous = .mode.current
                | .mode.current = \"$target_mode\"
                | .mode.since = \"$now_iso\""
  ea_log "enter-review: $current -> $target_mode"
fi

ea_inject_context "Entrando em modo $target_mode. Outras skills ficam bloqueadas até concluir o ritual. Não responda triagens, drafts ou status updates de projeto neste contexto."
