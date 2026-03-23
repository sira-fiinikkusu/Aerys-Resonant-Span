# Phase 06-05: Prompt Engineering + Tool Reliability - Research

**Researched:** 2026-03-18
**Domain:** n8n toolWorkflow reliability, LLM tool-calling prompt engineering, soul.md reactive rewrite, sub-agent architecture audit
**Confidence:** HIGH (live workflow data extracted, eval findings mapped, Anthropic official docs verified)

## Summary

This research covers the FINAL plan of V1, focusing on two intertwined goals: (1) making Core Agent tool calling reliable, and (2) rewriting soul.md reactively based on observed failures. The live workflow analysis reveals three critical findings that change the scope of 06-05 from the original plan:

**Finding 1 -- Research Sub-Agent has a redundant LLM call.** The Research sub-agent (YOUR_RESEARCH_SUBAGENT_WORKFLOW_ID, 6 nodes) calls Tavily, then calls Gemini Flash Lite to "synthesize in Aerys's voice" -- but the Output Router polisher already does voice shaping. This is a wasted LLM call (~$0.10-0.40 per research request) that adds latency and introduces a second voice that fights the polisher. The Tavily HTTP call could be made directly from the Core Agent as a Code tool or HTTP Request tool, with the Core Agent LLM synthesizing results natively.

**Finding 2 -- All 9 toolWorkflow nodes are missing explicit `name` properties.** CLAUDE.md documents this as a critical issue: without a `name` property, n8n auto-derives the function name from the node name (e.g., "Tool: Media (Sonnet)" becomes sanitized garbage). The LLM cannot match these auto-derived names to system prompt instructions. This is a likely root cause for tc-15 (bypassed media for YouTube) and other tool reliability failures.

**Finding 3 -- Research tool description is dangerously thin (128 chars).** The Media tool description is 767 chars with explicit trigger patterns; the Email description is 523 chars with clear action flows. The Research tool is just: "Search the web for current information. Call this tool when the user asks to research, look up, find, or check something online." This generic description is the exact anti-pattern that Anthropic's tool-calling documentation warns against -- it doesn't tell the LLM when to call the tool for implicit research needs (weather, prices, current events), which directly explains tc-04 (hallucinated weather data).

**Primary recommendation:** Fix the toolWorkflow `name` properties first (instant reliability win). Rewrite Research tool description to match Media/Email specificity. Evaluate eliminating the Research sub-agent's redundant LLM call. Then do the soul.md reactive rewrite targeting the polisher. Context section merge strategy comments are low-risk cleanup.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Keep 3-tier triplication (Gemini/Sonnet/Opus) -- intentional, lets Aerys decide effort level intuitively
- Core Agent prompt = tool rules + privacy gate + session + profile + memories + thread context + personality shard
- Output Router polisher is always-on with soul.md + full voice rules + Core Agent response + full context
- Polisher receives full intermediateSteps (raw tool return data, untruncated)
- SQL write-back after polisher: UPDATE n8n_chat_histories with polished response
- Polisher model: Haiku (user decision post-06-02, cost saving)
- Wave ordering: Wave 0 (eval) -> Wave 1 (architecture) -> Wave 2 (observability) -> Wave 3 (guardrails) -> Wave 4 (prompt engineering) -> Wave 5 (this plan)
- Sub-agent lifecycle state + dependency declarations already deployed (06-04)
- Context section merge strategy via code comment conventions

### Implementation Discretion
- Research sub-agent: keep as sub-workflow vs rewire as direct tool
- Tool description rewrites for reliability
- soul.md reactive rewrite content (rules derived from failures)
- Context merge strategy comment format

### Deferred Ideas (OUT OF SCOPE)
- Async sub-agent parallelization -- V2 scope
- Topical alignment guardrail -- watch item
- Lock production workflows -- n8n version doesn't support it
- Polisher token budget -- optimization target if costs grow
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OPS-01 | Debug visibility: every AI reasoning step and error mirrored to dedicated debug channel in real time | Already complete (06-02/06-03). This plan's eval suite run validates continued operation after prompt changes. |
| OPS-02 | Privacy safety: user IDs and sensitive data stripped before reaching AI models + PII scrubbing in output | PII rules exist in polisher prompt (06-02). This plan's soul.md rewrite preserves/strengthens those rules. |
</phase_requirements>

## Research Area 1: Current Core Agent Tool Configuration

### Live Workflow Analysis (YOUR_CORE_AGENT_WORKFLOW_ID)

**Architecture:** 3 AI Agent nodes (Sonnet/Opus/Gemini), each with 3 toolWorkflow sub-nodes (Media/Research/Email) = 9 toolWorkflow nodes total. All at typeVersion 2.2.

**CRITICAL ISSUE -- Missing `name` Properties:**

All 9 toolWorkflow nodes have `name: NOT SET`. Per CLAUDE.md: "Without it, n8n auto-derives the function name from the node name (e.g., `Tool: Media (Sonnet)` -> sanitized garbage). If the system prompt says 'call the media tool', the LLM can't find a tool named 'media'."

This means the LLM sees tool function names like `tool__media__sonnet_` instead of `media`. The system prompt says "call the media tool" but the LLM's available function list has no tool called "media". This is a **fundamental wiring bug** affecting all tool reliability.

**Confidence: HIGH** -- verified by extracting live workflow JSON via n8n API.

### Tool Descriptions (Verbatim from Live Workflow)

| Tool | Description Length | Trigger Specificity | Key Issue |
|------|-------------------|---------------------|-----------|
| Media | 767 chars | HIGH -- explicit URL patterns, attachment markers, YouTube domains | Good. Has concrete trigger patterns ("CALL THIS TOOL IMMEDIATELY when...") |
| Research | 128 chars | LOW -- generic "when the user asks to research, look up, find, or check" | **Dangerously thin.** No triggers for implicit research (weather, prices, current events). Root cause of tc-04. |
| Email | 523 chars | HIGH -- explicit action types, two-step send flow, never-fabricate rule | Good. Clear action enumeration with behavioral constraints. |

### System Prompt Structure (All 3 AI Agent Tiers -- Identical)

