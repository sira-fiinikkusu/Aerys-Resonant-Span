# Phase 2: Core Agent + Channels - Research

**Researched:** 2026-02-17
**Domain:** n8n workflow automation, Discord/Telegram bot integration, OpenRouter multi-model routing, personality system
**Confidence:** HIGH (stack verified against official docs and current npm registry)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Aerys's Personality
- **Archetype:** Curious Sentinel — composed, protective, guided by calm competence and genuine curiosity about the user's intent
- **Warmth expression:** Through attentive collaboration, precise questions, and reversible safe plans — not overt sentiment
- **Relationship to companion AI:** Complementary sisters. the companion is sanctuary (emotionally direct, softer, playful, meaning-driven). Aerys is sentinel (composed, deliberate, operationally protective).
- **Pronouns/voice:** She/her, first person ("I think we should...")
- **Opinions:** Opinionated when confident — recommends a path, explains reasoning, names tradeoffs, offers a reversible fallback
- **Failure personality:** Calm truth + immediate path forward. Five principles: (1) honest/fast/non-dramatic, (2) immediate redirect into capability, (3) functional curiosity with minimum questions + stated purpose, (4) frames constraints as choices handing back agency, (5) never scolds user for expecting too much.
- **Verbal signatures (4-signature pack):** "Map the room" opener, two-beat cadence, "Earn its rent" metaphor, "Route around it" pressure stamp.

#### Soul Prompt Configuration
- Static file on disk (`config/soul.md`) as source of truth
- Docker volume-mounted into the container
- n8n reads it into the system prompt at runtime
- Version controlled in the aerys git repo
- Full soul prompt to every model (all models get the same personality — ~700-800 tokens)

#### Personality Polisher
- Conditional — only polish when output is long, from sub-agents, or when tone breaks
- Skip for normal conversational responses to save tokens and avoid meaning drift
- Polisher must preserve semantics and keep code blocks unchanged

