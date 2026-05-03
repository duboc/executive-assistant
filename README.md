# Executive Assistant

Chief-of-staff digital sobre Google Workspace. Orquestrador central + subagents
especializados + skills de workflow + hooks que transformam disciplina executiva
em infraestrutura.

**Roda nos dois runtimes:**

- **Claude Code** — config em `.claude/settings.json`, subagents em `.claude/agents/`
- **Gemini CLI** — config em `.gemini/settings.json`, subagents nativos em `.gemini/agents/`, policy isolation em `.gemini/policies/ea-policies.toml`

Skills, hooks e estado são compartilhados.

> **Premissa de ambiente:** as skills de Google Workspace (`gdocs`, `gdrive`,
> `gcalendar`, `gchat`, `gsheets`, `gslides`) já estão disponíveis no runtime
> do operador (como skill nativa, MCP server, ou extension). Os subagents/skills
> aqui apenas as compõem.

## Arquitetura — visão de 30 segundos

```
ORQUESTRADOR (ea-orchestrator skill)
   ├─ SKILLS de workflow:    daily-brief, weekly-review, noise-cancel,
   │                         meeting-workflow, quarterly-review
   ├─ SUBAGENTS (8):         inbox-triager, meeting-prepper, meeting-debriefer,
   │                         project-router, project-tracker, commitment-tracker,
   │                         relationship-keeper, draft-composer
   ├─ SKILLS pré-existentes: gdocs · gdrive · gcalendar · gchat · gsheets · gslides
   └─ HOOKS (12 scripts):    SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/
                             Stop/PreCompact/SessionEnd  (Claude Code)
                             SessionStart/BeforeAgent/BeforeToolSelection/BeforeTool/
                             AfterTool/AfterModel/PreCompress/SessionEnd  (Gemini CLI)
```

Detalhe completo: [ARCHITECTURE.md](./ARCHITECTURE.md).

## Quickstart por runtime

### Rodando no Claude Code

1. Abra uma sessão neste diretório.
2. Edite `state/ea-state.json` com seus dados de operador.
3. Adicione projetos em `state/projects/<id>.yaml` e atualize `state/projects/_index.json`.
4. Adicione pessoas-chave em `state/people/<id>.yaml`.
5. Diga "bom dia" — o hook `bootstrap.sh` carrega estado e infere modo. Para ritual semanal, rode `/weekly-review`.

### Rodando no Gemini CLI

1. Sincronize skills (idempotente):
   ```bash
   ./scripts/sync-runtimes.sh
   ```
2. Inicie `gemini` neste diretório. `.gemini/settings.json` carrega automaticamente:
   - **Hooks** (mesmos scripts que Claude Code, referenciados via `$GEMINI_PROJECT_DIR/.claude/hooks/...`)
   - **Subagents** em `.gemini/agents/` (8 hand-tuned com handoffs estruturados)
   - **Agent overrides** com `maxTurns`/`maxTimeMinutes` por subagent
3. Para isolation forte, copie `.gemini/policies/ea-policies.toml` para `~/.gemini/policies/` (ou aponte via setting do Policy Engine). Ele restringe o que cada subagent pode escrever.
4. Invoque subagent explicitamente: `@meeting-prepper preparar 1:1 com Laiane às 10h` ou deixe a delegação automática decidir.

### Diferença de orquestração

| | Claude Code | Gemini CLI |
|---|---|---|
| Subagent → subagent | ✅ permitido | ❌ proibido (recursion guard) |
| Coordenação | subagent ou orquestrador | **sempre** orquestrador |
| Padrão de output | livre | **handoffs[]** estruturado obrigatório |

Os arquivos em `.gemini/agents/` já refletem esse padrão.

## Estrutura de diretórios

```
.
├── ARCHITECTURE.md
├── README.md
├── .claude/
│   ├── settings.json              # wiring de hooks + permissões
│   ├── skills/
│   │   ├── ea-orchestrator/SKILL.md
│   │   ├── daily-brief/SKILL.md
│   │   ├── weekly-review/SKILL.md
│   │   ├── noise-cancel/SKILL.md
│   │   ├── meeting-workflow/SKILL.md
│   │   └── quarterly-review/SKILL.md
│   ├── agents/
│   │   ├── inbox-triager.md
│   │   ├── meeting-prepper.md
│   │   ├── meeting-debriefer.md
│   │   ├── project-router.md
│   │   ├── project-tracker.md
│   │   ├── commitment-tracker.md
│   │   ├── relationship-keeper.md
│   │   └── draft-composer.md
│   └── hooks/
│       ├── lib/common.sh
│       ├── bootstrap.sh             # SessionStart
│       ├── ritual-check.sh          # SessionStart
│       ├── mode-context.sh          # UserPromptSubmit
│       ├── filter-skills-by-mode.sh # PreToolUse
│       ├── check-pending-debriefs.sh# PreToolUse (meeting-prepper)
│       ├── enter-review-mode.sh     # PreToolUse (weekly/quarterly)
│       ├── touch-projects.sh        # PostToolUse
│       ├── scan-commitments.sh      # PostToolUse
│       ├── promise-detector.sh      # Stop
│       ├── project-mention-tracker.sh # Stop
│       ├── preserve-crm.sh          # PreCompact
│       └── eod-snapshot.sh          # SessionEnd
├── state/
│   ├── ea-state.json
│   ├── projects/
│   │   └── _index.json
│   ├── people/
│   ├── commitments/
│   │   ├── made-by-operator.json
│   │   ├── made-to-operator.json
│   │   └── implicit.json
│   └── rituals/
│       ├── daily/
│       ├── weekly/
│       ├── quarterly/
│       └── meetings/
└── templates/
    ├── ea-state.template.json
    ├── project.template.yaml
    ├── person.template.yaml
    └── commitment.template.json
```

