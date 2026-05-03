---
name: weekly-review
description: Ritual semanal de 7 fases (40min). Forcing function que hooks tornam impossível pular. Use sex/sáb, ou quando hook ritual-check sinaliza atraso. Trava outras skills enquanto roda.
allowed-tools: Read, Write, Edit, Bash(jq:*), Bash(date:*), Skill(gdocs), Skill(gcalendar), Agent
---

# Weekly Review

Ritual semanal em 7 fases ordenadas. **Cada fase tem critério de saída.** Não
avança sem fechar. Hook `enter-review-mode.sh` trava outras skills durante
a execução.

## Diagrama

```
Fase 1: COLETA       (5min)  agrega o que aconteceu na semana
Fase 2: COMMITMENTS  (5min)  review de promessas feitas/recebidas
Fase 3: PROJECTS     (10min) status de cada projeto ativo
Fase 4: ENERGIA      (5min)  onde a energia foi vs onde deveria
Fase 5: PRÓXIMA      (10min) top 3 prioridades da próxima semana
Fase 6: DORMENTES    (3min)  matar/ressuscitar/aceitar dormência
Fase 7: NOISE TUNE   (2min)  refinar filtros de ruído
```

## Modo de operação

**Diálogo, não formulário.** Você puxa estado, faz pergunta direcionada,
espera resposta, atualiza estado. Operador decide; você cataloga.

Em cada fase:
1. Anuncie a fase (`## Fase N: <nome>`)
2. Apresente o estado relevante (1-2 telas máx)
3. Faça a **pergunta direcionada** específica da fase
4. Aplique a decisão (escreva no estado)
5. Mostre critério de saída atingido antes de passar pra próxima

## Fase 1 — COLETA

**Pergunta direcionada:** "Olha a semana. O que mais te orgulhou? O que mais te frustrou?"

**O que mostrar:**
- Eventos do `gcalendar` da semana, agrupados por dia
- Commitments fechados na semana (status: completed)
- Projetos com `last_touched` na semana

**Critério de saída:** operador respondeu, anotação salva em `state/rituals/weekly/<YYYY-WW>.md`.

## Fase 2 — COMMITMENTS

**Pergunta direcionada:** "Vamos por essa lista. Para cada um: feito, ainda em pé, ou morreu?"

**O que mostrar:**
- `made-by-operator.json` com status=open, agrupados por contraparte
- `made-to-operator.json` com status=open, idem
- `implicit.json` com confidence>=medium

**Aplicar:**
- Status atualizado por commitment
- Implícitos viram explícitos (confirmar prazo) ou são despromovidos

**Critério de saída:** zero commitments com status `open` sem prazo definido.

## Fase 3 — PROJECTS

Para cada projeto em `state/projects/*.yaml` com status `active|shipping|iterating`:

**Pergunta direcionada:** "<projeto>: status muda? next_action ainda é essa? algo bloqueando?"

**Aplicar:**
- `status` (mantém / muda)
- `next_action` (refina ou substitui)
- `blockers` (adicionar/remover)
- `last_touched = now`

**Critério de saída:** todos projetos active+ visitados, last_touched atualizado.

## Fase 4 — ENERGIA

**Pergunta direcionada:** "Olhando a semana, energia foi pra onde você queria? O que sugou?"

**O que mostrar:**
- Comparativo: tempo em meetings vs tempo em deep work (do gcalendar)
- Projetos que receberam touches vs que receberam declarações ("vou olhar")

**Aplicar:** ajuste de `operator.energy_pattern` se padrão mudou.

**Critério de saída:** uma frase escrita pelo operador no review doc.

## Fase 5 — PRÓXIMA

**Pergunta direcionada:** "Próxima semana, se só 3 coisas saírem, quais têm que ser?"

**Aplicar:**
- `state/ea-state.json :: today.top_3_priorities` para a próxima segunda
- Cada uma vinculada a project_id ou commitment_id

**Critério de saída:** exatamente 3 prioridades. Nem 4, nem 2.

## Fase 6 — DORMENTES

**O que mostrar:**
- Projetos com `last_touched > dormancy.threshold_days`

**Pergunta direcionada (por projeto):** "Esse aqui: matar (sunset), aceitar dormência, ou ressuscitar?"

**Aplicar:**
- `sunset` → `status: sunset`, mover do `_index.json` para arquivo histórico
- `dormant` → `status: dormant`, mantém arquivo, sai de roteamento ativo
- `resurrect` → `status: active`, define novo `next_action`

**Critério de saída:** zero projetos active com last_touched > 14d sem decisão.

## Fase 7 — NOISE TUNE

**O que mostrar:**
- `noise_filters.learning_log` da semana: itens auto-arquivados que operador resgatou
- Itens que operador arquivou manualmente que não casavam com nenhum padrão

**Pergunta direcionada:** "Esses padrões: adicionar, remover, ou ignorar?"

**Aplicar:**
- Atualizar `auto_archive_patterns`, `auto_defer_patterns`, `vip_senders`
- Limpar `learning_log`

**Critério de saída:** filtros atualizados, log zerado.

## Atualização final

```json
{
  "rituals.last_weekly_review": "<ISO>",
  "rituals.next_weekly_due": "<ISO + 7d>",
  "mode.current": "active_day"
}
```

E gerar/salvar `state/rituals/weekly/<YYYY-WW>.md` com todas as decisões.

## Por que diálogo, não formulário

Formulários são preenchidos no automático. Diálogo força reflexão. Cada
pergunta direcionada é construída pra evitar resposta mecânica.

## Anti-padrões

- ❌ Saltar fase ("commitments tá tudo OK, próximo")
- ❌ Top 5 ao invés de top 3
- ❌ Aceitar projeto active sem next_action
- ❌ Pular fase 7 — é onde o sistema aprende
- ❌ Permitir o operador entrar no inbox no meio do review
