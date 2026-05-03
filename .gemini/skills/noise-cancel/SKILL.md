---
name: noise-cancel
description: Filtra ruído de inboxes (Gmail, Google Chat) em três níveis — puro, contextual, sinal disfarçado. Aprende com correções. Use no morning_brief antes de qualquer triagem profunda.
allowed-tools: Read, Write, Edit, Bash(jq:*), Skill(gchat), Agent
---

# Noise Cancel

A maioria dos sistemas de email é binária (importante / não). Esta skill é
ternária — o estágio do meio (`contextual`) é onde mora o valor real.

## Os três níveis

| Nível | Critério | Ação |
|---|---|---|
| **Ruído puro** | Newsletter não-aberta há 30d, notificação automática, FYI puro | Auto-archive, sem reportar |
| **Ruído contextual** | Pode importar em outro momento (oferta de curso, evento, paper) | Defer para weekly review (fase 1) |
| **Sinal disfarçado** | Sender em `vip_senders` OU contém `vip_keywords` OU é resposta a thread aberta | Promover para triagem profunda |

A skill **não deleta nada**. Ela move pra buckets. Operador valida edge cases.

## Fluxo

### Passo 1 — Carregar filtros aprendidos

```bash
cat state/ea-state.json | jq '.noise_filters'
```

Padrões em `auto_archive_patterns` e `auto_defer_patterns` são tratados como regex.
`vip_senders` e `vip_keywords` são overrides (sempre promovem).

### Passo 2 — Classificar (em batch via subagent inbox-triager)

Delegue ao subagent `inbox-triager` com modo=`noise_first_pass`. Ele recebe a
lista de mensagens (do gchat/gmail) e devolve:

```json
{
  "pure_noise": [{ "id": "...", "matched_pattern": "..." }],
  "contextual": [{ "id": "...", "reason": "..." }],
  "disguised_signal": [{ "id": "...", "vip_match": "..." }],
  "uncertain": [{ "id": "...", "why": "..." }]
}
```

**Regra:** se qualquer item bate em `vip_*`, vai pra `disguised_signal` mesmo que
também bata num padrão de archive. Override sempre vence.

### Passo 3 — Aplicar ações

- `pure_noise` → arquivar via `gchat`/gmail skill, registrar id em `learning_log` com `action: archived`
- `contextual` → mover pra label "EA/Defer" (gmail) ou flag deferido, registrar
- `disguised_signal` → deixar inbox, sinaliza pro operador na próxima triagem
- `uncertain` → pergunta ao operador (máx 5 por sessão; resto vai pra `contextual`)

### Passo 4 — Aprender

Toda vez que:
- Operador **resgata** um item de `pure_noise` → adicionar exceção (sender ou keyword) a `vip_*`
- Operador **arquiva manualmente** um item que não bateu em padrão → propor novo padrão na próxima weekly

Hook `PostToolUse` em ações de inbox alimenta `learning_log` automaticamente.

## Estado: noise_filters

```json
{
  "auto_archive_patterns": [
    "from:.*@noreply\\..*",
    "subject:.*\\[FYI\\].*",
    "list-id:.*newsletter.*"
  ],
  "auto_defer_patterns": [
    "subject:.*(curso|webinar|treinamento).*"
  ],
  "vip_senders": ["laiane@", "boss@google.com"],
  "vip_keywords": ["GymPulse", "mainframe-skills", "urgent"],
  "learning_log": [
    {
      "ts": "2026-05-01T08:30:00Z",
      "msg_id": "abc123",
      "auto_action": "archived",
      "operator_correction": "rescued",
      "proposed_exception": "sender:partner@x.com"
    }
  ]
}
```

## Calibração

Critério de saúde: **precision > 0.95 em pure_noise**. Se operador resgatou >5%
do que foi auto-arquivado nos últimos 7 dias, a skill **pausa o auto-archive**
e pede tuning na próxima weekly review.

Hook `PostToolUse` calcula esse rate. Se >5%, escreve em
`state/ea-state.json :: stats.noise_cancel_health = "needs_tuning"` e a skill
recusa rodar até a fase 7 da próxima review.

## Anti-padrões

- ❌ Deletar (irreversível). Sempre arquivar.
- ❌ Aprender em silêncio. Toda mudança de filtro passa por weekly review fase 7.
- ❌ Tratar VIP como soft signal. VIP override sempre.
- ❌ "Importante" sem mais qualificação. Importante pra quê? Pra qual projeto?
