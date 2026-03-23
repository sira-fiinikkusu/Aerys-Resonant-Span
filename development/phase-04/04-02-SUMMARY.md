---
phase: 04-memory-system
plan: 02
subsystem: database
tags: [pgvector, embeddings, openrouter, n8n, long-term-memory, batch-extraction, hybrid-retrieval]

# Dependency graph
requires:
  - phase: 04-memory-system/04-01
    provides: memories table with pgvector extension, ## Relevant Memories injection point in Core Agent system message
  - phase: 02-core-agent-channels
    provides: Discord adapter (YOUR_DISCORD_ADAPTER_WORKFLOW_ID), Telegram adapter (YOUR_TELEGRAM_ADAPTER_WORKFLOW_ID), Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID)
provides:
  - "04-02 Memory Retrieval sub-workflow (YOUR_MEMORY_RETRIEVAL_WORKFLOW_ID): pgvector hybrid retrieval, 70/30 semantic+recency, privacy-filtered, returns memory_context string"
  - "04-02 Memory Batch Extraction workflow (YOUR_BATCH_EXTRACTION_WORKFLOW_ID): hourly schedule, LLM extraction via claude-haiku-4.5, embeddings via text-embedding-3-small, inserts into memories with source_platform + privacy_level"
  - "Discord and Telegram adapters: pre-fetch memory context on every message arrival before Core Agent fires"
  - "Privacy isolation: public memories only in guild context, public+private in DM context"
affects: [04-03-profile-summary, Core Agent system message]

# Tech tracking
tech-stack:
  added:
    - "pgvector hybrid SQL (70/30 semantic+recency scoring)"
    - "openai/text-embedding-3-small via OpenRouter (1536 floats)"
    - "anthropic/claude-haiku-4.5 via OpenRouter for fact extraction"
  patterns:
    - "Execute Workflow Trigger passthrough: $json at non-trigger nodes is the PREVIOUS node's output, not the trigger input; use $('Execute Workflow Trigger').first().json for original trigger data"
    - "UNION ALL placeholder: add SELECT NULL... WHERE NOT EXISTS(...) to guarantee Postgres node always emits at least one row when result may be empty"
    - "Prepare Insert Data pattern: when embed result is at $input and original observation context is at $('ParseNode').item.json, merge them in a Code node before INSERT"
    - "Markdown strip for LLM JSON: text.replace(/^```(?:json)?\\n?/m, '').replace(/\\n?```$/m, '').trim() before JSON.parse"
    - "CTE UUID guard: WITH valid_sessions AS (SELECT session_id ... WHERE session_id ~ '^uuid-regex$') to filter mixed session_id formats before casting"
    - "Two-query privacy branch: IF node routes to separate Postgres queries for public-only vs public+private instead of ANY($3::text[]) array binding"

key-files:
  created:
    - "~/aerys/workflows/04-02-memory-retrieval.json (YOUR_MEMORY_RETRIEVAL_WORKFLOW_ID)"
    - "~/aerys/workflows/04-02-memory-batch.json (YOUR_BATCH_EXTRACTION_WORKFLOW_ID)"
  modified:
    - "~/aerys/workflows/02-01-discord-adapter.json (YOUR_DISCORD_ADAPTER_WORKFLOW_ID)"
    - "~/aerys/workflows/02-02-telegram-adapter.json (YOUR_TELEGRAM_ADAPTER_WORKFLOW_ID)"

key-decisions:
  - "[04-02]: ANY($3::text[]) array binding fails in n8n Postgres node — replaced with two separate SQL queries branched by IF node (public-only vs public+private)"
  - "[04-02]: $('Execute Workflow Trigger').first().json returns {} when called via executeWorkflow typeVersion 2 + passthrough (no defineBelow). At the TRIGGER node itself, data flows to downstream nodes. At those downstream nodes, $json = previous node's output. Use $('Execute Workflow Trigger').first().json at Code nodes AFTER the trigger to read trigger input."
  - "[04-02]: Prepare Insert Data Code node required before INSERT — $json at the Insert Memory node is the Embed output, not the observation data. Node reads $('Parse Observations').item.json for person_id/privacy_level/source_platform."
  - "[04-02]: Batch extraction routes to messages table when schema is present, falls back to n8n_chat_histories — privacy_level defaults to 'private' for fallback path (safe direction, prevents DM exposure in guild)"
  - "[04-02]: messages table uses channel (not source_channel), role (not is_bot), no processed_at column — Fetch Unprocessed Messages query corrected to real schema"

