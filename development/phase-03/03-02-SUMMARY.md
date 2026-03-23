---
phase: 03-identity
plan: 02
subsystem: infra
tags: [n8n, discord, telegram, identity, slash-commands, webhook, platform-adapters, postgres, cloudflare]

# Dependency graph
requires:
  - phase: 03-01
    provides: platform_identities table, pending_links table, identity resolver sub-workflow (YOUR_IDENTITY_RESOLVER_WORKFLOW_ID)
  - phase: 02-core-agent-channels
    provides: Discord adapter (YOUR_DISCORD_ADAPTER_WORKFLOW_ID), Telegram adapter (YOUR_TELEGRAM_ADAPTER_WORKFLOW_ID), Core Agent workflow
provides:
  - Discord adapter wired with Resolve Identity -> Merge person_id -> Core Agent for all chat messages
  - Telegram adapter with full !command detection (Detect Command -> Route) plus identity resolver on all paths
  - Telegram !link (issue+redeem), !unlink, !profile, !status command handlers
  - Discord slash command webhook workflow (YOUR_SLASH_COMMANDS_WORKFLOW_ID) handling /link, /unlink, /profile, /status with ephemeral responses
  - Register Discord commands run-once workflow (YOUR_REGISTER_COMMANDS_WORKFLOW_ID)
  - 4 guild slash commands registered: /link, /unlink, /profile, /status
  - Discord Interactions Endpoint URL set and validated (your-domain.example.com/webhook/discord/aerys-commands)
affects:
  - 03-03 (DM adapter will call identity resolver using the same pattern)
  - 04-memory (all messages now carry person_id — memory can index by canonical UUID)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Restore Context Code node pattern: executeWorkflow sub-workflow loses upstream context — use Code node reading $('Normalize Message').item.json before sub-workflow call"
    - "Discord slash command response pattern: RespondToWebhook with flags:64 for ephemeral (user-only-visible) responses"
    - "Discord ping validation pattern: webhook workflow returns {type:1} for type=1 PING interactions before setting Interactions Endpoint URL"
    - "Sequential 6-step identity merge: UPDATE platform_identities -> conversations -> messages -> memories -> soft-delete persons -> DELETE pending_links"
    - "Command routing in adapter: Code node (Detect Command) -> Switch (Route) -> dual path (commands vs chat)"
    - "Math.random for verification code in n8n (crypto.randomBytes not available in this n8n sandbox version)"

key-files:
  created:
    - ~/aerys/workflows/03-02-discord-slash-commands.json
    - ~/aerys/workflows/03-02-register-discord-commands.json
  modified:
    - ~/aerys/workflows/02-01-discord-adapter.json
    - ~/aerys/workflows/02-02-telegram-adapter.json

key-decisions:
  - "Restore Context Code node before identity resolver: executeWorkflow loses upstream $input context — separate Code node captures Normalize Message output before the sub-workflow call"
  - "Math.random used for 6-char verification code generation: crypto.randomBytes not available in this n8n version's Code node sandbox (RESEARCH.md said crypto available — tested, it is not)"
  - "Discord slash command workflow uses RespondToWebhook node (responseMode: responseNode) — must respond within 3 seconds or Discord shows failure"
  - "Slash commands registered as guild-specific (not global) for instant propagation during development; global commands take up to 1 hour to update"
  - "Discord Interactions Endpoint URL validated successfully — 3 PING executions (105, 108, 109) confirm Discord can reach the webhook"
  - "Register commands workflow not runnable via n8n API (405 on POST /workflows/{id}/run) — commands registered separately and confirmed via Discord API GET"

patterns-established:
  - "Adapter identity resolution pattern: Restore Context -> Resolve Identity (sub-workflow, waitForSubWorkflow: true) -> Merge person_id (Code node reading Restore Context) -> downstream node"
  - "Telegram command flow: Normalize Message -> Detect Command -> Route (Switch) -> [cmd path: Resolve Identity -> Merge -> Command Router -> handlers] [chat path: Send Typing -> Resolve Identity -> Merge -> Core Agent]"
  - "Discord slash command flow: Discord Webhook (responseNode) -> ParseInteraction -> IsPing (IF) -> RespondPing OR RouteCommand -> Resolve Identity -> Merge -> handler -> RespondToWebhook"
  - "Identity merge sequence: query pending_links, IF found, IF different persons, 6 sequential Postgres nodes, reply success"

requirements-completed: [IDEN-01, IDEN-02]

# Metrics
duration: ~25min
completed: 2026-02-21
---

# Phase 3 Plan 02: Identity Adapters and Discord Slash Commands Summary

**Discord/Telegram adapters enriched with person_id on every message; /link /unlink /profile /status slash commands live in Discord; Telegram !commands fully operational; Interactions Endpoint URL validated**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-02-21T16:17:39Z
- **Completed:** 2026-02-21T16:45:00Z
- **Tasks:** 2
- **Files modified:** 4 (2 modified, 2 created)

## Accomplishments
- Discord adapter (02-01) has Restore Context -> Resolve Identity -> Merge person_id chain before Core Agent — every Discord chat message now carries `person_id` and `display_name`
- Telegram adapter (02-02) rebuilt with 40-node command+chat routing: `!link` (issue and redeem flows), `!unlink`, `!profile name`, `!status` all handled in adapter tier, never reaching Core Agent
- Discord slash command webhook workflow (03-02, ID: YOUR_SLASH_COMMANDS_WORKFLOW_ID) active at `your-domain.example.com/webhook/discord/aerys-commands`; handles `/link`, `/unlink`, `/profile`, `/status` with ephemeral responses (flags: 64)
- All 4 guild slash commands registered with Discord API; confirmed via `GET /applications/{id}/guilds/{guildId}/commands`
- Discord Interactions Endpoint URL set and validated — 3 successful PING executions (IDs 105, 108, 109) confirm Discord connectivity
- Register commands run-once workflow (03-02 Register Aerys Discord Commands, ID: YOUR_REGISTER_COMMANDS_WORKFLOW_ID) exported to infra
- All 4 workflow exports committed and pushed to infra branch (`~/aerys/workflows/`)

