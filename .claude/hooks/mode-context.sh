#!/usr/bin/env bash
# UserPromptSubmit hook — inject mode-specific context every prompt
# so the orchestrator never drifts about which mode it's in.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/lib/common.sh"

# Consume payload (we don't need fields here, but must not break stdin)
cat >/dev/null

if [ ! -f "$EA_STATE" ]; then ea_passthrough; exit 0; fi

mode="$(jq -r '.mode.current' "$EA_STATE")"

case "$mode" in
  morning_brief)
    ctx="Modo: morning_brief. Skill recomendada: daily-brief. Subagents: inbox-triager, project-tracker."
    ;;
  active_day)
    ctx="Modo: active_day. Operador dirige. Subagents: inbox-triager, project-router, draft-composer, commitment-tracker."
    ;;
  meeting_prep)
    ctx="Modo: meeting_prep. Foco: meeting-prepper, relationship-keeper. Não comece outro trabalho profundo."
    ;;
  meeting_debrief)
    ctx="Modo: meeting_debrief. Foco: meeting-debriefer, depois commitment-tracker e project-router para rotear ações."
    ;;
  weekly_review)
    ctx="Modo: weekly_review. **TRAVADO**. Apenas skill weekly-review. Não responda a triagens, drafts ou outras tarefas até concluir o ritual."
    ;;
  quarterly_review)
    ctx="Modo: quarterly_review. **TRAVADO**. Apenas quarterly-review."
    ;;
  end_of_day)
    ctx="Modo: end_of_day. Foco: revisar commitments due, salvar snapshot, planejar amanhã. Sem deep work novo."
    ;;
  *)
    ctx="Modo desconhecido: $mode. Fallback para active_day."
    ;;
esac

# Add hint about pending implicit commitments (always relevant)
implicit_count="$(jq '.commitments | length' "${EA_ROOT}/state/commitments/implicit.json" 2>/dev/null || echo 0)"
if [ "${implicit_count:-0}" -gt 0 ]; then
  ctx="${ctx}
${implicit_count} commitment(s) implícito(s) aguardando confirmação."
fi

ea_inject_context "$ctx"
