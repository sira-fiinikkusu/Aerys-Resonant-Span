---
phase: 06-polish-hardening
plan: 02
subsystem: ai, workflow
tags: [n8n, langchain, polisher, openrouter, sonnet, postgres, soul.md]

requires:
  - phase: 06-01
    provides: "Eval baseline (3.88/5.0) for regression comparison"
  - phase: 05-sub-agents-media
    provides: "Core Agent with soul.md, Output Router with polisher gate, sub-agent tools"
provides:
  - "Core Agent with ~30 token personality shard (soul.md stripped)"
  - "Always-on polisher in Output Router (Sonnet + soul.md + full context)"
  - "SQL write-back updates n8n_chat_histories with polished response"
  - "intermediateSteps passthrough from Core Agent AI Agents to Output Router"
  - "Platform Formatter context recovery pattern (survives Postgres output collapse)"
affects: [06-03, 06-04, 06-05]

tech-stack:
  added: []
  patterns:
    - "Postgres output collapse recovery: read from $('LastGoodNode').item.json not $input"
    - "Polisher prompt architecture: rules in prompt (user message), identity/context in system message"
    - "intermediateSteps JSON.stringify through Execute Workflow schema, JSON.parse back in Output Router"

key-files:
  created: []
  modified:
    - "n8n Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID) — stripped soul.md, added personality shard, enabled returnIntermediateSteps, expanded Execute Workflow inputs"
    - "n8n Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID) — always-on polisher, Build Polisher Context, SQL Write-Back, Platform Formatter context fix"

key-decisions:
  - "Personality shard is ~30 tokens (not 50-100 as planned) — minimal but sufficient for character-appropriate reasoning"
  - "Polisher initially deployed with Sonnet per CONTEXT.md locked decision, later downgraded to Haiku (claude-haiku-4.5) as cost-saving measure — Sonnet unnecessary for voice polishing"
  - "Polisher prompt restructured: rules in prompt (user message), soul.md + context in system message — model treats system message as background, prompt as task instructions"
  - "Platform Formatter reads from $('Set Polished Response').item.json — survives Postgres executeQuery output collapse"
  - "PII scrubbing rules placed in polisher prompt, keyed on conversation_privacy (public = scrub, private = no restrictions)"

patterns-established:
  - "Postgres output collapse recovery: downstream nodes read $('LastGoodNode').item.json, not $input.item.json"
  - "Polisher prompt architecture: system = identity + context, prompt = task instructions + rules"
  - "Context recovery chain: Check Output → Prepare Response → Execute Workflow → Build Polisher Context → Set Polished Response"

requirements-completed: [OPS-01]

duration: ~180min
completed: 2026-03-09
---

# Plan 06-02: Architecture Split Summary

**Core Agent stripped to ~30 token personality shard; always-on Sonnet polisher with soul.md + intermediateSteps + SQL write-back in Output Router**

## Performance

- **Duration:** ~180 min (across 2 sessions, including debugging)
- **Started:** 2026-03-09T01:35:00Z
- **Completed:** 2026-03-09T04:00:00Z
- **Tasks:** 3 (2 auto + 1 human-verify)
- **Workflows modified:** 2 (Core Agent, Output Router)

## Accomplishments
- Core Agent system prompt reduced from ~900 tokens (full soul.md) to ~30 token personality shard — significant context budget freed for tool routing
- Output Router polisher is always-on (old gate/IF removed), uses Sonnet via OpenRouter with soul.md + full context
- SQL write-back updates n8n_chat_histories with polished response so stored conversation matches what user sees
- intermediateSteps flow from all 3 AI Agent nodes through to Output Router for tool-aware polishing
- Research category improved from 2.75 → 4.00 (+1.25) after split

## Eval Results

