---
phase: 05-sub-agents-media
plan: "00"
subsystem: database
tags: [postgres, migration, schema, sub-agents, n8n, community-node, docx, timestamps]

# Dependency graph
requires:
  - phase: 04-memory-system
    provides: Aerys DB schema, n8n migration workflow pattern, credential YOUR_POSTGRES_CREDENTIAL_ID

provides:
  - sub_agents table in Aerys DB (3 rows: media_agent, research_agent, email_agent)
  - pending_emails table in Aerys DB (draft-then-confirm staging)
  - sub_agent_invocations table in Aerys DB (Layer 1 of V2 adaptive routing feedback loop)
  - ET timestamps in guild adapter thread context ([SpeakerName (Feb 26, 2:34 PM EST)]: message)
  - current_datetime injected into Core Agent ## Current Session block (America/New_York)
  - DOCX extraction confirmed: @mazix/n8n-nodes-converter-documents community node installed

affects:
  - 05-01-media-agent (uses sub_agents table, uses @mazix/n8n-nodes-converter-documents for DOCX)
  - 05-02-research-agent (uses sub_agents table, UPDATE workflow_id for research_agent row)
  - 05-03-email-agent (uses sub_agents + pending_emails tables, UPDATE workflow_id for email_agent row)
  - core-agent (YOUR_CORE_AGENT_WORKFLOW_ID) — current_datetime available in session context

# Tech tracking
tech-stack:
  added:
    - "@mazix/n8n-nodes-converter-documents (n8n community node — DOCX/PDF/TXT extraction)"
  patterns:
    - "Migration 006: idempotent DDL via n8n Manual Trigger + Postgres executeQuery node (docker exec stalls on Tachyon)"
    - "sub_agents tool registry: name/description/workflow_id/trigger_hints/capability_id/enabled — capability_id is dot-notation stable ID (media, research.web, email)"
    - "sub_agent_invocations: Layer 1 data accumulation — outcome=NULL at write time; V2 writes good/poor from follow-up signals"
    - "America/New_York timestamp formatting via toLocaleString with timeZone option (handles EST/EDT automatically)"

key-files:
  created:
    - ~/aerys/migrations/006_sub_agents.sql
  modified:
    - ~/aerys/workflows/02-01-discord-adapter.json (ET timestamps in Build Thread Context)
    - ~/aerys/workflows/02-03-core-agent.json (current_datetime in Load Config + all 3 AI Agent nodes)

key-decisions:
  - "Migration file named 006 (not 005) because 005_fix_core_claim_visibility.sql already existed in ~/aerys/migrations/"
  - "DOCX approach: @mazix/n8n-nodes-converter-documents community node installed successfully — 05-01 MUST use this node, not mammoth fallback"
  - "Temp migration workflow deleted after use (FP9T47qa302xg6cq) — production workflows not touched"
  - "current_datetime format: 'Thursday, February 26, 2026 at 2:34 PM EST' (weekday + full date + 12h time + TZ abbreviation)"
  - "sub_agent_invocations outcome column intentionally NULL at write time — V2 feedback loop populates it, not Phase 5"

patterns-established:
  - "Sub-agent routing: capability_id dot-notation (media, research.web, email) is stable machine-readable ID; trigger_hints are LLM fuzzy-match strings"
  - "pending_emails: person_id + 30-minute expiry + status enum (pending/sent/cancelled) — draft-then-confirm requires explicit confirmation before send"

requirements-completed: [AI-03, AI-04, MEDIA-01, MEDIA-02]

# Metrics
duration: ~90min (multi-session)
completed: 2026-03-02
---

# Phase 5 Plan 00: Sub-Agents Schema + DOCX Validation Summary

**sub_agents tool registry, pending_emails, and sub_agent_invocations tables applied via migration 006; DOCX community node installed; ET timestamps and current_datetime wired into guild adapter and Core Agent**

## Performance

- **Duration:** ~90 min (multi-session including two human-verify checkpoints)
- **Started:** ~2026-02-26
- **Completed:** 2026-03-02
- **Tasks:** 4 (Task 1: migration, Task 2a: guild adapter timestamps, Task 2b: Core Agent datetime, Task 4: DOCX approach)
- **Files modified:** 3 infra files + migration SQL

## Accomplishments

- Phase 5 database schema fully provisioned: sub_agents (3 rows), pending_emails, sub_agent_invocations tables all live in Aerys DB
- DOCX extraction confirmed viable: @mazix/n8n-nodes-converter-documents community node installed successfully in n8n — 05-01 media agent can use it directly
- Thread context transcript lines now include America/New_York timestamps (EST/EDT auto-handled), giving sub-agents and Aerys temporal context in conversation history
- Core Agent ## Current Session block now includes current date and time (e.g. "Thursday, February 26, 2026 at 2:34 PM EST") — Aerys can answer "what time is it?" correctly

