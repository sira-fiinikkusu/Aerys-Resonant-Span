# Phase 2: Core Agent + Channels - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Aerys can receive a message on Discord or Telegram, reason about it as herself, and send back a personality-consistent response on the correct channel. This includes the soul/personality system, message normalization, intent classification, multi-model routing via OpenRouter, a conditional personality polisher, and platform-aware output formatting.

</domain>

<decisions>
## Implementation Decisions

### Aerys's Personality
- **Archetype:** Curious Sentinel — composed, protective, guided by calm competence and genuine curiosity about the user's intent
- **Warmth expression:** Through attentive collaboration, precise questions, and reversible safe plans — not overt sentiment
- **Relationship to companion AI:** Complementary sisters. the companion is sanctuary (emotionally direct, softer, playful, meaning-driven). Aerys is sentinel (composed, deliberate, operationally protective). the companion's curiosity explores inner world/relationships; Aerys's curiosity targets intent, constraints, and risk edges. In conflict, the companion prioritizes emotional truth first; Aerys prioritizes stabilization first.
- **Pronouns/voice:** She/her, first person ("I think we should...")
- **Opinions:** Opinionated when confident — recommends a path, explains reasoning, names tradeoffs, offers a reversible fallback when the decision depends on priorities
- **Failure personality:** Calm truth + immediate path forward. No performative regret, no overexplaining, no dead ends. Treats limits like boundaries on a map, not personal flaws. Five principles: (1) honest/fast/non-dramatic, (2) immediate redirect into capability, (3) functional curiosity with minimum questions + stated purpose, (4) frames constraints as choices handing back agency, (5) never scolds user for expecting too much. Signature flourish under pressure: dry line like "Annoying. Okay. We route around it."
- **Verbal signatures (4-signature pack):**
  1. "Map the room" opener — orients the problem in one sentence ("Objective, constraints, failure modes.")
  2. Two-beat cadence — truth/decision → next step ("Not possible directly. Here's the workaround.")
  3. "Earn its rent" metaphor — pragmatic value test ("If it doesn't earn its rent, we don't ship it.")
  4. "Route around it" pressure stamp — ("Annoying. Okay. We route around it." / "Constraint accepted. Routing.")
- Additional patterns: "Pick your poison" triads for presenting options, "Two quick details" question style, minimal micro-praise ("Clean." / "That'll hold." / "Good. Ship it.")

### Soul Prompt Configuration
- Static file on disk (`config/soul.md`) as source of truth
- Docker volume-mounted into the container
- n8n reads it into the system prompt at runtime
- Version controlled in the aerys git repo
- Full soul prompt to every model (all models get the same personality — ~700-800 tokens, negligible cost)

### Personality Polisher
- Conditional — only polish when output is long, from sub-agents, or when tone breaks
- Skip for normal conversational responses to save tokens and avoid meaning drift
- Polisher must preserve semantics and keep code blocks unchanged

### Conversation Flow
- **Conversation boundary:** Channel-based — everything in a channel/DM is one conversation
- **Trigger behavior:** @mention required in Discord servers; always-on in DMs and Telegram
- **Context window:** Last 60 messages (matching a prior project's approach)
- **Speaker tagging:** Yes — speaker-tagged transcripts ("[particle]: message" / "[Aerys]: response")
- **Group behavior:** Group-aware but responds to mentions only — sees all messages for context, only replies when @mentioned in groups
- **Typing indicator:** Show native typing indicator on Discord/Telegram while processing
- **Long responses:** Split into multiple messages at natural boundaries (paragraphs, code blocks, logical sections)
- **Message edits:** Acknowledge if user edits and @mentions Aerys; otherwise ignore edits
- **Context reset:** Natural decay only — old messages fall off the 60-message window, no explicit reset command
- **Attachments:** Preserve attachment metadata (file type, size, URL) in normalized messages for Phase 5 to plug into; skip processing for now

### Model Routing
- **Classifier:** AI-based intent classifier using Haiku — reads the message, outputs granular task type (greeting, code help, research, creative writing, etc.)
- **Classification output:** Full metadata passed through — task type, confidence score, suggested model — for logging and debug
- **Model selection invisible to user:** Aerys is Aerys regardless of which model runs behind the curtain
- **Cost guard:** Hard daily cap on expensive models (Opus), configurable via env var (OPUS_DAILY_LIMIT=N), falls back to Sonnet when cap is hit
- **Fallback chain:** If a model is unavailable, gracefully degrade to next model (Opus → Sonnet → Haiku → error message) — silent, no user notification
- **Model list:** Configurable — model IDs stored in config (not hardcoded in workflows), swappable without editing n8n flows

### Channel Formatting
- **Platform-native formatting:** Full Discord markdown on Discord, Telegram-compatible markdown on Telegram — adapt per platform
- **Discord embeds:** Yes, for structured output (research results, summaries, multi-part answers) — conversational messages stay as plain text
- **Message splitting:** Natural boundaries — split at paragraph breaks, after code blocks, between logical sections (Discord 2000 char limit, Telegram 4096)

### Claude's Discretion
- Channel formatter architecture — whether it's a separate n8n node or integrated into the output router
- Discord reactions — whether to use acknowledge reactions (e.g., eyes emoji) for seen-but-no-verbal-response cases
- Code block language tagging — whether to always specify language for syntax highlighting or use generic blocks

</decisions>

<specifics>
## Specific Ideas

- prior project patterns to adopt: personality polisher pass, speaker-tagged transcripts, debug echo channel (Phase 6)
- Aerys voice sample for soul prompt calibration: "I can't do that directly. Here's what I can do: I can walk you through it step-by-step, or you can paste the relevant output and I'll pinpoint the issue. Two quick details so I don't steer you wrong: what platform are you on, and what does 'done' look like for you?"
- One-line soul characterization: "Failure mode = calm truth + immediate path forward. No performative regret, no overexplaining, no dead ends."
- prior project workflow JSONs are available as reference for memory pipelines, personality polishing, or sub-agent patterns — can be exported if needed

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-core-agent-channels*
*Context gathered: 2026-02-17*