| Category | Baseline | Post-Split | Delta |
|----------|----------|------------|-------|
| normal_conversation | 3.80 | 3.90 | +0.10 |
| research | 2.75 | 4.00 | +1.25 |
| media | 4.00 | 3.67 | -0.33 |
| email | 4.33 | 3.67 | -0.66 |
| edge_case | 4.60 | 4.40 | -0.20 |
| **Overall** | **3.88** | **3.96** | **+0.08** |

Edge case failures forwarded to 06-04 and 06-05 plans (tc-04 hallucinated weather, tc-07 abrupt gratitude, tc-09 no source attribution, tc-15 bypassed media tools, tc-22 identity leak).

## Task Commits

1. **Task 1: Core Agent prompt surgery** — `fdadb10` (infra)
2. **Task 2: Output Router always-on polisher** — `e6bf59f` (infra)
3. **Task 3: User verification** — manual testing + eval suite

## Decisions Made

- **Personality shard is ~30 tokens** — plan said 50-100 but minimal shard proved sufficient. Core Agent reasoning stays in character without full soul.md.
- **Polisher prompt restructured** — original plan had rules in system message. During verification, polisher was barely modifying output. User suggested moving rules to prompt (user message) section, matching Core Agent's tool description pattern. This produced distinct rewrites.
- **Platform Formatter context recovery** — SQL Write-Back (Postgres executeQuery UPDATE) replaces entire item JSON with `{success: true}`. Platform Formatter had to be changed to read from `$('Set Polished Response').item.json` instead of `$input.item.json`. This is a generalization of the documented "HTTP Request nodes wipe all item JSON" pattern.
- **Credential UI warning is cosmetic** — API-modified nodes may show credential warnings in n8n UI even when credentials are correctly set in JSON. Fix: re-select credential in UI dropdown and save.
- **Polisher downgraded to Haiku post-deployment** — user decision after 06-02 completion. Sonnet overkill for voice polishing; Haiku sufficient at lower cost. Model changed in n8n UI but systemMessage was not wired during that manual edit, causing polisher to lose identity context (fixed in 06-03).

## Deviations from Plan

### Auto-fixed Issues

**1. Postgres output collapse — message delivery broken**
- **Found during:** Task 3 (user verification)
- **Issue:** SQL Write-Back replaced entire item JSON with `{success: true}`. Platform Formatter read `$input.item.json` which was `{success: true}` with no `source_channel` — Switch matched nothing, messages not delivered.
- **Fix:** Platform Formatter changed to `$('Set Polished Response').item.json` and spreads `ctx` instead of `$input.item.json`
- **Verification:** Messages delivered correctly on subsequent tests

**2. Polisher passthrough — not producing distinct rewrites**
- **Found during:** Task 3 (user verification)
- **Issue:** Rules buried at bottom of long system message. Prompt was just `={{ $json.output }}` — raw Core Agent text with zero instruction. Model treated it as something to acknowledge, not rewrite.
- **Fix:** Restructured: system message = soul.md + context only (no rules). Prompt = explicit rewrite instructions + rules + core agent output.
- **Verification:** Coyote image analysis response showed real voice transformation with Aerys-flavored phrases

**3. Send Discord Message credential UI warning**
- **Found during:** Task 3 (user verification)
- **Issue:** Node showed "credentials not set" warning flag in n8n UI after API modification
- **Fix:** User re-selected credential from dropdown in n8n UI and saved
- **Verification:** Messages sent successfully

---

**Total deviations:** 3 auto-fixed (all discovered during verification testing)
**Impact on plan:** All fixes essential for correctness. No scope creep.

## Issues Encountered
- Memory cleanup required after eval runs — created temp workflows to hard-delete chat histories and soft-delete memories for 2026-03-09 window (162 total rows across two cleanup passes)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Architecture split stable — Core Agent is action-focused, Output Router handles voice
- Eval edge case failures documented in 06-04 and 06-05 plans as `<eval_findings>` sections
- Ready for Wave 3 (06-03: debug traces + central error workflow)

---
*Phase: 06-polish-hardening*
*Completed: 2026-03-09*
