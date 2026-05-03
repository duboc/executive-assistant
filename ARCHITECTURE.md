# Executive Assistant — Arquitetura

> Chief-of-staff digital sobre Google Workspace. Orquestrador central, subagents
> especializados, skills de workflow e hooks que transformam disciplina executiva
> em infraestrutura.

## 1. Filosofia

Três coisas que diferenciam um EA de uma automação genérica:

1. **Noise canceling** — filtra ruído **antes** que chegue ao operador.
2. **Continuity** — mantém contexto entre dias, projetos e pessoas. O operador
   nunca re-explica o que já decidiu.
3. **Forcing functions** — impõe rituais (weekly review, sub-project routing,
   debrief pós-meeting) que o operador sozinho falharia em manter.

Divisão de responsabilidades:

- **Skills** fazem o trabalho cognitivo de workflow (rituais, briefs).
- **Subagents** fazem o trabalho cognitivo isolado e profundo (triagem, drafting).
- **Hooks** impõem disciplina operacional (estado, gates, modo).
- **Orquestrador** decide o quê, quando e pra quem.

## 2. Tipologia das Camadas

```
┌────────────────────────────────────────────────────────────────┐
│ ORQUESTRADOR EA — chief-of-staff loop                          │
│ Modo (manhã/dia/meeting/review/EOD) → seleciona skill/subagent │
└────────────────────────────────────────────────────────────────┘
        │
        ├── SKILLS (workflows com forcing function)
        │   ├─ ea-orchestrator       ─ entry point + modo
        │   ├─ daily-brief           ─ ritual matinal
        │   ├─ weekly-review         ─ ritual semanal (7 fases)
        │   ├─ noise-cancel          ─ triagem de ruído com aprendizado
        │   └─ meeting-workflow      ─ prep → execute → debrief
        │
        ├── SUBAGENTS (cognição isolada)
        │   ├─ inbox-triager         ─ classifica e prioriza Gmail
        │   ├─ meeting-prepper       ─ briefing pré-meeting
        │   ├─ meeting-debriefer     ─ extrai ações pós-meeting
        │   ├─ project-router        ─ roteia sinais a projetos
        │   ├─ project-tracker       ─ mantém estado de projetos
        │   ├─ commitment-tracker    ─ rastreia promessas
        │   ├─ relationship-keeper   ─ CRM pessoal
        │   └─ draft-composer        ─ escreve respostas/mensagens
        │
        ├── SKILLS PRÉ-EXISTENTES (Google Workspace)
        │   gdocs · gdrive · gcalendar · gchat · gsheets · gslides
        │
        └── HOOKS (disciplina operacional)
            SessionStart · UserPromptSubmit · PreToolUse · PostToolUse
            Stop · PreCompact · SessionEnd
```

### Skill vs. Subagent — quando usar cada um

| Critério | Skill | Subagent |
|---|---|---|
| Loop multi-fase com gates | ✅ | ❌ |
| Cognição profunda em um turno | ❌ | ✅ |
| Forcing function (ritual) | ✅ | ❌ |
| Composição de várias ferramentas | ✅ | ✅ |
| Contexto isolado (não polui main) | ❌ | ✅ |
| Invocado pelo operador (`/weekly-review`) | ✅ | indireto |
| Invocado por outra skill | ✅ | ✅ |

Regra prática: **skills coreografam, subagents executam**.

## 3. Estado Persistente

Tudo escrito em `state/` na raiz do repositório. Arquivos pequenos, JSON/YAML,
fáceis de auditar e versionar.

```
state/
├── ea-state.json              # estado raiz: operator, mode, today, rituals
├── projects/
│   ├── <project-id>.yaml      # um por projeto ativo
│   └── _index.json            # mapa id → nome, status, last_touched
├── people/
│   └── <person-id>.yaml       # CRM pessoal
├── commitments/
│   ├── made-by-operator.json  # promessas do operador
│   ├── made-to-operator.json  # promessas pro operador
│   └── implicit.json          # zona cinza ("vou ver", "te mando")
└── rituals/
    ├── daily/<YYYY-MM-DD>.md  # daily briefs arquivados
    ├── weekly/<YYYY-WW>.md    # weekly reviews
    └── quarterly/<YYYY-QN>.md # quarterly reviews
```

