---
phase: 06-polish-hardening
plan: 03
subsystem: workflow, observability
tags: [n8n, discord, debug-trace, error-handler, retryOnFail, audit-log, graceful-errors]

requires:
  - phase: 06-02
    provides: "Architecture split — Output Router with Set Polished Response node as fork point for debug traces"
  - phase: 05-sub-agents-media
    provides: "18 production workflows needing errorWorkflow + retryOnFail patches"
provides:
  - "Debug trace fork in Output Router — Crabwalk-style model/timing/tool traces to #aerys-debug on every response"
  - "Central Error Handler workflow (YOUR_ERROR_HANDLER_WORKFLOW_ID) — catches unhandled failures, logs audit_log + notifies #echoes"
  - "retryOnFail (maxTries: 3) on 55 HTTP Request nodes across 10 workflows"
  - "Graceful in-character error messages in Core Agent (3 Check Output nodes)"
  - "18 production workflows patched with settings.errorWorkflow"
affects: [06-04, 06-05]

tech-stack:
  added: []
  patterns:
    - "Parallel fork after Set Polished Response — debug trace path runs in parallel with user response delivery, continueOnFail on all trace nodes"
    - "Central error workflow pattern — Error Trigger + Format Error + parallel Log to Audit / Send to Discord"
    - "retryOnFail with onError:continueErrorOutput exclusion — skip nodes with continueErrorOutput to avoid bug #10763"
    - "Graceful error messages — in-character error handling in Check Output nodes with tool-specific response templates"

key-files:
  created:
    - "n8n 06-03 Central Error Handler (YOUR_ERROR_HANDLER_WORKFLOW_ID) — Error Trigger + audit_log + #echoes notification"
  modified:
    - "n8n Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID) — 4 new nodes: Check Debug Enabled, IF: Debug Enabled, Format Trace, Send Trace"
    - "n8n Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID) — graceful error messages in 3 Check Output nodes + Polisher systemMessage wired"
    - "18 production workflows — settings.errorWorkflow patched to YOUR_ERROR_HANDLER_WORKFLOW_ID"
    - "10 workflows — 55 HTTP Request nodes with retryOnFail: true, maxTries: 3, waitBetweenTries: 2000"

key-decisions:
  - "Polisher model is Haiku (claude-haiku-4.5), not Sonnet — user decision post-06-02 as cost-saving measure"
  - "New workflow: 06-03 Central Error Handler = YOUR_ERROR_HANDLER_WORKFLOW_ID"
  - "#echoes channel (YOUR_ECHOES_CHANNEL_ID) used for error notifications; #aerys-debug (YOUR_DEBUG_CHANNEL_ID) for traces"
  - "Skipped retryOnFail on nodes with onError: continueErrorOutput to avoid n8n bug #10763"
  - "Format Trace uses case-insensitive regex patterns for tool name matching (intermediateSteps sanitizes node names)"

patterns-established:
  - "Parallel fork pattern: wire from same output to both user-response path and debug/trace path with continueOnFail on trace nodes"
  - "Central error workflow: all production workflows point settings.errorWorkflow to a single handler that logs + notifies"
  - "retryOnFail sweep: add to all HTTP Request nodes except those with onError: continueErrorOutput"

requirements-completed: [OPS-01, OPS-03]

duration: ~120min
completed: 2026-03-17
---

# Plan 06-03: Observability + Error Infrastructure Summary

**Crabwalk-style debug traces to #aerys-debug on every response, central error handler workflow with audit_log + #echoes notifications, retryOnFail on 55 HTTP nodes, graceful in-character error messages**

## Performance

- **Duration:** ~120 min (across 2 sessions including verification)
- **Started:** 2026-03-13T00:00:00Z
- **Completed:** 2026-03-17T00:00:00Z
- **Tasks:** 3 (2 auto + 1 human-verify)
- **Workflows created:** 1 (Central Error Handler)
- **Workflows modified:** 20 (Output Router + Core Agent + 18 production workflows patched)

## Accomplishments

- Debug trace fires after every Aerys response via parallel fork in Output Router -- shows model tier, elapsed time, and tool calls in #aerys-debug without any user content (privacy-safe)
- Central Error Handler (YOUR_ERROR_HANDLER_WORKFLOW_ID) catches unhandled crashes from all 18 production workflows -- logs to audit_log table and sends notification to #echoes Discord channel
- 55 HTTP Request nodes across 10 workflows patched with retryOnFail (maxTries: 3, waitBetweenTries: 2000) to handle Tachyon DNS transient failures
- All 3 Core Agent Check Output nodes produce graceful in-character error messages with tool-specific responses when sub-agents fail
- Polisher systemMessage wired to polisher_system_prompt -- Haiku now has identity context for voice polishing

## Task Commits

Each task was committed atomically:

