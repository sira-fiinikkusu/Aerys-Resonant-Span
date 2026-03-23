---
plan: 05-04
phase: 05-sub-agents-media
status: complete
completed: 2026-03-04
type: uat-gap-closure
---

# 05-04 UAT Gap Closure — SUMMARY

## What This Was

This was not a new build plan — it was the UAT gap closure session that followed parallel Wave 2 execution (05-01, 05-02, 05-03). Four tests were blocked by bugs not caught during initial build. This document captures all fixes, what caused each failure, and what the final production state of each workflow looks like.

## UAT Results Before This Session

| Test | Description | Status Before |
|------|-------------|--------------|
| 6 | Image analysis | blocker — image not processed |
| 7 | YouTube transcript | blocker — tool triggered, no round-trip |
| 8 | Email read (owner) | blocker — auth gate denied owner |
| 9 | Email gate (non-owner) | skipped (blocked by test 8) |
| 2 | Thread timestamps in context | major — Recent Conversation section missing |

Tests 1, 3, 4, 5, 10 were already passing.

## UAT Results After This Session

| Test | Status | Fix Summary |
|------|--------|-------------|
| 6 | ✓ pass | CDN URL direct, extension detection, orphaned node cleanup |
| 7 | ✓ pass | Innertube approach confirmed, orphaned nodes removed |
| 8 | ✓ pass | toolWorkflow schema, EWT rewiring, fallback fix |
| 9 | ✓ pass | Directive denial text, gate properly enforced |
| 2 | ⚠ open | Not addressed — deferred to Phase 6 investigation |

**Final: 9/10 passing. 1 open (test 2 — thread timestamps, non-blocking).**

---

## Fix 1: Media Sub-Agent — Image and YouTube (Tests 6 & 7)

### Root Causes

**Image:** Two failure modes found in initial UAT:
1. Image-only message (no text) caused workflow errors — `Detect Media Type` catch-all was routing everything without text to error path
2. Image + text message: Aerys saw the text but not the image — the CDN URL was not being passed to the vision API

**YouTube:** Tool triggered correctly but never completed — same underlying issue as image, the sub-workflow was getting the URL as a query string but Detect Media Type wasn't recognizing it.

**Core issue:** The `Core Agent` passes file attachments as a URL string in the `query` field (not as a separate `attachments` field). `Detect Media Type` was checking for an image URL catch-all BEFORE checking file extensions, so PDFs, DOCXs, and TXTs were being routed to the image branch. YouTube URLs were also being misrouted.

**Secondary issue:** `$helpers.getBinaryDataBuffer()` is not available in n8n Code node sandbox. The media agent was attempting to download the Discord CDN attachment and convert to base64 — this failed silently. The correct approach is passing the CDN URL directly to the vision API as `image_url.url`.

**Tertiary issue:** 47 nodes in the media sub-agent included orphaned YouTube nodes from an earlier iteration — dead code that wasn't connected but bloated the workflow.

### Fixes Applied

1. **Detect Media Type reordered:** File extension checks (`.pdf`, `.docx`, `.txt`, YouTube URL patterns) now run BEFORE the image URL catch-all
2. **Discord CDN URL direct:** Vision API calls now pass the full CDN URL as `image_url.url` — no download, no base64 conversion
3. **CDN signature preservation:** URLs passed as-is including `?ex=...&is=...&hm=...` params — never stripped
4. **Orphaned YouTube nodes removed:** 47 → 39 nodes (8 dead nodes removed)
5. **DNS retry:** `retryOnFail: true, maxTries: 3, waitBetweenTries: 2000` added to Send Discord Message — handles transient DNS failures on the Tachyon board

### Media Sub-Agent Final State

- **ID:** `YOUR_MEDIA_SUBAGENT_WORKFLOW_ID`
- **Nodes:** 39
- **Media types confirmed working:** Image (Discord CDN), YouTube (Innertube transcript), DOCX (@mazix converter → `$json.files[0].text`), PDF (extract text), TXT (raw text)
- **Vision cascade:** `google/gemini-2.0-flash-exp:free` → `google/gemini-flash-1.5` → `anthropic/claude-3-haiku`

---

## Fix 2: Email Sub-Agent — Auth Gate (Tests 8 & 9)

### Root Causes

**Three separate bugs, all required for the auth gate to work correctly:**