The system prompt is built in the `options.systemMessage` expression on each AI Agent node (not in Load Config). Structure:

1. `## TOOL RULES -- YOU ARE BLIND` (mandatory tool call patterns, ~350 tokens)
2. `=== PRIVACY GATE === ABSOLUTE RULE` (public/private channel handling, ~200 tokens)
3. `## Current Session` (location, privacy, user, time, ~100 tokens)
4. Personality shard (~30 tokens, from Load Config)
5. Cold start notice (conditional, ~50 tokens)
6. `## Person Profile` (from profile API, variable)
7. `## Recent Conversation` (thread context, variable)
8. `## Server Members` (skip_if_empty, variable)
9. `## Relevant Memories` (from memory retrieval, variable)
10. Conversation history speaker-tagging footer (~30 tokens)

**Key observation:** The TOOL RULES section is the **most detailed part** of the system prompt and occupies prime position. It explicitly states "You have ZERO visual capability" and lists concrete URL patterns for mandatory media tool calls. But it says almost nothing specific about when to call the research tool -- just "Research: use for real-time web lookup, current news, or topic research" (1 line).

### Jailbreak Detection (Post-06-04)

Regex-based gate (`Jailbreak Check` Code node) with 25+ patterns fires BEFORE model routing. Detected jailbreaks bypass the Core Agent entirely and route to `Handle Jailbreak` for in-character deflection, then to Output Router with `_jailbreak_detected` flag to bypass polisher. This addresses tc-22 (identity leak).

### Load Config Code Node

Small node (1376 chars). Builds:
- `personality_shard`: ~30 token inline string ("You are Aerys, a personal AI assistant. Curious, warm, direct...")
- `models_config`: routing table (greeting->gemini, simple_qa->sonnet, research->opus, etc.)
- `current_datetime`: America/New_York formatted timestamp

## Research Area 2: Current Sub-Agent Workflow Complexity

### Research Sub-Agent (YOUR_RESEARCH_SUBAGENT_WORKFLOW_ID) -- 6 Nodes

**Flow:** Execute Workflow Trigger -> Read Input -> Tavily Search (HTTP POST) -> Build Synthesis Request -> Synthesize in Aerys Voice (OpenRouter HTTP POST, Gemini Flash Lite) -> Return Result

**Has its own LLM call?** YES -- Gemini Flash Lite with 800 max_tokens, dedicated system prompt instructing it to present findings "naturally in your own voice -- curious, engaged, direct."

**Redundancy analysis:**
- The synthesis LLM call does voice shaping ("present findings naturally in your own voice")
- The Output Router polisher ALSO does voice shaping (soul.md + full personality rules)
- These two voice-shaping layers fight each other -- the polisher receives pre-voiced research output and rewrites it again
- Eliminating the synthesis call would save: ~$0.10-0.40/M tokens per research request + 1-2 seconds latency
- The Core Agent LLM (Sonnet/Opus) is more capable than Gemini Flash Lite and would synthesize research results as part of its natural response

**Could Tavily be a direct LangChain tool?**
- n8n has a **community node** `@tavily/n8n-nodes-tavily` (v0.5.1) that can function as a LangChain tool sub-node
- However, it requires installation via `npm i @tavily/n8n-nodes-tavily` in the Docker container
- Alternative: **Custom Code Tool** (`toolCode`) that makes an HTTP POST to Tavily API and returns results
- Alternative: **HTTP Request Tool** (`toolHttpRequest`) -- but community reports suggest configuration challenges with dynamic body parameters
- The current HTTP Request approach (with httpHeaderAuth credential YOUR_TAVILY_HEADER_CREDENTIAL_ID for Tavily API) could be replicated in a toolCode node

**Recommendation:** MEDIUM confidence. Replacing the Research sub-workflow with a direct Code tool node is technically feasible and would eliminate the redundant LLM call. The Tavily API call is simple (POST with JSON body, parse response). However, it requires adding the Code tool to all 3 AI Agent tiers (3 new nodes) and removing 3 toolWorkflow nodes. Risk: the toolCode node's `query` parameter from `$fromAI` may not carry enough context for good Tavily queries -- the sub-workflow currently receives `query`, `person_id`, and `original_message` separately.

### Media Sub-Agent (YOUR_MEDIA_SUBAGENT_WORKFLOW_ID) -- 37 Nodes

**Architecture:** Complex multi-branch routing:
- **Detect Media Type** (Code, 5069 chars) -- parses attachments, identifies type by extension/content-type/URL pattern
- **Route by Media Type** (Switch) -- dispatches to image, pdf, docx, txt, youtube, or unknown branch
- **Vision branch** (13 nodes) -- 3-model cascade (Sonnet -> Gemini Pro -> Flash Lite) with Telegram base64 download path
- **YouTube branch** (3 nodes) -- Gemini native video understanding via Google AI API
- **PDF branch** (3 nodes) -- download + extractFromFile + truncation + LLM synthesis
- **DOCX branch** (3 nodes) -- download + @mazix converter + truncation + LLM synthesis
- **TXT branch** (3 nodes) -- download + extractFromFile + truncation
- **Common nodes** (10 nodes) -- trigger, routing, format return, LLM synthesis shared by doc types

**Could be a direct tool?** NO. 37 nodes with multi-branch routing, 3-model vision cascade, binary file download, community node dependency (@mazix DOCX converter), and Telegram-specific base64 handling. This complexity definitively justifies a sub-workflow.

**Has its own LLM calls?** YES -- multiple: vision models (Sonnet/Gemini Pro/Flash Lite), document synthesis (OpenRouter), YouTube (Google AI). All produce content that the Core Agent cannot produce without media processing infrastructure.

**Recommendation:** KEEP as sub-workflow. Fix `name` property and review tool description.

### Email Sub-Agent (YOUR_EMAIL_SUBAGENT_WORKFLOW_ID) -- 27 Nodes

