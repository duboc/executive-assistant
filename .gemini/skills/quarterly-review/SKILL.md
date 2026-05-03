---
name: quarterly-review
description: Ritual trimestral. Mata projetos dormentes, recalibra north stars, audita filtros de ruído acumulados. Forcing function que bloqueia novo trimestre sem revisão.
allowed-tools: Read, Write, Edit, Bash(jq:*), Bash(date:*), Skill(gdocs), Agent
---

# Quarterly Review

Roda 4x ao ano. Hook bloqueia início de novo trimestre (1º dia útil de
jan/abr/jul/out) sem completar este ritual.

## Fases

### Fase 1 — North stars
Para cada projeto com status ≠ sunset: `north_star` ainda é verdadeira? Mudou
o que está em jogo? Operador re-escreve ou confirma cada uma.

### Fase 2 — Sunset bulk
Projetos com status `dormant` há >60d: confirmar sunset. Mover arquivos para
`state/projects/_archive/<YYYY-Q>/`.

### Fase 3 — Audit de ruído
Olhar `noise_filters.learning_log` acumulado do trimestre. Quais padrões foram
úteis (zero corrections)? Quais foram problemáticos (>10% corrections)?
Promover/depreciar.

### Fase 4 — Cadências de relacionamento
Para cada `state/people/<id>.yaml` com `cadence.expected_days != null`: o ritmo
foi cumprido? Pessoas silenciosas há >2x cadência: ressuscitar contato ou
remover cadência.

### Fase 5 — Padrões emergentes
Olhar 3 weekly reviews mais recentes. Que padrões aparecem? (Ex: "energia
sempre baixa quartas". "Projeto X aparece em frustrações há 4 semanas".)
Operador decide o que fazer.

### Fase 6 — Próximo trimestre
Top 3 **iniciativas** (não projetos) do trimestre. Mais bruto que weekly,
mais granular que anual.

## Output

`state/rituals/quarterly/<YYYY-QN>.md` com decisões + state mutations
agrupadas. Anexar ao gdoc de quarterly trimestre no Drive.

## Atualização final

```json
{
  "rituals.last_quarterly_review": "<ISO>",
  "rituals.next_quarterly_due": "<ISO + 90d>"
}
```
