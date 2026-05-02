#!/usr/bin/env bash
# PostToolUse hook — increment skill/subagent invocation counters,
# log to .hooks.log. Cheap accounting that keeps stats fresh.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

payload="$(cat)"
tool="$(echo "$payload" | jq -r '.tool_name // empty')"
sub="$(echo "$payload" | jq -r '.tool_input.subagent_type // .tool_input.skill // empty')"

if [ ! -f "$EA_STATE" ]; then ea_passthrough; exit 0; fi

today="$(ea_today)"

case "$tool" in
  Skill)
    if [ -n "$sub" ]; then
      ea_state_patch ".stats.skills_invoked_today[\"$sub\"] = ((.stats.skills_invoked_today[\"$sub\"] // 0) + 1)
                    | .today.date = \"$today\""
    fi
    ;;
  Agent|Task)
    if [ -n "$sub" ]; then
      ea_state_patch ".stats.subagents_invoked_today[\"$sub\"] = ((.stats.subagents_invoked_today[\"$sub\"] // 0) + 1)
                    | .today.date = \"$today\""
    fi
    ;;
esac

ea_passthrough