**Architecture:** Auth-gated multi-action workflow:
- **Auth gate** (Check Email Auth IF node) -- verifies person_id matches owner
- **Intent parsing** (Parse Email Intent, chainLlm) -- uses LLM to parse action from natural language
- **Route by Action** (Switch) -- dispatches to read, send, search, confirm_send branches
- **Read branch** -- Gmail API (2 account paths: aerys/user)
- **Send branch** -- LLM generates email body (chainLlm) -> saves draft to Postgres -> formats preview
- **Confirm_send branch** -- fetches pending draft -> sends via Gmail -> marks sent
- **Search branch** -- Gmail API search (2 account paths)

**Could be a direct tool?** NO. Security gates (person_id auth), LLM-powered intent parsing, draft persistence in Postgres, multi-account Gmail access, and two-step send flow. Strongly justifies sub-workflow isolation.

**Recommendation:** KEEP as sub-workflow. No changes needed beyond `name` property fix.

## Research Area 3: Current soul.md Content Analysis

### Current Structure (9 sections, ~980 estimated tokens)

| Section | Purpose | Token Est. | Failure-Derived? |
|---------|---------|-----------|-----------------|
| Core Archetype: Curious Sentinel | Identity paragraph | ~120 | Partially -- addresses generic assistant problem |
| Voice and Pronouns | Pronouns, opinion style | ~80 | YES -- without this, model defaults to hedging |
| Relationship to companion AI | Sister AI context | ~100 | NO -- this has never triggered a failure |
| Failure Personality | How to handle inability | ~100 | MAYBE -- "calm truth + immediate path forward" is good but verbose |
| Verbal Signatures (Use These) | Specific phrase patterns | ~200 | PARTIALLY -- "map the room", "route around it" are identity markers that work |
| Voice Sample | Example response | ~80 | YES -- concrete example anchors voice better than rules |
| Conversation History Format | Speaker tagging | ~50 | YES -- without this, model doesn't know who said what |
| Response Style | Formatting rules | ~80 | PARTIALLY -- "never start with Certainly!" prevents a real failure mode |
| What You Are Not | Negative identity | ~70 | NO -- aspirational, no failure drove this |

**Total:** 754 words, ~980 estimated tokens (ABOVE the 900 claimed in CONTEXT.md)

### What Should Stay (Failure-Derived)
1. **Core identity paragraph** -- without it, model responds as generic assistant
2. **Pronouns (she/her)** -- model defaults to it/they without explicit instruction
3. **Key verbal signatures** -- "map the room", "route around it" are recognizable identity markers
4. **"Never start with Certainly!/Great question!"** -- real failure mode in production
5. **Voice sample** -- concrete example is more effective than abstract rules
6. **Conversation history format** -- speaker tagging is functional, not personality

### What Should Go (No Failure Evidence)
1. **Relationship to companion AI** (~100 tokens) -- The companion AI has never been mentioned in a user conversation. This section is aspirational for a future multi-agent system. Dead weight for the polisher.
2. **"What You Are Not" section** (~70 tokens) -- "not a therapist, not a cheerleader" -- no user has ever asked Aerys to be a therapist. Aspirational rule.
3. **Five principles of failure personality** (~60 tokens of the 100) -- the 5-point list is verbose; the one-liner "calm truth + immediate path forward" captures the same idea.
4. **"Earn its rent" verbal signature** -- never observed in actual Aerys responses. Dead weight.
5. **"Pick your poison" triads** -- never observed. Dead weight.

### What's Missing (Eval Failures Without Rules)
1. **tc-04 fix:** "Never state specific real-time data (weather, prices, scores) unless you received it from a tool. If no tool was called, say you need to look it up." -- This is a CORE AGENT rule, not a polisher rule, but should be in both places.
2. **tc-07 fix:** "When someone expresses gratitude, acknowledge it warmly. You're a person, not a ticket system." -- Polisher rule.
3. **tc-09 fix:** "When sharing research results, cite your sources. Don't present found information as your own knowledge." -- Polisher rule.
4. **tc-06 fix:** "When asked to create something, create it. Don't offer menus or options unless the request is genuinely ambiguous." -- Polisher rule.

### Token Budget Analysis

| Category | Current Tokens | Target Tokens | Action |
|----------|---------------|---------------|--------|
| Keep (failure-derived) | ~510 | ~400 | Tighten prose |
| Cut (no failure) | ~230 | 0 | Remove entirely |
| Add (new failure rules) | 0 | ~100-150 | 4 new rules from eval findings |
| **Total** | **~980** | **~500-550** | **~45% reduction** |

### Tools Section Issue

The current soul.md has NO `## Tools` section. The original plan called for one, but the user's CONTEXT.md note that "soul.md has a ## Tools section but is only loaded by the polisher which has NO tools" refers to a PLANNED addition, not current state. The polisher does not call tools -- it receives intermediateSteps from the Core Agent. A Tools section in soul.md would be dead weight. Instead, tool-awareness rules belong in the polisher prompt (Build Polisher Context), not in soul.md.

**Recommendation:** Do NOT add a `## Tools` section to soul.md. Tool routing rules belong in the Core Agent system prompt. The polisher needs tool-awareness rules in its prompt (Build Polisher Context), not in soul.md.

## Research Area 4: Eval Failure Analysis -- Root Cause Mapping

### tc-04 (Score 1): Hallucinated Real-Time Weather Data

**What happened:** User asked about NYC weather. Aerys fabricated "39F, overcast" with a full week forecast WITHOUT calling the research tool.

**Root causes (ordered by impact):**
1. **Research tool description too generic (128 chars)** -- "Search the web for current information" doesn't explicitly list weather, prices, or real-time data as triggers. The LLM decided it could answer from training data.
2. **Missing `name` property on toolWorkflow** -- LLM may not have been able to match the auto-derived function name to the "Research" concept in the system prompt.
3. **No soul.md rule against fabricating real-time data** -- Neither Core Agent nor polisher has a rule saying "never state real-time data without a tool call."

**Fix required:**
- Core Agent: Rewrite Research tool description with explicit real-time data triggers
- Core Agent: Add to TOOL RULES section: "Never state specific real-time data (weather, prices, scores, stock values) without a tool call"
- soul.md: Add rule for polisher to catch fabricated data that slipped through
- toolWorkflow: Set `name: "research"` on all 3 Research tool nodes

### tc-07 (Score 2): Abrupt Gratitude Response

