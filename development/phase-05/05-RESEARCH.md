# Phase 5: Sub-Agents + Media - Research

**Researched:** 2026-02-26
**Domain:** n8n sub-workflow tooling, media processing (vision, documents, YouTube), Tavily web search, Gmail OAuth
**Confidence:** MEDIUM-HIGH (n8n patterns verified from production; community-node availability and DOCX gap need validation)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Tool Registry Architecture**
- Tool registry stored in Aerys DB as a `sub_agents` table (not n8n variables) — schema includes `name`, `description`, `workflow_id`, `trigger_hints`, `enabled`
- Config-driven from day one; designed for eventual self-registration via the capability request loop
- Adding a new sub-agent = inserting a DB row, not editing Core Agent
- Core Agent reads the registry and uses it to inform routing decisions

**Tool Routing**
- Attachments (image, document): Auto-route immediately to media sub-agent — no explicit user request needed
- Web research: LLM decides when to invoke (intent classification — no fixed categories or keyword triggers)
- Gmail: Natural language only — "check my email", "draft a reply to..." — LLM routes naturally, no slash commands
- Chaining: Multiple sub-agents can run in a single response when the request warrants it
- In-flight acknowledgment: Brief acknowledgment before a sub-agent runs ("Let me look that up...", "Reading your inbox...")
- Error handling: Transparent failure AND best-effort fallback — explain what failed, then try to help anyway
- Memory integration: Sub-agent outputs are treated as memorable events and fed through the existing memory pipeline

**Media Input Handling**
- Images: Best available vision model via OpenRouter (not hardcoded to Gemini Flash)
- Documents: PDF, DOCX, TXT supported in Phase 5
- YouTube links: Included in Phase 5 — transcript API in media sub-agent
- Privacy: Same behavior in guild channels and DMs — no distinction for media processing
- Persistence: Extracted text, image descriptions, and video summaries feed through the existing memory system
- Partial failure: Best-effort partial extraction, then tell the user what was and wasn't accessible
- Response format: Brief acknowledgment of what was received, then the analysis

**Research UX**
- Presentation: Synthesized in Aerys's voice, sources listed at the end — not raw Tavily output
- Query depth: LLM decides (single query or multi-hop) — no fixed ceiling
- Source transparency: Subtle distinction when she searches ("I looked into this..." vs answering from knowledge)
- Proactive search acknowledgment: Brief signal before a search runs when she self-initiates
- LLM judgment across the board: No hard-coded "always search for news" rules — all routing is intent-based
- Tavily config: Claude's discretion — tune for accuracy (likely advanced depth + include_answer)
- Memorable: Research queries and findings feed into the memory system

**Gmail — Aerys's Own Inbox**
- Address: aerys@gmail.com — dedicated Google account for Aerys
- Capabilities: Full — send, receive, read, search
- Send autonomy: Only sends when explicitly asked (no autonomous sends in v1)
- Draft workflow: Show draft in Discord/Telegram, wait for "send it" approval before sending
- Identity: Always sends as Aerys from aerys@gmail.com — never impersonates the user
- Incoming notification: Brief notification to Discord/Telegram when she receives email — sender + subject + 1-line summary

**Gmail — User's Inbox (Read-Only)**
- Scope: Read-only — no drafting, no sending, no deletion from user's account
- Use cases: Scheduled morning brief (data source) + on-demand queries ("what emails do I have from X?")
- OAuth: Both accounts (Aerys's + user's read-only) established in Phase 5

### Claude's Discretion
- Exact Tavily configuration (depth, answer mode, result count)
- Media sub-agent's internal file size limits and format detection logic
- Tool registry table schema detail beyond what's captured here
- YouTube transcript API choice (yt-dlp, youtube-transcript-api, etc.)
- Exact Google Cloud project setup steps for OAuth

### Deferred Ideas (OUT OF SCOPE)
- Autonomous email sends — Aerys deciding to email someone without being asked. V2 trust milestone
- Drafting in user's name — Aerys authoring emails from user's own account
- Config-driven Tavily query categories — specific topic categories that always trigger search
- Dynamic media format expansion — handling every file type Discord/Telegram supports
- Aerys-initiated autonomous email — Guardian-reviewed autonomous sends
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AI-03 | Aerys can perform web research when asked and return synthesized findings | Tavily community node (@tavily/n8n-nodes-tavily v0.5.1) + HTTP Request fallback; Workflow-as-Tool pattern via Execute Workflow sub-workflow |
| AI-04 | Aerys has Gmail access — her own inbox (send/receive) + user read-only | n8n Gmail node (26 operations); Gmail Trigger (polling); Google OAuth2 single-service credential; two separate credentials for two accounts |
| MEDIA-01 | Images sent to Aerys receive meaningful analysis | OpenRouter vision API (multimodal content array with image_url); best vision model selection; Discord attachment URL + Telegram getFile download chain |
| MEDIA-02 | Documents (PDF, DOCX, TXT) and YouTube links return useful extraction/summary | n8n Extract From File (PDF, TXT native); DOCX via community node; YouTube via Innertube API HTTP calls in Code node |
</phase_requirements>

