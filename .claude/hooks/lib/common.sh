#!/usr/bin/env bash
# Helpers shared by EA hooks. Source this in every hook.
# All hooks read JSON from stdin and write JSON to stdout.
#
# Runtime detection: this lib resolves EA_ROOT from whichever runtime is
# driving the session (Claude Code or Gemini CLI). Hooks themselves stay
# runtime-agnostic.

set -euo pipefail

# Detect runtime ("claude" | "gemini" | "unknown") for downstream conditionals
EA_RUNTIME="unknown"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  EA_RUNTIME="claude"
elif [ -n "${GEMINI_PROJECT_DIR:-}" ]; then
  EA_RUNTIME="gemini"
fi

# Resolve repo root regardless of CWD; honor either runtime's env var
EA_ROOT="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-${EA_PROJECT_DIR:-}}}"
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

# Normalize tool/skill/agent identifiers across runtimes.
# Claude Code payload: .tool_name, .tool_input.subagent_type, .tool_input.skill
# Gemini CLI  payload: .toolName,  .toolInput.subagent_type (varies by event)
ea_payload_tool_name() {
  echo "$1" | jq -r '.tool_name // .toolName // empty'
}

ea_payload_sub() {
  echo "$1" | jq -r '
    .tool_input.subagent_type // .toolInput.subagent_type
    // .tool_input.skill // .toolInput.skill
    // .tool_input.skill_name // .toolInput.skill_name
    // empty
  '
}

ea_payload_user_prompt() {
  echo "$1" | jq -r '.user_prompt // .userPrompt // .prompt // empty'
}

# Best-effort extraction of the latest assistant text from Stop/AfterModel
# payloads — both runtimes structure transcripts differently, so we try
# several common keys and concatenate.
ea_payload_last_text() {
  echo "$1" | jq -r '
    [
      (.transcript // [] | last | (.content // "")),
      (.message // ""),
      (.last_message // ""),
      (.lastMessage // ""),
      (.modelOutput // ""),
      (.output // "")
    ] | map(select(. != null and . != "")) | join(" ")
  ' 2>/dev/null || true
}
