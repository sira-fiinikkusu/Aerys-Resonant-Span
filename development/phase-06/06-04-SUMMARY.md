---
phase: 06-polish-hardening
plan: 04
subsystem: workflow, security, database
tags: [n8n, jailbreak, guardrails, pii, sub-agents, lifecycle, migration, discord, regex]

requires:
  - phase: 06-03
    provides: "Observability infrastructure — debug traces to #aerys-debug, central error handler, retryOnFail, graceful errors"
  - phase: 06-02
    provides: "Architecture split — Output Router polisher with PII scrubbing rules keyed on conversation_privacy"
provides:
  - "Jailbreak detection gate in Core Agent — 25+ regex patterns with in-character deflection + @owner alert to #aerys-debug"
  - "Polisher bypass for jailbreak responses — _jailbreak_detected flag routes around polisher to preserve deflection tone"
  - "Sub-agent lifecycle state column (ready/failed/disabled) + dependencies JSONB on sub_agents table"
  - "Migration 008: state + dependencies columns with constraint and index"
affects: [06-05]

tech-stack:
  added: []
  patterns:
    - "Regex-based jailbreak detection with random deflection response selection — no LLM cost for guardrail checks"
    - "Flag-based polisher bypass — _jailbreak_detected flag in output routes around polisher via IF: Skip Polisher node"
    - "Sub-agent dependency declarations — JSONB column listing required credentials per agent for future health-check routing"

key-files:
  created:
    - "~/aerys/migrations/008_sub_agent_lifecycle.sql — state + dependencies columns on sub_agents"
  modified:
    - "n8n Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID) — 4 new nodes: Jailbreak Check, IF: Jailbreak Detected, Handle Jailbreak, Send Jailbreak Alert"
    - "n8n Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID) — IF: Skip Polisher + Bypass Polisher nodes for jailbreak deflection passthrough"

key-decisions:
  - "Regex-based jailbreak detection instead of LLM-based Guardrails node — zero incremental cost, sub-millisecond latency, 25+ patterns covering prompt injection, role-play hijacking, system prompt extraction, identity probing"
  - "Polisher bypass for jailbreak deflections — Handle Jailbreak crafts in-character tone that polisher was rewriting; _jailbreak_detected flag routes around polisher"
  - "Sub-agent state column is infrastructure for V2 dynamic routing — tools remain hardcoded as 9 toolWorkflow nodes in Core Agent (static); no query-based routing added"
  - "PII scrubbing not end-to-end tested — rules exist in polisher prompt from 06-02, keyed on conversation_privacy, but Haiku model behavior not verified with real PII; mechanism exists but may need prompt tuning in 06-05"
  - "Guardian LEFT JOIN deleted_at fix — prior fix (b028a95) referenced non-existent cc.deleted_at column on core_claim; removed in 454b728"

patterns-established:
  - "Jailbreak deflection pattern: regex check -> random in-character response -> alert to debug channel -> bypass polisher via flag"
  - "Flag-based polisher bypass: set _jailbreak_detected on output, IF node checks flag before polisher, Bypass Polisher node passes response through unchanged"

requirements-completed: [OPS-02, OPS-03]

duration: ~90min
completed: 2026-03-17
---

# Plan 06-04: Guardrails + Hardening Summary

**Jailbreak detection with 25+ regex patterns and in-character deflection, polisher bypass for deflection tone preservation, sub-agent lifecycle state/dependencies migration 008**

## Performance

- **Duration:** ~90 min (across 2 sessions including verification)
- **Started:** 2026-03-17T00:00:00Z
- **Completed:** 2026-03-17T00:00:00Z
- **Tasks:** 3 (2 auto + 1 human-verify)
- **Workflows modified:** 2 (Core Agent + Output Router)
- **Migration executed:** 1 (008_sub_agent_lifecycle.sql)

## Accomplishments

- Jailbreak detection gate in Core Agent with 25+ regex patterns covering prompt injection, role-play hijacking, system prompt extraction, and identity probing (tc-22 eval fix)
- 5 in-character deflection response variants selected randomly on jailbreak detection
- Alert to #aerys-debug with admin @mention and spoiler-tagged content on every jailbreak detection
- Polisher bypass added to Output Router -- _jailbreak_detected flag routes around polisher so deflection tone is preserved
- Migration 008 adds state column (ready/failed/disabled) and dependencies JSONB column to sub_agents table
- All 3 sub-agents populated with correct dependency declarations (email: gmail_aerys + gmail_user, media: openrouter, research: tavily)
- PII scrubbing rules confirmed present in polisher from 06-02 (conversation_privacy-keyed), though not end-to-end tested with Haiku

## Task Commits

Each task was committed atomically (infra repo):

1. **Task 1: Jailbreak guardrail in Core Agent** -- `fe5c914` (feat) -- 4 new nodes: Jailbreak Check, IF: Jailbreak Detected, Handle Jailbreak, Send Jailbreak Alert
2. **Task 2: Sub-agent lifecycle migration 008** -- `251ea31` (feat) -- migration file + temp workflow for execution

