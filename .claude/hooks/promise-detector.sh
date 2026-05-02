#!/usr/bin/env bash
# Stop hook — scan the assistant's last response for commitment-language
# emanating from the operator quoted earlier in the turn (e.g. the operator
# said "vou mandar pro Pedro amanhã"). When detected, inject a reminder so the
# orchestrator delegates to commitment-tracker.
#
# We deliberately do not auto-register; we only flag.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

payload="$(cat)"

# Try common payload shapes for the assistant's final text
text="$(echo "$payload" | jq -r '
  .stop_reason // empty,
  (.transcript // [] | last | .content // empty),
  (.last_message // empty),
  (.message // empty)
' 2>/dev/null | tr '\n' ' ')"

# If we got nothing useful, bail silently
if [ -z "$text" ]; then ea_passthrough; exit 0; fi

# Phrase patterns suggesting an implicit operator promise
patterns=(
  "vou mandar"
  "vou ver"
  "te mando"
  "vou dar uma olhada"
  "deixa eu pensar"
  "podemos conversar"
  "vou falar com"
  "I'll send"
  "I'll look"
  "I'll get back"
  "let me check"
)

found=""
for p in "${patterns[@]}"; do
  if echo "$text" | grep -qiF "$p"; then
    found="$p"
    break
  fi
done

if [ -n "$found" ]; then
  ea_inject_context "[hook promise-detector] Possível promessa implícita detectada: \"$found\". Delegue ao commitment-tracker (add_implicit) e pergunte ao operador se confirma como commitment com prazo."
  exit 0
fi

ea_passthrough