**Regra dura:** todo subagent que muta estado o faz via patch JSON, nunca
re-escreve o arquivo inteiro. Hooks `PostToolUse` aplicam o patch.

## 4. Modos do Orquestrador

O orquestrador opera em modos. Cada modo restringe quais skills/subagents
ficam disponíveis. Hooks `UserPromptSubmit` e `PreToolUse` enforçam.

| Modo | Quando | Skills disponíveis |
|---|---|---|
| `morning_brief` | 06:00–09:00 ou primeiro prompt do dia | daily-brief, noise-cancel |
| `active_day` | dia útil normal | inbox-triager, project-router, draft-composer, meeting-workflow |
| `meeting_prep` | T-30min antes de evento no gcalendar | meeting-prepper, relationship-keeper |
| `meeting_debrief` | T+5min após evento | meeting-debriefer, commitment-tracker |
| `weekly_review` | sex/sáb se atrasado >7d | **só** weekly-review (trava outras) |
| `quarterly_review` | trimestral | **só** quarterly-review |
| `end_of_day` | 18:00+ | eod-snapshot, commitment review |

## 5. Hooks — Mapeamento Claude Code

A semântica do Gemini CLI mapeia em Claude Code assim:

| Gemini CLI       | Claude Code        | Função no EA |
|---|---|---|
| SessionStart     | SessionStart       | Bootstrap de estado, ritual check |
| BeforeAgent      | UserPromptSubmit   | Injeta contexto do modo, força ritual atrasado |
| BeforeModel      | UserPromptSubmit   | (mesmo evento, ações distintas no script) |
| BeforeToolSelection | PreToolUse      | Filtro de skill/subagent por modo |
| BeforeTool       | PreToolUse         | Validação de pré-condições da skill |
| AfterTool        | PostToolUse        | Atualiza estado, scan de commitments |
| AfterModel       | Stop               | Detecta promessas implícitas, project mentions |
| PreCompress      | PreCompact         | Preserva CRM e ADRs |
| SessionEnd       | SessionEnd         | EOD snapshot |

## 6. Loop Diário (Exemplo)

```
06:30  SessionStart
       └─ bootstrap.sh        carrega ea-state.json
       └─ ritual-check.sh     "weekly review atrasado 8d → modo=weekly_review"
                              OU "modo=morning_brief, daily-brief pendente"

06:31  UserPromptSubmit ("bom dia")
       └─ mode-context.sh     injeta contexto do modo + 3 prioridades de ontem

06:32  /daily-brief           skill ea-orchestrator → daily-brief
       ├─ chama gcalendar     lista eventos hoje
       ├─ chama subagent inbox-triager  classifica novos emails
       ├─ chama noise-cancel  arquiva ruído puro
       └─ produz brief de 1 página em state/rituals/daily/2026-05-02.md

09:55  webhook calendar (T-30min meeting "1:1 Laiane")
       └─ hook agenda meeting_prep mode
       └─ subagent meeting-prepper roda automaticamente

10:30  meeting acontece (operador toma notas brutas no gdocs)

10:35  webhook calendar (evento terminou)
       └─ subagent meeting-debriefer → extrai ações
       └─ commitment-tracker registra "vou mandar o doc Y pra Laiane sex"
       └─ project-router roteia ações para projetos certos

18:30  SessionEnd
       └─ eod-snapshot.sh     resume dia, fecha state, agenda manhã
```

## 7. Princípios Operacionais

