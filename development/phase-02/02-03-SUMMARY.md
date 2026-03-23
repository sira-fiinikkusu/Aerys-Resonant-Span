---
phase: 02-core-agent-channels
plan: 03
status: complete
completed: 2026-02-20
duration: ~90 min (across two sessions)
---

# Summary: Plan 02-03 — Polisher + Channel Dispatch

## What Was Built

The complete output pipeline for Aerys: a dedicated output router workflow (02-04) that takes the core agent's response and delivers it to the correct platform. All four workflows are now active and the message loop — from user input to AI response to channel delivery — is fully closed.

**Workflows active:**
- `02-01-discord-adapter` (YOUR_DISCORD_ADAPTER_WORKFLOW_ID) — Discord trigger, message normalization
- `02-02-telegram-adapter` (YOUR_TELEGRAM_ADAPTER_WORKFLOW_ID) — Telegram trigger, message normalization
- `02-03-core-agent` (YOUR_CORE_AGENT_WORKFLOW_ID) — Intent classify, model route, AI reason, Prepare Response
- `02-04-output-router` (YOUR_OUTPUT_ROUTER_WORKFLOW_ID) — Polisher gate, formatter, splitter, channel dispatch

## What Works

- Discord: trigger fires on guild @mentions, core agent responds, output router delivers to correct channel
- Telegram: trigger fires on private messages, core agent responds, output router delivers to correct chat
- Personality consistent across both channels (Aerys sounds like the same character)
- Platform-specific formatting: Discord markdown passes through; Telegram converts to HTML with `<b>`, `<i>`, `<pre><code>` tags
- Code blocks render correctly on both platforms
- Polisher gate conditionally routes long or tone-broken responses through Haiku polish pass
- Message splitter handles responses exceeding platform character limits (Discord 2000, Telegram 4096)
- Conversation memory persists within session (Postgres Chat Memory)
- Attribution watermark removed from Telegram messages (`appendAttribution: false`)

## Bugs Fixed During Execution

- **Discord adapter activation race** — katerlol bot.js has IPC startup instability; deactivate/reactivate via n8n API after each restart resolves. Workaround documented as operational procedure.
- **Discord send empty message (50006)** — `Build Discord Body` produces a JSON string; `Send Discord Message` was using `contentType: json` which double-encoded it. Fixed: `contentType: raw` + `rawContentType: application/json`.
- **Telegram HTML parse error (code blocks)** — `toTelegramHtml` was wrapping unescaped code in `<pre><code>`. Fixed with extract-escape-reassemble pattern: extract code blocks first, escape `<`, `>`, `&` inside them, then reassemble.
- **Platform Formatter regex syntax error** — inject-via-API introduced a stray `\` before `!` in lookbehind/lookahead (`(?<\!\*)` instead of `(?<!\*)`). Fixed by writing JS to temp file, reading back via Python, and PUTting with correct JSON encoding.
- **bot.js debug patch reverted** — temporary `console.log('DEBUG: clientId=...')` removed; n8n restarted clean.

## Key Decisions Made

- `contentType: raw` + `rawContentType: application/json` is the correct approach for Discord HTTP send when body is a pre-built JSON string
- Platform Formatter must escape HTML entities inside code blocks BEFORE wrapping in `<pre><code>` — extract, escape, reassemble
- Telegram's n8n node `appendAttribution: false` removes the n8n watermark
- katerlol Discord trigger race is a startup condition only — manual reactivate via API after boot is sufficient; no deeper fix needed for v1

## Artifacts

- `~/aerys/workflows/02-01-discord-adapter.json` — exported post-completion
- `~/aerys/workflows/02-02-telegram-adapter.json` — exported post-completion
- `~/aerys/workflows/02-03-core-agent.json` — exported post-completion
- `~/aerys/workflows/02-04-output-router.json` — exported post-completion

## Checkpoint Result

**Approved** — Both Discord and Telegram confirmed responding end-to-end with correct formatting and consistent Aerys personality.

## Phase 2 Complete

All three plans executed and verified. Aerys is alive on Discord and Telegram.