**Bug 1: toolWorkflow schema:[] makes value dict dead code**

The Core Agent's email toolWorkflow nodes (Tool: Email Sonnet, Tool: Email Opus, Tool: Email Gemini) all had `schema: []`. This is a critical LangChain/n8n behavior: when schema is empty, LangChain generates a single `query` parameter and the entire `workflowInputs` value dict is never evaluated. Every field — including `$json.person_id` — was dead code. The Email Sub-Agent received only `{query: "action: read — check inbox for [user]."}` with no person_id, no account field, nothing.

Confirmed via execution 2721 output: trigger payload was `{query: "action: read — check inbox for pink_princess."}` — exactly what happens when schema:[] collapses everything.

**Bug 2: Check Email Auth was floating (disconnected)**

The Execute Workflow Trigger (EWT) in the Email Sub-Agent was connected to `Parse Email Intent`, not to `Check Email Auth`. The auth gate IF node existed in the workflow but was completely disconnected from the execution path. Every call went straight to parsing intent and executing the email operation — auth was never checked.

**Bug 3: Read Input fallback granted owner access on missing person_id**

Read Input was parsing `trigger.person_id || OWNER_PERSON_ID`. When person_id didn't arrive (due to Bug 1), the fallback made it look like the owner was calling — so the gate passed. This masked Bug 2 during initial development. Once Bug 1 was fixed (person_id arrives), a non-owner's actual UUID failed the gate — but the owner's fallback behavior was still wrong. Changed to `|| 'unknown'` so missing person_id explicitly fails the gate.

### Fixes Applied

**Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID) — all 3 email toolWorkflow nodes:**
```json
"workflowInputs": {
  "schema": [
    {"name": "action", "type": "string"},
    {"name": "person_id", "type": "string"},
    {"name": "to_address", "type": "string"},
    {"name": "subject", "type": "string"},
    {"name": "body_prompt", "type": "string"},
    {"name": "search_query", "type": "string"},
    {"name": "account", "type": "string"}
  ],
  "value": { ... existing value dict unchanged ... }
}
```

**Email Sub-Agent (YOUR_EMAIL_SUBAGENT_WORKFLOW_ID):**
1. Rewired: Execute Workflow Trigger → `Check Email Auth` (was → `Parse Email Intent`)
2. Read Input: `trigger.person_id || 'unknown'` (was `|| OWNER_PERSON_ID`)
3. Email Access Denied: directive text with "EMAIL_ACCESS_DENIED:" prefix

### Email Access Denied Message

The first working denial (after gate was fixed) had Aerys saying "Hitting a wall... try again in a moment" — the Core Agent LLM was rephrasing the denial result creatively. Fixed by returning directive text:

```javascript
return [{json: {
  result: 'EMAIL_ACCESS_DENIED: Email access is restricted to the account owner. Inform the user clearly and directly: you cannot access email for them — this is a permanent restriction, not a temporary issue. Do not suggest trying again or offer workarounds.'
}}];
```

The `EMAIL_ACCESS_DENIED:` prefix + explicit behavioral instruction prevents the LLM from softening, reframing, or treating this as a recoverable error.

---

## Fix 3: User Inbox Read (discovered during Test 8)

Test 8 passed (owner gets inbox), but user observed that only Aerys's inbox was wired. "Check my email" should return the *user's* inbox, not Aerys's. The initial 05-03 build only wired the Aerys Gmail credential for the read path.

### Fix Applied

Added "Route Read by Account" IF node (checks `$json.account === 'user'`) and "Get Recent Emails User" Gmail node (credential `YOUR_GMAIL_USER_CREDENTIAL_ID`) branching from the read path. Read Input's account detection already defaulted to `'user'` for first-person requests ("check my email"), so routing was correct once the branch existed.

`Format Email List` updated to detect account from Read Input and use appropriate framing ("Here's what's in your inbox" vs "Here's what's in my inbox").

### Email Sub-Agent Final State

- **ID:** `YOUR_EMAIL_SUBAGENT_WORKFLOW_ID`
- **Nodes:** 27 (was 20 in 05-03 build)
- **Routes:** compose → send confirm flow, send (direct), read (owner: Aerys inbox | user: Gmail-User inbox), search
- **Auth:** Check Email Auth gates all calls — owner person_id `00000000-0000-0000-0000-000000000001` only
- **Denial:** Directive text, EMAIL_ACCESS_DENIED prefix