patterns-established:
  - "Memory pre-fetch pattern: Prepare Memory Fetch (Code) -> Execute Memory Retrieval (executeWorkflow, defineBelow) -> Merge Memory Result (Code reading $('Merge person_id').item.json)"
  - "Retrieval sub-workflow: Execute Workflow Trigger (passthrough) -> Embed Query Text (HTTP) -> Build Retrieval Query (Code, reads trigger via node reference) -> Privacy Branch (IF) -> Retrieve Memories (Postgres, UNION ALL placeholder) -> Wrap Results (Code) -> Format Memory Context (Code) -> Return Result (Code)"

requirements-completed: [MEM-02, MEM-06, MEM-08, MEM-09]

# Metrics
duration: ~120min (across two sessions)
completed: 2026-02-24
---

# Phase 4 Plan 02: Long-term Memory Pipeline Summary

**pgvector hybrid retrieval (70/30 semantic+recency) with LLM batch extraction and pre-fetch injection into Discord and Telegram adapters**

## Performance

- **Duration:** ~120 min (two sessions — context ran out mid-execution)
- **Started:** 2026-02-24T00:00:00Z
- **Completed:** 2026-02-24T02:00:00Z
- **Tasks:** 2
- **Files modified:** 4 workflow exports + 1 fix commit

## Accomplishments
- Memory Retrieval sub-workflow (YOUR_MEMORY_RETRIEVAL_WORKFLOW_ID): receives message_text + person_id, generates embedding via OpenRouter, runs pgvector hybrid SQL (70% semantic similarity + 30% recency), returns top 5 as formatted bullet list; privacy-filtered (public-only in guild, public+private in DM)
- Memory Batch Extraction workflow (YOUR_BATCH_EXTRACTION_WORKFLOW_ID): hourly schedule, checks messages table (falls back to n8n_chat_histories), groups 20 messages per LLM call, extracts facts via claude-haiku-4.5, embeds via text-embedding-3-small, inserts with source_platform + privacy_level provenance tags; verified extracted "user.name: Saelen" from Saelen's chat history
- Discord and Telegram adapters: 3-node pre-fetch pattern (Prepare Memory Fetch → Execute Memory Retrieval → Merge Memory Result) wired between identity resolution and Core Agent call; memory_context flows into ## Relevant Memories section of Core Agent system message

## Task Commits

1. **Task 1: Memory Retrieval sub-workflow** - `f575353` (feat)
2. **Task 1: Fix person_id lookup in Build Retrieval Query** - `89c0857` (fix)
3. **Task 2: Wire memory pre-fetch + create batch extraction** - `e3aa7cf` (feat)

## Files Created/Modified
- `~/aerys/workflows/04-02-memory-retrieval.json` - Memory Retrieval sub-workflow (YOUR_MEMORY_RETRIEVAL_WORKFLOW_ID), 10 nodes
- `~/aerys/workflows/04-02-memory-batch.json` - Memory Batch Extraction workflow (YOUR_BATCH_EXTRACTION_WORKFLOW_ID), 19 nodes
- `~/aerys/workflows/02-01-discord-adapter.json` - Added 3 memory pre-fetch nodes, Execute Core Agent moved to [3800,0]
- `~/aerys/workflows/02-02-telegram-adapter.json` - Added 3 memory pre-fetch nodes (Chat suffix), Execute Core Agent moved to [2350,0]

## Decisions Made