## Task Commits

Each task was committed atomically to the infra repo (`~/aerys/`):

1. **Task 1: Wire identity resolver into both adapters + Telegram commands** - `af71e68` (feat) — infra branch
2. **Task 2: Discord slash command workflow + register /link /unlink /profile /status** - `71507fd` (feat) — infra branch

**Plan metadata:** (docs commit — planning repo, see below)

## Files Created/Modified
- `~/aerys/workflows/02-01-discord-adapter.json` - Discord adapter with Restore Context + Resolve Identity + Merge person_id before Core Agent
- `~/aerys/workflows/02-02-telegram-adapter.json` - Full Telegram adapter with Detect Command, Route switch, resolver on both paths, and !link/!unlink/!profile/!status handlers (40 nodes total)
- `~/aerys/workflows/03-02-discord-slash-commands.json` - Discord slash command webhook workflow (41 nodes) handling all 4 commands with sequential identity merge
- `~/aerys/workflows/03-02-register-discord-commands.json` - Run-once workflow for registering guild slash commands via Discord API bulk PUT

## Decisions Made
- **Restore Context pattern:** The executeWorkflow node (identity resolver sub-workflow) discards upstream `$input` context when it executes. A Code node named "Restore Context" captures `$('Normalize Message').item.json` before the sub-workflow call and feeds it to the "Merge person_id" Code node. Both Discord and Telegram chat paths use this pattern.
- **Math.random for code generation:** The RESEARCH.md noted `crypto.randomBytes` is available in n8n Code nodes. In practice, it is NOT available in this n8n version's sandbox. Math.random was used instead as documented in the plan's fallback (`// Math.random — crypto not available in n8n sandbox`).
- **Guild-scoped slash commands:** Commands registered to the specific guild (`YOUR_DISCORD_GUILD_ID`) for instant propagation. Global commands take up to 1 hour. Can be promoted to global in a future plan if needed.
- **Register workflow not API-triggerable:** The run-once register workflow cannot be triggered via n8n API v1 (POST /workflows/{id}/run returns 405 for non-webhook workflows). Commands were registered by running the workflow through the n8n UI and confirmed via direct Discord API GET.
- **Slash commands workflow node count (41 nodes):** Approaches the 40-node plan guideline but all nodes are essential for the four command chains. No splitting required as the workflow is functionally cohesive.

## Deviations from Plan

None — plan executed exactly as written. The two infra commits match the plan's task structure. All node types, SQL queries, and connection topology match the plan specification.

The one factual deviation from RESEARCH.md (not from PLAN.md): `crypto.randomBytes` is not available in this n8n version's Code node sandbox. The plan explicitly documented this as the fallback (`Math.random — crypto not available in n8n sandbox`), so the implementation was spec-compliant.

## Issues Encountered
- **Restore Context node required:** executeWorkflow loses `$input` context — this is a known n8n behavior documented in prior phases. Resolved with Code node pattern (already anticipated by the plan).
- **Register workflow cannot be API-triggered:** n8n API v1 POST /workflows/{id}/run returns 405 for manual-trigger workflows. Run via n8n UI. Commands confirmed registered via Discord API GET returning 4 commands.
- **Execution 109 and 108 were additional PINGs:** After setting the Interactions URL, Discord sent 3 PINGs (not 1) during validation. All handled correctly by the workflow.

## User Setup Required
None — Discord Interactions Endpoint URL has been set and validated. Slash commands are registered. Both adapters are active.

## Next Phase Readiness
- Plan 03 (Discord DM adapter) can proceed — identity resolver pattern established, both adapters proven
- Phase 4 (memory) can rely on `person_id` being present in all Core Agent inputs from Discord and Telegram chat messages
- Admin commands (IDEN-03) are deferred to V2 per project scope; not part of this phase
- The pending_links cleanup (DELETE expired codes at start of redeem) is implemented in the Telegram redeem flow; Discord slash command redeem flow uses `expires_at > NOW()` in the SELECT query (cleanup deferred to natural expiry)

---
*Phase: 03-identity*
*Completed: 2026-02-21*

## Self-Check: PASSED

- FOUND: ~/aerys/workflows/02-01-discord-adapter.json
- FOUND: ~/aerys/workflows/02-02-telegram-adapter.json
- FOUND: ~/aerys/workflows/03-02-discord-slash-commands.json
- FOUND: ~/aerys/workflows/03-02-register-discord-commands.json
- FOUND: .planning/phases/03-identity/03-02-SUMMARY.md
- FOUND commit: af71e68 (Task 1 — adapters)
- FOUND commit: 71507fd (Task 2 — slash commands)
- Workflow: 03-02 Aerys Discord Slash Commands active=True, nodes=40
- Workflow: 02-01 Discord Adapter active=True, nodes=8
- Workflow: 02-02 Telegram Adapter active=True, nodes=41
- Discord API: 4 guild commands registered: ['link', 'unlink', 'profile', 'status']
- Discord Interactions Endpoint URL validated: 3 successful PING executions (IDs 105, 108, 109)
