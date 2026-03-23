---
phase: 04-memory-system
plan: 03
subsystem: memory
tags: [n8n, postgres, discord, slash-commands, core_claim, profile-api, guardian, override-api]

requires:
  - phase: 04-01-SUMMARY.md
    provides: "Core Agent system message injection structure (## Person Profile stub, ## Relevant Memories stub, cold_start flag)"
  - phase: 04-02-SUMMARY.md
    provides: "memories table + long-term memory retrieval sub-workflow, batch extraction, hybrid pgvector retrieval"

provides:
  - "Profile API (YOUR_PROFILE_API_WORKFLOW_ID) at /webhook/aerys-profile-api — returns formatted profile_context from approved/provisional P2/P3 core_claim entries; cold_start:true for new users"
  - "Guardian (YOUR_GUARDIAN_WORKFLOW_ID) — hourly schedule at :30 offset, advisory lock, semantic pre-clustering before LLM consolidation, promotes userinfo -> core_claim"
  - "Override API (YOUR_OVERRIDE_API_WORKFLOW_ID) at /webhook/aerys-override-api — handles lock/retract/correct/add on core_claim with audit_log writes"
  - "Memory Commands (YOUR_MEMORY_COMMANDS_WORKFLOW_ID) at /webhook/aerys-memory-commands — standalone webhook handler for 5 slash commands"
  - "5 Discord slash commands registered guild-scoped: /aerys-recall /aerys-pin /aerys-forget /aerys-correct /aerys-tell"
  - "Slash Commands workflow (YOUR_SLASH_COMMANDS_WORKFLOW_ID) updated with 29 new memory command handler nodes"
  - "Discord and Telegram adapters pre-fetch profile context on every message"
  - "Core Agent cold-start curiosity mode for new users with no profile"

affects: [05-ai-agents, 06-voice-ui, Core Agent system message, profile evolution, Guardian promotion pipeline]

tech-stack:
  added: []
  patterns:
    - "Prepare Audit Data node pattern — intermediate Code node between handler and Postgres to pre-stringify JSON for queryReplacement"
    - "Memory command inline routing — 5 new command handlers embedded directly in slash commands workflow (97 nodes total), not as sub-workflow"
    - "Override API centralizes all core_claim mutations — slash commands never write directly, always POST to override webhook"
    - "Boolean($json.core_id) guard — safer than isNotEmpty for UUID columns in n8n IF nodes (established in Guardian fixes, reused here)"

key-files:
  created:
    - ~/aerys/workflows/04-03-override-api.json
    - ~/aerys/workflows/04-03-memory-commands.json
    - ~/aerys/workflows/04-03-profile-api.json
    - ~/aerys/workflows/04-03-guardian.json
  modified:
    - ~/aerys/workflows/03-02-slash-commands.json
    - ~/aerys/workflows/03-02-register-commands.json
    - ~/aerys/workflows/02-01-discord-adapter.json
    - ~/aerys/workflows/02-02-telegram-adapter.json

key-decisions:
  - "Memory commands wired into existing slash commands workflow (YOUR_SLASH_COMMANDS_WORKFLOW_ID) inline — not as sub-workflow — to avoid n8n executeWorkflow context loss issues and keep routing in one place without modifying the Cloudflare Worker"
  - "Override API uses Prepare Audit Data Code node before Postgres audit_log INSERT — JSON.stringify inside queryReplacement expression causes 'Query Parameters must be comma-separated' error"
  - "Memory Commands workflow (YOUR_MEMORY_COMMANDS_WORKFLOW_ID) kept active as standalone webhook for future direct testing; actual Discord traffic routes through YOUR_SLASH_COMMANDS_WORKFLOW_ID which has the inline handlers"
  - "RouteCommand Switch outputs 7-11 (memory commands) all route through shared Resolve Identity (memory) -> Merge person_id (memory) -> Route Memory Command chain before branching to command-specific handlers"
  - "Correct handler sets locked=true on update — prevents Guardian from overwriting user-corrected facts"
  - "Add handler sets locked=true + confidence=0.95 — user-stated facts are treated as high-confidence authoritative claims"

requirements-completed: [MEM-03, PERS-04]

duration: ~60min (continuation from Task 1a/1b checkpoint)
completed: 2026-02-25
---

# Phase 4 Plan 03: Memory Management Surface Summary

**Guardian pipeline (userinfo -> core_claim), Profile API, Override API, and five Discord slash commands for user-facing memory control with audit logging**

## Performance

- **Duration:** ~60 min (Task 2 only — Tasks 1a/1b completed in prior session)
- **Started:** 2026-02-25T21:40:26Z
- **Completed:** 2026-02-25T21:56:52Z
- **Tasks:** 3 complete (1a + 1b + Task 2)
- **Files modified:** 8 workflows exported to infra repo

## Accomplishments

- Override API (YOUR_OVERRIDE_API_WORKFLOW_ID) active — handles lock/retract/correct/add with full audit_log writes; all 4 actions tested and verified with real person_id
- Five Discord slash commands registered guild-scoped and routed through existing slash commands workflow without touching the Cloudflare Worker
- Slash commands workflow extended from 68 to 97 nodes with full memory command handler chain (recall/pin/forget/correct/tell with DB queries and override API calls)
- All command responses ephemeral (flags=64), PIN and CORRECT set locked=true preventing Guardian overwrites
- Guardian hourly promotion pipeline active with semantic pre-clustering, advisory lock, and confidence scoring
- Profile API returning formatted core_claim profile_context injected into every Core Agent system message