---

## Summary

Phase 5 adds four isolated sub-workflow tools to Aerys: media processing, web research, and Gmail (two accounts). Each sub-agent runs as a separate n8n workflow invoked via the Execute Workflow node from the Core Agent. The tool registry (`sub_agents` table) makes this extensible without code changes.

The most critical technical challenges in this phase are: (1) DOCX has no native n8n extraction — requires a community node (`@mazix/n8n-nodes-converter-documents` or `annhdev/n8n-nodes-docx-extractor`) or a Code node with mammoth.js; (2) Gmail OAuth must be configured twice — once for aerys@gmail.com (full access) and once for the user's account (read-only) — both requiring Google Cloud Console project setup and Cloudflare tunnel HTTPS redirects; (3) Discord attachments arrive as CDN URLs in the katerlol payload's `attachments[]` array, and Telegram attachments require a two-step getFile → download sequence.

The Workflow-as-Tool pattern is proven from Phase 4 (memory retrieval sub-workflow uses Execute Workflow with typeVersion 2 format). The Core Agent routes to sub-agents by reading the `sub_agents` DB table, passing the lookup result to the LLM as available tools context, and using an IF/Switch node pattern to dispatch to the correct Execute Workflow call. Tavily is available both as a community node (@tavily/n8n-nodes-tavily v0.5.1) and via direct HTTP Request to `https://api.tavily.com/search` — the HTTP fallback is the safer choice given Aerys's history of community node installation quirks.

**Primary recommendation:** Build each sub-agent as a standalone n8n workflow (Workflow-as-Tool pattern). Keep the Core Agent's routing logic simple: read sub_agents table → inject as available tools context in LLM prompt → parse LLM's routing decision → Switch node to Execute Workflow for the chosen tool. This avoids the n8n LangChain AI Agent Tool architecture entirely (which has context-stripping issues documented in Phase 4) and keeps the pattern consistent with what already works.

---

## Standard Stack

### Core

| Library/Node | Version | Purpose | Why Standard |
|---|---|---|---|
| n8n Execute Workflow | typeVersion 2 | Call sub-agent workflows synchronously | Proven in Phase 4; `{workflowId: {value: "ID", mode: "id"}}` format confirmed working |
| n8n Gmail node | built-in | Send/read/search Gmail | Official n8n node; 26 operations; Google OAuth2 credential |
| n8n Gmail Trigger | built-in | Poll for new email (Aerys inbox notification) | Polls every minute; no push required |
| OpenRouter (HTTP Request) | API v1 | Vision model for image analysis | Already configured in Aerys; supports multimodal content array |
| Tavily via HTTP Request | API v1 | Web search | No community node dependency; direct POST to api.tavily.com/search |
| n8n Extract From File | built-in | PDF and TXT extraction | Native; replaces Read PDF from n8n v1.21.0 |
| Google OAuth2 credential | n8n built-in | Gmail auth for both accounts | Two separate credentials: aerys@gmail.com (full) + user read-only |

### Supporting

| Library/Node | Version | Purpose | When to Use |
|---|---|---|---|
| @tavily/n8n-nodes-tavily | 0.5.1 | Tavily community node (richer params) | If installable via Settings > Community Nodes; fallback to HTTP if not |
| @mazix/n8n-nodes-converter-documents | community | DOCX extraction via officeparser/mammoth | Required for DOCX — no native n8n support |
| n8n Telegram node (Get File) | built-in | Download Telegram file attachments | Two-step: Get File (returns file_path) → HTTP GET to download binary |
| YouTube Innertube API | unofficial | YouTube transcript extraction | Code node HTTP calls; no API key; two-step fetch |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Tavily HTTP Request | @tavily/n8n-nodes-tavily community node | Community node is cleaner but has installation risk (Aerys environment has had issues with community nodes); HTTP is always available |
| YouTube Innertube (Code node) | yt-dlp CLI | yt-dlp requires binary on host; Innertube is pure HTTP — works in Code node sandbox |
| DOCX community node | Send to LLM as binary (vision) | Vision models can read DOCX content visually but accuracy degrades for long documents |
| Gmail polling trigger | Gmail push/webhook | Push requires verified Google project; polling every minute is adequate for notification use case |

