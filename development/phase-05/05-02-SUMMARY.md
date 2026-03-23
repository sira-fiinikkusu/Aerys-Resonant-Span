---
plan: 05-02
phase: 05-sub-agents-media
status: complete
completed: 2026-03-03
infra_commit: 293de9b
---

# 05-02 Research Sub-Agent — SUMMARY

## What Was Built

Research sub-agent workflow (ID: `YOUR_RESEARCH_SUBAGENT_WORKFLOW_ID`) that performs Tavily web search on demand and returns synthesized findings in Aerys's voice.

## Key Files

- `~/aerys/workflows/05-02-research-agent.json` — 6-node sub-workflow

## Workflow Structure

`Execute Workflow Trigger (passthrough)` → `Read Input` → `Tavily Search (HTTP Request)` → `Build Synthesis Request` → `Synthesize in Aerys Voice (OpenRouter)` → `Return Result`

## Decisions Made

- **Synthesis model:** `google/gemini-2.5-flash-lite` (plan specified haiku-4.5 — updated to current gemini tier)
- **Tavily auth:** HTTP Header Auth credential `YOUR_TAVILY_HEADER_CREDENTIAL_ID` ("Tavily API") — not $vars (enterprise-only)
- **Error handling:** `neverError: true` on Tavily call; Build Synthesis Request detects failure and adjusts LLM prompt to acknowledge the search problem gracefully
- **Built by orchestrator directly** (gsd-executor agents lack Bash/MCP access)

## Interface

Input fields: `query`, `person_id`, `original_message`, `source_channel`, `conversation_privacy`
Output fields: `result` (synthesized text in Aerys voice with sources), `query`

## DB Update

`sub_agents` table updated: `research_agent` → workflow_id `YOUR_RESEARCH_SUBAGENT_WORKFLOW_ID`

## Requirements Satisfied

- AI-03: Aerys performs web research on demand ✓
- Tavily search with Aerys voice synthesis ✓
- Sources listed in response ✓
- Graceful failure handling ✓