---

## Data Cleanup

**n8n_chat_histories:** Sensitive rows from a TXT file processing test (2026-03-04 01:00–03:00 UTC window, session_id `00000000-0000-...`) were deleted via temp workflow. Core Agent memory nodes use `person_id` as session key — cleanup was surgical to only the time window, preserving all other conversation history.

**Execution 2677:** Raw TXT file content stored in n8n's execution_entity table was deleted via MCP `n8n_executions action=delete`.

---

## New Patterns Discovered (added to CLAUDE.md)

| Pattern | Details |
|---------|---------|
| toolWorkflow schema:[] dead value dict | schema:[] collapses all tool input to {query:"..."}. Must define schema fields for $json.* to evaluate |
| Email auth gate wiring | EWT must connect to Check Email Auth FIRST, not Parse Email Intent |
| $helpers.getBinaryDataBuffer unavailable | Pass Discord CDN URL directly as image_url.url |
| CDN URL signature preservation | Never strip ?ex=&is=&hm= params — pass full URL |
| Guild adapter content_type field | Stored as `type`, not `content_type` |
| @mazix DOCX output | Text at $json.files[0].text |
| Send Discord Message DNS retry | retryOnFail x3, 2s for Tachyon DNS stability |
| thread_context snippet | Bumped 80→300 chars in both adapters |
| Email Access Denied directive | EMAIL_ACCESS_DENIED prefix prevents LLM softening |
| n8n_chat_histories session key | session_id = person_id UUID |

---

## New Credentials (added to CLAUDE.md)

| Credential | ID | Used by |
|-----------|----|---------|
| Gmail - Aerys (full) | YOUR_GMAIL_AERYS_CREDENTIAL_ID | Email Sub-Agent — Aerys inbox |
| Gmail - User (read-only) | YOUR_GMAIL_USER_CREDENTIAL_ID | Email Sub-Agent — user inbox |
| OpenRouter Header Auth | YOUR_OPENROUTER_HEADER_CREDENTIAL_ID | Media/Research HTTP Request nodes |
| Google AI - Aerys | YOUR_GOOGLE_AI_CREDENTIAL_ID | YouTube transcript (Gemini direct API) |
| Tavily API | YOUR_TAVILY_HEADER_CREDENTIAL_ID | Research Sub-Agent search |

---

## Workflow Exports (this session)

All exported to `~/aerys/workflows/` from live n8n instance:

| File | Workflow | Nodes |
|------|----------|-------|
| `02-03-core-agent.json` | Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID) | ~45 |
| `02-04-output-router.json` | Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID) | — |
| `05-01-media-agent.json` | Media Sub-Agent (YOUR_MEDIA_SUBAGENT_WORKFLOW_ID) | 39 |
| `05-03-email-agent.json` | Email Sub-Agent (YOUR_EMAIL_SUBAGENT_WORKFLOW_ID) | 27 |
| `05-03-gmail-trigger.json` | Gmail Trigger (YOUR_GMAIL_TRIGGER_WORKFLOW_ID) | 3 |
| `05-03-morning-brief.json` | Morning Brief (YOUR_MORNING_BRIEF_WORKFLOW_ID) | 9 |

---

## Open Items

- **Test 2 (Thread Timestamps):** "## Recent Conversation section no longer appearing after ## Person Profile." Not addressed in Phase 5. System message injection order is documented as correct per aerys-n8n agent. Possible regression from 05-00 datetime injection work. Investigate at start of Phase 6.

---

## Phase 5 Final Requirements Status

| Requirement | Status |
|------------|--------|
| MEDIA-01: Image analysis (Discord + Telegram) | ✓ |
| MEDIA-02: PDF/DOCX/TXT/YouTube extraction | ✓ |
| AI-03: Web research on demand (Tavily) | ✓ |
| AI-04: Research synthesized in Aerys voice | ✓ |
| EMAIL-01: Email read via Gmail OAuth | ✓ |
| EMAIL-02: Email search | ✓ |
| EMAIL-03: Email send + confirm flow | ✓ |
| EMAIL-04: Morning brief workflow | ✓ |
| ROUTING-01: Core Agent routes media/research/email natively | ✓ |
| ROUTING-02: LangChain handles tool detection | ✓ |
| SECURITY-01: Email access gated to owner only | ✓ |