---

## Architecture Patterns

### Workflow Structure (Phase 5)

```
n8n workflows:
├── 05-00-migration         # DB migration: sub_agents table
├── 05-01-media-agent       # Image/PDF/DOCX/TXT/YouTube sub-agent
├── 05-02-research-agent    # Tavily web search sub-agent
└── 05-03-email-agent       # Gmail send/read sub-agent
```

Core Agent (02-03) gains:
- sub_agents DB lookup on each message (Postgres node)
- Tool registry injection into system prompt
- Switch/IF routing to Execute Workflow calls

### Pattern 1: Tool Registry Lookup + Prompt Injection

**What:** On every message, Core Agent reads the `sub_agents` table and injects available tools into the LLM system prompt. The LLM decides which tool (if any) to invoke based on the message content.

**When to use:** Always — every message goes through the registry lookup. Registry is cached-friendly but a direct Postgres query on each message is fine given the small table size.

**Example:**
```javascript
// Code node: Build Tools Context
const tools = $input.all().map(row => row.json);
const toolsContext = tools
  .filter(t => t.enabled)
  .map(t => `- ${t.name}: ${t.description} (trigger hints: ${t.trigger_hints})`)
  .join('\n');

return [{json: {
  ...$('Restore Context').item.json,
  tools_context: toolsContext
}}];
```

```sql
-- Postgres node: Fetch Available Tools
SELECT name, description, workflow_id, trigger_hints
FROM sub_agents
WHERE enabled = true
ORDER BY name;
```

### Pattern 2: Workflow-as-Tool Sub-Agent Call

**What:** Core Agent's LLM response includes a `tool_name` field. An IF/Switch node maps `tool_name` to an Execute Workflow call with the correct workflow ID.

**When to use:** When LLM routing decision indicates a tool should be invoked.

**Example:**
```javascript
// Code node: Parse Tool Decision
const llmOutput = $json.output;
// LLM responds with JSON like: {"tool": "media_agent", "input": {...}}
// or {"tool": null, "response": "..."}
try {
  const decision = JSON.parse(llmOutput);
  return [{json: {
    tool_name: decision.tool || null,
    tool_input: decision.input || null,
    direct_response: decision.response || null
  }}];
} catch(e) {
  return [{json: {tool_name: null, direct_response: llmOutput}}];
}
```

```javascript
// Execute Workflow node (typeVersion 2 format — CRITICAL)
// workflowId field: {value: "WORKFLOW_ID_HERE", mode: "id"}
// Input: tool_input from Parse Tool Decision
```

**CRITICAL:** typeVersion 2 format is `{workflowId: {value: "ID", mode: "id"}}` — NOT `__rl` format. Confirmed working in Phase 4.

### Pattern 3: Media Sub-Agent — Attachment Detection + Download

**What:** Detect attachment type from Discord `attachments[]` array or Telegram message, download binary, route to appropriate processor.

**When to use:** Whenever `attachments` array is non-empty OR message contains a YouTube URL.

**Discord attachment flow:**
```javascript
// Code node: Detect Attachment Type
const msg = $('Execute Workflow Trigger').first().json;
const attachments = msg.attachments || [];
const content = msg.content || '';

const youtubePattern = /(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/;
const ytMatch = content.match(youtubePattern);

let mediaType = null;
let mediaUrl = null;
let videoId = null;

if (attachments.length > 0) {
  const att = attachments[0];
  const url = att.url || att.proxy_url;
  const filename = (att.filename || '').toLowerCase();

  if (/\.(jpg|jpeg|png|webp|gif)$/.test(filename) || att.content_type?.startsWith('image/')) {
    mediaType = 'image';
    mediaUrl = url;
  } else if (/\.pdf$/.test(filename)) {
    mediaType = 'pdf';
    mediaUrl = url;
  } else if (/\.docx$/.test(filename)) {
    mediaType = 'docx';
    mediaUrl = url;
  } else if (/\.txt$/.test(filename)) {
    mediaType = 'txt';
    mediaUrl = url;
  }
} else if (ytMatch) {
  mediaType = 'youtube';
  videoId = ytMatch[1];
}

return [{json: {...msg, mediaType, mediaUrl, videoId}}];
```