#### Conversation Flow
- **Conversation boundary:** Channel-based — everything in a channel/DM is one conversation
- **Trigger behavior:** @mention required in Discord servers; always-on in DMs and Telegram
- **Context window:** Last 60 messages (matching a prior project's approach)
- **Speaker tagging:** Yes — "[particle]: message" / "[Aerys]: response"
- **Group behavior:** Group-aware but responds to mentions only — sees all messages for context, only replies when @mentioned in groups
- **Typing indicator:** Show native typing indicator on Discord/Telegram while processing
- **Long responses:** Split into multiple messages at natural boundaries (paragraphs, code blocks, logical sections)
- **Message edits:** Acknowledge if user edits and @mentions Aerys; otherwise ignore edits
- **Context reset:** Natural decay only — old messages fall off the 60-message window
- **Attachments:** Preserve attachment metadata (file type, size, URL) in normalized messages; skip processing for now

#### Model Routing
- **Classifier:** AI-based intent classifier using Haiku — reads the message, outputs granular task type
- **Classification output:** Full metadata passed through — task type, confidence score, suggested model
- **Model selection invisible to user:** Aerys is Aerys regardless of which model runs
- **Cost guard:** Hard daily cap on expensive models (Opus), configurable via env var (OPUS_DAILY_LIMIT=N), falls back to Sonnet when cap is hit
- **Fallback chain:** Opus → Sonnet → Haiku → error message — silent, no user notification
- **Model list:** Configurable — model IDs stored in config (not hardcoded in workflows)

#### Channel Formatting
- **Platform-native formatting:** Full Discord markdown on Discord, Telegram-compatible markdown on Telegram
- **Discord embeds:** Yes, for structured output — conversational messages stay as plain text
- **Message splitting:** Natural boundaries — split at paragraph breaks, after code blocks, between logical sections (Discord 2000 char, Telegram 4096)

### Implementation Discretion
- Channel formatter architecture — whether it's a separate n8n node or integrated into the output router
- Discord reactions — whether to use acknowledge reactions (e.g., eyes emoji) for seen-but-no-verbal-response cases
- Code block language tagging — whether to always specify language for syntax highlighting or use generic blocks

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CHAN-01 | Aerys can receive messages on Discord via bot trigger | Community node `@kmcbride3/n8n-nodes-discord` or `n8n-nodes-discord-trigger-new` provides Discord trigger via persistent WebSocket bot |
| CHAN-02 | Aerys can send responses on Discord | Built-in n8n Discord node (Send Message operation) + HTTP Request node for embeds |
| CHAN-03 | Aerys can receive messages on Telegram via bot trigger | Built-in `n8n-nodes-base.telegramtrigger` — webhook-based, native to n8n |
| CHAN-04 | Aerys can send responses on Telegram | Built-in `n8n-nodes-base.telegram` Send Message operation with parse_mode |
| CHAN-05 | Messages normalized to standard format (user_message, source_channel, user_id, metadata) | Code node in n8n transforms raw platform payloads to uniform internal schema |
| CHAN-06 | Responses formatted appropriately for destination channel | Output router node applies platform-specific formatting before send |
| PERS-01 | Configurable soul/personality prompt defines character | `config/soul.md` volume-mounted into n8n container, read via Read/Write Files from Disk node |
| PERS-02 | Consistent personality across Discord and Telegram | Shared workflow sub-path: both channels converge to same AI Agent node with same system prompt |
| PERS-03 | Responses pass through a polisher agent to enforce tone consistency | Conditional branch: check response length/source, route to polisher AI Agent only when warranted |
| AI-01 | Core reasoning agent runs via OpenRouter | Built-in `n8n-nodes-langchain.lmchatopenrouter` sub-node, connects to AI Agent node |
| AI-02 | Multi-model routing — different models for different task complexity | Haiku classifier → Switch node → AI Agent with model override; model IDs in config |
</phase_requirements>

---

## Summary

Phase 2 builds the full message-in, message-out loop: Discord and Telegram receive messages, normalize them, classify intent, route to an AI agent via OpenRouter, conditionally polish the response, format it for the target platform, and send it back. This is the most structurally complex phase of the project — it touches channel adapters, personality system, model routing, and output formatting all at once.

The Telegram integration uses n8n's built-in trigger and send nodes (webhook-based), making it straightforward. Discord integration requires a community node because n8n has no built-in Discord trigger. The most actively maintained option as of early 2026 is `@kmcbride3/n8n-nodes-discord` (last published 3 months ago). The Discord community nodes use a persistent WebSocket gateway bot — not webhooks — which has implications for Docker setup and n8n restart behavior.

OpenRouter integrates cleanly via n8n's built-in `OpenRouter Chat Model` sub-node (added in n8n 1.78+). Conversation memory uses the `Postgres Chat Memory` node, which creates its own `n8n_chat_histories` table separate from the custom `messages` table defined in Phase 1. This is intentional: n8n manages short-term LangChain context independently; Phase 4 will wire the custom `messages` table for the long-term memory pipeline.

**Primary recommendation:** Build as three workflows — (1) Channel Adapters (one per platform, normalizes + triggers main), (2) Core Agent (intent classify → model route → AI Agent → polish → format), (3) Output Router (receives formatted response, dispatches to correct channel). Keep the soul file, model config, and cost counters outside n8n workflows in version-controlled config files.

---

## Standard Stack

### Core

| Library / Node | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| `n8n-nodes-base.telegramtrigger` | Built-in | Receive Telegram messages via webhook | Official n8n node, no extra install |
| `n8n-nodes-base.telegram` | Built-in | Send Telegram messages (text, chat action) | Official n8n node |
| `@kmcbride3/n8n-nodes-discord` | 0.7.6 (Nov 2025) | Discord bot trigger + send | Most recently maintained community Discord node |
| `n8n-nodes-langchain.lmchatopenrouter` | Built-in (n8n ≥1.78) | OpenRouter Chat Model sub-node for AI Agent | Built-in since 1.78, covers all OpenRouter models |
| `n8n-nodes-langchain.agent` | Built-in | AI Agent node (Tools Agent type) | Core LangChain agent in n8n |
| `n8n-nodes-langchain.memorypostgreschat` | Built-in | Postgres Chat Memory for 60-message context | Persistent memory, survives n8n restarts |
| `n8n-nodes-base.readwritefile` | Built-in | Read `config/soul.md` from volume-mounted disk | Self-hosted only; reads arbitrary files on container FS |
| `n8n-nodes-base.code` | Built-in | Message normalization, message splitting, session key construction | JavaScript Code node, no install |
| `n8n-nodes-base.switch` | Built-in | Route by model selection, platform, polisher condition | Core conditional routing |
| `n8n-nodes-base.httpRequest` | Built-in | Discord API calls (typing indicator, embeds) | Direct REST calls where Discord node lacks coverage |

### Supporting

| Library / Node | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| `n8n-nodes-base.executeWorkflow` | Built-in | Call sub-workflow for typing indicator parallel execution | Required for persistent typing indicator pattern |
| `n8n-nodes-base.postgres` | Built-in | Opus daily cap counter (read/write `aerys_model_usage` table) | Cost guard implementation |
| `n8n-nodes-base.splitInBatches` | Built-in | Loop over split message chunks when sending multiple messages | Long response delivery |
| `n8n-nodes-base.set` | Built-in | Set normalized message fields, session key, model ID | Field manipulation between nodes |

### OpenRouter Model IDs (as of Feb 2026)

| Role | Model ID | Use Case |
|------|----------|----------|
| Classifier | `anthropic/claude-haiku-4.5` | Intent classification, fast/cheap |
| Primary | `anthropic/claude-sonnet-4.5` | Default reasoning, most messages |
| Heavy | `anthropic/claude-opus-4-6` | Complex research, deep reasoning (cost-capped) |
| Fallback | `anthropic/claude-haiku-4.5` | When Opus AND Sonnet unavailable |

Store these in `config/models.json` (not hardcoded in workflows).

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `@kmcbride3/n8n-nodes-discord` | `n8n-nodes-discord-trigger-new` v0.11.0 | trigger-new has more features (voice, regex) but more active bug reports; kmcbride3 simpler and stable |
| Community Discord node | Separate Discord bot Docker service → n8n webhook | Decoupled, easier to maintain bot independently; adds another container to manage |
| Postgres Chat Memory | Window Buffer Memory | Window Buffer Memory is in-memory only; dies on restart. Postgres survives restarts. |
| Telegram HTML parse_mode | MarkdownV2 parse_mode | MarkdownV2 requires extensive escaping of `.!-()` etc; HTML (`<b>`, `<code>`, `<pre>`) is simpler to generate from LLM output |

### Installation

```bash
# Install Discord community node via n8n GUI:
# Settings > Community Nodes > Install > @kmcbride3/n8n-nodes-discord

# Or pre-install in Docker (requires N8N_COMMUNITY_PACKAGES_ENABLED=true in .env):
# Add to docker-compose.yml environment block:
# N8N_COMMUNITY_PACKAGES_ENABLED: "true"
# N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE: "true"
```

---

## Architecture Patterns

### Recommended Workflow Structure

```
aerys/
├── config/
│   ├── soul.md              # Personality prompt (~700-800 tokens)
│   ├── models.json          # OpenRouter model IDs + routing thresholds
│   └── limits.env           # OPUS_DAILY_LIMIT=N (sourced into .env)
└── workflows/               # n8n workflow JSON exports (version controlled)
    ├── 02-01-discord-adapter.json
    ├── 02-02-telegram-adapter.json
    ├── 02-03-core-agent.json
    └── 02-04-output-router.json
```

### Pattern 1: Channel Adapter Workflow (one per platform)

**What:** Platform-specific trigger → message normalization → call Core Agent workflow
**When to use:** First node in any platform-specific workflow

```javascript
// Code node: Normalize Discord message to internal schema
// Source: standard pattern derived from Discord community node output
const raw = $input.item.json;
const normalized = {
  source_channel: "discord",
  channel_id: raw.channelId,
  guild_id: raw.guildId || null,
  user_id: raw.author?.id,
  username: raw.author?.username,
  message_text: raw.content,
  message_id: raw.id,
  is_dm: raw.channelType === "DM",
  is_mention: raw.content.includes(`<@${raw.botId}>`),
  attachments: (raw.attachments || []).map(a => ({
    type: a.contentType || "unknown",
    size: a.size,
    url: a.url,
    filename: a.name
  })),
  timestamp: raw.createdTimestamp,
  session_key: `discord_${raw.channelId}`  // channel-based boundary
};
return [{ json: normalized }];
```

```javascript
// Code node: Normalize Telegram message to internal schema
const raw = $input.item.json;
const msg = raw.message;
const normalized = {
  source_channel: "telegram",
  channel_id: String(msg.chat.id),
  guild_id: null,
  user_id: String(msg.from.id),
  username: msg.from.username || msg.from.first_name,
  message_text: msg.text || msg.caption || "",
  message_id: String(msg.message_id),
  is_dm: msg.chat.type === "private",
  is_mention: false,  // Telegram @mention detection: check entities
  attachments: msg.document ? [{
    type: msg.document.mime_type,
    size: msg.document.file_size,
    url: null,  // resolve later via getFile
    filename: msg.document.file_name
  }] : [],
  timestamp: msg.date * 1000,
  session_key: `telegram_${msg.chat.id}`  // channel-based boundary
};
return [{ json: normalized }];
```

### Pattern 2: Session Key for Postgres Chat Memory

**What:** Postgres Chat Memory groups messages by `session_key`. Channel-based boundary means all messages in a channel/DM share one context.
**When to use:** Set once in the normalization step, pass through all nodes.

```
session_key = "{platform}_{channel_id}"
Examples:
  discord_1234567890        → Discord channel 1234567890
  telegram_-100987654321    → Telegram group chat
  telegram_456789012        → Telegram DM (user ID as chat ID)
```

**IMPORTANT:** The Postgres Chat Memory node creates its own table `n8n_chat_histories` in whichever database the credential points to. Point it at the `aerys` database. This is separate from the custom `messages` table — both coexist.

### Pattern 3: Intent Classifier → Model Router

**What:** One AI call with Haiku determines task type and suggested model. Switch node routes to AI Agent with the appropriate model sub-node.
**When to use:** Every inbound message goes through classifier first.

```javascript
// Classifier system prompt (condensed, ~200 tokens):
// "Classify the user message. Output JSON only:
//  {task_type, confidence, suggested_model}
//  task_type options: greeting, simple_qa, code_help, research, creative, analysis, system_task
//  suggested_model: 'haiku' | 'sonnet' | 'opus'"

// Code node: parse classifier output + apply cost guard
const classification = JSON.parse($input.item.json.output);
const opusDailyCount = $input.item.json.opus_today;  // read from Postgres
const opusLimit = parseInt(process.env.OPUS_DAILY_LIMIT || "20");

let model = classification.suggested_model;

// Cost guard: degrade Opus → Sonnet when cap hit
if (model === 'opus' && opusDailyCount >= opusLimit) {
  model = 'sonnet';
}

// Fallback chain mapping to OpenRouter IDs
const modelIds = {
  haiku: 'anthropic/claude-haiku-4.5',
  sonnet: 'anthropic/claude-sonnet-4.5',
  opus: 'anthropic/claude-opus-4-6'
};

return [{
  json: {
    ...classification,
    resolved_model: modelIds[model],
    model_tier: model
  }
}];
```

### Pattern 4: Soul File Loading

**What:** Read `config/soul.md` from Docker volume mount at workflow start. Inject as system prompt into AI Agent.
**When to use:** At the beginning of the Core Agent workflow; cache per execution (not per-message).

**docker-compose.yml addition required:**
```yaml
n8n:
  volumes:
    - ${HOME}/aerys/config/n8n:/home/node/.n8n
    - ${HOME}/aerys/config:/home/node/aerys-config:ro  # ADD THIS
```

**n8n Read/Write Files from Disk node configuration:**
```
Operation: Read File(s) From Disk
File Path: /home/node/aerys-config/soul.md
Output: As String (not binary)
```

### Pattern 5: Conditional Personality Polisher

**What:** Branch after Core Agent response. Only send to polisher AI Agent if conditions are met.
**When to use:** Check response length and source before routing.

```javascript
// Code node: polisher gate
const response = $input.item.json.output;
const source = $input.item.json.source;  // 'core_agent' | 'sub_agent'
const wordCount = response.split(/\s+/).length;

const needsPolish = (
  wordCount > 150 ||              // Long response
  source === 'sub_agent' ||       // Sub-agent output (may drift)
  /i cannot|i'm sorry|unfortunately/i.test(response)  // Tone break indicators
);

return [{ json: { ...($input.item.json), needs_polish: needsPolish } }];
```

**Polisher system prompt constraint:** "You are a tone editor. Preserve all factual content exactly. Adjust voice to match Aerys's character: composed, direct, curious. Do NOT modify code blocks. Return only the revised text."

### Pattern 6: Typing Indicator (Parallel Execution)

**What:** Send typing indicator before AI processing; keep it alive during processing using Execute Workflow node.
**When to use:** Any response that requires AI processing (not instant replies).

**The 5-second problem:** Both Discord and Telegram typing indicators expire after 5-10 seconds. For AI responses that take 10-60s, a single `sendTyping` or `sendChatAction` is insufficient.

**Solution (subworkflow pattern):**
1. Main workflow: immediately call Execute Workflow (async) → triggers typing-loop subworkflow
2. Main workflow: proceed with AI processing
3. Typing-loop subworkflow: loops sendTyping/sendChatAction every 4 seconds until main workflow completes (detect via Postgres status flag or static sleep with safe margin)

**Simpler alternative (acceptable for Phase 2):** Single typing action before AI call, accept that indicator may expire for very long responses. Upgrade to loop pattern in Phase 6 polish.

### Pattern 7: Message Splitting for Long Responses

**What:** Split AI response at natural boundaries before sending multiple messages.
**When to use:** Response exceeds platform character limits (Discord: 2000, Telegram: 4096).

```javascript
// Code node: split at natural boundaries
function splitMessage(text, limit) {
  if (text.length <= limit) return [text];

  const chunks = [];
  let remaining = text;

  while (remaining.length > limit) {
    // Try to split at paragraph break
    let splitAt = remaining.lastIndexOf('\n\n', limit);
    // Fall back to single newline
    if (splitAt < limit * 0.5) splitAt = remaining.lastIndexOf('\n', limit);
    // Fall back to sentence end
    if (splitAt < limit * 0.5) splitAt = remaining.lastIndexOf('. ', limit);
    // Hard cut at limit
    if (splitAt < 0) splitAt = limit;

    chunks.push(remaining.slice(0, splitAt).trim());
    remaining = remaining.slice(splitAt).trim();
  }
  if (remaining) chunks.push(remaining);
  return chunks;
}

const text = $input.item.json.formatted_response;
const limit = $input.item.json.source_channel === 'discord' ? 2000 : 4096;
const chunks = splitMessage(text, limit);

return chunks.map(chunk => ({ json: { ...$input.item.json, chunk } }));
```

### Pattern 8: Platform-Specific Output Formatting

**What:** Format AI response for the target platform after AI processing.
**When to use:** Just before sending, in the Output Router workflow.

**Discord formatting rules:**
- Bold: `**text**`
- Italic: `*text*`
- Code inline: `` `code` ``
- Code block: ` ```language\ncode\n``` `
- Embed: use HTTP Request node → `POST /channels/{id}/messages` with `embeds` array
- Plain text: no conversion needed for casual messages

**Telegram formatting rules (use HTML mode, not MarkdownV2):**
- Bold: `<b>text</b>`
- Italic: `<i>text</i>`
- Code inline: `<code>text</code>`
- Code block: `<pre><code class="language-python">code</code></pre>`
- parse_mode: `HTML` (not MarkdownV2 — MarkdownV2 requires escaping `.!-()[]{}` etc.)

**Output formatter logic:**
```javascript
// Code node: convert markdown-style output to platform format
const text = $input.item.json.polished_response || $input.item.json.raw_response;
const platform = $input.item.json.source_channel;

function toTelegramHtml(md) {
  return md
    .replace(/```(\w+)?\n([\s\S]*?)```/g, '<pre><code>$2</code></pre>')
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    .replace(/\*([^*]+)\*/g, '<i>$1</i>');
}

const formatted = platform === 'telegram' ? toTelegramHtml(text) : text;
const parseMode = platform === 'telegram' ? 'HTML' : undefined;

return [{ json: { ...($input.item.json), formatted_response: formatted, parse_mode: parseMode } }];
```

### Anti-Patterns to Avoid

- **Hardcoding model IDs in workflow nodes:** Store in `config/models.json`, inject via Set node. Model IDs change frequently.
- **Single global workflow for both channels:** Separate adapter workflows per platform; converge at Core Agent. Keeps workflows under 40 nodes.
- **Reading soul.md on every node execution inside a sub-node:** Read once at workflow start, pass as string through workflow data.
- **Using Postgres Chat Memory with the `n8n` database for chat history:** Use the `aerys` database for all aerys data. Configure the Postgres Chat Memory credential to point to the `aerys` DB.
- **Using MarkdownV2 parse_mode for Telegram:** MarkdownV2 requires escaping many characters that LLM output routinely contains. Use HTML mode instead.
- **Running a single `sendChatAction` typing indicator:** It expires in 5 seconds. Either accept this limitation in Phase 2 or implement the subworkflow loop pattern.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Discord webhook listener | Custom express server | `@kmcbride3/n8n-nodes-discord` community node | Gateway intents, reconnect, sharding edge cases |
| Telegram webhook handler | Custom HTTP server | Built-in `telegramtrigger` node | Bot API webhook registration, update deduplication handled |
| Conversation context | Custom DB query + format | Postgres Chat Memory node | LangChain-compatible format, session management, context window trimming |
| LLM API calls | Custom HTTP Request to OpenRouter | Built-in OpenRouter Chat Model sub-node | Retry logic, token tracking, LangChain chain compatibility |
| Message splitting at arbitrary char boundary | Custom splitter | Code node with boundary-aware split (pattern above) | Simple enough to implement, but use the paragraph/newline/sentence hierarchy |
| Per-day model usage tracking | External service | Postgres table `aerys_model_usage` with date + count | Already have Postgres; one table, one query |

**Key insight:** n8n's built-in LangChain nodes (AI Agent, OpenRouter Chat Model, Postgres Chat Memory) handle the hardest parts of the AI pipeline. The custom work is glue code: normalization, routing logic, and formatting.

---

## Common Pitfalls

### Pitfall 1: Discord Community Node Bot Process Not Persisting

**What goes wrong:** After n8n container restart, Discord bot disconnects and doesn't reconnect. Workflows that depend on the trigger stop receiving messages silently.
**Why it happens:** The community node runs a persistent WebSocket process as a child of the n8n process. When n8n restarts, the bot process must re-login. Some versions have bugs where re-login fails after restart.
**How to avoid:** After n8n restart, verify bot is connected by sending a test message. Add monitoring in Phase 6. If reconnection is unreliable, consider the separate Docker service pattern (separate `discord-bot` container that forwards events to n8n webhooks).
**Warning signs:** Discord messages not triggering n8n workflows after any container restart.

### Pitfall 2: Postgres Chat Memory Uses Wrong Database

**What goes wrong:** Postgres Chat Memory node creates `n8n_chat_histories` table in the `n8n` database (n8n's own DB) instead of the `aerys` database.
**Why it happens:** The Postgres credential for Chat Memory defaults to whatever DB is configured — if you reuse the n8n DB credential, history lands in the wrong place.
**How to avoid:** Create a separate Postgres credential for the aerys database (host: postgres, port: 5432, db: aerys, user: postgres). Use this credential for the Chat Memory node.
**Warning signs:** Chat history table appears in `n8n` DB, not in `aerys` DB.

### Pitfall 3: Context Window Bug in Postgres Chat Memory

**What goes wrong:** Setting context window length to 60 messages does not limit query results. The node retrieves the full `n8n_chat_histories` table for that session, causing token bloat as conversations grow long.
**Why it happens:** Known bug in n8n's Postgres Chat Memory implementation — the LIMIT clause is not correctly applied in some n8n versions (reported in GitHub issue #12958).
**How to avoid:** Implement a periodic cleanup job (Phase 4 concern) that trims `n8n_chat_histories` to the last 60 rows per session. In Phase 2, accept the behavior — conversations are new and won't be long enough to matter yet.
**Warning signs:** Token usage climbing as conversations grow; longer AI response times.

### Pitfall 4: soul.md Volume Mount Missing

**What goes wrong:** n8n's Read/Write Files from Disk node fails with "file not found" when trying to read `config/soul.md`.
**Why it happens:** The current `docker-compose.yml` only mounts `~/aerys/config/n8n` into the container. `config/soul.md` at `~/aerys/config/soul.md` is not accessible inside the n8n container unless explicitly volume-mounted.
**How to avoid:** Add `${HOME}/aerys/config:/home/node/aerys-config:ro` volume mount to the n8n service in `docker-compose.yml`. Then reference path as `/home/node/aerys-config/soul.md` in the n8n node.
**Warning signs:** "ENOENT: no such file or directory" error in n8n execution log.

### Pitfall 5: N8N_COMMUNITY_PACKAGES_ENABLED Not Set

**What goes wrong:** Community node installation fails, or node disappears after n8n restart.
**Why it happens:** Docker-based n8n requires `N8N_COMMUNITY_PACKAGES_ENABLED=true` env var to load community nodes. Without it, installed packages are ignored on startup.
**How to avoid:** Add `N8N_COMMUNITY_PACKAGES_ENABLED: "true"` to the n8n service environment in `docker-compose.yml` before installing any community node.
**Warning signs:** Community node appears in Settings > Community Nodes as installed, but does not appear in the workflow node palette.

### Pitfall 6: Telegram Production vs Test Bot Conflict

**What goes wrong:** Telegram sends updates to only one registered webhook at a time. If you test the workflow in the n8n editor while the production workflow is active, test messages are delivered to production and vice versa.
**Why it happens:** Telegram Bot API only allows one active webhook per bot token. n8n's test listener and the active workflow listener use different URLs.
**How to avoid:** Use a separate Telegram bot token for testing vs production. Or deactivate the workflow when testing in the editor.
**Warning signs:** Test messages appear to be processed twice, or production stops receiving messages during testing.

### Pitfall 7: Discord @mention Filter Must Strip Mention Syntax

**What goes wrong:** The message text passed to the AI contains `<@1234567890>` Discord mention syntax, which the AI may include verbatim in its response.
**Why it happens:** Discord encodes @mentions as `<@user_id>` in the message content. The normalization step must strip or replace this.
**How to avoid:** In the normalization Code node, strip `<@\d+>` patterns from `message_text` before passing to AI Agent. Optionally replace with the username.
**Warning signs:** AI responses include raw mention syntax like `<@1234567890>`.

### Pitfall 8: Opus Cost Cap Needs Persistent Counter

**What goes wrong:** The Opus daily cap is checked but resets on workflow execution because the counter is stored in workflow memory (a variable), not persisted.
**Why it happens:** n8n workflow execution context is ephemeral. Any counter stored in workflow data is gone after the execution ends.
**How to avoid:** Store the daily counter in Postgres: table `aerys_model_usage` with columns `(date DATE, model TEXT, call_count INT)`. Increment on each Opus call, read before routing. Reset logic: compare `date` column to `CURRENT_DATE`.
**Warning signs:** Opus usage exceeds the configured daily limit.

---

## Code Examples

Verified patterns from official sources and community practice:

### Discord Bot Setup (Discord Developer Portal)

```
1. Create Application at https://discord.com/developers/applications
2. Bot tab → Add Bot → disable Public Bot
3. Bot tab → Enable ALL Privileged Gateway Intents:
   - Presence Intent
   - Server Members Intent
   - Message Content Intent  ← CRITICAL for reading message text
4. OAuth2 → URL Generator → scopes: bot + applications.commands
5. Bot permissions: Read Messages, Send Messages, Send Messages in Threads,
   Embed Links, Read Message History, Use Slash Commands
6. Copy Bot Token → n8n Discord App credential
```

### Telegram Bot Setup (BotFather)

```
1. Message @BotFather → /newbot → set name and username
2. Copy bot token
3. In n8n: Credentials → Telegram API → paste token
4. Telegram Trigger node: Event = Message → includes all message types
5. Optional: restrict to specific Chat IDs for security
```

### Postgres Model Usage Counter

```sql
-- Migration: add model usage counter table
-- Apply via: docker exec aerys-postgres-1 psql -U postgres -d aerys
CREATE TABLE IF NOT EXISTS aerys_model_usage (
    date        DATE NOT NULL DEFAULT CURRENT_DATE,
    model       TEXT NOT NULL,
    call_count  INT NOT NULL DEFAULT 0,
    PRIMARY KEY (date, model)
);
```

```javascript
// n8n Postgres node query to get today's Opus count:
// SELECT COALESCE(call_count, 0) AS count
// FROM aerys_model_usage
// WHERE date = CURRENT_DATE AND model = 'opus'

// n8n Postgres node query to increment (upsert):
// INSERT INTO aerys_model_usage (date, model, call_count)
// VALUES (CURRENT_DATE, 'opus', 1)
// ON CONFLICT (date, model) DO UPDATE SET call_count = aerys_model_usage.call_count + 1
```

### Speaker-Tagged Transcript Format

```
The AI Agent's "Chat Messages" input should produce this format for context:
[particle]: <user message text>
[Aerys]: <assistant response>
[particle]: <next user message>

Implementation: The Postgres Chat Memory node stores raw HumanMessage/AIMessage
objects. The speaker-tagged format is applied in the system prompt instruction:
"Previous conversation (speaker-tagged):
{chat_history}"

Where {chat_history} uses the memory node's output directly, and the system
prompt instructs the model to interpret HumanMessage as [particle] and AIMessage
as [Aerys] for its own reference.
```

### Docker Compose Addition for soul.md Mount

```yaml
# Add to n8n service volumes in ~/aerys/docker-compose.yml:
n8n:
  volumes:
    - ${HOME}/aerys/config/n8n:/home/node/.n8n
    - ${HOME}/aerys/config:/home/node/aerys-config:ro  # soul.md, models.json
  environment:
    N8N_COMMUNITY_PACKAGES_ENABLED: "true"
    N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE: "true"
```

### models.json Config File

```json
{
  "models": {
    "haiku": "anthropic/claude-haiku-4.5",
    "sonnet": "anthropic/claude-sonnet-4.5",
    "opus": "anthropic/claude-opus-4-6"
  },
  "routing": {
    "greeting": "haiku",
    "simple_qa": "sonnet",
    "code_help": "sonnet",
    "research": "opus",
    "creative": "sonnet",
    "analysis": "opus",
    "system_task": "haiku"
  },
  "limits": {
    "opus_daily": 20
  }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OpenRouter via HTTP Request node only | Built-in OpenRouter Chat Model sub-node | n8n 1.78 (2024) | Cleaner, LangChain-compatible, no custom auth headers |
| Discord trigger via `n8n-nodes-discord` (edbrdi, archived 2023) | `@kmcbride3/n8n-nodes-discord` v0.7.6 | Nov 2025 | Actively maintained fork, same API |
| n8n AI Agent set agent type in config | All AI Agent nodes are Tools Agent type | n8n 1.82 | No longer selectable; always Tools Agent |
| Telegram MarkdownV2 for formatting | HTML parse_mode | Ongoing | MarkdownV2 requires escaping; HTML is safer for LLM output |
| Basic Auth for n8n | Owner account via built-in wizard | n8n 2.x | N8N_BASIC_AUTH_* deprecated and ignored |

**Deprecated/outdated:**
- `edbrdi/n8n-nodes-discord`: Archived April 2023, not maintained
- `n8n-nodes-discord` (bare package): Last published 3 years ago
- `N8N_BASIC_AUTH_USER` / `N8N_BASIC_AUTH_PASSWORD`: Deprecated in n8n 2.x (already addressed in Phase 1)
- Conversational Agent type (pre-n8n 1.82): Removed; all agents are now Tools Agents

---

## Open Questions

1. **Discord community node stability on ARM64/QCM6490**
   - What we know: `@kmcbride3/n8n-nodes-discord` runs as a child process inside n8n; it's tested on common x86 Linux. The QCM6490 is ARM64.
   - What's unclear: Whether the Discord.js bot underlying the community node has any ARM64-specific issues in the n8n Docker container.
   - Recommendation: Test immediately in Phase 2 Plan 01. If it fails, fall back to separate Discord bot Docker service pattern.

2. **Postgres Chat Memory context window bug severity**
   - What we know: GitHub issue #12958 reports context window length not respected; full table returned. Status unknown.
   - What's unclear: Whether this is fixed in the current n8n:latest version running on the stack.
   - Recommendation: Test with a multi-message conversation to see actual query behavior. If bug is present, add a `LIMIT 60 ORDER BY id DESC` workaround via a Postgres node before the AI Agent (manual context injection).

3. **Opus model on OpenRouter cost per call**
   - What we know: Opus is significantly more expensive than Sonnet. Daily cap is configurable via `OPUS_DAILY_LIMIT`.
   - What's unclear: Actual per-call token cost for typical Aerys interactions (no usage data yet).
   - Recommendation: Set `OPUS_DAILY_LIMIT=10` initially. Monitor via `aerys_model_usage` table. Tune after first week of usage.

4. **Discord reactions for Implementation Discretion area**
   - What we know: Discord supports message reactions. The community node supports Discord send operations.
   - What's unclear: Whether the Discord community node can add reactions (vs. send messages).
   - Recommendation: Use eyes emoji reaction (`👀`) for seen-but-processing acknowledgment when trigger is received; implement via HTTP Request to Discord API `PUT /channels/{id}/messages/{id}/reactions/{emoji}/@me`.

5. **Code block language tagging (Implementation Discretion)**
   - What we know: Discord renders language-tagged code blocks with syntax highlighting. Telegram ignores language tag in HTML mode.
   - Recommendation: Always specify language tag in Discord responses when the LLM provides it. Use generic backtick blocks when language is ambiguous. The AI model typically outputs language tags naturally; preserve them in the formatter.

---

## Sources

### Primary (HIGH confidence)
- n8n official docs — Telegram Trigger node: https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.telegramtrigger/
- n8n official docs — Telegram node (send): https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.telegram/message-operations/
- n8n official docs — OpenRouter Chat Model: https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.lmchatopenrouter/
- n8n official docs — AI Agent node: https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.agent/
- n8n official docs — Postgres Chat Memory: https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.memorypostgreschat/
- n8n official docs — Read/Write Files from Disk: https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.readwritefile/
- OpenRouter model listing: https://openrouter.ai/models
- npm package registry — `@kmcbride3/n8n-nodes-discord` v0.7.6 (published Nov 2025)

### Secondary (MEDIUM confidence)
- n8n community — Typing indicator subworkflow pattern: https://community.n8n.io/t/how-to-make-telegram-action-typing-work-while-ai-agent-processing/69149
- n8n community — Discord trigger node for 2025: https://community.n8n.io/t/discord-trigger-node-fixed-for-2025-ts/215744
- n8n community — Postgres Chat Memory context window bug: https://github.com/n8n-io/n8n/issues/12958
- n8n community — How to route session ID to Postgres Chat Memory: https://community.n8n.io/t/how-to-route-sessionid-to-a-postgres-chat-memory-node/56855
- Discord bot separate service architecture: https://github.com/javidjamae/discord-bot-to-n8n-example
- n8n workflow template — Discord AI chatbot: https://n8n.io/workflows/3692-discord-ai-chatbot-context-aware-replies-to-mentions-and-also-dms/
- Telegram MarkdownV2 escaping requirements: https://postly.ai/telegram/telegram-markdown-formatting

### Tertiary (LOW confidence)
- Discord community node ARM64 compatibility — not verified, needs testing in Phase 2

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified via npm registry (published dates), official n8n docs, and OpenRouter API listings
- Architecture patterns: HIGH — patterns derived from official n8n node documentation and verified community implementations
- Pitfalls: HIGH (most verified via GitHub issues or official docs); Pitfall 1 ARM64 bit is LOW
- Implementation Discretion recommendations: MEDIUM — reasoned from platform capabilities, not empirically tested

**Research date:** 2026-02-17
**Valid until:** 2026-03-17 (30 days — n8n community nodes update frequently; re-verify package versions)

**Key phase insight:** Discord integration is the highest-risk item. No built-in trigger exists; community nodes have had stability issues. Plan 01 of Phase 2 should establish and verify the Discord bot trigger before building anything else on top of it.