Deviation fixes (infra repo):
- `a97f0a2` + `5cc4923` -- Polisher bypass nodes in Output Router (_jailbreak_detected flag routing)
- `454b728` -- Guardian LEFT JOIN deleted_at column fix

## Files Created/Modified

- **~/aerys/migrations/008_sub_agent_lifecycle.sql** -- state + dependencies columns on sub_agents table
- **n8n Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID)** -- 4 new nodes for jailbreak detection + deflection + alerting
- **n8n Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID)** -- IF: Skip Polisher + Bypass Polisher nodes for jailbreak deflection passthrough
- **n8n Guardian (YOUR_GUARDIAN_WORKFLOW_ID)** -- removed non-existent deleted_at column reference from LEFT JOIN

## Decisions Made

- **Regex-based jailbreak detection over LLM-based Guardrails node** -- Zero incremental cost per check, sub-millisecond latency, easily extensible pattern list. LLM-based approach would add latency and cost to every message.
- **Polisher bypass via flag routing** -- Handle Jailbreak crafts specific in-character deflection tone. Without bypass, Haiku polisher rewrites the deflection ("I'd rather keep it real" became "Map the room: what's the actual ask"), losing the intended tone. _jailbreak_detected flag in output triggers IF: Skip Polisher node.
- **Sub-agent state is V2 infrastructure only** -- The state column enables future dynamic routing where failed sub-agents are excluded at query time. Currently tools are hardcoded as 9 toolWorkflow nodes. No Fetch Available Tools query update was needed since routing is static.
- **PII scrubbing deferred to observation in production** -- Rules are wired in polisher prompt (from 06-02), but end-to-end testing with real PII was not performed (user decided against sending fake phone number through memory pipeline). If PII leaks surface, prompt tuning in 06-05 is the fix.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Polisher rewrote jailbreak deflections**
- **Found during:** Task 3 (user verification)
- **Issue:** Handle Jailbreak crafted in-character deflection but the Haiku polisher rewrote it, losing the deflection tone ("I'd rather keep it real" became "Map the room: what's the actual ask")
- **Fix:** Added IF: Skip Polisher + Bypass Polisher nodes in Output Router. _jailbreak_detected flag routes around polisher. Set Polished Response updated with try/catch fallback for Build Polisher Context.
- **Files modified:** Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID)
- **Verification:** Subsequent jailbreak test produced unmodified deflection response
- **Committed in:** `a97f0a2` and `5cc4923` (infra)

**2. [Rule 1 - Bug] Guardian LEFT JOIN referenced non-existent deleted_at column**
- **Found during:** Task 3 (user verification)
- **Issue:** The earlier Guardian credit burn fix (b028a95) referenced `cc.deleted_at` on core_claim which doesn't have that column. #echoes error handler caught the failure (proving the 06-03 error infrastructure works).
- **Fix:** Removed deleted_at condition from Guardian LEFT JOIN
- **Files modified:** Guardian workflow (YOUR_GUARDIAN_WORKFLOW_ID)
- **Verification:** Guardian runs without error after fix
- **Committed in:** `454b728` (infra)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs)
**Impact on plan:** Polisher bypass was essential for jailbreak deflection correctness. Guardian fix was a pre-existing bug exposed by the new error handler. No scope creep.

## Untested Items

- **PII scrubbing end-to-end** -- Rules present in polisher prompt (from 06-02), keyed on conversation_privacy (public: scrub, private: preserve). Not tested with real PII data because user decided against sending fake phone number through the memory pipeline. If PII leaks become a problem, the mechanism exists but may need prompt tuning in 06-05.

## Issues Encountered

- **Temp migration workflow 7R4GQalXJxXaPVgZ** -- Created for migration 008 execution, user ran manually, deleted after verification confirmed state/dependencies columns populated correctly.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- Jailbreak guardrail active -- public channels protected from prompt injection with in-character deflections
- Sub-agent lifecycle state infrastructure ready for V2 dynamic routing
- PII scrubbing rules wired but untested -- monitor in production, tune in 06-05 if needed
- Ready for Wave 5 (06-05: Prompt Engineering -- soul.md reactive rewrite, context section merge strategy, sub-agent prompt review)

## Self-Check: PASSED

- [x] 06-04-SUMMARY.md exists
- [x] STATE.md updated (4 of 5 plans, 95%, decisions added, session updated)
- [x] ROADMAP.md updated (06-04 checked, 4/5 progress)
- [x] Temp workflow 7R4GQalXJxXaPVgZ deleted from n8n
- [x] Task commits documented (fe5c914, 251ea31 + deviations a97f0a2, 5cc4923, 454b728)

---
*Phase: 06-polish-hardening*
*Completed: 2026-03-17*