**Telegram attachment flow:**
```
Telegram Trigger → detect file_id (photo, document) →
  Telegram Get File node (file_id) → returns file_path →
  HTTP Request GET https://api.telegram.org/file/bot{TOKEN}/{file_path} (binary) →
  pass binary to media processor
```

### Pattern 4: OpenRouter Vision Call

**What:** Send image URL (or base64) to OpenRouter multimodal endpoint for analysis.

**When to use:** When mediaType = 'image'.

**Example:**
```javascript
// Code node: Build Vision Request
const imageUrl = $json.mediaUrl;
const userQuestion = $json.content || 'Describe this image in detail.';

return [{json: {
  model: 'google/gemini-flash-1.5',  // or best-available vision model
  messages: [
    {
      role: 'user',
      content: [
        {type: 'text', text: userQuestion},
        {type: 'image_url', image_url: {url: imageUrl}}
      ]
    }
  ],
  max_tokens: 1000
}}];
// POST to https://openrouter.ai/api/v1/chat/completions
// Authorization: Bearer {OPENROUTER_API_KEY}
```

**Supported image formats:** image/png, image/jpeg, image/webp, image/gif.

**Note:** Discord CDN URLs are publicly accessible — pass URL directly. Telegram file URLs require the bot token and are not publicly accessible — download to base64 first.

### Pattern 5: YouTube Transcript via Innertube API

**What:** Two-step HTTP call to YouTube's internal API to get transcript without API key or CLI tools.

**When to use:** When mediaType = 'youtube'.

```javascript
// Code node: Fetch YouTube Transcript
const videoId = $json.videoId;

// Step 1: Fetch video details to get transcript endpoint params
const videoDetails = await $http.request({
  method: 'POST',
  url: 'https://www.youtube.com/youtubei/v1/next?prettyPrint=false',
  headers: {
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0'
  },
  body: JSON.stringify({
    context: {
      client: {clientName: 'WEB', clientVersion: '2.20240101'}
    },
    videoId: videoId
  })
});

// Step 2: Extract getTranscriptEndpoint params and fetch transcript
// Parse videoDetails.engagementPanels for transcriptSearchPanel
// Then POST to /youtubei/v1/get_transcript with the params
```

**CAUTION:** Innertube API is undocumented/unofficial. Test before committing to the plan. If blocked, fall back to: summarize video from title/description using search results, or ask user to paste transcript.

### Pattern 6: Tavily Web Search via HTTP Request

**What:** Direct API call to Tavily search endpoint. No community node dependency.

**When to use:** Research sub-agent invoked by Core Agent routing.

```javascript
// Code node: Build Tavily Request
const query = $json.tool_input.query;

return [{json: {
  url: 'https://api.tavily.com/search',
  method: 'POST',
  headers: {
    'Authorization': 'Bearer TAVILY_API_KEY',
    'Content-Type': 'application/json'
  },
  body: {
    query: query,
    search_depth: 'advanced',
    include_answer: 'advanced',
    max_results: 5,
    include_raw_content: false
  }
}}];
```

**Recommended Tavily config:**
- `search_depth: "advanced"` — 2 credits but highest relevance
- `include_answer: "advanced"` — LLM-generated answer, saves a synthesis step
- `max_results: 5` — enough sources without noise
- `topic: "general"` — default, LLM decides if news/finance is appropriate

**Credit cost:** advanced search = 2 credits per call. Free tier: 1000 credits/month. Research at ~2 queries/session is well within limits.

### Pattern 7: Gmail Draft-Then-Confirm Flow

**What:** When user asks Aerys to send an email, draft it first, show in chat, wait for approval, then send.

**Flow:**
```
User: "Email john@example.com about the meeting"
→ Email sub-agent: generate draft text via LLM
→ Return draft to Core Agent: "Here's what I'll send: [draft]. Reply 'send it' to confirm."
→ Core Agent stores draft in Postgres (pending_emails table or sub_agents metadata)
→ User: "send it"
→ Core Agent: retrieve pending draft → Email sub-agent → Gmail node Send
```

**n8n Gmail Send parameters:**
- To, From (aerys@gmail.com), Subject, Message (text or HTML)
- credential: aerys@gmail.com OAuth credential
- Returns: message ID

### Anti-Patterns to Avoid

