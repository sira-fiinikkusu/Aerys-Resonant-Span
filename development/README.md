# Development History

This directory contains the planning artifacts from Aerys's development, organized by phase. Each phase followed a plan-research-build-verify cycle, producing implementation plans with specific tasks and acceptance criteria, technology research documents, and post-implementation summaries documenting decisions, deviations, and lessons learned.

The full system was built across 22 plans in 7 phases over approximately five weeks, progressing from bare infrastructure to a production-hardened multi-channel AI assistant.

## Timeline

| Phase | Name | Duration | Plans | Key Deliverables |
|-------|------|----------|-------|------------------|
| 1 | Infrastructure | Feb 17 | 2 | PostgreSQL + pgvector, n8n instance, database schema |
| 2 | Core Agent + Channels | Feb 17--20 | 3 | Discord/Telegram adapters, Core Agent, Output Router |
| 3 | Identity | Feb 20--22 | 3 | Cross-platform identity, slash commands, DM adapter |
| 4 | Memory System | Feb 22--25 | 3 | Three-tier memory, Guardian profiles, pgvector retrieval |
| 5 | Sub-Agents + Media | Feb 25 -- Mar 4 | 4 | Research, email, media sub-agents |
| 5.1 | Memory Quality | Mar 4--7 | 2 | Extraction rewrite, dedup, person_id grouping |
| 6 | Polish + Hardening | Mar 7--22 | 5 | Eval suite, per-tier architecture, guardrails, observability |

**Total: 22 plans across 7 phases, ~5 weeks from first line of infrastructure to production system.**

---

## Phase 1: Infrastructure

The project began with the foundation: a Docker Compose stack running PostgreSQL 16 with pgvector and n8n on a Particle Tachyon board. The database schema was provisioned through numbered SQL migration files executed on first container start. A bind-mount architecture ensured all persistent data lived under a single directory, making the entire stack portable to different hardware.

Early decisions shaped everything that followed. CPU resource limits had to be removed from Docker Compose because the Tachyon's kernel (5.4.219 on QCM6490) uses cgroup v1 without CPU CFS quota support. The discovery that `docker exec` commands stall indefinitely on this kernel led to adopting n8n API-based migration patterns for all future schema changes -- a constraint that persisted through every subsequent phase.

Planning artifacts: [Phase 1 docs](phase-01/)

## Phase 2: Core Agent + Channels

With infrastructure in place, Phase 2 built the conversational loop. Discord and Telegram adapters normalize incoming messages into a common format (content, author, platform, channel metadata), feeding them to the Core Agent. The Core Agent classifies intent and routes to the appropriate model tier via OpenRouter, while the Output Router handles platform-specific formatting, message splitting for Discord's 2000-character limit, and dispatch back to the originating channel.

The most significant technical challenge was configuring n8n's HTTP Request nodes for OpenRouter authentication. The credential system requires explicit `authentication: "genericCredentialType"` and `genericAuthType: "httpHeaderAuth"` parameters -- simply attaching a credential block is silently ignored. This pattern broke the initial intent classifier and was documented as a recurring n8n quirk.

The soul.md personality system was introduced in this phase, loaded at runtime via `require('fs')` from a file on disk. This design means personality changes take effect immediately without redeploying any workflow.

Planning artifacts: [Phase 2 docs](phase-02/) | Workflows: [`02-03-core-agent.json`](../workflows/02-03-core-agent.json), [`02-04-output-router.json`](../workflows/02-04-output-router.json)

## Phase 3: Identity

Phase 3 introduced cross-platform identity resolution. The Identity Resolver maps Discord user IDs and Telegram user IDs to a single `person_id`, enabling shared memory and context across platforms. A Cloudflare tunnel was configured for webhook routing to the Tachyon board.

Discord slash commands were registered via a dedicated workflow, and a DM adapter was built for private conversations. The DM adapter introduced the IPC race condition that would later require a dedicated systemd service to manage: because n8n's Discord trigger uses a shared IPC channel, only the last-activated adapter actually receives messages. The fix required a specific activation sequence (DM adapter first, guild adapter last with an 8-second delay) enforced by a watcher script.

Planning artifacts: [Phase 3 docs](phase-03/) | Workflows: [`03-01-identity-resolver.json`](../workflows/03-01-identity-resolver.json), [`03-03-discord-dm-adapter.json`](../workflows/03-03-discord-dm-adapter.json)

## Phase 4: Memory System

The memory system was the most architecturally complex phase. Three tiers work together: short-term verbatim context via a LangChain Postgres buffer (keyed by `person_id` for cross-platform continuity), long-term batch extraction with pgvector hybrid retrieval (combining semantic similarity, keyword matching, and recency scoring), and per-person profiles built by the Guardian workflow from extracted memories.