## Task Commits

All commits are in the infra branch (`~/aerys/`):

1. **Task 1: Write and apply migration 006** - `40557fb` (feat) — sub_agents + pending_emails + sub_agent_invocations DDL applied to Aerys DB
2. **Task 2a: Guild adapter ET timestamps** - `9eccdda` (feat) — Build Thread Context node patched with formatTime helper, America/New_York timezone
3. **Task 2b: Core Agent inject current_datetime** - `e382e83` (feat) — Load Config returns current_datetime; all 3 AI Agent system message nodes updated

_Note: Migration workflow FP9T47qa302xg6cq was deleted after use. DOCX approach (Task 4) was a decision checkpoint with no code commit._

## Files Created/Modified

- `~/aerys/migrations/006_sub_agents.sql` — DDL for sub_agents, pending_emails, sub_agent_invocations with placeholder rows and indexes
- `~/aerys/workflows/02-01-discord-adapter.json` — Build Thread Context node: added formatTime() helper + msgDate() timestamp extraction, ET timezone
- `~/aerys/workflows/02-03-core-agent.json` — Load Config: adds current_datetime field; Haiku/Sonnet/Opus AI Agent nodes: "Time: ..." line added to ## Current Session block

## Decisions Made

**Migration file number:** Named 006 because `005_fix_core_claim_visibility.sql` already existed in `~/aerys/migrations/`. Executor correctly detected the collision and incremented to 006.

**DOCX approach confirmed:** `@mazix/n8n-nodes-converter-documents` installed successfully via n8n Settings > Community Nodes. This is the approach 05-01 MUST use. The mammoth fallback (`NODE_FUNCTION_ALLOW_EXTERNAL=mammoth`) is not needed.

**Temp migration workflow deleted:** FP9T47qa302xg6cq was removed after the migration was verified. Production workflows were not modified for migration purposes.

**current_datetime format:** Full verbose format chosen — "Thursday, February 26, 2026 at 2:34 PM EST" — to give the LLM maximum temporal orientation without ambiguity.

**sub_agent_invocations.outcome is intentionally NULL:** The column exists at schema creation time but is never written by Phase 5 workflows. V2 adaptive routing populates it from user follow-up signals. Phase 5 accumulates the data; V2 reads it. See todo: v2-trigger-hints-feedback-loop.

## Deviations from Plan

**1. [Rule 1 - Bug] Migration file number corrected from 005 to 006**
- **Found during:** Task 1 (Write and apply migration)
- **Issue:** Plan specified filename `005_sub_agents.sql` but `005_fix_core_claim_visibility.sql` already existed in `~/aerys/migrations/` — would have overwritten or conflicted
- **Fix:** Executor named the file `006_sub_agents.sql` and updated commit message accordingly
- **Files modified:** ~/aerys/migrations/006_sub_agents.sql
- **Verification:** Migration applied successfully; no existing migration overwritten
- **Committed in:** 40557fb

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug: filename collision)
**Impact on plan:** Trivial fix, no scope change. Migration outcome identical to plan intent.

## Issues Encountered

**Temp webhook pattern still broken:** As documented in Phase 4 UAT ([04-UAT] note in STATE.md), n8n temp webhook workflows return 404 after PUT/activate cycles. Migration used the Manual Trigger pattern instead — consistent with established workaround.

**current_datetime prompting observation:** After the Core Agent datetime injection was deployed, Aerys had the current_datetime in context but required explicit prompting ("what time is it?") to surface it proactively. This is a prompt tuning observation, not a blocker. Logged for V2 soul.md refinement.

## Next Phase Readiness

Wave 2 (05-01, 05-02, 05-03) can proceed. All dependencies are satisfied:

- sub_agents table queryable with 3 PENDING-05-0N placeholder rows — each plan UPDATEs its row to a real workflow ID after creation
- pending_emails table ready for 05-03 email sub-agent draft-then-confirm flow
- sub_agent_invocations table ready for Phase 5 invocation logging (outcome=NULL until V2)
- @mazix/n8n-nodes-converter-documents installed — 05-01 media agent uses this for DOCX extraction
- No blockers for Wave 2

**Wave 2 dependency note for 05-01:** Use `@mazix/n8n-nodes-converter-documents` community node for DOCX. Do NOT use mammoth fallback or attempt to add `NODE_FUNCTION_ALLOW_EXTERNAL=mammoth` to docker-compose.yml.

---
*Phase: 05-sub-agents-media*
*Completed: 2026-03-02*
