#!/usr/bin/env bash
# Stop hook — detect when the operator (or assistant talking about the
# operator) mentioned a known project. If so, touch the project's
# last_touched without invoking the full project-tracker. Just thinking
# about a project keeps it alive in the system.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

payload="$(cat)"
text="$(ea_payload_last_text "$payload")"

if [ -z "$text" ]; then ea_passthrough; exit 0; fi

idx="${EA_ROOT}/state/projects/_index.json"
if [ ! -f "$idx" ]; then ea_passthrough; exit 0; fi

now_iso="$(ea_now_iso)"
touched=()

while IFS=$'\t' read -r pid pname; do
  [ -z "$pid" ] && continue
  if echo "$text" | grep -qiE "\b${pname}\b|\b${pid}\b"; then
    pyaml="${EA_ROOT}/state/projects/${pid}.yaml"
    if [ -f "$pyaml" ]; then
      # Edit the YAML's last_touched line in place
      if grep -q "^last_touched:" "$pyaml"; then
        sed -i.bak "s|^last_touched:.*|last_touched: ${now_iso}|" "$pyaml" && rm -f "${pyaml}.bak"
      else
        printf 'last_touched: %s\n' "$now_iso" >>"$pyaml"
      fi
      touched+=("$pid")
      ea_log "project-mention: touched $pid"
    fi
  fi
done < <(jq -r '.projects[]? | [.id, .name] | @tsv' "$idx" 2>/dev/null)

if [ ${#touched[@]} -gt 0 ]; then
  ea_inject_context "[hook project-mention] Projetos tocados: ${touched[*]}"
  exit 0
fi

ea_passthrough