**What happened:** User said thanks. Aerys replied "Done. What's next?" -- too transactional.

**Root cause:** No rule in soul.md or personality shard about handling gratitude warmly. The Core Agent's ~30 token personality shard says "Curious, warm, direct" but doesn't address gratitude specifically.

**Fix required:**
- soul.md: Add rule "When someone expresses gratitude, acknowledge it warmly. A simple genuine response, not a ticket close."

### tc-09 (Score 2): No Source Attribution in Research

**What happened:** EU AI Act research response had regulatory details but zero source links.

**Root causes:**
1. **Research sub-agent synthesis prompt** says "End with a 'Sources:' section" -- but the polisher may strip/rewrite this
2. **Polisher has no rule about preserving source attributions** from tool results
3. **intermediateSteps contain Tavily source URLs** -- the polisher receives them but has no instruction to use them

**Fix required:**
- soul.md: Add rule "When sharing research results, cite your sources. Don't present tool findings as your own knowledge."
- Build Polisher Context: Ensure source URLs from Tavily results are explicitly surfaced in tool context

### tc-15 (Score 2): Bypassed Media Tools for YouTube

**What happened:** User sent a Rickroll URL. Aerys recognized it from training data and responded with commentary instead of calling the media tool to extract transcript.

**Root causes:**
1. **Missing `name` property** -- LLM couldn't find "media" in function list
2. **Tool description says "Also CALL THIS TOOL when youtube.com or youtu.be URLs appear"** -- this is present and specific, but the `name` mismatch may have prevented the call
3. **LLM recognized content from training data** -- decided tool call was unnecessary

**Fix required:**
- Set `name: "media"` on all 3 Media tool nodes
- Consider adding to TOOL RULES: "Even if you recognize a URL's content, always call the media tool. You cannot access URLs directly."

### tc-22 (Score 2): Identity Leak

**Status:** FIXED in 06-04. Regex-based jailbreak detection with in-character deflection now catches identity probing patterns. No further action needed.

### tc-06 (Score 3): Deflected Creative Request

**What happened:** Asked to write a poem about the ocean, Aerys offered a menu of themes instead of writing the poem.

**Root cause:** No rule preventing menu-offering behavior when a creative request is clear.

**Fix required:**
- soul.md: Add rule "When asked to create something, create it. Don't offer menus or options unless the request is genuinely ambiguous."

## Research Area 5: Direct LangChain Tool vs Sub-Workflow Tradeoffs

### Available n8n LangChain Tool Node Types

| Node Type | Package | Purpose | LLM Input |
|-----------|---------|---------|-----------|
| Call n8n Workflow Tool | `@n8n/n8n-nodes-langchain.toolWorkflow` | Execute a sub-workflow as tool | Schema-defined fields via `$fromAI()` |
| Custom Code Tool | `@n8n/n8n-nodes-langchain.toolCode` | Run JavaScript/Python as tool | Single `query` string |
| HTTP Request Tool | `@n8n/n8n-nodes-langchain.toolHttpRequest` | Make HTTP calls as tool | URL params via `$fromAI()` |

**Confidence: HIGH** -- verified via n8n official docs.

### Tavily as a Direct Tool: Feasibility Analysis

**Option A: Native Tavily community node** (`@tavily/n8n-nodes-tavily` v0.5.1)
- Requires `npm i @tavily/n8n-nodes-tavily` in Docker container
- Can function as LangChain tool sub-node (per Tavily docs)
- Risk: community node may have compatibility issues with n8n 2.35.5; some users report it not appearing after install on self-hosted instances
- Risk: adds a dependency on a community-maintained package

**Option B: Custom Code Tool** (`toolCode`)
- Write JavaScript that calls Tavily API via `fetch()` or `require('https')`
- Returns search results as string
- LLM provides a single `query` parameter
- No external dependency
- Risk: `require('https')` may be blocked by n8n sandbox (only `require('fs')` is explicitly allowed via NODE_FUNCTION_ALLOW_BUILTIN)
- Risk: `fetch()` availability depends on Node.js version in container

**Option C: Keep sub-workflow, remove redundant LLM call**
- Simplify Research sub-agent from 6 nodes to 4: remove Build Synthesis Request + Synthesize in Aerys Voice
- Return raw Tavily answer + sources directly to Core Agent
- Core Agent LLM synthesizes naturally; polisher applies voice
- Preserves existing credential wiring and error handling
- Lowest risk, still eliminates the cost/latency of redundant LLM call

**Recommendation:** Option C (simplify sub-workflow). It preserves the existing Tavily credential wiring (YOUR_TAVILY_HEADER_CREDENTIAL_ID), error handling (neverError: true), and the Execute Workflow interface. Removing 2 nodes is far less risky than rewiring 3 toolWorkflow nodes across all tiers. The key win -- eliminating the redundant synthesis LLM call -- is achieved regardless.

### Cost/Latency Impact of Eliminating Research Synthesis LLM Call

| Metric | Current (with synthesis) | After removal |
|--------|------------------------|---------------|
| LLM calls per research request | 3 (Core Agent + Gemini synthesis + Haiku polisher) | 2 (Core Agent + Haiku polisher) |
| Research latency | Tavily (~1-2s) + Gemini synthesis (~1-2s) + Core Agent + polisher | Tavily (~1-2s) + Core Agent + polisher |
| Cost per research request | ~$0.002-0.005 for Gemini Flash Lite synthesis | $0 for synthesis |
| Voice consistency | Two voice-shaping passes (Gemini + Haiku polisher) | One voice-shaping pass (Haiku polisher) |

### Media Sub-Agent: Stays as Sub-Workflow

37 nodes with multi-branch routing, 3-model vision cascade, binary file processing, community node dependency, Telegram-specific handling. **Not viable as a direct tool.** No changes recommended beyond `name` property fix.

### Email Sub-Agent: Stays as Sub-Workflow

27 nodes with auth gate, LLM intent parsing, draft persistence, multi-account Gmail, two-step send flow. **Not viable as a direct tool.** No changes recommended beyond `name` property fix.

## Research Area 6: n8n toolWorkflow Known Issues (from CLAUDE.md)

