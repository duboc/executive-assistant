---
name: daily-brief
description: Ritual matinal. Gera brief de 1 página com agenda do dia, commitments due, ruído já filtrado, e sugestão de top 3 prioridades. Use de manhã ou quando operador pede "o que tenho hoje".
allowed-tools: Read, Write, Edit, Bash(jq:*), Bash(date:*), Skill(gcalendar), Skill(gchat), Skill(gdocs), Agent
---

# Daily Brief

Brief matinal de 1 página. Não é resumo — é alavanca de decisão.

## Saída desejada

Um documento em `state/rituals/daily/<YYYY-MM-DD>.md` com **6 seções fixas**:

```markdown
# <YYYY-MM-DD>

## Agenda
- 10:00 1:1 com Laiane — meeting-prepper já rodou? [link]
- 14:30 Review GymPulse — prep pendente

## Commitments due hoje
- Você → Pedro: enviar doc Y (declarado ontem)
- Beatriz → você: feedback no design Z (vencendo)

## Threads abertas que merecem atenção
- (até 3, vindo de people/*.yaml com last_contact recente + open_threads)

## Ruído já tratado
- 14 emails arquivados (newsletter, notificações)
- 2 deferidos para weekly review

## Energia
- Bloco AM livre: 09:00–11:30 (3 deep work blocks de 50min)
- PM dominado por meetings — não programe trabalho criativo

## Top 3 sugeridos
1. <prioridade>
2. <prioridade>
3. <prioridade>
```

## Como construir

Execução em **fases sequenciais**, cada uma um turno:

### Fase 1 — Agenda
- Chame skill `gcalendar` (ou subagent que a use): listar eventos de hoje + amanhã cedo
- Para cada evento: marcar se já tem prep doc (`meeting-prepper` rodou?)

### Fase 2 — Commitments
- Read `state/commitments/made-by-operator.json` filtrado por `due.declared <= hoje`
- Read `state/commitments/made-to-operator.json` mesma filtro
- Para implícitos: só os com `due.confidence >= medium`

### Fase 3 — Threads abertas
- Read `state/people/*.yaml`, filtrar por `open_threads.length > 0`
- Limite: 3 threads. Mais que isso vira ruído.

### Fase 4 — Noise cancel
- **Delegar ao subagent `inbox-triager`** com modo=`noise_first_pass`
- Operador não vê o ruído individual, vê só o contador

### Fase 5 — Energia
- Calcular blocos livres entre meetings (>50min)
- Se PM tem ≥3 meetings, marcar como "PM saturado"

### Fase 6 — Top 3
- Combinar: commitments due + projects com `next_action` e `last_touched > 7d`
- **Pergunte ao operador**: "concorda com essas 3, ou quer ajustar?"
- Não imponha. Sugestão calibra pela aceitação ao longo de semanas.

## Regras de qualidade

- **Brief tem que caber em 1 tela.** Se passa, você está incluindo ruído.
- **Cada item tem ação clara ou é cortado.** "FYI" não é brief.
- **Commitments vencendo são highlight visual** (ex.: ⚠️). Não enterre.
- **Não inclua tudo do calendário** — só o que precisa de prep ou onde operador é dono.

## Atualização de estado ao final

```json
{
  "rituals.last_morning_brief": "<ISO timestamp>",
  "today.date": "<YYYY-MM-DD>",
  "today.meetings": [<ids>],
  "today.commitments_due": [<ids>],
  "today.top_3_priorities": [<strings>],
  "mode.current": "active_day"
}
```

## Integração com Google Workspace

- **gcalendar**: listar eventos, ler descrição/anexos pra detectar prep necessário
- **gdocs**: salvar brief em `Drive/EA/daily/<YYYY-MM-DD>.md` (mirror do state/)
- **gchat**: opcional — postar resumo num espaço pessoal

## Anti-padrões

- ❌ Brief de 3 páginas com todo email do dia
- ❌ "Top 5" — força priorização real, fica em 3
- ❌ Listar reuniões sem destacar onde precisa preparação
- ❌ Repetir commitments sem flag de urgência
