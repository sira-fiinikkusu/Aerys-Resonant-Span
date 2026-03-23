# Phase 4: Memory System - Context

**Gathered:** 2026-02-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Aerys remembers recent conversations verbatim, builds long-term memories from past interactions, maintains per-person profiles, and injects all of this into every conversation automatically — none of it is lost when n8n restarts.

This phase covers: short-term session history, long-term memory pipeline (extraction + storage + retrieval), per-person profiles, and user-facing memory management commands.

Not in scope: multi-modal memory, server-wide analytics, memory sharing between users.

</domain>

<decisions>
## Implementation Decisions

### Context injection priority
- **Profile first** — person profile is always injected in full
- **Short-term history second** — verbatim recent conversation (currently stored via n8n's Postgres Chat Memory node, ~60 turns, Claude may tune limit)
- **Long-term memories third** — injected if space allows after profile + history

### Short-term history format
- **Speaker-tagged turns** — every message stored as `[Username]: message`
- Captures full group thread with attribution, not just Aerys's exchanges
- "Person in the room" model: Aerys is present in the conversation, not just a responder

### Short-term history — pull-on-trigger pattern (solved by a prior project's approach)
the prior project's core workflow solves the group observation problem without passive observation or adapter modification. When triggered, she immediately calls `Get many messages` (Discord API) to retroactively fetch the last N messages from that channel — getting the full room history on demand.

This is the pattern Aerys should adopt:
1. On trigger (any message in an observed channel), fetch the last ~30 messages from that channel via Discord API
2. Build speaker-tagged transcript from those messages (`[Username]: message`), filtering to human messages before the trigger time
3. Add participant summary header (who spoke and how many times) — helps the model understand the room at a glance
4. This becomes the `thread_context` injected into the Core Agent prompt

In parallel (zero latency impact), the same fetched messages feed the long-term memory pipeline (`Build Vault context` → VaultLore equivalent).

**In-agent short-term memory**: Aerys uses **Postgres Chat Memory** (NOT the prior project's `memoryBufferWindow` — Postgres survives n8n restarts, satisfying MEM-05). Session key is **`person_id` for ALL contexts**: Discord guild, Discord DM, Telegram group, and Telegram private. This enables room-to-room following — one continuous conversation buffer per person regardless of which platform or channel they speak in. Privacy isolation is handled by the `conversation_privacy` field in the ## Current Session block and `privacy_level` filtering on long-term memory retrieval (MEM-09), not by session key separation. The `dm_` prefix set in Phase 3 for Discord DMs is being removed for consistency.

### Cross-channel context
- **Both channel-scoped and user-scoped, labeled separately**
- When a user moves from a public channel to a DM, Aerys carries context from the public conversation — she remembers who said what, even across room boundaries
- Whether to proactively reference public-channel context in DMs: Claude's discretion (natural vs intrusive judgment)

### Privacy for cross-channel short-term injection
- **Hybrid model** — not a simple hard block, not a simple filter
- Rule: DM content crosses to public only if it is (a) non-private and (b) contains no PII that the user did not already share publicly
- Sensitive DM content: hard blocked from public injection
- General non-identifying DM content: may surface in public if context warrants it
- This applies to both short-term history injection and long-term memory retrieval

### Long-term memory injection format
- **Claude's discretion** — pick the format (prose block, bullets, inline) that works best for Aerys's LLM attention

### Long-term capture trigger
- **Hourly scheduled batch job** — processes all observed messages from the last hour
- Scope: **all observed messages** (every channel/user Aerys can see, not just conversations she participated in)

### Long-term capture extraction targets
When the LLM summarizes a conversation, extract:
1. **Factual statements** — stated facts about who the user is (job, location, relationships, etc.)
2. **Emotional moments** — frustration, excitement, distress — affective context
3. **Decisions made** — choices the user committed to during the conversation
4. **Code / technical content verbatim** — never paraphrase code, configs, or technical specifics
5. **Interesting conversations** — topics of genuine engagement (games, movies, hobbies, interests)

### Long-term memory storage
- **Single table with enforced privacy_level tag** (not separate DM/public stores)
- Every memory tagged with `source_platform` and `privacy_level` at write time (MEM-08)
- Retrieval always filters by privacy_level — private memories never surface in public contexts (MEM-09)
- Deduplication strategy: Claude's discretion

### Summarization model
- **Claude's discretion** — pick the model that balances extraction quality with hourly cost

### Retrieval strategy
- **Recency + relevance blend** — 70% semantic similarity / 30% recency score
- Rationale: Aerys should feel contextually current (recency) and topically aware (semantic), matching the "person in the room" quality
- **Top 5 memories per turn** — tunable upward if Aerys feels memory-sparse in practice
- **Per-user + per-channel** — retrieves both user-specific memories and channel-level context
- **Pre-fetch on message receipt** — memory retrieval starts when message arrives (during adapter normalization), ready before Core Agent node fires — zero added latency from user perspective

### Server member roster
- On each trigger, fetch all server members in parallel with `Get many messages` (same pattern as the prior project's `Get many members` → `Format member list`)
- Build a `userId → displayName` map and inject it into the Core Agent prompt alongside thread context
- This enables Aerys to resolve names to user IDs for mentions — e.g. "say hi to Bob" → Aerys looks up Bob in the member list → uses `<@userId>` Discord mention syntax in her reply
- Member list also tells Aerys who is *present in the server* (not necessarily active in the current conversation) — context for social awareness

### Cold start behavior
- New users with no prior memory: **Aerys is actively curious** — slightly more question-prone while she builds her picture of them

### Person profile fields
Every user profile tracks:
- Basic facts (name, pronouns, location, occupation — stated facts)
- Interests & topics (hobbies, games, shows, recurring interests)
- Relationship to Aerys (how long they've known each other, notable moments, dynamic)
- Emotional patterns (how they typically show up — playful, serious, stressed — from observed behavior)

### Personality evolution
Both dimensions:
1. **Tone adaptation per-user** — Aerys adjusts her register (more formal/casual) based on how each person interacts with her
2. **Relationship depth awareness** — she knows who's been around a long time vs who's new, and the relationship texture that's developed

### Profile update trigger
- **Same hourly batch job** as long-term capture — one pipeline handles both memory extraction and profile updates

### Memory architecture
Adopt the prior project's two-table pattern (adapt, don't copy verbatim):
- `userinfo` table — raw extracted observations (every mention of a fact goes here)
- `core_claim` table — promoted/confirmed facts (what gets injected into prompts)
- **Self-asserted facts** (`asserted_by: 'self'`) — fast-tracked to `approved` at lower confidence threshold
- **Third-party facts** — start as `provisional`, promoted to `approved` when multi-source evidence accumulates
- **Contradictions** → demote approved → provisional
- Confidence scoring formula and LLM consolidation approach: Claude's discretion (a prior project's formula is the reference)
- Status flow: `proposed` → `provisional` → `approved` (+ `locked` via user command)
- TTL on provisional claims: ~90 days if not reinforced

### Sensitivity tiers (adopted from a prior project's P1/P2/P3)
- **P1** — internal only, never shown to users or injected in any public context
- **P2/P3** — user-visible (slash commands show these), injectable per privacy context rules

### User memory controls (Discord slash commands)
Five commands — **naming decided by Claude** (must not collide with the other bot's existing commands in the same server):
1. List memories (equivalent to the other bot's memory commands)
2. Lock a memory — protect from overwrite
3. Forget a memory — retract/delete
4. Correct a memory — update the value
5. Add a memory — explicitly tell Aerys something she may have missed

All responses: ephemeral (visible only to the requesting user)
Commands show memories at P2/P3 sensitivity only

### Override API pattern
- **Yes, dedicated internal mutation webhook** — same architecture as the prior project's override API
- All memory write operations (lock, retract, correct, add) route through this internal webhook
- This allows multiple callers: slash commands, Aerys herself mid-conversation, future admin tooling
- Read operations (list memories): Claude decides whether to go through the API or query directly

### Embedding model
- **Claude's discretion** — OpenRouter is available with access to all major providers. Pick the model that best balances embedding quality, cost at hourly batch scale, and vector dimensionality for pgvector. Both the long-term memory pipeline (write path) and retrieval (read path) use the same model.

### Claude's Discretion
- Long-term memory injection format (prose, bullets, or inline in system prompt)
- Deduplication strategy for repeated facts
- Summarization model selection
- Embedding model selection (via OpenRouter — choose for quality/cost/dimensionality tradeoff)
- Exact confidence scoring formula (a prior project's formula is the reference, adapt as needed)
- LLM consolidation approach for conflicting values
- Memory command naming convention (must not conflict with the other bot's memory commands, `/memory-lock`, `/memory-forget`, `/memory-correct`)
- Whether override API handles reads or just writes
- Exact short-term history turn limit (60 is the current baseline, tune based on context window)
- Whether Aerys proactively references public-channel context when a user enters a DM
- Architecture for solving the group observation gap (observer flow vs. adapter modification)

### Requirement ID mapping (for plan-checker coverage verification)
MEM-01 through MEM-06 are referenced in the roadmap but not formally defined in PROJECT.md. Mapping inferred from success criteria and PROJECT.md prose:

| ID | Requirement |
|----|-------------|
| MEM-01 | Short-term verbatim memory — Aerys references what was said earlier in the same conversation without being reminded |
| MEM-02 | Long-term memory — Aerys recalls relevant things from past conversations |
| MEM-03 | Per-person profiles — Aerys mentions known facts about a user without being asked |
| MEM-04 | Automatic injection — all memory tiers injected into every conversation without manual triggering |
| MEM-05 | Persistence across restarts — memory survives n8n restarts (stored in Postgres, not in-memory) |
| MEM-06 | Non-blocking capture — memory capture does not slow down or block Aerys's replies (async batch) |
| MEM-08 | Memory provenance — every memory tagged with source_platform and privacy_level at write time |
| MEM-09 | Privacy-filtered injection — private memories (DMs) never surface in public/guild contexts |
| PERS-04 | Personality evolution — tone adapts per-user, relationship depth awareness develops over time |

</decisions>

<specifics>
## Specific Ideas

- **"Person in the room" mental model** — Aerys is present in the space, not just a responder. When you move from a public channel to a DM, she carries the room's conversation with her. She knows who said what.

- **a prior project's memory system as the reference implementation** — Three n8n workflows provided as direct reference:
  - *prior-project-core-workflow (reference)* — Core Discord workflow. Key patterns: pull-on-trigger thread context (Get many messages), parallel Vault context build, memoryBufferWindow keyed by channelId, profile API injection, Polisher pass, error telemetry to debug channel.
  - *prior-project-slash-commands (reference)* — Command surface (4 commands, override API pattern, ephemeral responses, P2/P3 filtering).
  - *prior-project-guardian (reference)* — Promotion logic (userinfo → core_claim, confidence formula, self-vs-third-party assertion, LLM consolidation, pg_advisory_lock, audit log, feature_flags for thresholds). **Known flaw:** consolidation only groups by identical `key_label` — misses cross-key entity references. "tech.vehicle: 2023 EV6", "car: EV6 Jolteon", and "ev6: nickname Jolteon" have different key_labels so they never reach the LLM together and accumulate as separate profile entries. Aerys must do better: semantic embedding pre-filtering and/or entity-aware grouping before LLM consolidation, not just pairwise `value_text` string comparison within the same key.

- **Aerys's memory commands must be distinct** from a prior project's. Both bots live in the same Discord server. The other bot already owns `/memories`, `/memory-lock`, `/memory-forget`, `/memory-correct`. Aerys needs a non-colliding command surface.

- **Actively curious cold start** — when a user is brand new, Aerys should feel slightly more curious and exploratory, not blankly neutral.

- **Top 5 memories is a starting point** — if Aerys feels memory-sparse in use, bump to 7–8. The quality of retrieval (recency+relevance blend) matters more than quantity.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-memory-system*
*Context gathered: 2026-02-23*