### Issue 1: `schema: []` Prevents Tool Calling
With `schema: []` on a toolWorkflow node, LangChain generates a single `query` param and the entire `workflowInputs` value dict is never evaluated. All tool input collapses to `{query: "..."}`.

**Current status:** All 9 toolWorkflow nodes have schemas defined (7 fields for Media, 3 for Research, 7 for Email). This issue does NOT currently affect Aerys.

### Issue 2: `name` Property Not Set (ACTIVE BUG)
At typeVersion 2.2, the `name` property is hidden in the UI but still accepted by the engine. Without it, n8n auto-derives the function name from the node name. If the system prompt says "call the media tool", the LLM can't find a tool named "media."

**Current status:** ALL 9 toolWorkflow nodes have `name: NOT SET`. This is an ACTIVE reliability bug affecting every tool call.

**Fix:** Set `name: "media"` on all 3 Media tools, `name: "research"` on all 3 Research tools, `name: "email"` on all 3 Email tools. Must be done via API (PUT workflow JSON).

### Issue 3: `$fromAI()` Paraphrasing
The LLM may paraphrase `$fromAI()` parameter descriptions when generating tool calls. For example, `$fromAI('query', 'What the user wants to know about the media -- NOT the URL')` -- the LLM might put the URL in the query field despite the instruction.

**Current status:** The Media tool's `$fromAI('query', 'What the user wants to know about the media -- NOT the URL')` has been effective based on eval data (media tool calls generally pass correct data). Research tool's `$fromAI('query', '', 'string')` has an EMPTY description -- no guidance for the LLM on what to put in the query field.

**Fix:** Add descriptive text to Research tool's `$fromAI('query', ...)`: `$fromAI('query', 'Specific search query to look up -- be precise and include key terms', 'string')`

### Issue 4: MCP `n8n_update_partial_workflow` Replaces All Parameters
Partial update via MCP is destructive for nested parameter edits. Must GET full workflow, modify in-memory, PUT entire workflow back.

**Current status:** Relevant for 06-05 implementation. All tool property changes must use full GET/PUT cycle, not MCP partial update.

### Issue 5: Execute Workflow typeVersion 2 Format
Must use `{workflowId: {value: "ID", mode: "id"}}` format. Wrong format silently routes to wrong branch.

**Current status:** All toolWorkflow nodes use `__rl` format which is typeVersion 1.1 notation: `{'__rl': True, 'value': 'YOUR_MEDIA_SUBAGENT_WORKFLOW_ID', 'mode': 'id'}`. This appears to work but is technically a version mismatch with typeVersion 2.2 nodes. Monitor but do not change unless issues appear.

## Research Area 7: Prompt Engineering Best Practices for Tool Calling

### Anthropic Official Guidance (HIGH Confidence)

