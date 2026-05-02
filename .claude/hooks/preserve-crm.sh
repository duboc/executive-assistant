#!/usr/bin/env bash
# PreCompact hook — before the conversation history is compressed, force a
# snapshot of CRM-critical context (active projects, open commitments due
# this week, top-3 priorities) into a durable file the orchestrator
# rereads after compaction.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

cat >/dev/null

if [ ! -f "$EA_STATE" ]; then ea_passthrough; exit 0; fi

snapshot_dir="${EA_ROOT}/state/.snapshots"
mkdir -p "$snapshot_dir"
ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
out="${snapshot_dir}/precompact-${ts}.md"

{
  printf '# Pre-compaction snapshot — %s\n\n' "$ts"
  printf '## Modo\n%s\n\n' "$(jq -r '.mode.current' "$EA_STATE")"
  printf '## Top 3 prioridades\n'
  jq -r '.today.top_3_priorities[]? | "- \(.)"' "$EA_STATE"
  printf '\n## Operator focus\n'
  jq -r '.operator.current_focus[]? | "- \(.)"' "$EA_STATE"
  printf '\n## Projetos ativos\n'
  jq -r '.projects[]? | select(.status == "active" or .status == "shipping" or .status == "iterating") | "- \(.id): \(.name) [\(.status)]"' \
    "${EA_ROOT}/state/projects/_index.json" 2>/dev/null || true
  printf '\n## Commitments abertos por operador\n'
  jq -r '.commitments[]? | select(.status == "open") | "- [\(.id)] \(.description) → \(.counterparty_person_id) (due \(.due.declared // .due.inferred // "?"))"' \
    "${EA_ROOT}/state/commitments/made-by-operator.json" 2>/dev/null || true
} >"$out"

ea_state_patch '.stats.compression_events = ((.stats.compression_events // 0) + 1)'

ea_inject_context "Contexto será comprimido. Snapshot crítico salvo em ${out}. Após compactação, releia ${out} e state/ea-state.json antes de continuar."