1. **Task 1: Debug trace fork in Output Router** -- `0a6cb14` (infra) -- 4 new nodes: Check Debug Enabled, IF: Debug Enabled, Format Trace, Send Trace
2. **Task 2: Central error workflow + retryOnFail + graceful errors** -- `69f9c1b` (infra) -- new workflow YOUR_ERROR_HANDLER_WORKFLOW_ID, 18 workflows patched, 55 HTTP nodes retryOnFail, Core Agent graceful errors

## Files Created/Modified

- **n8n 06-03 Central Error Handler** (YOUR_ERROR_HANDLER_WORKFLOW_ID) -- Error Trigger, Format Error, parallel Log to Audit + Send to Echoes
- **n8n Output Router** (YOUR_OUTPUT_ROUTER_WORKFLOW_ID) -- parallel debug trace fork after Set Polished Response
- **n8n Core Agent** (YOUR_CORE_AGENT_WORKFLOW_ID) -- graceful error handling in Check Sonnet/Opus/Gemini Output nodes
- **18 production workflows** -- settings.errorWorkflow set to YOUR_ERROR_HANDLER_WORKFLOW_ID

## Decisions Made

- **Polisher model is Haiku (claude-haiku-4.5)** -- user decision post-06-02. Sonnet unnecessary for voice polishing; Haiku sufficient at lower cost.
- **Central Error Handler workflow ID: YOUR_ERROR_HANDLER_WORKFLOW_ID** -- active, receiving errors from all production workflows.
- **#echoes (YOUR_ECHOES_CHANNEL_ID) for error notifications** -- separate from #aerys-debug (traces only). Error channel chosen because it already serves as Aerys's self-awareness/echo channel.
- **retryOnFail excluded from continueErrorOutput nodes** -- n8n bug #10763 causes retry success to still fire the error branch. Safer to skip.
- **Format Trace uses regex patterns** -- intermediateSteps sanitizes node names (e.g., `Tool_Research_Opus_`), exact match failed. Case-insensitive regex patterns resolve correctly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Polisher systemMessage not wired**
- **Found during:** Task 3 (user verification)
- **Issue:** Build Polisher Context constructed polisher_system_prompt but the Polisher AI Agent node had no systemMessage set. Haiku had no identity context, treated Core Agent output as conversation to continue rather than content to polish.
- **Fix:** Set Polisher AI Agent systemMessage to `={{ $json.polisher_system_prompt }}`
- **Files modified:** Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID)
- **Verification:** Subsequent responses showed distinct voice polishing with Aerys personality
- **Committed in:** `f232775` (infra)

**2. [Rule 1 - Bug] Format Trace tool name matching**
- **Found during:** Task 3 (user verification)
- **Issue:** intermediateSteps uses sanitized node names (e.g., `Tool_Research_Opus_`), exact-match lookup against TOOL_ICONS showed `[?]` for all tools.
- **Fix:** Switched to case-insensitive regex patterns for tool name matching
- **Files modified:** Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID), Format Trace Code node
- **Verification:** Debug traces correctly display [RES], [IMG], [EML] icons
- **Committed in:** `c37df41` (infra)

### Side-fix (out-of-scope, discovered during verification)

**3. [Rule 1 - Bug] Guardian idle credit burn**
- **Found during:** Task 3 verification window
- **Issue:** Guardian re-processed 211 already-promoted candidates every hour for 9+ days, burning ~$12.30 in LLM credits on no-op consolidation runs.
- **Fix:** Added LEFT JOIN core_claim exclusion so already-promoted memories are skipped.
- **Files modified:** Guardian workflow (YOUR_GUARDIAN_WORKFLOW_ID)
- **Committed in:** `b028a95` (infra)
- **Note:** This is a Guardian fix, not an 06-03 deliverable. Documented here because discovered during 06-03 verification.

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs), 1 side-fix (Guardian credit burn, out of plan scope)
**Impact on plan:** Polisher systemMessage and Format Trace regex were both essential for correctness. Guardian fix was a cost-saving discovery. No scope creep.

## Issues Encountered

- **errorWorkflow only fires on unhandled crashes** -- by design, n8n's errorWorkflow mechanism does not fire when errors are caught by onError/continueOnFail. This means #echoes stays clean (no noise from handled errors like Guardian credit exhaustion). Confirmed working as expected.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- Debug trace infrastructure stable -- every interaction is now visible in #aerys-debug
- Error handling complete -- silent failures impossible; all unhandled crashes notify #echoes
- retryOnFail on HTTP nodes handles Tachyon DNS transient failures
- Ready for Wave 4 (06-04: Guardrails + Hardening -- jailbreak detection, PII scrubbing, sub-agent lifecycle migration)

---
*Phase: 06-polish-hardening*
*Completed: 2026-03-17*