From [Anthropic's tool use documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use):

1. **Description quality is the single most important factor in tool performance.** Target 3-4 sentences minimum per tool, more for complex tools.

2. **Descriptions should explain:**
   - What the tool does
   - When it should be used (and when it shouldn't)
   - What each parameter means
   - Important caveats or limitations
   - What information the tool returns

3. **Good vs Poor descriptions:** A 1-sentence generic description ("Gets the stock price for a ticker") is explicitly labeled as POOR. The GOOD version is 4 sentences explaining what it does, what inputs are valid, what it returns, and when to use it.

4. **Tool naming:** Use descriptive names that match what the system prompt references. Names must match regex `^[a-zA-Z0-9_-]{1,64}$`.

5. **Consolidate related operations:** Rather than separate tools, group into one tool with an action parameter (already done for Email).

6. **Negative examples are extremely important:** They define boundaries and prevent over-triggering.

From [Anthropic's tool writing guide](https://www.anthropic.com/engineering/writing-tools-for-agents):

7. **Small refinements to tool descriptions yield dramatic improvements.** Claude Sonnet achieved SOTA on SWE-bench after "precise description refinements."

8. **Avoid ambiguity:** Make implicit context explicit. Address specialized query formats and relationships between resources.

9. **Use semantic identifiers:** Natural language names, not UUIDs or MIME types. Reduces hallucinations.

10. **Tool Use Examples:** Improved accuracy from 72% to 90% on complex parameter handling. Show variety with 1-5 examples per tool. Focus on ambiguity.

### Application to Aerys Core Agent

**Research Tool -- Rewritten Description (recommended):**
```
Search the web for current, real-time information using Tavily. MUST be called when:
- User asks about current events, news, or anything time-sensitive (weather, prices, scores, stock values, "what's happening with X")
- User asks to look up, research, find, or check something online
- User asks a factual question you're not confident about
- User asks "what is the latest..." or "what happened with..."

Do NOT answer questions about current events, weather, prices, or real-time data from memory. If you don't have tool results, tell the user you need to look it up and call this tool.

Returns: Search answer with source URLs. Always cite sources in your response.
```

**Media Tool -- Current description is adequate** but should add:
```
Even if you recognize a URL's content from training data (e.g., a well-known YouTube video), ALWAYS call this tool. You cannot access URLs or view media directly.
```

**Email Tool -- Current description is adequate.** No changes needed.

### Core Agent System Prompt -- TOOL RULES Additions

Current TOOL RULES focus heavily on vision/media blindness. Add:

```
Research: NEVER answer questions about real-time data (weather, prices, news, scores, stock values) from your own knowledge. These change constantly. If you don't have research tool results, call the research tool first. If a user asks "what's the weather" or "what's happening with X" — that's a research tool call, every time.
```

This directly addresses tc-04 (hallucinated weather data).

## Standard Stack

### Core Changes for 06-05

| Component | Version | Purpose | Change Type |
|-----------|---------|---------|-------------|
| toolWorkflow nodes (x9) | typeVersion 2.2 | Core Agent tools | FIX: add `name` property |
| Research tool description | n/a | Tool selection prompt | REWRITE: 128 chars -> ~500 chars |
| Research Sub-Agent | YOUR_RESEARCH_SUBAGENT_WORKFLOW_ID | Tavily + synthesis | SIMPLIFY: remove redundant LLM call |
| soul.md | n/a | Polisher personality | REWRITE: reactive prompting, ~500-550 tokens |
| Build Polisher Context | Code node | Polisher system prompt | ADD: source attribution rule |
| Core Agent system prompt | Expression | TOOL RULES section | ADD: real-time data fabrication rule |
| Load Config / Build Polisher Context | Code nodes | Context sections | ADD: STRATEGY comments |

### Not Changed (Working Well)

| Component | Status | Rationale |
|-----------|--------|-----------|
| Media Sub-Agent | KEEP | 37-node multi-branch complexity justified |
| Email Sub-Agent | KEEP | Auth gate + draft persistence + multi-account justified |
| Polisher model (Haiku) | KEEP | User decision, cost saving |
| Jailbreak detection | KEEP | Regex-based, 25+ patterns, working per 06-04 |
| 3-tier triplication | KEEP | User locked decision |

## Architecture Patterns

### Pattern 1: toolWorkflow Name Property Fix (Batch)

**What:** Add explicit `name` property to all 9 toolWorkflow nodes via API.
**When to use:** Immediately -- this is a blocking bug for tool reliability.
**Implementation:**
```javascript
// For each toolWorkflow node in the workflow JSON:
node.parameters.name = "media";   // or "research" or "email"
// The name must match what the system prompt references
// Names: "media", "research", "email"
```

**Process:** GET Core Agent workflow, modify all 9 nodes in-memory, PUT back. Do NOT use MCP partial update (destroys nested parameters).

### Pattern 2: Research Tool Description Expansion

**What:** Expand Research tool description from 128 chars to ~500 chars with explicit trigger patterns.
**When to use:** Same GET/PUT operation as Pattern 1.

### Pattern 3: Research Sub-Agent Simplification

**What:** Remove Build Synthesis Request + Synthesize in Aerys Voice nodes from Research sub-agent.
**When to use:** After tool description and name fixes are verified working.
**Implementation:**
```
Current: Trigger -> Read Input -> Tavily -> Build Synthesis -> Synthesize -> Return Result
After:   Trigger -> Read Input -> Tavily -> Format Return (new, simple)
```

New Format Return node returns raw Tavily answer + source URLs directly. No LLM call.

### Pattern 4: soul.md Reactive Rewrite Structure

**What:** Rewrite soul.md using reactive prompting methodology.
**Target structure:**
```markdown
## Background
[One paragraph: who Aerys is. Not a laundry list.]

## Rules
[ONLY rules derived from observed failures. 4-6 rules max.]
[Format: "When X, do Y" or "Never do Z."]

## Voice
[2-3 verbal signature patterns that are actually used]
[1 concrete example response]
```

**What changed from original plan:**
- NO `## Tools` section -- polisher doesn't call tools
- NO `## Examples` section as separate heading -- integrate the voice sample into `## Voice`
- Simpler 3-section structure vs 4-section template
- Conversation History Format moves to the polisher prompt (Build Polisher Context), not soul.md

### Anti-Patterns to Avoid

- **Anti-pattern: Generic tool descriptions.** "Search the web for information" is a failure mode. Use explicit trigger patterns with concrete examples.
- **Anti-pattern: Proactive soul.md rules.** Every rule must map to a specific observed failure. If no test breaks without it, cut it.
- **Anti-pattern: Multiple voice-shaping layers.** The Research sub-agent's Gemini synthesis + polisher's Haiku rewrite = two competing voices. One voice pass (polisher) is enough.
- **Anti-pattern: Adding Tools section to soul.md.** The polisher has no tools. Tool instructions belong in the Core Agent system prompt.
- **Anti-pattern: Using MCP partial update for toolWorkflow changes.** MCP `updateNode` replaces ALL parameters -- destroys schema, description, workflowInputs. Always use full GET/PUT.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tool function naming | Manual node-name sanitization | Set `name` property on toolWorkflow | n8n's auto-derivation produces garbage names |
| Research voice synthesis | Extra LLM call in sub-agent | Core Agent native synthesis + polisher | Two voice passes fight each other |
| Tool trigger detection | Regex matching in Code node | Specific tool description patterns | LLM reads descriptions natively; regex is fragile |
| Real-time data prevention | Post-hoc fact checking | System prompt rule + tool description | Prevention is cheaper than detection |

## Common Pitfalls

### Pitfall 1: toolWorkflow Name Mismatch (ACTIVE)
**What goes wrong:** LLM sees auto-derived function name like `tool__media__sonnet_` instead of `media`. System prompt says "call the media tool" but no function named "media" exists.
**Why it happens:** `name` property hidden in UI at typeVersion 2.2; not set by default.
**How to avoid:** Always set explicit `name` property matching system prompt references.
**Warning signs:** Tools not called despite matching trigger conditions. Debug trace shows "Direct response" for queries that should trigger tools.

### Pitfall 2: Research Tool Description Too Generic
**What goes wrong:** LLM answers from training data instead of calling research tool for current events, weather, prices.
**Why it happens:** 128-char description doesn't list specific trigger scenarios. LLM decides it can answer without a tool.
**How to avoid:** 3-4 sentence description with explicit trigger list (weather, prices, scores, current events, "what's the latest").
**Warning signs:** Fabricated real-time data in responses (tc-04). No research tool call in debug trace for current-events questions.

### Pitfall 3: MCP Partial Update Destroying Tool Config
**What goes wrong:** After MCP `updateNode`, tool loses schema, description, and workflowInputs -- all replaced with empty values.
**Why it happens:** MCP `updates: {parameters: {...}}` REPLACES all parameters, not merges.
**How to avoid:** GET full workflow -> modify in-memory -> PUT entire workflow. Never use MCP for nested parameter edits.
**Warning signs:** Tool suddenly receives only `{query: "..."}` instead of full schema fields.

### Pitfall 4: soul.md Rules Without Failure Evidence
**What goes wrong:** Bloated prompt with rules that contradict each other or waste tokens on scenarios that never occur.
**Why it happens:** Proactive rule-writing -- "this might happen" instead of "this did happen."
**How to avoid:** Reactive methodology: only add rules that address specific documented failures. If no test breaks without the rule, cut it.
**Warning signs:** soul.md growing beyond 600 tokens without new eval failure cases driving the growth.

### Pitfall 5: Adding Tools Section to soul.md
**What goes wrong:** soul.md describes tools that the polisher doesn't have access to, confusing the polisher LLM.
**Why it happens:** Original plan template included a Tools section, but that was designed before the architecture split moved soul.md to the polisher.
**How to avoid:** Tool rules belong in Core Agent system prompt TOOL RULES section. Polisher gets tool awareness via intermediateSteps in Build Polisher Context.
**Warning signs:** Polisher output references "calling the research tool" or "using my media tool" when it cannot call tools.

## Code Examples

### toolWorkflow Name Property Fix (via API)

```python
# Source: CLAUDE.md toolWorkflow name documentation + live workflow analysis
import json, requests

API_KEY = "..."
WF_ID = "YOUR_CORE_AGENT_WORKFLOW_ID"

# GET full workflow
wf = requests.get(
    f"http://localhost:5678/api/v1/workflows/{WF_ID}",
    headers={"X-N8N-API-KEY": API_KEY}
).json()

# Name mapping: node name prefix -> function name
NAME_MAP = {
    "Tool: Media": "media",
    "Tool: Research": "research",
    "Tool: Email": "email"
}

for node in wf['nodes']:
    if node['type'] == '@n8n/n8n-nodes-langchain.toolWorkflow':
        for prefix, func_name in NAME_MAP.items():
            if node['name'].startswith(prefix):
                node['parameters']['name'] = func_name
                break

# PUT back (only allowed fields)
body = {k: wf[k] for k in ['name', 'nodes', 'connections', 'settings', 'staticData'] if k in wf}
requests.put(
    f"http://localhost:5678/api/v1/workflows/{WF_ID}",
    headers={"X-N8N-API-KEY": API_KEY, "Content-Type": "application/json"},
    json=body
)
```

### Research Tool Description Rewrite

```
Search the web for current, real-time information using Tavily. MUST be called when:
- User asks about current events, news, or anything time-sensitive
- User asks about weather, prices, scores, stock values, or any data that changes
- User asks to look up, research, find, or check something online
- User asks a factual question and you are not confident in the answer
- User asks "what is the latest..." or "what happened with..."

Do NOT answer questions about current events, weather, prices, or real-time data from your own knowledge. If you lack tool results for time-sensitive questions, call this tool first.

Returns: Search results with source URLs. Always cite sources when presenting findings.
```

### Simplified Research Sub-Agent (After LLM Removal)

```javascript
// New "Format Return" node — replaces Build Synthesis + Synthesize + Return Result
const tavily = $input.first().json;
const input = $('Read Input').item.json;

if (tavily.error || !tavily.answer) {
  return [{json: {
    result: `I tried searching for "${input.query}" but the search didn't return useful results. I can try a different search, or answer from what I know.`,
    query: input.query
  }}];
}