- `ANY($3::text[])` array binding does not work in n8n Postgres node — replaced with two separate SQL queries branched by IF node (one for public-only, one for public+private)
- `$('Execute Workflow Trigger').first().json` pattern: at Code nodes DOWNSTREAM of the trigger, this returns the original trigger input. But `$json` at those nodes is the PREVIOUS node's output. Build Retrieval Query uses the trigger node reference for person_id/privacy_context, and `$input.first().json` for the embedding result.
- Prepare Insert Data Code node added before INSERT — when the current `$json` is the Embed output, original observation fields (person_id, privacy_level, source_platform) must be recovered from `$('Parse Observations').item.json`
- Batch extraction uses messages table when schema present, falls back to n8n_chat_histories; fallback always uses privacy_level='private' as safe default (DM-context memories, will not surface in guild)
- Set node (typeVersion 3.4) returns `{}` in this n8n version — all test harnesses use Code nodes to inject input data instead

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ANY($3::text[]) array binding fails in n8n Postgres**
- **Found during:** Task 1
- **Issue:** n8n Postgres node cannot bind a JSON array string as PostgreSQL text array for ANY() operator
- **Fix:** Created two separate SQL queries (Retrieve Memories Public, Retrieve Memories Private) branched by IF node on `is_private` field; eliminated array parameter entirely
- **Files modified:** 04-02-memory-retrieval.json (YOUR_MEMORY_RETRIEVAL_WORKFLOW_ID)
- **Verification:** Both branches execute without parameter type errors
- **Committed in:** f575353

**2. [Rule 1 - Bug] Postgres 0-row empty result stops downstream chain**
- **Found during:** Task 1
- **Issue:** When memories table is empty, Retrieve Memories returns 0 rows; n8n doesn't execute downstream nodes, chain stops
- **Fix:** Added UNION ALL placeholder: `SELECT NULL::uuid, NULL, NULL, NULL, NULL, 0.0 WHERE NOT EXISTS(...)` to guarantee at least one row; added Wrap Results Code node that filters out placeholder rows before formatting
- **Files modified:** 04-02-memory-retrieval.json (YOUR_MEMORY_RETRIEVAL_WORKFLOW_ID)
- **Verification:** Retrieval returns `{"memory_context": ""}` for empty DB, confirmed via test exec
- **Committed in:** f575353

**3. [Rule 1 - Bug] Set node returns {} in this n8n version**
- **Found during:** Task 1 (Return Result step)
- **Issue:** Set node with keepAllExistingFields + selectedFields throws "Cannot read properties of undefined (reading 'execute')"
- **Fix:** Replaced Return Result Set node with simple Code node: `return [{ json: { memory_context: mc } }]`
- **Files modified:** 04-02-memory-retrieval.json
- **Verification:** Return Result Code node runs cleanly
- **Committed in:** f575353

**4. [Rule 1 - Bug] executeWorkflow typeVersion format mismatch**
- **Found during:** Task 2
- **Issue:** typeVersion 1.1 with `__rl` workflowId format caused "No information about the workflow to execute found"
- **Fix:** Changed to typeVersion 2 with `{"value": "ID", "mode": "id"}` format and `waitForSubWorkflow: true`
- **Files modified:** 02-01-discord-adapter.json, 02-02-telegram-adapter.json
- **Verification:** Execute Memory Retrieval node runs without error in test exec
- **Committed in:** e3aa7cf

**5. [Rule 1 - Bug] $('Execute Workflow Trigger').first().json returns {} for passthrough**
- **Found during:** Task 1 (retrieval returns empty despite memory in DB)
- **Issue:** When executeWorkflow uses typeVersion 2 + passthrough inputSource, the trigger node emits `{}`. Data is accessible as `$json` at the TRIGGER node's immediate downstream, but at Code nodes further downstream, `$json` is the previous node's output. Build Retrieval Query read person_id from `$json` which was the embedding result — person_id was always undefined.
- **Fix:** Changed Build Retrieval Query to use `$('Execute Workflow Trigger').first().json` for trigger input fields (person_id, privacy_context) and `$input.first().json` for embedding result
- **Files modified:** 04-02-memory-retrieval.json
- **Verification:** Retrieval returns "• channel_access: Messages are visible in channel history [discord] (0d ago)" — confirmed working
- **Committed in:** 89c0857

**6. [Rule 1 - Bug] Batch extraction: privacy_level NULL in INSERT**
- **Found during:** Task 2 (Part C)
- **Issue:** At Insert Memory node, `$json` is the Embed Observation output (only has embedding data fields), so `$json.privacy_level` was NULL; INSERT failed or inserted NULL
- **Fix:** Added Prepare Insert Data Code node that reads `$('Parse Observations').item.json` for observation context (person_id, privacy_level, source_platform) and merges with embedding from `$input.first().json`
- **Files modified:** 04-02-memory-batch.json
- **Verification:** Memory inserted with correct privacy_level='public' confirmed in memories table
- **Committed in:** e3aa7cf