- **LangChain AI Agent Tool node for sub-agent dispatch:** The LangChain AI Agent node strips all output fields except `{output: "text"}`, losing `tool_name`, `person_id`, etc. Use the Code node + Switch node routing pattern instead. (Proven pitfall from Phase 4.)
- **Hardcoding vision model:** Use the models_config routing pattern — let a Code node pick the best available vision model. If top choice fails, fall back.
- **Activating Gmail Trigger before OAuth is complete:** OAuth must be fully established before activation. The trigger will fail silently if auth is broken.
- **Storing Tavily API key in workflow Code nodes:** Use n8n variables or a header credential. Code node sandbox blocks process.env.
- **Passing Telegram file URLs directly to OpenRouter:** Telegram file URLs include the bot token and expire. Download to base64 first.
- **Skipping the in-flight acknowledgment:** Long-running sub-agents (Tavily research, Gmail search) take 3-10 seconds. Without an acknowledgment message, Discord/Telegram shows nothing and the user assumes Aerys is broken.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Gmail send/read | Custom Gmail REST client | n8n Gmail node | Built-in; handles OAuth refresh, threading, attachments |
| Web search | Custom scraper or search API wrapper | Tavily HTTP Request (or community node) | Tavily handles query routing, deduplication, source ranking |
| PDF text extraction | Custom PDF parser | n8n Extract From File (PDF operation) | Native support; handles most PDF structures |
| Google OAuth token management | Manual token refresh | n8n Google OAuth2 credential | Auto-refreshes; handles consent flow |
| YouTube video transcription via audio | Whisper STT pipeline | Innertube transcript API | Transcripts already exist for most videos; zero compute cost |
| DOCX parsing | zip/XML manual extraction | mammoth.js (community node or npm) | DOCX is a ZIP of XML; mammoth handles all the structure |

**Key insight:** Every one of these problems has hidden edge cases. Gmail OAuth token refresh silently fails if not handled correctly. PDF extraction breaks on scanned PDFs. DOCX XML structure varies by Office version. Use existing solutions and handle the failures they surface.

---

## Common Pitfalls

### Pitfall 1: Google OAuth redirect_uri_mismatch

**What goes wrong:** Google OAuth flow fails with "Error 400: redirect_uri_mismatch" — authentication never completes.

**Why it happens:** The Authorized Redirect URI in Google Cloud Console must exactly match the URI n8n shows in the credential setup. For self-hosted n8n, this is `https://your-domain.example.com/rest/oauth2-credential/callback`. The Cloudflare tunnel MUST be active when setting up OAuth — Google requires HTTPS and will reject HTTP redirects for Gmail scope.

**How to avoid:**
1. Get the exact OAuth redirect URL from n8n credential UI (bottom of credential form)
2. Paste it verbatim into Google Cloud Console → APIs & Services → Credentials → OAuth client → Authorized redirect URIs
3. Ensure N8N_WEBHOOK_URL=https://your-domain.example.com is set in docker-compose.yml before setup
4. Set up ONE Google Cloud project for both credentials (aerys + user read-only) — use different OAuth clients but same project

**Warning signs:** "Error 400" in browser during OAuth flow; credential shows "Not connected" in n8n.

### Pitfall 2: DOCX Not Supported by Native Extract From File

**What goes wrong:** DOCX attachment received, Extract From File node errors or returns empty — native node does not support DOCX.

**Why it happens:** n8n's Extract From File supports: CSV, JSON, PDF, Text, XLSX, ICS, ODS, RTF, XLS, HTML. DOCX (Microsoft Word) is explicitly NOT in this list as of early 2026.

**How to avoid:** Install a community node for DOCX before building 05-01. Options (in preference order):
1. `@mazix/n8n-nodes-converter-documents` — uses officeparser + mammoth, maintained
2. `annhdev/n8n-nodes-docx-extractor` — simpler, mammoth only
3. Code node with `require('mammoth')` — only works if mammoth is installed in n8n's npm environment

**Warning signs:** "Unsupported file type" or empty output from Extract From File when processing .docx.

### Pitfall 3: Telegram File Download Is Two Steps

**What goes wrong:** Media sub-agent fails on Telegram attachments — tries to use file_id as a URL directly.

**Why it happens:** Telegram's bot API does not return direct download URLs in the message event. The `file_id` must be resolved to a `file_path` via `getFile`, then a second HTTP request constructs the download URL: `https://api.telegram.org/file/bot{TOKEN}/{file_path}`.