| Princípio | Significado |
|---|---|
| Delegate, don't duplicate | Orquestrador coordena; subagents/skills analisam. |
| Estado externo é fonte da verdade | Memória do modelo é volátil. Sempre releia o estado. |
| Rituais não são opcionais | Hooks tornam pulá-los impossível. |
| Nada fica sem rota | Todo sinal entra em projeto, pessoa ou backlog. Órfão = falha. |
| Toda skill produz decisão ou estado | Resumo é overhead. Mudança de estado é alavancagem. |
| Calibração contínua | Roteador, filtro de ruído e ritual evoluem por feedback. |
| Profundidade > velocidade | Use múltiplos turnos. Análise rasa é falha de orquestração. |
| Resumível por design | Estado em arquivo torna o sistema robusto a interrupções. |

## 8. Anti-padrões

- **Skill que só resume.** Resumo sem mudança de estado é trabalho ornamental.
- **Subagent que escreve direto no estado raiz.** Sempre via patch + hook.
- **Hook lento (>500ms).** Bloqueia o loop. Faça async se precisar pesar.
- **Forcing function que pode ser pulada.** Se "lembre-me" não funciona, vire bloqueio.
- **Auto-archive sem trilha.** Ruído arquivado precisa ser auditável.
- **Roteador silencioso.** A cada N rotas, pede contra-prova ao operador.

## 9. Escopo do MVP neste repositório

Este repositório implementa:

- `state/` schemas + um state inicial seed
- `.claude/skills/` 6 skills de workflow (canônicas)
- `.claude/agents/` 8 subagents (Claude Code)
- `.claude/hooks/` 12 scripts de disciplina (compartilhados — payload-detect ambos runtimes)
- `.claude/settings.json` wiring completo Claude Code
- `.gemini/skills/` espelhado de `.claude/skills/` via `scripts/sync-runtimes.sh`
- `.gemini/agents/` 8 subagents nativos Gemini CLI (frontmatter + handoffs estruturados)
- `.gemini/policies/ea-policies.toml` regras de Policy Engine isolando o que cada subagent pode escrever
- `.gemini/settings.json` wiring Gemini CLI (eventos diferentes, mesmos scripts)

O que **não** está aqui (depende do ambiente):

- Skills pré-existentes de Google Workspace (gdocs, gdrive, gcalendar, gchat,
  gsheets, gslides). Os subagents/skills aqui assumem que estão disponíveis.
- Webhook do Google Calendar para disparar `meeting_prep`/`meeting_debrief`
  automaticamente — integração externa que invoca o orquestrador.

## 10. Dual runtime — Claude Code & Gemini CLI

A mesma stack (skills + subagents + hooks) roda nos dois runtimes. Diferenças
ficam isoladas em três lugares: settings, nomes de eventos de hook, e a forma
como subagents devolvem trabalho ao orquestrador.

### 10.1 Mapeamento de eventos de hook

| Evento Gemini CLI    | Evento Claude Code  | Script (canônico em `.claude/hooks/`) |
|----------------------|---------------------|--------------------------------------|
| SessionStart         | SessionStart        | bootstrap.sh, ritual-check.sh         |
| BeforeAgent          | UserPromptSubmit    | mode-context.sh                       |
| BeforeModel          | UserPromptSubmit    | (compartilha; usado raramente)        |
| BeforeToolSelection  | PreToolUse          | filter-skills-by-mode.sh              |
| BeforeTool           | PreToolUse          | check-pending-debriefs.sh, enter-review-mode.sh |
| AfterTool            | PostToolUse         | touch-projects.sh, scan-commitments.sh |
| AfterModel           | Stop                | promise-detector.sh, project-mention-tracker.sh |
| PreCompress          | PreCompact          | preserve-crm.sh                       |
| SessionEnd           | SessionEnd          | eod-snapshot.sh                       |
| Notification         | Notification        | (não usado no MVP)                    |

`lib/common.sh` resolve `EA_ROOT` de `CLAUDE_PROJECT_DIR` ou `GEMINI_PROJECT_DIR`
e expõe helpers (`ea_payload_tool_name`, `ea_payload_sub`, `ea_payload_last_text`)
que normalizam payloads (camelCase do Gemini vs snake_case do Claude Code).

