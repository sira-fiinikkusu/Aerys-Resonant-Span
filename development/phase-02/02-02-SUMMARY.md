---
phase: 02-core-agent-channels
plan: 02-02
status: complete
completed: 2026-02-19
---

## What Was Built

Core Aerys agent workflow (`02-03-core-agent`, n8n ID: `YOUR_CORE_AGENT_WORKFLOW_ID`, active).

**Pipeline:** Execute Workflow Trigger → Load Config → Intent Classifier (Haiku/OpenRouter) → Parse Classification → Check Opus Daily Usage → Resolve Model (cost guard) → Switch: Model Tier (opus/haiku/sonnet explicit) → AI Agent (Sonnet/Opus/Haiku, each with OpenRouter Chat Model + Postgres Chat Memory) → fallback chain (opus→sonnet→haiku→static error) → If Opus Used → Increment Opus Counter → Prepare Response.

Both channel adapters (Discord 02-01, Telegram 02-02) wired to call this workflow.

## Checkpoint Verification: PASSED

- Intent Classifier: code_help / sonnet ✓
- Switch: routed to AI Agent (Sonnet) ✓
- AI Agent (Sonnet): Aerys-personality response produced ✓
- Prepare Response: raw_response + source: core_agent ✓

## Issues Fixed During Checkpoint

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Intent Classifier error | `predefinedCredentialType: openRouterApi` invalid for HTTP Request | `genericCredentialType: httpHeaderAuth` (cred: YOUR_OPENROUTER_HEADER_CREDENTIAL_ID) |
| Load Config `require('fs')` blocked | n8n task runner sandbox blocks fs module | Inlined soul + models config in Code node |
| n8n Variables unavailable | Paid license feature on community edition | Inlined config workaround |
| Postgres empty result stops execution | 0-row result kills downstream | Subquery: `SELECT COALESCE((SELECT call_count ...), 0) AS count` |
| Switch doesn't route sonnet | `fallbackOutput: extra` unreliable in Switch v3.2 | Explicit sonnet rule added |
| Postgres Chat Memory "No session ID" | `sessionIdType` defaults to reading `sessionId` input field | Set `sessionIdType: customKey` on all 3 memory nodes |
| n8n OOM crash on AI Agent | LangChain + Discord IPC + Task Runner exceeds 1G container | Container 1G→2G, `NODE_OPTIONS: --max-old-space-size=1536` |
| Merge Responses error | Merge node errors when 3 inputs wired but only 1 fires | Removed Merge node, branches wire directly to If Opus Used |

## Key Decisions

- Soul prompt inlined in Load Config Code node — update node JS when soul.md changes
- n8n community edition: no Variables, no fs in Code nodes — documented for distribution
- n8n container memory raised to 2GB — required for LangChain on Tachyon
- Merge node unusable for single-firing branches — use direct multi-upstream wiring

## Artifacts

- `~/aerys/workflows/02-03-core-agent.json`
- `~/aerys/workflows/02-01-discord-adapter.json` (Execute Core Agent wired)
- `~/aerys/workflows/02-02-telegram-adapter.json` (Execute Core Agent wired)
- `n8n_chat_histories` table auto-created in aerys DB on first AI Agent execution
