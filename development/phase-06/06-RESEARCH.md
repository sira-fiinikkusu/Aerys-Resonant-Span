# Phase 6: Polish + Hardening - Research

**Researched:** 2026-03-08
**Domain:** n8n workflow hardening, observability, guardrails, LLM evaluation, prompt engineering
**Confidence:** HIGH (well-documented n8n features, proven Aerys patterns, CONTEXT.md decisions locked)

## Summary

Phase 6 hardens Aerys for daily use across five plans: (1) Core Agent/personality split with debug trace channel, (2) native guardrails, (3) error resilience, (4) LLM-as-judge eval suite, and (5) prompt engineering. The most architecturally significant change is splitting soul.md and full personality rules out of the Core Agent into an always-on polisher in the Output Router -- this reduces Core Agent context weight, improves tool-calling reliability, and creates a clean separation between action-taking and voice-shaping.

The n8n instance (v2.35.5) supports all required features: Guardrails node (requires >= 1.119), Evaluation Trigger / Evaluation nodes, Error Trigger for central error handling, and `returnIntermediateSteps` on AI Agent nodes. Key risks are: (1) `returnIntermediateSteps` has known bugs with streaming mode -- streaming must be disabled on the Core Agent, (2) the SQL write-back to n8n_chat_histories after polishing must handle JSONB message column correctly, and (3) the always-on polisher adds approximately 2 seconds of latency per response, which the user has explicitly accepted.

**Primary recommendation:** Execute in wave order: Wave 0 captures eval baseline before any changes, Wave 1 does the architectural split, Waves 2-3 layer observability and hardening on the new architecture, Wave 4 refines prompts with eval-measured feedback.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Keep 3-tier triplication (Gemini/Sonnet/Opus) -- intentional, lets Aerys decide effort level intuitively
- Strip soul.md (~900 tokens) and full personality/voice rules from Core Agent system prompt
- Keep a small personality shard (~50-100 tokens) in the Core Agent -- enough for character-appropriate reasoning and tool decisions, not full voice rules
- Core Agent prompt becomes: tool rules + privacy gate + session + profile + memories + thread context + personality shard
- Output Router polisher becomes always-on (remove Polisher Gate conditional)
- Polisher receives: soul.md + full voice rules + Core Agent response + full memory context + full thread context + profile
- Polisher also receives full intermediateSteps (raw tool return data, untruncated)
- SQL write-back after polisher: UPDATE n8n_chat_histories with polished response so stored conversation matches what user actually saw
- Polisher model: Sonnet as safe default. Researcher benchmarks alternatives with live OpenRouter metrics.
- No GPT-4 series for polisher -- expected retirement soon
- Latency: +2s from always-on polisher is acceptable
- New #aerys-debug Discord channel for Crabwalk-style thought traces
- Trace fires on every message -- model tier, timing, tool calls with tokens/cost
- No user content or Aerys output in traces -- privacy; traces show what she did, not what was said
- #echoes stays separate for errors (error routing to #echoes is new in P6)
- Trace runs in parallel with user response delivery -- never blocks
- Jailbreak: natural in-character deflection + #aerys-debug trace with @mention to owner for alert escalation
- PII: no pre-LLM redaction (Core Agent needs personal facts). Output Router personality agent scrubs/generalizes sensitive PII in public channels only, keyed on conversation_privacy flag. DMs are unfiltered.
- Topical alignment: deferred -- not a problem yet
- Error messaging: specific in-character to user + error details to #echoes + failure shown in debug trace
- Wave ordering: Wave 0 (eval baseline) -> Wave 1 (architecture split) -> Wave 2 (observability) -> Wave 3 (guardrails + hardening) -> Wave 4 (prompt engineering)
- Sub-agent lifecycle state column (ready/failed/disabled) on sub_agents table
- Sub-agent dependency declarations (JSONB column) on sub_agents table
- Context section merge strategy via code comment conventions

### Implementation Discretion
- Debug trace toggle implementation (staticData vs Load Config constant)
- SQL write-back exact placement and error handling in Output Router
- Sub-agent lifecycle/dependency schema details
- Context merge strategy comment format

### Deferred Ideas (OUT OF SCOPE)
- Async sub-agent parallelization -- V2 scope
- Topical alignment guardrail -- watch item, not currently a problem
- Lock production workflows -- n8n version doesn't support it
- Thread context timestamps -- already implemented in Phase 05-00
- Polisher token budget -- optimization target if costs grow, not Phase 6
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OPS-01 | Debug visibility: every AI reasoning step and error mirrored to dedicated debug channel in real time | intermediateSteps from AI Agent (returnIntermediateSteps: true), #aerys-debug Discord channel, Crabwalk-style trace format, parallel send with continueOnFail |
| OPS-02 | Privacy safety: user IDs and sensitive data stripped before reaching AI models + PII scrubbing in output | PII guardrail node (built-in PII detection, 12+ entity types), conversation_privacy flag for public/DM distinction, polisher-side output scrubbing |
| OPS-03 | Error resilience: users receive clear notifications on error, critical nodes retry, unrecoverable failures route to central error workflow | Error Trigger node for central error workflow, retryOnFail on HTTP/API nodes, in-character error messages, #echoes error notifications |
</phase_requirements>

## Standard Stack

