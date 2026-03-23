# Phase 4: Memory System - Research

**Researched:** 2026-02-23
**Domain:** n8n memory pipeline — short-term session history, long-term vector storage, per-person profiles, pgvector retrieval, Discord channel context, async batch extraction
**Confidence:** HIGH (primary architecture verified against prior project reference JSONs and official n8n docs; LOW on embedding model exact dimensions — schema must use the actual model's output)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Context injection priority:**
- Profile first — person profile is always injected in full
- Short-term history second — verbatim recent conversation (~60 turns, tunable)
- Long-term memories third — injected if space allows after profile + history

**Short-term history format:** Speaker-tagged turns — `[Username]: message`

**Short-term history — pull-on-trigger pattern (a prior project's approach):**
1. On trigger, fetch the last ~30 messages from that channel via Discord API
2. Build speaker-tagged transcript, filtering to human messages before trigger time
3. Add participant summary header (who spoke and how many times)
4. This becomes `thread_context` injected into Core Agent prompt
In parallel (zero latency impact), the same fetched messages feed the long-term memory pipeline.

**In-agent short-term memory:** `memoryBufferWindow` (NOT Postgres Chat Memory) keyed by `channelId` with 30-turn window. Session key: channel ID for group channels, user ID for DMs.

**Cross-channel context:** Both channel-scoped and user-scoped, labeled separately. When user moves from public channel to DM, Aerys carries context from the public conversation.

**Privacy for cross-channel short-term injection:** Hybrid model — DM content crosses to public only if (a) non-private and (b) contains no PII not already shared publicly. Sensitive DM content: hard blocked from public injection.

**Long-term memory injection format:** Claude's discretion.

**Long-term capture trigger:** Hourly scheduled batch job — processes all observed messages from the last hour.

**Long-term capture extraction targets:** Factual statements, emotional moments, decisions made, code/technical content verbatim, interesting conversations.

**Long-term memory storage:** Single table with enforced `privacy_level` tag. Every memory tagged with `source_platform` and `privacy_level` at write time. Retrieval filters by `privacy_level`.

**Summarization model:** Claude's discretion.

**Retrieval strategy:** 70% semantic similarity / 30% recency score. Top 5 memories per turn. Per-user + per-channel. Pre-fetch on message receipt.

**Server member roster:** On each trigger, fetch all server members in parallel with `Get many messages`. Build `userId → displayName` map. Inject into Core Agent prompt alongside thread context.

**Cold start behavior:** Aerys is actively curious — slightly more question-prone with new users.

**Person profile fields:** Basic facts, interests & topics, relationship to Aerys, emotional patterns.

**Personality evolution:** Tone adaptation per-user + relationship depth awareness.

**Profile update trigger:** Same hourly batch job as long-term capture.

**Memory architecture — two-table pattern (adapt from a prior project):**
- `userinfo` table — raw extracted observations
- `core_claim` table — promoted/confirmed facts (injected into prompts)
- Self-asserted facts fast-tracked to `approved` at lower confidence threshold
- Third-party facts start as `provisional`, promoted when multi-source evidence accumulates
- Contradictions demote approved → provisional
- Status flow: `proposed` → `provisional` → `approved` (+ `locked` via user command)
- TTL on provisional claims: ~90 days if not reinforced

**Sensitivity tiers:** P1 (internal only), P2/P3 (user-visible, injectable per privacy rules)

**User memory controls (Discord slash commands):** Five commands — naming decided by Claude (must not collide with the other bot's memory commands, `/memory-lock`, `/memory-forget`, `/memory-correct`). All ephemeral. Show P2/P3 only.

**Override API pattern:** Dedicated internal mutation webhook. All memory write operations route through this internal webhook.

**Embedding model:** Claude's discretion (OpenRouter — quality/cost/dimensionality tradeoff).

**Known flaw to improve on from a prior project's Guardian:** the prior implementation's consolidation groups only by identical `key_label` — misses cross-key entity references. Aerys must use semantic embedding pre-filtering and/or entity-aware grouping before LLM consolidation.

### Claude's Discretion
- Long-term memory injection format (prose, bullets, or inline in system prompt)
- Deduplication strategy for repeated facts
- Summarization model selection
- Embedding model selection (via OpenRouter)
- Exact confidence scoring formula (a prior project's formula is the reference, adapt as needed)
- LLM consolidation approach for conflicting values
- Memory command naming convention (must not conflict with the other bot's commands above)
- Whether override API handles reads or just writes
- Exact short-term history turn limit (60 is baseline, tune based on context window)
- Whether Aerys proactively references public-channel context when user enters a DM
- Architecture for solving the group observation gap

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MEM-01 | Short-term verbatim memory — Aerys references what was said earlier in the same conversation without being reminded | pull-on-trigger pattern with memoryBufferWindow; thread_context transcript injected into system message |
| MEM-02 | Long-term memory — Aerys recalls relevant things from past conversations | hourly batch extraction → pgvector storage → recency+semantic retrieval pre-fetched on message receipt |
| MEM-03 | Per-person profiles — Aerys mentions known facts about a user without being asked | core_claim table → profile API → injected before agent runs |
| MEM-04 | Automatic injection — all memory tiers injected into every conversation without manual triggering | profile API call + pre-fetch on trigger, no user action required |
| MEM-05 | Persistence across restarts — memory survives n8n restarts | Postgres storage for all tiers: n8n_chat_histories (current), memories table (long-term), core_claim table (profiles) |
| MEM-06 | Non-blocking capture — memory capture does not slow down or block Aerys's replies | async parallel branch from Get many messages; batch job runs hourly on schedule, never on reply path |
| MEM-08 | Memory provenance — every memory tagged with source_platform and privacy_level at write time | enforced at INSERT time in memories table; extraction pipeline receives this from normalized message context |
| MEM-09 | Privacy-filtered injection — private memories never surface in public/guild contexts | retrieval WHERE clause filters by privacy_level matching current conversation context |
| PERS-04 | Personality evolution — tone adapts per-user, relationship depth awareness develops over time | core_claim fields for emotional patterns + relationship texture; profile injection gives Aerys this context per turn |
</phase_requirements>

---

## Summary

Phase 4 builds three interconnected memory systems on top of the existing Postgres + pgvector foundation. The architecture is fully specified in CONTEXT.md based on a prior project's memory system reference implementation. The key insight is that all three tiers are designed to operate without blocking the reply path: short-term history is fetched once on trigger and used immediately, long-term retrieval is pre-fetched in parallel with context assembly, and extraction happens in a scheduled batch job that runs after replies have been sent.

The most technically novel aspect of this phase is the two-table profile promotion system (`userinfo` → `core_claim`) with confidence scoring, contradiction detection, and LLM-based entity consolidation. a prior project's implementation has a known flaw — its consolidation groups only by identical key_label, missing cross-key entity references. Aerys's implementation must address this with semantic pre-filtering before the LLM consolidation step.

The critical infrastructure gap to resolve early is the in-agent memory: the current Core Agent uses `memoryPostgresChat` keyed by `person_id`, but the decided pattern switches to `memoryBufferWindow` keyed by `channelId`. These two nodes have different persistence properties: `memoryBufferWindow` is **in-memory only and does not survive n8n restarts** (confirmed by n8n docs). This means MEM-05 (persistence across restarts) requires the pull-on-trigger channel history fetch to serve as the restart-recovery path — after restart, the buffer rebuilds from the Discord channel fetch on next message. This is the intended architecture: the PostgreSQL-backed `n8n_chat_histories` table satisfies MEM-05 for the in-agent buffer, so if Postgres Chat Memory remains in use for the buffer, it satisfies MEM-05. If `memoryBufferWindow` is used instead (as the prior project does), the channel fetch provides effective restart recovery for recent context.

**Primary recommendation:** Build in three sequential plans as outlined in ROADMAP.md: 04-01 (short-term history + channel context), 04-02 (long-term memory pipeline), 04-03 (profiles + memory commands). Each plan is independently testable and additive.

---

## Standard Stack

### Core

| Library / Node | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| `memoryBufferWindow` (n8n Simple Memory) | n8n built-in | In-agent session window keyed by channelId | prior project pattern; channel-scoped, zero DB overhead per turn |
| `memoryPostgresChat` (n8n Postgres Chat Memory) | n8n built-in | Persistent session history survives restarts | Current Aerys pattern; satisfies MEM-05 out of the box |
| n8n Schedule Trigger | n8n built-in | Hourly batch job trigger | Native n8n; no external cron |
| n8n Postgres node | n8n built-in | All DB reads/writes (userinfo, core_claim, memories) | Existing credential `YOUR_POSTGRES_CREDENTIAL_ID` |
| n8n Discord node | n8n built-in | `Get many messages`, `Get many members` operations | Already in use for adapters |
| `vectorstorepgvector` (n8n PGVector Vector Store) | n8n built-in | Insert and retrieve memory embeddings from pgvector | Native integration with existing Postgres |
| `embeddingsOpenAI` (n8n Embeddings OpenAI) | n8n built-in | Generate embeddings via OpenRouter-compatible endpoint | Supports custom `baseURL` option — point at `https://openrouter.ai/api/v1` |
| `pg_try_advisory_lock` | PostgreSQL built-in | Prevent concurrent Guardian runs | Used in a prior project's Guardian — safe for Tachyon |

### Supporting

| Library / Node | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| n8n HTTP Request | built-in | Call internal override API webhook, call profile API | Memory mutation commands, profile injection |
| n8n Switch node | built-in | Route memory commands by type | Slash command dispatcher |
| n8n If node | built-in | Guard logic (lock acquired, memory found) | Guardian and slash command flows |
| `@n8n/n8n-nodes-langchain.lmChatOpenRouter` | installed | LLM consolidation step in Guardian | Already installed in Aerys n8n instance |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `embeddingsOpenAI` node with OpenRouter baseURL | Direct HTTP Request to OpenRouter `/api/v1/embeddings` | HTTP Request cannot be wired as sub-node to PGVector Vector Store — can't use as LangChain embeddings sub-node. Use `embeddingsOpenAI` with baseURL override. |
| `memoryBufferWindow` | `memoryPostgresChat` | Postgres Chat Memory persists across restarts but uses DB on every turn; Buffer Window is faster but in-memory only. Aerys currently uses Postgres Chat Memory — switching to Buffer Window requires understanding the restart recovery path. |
| Hourly batch schedule | Per-message async webhook call | Per-message adds latency variance on the reply path even if non-blocking; batch is cleaner and cost-efficient |
| Two-table (userinfo + core_claim) | Single memories table | Single table is simpler but can't track confidence, promotion status, or contradiction — two-table is required by the architecture |

**Installation:** No new packages needed. All required nodes are built-in or already installed.

---

## Architecture Patterns

### Recommended Workflow Structure

```
04-01: Short-term history + channel context
├── Modifications to: 02-01-discord-adapter.json (guild)
├── Modifications to: 03-03-discord-dm-adapter.json (DM)
├── Modifications to: 02-03-core-agent.json (system message update)
├── New: DB migration 004_memory_system.sql (memories schema additions)
└── Verified: memoryBufferWindow or Postgres Chat Memory keyed by channelId

04-02: Long-term memory pipeline
├── New: 04-02-memory-batch.json (hourly scheduler → extract → embed → store)
├── New: 04-02-memory-retrieval.json (sub-workflow: query pgvector → return top 5)
├── Modifications to: 02-01-discord-adapter.json (pre-fetch memory retrieval trigger)
└── DB migration: privacy_level + source_platform columns on memories table

04-03: Per-person profiles + memory commands
├── New: 04-03-profile-api.json (internal webhook: profile read endpoint)
├── New: 04-03-guardian.json (scheduled promote/demote: userinfo → core_claim)
├── New: 04-03-override-api.json (internal webhook: memory mutation)
├── New: 04-03-memory-commands.json (Discord slash commands for memory management)
├── DB migration: userinfo + core_claim tables, audit_log
└── Modifications to: 03-02-register-discord-commands.json (add 5 new commands)
```

### Pattern 1: Pull-on-Trigger Channel Context (Prior Project Reference)

**What:** When a Discord message triggers the Core Agent, immediately fetch the last 30 messages from that channel via the Discord node (not passively stored). Filter to human messages before the trigger time. Build a speaker-tagged transcript with participant summary header.

**When to use:** Every Discord guild message trigger (not DMs — DMs use the person_id keyed buffer instead)

**Workflow node sequence:**
```
Discord Trigger → Get many messages (limit 30) → [fork]
  Branch A: Build thread context (Code) → Call Profile API → Format Profile Context → Merge
  Branch B: Get many members → Format member list → Merge
  Branch C: Build Vault context (Code) → [async, feeds batch pipeline]
Merge → Clock → AI Agent (with memoryBufferWindow keyed by channelId)
```

**Key code pattern from prior-project-core-workflow (reference) (Build thread context):**
```javascript
// Snowflake to Date helper
function snowflakeToDate(id) {
  try { return new Date(Number((BigInt(id) >> 22n)) + 1420070400000); }
  catch { return null; }
}

// Filter to human messages before trigger time
const humanMsgs = msgs
  .filter(m => {
    const isBot = (m.author && m.author.bot) || m.isBot;
    const hasText = (m.content ?? '').trim().length > 0;
    const mt = msgDate(m);
    const beforeTrigger = mt ? (mt <= triggerTime) : true;
    const notWake = m.id !== trigId;  // exclude the triggering message itself
    return hasText && !isBot && beforeTrigger && notWake;
  });

// Participant summary header
const speakerCounts = {};
humanMsgs.forEach(m => {
  const name = nameOf(m);
  speakerCounts[name] = (speakerCounts[name] || 0) + 1;
});
const participantSummary = `PARTICIPANTS: ${Object.entries(speakerCounts)
  .sort((a,b) => b[1]-a[1])
  .map(([n,c]) => `${n} (${c})`).join(', ')}\n---\n`;

// Speaker-tagged transcript
const lines = humanMsgs.map(m => `${nameOf(m)}: ${m.content.trim()}`);
const transcript = participantSummary + lines.join('\n').slice(0, 5800);
```

**Confidence:** HIGH — directly verified against prior-project-core-workflow (reference)

### Pattern 2: Two-Track Async Context Assembly

**What:** The `Get many messages` response fans out to three branches simultaneously: (A) thread context for the agent, (B) member list fetch, (C) vault context build for async storage. Only A and B block the reply path; C is fire-and-forget.

**When to use:** Every guild message trigger.

**n8n wiring:** `Get many messages` node outputs to three nodes in the `connections` object simultaneously. No `Wait` node on the async path.

**Note from prior project reference:** The `Build Vault context` output feeds `Call VaultLore` which is the async path that does NOT converge with the agent response. In Aerys, this feeds the batch pipeline trigger instead.

**Confidence:** HIGH — verified against prior-project-core-workflow (reference) connection map

### Pattern 3: memoryBufferWindow vs memoryPostgresChat

**Decision required:** The prior project reference uses `memoryBufferWindow` keyed by `channelId`. The current Aerys Core Agent uses `memoryPostgresChat` keyed by `person_id`.

**Key difference:**
- `memoryBufferWindow`: in-memory, **lost on n8n restart**, channel-scoped
- `memoryPostgresChat`: persists to `n8n_chat_histories` table, survives restarts, currently person-scoped

**MEM-05 impact:** If switching to `memoryBufferWindow`, restart recovery relies on the pull-on-trigger channel fetch (which gets recent messages from Discord API). The in-agent buffer rebuilds from channel context on next message. This is adequate for group channels where recent history exists in Discord.

**Recommendation (Claude's discretion):** Keep `memoryPostgresChat` for MEM-05 compliance but change the session key from `person_id` to the correct channel-scoped key per the context decisions:
- Guild Discord: `discord_{channel_id}`
- Discord DM: `dm_{person_id}` (already correct — channel IDs can change for DMs)
- Telegram: `telegram_{chat_id}`

This matches STATE.md architecture notes exactly and satisfies both MEM-05 (persistence) and the "channel-scoped" requirement. The thread_context from the pull-on-trigger fetch provides the group conversation view regardless of which memory backend is used.

**Confidence:** HIGH — verified against n8n docs (Simple Memory is volatile), STATE.md architecture notes

### Pattern 4: Long-term Memory Batch Pipeline

**What:** Scheduled hourly workflow that processes all observed messages from the last hour, extracts facts via LLM, generates embeddings via OpenRouter, stores in `memories` table with provenance tags.

**Node sequence:**
```
Schedule Trigger (hourly)
→ Fetch unseen messages (Postgres: messages table or channel log, WHERE processed_at IS NULL)
→ Group by channel/user context (Code)
→ LLM Extraction (HTTP Request → OpenRouter: Haiku or Sonnet for cost)
  System prompt: extract [facts, emotions, decisions, code verbatim, interests]
  Return structured JSON array of observations
→ For each observation:
  → Embed via Embeddings OpenAI node (baseURL: https://openrouter.ai/api/v1, model: text-embedding-3-small)
  → Insert into memories table (with person_id, source_platform, privacy_level, embedding, content)
→ Mark messages as processed
→ Trigger userinfo insert (same batch job, separate branch)
```

**Confidence:** MEDIUM — pattern inferred from CONTEXT.md decisions + prior project reference structure; exact n8n node wiring requires verification

### Pattern 5: Pre-fetch Retrieval (Zero Latency Impact)

**What:** Memory retrieval starts the moment a message arrives (during adapter normalization), ready before Core Agent fires.

**Where:** In the Discord Adapter workflow (02-01), after Normalize Message but before Execute Core Agent. Add a sub-workflow call: `Execute: Memory Retrieval` passing `person_id` + `channel_id` + `message_text` + `privacy_context`.

**Memory Retrieval sub-workflow:**
```
Execute Workflow Trigger
→ Embed query text (Embeddings OpenAI, OpenRouter baseURL)
→ Vector similarity search (Postgres: SELECT ... ORDER BY embedding <=> $query_embedding ...)
  Apply recency boost: combined_score = 0.7 * cosine_similarity + 0.3 * recency_score
  Filter: WHERE privacy_level <= current_privacy_context
  LIMIT 5
→ Format as memory context string
→ Return to caller
```

**SQL pattern for hybrid retrieval:**
```sql
SELECT content,
  (1 - (embedding <=> $1::vector)) * 0.7
  + (1 - EXTRACT(EPOCH FROM (NOW() - created_at)) / 2592000.0)::numeric * 0.3 AS combined_score
FROM memories
WHERE person_id = $2
  AND deleted_at IS NULL
  AND privacy_level IN ($3)  -- filtered by current conversation privacy
ORDER BY combined_score DESC
LIMIT 5;
```

**Confidence:** MEDIUM — SQL pattern synthesized from CONTEXT.md decisions and pgvector documentation; exact column names depend on migration 004

### Pattern 6: Profile Injection via Internal API

**What:** A dedicated internal webhook workflow that accepts `{user_id, privacy_context}` and returns formatted profile lines from `core_claim` table, filtered by sensitivity tier and privacy context.

**Pattern from prior-project-core-workflow (reference):**
```javascript
// After Call Profile API returns:
const profileData = profileResponse.profile || {};
const displayName = profileData.display_name;
const lines = profileData.lines || [];  // ['• claim text', ...]

let profileContext = '';
if (lines.length > 0) {
  profileContext = `Profile claims:\n${lines.map(l => `  ${l}`).join('\n')}`;
}
```

**Profile API response format:**
```json
{
  "profile": {
    "display_name": "ExampleUser",
    "lines": [
      "• occupation: Software engineer",
      "• location: Example City",
      "• interests: Builds AI assistants, enjoys technology"
    ]
  }
}
```

**Confidence:** HIGH — directly from prior-project-core-workflow (reference) + prior-project-slash-commands (reference)

### Pattern 7: Confidence Scoring Formula (Prior Project Reference, Adapted)

**a prior project's formula (from prior-project-guardian (reference) FetchCandidates SQL):**
```sql
LEAST(1.0,
  0.70 * COALESCE(max_model_conf, 0.5)
  + 0.20 * LEAST(1.0, LN(1 + total_repeat_count) / LN(4))
  + CASE WHEN asserted_by = 'self' THEN 0.20 ELSE 0.05 END
  + CASE WHEN total_repeat_count > 2 THEN 0.10 ELSE 0 END
  - CASE WHEN has_contradiction THEN 0.15 ELSE 0 END
) AS computed_confidence
```

**Promotion thresholds (prior project defaults, adapt as needed):**
- span_days: 7 (fact must appear over at least 7 days)
- min_repeats: 2
- min_confidence: 0.85
- self-asserted promotion threshold: 0.75 (lower)
- TTL on provisional: 90 days

**Entity consolidation improvement over the prior project:**
The prior project groups by identical `key_label` only. Aerys must group candidates by semantic embedding similarity BEFORE the LLM consolidation step. Pre-cluster using pgvector: find all `userinfo` rows for the same `speaker_id` where `embedding <=> candidate_embedding < 0.3` — send the whole cluster to LLM consolidation together.

**Confidence:** HIGH — formula directly from prior-project-guardian (reference) code

### Pattern 8: Override API + Slash Commands

**Pattern from prior-project-slash-commands (reference):**
1. Discord slash command webhook receives interaction
2. Parse: `commandName`, `userId`, `fact` (key search string), `value` (new value for correct)
3. For mutations: `FindMemory` (SQL ILIKE search in `core_claim`) → `PrepareAPI` (build payload) → `CallOverrideAPI` (POST to internal webhook) → `FormatSuccess` → `RespondToWebhook` (type 4, flags 64 = ephemeral)
4. Override API webhook: receives `{action, core_id, ...}`, dispatches to: lock, retract, correct, add

**The other bot's command names (BLOCKED for Aerys):** `/memories`, `/memory-lock`, `/memory-forget`, `/memory-correct`

**Recommended Aerys command names (non-colliding):**
- `/aerys-recall` — list memories (instead of `/memories`)
- `/aerys-pin` — lock a memory (instead of `/memory-lock`)
- `/aerys-forget` — delete a memory (same word is fine — different bot command scope since Discord slash commands are per-application, not globally; but verify with Discord's application-scoped command model)
- `/aerys-correct` — update a memory (instead of `/memory-correct`)
- `/aerys-tell` — add a memory explicitly

**Note on command collision:** Discord slash commands are scoped to the application (bot), not globally. the other bot's commands and Aerys's commands are separate applications and cannot collide by Discord's model. However, using `aerys-` prefix is good UX practice for clarity in shared servers.

**Confidence:** HIGH for pattern; MEDIUM for exact command names (verify no Discord prefix restrictions)

### Anti-Patterns to Avoid

- **Anti-pattern: Postgres Chat Memory keyed by person_id for group channels:** Cross-platform history accumulates in one buffer; Telegram history bleeds into Discord context. Fix: key by channel (already documented in STATE.md architecture notes). The `n8n_chat_histories` table stores history with `session_id` column.
- **Anti-pattern: Embedding on the reply path:** Never call the embedding API during message processing. All embedding happens async (batch) or in the pre-fetch sub-workflow which runs in parallel to context assembly.
- **Anti-pattern: Processing DM content in public memory retrieval:** Every memory `INSERT` must include `privacy_level = 'private'` for DM messages (use `conversation_privacy` field already present on normalized messages). Every retrieval must filter by privacy context.
- **Anti-pattern: Copying a prior project's Guardian verbatim:** The Guardian's LLM consolidation step has the known key_label grouping flaw. Aerys's equivalent must use semantic pre-clustering.
- **Anti-pattern: Blocking the reply path on profile fetch:** Profile API call runs after `Build thread context` but before `AI Agent`. If the profile API is slow, it blocks the reply. Use `onError: continueRegularOutput` + `alwaysOutputData: true` on the HTTP Request node (the prior project does this — see prior-project-core-workflow (reference) `Call Profile API`).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Vector similarity search | Custom cosine distance code | pgvector `<=>` operator + HNSW index already provisioned | Index already exists in 001_init.sql; custom code misses index optimizations |
| In-agent session history | Custom buffer management in Code nodes | `memoryBufferWindow` or `memoryPostgresChat` LangChain nodes | These integrate directly as AI Agent sub-nodes; custom code breaks the LangChain memory protocol |
| Concurrency control for batch job | Custom lock tables | `pg_try_advisory_lock(hashtext('guardian'))` | Postgres native; works across n8n workflow instances without extra tables |
| Embedding generation | Custom HTTP Request + manual vector parsing | `embeddingsOpenAI` node with `baseURL` override | The node handles batching, retry, and is wirable as sub-node to PGVector Vector Store |
| Scheduled batch trigger | External cron / systemd timer | n8n Schedule Trigger node | Already works; adding systemd timers adds operational complexity |

**Key insight:** The n8n node ecosystem handles the LangChain integration protocol. Any node that needs to connect as a sub-node to an AI Agent, Vector Store, or Memory must implement the LangChain sub-node interface — only built-in or community nodes do this. Custom HTTP Request nodes cannot be wired as sub-nodes.

---

## Common Pitfalls

### Pitfall 1: memoryBufferWindow Does Not Survive Restarts
**What goes wrong:** If the Core Agent switches from `memoryPostgresChat` to `memoryBufferWindow` (as the prior project uses), the in-agent conversation history is wiped on every n8n restart. MEM-05 requires persistence.
**Why it happens:** `memoryBufferWindow` is in-process memory only — confirmed by n8n official documentation.
**How to avoid:** Either keep `memoryPostgresChat` (modify only the session key from `person_id` to channel-scoped key), or use `memoryBufferWindow` and accept that the pull-on-trigger channel fetch provides restart recovery for recent history (Discord stores it). The `thread_context` from `Get many messages` serves as the restart recovery path.
**Warning signs:** Users complain Aerys "forgot" everything after a bot restart even though they're in the middle of a conversation.

### Pitfall 2: Embedding Dimensionality Mismatch
**What goes wrong:** The existing `memories` table schema defines `embedding vector(1536)`. If the chosen embedding model outputs a different dimension count, all `INSERT`s will fail with a dimension mismatch error.
**Why it happens:** `text-embedding-3-small` default output is 1536 dimensions. But the `dimensions` parameter can reduce this (e.g., 512). If any dimensions parameter is set, it must match the column definition.
**How to avoid:** Pin the exact embedding call to match the column definition. If switching to a different model (e.g., `text-embedding-3-large` at 3072 dimensions), migration 004 must ALTER the column. The HNSW index must also be rebuilt after column dimension changes.
**Warning signs:** `ERROR: expected 1536 dimensions, not X` in n8n execution logs.

### Pitfall 3: EmbeddingsOpenAI Node baseURL for OpenRouter
**What goes wrong:** The `embeddingsOpenAI` node has a `Base URL` option parameter. If left at default, it calls `https://api.openai.com/v1`. To use OpenRouter, set `Base URL` to `https://openrouter.ai/api/v1`. The API key must be the OpenRouter key (existing credential `YOUR_OPENROUTER_CREDENTIAL_ID`).
**Why it happens:** n8n's OpenRouter LM nodes are chat-only; there is no dedicated OpenRouter Embeddings node. The workaround (confirmed: `embeddingsOpenAI` supports baseURL override) is documented in the node source code.
**How to avoid:** In the `embeddingsOpenAI` node configuration, expand Options and set Base URL to `https://openrouter.ai/api/v1`. Use `openai/text-embedding-3-small` as the model.
**Warning signs:** 401 errors (wrong credentials) or 404 errors (wrong base URL) in embedding calls.

### Pitfall 4: Docker exec psql Timeout on Tachyon
**What goes wrong:** `docker exec aerys-postgres-1 psql` times out on the Tachyon board (known cgroup quirk documented in STATE.md). Migration 004 cannot be run directly via `docker exec`.
**Why it happens:** Tachyon QCM6490 ARM64 with cgroup v1 has a timeout issue with docker exec interactive commands.
**How to avoid:** Run all migrations via the n8n API temp workflow pattern (documented in STATE.md post-03 notes): POST temp workflow → activate → trigger via webhook → GET executions → DELETE. Same pattern used for discord_channel_cache seeding.
**Warning signs:** `docker exec` command hangs indefinitely.

### Pitfall 5: LangChain Agent Output Is a Context Black Hole
**What goes wrong:** Any n8n node downstream of a LangChain AI Agent node only sees `{output: "text"}`. All original input fields (person_id, channel_id, privacy context, memory context) are stripped.
**Why it happens:** LangChain agent node output format — documented in STATE.md post-03 session 2.
**How to avoid:** Any node after a LangChain agent must recover original context via `$('LastNodeBeforeAgent').item.json`. This is already handled in the Core Agent for Prepare Response, but the memory injection nodes in Phase 4 must be placed BEFORE the agent, not after.
**Warning signs:** Memory context is missing from agent output; person_id undefined in downstream nodes.

### Pitfall 6: Privacy Bleed — DM Content in Public Retrieval
**What goes wrong:** Long-term memories extracted from DM conversations surface in guild (public) responses.
**Why it happens:** If the retrieval SQL doesn't filter by `privacy_level`, all memories for a `person_id` are returned regardless of source.
**How to avoid:** Every memory `INSERT` must tag `privacy_level` from `conversation_privacy` field. Every retrieval query must include `WHERE privacy_level IN (SELECT allowed_levels FOR current_context)`. Guild context: only `public` memories. DM context: both `public` and `private` memories.
**Warning signs:** Aerys references something said in a private DM while responding in a public channel.

### Pitfall 7: n8n_chat_histories session_id Column Name
**What goes wrong:** Querying or managing the Postgres Chat Memory table with wrong column name.
**Why it happens:** The table uses `session_id` (snake_case), not `sessionId` (camelCase). Documented in STATE.md.
**How to avoid:** All SQL against `n8n_chat_histories` uses `session_id`. To clear a user's memory: `DELETE FROM n8n_chat_histories WHERE session_id = 'discord_{channel_id}'`.
**Warning signs:** SQL returns 0 rows when trying to manage conversation history.

---

## Code Examples

### Hourly Batch Memory Extraction — LLM Prompt Structure
```
// Source: CONTEXT.md extraction targets + prior project reference pattern
System: You extract structured observations from conversation transcripts.

Extract the following as a JSON array:
- factual_statements: stated facts about who the person is (job, location, relationships)
- emotional_moments: frustration, excitement, distress (mark with emotion_type)
- decisions_made: choices the person committed to
- technical_content: code, configs, technical specs — VERBATIM, never paraphrase
- interests: topics of genuine engagement (games, movies, hobbies)

Return format:
[
  {
    "observation_type": "factual_statement|emotional_moment|decision|technical_content|interest",
    "key_label": "short.snake_case.key",
    "value_text": "the extracted value",
    "asserted_by": "self|third_party",
    "speaker_id": "person_id if identifiable",
    "confidence": 0.0-1.0
  }
]

Conversation:
[TRANSCRIPT]
```

### pgvector Hybrid Retrieval SQL (70/30 blend)
```sql
-- Source: CONTEXT.md retrieval strategy decisions
SELECT
  m.id,
  m.content,
  m.source_platform,
  m.privacy_level,
  m.created_at,
  (1 - (m.embedding <=> $1::vector)) * 0.7
  + LEAST(1.0, GREATEST(0.0,
      1 - EXTRACT(EPOCH FROM (NOW() - m.created_at)) / 2592000.0
    )) * 0.3 AS combined_score
FROM memories m
WHERE m.person_id = $2
  AND m.deleted_at IS NULL
  AND m.privacy_level = ANY($3::text[])
ORDER BY combined_score DESC
LIMIT 5;
-- $1: query embedding vector
-- $2: person_id UUID
-- $3: allowed privacy levels array, e.g. ARRAY['public'] for guild context
```

### memoryBufferWindow Node Configuration (Prior Project Pattern)
```json
{
  "type": "@n8n/n8n-nodes-langchain.memoryBufferWindow",
  "parameters": {
    "sessionIdType": "customKey",
    "sessionKey": "={{ $('Merge context').item.json.channelId }}",
    "contextWindowLength": 30
  }
}
```

### Profile API Response Query
```sql
-- Source: prior-project-slash-commands (reference) QueryMemories pattern, adapted
SELECT core_id, key_label, claim_text, status, locked, confidence
FROM core_claim
WHERE speaker_id = $1
  AND status IN ('approved', 'provisional')
  AND sensitivity IN ('P2', 'P3')
  -- For private context (DMs), include P1 if policy allows
ORDER BY
  CASE WHEN locked THEN 0 ELSE 1 END,
  confidence DESC
LIMIT 15;
```

### Migration 004 — New Tables Schema Outline
```sql
\c aerys

-- Add provenance columns to existing memories table
ALTER TABLE memories
  ADD COLUMN IF NOT EXISTS source_platform TEXT,         -- 'discord', 'telegram'
  ADD COLUMN IF NOT EXISTS privacy_level   TEXT DEFAULT 'public',  -- 'public', 'private'
  ADD COLUMN IF NOT EXISTS batch_job_id    UUID,          -- which batch run extracted this
  ADD COLUMN IF NOT EXISTS processed_at   TIMESTAMPTZ;   -- when message was processed

-- Raw extracted observations (per-mention, before promotion)
CREATE TABLE IF NOT EXISTS userinfo (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  speaker_id      UUID NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
  key_label       TEXT NOT NULL,        -- short.dotted.key
  value_text      TEXT NOT NULL,        -- human-readable value
  value_norm      JSONB DEFAULT '{}',   -- normalized structured value
  sensitivity     TEXT DEFAULT 'P2',    -- P1/P2/P3
  asserted_by     TEXT DEFAULT 'third_party',  -- 'self' | 'third_party'
  source_gist_id  UUID,                -- reference to batch job or memory ID
  model_conf      NUMERIC(4,3),        -- LLM extraction confidence
  first_seen      TIMESTAMPTZ DEFAULT NOW(),
  last_seen       TIMESTAMPTZ DEFAULT NOW()
);

-- Promoted confirmed facts (what gets injected into prompts)
CREATE TABLE IF NOT EXISTS core_claim (
  core_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  speaker_id  UUID NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
  key_label   TEXT NOT NULL,
  claim_text  TEXT NOT NULL,           -- human-readable "key: value"
  value_norm  JSONB DEFAULT '{}',
  sensitivity TEXT DEFAULT 'P2',
  status      TEXT NOT NULL DEFAULT 'proposed',  -- proposed/provisional/approved/locked
  locked      BOOLEAN DEFAULT FALSE,
  confidence  NUMERIC(4,3),
  ttl_ts      TIMESTAMPTZ,
  visibility  TEXT DEFAULT 'server',   -- 'server' | 'dm' | 'all'
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  last_seen   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (speaker_id, key_label)
);

-- Audit log for Guardian promotions and user overrides
CREATE TABLE IF NOT EXISTS audit_log (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  who       TEXT NOT NULL,    -- 'guardian', 'user', 'admin'
  action    TEXT NOT NULL,    -- 'promote', 'demote', 'lock', 'retract', 'correct', 'add'
  details   JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_userinfo_speaker    ON userinfo(speaker_id);
CREATE INDEX IF NOT EXISTS idx_userinfo_key        ON userinfo(speaker_id, key_label);
CREATE INDEX IF NOT EXISTS idx_userinfo_last_seen  ON userinfo(last_seen DESC);
CREATE INDEX IF NOT EXISTS idx_core_claim_speaker  ON core_claim(speaker_id);
CREATE INDEX IF NOT EXISTS idx_core_claim_status   ON core_claim(status) WHERE status != 'proposed';
CREATE INDEX IF NOT EXISTS idx_memories_privacy    ON memories(person_id, privacy_level) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_memories_processed  ON memories(processed_at) WHERE processed_at IS NULL;
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Postgres Chat Memory keyed by person_id | memoryBufferWindow OR Postgres Chat Memory keyed by channelId | Phase 4 (this phase) | Correct channel-scoping; cross-platform contamination eliminated |
| No long-term memory | pgvector + hourly batch extraction | Phase 4 | Aerys remembers across sessions |
| No profile injection | core_claim → profile API → system prompt | Phase 4 | Per-user context always present |
| Processing.env for secrets | n8n variables (sandbox blocks process.env) | Pre-existing | Already handled; no change |

**Confirmed current state going into Phase 4:**
- `memoryPostgresChat` currently in use, keyed by `person_id` — must change session key to channel-scoped
- `memories` table exists with `embedding vector(1536)` — needs provenance columns added
- `n8n_chat_histories` table uses `session_id` column (not `sessionId`)
- No `userinfo` or `core_claim` tables yet
- No batch extraction workflow yet
- No profile API yet
- All messages carry `conversation_privacy` field ('public'/'private') from adapters

---

## Open Questions

1. **memoryBufferWindow vs memoryPostgresChat — which to use?**
   - What we know: Buffer Window matches the prior project; Postgres Chat Memory satisfies MEM-05 out of the box. Switching to Buffer Window with pull-on-trigger channel fetch provides effective recovery.
   - What's unclear: Does the team want guaranteed restart-persistence in the LangChain buffer, or is restart recovery via channel fetch acceptable?
   - Recommendation: Keep `memoryPostgresChat` (change session key only) for MEM-05 compliance with zero risk. Switch to `memoryBufferWindow` only if Postgres Chat Memory causes performance issues at scale.

2. **EmbeddingsOpenAI node + OpenRouter base URL — verified to work?**
   - What we know: The node source code supports a `Base URL` options parameter. OpenRouter has a confirmed embeddings API at `https://openrouter.ai/api/v1/embeddings`. The n8n community reports this as a workaround.
   - What's unclear: Whether this works with the current n8n version on Aerys (verified in node source, but some version-specific issues reported).
   - Recommendation: Test embedding call in 04-02 plan's first task before building the full pipeline. Fallback: use direct HTTP Request to embed + raw Postgres INSERT for vector storage (bypassing PGVector Vector Store node).

3. **How to store batch-extracted content from messages that aren't in the `messages` table?**
   - What we know: The batch job processes "all observed messages from the last hour." The current `messages` table stores individual messages. The batch trigger needs to know which messages haven't been processed yet.
   - What's unclear: Are Discord messages being stored in the `messages` table currently? Or is only `n8n_chat_histories` used?
   - Recommendation: Check current flow — if messages aren't being persisted to `messages` table, the batch job must use a different source (e.g., fetch from Discord API for each observed channel, or process from `n8n_chat_histories`). The `Build Vault context` node in the prior project's pattern receives the already-fetched messages from `Get many messages` — same messages used for both short-term context and long-term storage. Aerys should follow the same pattern: the pull-on-trigger fetch feeds both the thread context AND queues the data for the batch job.

4. **Batch job message deduplication across overlapping hourly windows?**
   - What we know: If the batch runs at :00 and processes messages from :00 to previous :00, there's no overlap. But if the batch job or n8n restarts mid-run, the same messages could be processed twice.
   - What's unclear: Acceptable deduplication strategy.
   - Recommendation: Add `processed_at` column to `messages` table (already in migration 004 outline above). Batch job queries `WHERE processed_at IS NULL` and marks rows on completion. Idempotent upsert on `memories` table using content hash.

---

## Sources

### Primary (HIGH confidence)
- `prior-project-core-workflow (reference)` (`.planning/phases/04-memory-system/`) — Build thread context code, memoryBufferWindow config, profile API pattern, async branch wiring
- `prior-project-guardian (reference)` (`.planning/phases/04-memory-system/`) — confidence formula, promotion logic, advisory lock, LLM consolidation code
- `prior-project-slash-commands (reference)` (`.planning/phases/04-memory-system/`) — override API pattern, slash command dispatch, ephemeral response pattern
- `04-CONTEXT.md` — all locked decisions
- `STATE.md` — session key decisions, n8n_chat_histories column name, docker exec timeout
- `/home/particle/aerys/migrations/001_init.sql` — existing memories table schema (vector(1536))
- `/home/particle/aerys/workflows/02-03-core-agent.json` — current memoryPostgresChat usage, session key
- n8n official docs (WebSearch) — Simple Memory is volatile (not persistent), Postgres Chat Memory persists to DB

### Secondary (MEDIUM confidence)
- OpenRouter embeddings API documentation (`https://openrouter.ai/docs/api/reference/embeddings`) — embeddings endpoint exists, supports text-embedding-3-small
- n8n GitHub source (`EmbeddingsOpenAi.node.ts`) — `Base URL` options parameter confirmed in node source
- n8n community (WebSearch) — EmbeddingsOpenAI with baseURL as OpenRouter workaround; community reports mixed success

### Tertiary (LOW confidence)
- text-embedding-3-small default dimensions = 1536 (multiple sources agree, but verify against actual API response before finalizing schema)
- Discord slash command scoping per-application (assumed from Phase 3 implementation; verify command names don't need `aerys-` prefix)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all nodes are existing n8n built-ins already in use
- Architecture: HIGH — directly derived from prior project reference JSONs and locked CONTEXT.md decisions
- Pitfalls: HIGH — drawn from STATE.md operational history and verified n8n docs
- Embedding specifics: MEDIUM — OpenRouter embedding API confirmed; exact n8n version compatibility needs one-step verification

**Research date:** 2026-02-23
**Valid until:** 2026-03-23 (stable domain — n8n node APIs change slowly; OpenRouter embedding support confirmed active)