## Quickstart

1. **Edite `state/ea-state.json`** com seus dados de operador (nome, role,
   focos atuais). O template já vem preenchido com defaults sensatos.

2. **Adicione projetos ativos** copiando `templates/project.template.yaml` para
   `state/projects/<id>.yaml` e atualizando `state/projects/_index.json`.

3. **Adicione pessoas-chave** (gerente, reportes diretos, mentor, ~10 pessoas
   prioritárias) copiando `templates/person.template.yaml` para
   `state/people/<id>.yaml`.

4. **Verifique hooks**: `chmod +x .claude/hooks/*.sh` (já feito no setup).

5. **Inicie uma sessão Claude Code neste diretório**. O hook
   `bootstrap.sh` carrega seu estado e infere o modo. Se for de manhã,
   peça `/daily-brief` ou apenas "bom dia".

6. **Sexta ou sábado**: rode `/weekly-review`. Os hooks travam outras skills
   até o ritual concluir.

## Como o loop funciona

### Manhã

```
06:30  SessionStart
   → bootstrap.sh        carrega ea-state.json, detecta hour < 11
                         e last_morning_brief != hoje → mode = morning_brief
   → ritual-check.sh     verifica next_weekly_due

06:31  Operador: "bom dia"
   → UserPromptSubmit/mode-context.sh injeta:
     "Modo morning_brief. Skill recomendada: daily-brief."

06:31  ea-orchestrator chama Skill:daily-brief
   → daily-brief usa gcalendar para listar agenda
   → delega ao inbox-triager (subagent) classificação de email
   → delega ao noise-cancel para auto-archive
   → produz brief de 1 página em state/rituals/daily/2026-05-02.md
   → mode → active_day
```

### Antes de meeting

```
09:55  Webhook calendar (T-30min meeting "1:1 Laiane")
   → ea-orchestrator detecta proximidade → mode = meeting_prep
   → invoca Skill:meeting-workflow phase=prep
   → hook check-pending-debriefs.sh:
     - verifica se há prep sem debrief de meetings anteriores
     - se houver: BLOQUEIA. operador faz debrief antes.
   → meeting-prepper subagent gera prep doc (5 seções)
   → salva em state/rituals/meetings/<event>-prep.md + gdocs
```

### Depois de meeting

```
10:35  Operador cola notas brutas
   → ea-orchestrator → meeting-workflow phase=debrief
   → meeting-debriefer extrai DECISÕES, AÇÕES, IMPLÍCITOS
   → commitment-tracker registra commitments (perguntando antes em implícitos)
   → project-router roteia ações para projetos
   → project-tracker atualiza next_action / blockers / decisions
   → relationship-keeper atualiza last_contact / threads
```

### Weekly review (sex/sáb)

```
SessionStart sex
   → ritual-check.sh detecta next_weekly_due ≤ hoje
   → injeta sugestão: "rodar /weekly-review antes de qualquer coisa"

Operador: /weekly-review
   → enter-review-mode.sh sets mode = weekly_review
   → filter-skills-by-mode.sh trava todas as outras skills
   → weekly-review skill conduz 7 fases em diálogo
   → cada fase atualiza estado
   → ao final: rituals.next_weekly_due = +7d, mode → active_day
```

### Compactação de contexto (sessões longas)

```
contexto enche → Claude Code dispara PreCompact
   → preserve-crm.sh salva snapshot de top-3, projetos ativos, commitments
     em state/.snapshots/precompact-<ts>.md
   → injeta: "Após compactação, releia esse arquivo e ea-state.json"
```

### Fim do dia

```
SessionEnd
   → eod-snapshot.sh gera state/rituals/daily/<date>-eod.md
   → reseta contadores diários
   → mode → active_day
```

## Princípios operacionais

| Princípio | Significado |
|---|---|
| Delegate, don't duplicate | Orquestrador coordena; subagents/skills analisam. |
| Estado externo é fonte da verdade | Memória do modelo é volátil. Releia antes de agir. |
| Rituais não são opcionais | Hooks tornam pulá-los impossível. |
| Nada fica sem rota | Todo sinal entra em projeto, pessoa ou backlog explícito. |
| Toda skill produz decisão ou estado | Resumo é overhead. Mudança de estado é alavancagem. |
| Calibração contínua | Roteador, filtro de ruído e ritual evoluem por feedback. |
| Profundidade > velocidade | Use múltiplos turnos. Análise rasa é falha de orquestração. |
| Resumível por design | Estado em arquivo torna o sistema robusto a interrupções. |

## Customizando

- **Modo lock**: edite `filter-skills-by-mode.sh` para adicionar novos modos
  travados ou suavizar travamentos.
- **Filtros de ruído**: comece editando `state/ea-state.json :: noise_filters`.
  A skill `noise-cancel` aprende e propõe ajustes na fase 7 da weekly review.
- **Cadência de pessoas**: declare em `state/people/<id>.yaml :: cadence` para
  receber alertas quando o ritmo de contato é violado.
- **Webhooks**: o disparo automático de `meeting_prep`/`meeting_debrief` baseado
  no calendário é integração externa (Cloud Function que invoca o orquestrador).
  Sem ela, o operador chama `/meeting-prep <event_id>` manualmente.

## O que NÃO está aqui

- Implementação das skills de Google Workspace — são pré-existentes no ambiente.
- Cloud Function de webhook para auto-disparar fases de meeting.
- Dashboards/visualização — focado em texto. Adicionar `visual-explainer` skill
  se quiser HTML.
- Self-healing avançado para skills que falham — é uma extensão futura sobre
  `PostToolUse` com `tool_response.error`.

## Licença

MIT — ver [LICENSE](./LICENSE).