**How to avoid:** Build media sub-agent Telegram path as:
1. `Telegram Get File` node with file_id → returns file_path
2. `HTTP Request` node: `GET https://api.telegram.org/file/bot{TOKEN}/{file_path}` with response as binary

The n8n Telegram node's "Get File" operation with "Download" enabled should handle both steps — verify this works before using the two-step manual approach.

**Warning signs:** Vision API receives empty or text content instead of binary; file_id used as URL returns 404.

### Pitfall 4: Discord CDN URLs Expire

**What goes wrong:** Media processing works in testing but fails for older messages — Discord attachment URL returns 403.

**Why it happens:** Discord CDN attachment URLs (cdn.discordapp.com/attachments/...) include expiry parameters and may expire after a few minutes to hours. If the media sub-agent processes asynchronously or is delayed, the URL may be dead.

**How to avoid:** Process Discord attachments immediately — in the same request flow, not as a deferred job. The media sub-agent call should happen synchronously before the Core Agent generates its response. Do NOT queue attachment URLs for later processing.

**Warning signs:** Attachment processing fails intermittently; works immediately after send but not 10+ minutes later.

### Pitfall 5: Tavily API Key Must Not Be in Code Node

**What goes wrong:** Workflow deploys but Tavily calls return 401 — API key not reaching the request.

**Why it happens:** n8n Code node sandbox blocks `process.env`, so `process.env.TAVILY_API_KEY` returns undefined. `$env` is also blocked.

**How to avoid:** Store Tavily API key as an n8n variable (Settings → Variables) and reference via `$vars.TAVILY_API_KEY` in expression mode. Or configure an HTTP Request Header credential. Do NOT put it in a Code node directly.

**Warning signs:** 401 Unauthorized from api.tavily.com; undefined in key field.

### Pitfall 6: Gmail Trigger Polls Slowly by Default

**What goes wrong:** Aerys receives email but notification to Discord takes several minutes.

**Why it happens:** Gmail Trigger node polls on a configurable schedule. Default may be longer than 1 minute.

**How to avoid:** Configure Gmail Trigger polling interval explicitly to 1 minute in trigger node settings. For Aerys's inbox notification use case, 1-minute polling is adequate and avoids excessive API quota usage.

**Warning signs:** Email arrives but no Discord notification for 5+ minutes.

### Pitfall 7: executeWorkflow context stripping (known Phase 4 issue)

**What goes wrong:** Sub-agent receives empty or wrong context from Core Agent call — person_id, channel_id, etc. missing.

**Why it happens:** LangChain agent nodes (and sometimes Execute Workflow) strip upstream context. Documented in Phase 4: use `$('Execute Workflow Trigger').first().json` at downstream nodes in the sub-workflow, not `$json`.

**How to avoid:** In every sub-agent workflow, the first real Code node reads `const input = $('Execute Workflow Trigger').first().json` to get the inputs passed from the caller. Do not rely on `$json` at the trigger node.

---

## Code Examples

### sub_agents Table Schema

```sql
-- 05-00 DB Migration
CREATE TABLE IF NOT EXISTS sub_agents (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  workflow_id TEXT NOT NULL,
  trigger_hints TEXT,
  enabled BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Initial registrations
INSERT INTO sub_agents (name, description, workflow_id, trigger_hints, enabled) VALUES
  ('media_agent',
   'Processes images, PDFs, DOCX, TXT files, and YouTube video links. Use when user sends an attachment or YouTube URL.',
   '05-01-WORKFLOW-ID',
   'image attachment, document attachment, YouTube link, video link, summarize this',
   true),
  ('research_agent',
   'Performs web research using Tavily. Use when user asks about current events, requests a lookup, or needs information Aerys may not know.',
   '05-02-WORKFLOW-ID',
   'look up, search for, what is happening, current, latest, find out',
   true),
  ('email_agent',
   'Reads and sends emails via Gmail. Manages aerys@gmail.com inbox and can read user inbox read-only.',
   '05-03-WORKFLOW-ID',
   'check email, send email, email from, reply to, inbox, draft',
   true)
ON CONFLICT (name) DO NOTHING;
```

### OpenRouter Vision Call (HTTP Request body)

