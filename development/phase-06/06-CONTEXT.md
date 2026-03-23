# Phase 6: Polish + Hardening - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the system observable, privacy-safe, and resilient for daily use. Core Agent prompt complexity is reduced by splitting personality into the Output Router. Every interaction is traced for debugging. Errors are surfaced gracefully. Guardrails protect public channels. An eval suite provides before/after measurement.

</domain>

<decisions>
## Implementation Decisions

### Core Agent / Personality Split
- Keep 3-tier triplication (Gemini/Sonnet/Opus) — intentional, lets Aerys decide effort level intuitively
- Strip soul.md (~900 tokens) and full personality/voice rules from Core Agent system prompt
- Keep a small personality shard (~50-100 tokens) in the Core Agent — enough for character-appropriate reasoning and tool decisions, not full voice rules
- Core Agent prompt becomes: tool rules + privacy gate + session + profile + memories + thread context + personality shard
- Output Router polisher becomes **always-on** (remove Polisher Gate conditional)
- Polisher receives: soul.md + full voice rules + Core Agent response + full memory context + full thread context + profile (prior project constraint: both agents need full context to avoid confusion)
- Polisher also receives **full intermediateSteps** (raw tool return data, untruncated) so personality agent can craft informed responses from what tools actually returned
  - Code comment: `// Token diet target: truncate intermediateSteps if polisher input costs grow`
- **SQL write-back** after polisher: UPDATE n8n_chat_histories with polished response so stored conversation matches what user actually saw
- Polisher model: Sonnet as safe default. Researcher benchmarks alternatives with live OpenRouter metrics (pricing, latency, voice fidelity against soul.md). **No GPT-4 series** — expected retirement soon.
- Latency: +2s from always-on polisher is acceptable; Aerys's current response quality is above expectations

### Debug Trace Visibility
- New **#aerys-debug** Discord channel for Crabwalk-style thought traces
- Trace fires on **every message** — model tier, timing, tool calls with tokens/cost
- **No user content or Aerys output** in traces — privacy; traces show what she did, not what was said
- Toggle mechanism: implementation discretion (staticData flag or Load Config constant)
- #echoes stays **separate** for errors (error routing to #echoes is new in P6, not existing)
- Trace runs **in parallel** with user response delivery — never blocks

### Guardrails
- **Jailbreak**: natural in-character deflection + #aerys-debug trace **with @mention to owner** for alert escalation
- **PII**: no pre-LLM redaction (Core Agent needs personal facts to reason). Output Router personality agent scrubs/generalizes sensitive PII (phone numbers, addresses, SSNs, medical details) in **public channels only**, keyed on `conversation_privacy` flag. DMs are unfiltered.
- **Topical alignment**: deferred — not a problem yet. Noted as watch item, address if it surfaces.

### Error Messaging
- **Specific in-character to user** — tells them what failed, offers alternatives, stays in Aerys's voice (e.g., "I tried to look that up but my research tool timed out — want me to try again, or I can answer from what I know?")
- **Error details to #echoes** — technical trace for owner (new in P6)
- Also visible in **#aerys-debug trace** — failure shown inline in the per-message trace

### Wave Ordering
- **Wave 0**: Eval suite — baseline capture of current behavior BEFORE architectural changes
- **Wave 1**: Architecture — Core Agent prompt split, always-on polisher, SQL write-back, personality shard, intermediateSteps passthrough
- **Wave 2**: Observability — debug trace to #aerys-debug, error routing to #echoes
- **Wave 3**: Guardrails + hardening — jailbreak detection, PII scrubbing in polisher, sub-agent lifecycle state + dependency declarations, error resilience (retryOnFail, central error workflow)
- **Wave 4**: Prompt engineering — soul.md reactive rewrite targeting the polisher, context section merge strategy

### Additional Scope (from P6 todos)
- **Sub-agent lifecycle state** — `state` column (ready/failed/disabled) on sub_agents table; Fetch Available Tools filters to ready agents
- **Sub-agent dependency declarations** — `dependencies` JSONB column listing required services; health-check verifies availability
- **Context section merge strategy** — code comment conventions for injection patterns (replace, append, prepend, skip_if_empty)

### Implementation Discretion
- Debug trace toggle implementation (staticData vs Load Config constant)
- SQL write-back exact placement and error handling in Output Router
- Sub-agent lifecycle/dependency schema details
- Context merge strategy comment format

</decisions>

<specifics>
## Specific Ideas

- Crabwalk-style trace format from the thought trace todo — tree structure with tool icons, timing, token counts, cost
- The prior project's two-agent pattern is the reference architecture for the split, adapted: Aerys keeps triplication on the action side, personality agent is in the Output Router
- The polisher already exists (Polisher Gate + IF: Needs Polish + Polisher AI Agent + OpenRouter Haiku) — upgrade in place rather than rebuilding
- Personality shard example: "You are Aerys, a personal AI assistant. Curious, warm, direct. You genuinely care about helping. Make decisions as yourself, not as a generic system."
- Error messages should feel like Aerys hitting a snag, not a system error page

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Output Router polisher** (YOUR_OUTPUT_ROUTER_WORKFLOW_ID): Polisher Gate + IF + Polisher AI Agent + Set Polished Response already wired. Upgrade model, make always-on, add context inputs.
- **intermediateSteps**: AI Agent nodes can return these with `returnIntermediateSteps: true` — data source for both debug traces and polisher tool context.
- **conversation_privacy flag**: flows through every message from adapters. Use for PII scrubbing gate in polisher.
- **#echoes channel**: exists in Discord but not currently wired to receive errors from workflows.
- **Load Config code node**: assembles the entire system prompt. This is where soul.md and personality rules get removed and the personality shard gets inserted.

### Established Patterns
- **LangChain AI Agent context black hole**: output is only `{output: "text"}`. Downstream nodes recover via `$('NodeName').item.json`. The polisher already handles this via Set Polished Response.
- **Execute Workflow sub-workflow calls**: Core Agent → Output Router is already an Execute Workflow call. Context passes through workflowInputs.
- **Fire-and-forget parallel sends**: Send Discord Message pattern can be reused for debug trace sends. Use `continueOnFail: true` so trace failures never block user delivery.
- **n8n_chat_histories schema**: `session_id`, `message` (JSONB with role + content), `created_at`. SQL write-back targets the most recent assistant message by session_id.

### Integration Points
- **Load Config** (Core Agent): strip soul.md, add personality shard
- **Output Router Execute Workflow call**: expand workflowInputs to pass memory_context, thread_context, profile_context, intermediateSteps
- **Polisher AI Agent**: upgrade model, new system prompt with soul.md + voice rules + context awareness
- **After polisher, before Platform Formatter**: add SQL write-back node + debug trace fork
- **All 3 AI Agent nodes**: enable `returnIntermediateSteps: true`
- **New Discord channel**: #aerys-debug must be created manually before deployment

</code_context>

<deferred>
## Deferred Ideas

- **Async sub-agent parallelization** — concurrent Execute Workflow for multi-tool messages. V2 scope, depends on chaining frequency data.
- **Topical alignment guardrail** — watch item, not currently a problem. Revisit if Aerys starts going off-topic in conversations.
- **Lock production workflows** — n8n version doesn't support workflow locking.
- **Thread context timestamps** — already implemented in Phase 05-00 (stale todo).
- **Polisher token budget** — if polisher input costs grow due to full intermediateSteps passthrough, truncation is a noted optimization target.

</deferred>

---

*Phase: 06-polish-hardening*
*Context gathered: 2026-03-08*