### Core (n8n Built-in Nodes)

| Node | Type/Version | Purpose | Why Standard |
|------|-------------|---------|--------------|
| Guardrails | `@n8n/n8n-nodes-langchain.guardrails` (typeVersion 1) | Jailbreak detection, PII detection/sanitization | Native n8n node since v1.119; 10 check types; no external dependencies |
| Error Trigger | `n8n-nodes-base.errortrigger` | Central error workflow trigger | Built-in; receives workflow.name, workflow.id, execution.lastNodeExecuted |
| Evaluation Trigger | `n8n-nodes-base.evaluationtrigger` (typeVersion 4.6) | Eval suite dataset trigger | Built-in; reads test cases row-by-row from data source |
| Evaluation | `n8n-nodes-base.evaluation` (typeVersion 4.7) | Scoring and metrics collection | Built-in; AI-based correctness (1-5), helpfulness (1-5), tool usage, custom |
| AI Agent | `@n8n/n8n-nodes-langchain.agent` | Core Agent + Polisher agent nodes | Already in use; enable returnIntermediateSteps for trace data |
| HTTP Request | `n8n-nodes-base.httpRequest` | Discord API calls (debug channel, error channel) | Already proven pattern for Discord message sends |

### Supporting

| Library/Service | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| OpenRouter API | current | Polisher model (Sonnet default) | Always-on polisher in Output Router |
| Discord REST API | v10 | Channel creation (#aerys-debug), message sends | Debug trace + error notification delivery |
| text-embedding-3-small | current | Eval dataset embedding (if needed) | Optional for semantic similarity metrics |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Guardrails node PII | Custom Code node regex | Guardrails node handles 12+ entity types natively; Code node would be fragile and incomplete |
| Evaluation nodes | Manual testing | Eval nodes give repeatable numeric scores; manual is subjective and non-reproducible |
| Error Trigger workflow | Per-node continueOnFail | Error Trigger catches ALL unhandled failures; continueOnFail only catches individual node failures |
| Sonnet polisher | Haiku polisher | Sonnet produces better voice fidelity for personality; Haiku is faster but may lose nuance (benchmark via eval suite) |

## Architecture Patterns

### Core Agent / Polisher Split (Wave 1 Architecture)

```
User Message → Adapter → Core Agent (action-focused, ~1500-3000 tokens system prompt)
    ↓
Execute Workflow → Output Router
    ↓
Polisher AI Agent (always-on, soul.md + voice rules + full context)
    ↓
SQL Write-Back → Platform Formatter → Send to User
    ↓ (parallel fork)
Format Trace → Send to #aerys-debug
```

**Core Agent system prompt (post-split):**
```
## Current Session (prepend - always first)
## Personality Shard (~50-100 tokens)
## Tool Rules
## Privacy Gate
## Person Profile (replace)
## Recent Conversation (replace)
## Server Members (skip_if_empty)
## Relevant Memories (replace)
## Available Tools (replace)
```

**Polisher system prompt (new):**
```
## Background (soul.md - full personality + voice rules)
## Context (memory_context + thread_context + profile_context)
## intermediateSteps (raw tool return data)
## Rules (formatting, PII scrubbing for public channels)
```

### Pattern 1: Always-On Polisher (replaces conditional Polisher Gate)

**What:** Remove Polisher Gate IF node. Polisher AI Agent runs on every response.
**When to use:** All responses -- the polisher shapes voice consistency, not just formatting.
**Implementation:**
```
Current: Polisher Gate → IF: Needs Polish → Polisher AI Agent
New: [remove gate] → Polisher AI Agent (always runs)
```

The existing polisher infrastructure (Polisher Gate + IF: Needs Polish + Polisher AI Agent + Set Polished Response) in Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID) is upgraded in place:
1. Remove Polisher Gate and IF: Needs Polish nodes
2. Wire Core Agent output directly to Polisher AI Agent
3. Upgrade polisher model from Haiku to Sonnet (via OpenRouter credential)
4. Expand workflowInputs to pass: memory_context, thread_context, profile_context, intermediateSteps
5. New system prompt with soul.md + voice rules + context awareness + PII scrubbing rules

### Pattern 2: SQL Write-Back After Polish

**What:** UPDATE n8n_chat_histories with polished response so stored conversation matches what user actually saw.
**When to use:** After every polished response, before Platform Formatter.

**n8n_chat_histories schema (verified):**
- `id` (int, serial)
- `session_id` (varchar) -- person_id for DMs, discord_{channel_id} for guild
- `message` (JSONB -- `{"type": "ai", "content": "response text"}`)
- `created_at` (timestamptz)

**SQL write-back query:**
```sql
UPDATE n8n_chat_histories
SET message = jsonb_set(message, '{content}', to_jsonb($1::text))
WHERE session_id = $2
  AND (message->>'type') = 'ai'
ORDER BY id DESC
LIMIT 1;
```

**Placement (implementation discretion recommendation):** After Set Polished Response, before Platform Formatter. Use a Code node to build the query, then a Postgres executeQuery node.

**Error handling:** `continueOnFail: true` on the write-back node -- write-back failure must never block user response delivery. Log failures to debug trace.

### Pattern 3: Debug Trace (Fire-and-Forget Parallel)