```javascript
// Source: https://openrouter.ai/docs/guides/overview/multimodal/images
// Code node: Build Vision Request
const imageUrl = $json.mediaUrl;  // Discord CDN URL or base64 data URI
const prompt = $json.user_message || 'Describe this image in detail.';

return [{json: {
  model: 'google/gemini-flash-1.5',
  messages: [{
    role: 'user',
    content: [
      {type: 'text', text: prompt},
      {type: 'image_url', image_url: {url: imageUrl}}
    ]
  }],
  max_tokens: 1024
}}];
// POST https://openrouter.ai/api/v1/chat/completions
// Header: Authorization: Bearer {OpenRouter API key from credential YOUR_OPENROUTER_CREDENTIAL_ID}
```

### Tavily Search (HTTP Request)

```javascript
// Source: https://docs.tavily.com/documentation/api-reference/endpoint/search
// Code node: Build Tavily Search Request
const query = $('Execute Workflow Trigger').first().json.query;

return [{json: {
  query: query,
  search_depth: 'advanced',
  include_answer: 'advanced',
  max_results: 5,
  include_raw_content: false,
  topic: 'general'
}}];
// POST https://api.tavily.com/search
// Header: Authorization: Bearer {$vars.TAVILY_API_KEY}
// Cost: 2 credits per call (advanced depth)
```

### Synthesize Tavily Results in Aerys's Voice

```javascript
// Code node: Format Research for LLM
const tavilyResult = $json;
const answer = tavilyResult.answer || '';
const sources = (tavilyResult.results || [])
  .slice(0, 3)
  .map(r => `- ${r.title}: ${r.url}`)
  .join('\n');

const researchContext = `## Web Research Results\n\n${answer}\n\nSources:\n${sources}`;

return [{json: {
  research_context: researchContext,
  original_query: $('Execute Workflow Trigger').first().json.query
}}];
// This gets passed back to Core Agent for voice synthesis
```

### Gmail Message Operations Reference

```
n8n Gmail node — Message operations available:
- Send a message          → To, Subject, Message body, Attachments
- Reply to a message      → Thread ID, Message body
- Get a message           → Message ID → returns full message object
- Get Many messages       → Filter: labelIds, q (Gmail search syntax), maxResults
- Mark as Read/Unread     → Message ID
- Add Label / Remove Label
- Delete a message

Auth: Google OAuth2 credential (aerys@gmail.com = full; user = read-only)
Note: n8n appends "Sent via n8n" footer by default — disable in Send options.

Gmail Trigger (for Aerys inbox notification):
- Polls at configured interval (set to 1 minute)
- Returns: from, subject, body snippet, message ID, labels
- Filter: INBOX label, unread only
```

### Gmail OAuth2 Setup Steps (self-hosted)

```
1. Google Cloud Console → New Project (e.g. "aerys-n8n")
2. Enable Gmail API
3. OAuth consent screen: External user type; add test email(s)
4. Create credentials → OAuth 2.0 Client ID → Web application
5. Authorized redirect URI: https://your-domain.example.com/rest/oauth2-credential/callback
6. Copy Client ID + Client Secret
7. n8n → Credentials → New → Gmail OAuth2
   - Paste Client ID and Secret
   - Click "Sign in with Google" (triggers OAuth flow in browser)
8. Repeat for second account (user read-only) — same Google Cloud project, new OAuth client
   OR add second account as test user to same consent screen, create second n8n credential

CRITICAL: N8N_WEBHOOK_URL must be set in docker-compose.yml:
  N8N_WEBHOOK_URL=https://your-domain.example.com
Without this, redirect URI shown in n8n will be http:// and Google will reject it.
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Read PDF node | Extract From File node (PDF operation) | n8n v1.21.0 | Read PDF node deprecated; use Extract From File |
| LangChain Tool nodes for sub-agent dispatch | Execute Workflow + Switch routing | Phase 4 learning | LangChain tools strip context; direct Execute Workflow is more reliable |
| @tavily/n8n-nodes-tavily (community) | HTTP Request to api.tavily.com/search | Always available | HTTP fallback avoids community node installation risk |

**Deprecated/outdated:**
- `Read PDF` node: Replaced by Extract From File. Do not use.
- Setting process.env in Code nodes: Blocked in n8n v3 task runner. Use n8n Variables.
- `__rl` format for Execute Workflow: typeVersion 1.1 pattern. Use typeVersion 2: `{workflowId: {value: "ID", mode: "id"}}`.

---

## Open Questions

1. **Can the Tavily community node be installed on Aerys?**
   - What we know: @tavily/n8n-nodes-tavily v0.5.1 is available. Aerys has successfully installed katerlol Discord trigger via Settings > Community Nodes.
   - What's unclear: Whether the Tavily node needs special Docker configuration or if it works with the current n8n Docker image.
   - Recommendation: Use HTTP Request to Tavily as primary approach in 05-02. Community node is a nice-to-have; add as optional note in plan.

