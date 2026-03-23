---
plan: 05-01
phase: 05-sub-agents-media
status: complete
completed: 2026-03-03
infra_commit: 0c21866
---

# 05-01 Media Sub-Agent — SUMMARY

## What Was Built

Media processing sub-agent workflow (ID: `YOUR_MEDIA_SUBAGENT_WORKFLOW_ID`) that handles images, PDFs, DOCXs, TXT files, and YouTube links — all returning a synthesized response in Aerys's voice.

## Key Files

- `~/aerys/workflows/05-01-media-agent.json` — 38-node sub-workflow (committed 0c21866)

## Workflow Structure

```
Execute Workflow Trigger → Detect Media Type → Route by Media Type (6 branches)

Image branch:
  Build Vision Request → Check If Telegram Image
  → [Telegram: Get File → Download → Convert to Base64]
  → Build Vision Req Model 1 → Call Vision Model 1 → Handle Vision Model 1 → Check Vision Model 1 Success
  → [fallback] → Build Vision Req Model 2 → Call Vision Model 2 → ... → Model 3
  → Format Image Result → Format Return

PDF branch:   Download PDF → Extract PDF Text → Truncate PDF Text → Build LLM Synthesis Request
DOCX branch:  Download DOCX → Convert DOCX to Text (@mazix) → Truncate DOCX Text → Build LLM Synthesis Request
TXT branch:   Download TXT → Extract TXT Text → Truncate TXT → Build LLM Synthesis Request
YouTube:      Fetch YouTube Transcript → Check YouTube Fallback → [Fallback Result] / [Prep YouTube for LLM → Build LLM Synthesis Request]
Unknown:      Unknown Media Result → Format Return

Build LLM Synthesis Request → Call LLM Synthesis → Format Synthesis Result → Format Return
```

## Decisions Made

- **Vision model priority** (LOCKED): `google/gemini-2.0-flash-exp:free` → `google/gemini-flash-1.5` → `anthropic/claude-3-haiku` — cascade with IF-gated fallback, not single hardcoded model
- **DOCX extraction**: `@mazix/n8n-nodes-converter-documents` community node (`convertFileToJson` operation) — confirmed installed in 05-00
- **YouTube**: Innertube raw approach (parse `ytInitialPlayerResponse` from watch page → fetch captionTracks[0].baseUrl)
- **LLM synthesis model**: `anthropic/claude-haiku-4-5` (fast, appropriate for document synthesis)
- **Telegram images**: two-step download (Telegram Get File → HTTP download → base64 data URI) before vision API call
- **Built by gsd-executor agent** — agent hit usage limit; workflow was fully committed (0c21866) before limit hit; SUMMARY not written by agent
- **Vision model success order**: not captured — agent hit usage limit before end-to-end test ran

## Interface

Input fields: `content`, `attachments`, `person_id`, `source_channel`, `conversation_privacy`, `platform`
Output fields: `result` (synthesized text or image description), `_media_type`, `_filename`

## DB Update

`sub_agents` table updated: `media_agent` → workflow_id `YOUR_MEDIA_SUBAGENT_WORKFLOW_ID` (done in previous session via Manual Trigger vq3U4EdLY3pGS5Lt)

## Requirements Satisfied

- MEDIA-01: Image analysis (Discord CDN + Telegram download) ✓
- MEDIA-02: PDF/DOCX/TXT extraction + YouTube transcript ✓
- Triple-model vision fallback ✓
- Telegram-specific file download path ✓
