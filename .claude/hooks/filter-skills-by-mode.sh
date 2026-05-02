#!/usr/bin/env bash
# PreToolUse hook — when mode is a locked-ritual mode, deny tool calls
# that aren't to the appropriate ritual skill/agent. This is the main
# forcing function that makes weekly_review uninterruptible.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

payload="$(cat)"
tool_name="$(echo "$payload" | jq -r '.tool_name // .toolName // empty')"
# Some tool calls embed a sub-skill or sub-agent identifier
sub="$(echo "$payload" | jq -r '
  .tool_input.subagent_type // .tool_input.skill // .tool_input.skill_name // empty
' 2>/dev/null || echo "")"

if [ ! -f "$EA_STATE" ]; then ea_passthrough; exit 0; fi
mode="$(jq -r '.mode.current' "$EA_STATE")"

# Helper: is this a Skill/Agent call we care about?
is_orchestration_call=false
case "$tool_name" in
  Skill|Agent|Task) is_orchestration_call=true ;;
esac

case "$mode" in
  weekly_review)
    if [ "$is_orchestration_call" = "true" ]; then
      case "$sub" in
        weekly-review|"") ea_passthrough; exit 0 ;;
        *)
          ea_deny_tool "Modo weekly_review está travado. Apenas a skill 'weekly-review' pode rodar. Tentativa de invocar '$sub' bloqueada. Conclua o ritual antes."
          exit 0
          ;;
      esac
    fi
    ;;
  quarterly_review)
    if [ "$is_orchestration_call" = "true" ]; then
      case "$sub" in
        quarterly-review|"") ea_passthrough; exit 0 ;;
        *)
          ea_deny_tool "Modo quarterly_review está travado. Apenas 'quarterly-review' permitida."
          exit 0
          ;;
      esac
    fi
    ;;
  meeting_prep)
    if [ "$is_orchestration_call" = "true" ]; then
      case "$sub" in
        meeting-workflow|meeting-prepper|relationship-keeper|"") ea_passthrough; exit 0 ;;
        weekly-review|quarterly-review)
          ea_deny_tool "Reunião em <30min. Não inicie '$sub' agora. Volte após meeting_debrief."
          exit 0
          ;;
      esac
    fi
    ;;
esac

ea_passthrough