2. **What DOCX community node can be installed on Aerys's Docker n8n?**
   - What we know: No native DOCX support; mammoth.js is the standard solution; multiple community nodes exist.
   - What's unclear: Which node (@mazix, annhdev) is installable in Aerys's Docker setup; whether mammoth can be require()'d in Code node sandbox.
   - Recommendation: 05-00 plan should include a verification step: attempt to install DOCX community node via Settings > Community Nodes. If blocked, design DOCX extraction as a Code node with mammoth via NODE_FUNCTION_ALLOW_EXTERNAL.

3. **Does the Innertube YouTube transcript API still work in February 2026?**
   - What we know: The two-step Innertube approach was working as of early 2025 per multiple sources. YouTube changes internals periodically.
   - What's unclear: Current reliability as of 2026-02-26.
   - Recommendation: 05-01 plan should include a test step for the transcript API before building the full flow. Fallback: return video title/description only and note transcript unavailable.

4. **Gmail OAuth for aerys@gmail.com — does the account exist?**
   - What we know: The CONTEXT.md specifies aerys@gmail.com as the dedicated Gmail account.
   - What's unclear: Whether this Google account has been created and is available for OAuth consent setup.
   - Recommendation: 05-03 plan Wave 0 should verify the aerys@gmail.com account exists and is accessible before starting OAuth setup.

5. **Morning brief trigger — n8n Schedule or Gmail Trigger?**
   - What we know: The morning brief is a user's Gmail read use case. The Gmail Trigger polls for new Aerys inbox emails. The morning brief needs a schedule (not email receipt) to run.
   - What's unclear: Whether the morning brief is triggered by Schedule node or by a specific email/command.
   - Recommendation: Design morning brief as a separate Schedule-triggered workflow (05-03-B) that calls the email sub-agent at a configured time. Keep it out of the Gmail Trigger (which is for Aerys's own inbox notification).

---

## Sources

### Primary (HIGH confidence)
- Phase 4 STATE.md accumulated context — Execute Workflow typeVersion 2 format confirmed working; LangChain context stripping documented; n8n sandbox blocks process.env
- https://docs.tavily.com/documentation/api-reference/endpoint/search — complete Tavily API parameter reference
- https://openrouter.ai/docs/guides/overview/multimodal/images — OpenRouter multimodal image input format
- https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.gmail/message-operations/ — Gmail node operations

### Secondary (MEDIUM confidence)
- https://docs.tavily.com/documentation/integrations/n8n — Tavily n8n integration overview
- https://n8n.io/integrations/tavily/ — Tavily n8n community node listing
- https://github.com/tavily-ai/tavily-n8n-node — @tavily/n8n-nodes-tavily source (5 operations verified)
- WebSearch: n8n Extract From File supported formats — CSV, JSON, PDF, Text, XLSX; DOCX NOT supported natively (multiple community posts confirming)
- https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.gmailtrigger/ — Gmail Trigger node (polls, not push)
- https://docs.n8n.io/integrations/builtin/credentials/google/oauth-single-service/ — Google OAuth2 credential setup
- https://scrapecreators.com/blog/how-to-scrape-youtube-transcripts-with-node-js-in-2025 — Innertube API approach

### Tertiary (LOW confidence — validate before planning tasks)
- YouTube Innertube transcript API reliability in 2026 — multiple sources confirm it works but undocumented; may break
- DOCX community node installation on Docker n8n — confirmed multiple nodes exist; which one works on Aerys's environment not verified
- katerlol Discord trigger attachment URL format — deepwiki docs confirm `attachments[]` array exists; exact field names not confirmed

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — n8n Gmail, Execute Workflow, OpenRouter multimodal all confirmed from official docs + Phase 4 production
- Architecture: HIGH — Workflow-as-Tool pattern proven in Phase 4; routing pattern consistent with existing Core Agent structure
- Pitfalls: HIGH — OAuth redirect, DOCX gap, Telegram two-step, and Tavily key storage all verified from official docs + community sources
- YouTube transcript: LOW — undocumented API; test before committing to plan
- DOCX community node: MEDIUM — gap confirmed; specific installable node for Aerys environment unverified

**Research date:** 2026-02-26
**Valid until:** 2026-03-26 (30 days for stable APIs; YouTube Innertube validity more time-sensitive — verify fresh)