The Guardian workflow promotes high-confidence observations from a staging table (`userinfo`) to permanent profile entries (`core_claim`) using a confidence scoring formula that weighs self-assertions higher than third-party observations. The Profile API injects relevant profile context into every conversation, giving the assistant immediate awareness of who it is talking to.

Privacy filtering ensures DM memories never surface in guild conversations. Every memory is tagged with `source_platform` and `privacy_level` at write time, and the retrieval layer filters by privacy context.

Planning artifacts: [Phase 4 docs](phase-04/) | Workflows: [`04-02-memory-retrieval.json`](../workflows/04-02-memory-retrieval.json), [`04-02-memory-batch-extraction.json`](../workflows/04-02-memory-batch-extraction.json), [`04-03-guardian.json`](../workflows/04-03-guardian.json)

## Phase 5: Sub-Agents + Media

Phase 5 extended the assistant's capabilities beyond conversation. The Research sub-agent uses Tavily for web search with LLM synthesis to deliver researched answers in the assistant's voice. The Email sub-agent provides full Gmail integration -- reading, searching, sending, and a scheduled morning brief. The Media sub-agent handles image analysis via a vision API, PDF and DOCX text extraction, and YouTube transcript processing.

A key architectural decision was exposing sub-agents as tools to the Core Agent's LangChain AI Agent node. Each sub-agent is a separate n8n workflow invoked via `toolWorkflow` nodes, which required careful schema configuration -- an empty `schema: []` causes LangChain to collapse all tool inputs to a single `query` parameter, breaking the sub-agent's ability to receive structured data.

Planning artifacts: [Phase 5 docs](phase-05/) | Workflows: [`05-02-research-sub-agent.json`](../workflows/05-02-research-sub-agent.json), [`05-03-email-sub-agent.json`](../workflows/05-03-email-sub-agent.json), [`05-01-media-sub-agent.json`](../workflows/05-01-media-sub-agent.json)

## Phase 5.1: Memory Quality (Inserted)

After Phase 5 was complete, quality issues in the memory pipeline prompted an inserted phase. The extraction prompt was rewritten to produce human-like memories instead of dry factual notes. A critical bug was discovered: batch extraction was not grouping messages by `person_id`, causing all guild chat memories to be stored under every participant in the conversation.

Write-time deduplication was added using pgvector similarity checks, and an importance scoring system was introduced to filter ephemeral conversational noise. The high-water mark pattern (using n8n's `staticData` to persist a `lastProcessedAt` timestamp) eliminated reprocessing after workflow restarts -- though this required saving the raw Postgres timestamp string rather than converting through JavaScript's Date object, which truncates microsecond precision and causes infinite re-matching.

Planning artifacts: [Phase 5.1 docs](phase-05.1/)

## Phase 6: Polish + Hardening

The final phase brought the system to production readiness across five plans. An LLM-as-judge eval suite with 25 test cases established a quality baseline (3.88/5.0 initial score). The architecture was split so that the Core Agent became a lean 21-node router delegating to per-tier sub-workflows (Sonnet, Opus, Gemini), each containing its own AI Agent and 7 tools.

This split solved a critical n8n platform limitation: workflows with more than approximately 40 nodes and many LangChain tool connections cause the task runner to hang indefinitely on Code node execution. By isolating each tier into its own sub-workflow (~11 nodes each), every workflow stays well under the threshold.

A central error handler was deployed with `retryOnFail` on critical nodes, jailbreak detection guardrails with in-character deflection, and a debug trace pushed to a dedicated Discord channel after every response. The soul.md personality file was rewritten from scratch as a "Curious Sentinel" archetype with reactive behavioral rules derived from eval failures rather than prescriptive instructions.

Planning artifacts: [Phase 6 docs](phase-06/) | Workflows: [`06-05-sonnet-agent.json`](../workflows/06-05-sonnet-agent.json), [`06-05-opus-agent.json`](../workflows/06-05-opus-agent.json), [`06-03-central-error.json`](../workflows/06-03-central-error.json), [`06-01-eval-suite.json`](../workflows/06-01-eval-suite.json)

---

## Document Types

Each phase folder contains some or all of these document types:

- **`*-PLAN.md`** -- Implementation plan with specific tasks, acceptance criteria, and verification steps
- **`*-SUMMARY.md`** -- Post-implementation summary with accomplishments, key decisions, deviations from plan, and lessons learned
- **`*-CONTEXT.md`** -- Phase context document with domain boundaries, design decisions, and constraints
- **`*-RESEARCH.md`** -- Technology research and architectural exploration conducted before implementation

---

See the [project README](../README.md) for architecture overview, feature descriptions, and setup instructions.