## Task Commits

1. **Task 1a: Profile API + Guardian** - `947fe90` (feat, prior session)
2. **Task 1b: Adapter pre-fetch + Core Agent cold-start** - `947fe90` (feat, prior session)
3. **Checkpoint: Human-verify three-tier pipeline** - PASSED (approved by user)
4. **Task 2: Override API + memory slash commands** - `ec8500d` (feat) + infra `c3adf55`

**Plan metadata:** (this SUMMARY commit)

## Files Created/Modified

- `~/aerys/workflows/04-03-override-api.json` — Override API workflow (YOUR_OVERRIDE_API_WORKFLOW_ID), handles lock/retract/correct/add on core_claim
- `~/aerys/workflows/04-03-memory-commands.json` — Memory Commands standalone webhook workflow (YOUR_MEMORY_COMMANDS_WORKFLOW_ID)
- `~/aerys/workflows/03-02-slash-commands.json` — Updated slash commands workflow with 29 new memory handler nodes (97 total)
- `~/aerys/workflows/03-02-register-commands.json` — Updated with 11 total commands (6 existing + 5 new)
- `~/aerys/workflows/04-03-profile-api.json` — Profile API workflow (YOUR_PROFILE_API_WORKFLOW_ID)
- `~/aerys/workflows/04-03-guardian.json` — Guardian promotion workflow (YOUR_GUARDIAN_WORKFLOW_ID)

## Decisions Made

- Memory commands wired inline into YOUR_SLASH_COMMANDS_WORKFLOW_ID (not as sub-workflow) — avoids n8n executeWorkflow context loss, keeps all slash command routing in one place, avoids Cloudflare Worker changes
- Override API requires an intermediate "Prepare Audit Data" Code node because JSON.stringify inside queryReplacement causes n8n to error with "Query Parameters must be comma-separated"
- Correct action sets locked=true on corrected claims — user corrections should persist through Guardian promotion cycles
- Add action (from /aerys-tell) sets locked=true with confidence=0.95 — user-stated explicit facts are authoritative

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Override API audit log queryReplacement format**
- **Found during:** Task 2 (Override API creation)
- **Issue:** `JSON.stringify($json.body)` inside `={{ [...] }}` queryReplacement array causes "Query Parameters must be a string of comma-separated values or an array of values" error — n8n serializes the stringify result as a single element
- **Fix:** Added "Prepare Audit Data" Code node between handlers and Write Audit Log node; Code node pre-stringifies `body` into `audit_action` and `audit_details` fields; Postgres node reads simple field references
- **Files modified:** Override API workflow nodes (in n8n, exported to 04-03-override-api.json)
- **Verification:** Audit log rows confirmed in audit_log table after each test call
- **Committed in:** c3adf55 (infra), ec8500d (planning)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug)
**Impact on plan:** Required for audit logging to function. Minor structural change (11 nodes instead of 10). No scope creep.

## Issues Encountered

- Override API test with dummy UUID `00000000-0000-0000-0000-000000000001` correctly rejected by FK constraint on core_claim.speaker_id — not a bug, expected behavior
- Register Commands workflow has Manual Trigger which can't be triggered via n8n API (405 error, per known STATE.md decision) — worked around by creating a temp webhook-based workflow using the same Discord Bot API credential to PUT the commands directly to Discord API

## Next Phase Readiness

Phase 4 memory system complete. All 4 plans done:
- 04-01: Foundation (thread context, member roster, session migration, Core Agent injection structure)
- 04-02: Long-term memory pipeline (batch extraction, embedding, pgvector retrieval)
- 04-03: Profile API + Guardian + Override API + 5 Discord slash commands

Ready for Phase 5 (AI Agents) or any other remaining phases.
- MEM-03 (profile injection) fulfilled — approved core_claim entries appear in every Core Agent call
- PERS-04 (personality evolution) fulfilled — relationship_depth, emotional register fields in core_claim flow to Core Agent
- All 9 Phase 4 requirements (MEM-01 through MEM-06, MEM-08, MEM-09, PERS-04) met

## Self-Check: PASSED

All required files found and commits verified:
- FOUND: 04-03-SUMMARY.md
- FOUND: 04-03-override-api.json, 04-03-memory-commands.json, 03-02-slash-commands.json, 03-02-register-commands.json
- FOUND commit: ec8500d (planning task 2), c3adf55 (infra)
- FOUND commit: e3c6a96 (planning final metadata)
- Workflows active: Override API (YOUR_OVERRIDE_API_WORKFLOW_ID), Memory Commands (YOUR_MEMORY_COMMANDS_WORKFLOW_ID), Slash Commands (YOUR_SLASH_COMMANDS_WORKFLOW_ID)
- Discord commands: 11 registered (6 existing + 5 new aerys-* commands)

---
*Phase: 04-memory-system*
*Completed: 2026-02-25*
