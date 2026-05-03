#!/usr/bin/env bash
# Mirror skills from .claude/ into .gemini/ so both runtimes can invoke them.
#
# Subagents are NOT mirrored: Gemini CLI subagents have a different
# orchestration model (no recursion, structured handoffs, native tool field
# with Gemini tool names). They are hand-tuned in .gemini/agents/ separately.
#
# Hook scripts stay in .claude/hooks/ — both runtimes' settings.json reference
# them via their respective env var ($CLAUDE_PROJECT_DIR or $GEMINI_PROJECT_DIR),
# and lib/common.sh resolves either.
#
# Usage:
#   ./scripts/sync-runtimes.sh           # sync .claude/skills -> .gemini/skills
#   ./scripts/sync-runtimes.sh --check   # exit 1 if out of sync (CI guard)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SKILLS="$REPO_ROOT/.claude/skills"
DST_SKILLS="$REPO_ROOT/.gemini/skills"

mode="sync"
if [ "${1:-}" = "--check" ]; then
  mode="check"
fi

drift=0

mirror_dir() {
  local src="$1" dst="$2" label="$3"
  [ -d "$src" ] || { echo "[$label] missing source: $src" >&2; return 1; }
  mkdir -p "$dst"

  if [ "$mode" = "check" ]; then
    if ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
      echo "[$label] DRIFT: $src vs $dst"
      drift=1
    else
      echo "[$label] OK"
    fi
  else
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete "$src/" "$dst/"
    else
      rm -rf "$dst"
      cp -R "$src" "$dst"
    fi
    echo "[$label] synced -> $dst"
  fi
}

mirror_dir "$SRC_SKILLS" "$DST_SKILLS" "skills"

if [ "$mode" = "check" ] && [ "$drift" -ne 0 ]; then
  echo "Out of sync. Run scripts/sync-runtimes.sh to fix." >&2
  exit 1
fi
