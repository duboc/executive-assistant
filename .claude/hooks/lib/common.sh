#!/usr/bin/env bash
# Helpers shared by EA hooks. Source this in every hook.
# All hooks read JSON from stdin and write JSON to stdout.

set -euo pipefail

# Resolve repo root regardless of CWD
EA_ROOT="${CLAUDE_PROJECT_DIR:-${EA_PROJECT_DIR:-}}"
if [ -z "$EA_ROOT" ]; then
  # Fallback: find the directory containing state/ea-state.json walking up
  cur="$(pwd)"
  while [ "$cur" != "/" ]; do
    if [ -f "$cur/state/ea-state.json" ]; then
      EA_ROOT="$cur"
      break
    fi
    cur="$(dirname "$cur")"
  done
fi

EA_STATE="${EA_ROOT}/state/ea-state.json"
EA_LOG="${EA_ROOT}/state/.hooks.log"

ea_log() {
  local msg="$1"
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >>"$EA_LOG" 2>/dev/null || true
}

# Atomic write helper (jq pipeline -> tmp -> mv)
ea_state_patch() {
  local jq_filter="$1"
  local tmp
  tmp="$(mktemp)"
  jq "$jq_filter" "$EA_STATE" >"$tmp" && mv "$tmp" "$EA_STATE"
}

ea_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
ea_today() { date +%Y-%m-%d; }

# Emit a no-op success (passthrough)
ea_passthrough() { printf '{}\n'; }

# Emit additional context to inject into the model
ea_inject_context() {
  local ctx="$1"
  jq -n --arg c "$ctx" '{hookSpecificOutput: {additionalContext: $c}}'
}

# Block a tool/prompt with reason
ea_block() {
  local reason="$1"
  jq -n --arg r "$reason" '{decision: "block", reason: $r}'
}

ea_deny_tool() {
  local reason="$1"
  jq -n --arg r "$reason" '{decision: "deny", reason: $r}'
}
