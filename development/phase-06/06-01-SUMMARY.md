---
phase: 06-polish-hardening
plan: 01
status: complete
started: 2026-03-09T00:30:00.000Z
completed: 2026-03-09T01:35:00.000Z
duration_minutes: 65
commits_infra: [30884ae, a0a94f6]
workflow_ids:
  eval_suite: YOUR_EVAL_SUITE_WORKFLOW_ID
---

# 06-01 Summary: Eval Baseline

## What Was Built

LLM-as-judge eval suite that scores Aerys responses 1-5 against expected behavior criteria. Establishes numeric baseline before Phase 6 architectural changes.

**Artifacts:**
- `~/aerys/evals/baseline.json` — 25 test cases across 5 categories
- n8n workflow `YOUR_EVAL_SUITE_WORKFLOW_ID` ("06-01 Eval Suite") — 10-node pipeline: Manual Trigger → Load Dataset → SplitInBatches → Build Test Input → Execute Core Agent → Capture Response → Build Judge Request → LLM Judge → Parse Score → Format Report
- Docker-compose updated with evals volume mount (`~/aerys/evals:/home/node/aerys-evals:ro`)

## Baseline Scores (2026-03-09)

| Category | Avg Score | Count | Min | Max | Avg Response (ms) |
|----------|-----------|-------|-----|-----|--------------------|
| **Overall** | **3.88** | 25 | 2 | 5 | ~7,000 |
| edge_case | 4.60 | 5 | 4 | 5 | 5,049 |
| email | 4.33 | 3 | 4 | 5 | 7,294 |
| media | 4.00 | 3 | 2 | 5 | 7,157 |
| normal_conversation | 3.80 | 10 | 2 | 5 | 6,292 |
| research | 2.75 | 4 | 2 | 4 | 7,298 |

**Key findings:**
- Research category weakest (2.75) — Core Agent answers from memory/chat history instead of invoking research sub-agent. Validates 06-02 architecture split.
- Edge cases strongest (4.60) — Aerys handles empty input, prompt injection, identity questions well.
- Chat history contamination from eval run 1 (broken pipeline) depressed ~5 scores. True baseline likely ~4.1.
- tc-02 hit DNS error on Discord API send — existing retryOnFail pattern needed (addressed in 06-03).

## Bugs Fixed During Deployment

1. **executeWorkflow typeVersion 2 "not installed" in UI** — blocks manual execution. User re-added node via UI (typeVersion 1.1). Todo created: audit-uninstalled-nodes.
2. **HTTP Request credential auth** — `authentication: "genericCredentialType"` + `genericAuthType: "httpHeaderAuth"` required for credentials to apply. Without them, silently unauthenticated.
3. **Core Agent field name mismatch** — expects `message_text` not `content`. Build Test Input rewritten to match DM adapter payload format.
4. **Capture Response context black hole** — read `testInput.content` (undefined) instead of `testInput.message_text` after LangChain agent stripped input fields. Fixed to `$('Build Test Input').item.json.message_text`.

## Deviations from Plan

- n8n Variables (AERYS_DEBUG_CHANNEL_ID, etc.) are Enterprise-only — Community Edition doesn't support them. Will hardcode in Code nodes when needed in 06-03/06-04.
- Eval messages route to #aerys-debug (channel_id YOUR_DEBUG_CHANNEL_ID) via Output Router — unavoidable without modifying Core Agent.
- Temp workflow awjAFcQ7bGaf90Wy created to extract chat histories — delete after eval cleanup.

## Cleanup Required

After all Phase 6 eval runs complete:
- Purge eval entries from `n8n_chat_histories` (session_id `00000000-0000-0000-0000-000000000001`, time window 2026-03-09 00:30 to end of evals)
- Check for eval-generated memories in `memories` table (same time window)
- Delete temp workflow awjAFcQ7bGaf90Wy