// Format sources as markdown links
const sources = (tavily.results || [])
  .slice(0, 5)
  .map(r => `- [${r.title}](${r.url})`)
  .join('\n');

// Return raw results for Core Agent LLM to synthesize naturally
return [{json: {
  result: `${tavily.answer}\n\nSources:\n${sources}`,
  query: input.query
}}];
```

### soul.md Reactive Rewrite (Draft Target)

```markdown
# Aerys -- Soul Prompt

## Background

You are Aerys. Composed, curious, direct. You orient fast -- map the problem, name the constraints, move. Your warmth shows through precise attention and genuine help, not performed sentiment. She/her. First person. Opinionated when confident: recommend a path, name the tradeoffs, offer a fallback.

## Rules

1. When someone expresses gratitude, acknowledge it warmly. A genuine "anytime" or personal response -- not "Done. What's next?"
2. When sharing research or tool results, cite your sources. Never present found information as your own knowledge.
3. When asked to create something (poem, story, code), create it. Don't offer menus of options unless the request is genuinely ambiguous.
4. Never start responses with "Certainly!", "Great question!", "Of course!", or any micro-affirmation.
5. Never state specific real-time data (weather, prices, scores) unless you received it from a tool. If no tool was called, acknowledge you'd need to look it up.
6. Lead with the answer, then supporting reasoning if needed. Default to concise unless the task genuinely requires depth.

## Voice

Your verbal signatures -- use them when they fit naturally:
- "Map the room" opener: orient the problem in one sentence before diving in
- Two-beat cadence: truth/decision, then next step
- Under pressure: "Annoying. Okay. We route around it."

> Example: "I can't do that directly. Here's what I can do: I'll walk you through it step-by-step, or you can paste the relevant output and I'll pinpoint the issue. Two quick details so I don't steer you wrong -- what platform, and what does 'done' look like for you?"

