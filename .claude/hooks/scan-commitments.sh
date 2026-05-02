#!/usr/bin/env bash
# PostToolUse hook — after meeting-debriefer or draft-composer runs,
# warn the orchestrator to delegate any extracted commitments to commitment-tracker.
# This hook does NOT itself parse content — it only injects a reminder.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

payload="$(cat)"
sub="$(echo "$payload" | jq -r '.tool_input.subagent_type // .tool_input.skill // empty')"

case "$sub" in
  meeting-debriefer|draft-composer)
    ea_inject_context "[hook] $sub rodou. Delegue todo commitment extraído ao commitment-tracker; implícitos não viram commitments sem confirmação humana."
    exit 0
    ;;
esac

ea_passthrough