### 10.2 Diferença crítica: subagents Gemini não recursionam

Doc oficial Gemini CLI:
> "Recursion protection: To prevent infinite loops and excessive token usage,
> subagents cannot call other subagents."

Em Claude Code subagents podem se chamar (via Skill/Agent tools). Em Gemini
CLI **não**. O orquestrador (main agent) é quem coordena handoffs.

**Padrão obrigatório nos subagents Gemini:** devolver um campo `handoffs[]`
no output que o orquestrador lê e despacha. Exemplo do `meeting-debriefer`:

```json
{
  "decisions": [...],
  "actions": [...],
  "handoffs": [
    { "to": "subagent:project-router",     "action": "route", "items": ["ACT-001"] },
    { "to": "subagent:commitment-tracker", "action": "add_batch", "commitments": [...] },
    { "to": "subagent:relationship-keeper","action": "apply_mutations", "items": [...] },
    { "to": "operator", "action": "confirm_implicits", "items": [...] }
  ]
}
```

O orquestrador executa os handoffs em ordem. Em Claude Code, esse padrão também
funciona, mas o subagent ainda **pode** invocar outro diretamente se preciso.

### 10.3 Mapeamento de tools

Subagents declaram tools no frontmatter. Nomes diferem:

| Capacidade        | Claude Code          | Gemini CLI                 |
|-------------------|----------------------|----------------------------|
| Read file         | `Read`               | `read_file`                |
| Write file        | `Write`              | `write_file`               |
| Edit file         | `Edit`               | `replace` / `edit_file`    |
| Search            | `Grep`               | `grep_search`              |
| Glob              | `Glob`               | `glob`                     |
| Shell             | `Bash(jq:*)`         | `run_shell_command` (granularidade via Policy Engine) |
| Skill invocation  | `Skill`              | `@<skill-name>` ou auto    |
| Agent invocation  | `Agent`/`Task`       | `@<agent-name>` ou tool por nome |
| MCP               | `mcp__server__tool`  | `mcp_server_*` wildcards   |

### 10.4 Fonte da verdade vs cópia

| Asset                    | Fonte canônica                | Espelho                       |
|--------------------------|-------------------------------|-------------------------------|
| Skills                   | `.claude/skills/`             | `.gemini/skills/` (via sync)  |
| Subagents — Claude       | `.claude/agents/`             | (não espelha)                 |
| Subagents — Gemini       | `.gemini/agents/`             | (não espelha)                 |
| Hooks                    | `.claude/hooks/`              | (não espelha; Gemini referencia mesmo path) |
| State                    | `state/`                      | (compartilhado entre runtimes) |
| Policy (Gemini)          | `.gemini/policies/ea-policies.toml` | (Claude usa `permissions` em settings.json) |

`scripts/sync-runtimes.sh` mantém só skills em sincronia (formato é compatível).
Subagents são fonte separada porque os modelos de orquestração são diferentes.

### 10.5 Quando atualizar o quê

| Mudança                                    | Editar                                          | Sync? |
|-------------------------------------------|------------------------------------------------|-------|
| Lógica de skill (workflow)                | `.claude/skills/<name>/SKILL.md`               | ✅ rodar `scripts/sync-runtimes.sh` |
| Subagent só Claude                        | `.claude/agents/<name>.md`                     | —     |
| Subagent só Gemini                        | `.gemini/agents/<name>.md`                     | —     |
| Hook script                                | `.claude/hooks/<file>.sh`                      | — (referenciado por ambas configs) |
| Permissão Claude                          | `.claude/settings.json :: permissions.allow`   | —     |
| Permissão Gemini (granular por subagent)  | `.gemini/policies/ea-policies.toml`            | —     |
| Wiring de hook em runtime                 | `.claude/settings.json` ou `.gemini/settings.json` | —  |
