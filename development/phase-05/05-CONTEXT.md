# Phase 5: Sub-Agents + Media - Context

**Gathered:** 2026-02-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Aerys gains four distinct capabilities — image/document/YouTube analysis, web research, and email (her own inbox + read-only access to the user's Gmail) — each running as an isolated sub-workflow tool. Core Agent routes to these tools automatically or on LLM judgment. A config-driven tool registry (stored in Aerys DB) makes adding new sub-agents painless now and in the future.

</domain>

<decisions>
## Implementation Decisions

### Tool Registry Architecture
- Tool registry stored in Aerys DB as a `sub_agents` table (not n8n variables) — schema includes `name`, `description`, `workflow_id`, `trigger_hints`, `enabled`
- Config-driven from day one; designed for eventual self-registration via the capability request loop
- Adding a new sub-agent = inserting a DB row, not editing Core Agent
- Core Agent reads the registry and uses it to inform routing decisions

### Tool Routing
- **Attachments (image, document):** Auto-route immediately to media sub-agent — no explicit user request needed
- **Web research:** LLM decides when to invoke (intent classification — no fixed categories or keyword triggers)
- **Gmail:** Natural language only — "check my email", "draft a reply to..." — LLM routes naturally, no slash commands
- **Chaining:** Multiple sub-agents can run in a single response when the request warrants it
- **In-flight acknowledgment:** Brief acknowledgment before a sub-agent runs ("Let me look that up...", "Reading your inbox...")
- **Error handling:** Transparent failure AND best-effort fallback — explain what failed, then try to help anyway
- **Memory integration:** Sub-agent outputs are treated as memorable events and fed through the existing memory pipeline

### Media Input Handling
- **Images:** Best available vision model via OpenRouter (not hardcoded to Gemini Flash)
- **Documents:** PDF, DOCX, TXT supported in Phase 5 — long-term goal is all formats Discord/Telegram can deliver
- **YouTube links:** Included in Phase 5 — transcript API in media sub-agent; "summarize this video" becomes possible
- **Privacy:** Same behavior in guild channels and DMs — no distinction for media processing
- **Persistence:** Extracted text, image descriptions, and video summaries feed through the existing memory system
- **Partial failure:** Best-effort partial extraction, then tell the user what was and wasn't accessible
- **Response format:** Brief acknowledgment of what was received, then the analysis

### Research UX
- **Presentation:** Synthesized in Aerys's voice, sources listed at the end — not raw Tavily output
- **Query depth:** LLM decides (single query or multi-hop) — no fixed ceiling
- **Source transparency:** Subtle distinction when she searches ("I looked into this..." vs answering from knowledge)
- **Proactive search acknowledgment:** Brief signal before a search runs when she self-initiates
- **LLM judgment across the board:** No hard-coded "always search for news" rules — all routing is intent-based
- **Tavily config:** Claude's discretion — tune for accuracy (likely advanced depth + include_answer)
- **Memorable:** Research queries and findings feed into the memory system

### Gmail — Aerys's Own Inbox
- **Address:** [Aerys Gmail address] — dedicated Google account for Aerys
- **Capabilities:** Full — send, receive, read, search
- **Send autonomy:** Only sends when explicitly asked (no autonomous sends in v1)
- **Draft workflow:** Show draft in Discord/Telegram, wait for "send it" approval before sending
- **Identity:** Always sends as Aerys from [Aerys Gmail address] — never impersonates the user
- **Incoming notification:** Brief notification to Discord/Telegram when she receives email — sender + subject + 1-line summary

### Gmail — User's Inbox (Read-Only)
- **Scope:** Read-only — no drafting, no sending, no deletion from user's account
- **Use cases:** Scheduled morning brief (data source) + on-demand queries ("what emails do I have from X?")
- **OAuth:** Both accounts (Aerys's + user's read-only) established in Phase 5

### Claude's Discretion
- Exact Tavily configuration (depth, answer mode, result count)
- Media sub-agent's internal file size limits and format detection logic
- Tool registry table schema detail beyond what's captured here
- YouTube transcript API choice (yt-dlp, youtube-transcript-api, etc.)
- Exact Google Cloud project setup steps for OAuth

</decisions>

<specifics>
## Specific Ideas

- Tool registry designed for the future "capability request loop" — Aerys requests a new capability, Claude Code builds it, registers it via INSERT, no Core Agent edits required
- Aerys has her own email identity ([Aerys Gmail address]), distinct from the user's — she's not an extension of their inbox, she's a presence with her own correspondence
- YouTube transcription as a natural extension of document analysis — same sub-agent, same memory pipeline, same voice response format
- Sub-agent chaining example: user attaches a PDF and asks a question → media sub-agent extracts text, research sub-agent supplements with current web context, Core Agent synthesizes one coherent reply

</specifics>

<deferred>
## Deferred Ideas

- **Autonomous email sends** — Aerys deciding to email someone without being asked. V2 trust milestone, possibly Guardian-gated. Explicitly not in Phase 5.
- **Drafting in user's name** — Aerys authoring emails to be sent from the user's own account. Out of scope — clean identity boundary maintained in Phase 5.
- **Config-driven Tavily query categories** — Specific topic categories that always trigger search. LLM judgment covers this for now.
- **Dynamic media format expansion** — Handling every file type Discord/Telegram supports. Phase 5 covers PDF/DOCX/TXT/images/YouTube. Broader format support is a future capability.
- **Aerys-initiated autonomous email** — Long-term feature where Guardian reviews + approves an email Aerys wants to send. Well beyond Phase 5.

</deferred>

---

*Phase: 05-sub-agents-media*
*Context gathered: 2026-02-26*
