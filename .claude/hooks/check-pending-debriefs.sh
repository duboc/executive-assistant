#!/usr/bin/env bash
# PreToolUse hook (matcher: meeting-prepper / meeting-workflow prep phase) —
# refuse running prep if there's a pending debrief from the previous meeting
# with overlapping participants. The single most important forcing function:
# you never walk into a meeting unprocessed from the last one.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

payload="$(cat)"
sub="$(echo "$payload" | jq -r '.tool_input.subagent_type // .tool_input.skill // empty')"

# Only act on meeting prep invocations
case "$sub" in
  meeting-prepper) ;;
  meeting-workflow)
    phase="$(echo "$payload" | jq -r '.tool_input.phase // ""')"
    if [ "$phase" != "prep" ] && [ -n "$phase" ]; then
      ea_passthrough; exit 0
    fi
    ;;
  *) ea_passthrough; exit 0 ;;
esac

# Discover meetings dir
meetings_dir="${EA_ROOT}/state/rituals/meetings"
if [ ! -d "$meetings_dir" ]; then ea_passthrough; exit 0; fi

# Find prep docs whose corresponding debrief is missing
pending=()
while IFS= read -r prep; do
  base="${prep%-prep.md}"
  if [ ! -f "${base}-debrief.md" ]; then
    pending+=("$(basename "$base")")
  fi
done < <(find "$meetings_dir" -maxdepth 1 -name "*-prep.md" 2>/dev/null || true)

if [ ${#pending[@]} -gt 0 ]; then
  list="$(printf '  - %s\n' "${pending[@]}")"
  ea_deny_tool "Há reuniões com prep mas sem debrief:
$list

Rode meeting-debriefer nas reuniões anteriores antes de preparar a próxima. Você nunca entra numa reunião sem ter processado a anterior."
  exit 0
fi

ea_passthrough
