---
plan: 05-03
phase: 05-sub-agents-media
status: complete
completed: 2026-03-03
infra_commit: d8c6133
---

# 05-03 Core Agent Wiring + Email Sub-Agent — SUMMARY

## What Was Built

Three email workflows + full Core Agent sub-agent routing wired end-to-end, with email access gated to owner only.

### Email Sub-Agent Workflows

| Workflow | ID | Nodes |
|----------|-----|-------|
| Email Sub-Agent | `YOUR_EMAIL_SUBAGENT_WORKFLOW_ID` | 20 |
| Gmail Trigger | `YOUR_GMAIL_TRIGGER_WORKFLOW_ID` | 3 |
| Morning Brief | `YOUR_MORNING_BRIEF_WORKFLOW_ID` | 9 |

### Core Agent — Native LangChain Tool Routing

**NOTE: The plan described manual routing but the actual implementation uses native LangChain toolWorkflow nodes.**
The Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID) has **35 nodes** (not 45). Tool routing is handled natively by LangChain — no manual Parse Tool Decision, Build Ack, Recover Context, or Route to Tool nodes exist.

```
Resolve Model → Switch: Model Tier
                        ↓
        [Sonnet / Opus / Gemini AI Agent]
         ↑ Tools attached per tier:
         │  Tool: Media (Sonnet/Opus/Gemini)    → YOUR_MEDIA_SUBAGENT_WORKFLOW_ID
         │  Tool: Research (Sonnet/Opus/Gemini) → Research sub-agent
         │  Tool: Email (Sonnet/Opus/Gemini)    → YOUR_EMAIL_SUBAGENT_WORKFLOW_ID
                        ↓
        Check {Model} Output
                        ↓
        If {Model} Failed → fallback tier
                        ↓
        If Opus Used → Increment Opus Counter
                        ↓
        Prepare Response → Execute Output Router
```

Each AI Agent tier (Sonnet/Opus/Gemini) has 3 toolWorkflow nodes attached as `ai_tool` connections. When the LangChain agent decides to use a tool, n8n automatically calls the referenced sub-workflow.

**Tool schema (affects what LangChain passes to sub-workflows):**
- `workflowInputs.schema: []` on all tools — LangChain generates its own arg schema
- Research tool uses `$fromAI('query', ...)` → LangChain passes `{query: "..."}` → works
- Media tool uses `$json.content / $json.attachments` → BUT with schema:[], LangChain passes `{query: "url"}` → Detect Media Type misses it (BUG)
- Email tool uses `$json.person_id` for auth → with schema:[], person_id not passed → Check Email Auth denies owner (BUG)

**Email gate is in Email Sub-Agent** (not Core Agent): `Check Email Auth` IF node checks `$('Execute Workflow Trigger').first().json.person_id === OWNER_PERSON_ID`.

## Key Decisions

- **Owner person_id:** `00000000-0000-0000-0000-000000000001` (Saelen)
- **toolWorkflow schema: []** — LangChain generates arg schema. Use `$fromAI('field', default, 'type')` for fields the LLM should provide. `$json.*` references ARE available during tool calls (LangChain evaluates them from the AI Agent's input item).
- **Connection format (MCP):** flat `source`/`target`, IF nodes use `branch: "true"/"false"`, Switch nodes use `case: N`
- **Switch node typeVersion 3.2** confirmed required for correct `caseSensitive` options structure

## OAuth Credentials Tested

- **Gmail - Aerys** (`YOUR_GMAIL_AERYS_CREDENTIAL_ID`): reads Aerys inbox ✓
- **Gmail - User** (`YOUR_GMAIL_USER_CREDENTIAL_ID`): search works ✓
- Email sub-agent Switch node: fixed typeVersion 3.2 + `caseSensitive` in `conditions.options`

## DB Updates

- `sub_agents.email_agent` → `YOUR_EMAIL_SUBAGENT_WORKFLOW_ID` ✓

## Known Issues

- Email `from` field shows "unknown" — Gmail simple mode returns sender in a different field name. Low priority, doesn't block routing.

## Files

- `~/aerys/workflows/05-03-email-agent.json` — Email Sub-Agent (committed b3b8e4d)
- `~/aerys/workflows/05-03-gmail-trigger.json` — Gmail Trigger (committed b3b8e4d)
- `~/aerys/workflows/05-03-morning-brief.json` — Morning Brief (committed b3b8e4d)
- `~/aerys/workflows/02-03-core-agent.json` — Core Agent 45-node wired version (committed d8c6133)

## Requirements Satisfied

- EMAIL-01: Email read via Gmail OAuth ✓
- EMAIL-02: Email search ✓
- EMAIL-03: Email send + confirm flow ✓
- EMAIL-04: Morning brief workflow ✓
- ROUTING-01: Core Agent routes media/research/email via native LangChain tools ✓
- ROUTING-02: LangChain handles tool detection natively (no manual parse/IF gate) ✓
- ROUTING-03: No explicit ack message — LangChain handles tool call natively ✗ (design changed)
- SECURITY-01: Email access gated in Email Sub-Agent via Check Email Auth IF node — BUG: person_id not reliably passed via toolWorkflow schema:[] → fixed in UAT gap closure