**What:** Structured thought trace pushed to #aerys-debug after every response.
**When to use:** Every message -- forked in parallel with user response delivery.

**Data source:** `intermediateSteps` from AI Agent node (requires `returnIntermediateSteps: true`).

**CRITICAL: Streaming must be disabled** on AI Agent nodes when returnIntermediateSteps is enabled. Known n8n bug (Issue #21998): streaming mode drops intermediateSteps from output. Workaround: disable streaming. This is acceptable since Aerys doesn't use streaming mode currently.

**intermediateSteps data structure (per step):**
- `action.tool` -- tool name (e.g., 'research_agent')
- `action.toolInput` -- input parameters passed to tool
- `observation` -- tool return data
- Token/cost data available from OpenRouter response headers

**Trace format (Crabwalk-style, no user content):**
```
[Sonnet] 3.4s
+-- research_agent
|   query: "latest AI news 2026"
|   847 tokens $0.0004
+-- Total: 1,459 tokens $0.0007
```

**Toggle mechanism (implementation discretion recommendation):** Use an n8n variable `AERYS_DEBUG_ENABLED` (string 'true'/'false'). Check in a Code node at the fork point. This is simpler than staticData and visible in n8n UI Settings > Variables.

### Pattern 4: Central Error Workflow

**What:** Error Trigger workflow that fires when ANY production workflow fails.
**When to use:** Configure all 18+ production workflows to point to this error workflow.

**Error Trigger receives:**
- `workflow.name` -- name of failed workflow
- `workflow.id` -- workflow ID
- `execution.lastNodeExecuted` -- node where execution stopped
- Error message details

**Error workflow structure:**
```
Error Trigger → Format Error Message (Code) → Log to audit_log (Postgres) + Notify #echoes (HTTP Request)
```

**Configuring production workflows:** Via n8n API PUT, add `settings.errorWorkflow` field:
```json
{
  "settings": {
    "errorWorkflow": "ERROR_WORKFLOW_ID"
  }
}
```

### Pattern 5: Personality Shard (Core Agent Lightweight Identity)

**What:** ~50-100 token identity anchor that stays in Core Agent after soul.md moves to polisher.
**Purpose:** Ensures Core Agent makes decisions as Aerys (not generic), without carrying full voice rules.

**Example:**
```
You are Aerys, a personal AI assistant. Curious, warm, direct. You genuinely care about helping.
Make decisions as yourself, not as a generic system. When in doubt, ask rather than assume.
```

This gives the Core Agent enough personality to make character-appropriate tool decisions and reasoning, while the polisher handles full voice shaping.

### Anti-Patterns to Avoid

- **Anti-pattern: Blocking user response on debug trace send.** Always use `continueOnFail: true` and parallel fork. Never wire trace send in series with user response.
- **Anti-pattern: PII redaction before Core Agent.** The Core Agent needs personal facts (names, preferences) to reason correctly. PII scrubbing happens ONLY in the polisher output, ONLY for public channels.
- **Anti-pattern: Proactive soul.md rules.** Only add prompt rules derived from observed failures. If no test breaks without a rule, cut it.
- **Anti-pattern: Trusting Set node for data injection.** Set node (typeVersion 3.4) returns `{}` in this n8n version. Use Code nodes for all merging.
- **Anti-pattern: Using streaming with returnIntermediateSteps.** Known bug drops intermediateSteps. Disable streaming.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PII detection in responses | Regex-based Code node | Guardrails node PII check/sanitize | Handles 12+ entity types (PERSON, EMAIL, PHONE, SSN, CREDIT_CARD, etc.) natively |
| Jailbreak detection | Keyword matching Code node | Guardrails node Jailbreak check | LLM-powered prompt injection detection with configurable threshold |
| LLM response scoring | Custom scoring Code node | Evaluation node with AI-based metrics | Built-in correctness (1-5) and helpfulness (1-5) scoring, result tracking |
| Error workflow routing | Per-node try/catch Code nodes | Error Trigger + workflow settings.errorWorkflow | Central catch-all for ALL unhandled failures across ALL workflows |
| Retry logic | Custom retry loops | retryOnFail node setting | Built-in with maxTries, waitBetweenTries, no code needed |

**Key insight:** n8n v2.35.5 has native solutions for every hardening concern in Phase 6. The only custom Code nodes needed are: (1) trace formatting, (2) SQL write-back assembly, (3) personality shard injection, and (4) error message formatting.

## Common Pitfalls

### Pitfall 1: intermediateSteps Empty or Missing
**What goes wrong:** AI Agent returns `{output: "text"}` without intermediateSteps field.
**Why it happens:** (a) `returnIntermediateSteps` not enabled on the AI Agent node, (b) streaming mode is enabled (known bug #21998), (c) direct response with no tool calls (intermediateSteps is empty array, not missing).
**How to avoid:** Enable `returnIntermediateSteps: true` on all 3 AI Agent nodes (Sonnet/Opus/Haiku). Disable streaming. Handle empty array as "direct response" in trace formatter.
**Warning signs:** Debug trace always shows "Direct response" even when tools were called.

### Pitfall 2: SQL Write-Back Targets Wrong Row
**What goes wrong:** UPDATE modifies an older AI message instead of the most recent one from this conversation turn.
**Why it happens:** n8n_chat_histories may have multiple `type: 'ai'` rows for the same session_id. Without ORDER BY id DESC LIMIT 1, the UPDATE hits the wrong row.
**How to avoid:** Always use `ORDER BY id DESC LIMIT 1` in the write-back query. Alternatively, capture the row ID at insert time and target by ID.
**Warning signs:** Conversation history shows polished text on the wrong message.

### Pitfall 3: LangChain Context Black Hole After Polisher
**What goes wrong:** Nodes after the Polisher AI Agent can't access input fields (source_channel, person_id, etc.).
**Why it happens:** AI Agent output is ONLY `{output: "text"}` -- all input fields stripped (documented in CLAUDE.md and aerys-debug agent).
**How to avoid:** Set Polished Response Code node must recover context from `$('LastNodeBeforePolisher').item.json`. This pattern already exists in the current Output Router.
**Warning signs:** Platform Formatter gets undefined for source_channel.

### Pitfall 4: Error Workflow Not Triggering
**What goes wrong:** Workflow fails but error workflow doesn't fire.
**Why it happens:** (a) `settings.errorWorkflow` not set on the failing workflow, (b) error occurs in the trigger node itself (Error Trigger doesn't receive trigger-node errors), (c) `continueOnFail: true` swallows the error before it becomes unhandled.
**How to avoid:** Set errorWorkflow on ALL production workflows via API. Know that continueOnFail errors are NOT forwarded to the error workflow (this is by design -- they're "handled").
**Warning signs:** Silent failures with no notification.

### Pitfall 5: Guardrails Node Latency on Every Message
**What goes wrong:** Adding LLM-based guardrails (Jailbreak, Topical) adds 1-5 seconds per message.
**Why it happens:** Each LLM-based check makes an API call to the connected chat model.
**How to avoid:** Per CONTEXT.md: Jailbreak check only (Topical deferred). Use Haiku for the guardrail LLM -- cheapest and fastest. Place guardrail AFTER intent classifier but BEFORE Core Agent to avoid wasting tokens on blocked messages. PII detection is non-LLM (100-300ms) so latency is minimal.
**Warning signs:** Response time increases noticeably after guardrails deployment.

### Pitfall 6: Polisher Context Passing Through executeWorkflow
**What goes wrong:** Polisher doesn't receive memory_context, thread_context, or intermediateSteps.
**Why it happens:** Execute Workflow (Core Agent -> Output Router) needs expanded workflowInputs schema. Without listing every field in the schema array, fields are silently dropped (documented toolWorkflow dead value dict quirk).
**How to avoid:** Define full schema array in the Execute Workflow node calling Output Router. List every field: `output`, `memory_context`, `thread_context`, `profile_context`, `intermediateSteps`, `model_tier`, `person_id`, `session_id`, `source_channel`, `conversation_privacy`, `_start_ts`.
**Warning signs:** Polisher produces generic responses without personality context.

### Pitfall 7: retryOnFail + continueOnFail Interaction Bug
**What goes wrong:** Node retries succeed but the error output branch still fires.
**Why it happens:** Known n8n issue (#10763): when both retryOnFail and continueOnError are set, the node returns an error even after a successful retry.
**How to avoid:** Use retryOnFail WITHOUT continueOnError on the same node. If you need error routing, use continueErrorOutput on a separate downstream node. Don't combine both on one node.
**Warning signs:** Error workflow fires for nodes that actually succeeded.

## Code Examples

### Trace Formatter (Code Node)

```javascript
// Source: p6-thought-trace-debug-channel.md todo + CONTEXT.md decisions
// STRATEGY: replace -- rebuilt from intermediateSteps on every message
const steps = $json.intermediateSteps || [];
const model = $json.model_tier || 'unknown';
const startTs = $json._start_ts || Date.now();
const elapsed = ((Date.now() - startTs) / 1000).toFixed(1);

const TOOL_ICONS = {
  media: '[IMG]',
  research: '[RES]',
  email: '[EML]',
};

let lines = [`[${model}] ${elapsed}s`];

if (steps.length === 0) {
  lines.push('+-- Direct response');
} else {
  steps.forEach((step, i) => {
    const isLast = i === steps.length - 1;
    const prefix = isLast ? '+--' : '|--';
    const icon = TOOL_ICONS[step.action?.tool] || '[?]';
    const tokens = step.tokenUsage?.totalTokens || '?';
    lines.push(`${prefix} ${icon} ${step.action?.tool || 'unknown'} ${tokens} tokens`);
  });
}

return [{ json: {
  trace_message: '```\n' + lines.join('\n') + '\n```',
  debug_channel_id: $vars.AERYS_DEBUG_CHANNEL_ID
}}];
```

### SQL Write-Back (Code Node)

```javascript
// Source: CONTEXT.md decision -- SQL write-back after polisher
// STRATEGY: replace -- overwrites most recent AI message content
const polishedResponse = $json.polished_response || $json.output;
const sessionId = $('LastNodeBeforePolisher').item.json.session_id
  || $('LastNodeBeforePolisher').item.json.person_id;

return [{ json: {
  polished_content: polishedResponse,
  session_id: sessionId
}}];

// Downstream Postgres node query:
// UPDATE n8n_chat_histories
// SET message = jsonb_set(message, '{content}', to_jsonb($1::text))
// WHERE session_id = $2
//   AND (message->>'type') = 'ai'
//   AND id = (SELECT MAX(id) FROM n8n_chat_histories WHERE session_id = $2 AND (message->>'type') = 'ai')
// queryReplacement: ={{ [$json.polished_content, $json.session_id] }}
```

### Graceful Error Message (Code Node)

```javascript
// Source: CONTEXT.md decision -- in-character error messages
// Placed in Core Agent error branch (continueErrorOutput)
const errorMsg = $json.error?.message || 'Something unexpected happened';
const toolName = $json.error?.node || 'unknown';

const errorResponses = {
  research: "I tried to look that up but my research tool timed out. Want me to try again, or I can answer from what I know?",
  media: "I hit a wall trying to process that image. Could you send it again? Sometimes these things just need a second try.",
  email: "My email connection stumbled. Give me a moment and I can try again.",
  default: "Something went sideways on my end. Mind if I try that again?"
};

const tool = Object.keys(errorResponses).find(k => toolName.toLowerCase().includes(k));
const userMessage = errorResponses[tool] || errorResponses.default;

return [{ json: { output: userMessage, _error_details: errorMsg }}];
```

### Sub-Agent Lifecycle State Migration (008)

```sql
-- Migration 008: Sub-agent lifecycle + dependency declarations
-- Source: p6-sub-agent-lifecycle-state.md + p6-sub-agent-dependency-declarations.md

ALTER TABLE sub_agents ADD COLUMN IF NOT EXISTS state TEXT NOT NULL DEFAULT 'ready';
ALTER TABLE sub_agents ADD COLUMN IF NOT EXISTS dependencies JSONB DEFAULT '[]';

-- Add check constraint (idempotent via DO block)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sub_agents_state_check'
  ) THEN
    ALTER TABLE sub_agents ADD CONSTRAINT sub_agents_state_check
      CHECK (state IN ('ready', 'failed', 'disabled'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sub_agents_state ON sub_agents(state);

-- Populate dependencies for existing agents
UPDATE sub_agents SET dependencies = '[
  {"service": "openrouter", "credential_id": "YOUR_OPENROUTER_CREDENTIAL_ID", "optional": false}
]'::jsonb WHERE capability_id = 'media';

UPDATE sub_agents SET dependencies = '[
  {"service": "tavily", "credential_id": "YOUR_TAVILY_HEADER_CREDENTIAL_ID", "optional": false}
]'::jsonb WHERE capability_id = 'research.web';

UPDATE sub_agents SET dependencies = '[
  {"service": "gmail_aerys", "credential_id": "YOUR_GMAIL_AERYS_CREDENTIAL_ID", "optional": false},
  {"service": "gmail_user", "credential_id": "YOUR_GMAIL_USER_CREDENTIAL_ID", "optional": true}
]'::jsonb WHERE capability_id = 'email';
```

### Error Log Table Extension (optional -- audit_log already exists)

```sql
-- Use existing audit_log table for error logging
-- Error Trigger Code node formats:
-- { action: 'workflow_error', details: { workflow_name, workflow_id, error_message, execution_id, node_name } }
-- No new table needed -- audit_log covers this use case
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Code node regex for PII | Guardrails node native PII | n8n 1.119 (Nov 2025) | 12+ entity types, no maintenance |
| Manual testing only | Evaluation Trigger + Evaluation nodes | n8n 1.x (2025) | Repeatable numeric scoring, historical tracking |
| Per-node error logging | Central Error Trigger workflow | Always available | Single pane of glass for all failures |
| Conditional polisher (gate) | Always-on polisher (prior project pattern) | Phase 6 decision | Consistent voice, clean separation of concerns |
| Soul.md in Core Agent | Soul.md in polisher only | Phase 6 decision | Reduced context weight, better tool calling |

**Deprecated/outdated:**
- Polisher Gate + IF: Needs Polish pattern -- replaced by always-on polisher in Wave 1
- Guardian Code node manual safety logic -- partially replaced by native Guardrails node in Wave 3 (Guardian hourly schedule for promotion remains unchanged)
- Haiku polisher model -- upgraded to Sonnet for better voice fidelity

## Guardrails Node Technical Reference

**Available in n8n >= 1.119 (Aerys is on 2.35.5 -- confirmed compatible)**

### Check Types Relevant to Phase 6

| Type | Operation | LLM Required | Config | Phase 6 Use |
|------|-----------|-------------|--------|-------------|
| Jailbreak | Check | Yes (Haiku) | Threshold 0.75 | Pre-Core Agent gate; deflect + trace + @owner alert |
| PII Detection | Check | No | Select entity types | Post-polisher check on public channel responses |
| PII Sanitization | Sanitize | No | Redact with [REDACTED-PII] | Alternative to detection -- strips in-place |
| Secret Keys | Check | No | Balanced strictness | Optional -- catch accidental API key leaks |

### Wiring Pattern

```
User Input → Jailbreak Check (Guardrails)
  → Pass: Core Agent
  → Fail: In-Character Deflection + Debug Trace (@owner mention)

Polished Response → PII Check (Guardrails, public channels only)
  → Pass: Platform Formatter
  → Fail: PII Sanitize → Platform Formatter
```

### Performance Budget

- Jailbreak check (LLM-based): 1-3 seconds with Haiku
- PII detection (non-LLM): 100-300ms
- Total guardrail overhead per message: ~1.5-3.5 seconds (Jailbreak only, per CONTEXT.md; Topical deferred)

**Per CONTEXT.md decision:** Only Jailbreak guardrail is active. PII handling is in the polisher (not a separate guardrail node for input). Topical alignment is deferred.

## Evaluation Suite Technical Reference

### Evaluation Trigger Node (typeVersion 4.6)

Reads test cases from a data source (Google Sheets, n8n Data Table, or JSON file). Feeds one row at a time through the evaluation workflow.

### Evaluation Node (typeVersion 4.7)

**Operations:**
- `Set Outputs` -- maps results back to data source
- `Set Metrics` -- selects which scores to track
- `Check If Evaluating` -- routes to test vs. production branch

**Built-in AI Metrics:**
- Correctness (AI-based): scores 1-5 whether answer is consistent with reference
- Helpfulness (AI-based): scores 1-5 whether response addresses query
- Custom: domain-specific criteria via custom prompt

**Deterministic Metrics:**
- String Similarity, Categorization (exact match), Token Count, Execution Time

### Eval Workflow Pattern for Aerys

```
Evaluation Trigger (reads eval_dataset)
  → Build Test Input (Code)
  → Execute Core Agent (sub-workflow call to YOUR_CORE_AGENT_WORKFLOW_ID)
  → LLM Judge (Sonnet via OpenRouter -- judge prompt with 1-5 scoring)
  → Evaluation Node (Set Outputs + Set Metrics)
```

**Dataset requirements (20-30 rows):**
- `user_message` -- test input
- `expected_behavior` -- what a good response looks like (not exact text)
- `context` -- any required memory/profile context
- `category` -- normal_conversation | research | media | email | edge_case

## Error Handling Technical Reference

### retryOnFail Configuration

```json
{
  "retryOnFail": true,
  "maxTries": 3,
  "waitBetweenTries": 2000
}
```

**Apply to these node types:**
- All HTTP Request nodes (OpenRouter API, Discord API, Tavily)
- All Postgres executeQuery nodes (connection interruption)
- Gmail API nodes

**Do NOT apply to:**
- INSERT nodes without ON CONFLICT (non-idempotent)
- Nodes with continueOnError set (interaction bug #10763)

### continueOnFail vs continueErrorOutput

| Setting | Behavior | Use When |
|---------|----------|----------|
| `continueOnFail: true` | Error swallowed, node output is error object | Non-critical: logging, trace sends, sub-agent invocation logging |
| `onError: "continueErrorOutput"` | Error routes to explicit error branch | Critical path: need to send user-facing error message |
| `onError: "continueRegularOutput"` | Error passes as regular output | Pattern already used in Guardian LLM consolidation |

### Central Error Workflow Structure

```
Error Trigger
  → Format Error (Code: extract workflow.name, error.message, execution.lastNodeExecuted)
  → [parallel fork]
    → Log to audit_log (Postgres, credential YOUR_POSTGRES_CREDENTIAL_ID)
    → Send to #echoes (HTTP Request to Discord API, continueOnFail: true)
```

**Error notification format for #echoes:**
```
**Aerys Error**
Workflow: {workflow_name}
Node: {last_node}
Error: {error_message}
Exec: {execution_id}
```

### Workflow Settings Update (via API)

To set errorWorkflow on all production workflows:
```bash
API_KEY=$(grep API_KEY /home/particle/aerys/scripts/discord-adapter-watcher.sh | cut -d'=' -f2 | tr -d '"')
# GET workflow, add settings.errorWorkflow, PUT back
curl -s -H "X-N8N-API-KEY: $API_KEY" http://localhost:5678/api/v1/workflows/WORKFLOW_ID \
  | python3 -c "
import json,sys
wf = json.load(sys.stdin)
wf.setdefault('settings', {})['errorWorkflow'] = 'ERROR_WF_ID'
body = {k: wf[k] for k in ['name','nodes','connections','settings','staticData'] if k in wf}
json.dump(body, sys.stdout)
" | curl -s -X PUT -H "X-N8N-API-KEY: $API_KEY" -H "Content-Type: application/json" \
  -d @- http://localhost:5678/api/v1/workflows/WORKFLOW_ID
```

## Output Router Modifications (Wave 1)

### Current Output Router Flow (YOUR_OUTPUT_ROUTER_WORKFLOW_ID)

```
Execute Workflow Trigger → Polisher Gate → IF: Needs Polish
  → [true] Polisher AI Agent → Set Polished Response
  → [false] Set Polished Response (passthrough)
→ Platform Formatter → Message Splitter → Loop Over Chunks → Switch: Route by Platform → Send
```

### Modified Output Router Flow (Wave 1)

```
Execute Workflow Trigger (expanded workflowInputs)
  → Polisher AI Agent (always-on, Sonnet, soul.md + full context)
  → Set Polished Response (recover context from before agent)
  → SQL Write-Back (Postgres, continueOnFail: true)
  → [parallel fork]
    → Platform Formatter → Message Splitter → Loop → Switch → Send
    → Format Trace → Send to #aerys-debug (continueOnFail: true)
```

### Execute Workflow Input Schema (Core Agent -> Output Router)

The Execute Workflow node in Core Agent calling Output Router must have its workflowInputs schema expanded:

```json
{
  "schema": [
    {"name": "output", "type": "string"},
    {"name": "memory_context", "type": "string"},
    {"name": "thread_context", "type": "string"},
    {"name": "profile_context", "type": "string"},
    {"name": "intermediateSteps", "type": "string"},
    {"name": "model_tier", "type": "string"},
    {"name": "person_id", "type": "string"},
    {"name": "session_id", "type": "string"},
    {"name": "source_channel", "type": "string"},
    {"name": "conversation_privacy", "type": "string"},
    {"name": "_start_ts", "type": "number"},
    {"name": "person_name", "type": "string"}
  ],
  "mappingMode": "defineBelow",
  "value": {
    "output": "={{ $json.output }}",
    "memory_context": "={{ $json.memory_context }}",
    "thread_context": "={{ $json.thread_context }}",
    "profile_context": "={{ $json.profile_context }}",
    "intermediateSteps": "={{ JSON.stringify($json.intermediateSteps || []) }}",
    "model_tier": "={{ $json.model_tier }}",
    "person_id": "={{ $json.person_id }}",
    "session_id": "={{ $json.session_id }}",
    "source_channel": "={{ $json.source_channel }}",
    "conversation_privacy": "={{ $json.conversation_privacy }}",
    "_start_ts": "={{ $json._start_ts }}",
    "person_name": "={{ $json.person_name }}"
  }
}
```

**CRITICAL:** intermediateSteps must be JSON.stringify'd because Execute Workflow schema type "string" cannot pass arrays. The polisher Code node must JSON.parse it back.

## Discord Channel Setup

### #aerys-debug Channel

Must be created manually before Wave 2 deployment. Store the channel ID as n8n variable `AERYS_DEBUG_CHANNEL_ID`.

Channel permissions: bot read/write, restrict to admin/owner only (no public access to debug traces).

### #echoes Channel

Already exists in Discord (discord_channel_cache has 'echoes'). Currently not wired to receive errors. Wave 2 wires error notifications here.

Store channel ID as n8n variable `AERYS_ECHOES_CHANNEL_ID`.

## Migration Plan

### Migration 008: Sub-Agent Lifecycle + Dependencies

File: `~/aerys/migrations/008_sub_agent_lifecycle.sql`

Adds `state` (TEXT with CHECK constraint) and `dependencies` (JSONB) columns to sub_agents table. Populates dependencies for existing 3 agents with their known credential IDs.

### Fetch Available Tools Query Update

```sql
SELECT name, description, trigger_hints, capability_id, workflow_id
FROM sub_agents WHERE enabled = true AND state = 'ready' ORDER BY name;
```

This filters out failed/disabled agents, giving the Core Agent only tools that are actually reachable.

## Reactive Prompting Methodology (Wave 4)

### Structure for soul.md Rewrite

```markdown
## Background
[Who Aerys is - one paragraph, no laundry list]

## Tools
[What tools she has, when to use them - derived from Phase 5]

## Rules
[ONLY rules derived from observed failures]
[Each rule: "When X happens, do Y. Never do Z in context W."]
[If no test breaks without it, cut it]

## Examples
[2-3 real input/output pairs showing desired behavior]
```

### Process

1. Export Phase 5 conversation logs from n8n_chat_histories
2. Identify failure patterns (out of character, rule ignored, user correction needed)
3. Write one rule per failure pattern
4. For each existing soul.md rule: "did this fail in Phase 5?" -- if no, consider cutting
5. Apply one change at a time, run eval suite after each
6. Target: 500-700 tokens (down from ~900)

### soul.md Target (Polisher, Not Core Agent)

Per CONTEXT.md decision: soul.md moves to the polisher. The rewrite targets the polisher system prompt, not the Core Agent personality shard.

## Context Section Merge Strategy (Code Comment Convention)

```javascript
// STRATEGY: prepend -- always first in system prompt
const sessionBlock = ...

// STRATEGY: replace -- rebuilt from core_claim table each message
const profileBlock = ...

// STRATEGY: skip_if_empty -- only when members present
const membersBlock = memberList ? `## Server Members\n${memberList}` : '';

// STRATEGY: replace -- rebuilt from sub_agents table each message
const toolsList = ...
```

Strategies: `replace`, `append`, `prepend`, `skip_if_empty`. Applied as code comments on each section builder in Load Config / Build Tools Context nodes.

## Open Questions

1. **Polisher model benchmarking**
   - What we know: Sonnet is the safe default per CONTEXT.md. Haiku is cheaper but may lose voice nuance.
   - What's unclear: Actual latency and cost difference on OpenRouter for this use case. Whether Gemini Flash would work.
   - Recommendation: Wave 1 ships with Sonnet. Wave 4 benchmarks alternatives using the eval suite. No GPT-4 series.

2. **intermediateSteps token usage data availability**
   - What we know: intermediateSteps contains action.tool and observation. Token usage is available from OpenRouter response.
   - What's unclear: Whether tokenUsage is populated in intermediateSteps in n8n 2.35.5, or if it needs to be calculated from OpenRouter headers.
   - Recommendation: Build trace formatter to handle both cases -- use intermediateSteps.tokenUsage if present, fall back to model pricing table calculation.

3. **Eval dataset source**
   - What we know: Need 20-30 input/output pairs from Phase 5 conversations.
   - What's unclear: Whether to use n8n Data Tables (built-in) or a JSON file in ~/aerys/evals/.
   - Recommendation: JSON file in ~/aerys/evals/baseline.json -- version-controlled in infra repo, no dependency on n8n features.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | n8n Evaluation Trigger + Evaluation nodes (built-in) |
| Config file | New eval workflow (created in Wave 0) |
| Quick run command | Manual trigger of eval workflow in n8n UI |
| Full suite command | Execute full 20-30 row eval dataset through eval workflow |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OPS-01 | Debug trace appears in #aerys-debug after every response | smoke | Send message, check #aerys-debug for trace | No -- Wave 2 |
| OPS-01 | Trace contains model tier, timing, tool calls | manual | Inspect trace message format | No -- Wave 2 |
| OPS-02 | PII scrubbed in public channel responses | smoke | Send message with phone number in guild, verify scrubbed | No -- Wave 3 |
| OPS-02 | PII preserved in DM responses | smoke | Send message with phone number in DM, verify preserved | No -- Wave 3 |
| OPS-03 | Error produces user-facing message | smoke | Trigger error condition, verify user gets response | No -- Wave 3 |
| OPS-03 | Error logged to #echoes | smoke | Trigger error, check #echoes for notification | No -- Wave 3 |
| OPS-03 | retryOnFail on HTTP nodes | unit | Check node config for retryOnFail flag | No -- Wave 3 |

### Sampling Rate
- **Per task commit:** Manual trigger of eval workflow (quick 5-row subset)
- **Per wave merge:** Full 20-30 row eval suite
- **Phase gate:** Full suite green + all smoke tests pass before /gsd:verify-work

### Wave 0 Gaps
- [ ] `~/aerys/evals/baseline.json` -- 20-30 test cases from Phase 5 conversations
- [ ] Eval workflow (Evaluation Trigger + Evaluation + Check If Evaluating nodes)
- [ ] #aerys-debug Discord channel created manually
- [ ] n8n variables: AERYS_DEBUG_CHANNEL_ID, AERYS_DEBUG_ENABLED, AERYS_ECHOES_CHANNEL_ID

## Sources

### Primary (HIGH confidence)
- [n8n Guardrails documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-langchain.guardrails/) -- node operations, check types, configuration
- [n8n Error Trigger documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.errortrigger/) -- error workflow setup
- [n8n Evaluation overview](https://docs.n8n.io/advanced-ai/evaluations/overview/) -- eval trigger + eval node
- [n8n Error handling](https://docs.n8n.io/flow-logic/error-handling/) -- retryOnFail, continueOnFail patterns
- [n8n LLM Evaluation Framework blog](https://blog.n8n.io/llm-evaluation-framework/) -- evaluation workflow pattern, metrics
- CONTEXT.md -- all locked decisions for Phase 6 architecture
- aerys-n8n agent -- workflow IDs, node quirks, API patterns
- aerys-db agent -- schema reference, migration patterns
- aerys-debug agent -- failure catalog, known bugs

### Secondary (MEDIUM confidence)
- [Optimize Smart n8n Guardrails Guide](https://optimizesmart.com/blog/n8n-guardrails-guide/) -- detailed guardrail types, thresholds, performance timings
- [Khaisa Studio Guardrails Reference](https://khaisa.studio/n8n-guardrails-node-dedicated-node-to-secure-your-ai-workflows/) -- check type configuration details
- [LogRocket n8n Eval Guide](https://blog.logrocket.com/stop-your-ai-agents-from-hallucinating-n8n/) -- evaluation node operations, workflow pattern
- [n8n Creating Error Workflows blog](https://blog.n8n.io/creating-error-workflows-in-n8n/) -- Error Trigger data structure, setup steps
- [GitHub Issue #21998](https://github.com/n8n-io/n8n/issues/21998) -- intermediateSteps + streaming bug
- [GitHub Issue #10763](https://github.com/n8n-io/n8n/issues/10763) -- retryOnFail + continueOnError interaction bug

### Tertiary (LOW confidence)
- intermediateSteps token usage data structure -- not verified on n8n 2.35.5; may need runtime verification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all nodes are built-in to n8n 2.35.5, verified available
- Architecture: HIGH -- Core Agent/polisher split is locked decision from CONTEXT.md, existing Output Router pattern proven
- Error handling: HIGH -- Error Trigger, retryOnFail, continueOnFail are well-documented n8n features
- Guardrails: HIGH -- native node confirmed available (n8n >= 1.119, we're on 2.35.5)
- Evaluation: MEDIUM -- eval nodes confirmed available, but exact workflow wiring needs runtime validation
- intermediateSteps: MEDIUM -- data available when streaming disabled, but token usage field availability on 2.35.5 needs verification
- Pitfalls: HIGH -- documented from 5 phases of Aerys development, aerys-debug failure catalog covers all known patterns

**Research date:** 2026-03-08
**Valid until:** 2026-04-07 (30 days -- n8n features are stable; eval nodes may get minor updates)