**7. [Rule 1 - Bug] Wrong LLM model name**
- **Found during:** Task 2 (Part C)
- **Issue:** `anthropic/claude-haiku-4` returns 400 Bad Request from OpenRouter
- **Fix:** Changed to `anthropic/claude-haiku-4.5` (correct model ID confirmed from exec 715)
- **Files modified:** 04-02-memory-batch.json
- **Verification:** LLM extraction call returns 200 with observation JSON
- **Committed in:** e3aa7cf

**8. [Rule 1 - Bug] LLM returns JSON in markdown code fences**
- **Found during:** Task 2 (Part C)
- **Issue:** claude-haiku-4.5 wraps JSON in ```json ... ``` — JSON.parse fails
- **Fix:** Added regex strip before parse: `text.replace(/^```(?:json)?\n?/m, '').replace(/\n?```$/m, '').trim()`
- **Files modified:** 04-02-memory-batch.json (Parse Observations node)
- **Verification:** Observations parsed correctly, memory inserted
- **Committed in:** e3aa7cf

**9. [Rule 1 - Bug] messages table schema mismatch**
- **Found during:** Task 2 (Part C)
- **Issue:** Plan assumed source_channel, conversation_privacy, processed_at, is_bot columns. Real schema: channel, role, no processed_at, no is_bot
- **Fix:** Corrected Fetch Unprocessed Messages query to use `channel AS source_platform`, `role = 'human'`; removed processed_at check; Mark Messages Processed skipped (no column)
- **Files modified:** 04-02-memory-batch.json
- **Verification:** Fetch Unprocessed Messages runs without column errors
- **Committed in:** e3aa7cf

**10. [Rule 1 - Bug] n8n_chat_histories schema mismatch**
- **Found during:** Task 2 (Part C)
- **Issue:** Plan assumed h.created_at, h.type columns. Real schema: only id (int), session_id (varchar), message (JSONB with {type, content})
- **Fix:** Changed query to use `(h.message->>'content')` and `(h.message->>'type') = 'human'`; added CTE to pre-filter UUID-format session_ids before casting (mixed session_ids like 'discord_test-123' cause cast errors)
- **Files modified:** 04-02-memory-batch.json
- **Verification:** Fallback path executes without type cast errors; 5 UUID sessions with human messages confirmed
- **Committed in:** e3aa7cf

---

**Total deviations:** 10 auto-fixed (all Rule 1 - Bug)
**Impact on plan:** All fixes required for correctness. Schema deviations reflect real infrastructure state. No scope creep.

## Issues Encountered

- Context ran out mid-execution (after Task 1 fix was applied but not yet tested). Resumed in second session; verified fix worked and completed Task 2.
- pgvector UNION ALL placeholder pattern required for all Retrieve Memories queries — n8n's behavior of not executing downstream nodes on 0-row Postgres results is a fundamental constraint.

## Next Phase Readiness
- Phase 4 Plan 3 (04-03 User Profile Summary) can now read from memories table and generate profile_context for the ## Person Profile injection point in Core Agent
- memory_context is populated live in guild and DM contexts; ## Relevant Memories section will show actual memories as soon as batch extraction runs
- Batch extraction workflow is hourly — first run will populate memories table from existing n8n_chat_histories (5 persons, 23 human messages available)
- Privacy isolation confirmed: private memories (privacy_level='private') never appear in guild context (privacy_context='public' queries only public)

---
*Phase: 04-memory-system*
*Completed: 2026-02-24*

## Self-Check: PASSED

All files exist and commits verified:
- FOUND: `.planning/phases/04-memory-system/04-02-SUMMARY.md`
- FOUND: `~/aerys/workflows/04-02-memory-retrieval.json`
- FOUND: `~/aerys/workflows/04-02-memory-batch.json`
- FOUND: `~/aerys/workflows/02-01-discord-adapter.json`
- FOUND: `~/aerys/workflows/02-02-telegram-adapter.json`
- FOUND: commit `f575353` (feat: create retrieval sub-workflow)
- FOUND: commit `89c0857` (fix: correct person_id lookup)
- FOUND: commit `e3aa7cf` (feat: wire adapters + batch extraction)
- FOUND: commit `7d9c8a4` (docs: planning repo metadata)
