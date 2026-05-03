---
name: meeting-workflow
description: Coordena ciclo completo de meeting (prep → execute → debrief). Trava avanço pra prep se há debrief pendente da reunião anterior com pessoas em comum. Use 30min antes de meeting ou logo após (hook detecta).
allowed-tools: Read, Write, Edit, Bash(jq:*), Bash(date:*), Skill(gcalendar), Skill(gdocs), Agent
---

# Meeting Workflow

Reuniões consomem energia desproporcional ao valor entregue. Esta skill
transforma cada reunião em um ciclo:

```
prep (T-30min) → execute (operador) → debrief (T+5min) → action (estado atualizado)
```

## Forcing function crítica

**Não roda prep se há debrief pendente da reunião anterior com pessoas em comum.**

Hook `check-pending-debriefs.sh` (PreToolUse) verifica isso. Se houver, esta
skill recusa e força o debrief antes. Você **nunca chega numa reunião sem ter
processado a anterior**.

## Fase PREP (T-30min antes)

Delegada ao subagent `meeting-prepper`. Ele produz briefing com 5 partes:

1. **Quem está na sala** — pra cada participante:
   - Último contato (canal, data, tópico) de `state/people/<id>.yaml`
   - Threads abertas relevantes
   - Contexto pessoal mínimo (cargo, projetos compartilhados)

2. **Por que esta reunião existe** — objetivo declarado vs objetivo real
   - Declarado: do convite do calendário
   - Real: inferido do contexto (último 1:1, projetos ativos compartilhados)
   - Se diferentes, sinalizar

3. **O que mudou desde a última** — atualizações em projetos compartilhados
   - Para cada `project_id` em comum: decisões/blockers desde último encontro

4. **3 perguntas que valem fazer** — geradas do contexto, não genéricas
   - Baseadas em `open_decisions` dos projetos compartilhados
   - Baseadas em commitments pendentes de/para os participantes

5. **Resultado desejado** — o que precisa estar verdadeiro ao final
   - Próxima ação acordada? Decisão tomada? Block desbloqueado?

Salvo em `state/rituals/meetings/<event_id>-prep.md` e mirrored em gdocs (anexo
ao evento via `gcalendar`).

## Fase DEBRIEF (T+5min depois)

Delegada ao subagent `meeting-debriefer`. Ele recebe:

- Notas brutas (do operador no gdocs ou bullets jogados no chat)
- Transcript (se disponível via Meet)
- O prep doc gerado anteriormente

Ele extrai (não resume — extrai):

### Decisões tomadas (≠ tópicos discutidos)

- Decisão concreta + dono + reversibilidade

### Ações com dono e prazo

- Operador: vai pro `commitment-tracker` em `made-by-operator.json`
- Outros: vai pro `commitment-tracker` em `made-to-operator.json`
- Por projeto: roteado via subagent `project-router`

### Promessas implícitas

Esta é a parte sutil. Linguagem como:

- "vou dar uma olhada"
- "te mando depois"
- "deixa eu pensar"
- "podemos conversar sobre isso"

**Não vira commitment automaticamente.** O debriefer **pergunta**: "isso é um
commitment? Pra quando? Pra quem?" Resposta entra em `commitments/implicit.json`
com confidence apropriada.

### Atualizações de relacionamento

- `state/people/<id>.yaml :: last_contact = { date, channel: meeting, topic }`
- Threads abertas: fechadas se discussão concluiu, novas se surgiram

### Atualizações de projeto

Via `project-router`: cada ação extraída é roteada para um project_id (existente
ou novo) e o `project-tracker` atualiza `next_action`/`blockers`/`recent_decisions`.

## Saída do debrief

```markdown
# Meeting <título> — <data>

## Decisões
- [DEC-001] X foi decidido por Y, reversível em 7d

## Ações
- [ACT-001] Operador → enviar Z para Pedro até 2026-05-05
- [ACT-002] Pedro → revisar W até 2026-05-07

## Implícitos detectados (aguardando confirmação)
- "vou dar uma olhada na proposta" — pra quem? prazo?

## Estado atualizado
- people/pedro: last_contact, +1 thread aberta
- projects/gympulse: next_action mudou, +1 decisão
```

Salvo em `state/rituals/meetings/<event_id>-debrief.md`.

## Por que essa skill é diferente de "ata automática"

Resumo é overhead. **Estado atualizado é alavancagem.** Cada output da skill
muda algo concreto:
- Novo commitment registrado e rastreado
- Projeto com next_action novo
- Pessoa com thread atualizada
- Decisão com data e reversibilidade

Resumo de meeting que não muda estado é trabalho ornamental.

## Integração com Google Workspace

| Onde | O quê |
|---|---|
| `gcalendar` | Listar evento, ler descrição/attachees, criar eventos de follow-up |
| `gdocs` | Ler notas brutas, salvar prep e debrief em Drive |
| `gchat` | Postar prep doc no espaço da reunião 30min antes (opcional) |

## Anti-padrões

- ❌ Skip do debrief porque "lembro de tudo" — memória decai, estado persiste
- ❌ Aceitar implícito como commitment automaticamente — ruidoso
- ❌ Prep genérico ("preparar pauta") — tem que ser específico ao contexto
- ❌ Debrief que vira ata textual — extrai ações, não transcreve discussão
