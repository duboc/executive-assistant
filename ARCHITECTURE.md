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
- `.claude/skills/` 5 skills de workflow
- `.claude/agents/` 8 subagents
- `.claude/hooks/` 11 scripts de disciplina
- `.claude/settings.json` wiring completo

O que **não** está aqui (depende do ambiente):

- As skills pré-existentes de Google Workspace (gdocs, gdrive, gcalendar, gchat,
  gsheets, gslides). Os subagents/skills aqui assumem que essas estão
  disponíveis e as referenciam por nome.
- Webhook do Google Calendar para disparar `meeting_prep`/`meeting_debrief`
  automaticamente — fica como integração externa que invoca o orquestrador.