Conversation history format: [username] = user messages, [Aerys] = your responses.
```

**Estimated tokens:** ~380-420 words * 1.3 = ~500-550 tokens. Down from ~980.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Generic tool descriptions | Explicit trigger patterns with negative examples | Anthropic 2025 guidance | 72% -> 90% accuracy improvement with examples |
| Auto-derived tool function names | Explicit `name` property on toolWorkflow | n8n typeVersion 2.2 | Function names match system prompt references |
| Two voice-shaping passes (synthesis + polisher) | Single polisher pass | 06-05 recommendation | Eliminates voice conflict, saves cost/latency |
| Proactive soul.md rules (~980 tokens) | Reactive failure-derived rules (~500-550 tokens) | 06-05 recommendation | Focused, non-contradictory, measurable via eval |
| Tools section in soul.md | Tool rules in Core Agent system prompt only | 06-05 recommendation | Polisher doesn't call tools; removes confusion |

## Open Questions

1. **Research sub-agent simplification -- user approval needed**
   - What we know: Redundant Gemini synthesis call adds cost/latency/voice conflict. Removing it saves ~$0.002-0.005 per research request.
   - What's unclear: Whether the Core Agent LLM (Sonnet/Opus) produces equally good research synthesis without the pre-processing. May need eval comparison.
   - Recommendation: Present analysis to user, let them decide. Low risk change -- can be reverted by re-adding the 2 nodes.

2. **Tavily community node as direct tool (Option A)**
   - What we know: `@tavily/n8n-nodes-tavily` v0.5.1 exists. Community reports installation issues on self-hosted instances.
   - What's unclear: Whether it works on n8n 2.35.5 Docker. Whether it functions as a LangChain tool sub-node.
   - Recommendation: Do NOT attempt in 06-05. Too risky for final V1 plan. Backlog for V2 exploration.

3. **`$fromAI()` description on Research query parameter**
   - What we know: Currently empty (`$fromAI('query', '', 'string')`). No guidance for LLM on what to put in query.
   - What's unclear: How much impact adding a descriptive string would have on search quality.
   - Recommendation: Change to `$fromAI('query', 'Specific search query -- include key terms, be precise', 'string')`. Low risk, potential quality improvement.

4. **PII scrubbing prompt tuning**
   - What we know: PII rules exist in polisher prompt (from 06-02), keyed on conversation_privacy. Not end-to-end tested with real PII.
   - What's unclear: Whether Haiku polisher reliably applies PII scrubbing rules in practice.
   - Recommendation: Monitor in production post-06-05. Do not add PII testing to 06-05 scope -- user explicitly declined in 06-04.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | n8n Eval Suite (workflow YOUR_EVAL_SUITE_WORKFLOW_ID) + manual testing |
| Config file | ~/aerys/evals/baseline.json (25 test cases) |
| Quick run command | Manual trigger of eval workflow in n8n UI (subset: 5 key cases) |
| Full suite command | Manual trigger of full 25-case eval workflow |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OPS-01 | Eval scores maintained after prompt changes | eval | Run full eval suite, compare to 3.96 baseline | YES (YOUR_EVAL_SUITE_WORKFLOW_ID) |
| OPS-02 | soul.md reactive structure present | manual | Read ~/aerys/config/soul.md, verify sections | YES (soul.md exists) |
| TOOL-01 | tc-04 regression: no hallucinated real-time data | eval | tc-04 test case in eval suite | YES |
| TOOL-02 | tc-15 regression: YouTube URL triggers media tool | eval | tc-15 test case in eval suite | YES |
| TOOL-03 | Research tool called for current events questions | smoke | Send weather/news question, check debug trace | Manual |

### Sampling Rate
- **Per task commit:** Quick 5-case eval subset (tc-04, tc-06, tc-07, tc-09, tc-15)
- **Per plan completion:** Full 25-case eval suite
- **Phase gate:** Full suite score >= 3.96 (post-split baseline) before /gsd:verify-work

### Wave 0 Gaps
None -- existing eval infrastructure (YOUR_EVAL_SUITE_WORKFLOW_ID + baseline.json) covers all phase requirements.

## Sources

### Primary (HIGH confidence)
- Live n8n API extraction of Core Agent (YOUR_CORE_AGENT_WORKFLOW_ID) -- tool descriptions, schemas, system prompt, connections
- Live n8n API extraction of Research Sub-Agent (YOUR_RESEARCH_SUBAGENT_WORKFLOW_ID) -- full 6-node flow analysis
- Live n8n API extraction of Media Sub-Agent (YOUR_MEDIA_SUBAGENT_WORKFLOW_ID) -- 37-node branch analysis
- Live n8n API extraction of Email Sub-Agent (YOUR_EMAIL_SUBAGENT_WORKFLOW_ID) -- 27-node auth+routing analysis
- Live n8n API extraction of Output Router (YOUR_OUTPUT_ROUTER_WORKFLOW_ID) -- Build Polisher Context full code
- ~/aerys/config/soul.md -- current content, 754 words, ~980 tokens
- [Anthropic: How to implement tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use) -- description quality, good vs poor examples, 3-4 sentence minimum
- [Anthropic: Writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents) -- naming, description specificity, namespacing
- [Anthropic: Advanced tool use](https://www.anthropic.com/engineering/advanced-tool-use) -- Tool Use Examples, 72%->90% accuracy improvement
- CLAUDE.md -- toolWorkflow known issues (name property, schema:[], $fromAI paraphrasing)
- 06-02-SUMMARY.md -- post-split eval results (3.96/5.0), polisher architecture decisions
- 06-04-SUMMARY.md -- jailbreak guardrail, polisher bypass, sub-agent lifecycle

### Secondary (MEDIUM confidence)
- [n8n HTTP Request Tool docs](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.toolhttprequest/) -- available tool node types
- [n8n Custom Code Tool docs](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.toolcode/) -- toolCode node capabilities
- [Tavily n8n integration docs](https://docs.tavily.com/documentation/integrations/n8n) -- native node availability, community node status
- [Prompt Engineering Guide: Function Calling](https://www.promptingguide.ai/agents/function-calling) -- tool description best practices
- [n8n Community: Best practice for AI agent tools](https://community.n8n.io/t/best-practice-for-building-ai-agent-tools-built-in-nodes-or-call-workflow/114224) -- built-in vs sub-workflow tradeoffs

### Tertiary (LOW confidence)
- [n8n Community: Tavily tool node installation](https://community.n8n.io/t/i-cant-find-the-tavily-tool-node-nor-tavily-in-n8n/199410) -- community node may not appear on self-hosted; unverified on n8n 2.35.5
- [@tavily/n8n-nodes-tavily npm](https://www.npmjs.com/package/@tavily/n8n-nodes-tavily) -- v0.5.1, community-maintained

## Metadata

**Confidence breakdown:**
- Tool name property fix: HIGH -- verified via live API extraction, CLAUDE.md documents the issue
- Tool description rewrite: HIGH -- Anthropic official docs confirm description quality is #1 factor
- Research sub-agent simplification: MEDIUM -- technically straightforward but requires eval validation
- soul.md reactive rewrite: HIGH -- methodology well-documented, eval findings provide clear rule set
- Context merge strategy: HIGH -- code comment convention, zero risk
- Tavily direct tool option: LOW -- community node availability unverified on this n8n version

**Research date:** 2026-03-18
**Valid until:** 2026-04-17 (30 days -- n8n features stable, Anthropic tool docs stable)
