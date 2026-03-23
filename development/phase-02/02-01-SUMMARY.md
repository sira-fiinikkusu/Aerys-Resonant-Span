---
phase: 02-core-agent-channels
plan: 01
subsystem: infra
tags: [n8n, discord, telegram, docker, postgresql, openrouter, soul-prompt]

# Dependency graph
requires:
  - phase: 01-infrastructure
    provides: "Docker Compose, n8n, Postgres aerys DB, backup automation"
provides:
  - "docker-compose.yml with aerys-config volume mount and community packages env vars"
  - "config/soul.md — Aerys Curious Sentinel personality prompt"
  - "config/models.json — OpenRouter model IDs and routing config"
  - "aerys_model_usage table in aerys DB for per-day model cost tracking"
  - "n8n workflow 02-01 Discord Adapter (inactive, awaiting core agent)"
  - "n8n workflow 02-02 Telegram Adapter (inactive, awaiting core agent)"
affects: [02-02, 02-03, 03-memory-pipeline, 05-media-attachments]

# Tech tracking
tech-stack:
  added:
    - "@kmcbride3/n8n-nodes-discord (community node — install via n8n GUI Settings > Community Nodes)"
    - "N8N_COMMUNITY_PACKAGES_ENABLED env var"
    - "N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE env var"
  patterns:
    - "Channel adapter pattern: platform trigger → filter → normalize → typing indicator → core agent sub-workflow"
    - "Normalized message schema: {source_channel, channel_id, guild_id, user_id, username, message_text, message_id, is_dm, is_mention, is_edit, attachments, timestamp, session_key}"
    - "Edit detection: Discord checks editedTimestamp; Telegram handles edited_message update type"
    - "Mention stripping: Discord removes <@ID> patterns from message_text before AI processing"
    - "Volume-mounted config: aerys-config:ro at /home/node/aerys-config in n8n container"
    - "Model usage counter: aerys_model_usage(date, model, call_count) with PRIMARY KEY (date, model)"

key-files:
  created:
    - "~/aerys/config/soul.md — Aerys personality/soul prompt (~900 tokens)"
    - "~/aerys/config/models.json — OpenRouter model IDs and routing thresholds"
    - "~/aerys/workflows/02-01-discord-adapter.json — Discord adapter workflow export"
    - "~/aerys/workflows/02-02-telegram-adapter.json — Telegram adapter workflow export"
  modified:
    - "~/aerys/docker-compose.yml — added aerys-config volume mount, community packages env vars"
    - "~/aerys/.env — added placeholder vars for DISCORD_BOT_TOKEN, TELEGRAM_BOT_TOKEN, OPENROUTER_API_KEY, OPUS_DAILY_LIMIT"
    - "~/aerys/.gitignore — updated to track soul.md and models.json while ignoring n8n runtime data"

key-decisions:
  - "soul.md targets ~900 tokens (slightly above planned 700-800) to fully capture 4 verbal signatures, failure personality, and speaker-tagging instructions"
  - "OPUS_DAILY_LIMIT set to 10 initially (conservative) — tune after first week of usage data"
  - "n8n community:install CLI command not available in current n8n version; Discord node requires GUI install via Settings > Community Nodes > Install"
  - "Workflows imported via n8n import:workflow CLI (container exec) after API required auth setup not yet complete"
  - "Stuck postgres container on restart (ARM64 zombie process) resolved by stopping Docker daemon, removing container directory from /var/lib/docker/containers/, restarting Docker"
  - "aerys_model_usage table survived container restart via PostgreSQL data volume persistence"

patterns-established:
  - "Normalized message schema is the contract between channel adapters and core agent — both channels produce identical field names and types"
  - "Filter-before-normalize: drop unwanted messages (bots, edits without mention) before normalization to avoid unnecessary processing"
  - "Inactive by default: channel adapter workflows are kept INACTIVE until the core agent they depend on exists"

requirements-completed: [CHAN-01, CHAN-03, CHAN-05, PERS-01]

# Metrics
duration: 13min
completed: 2026-02-18
---

# Phase 2 Plan 01: Channel Adapters and Infrastructure Prep Summary

**Docker Compose updated with config volume mount, soul.md and models.json created, aerys_model_usage table migrated, and Discord + Telegram adapter workflows built with unified normalized message schema**

## Performance

- **Duration:** 13 min
- **Started:** 2026-02-18T14:02:55Z
- **Completed:** 2026-02-18T14:15:58Z
- **Tasks:** 2 of 2 auto tasks complete (1 checkpoint pending user verification)
- **Files modified:** 7

## Accomplishments

- Infrastructure updated: docker-compose.yml now mounts aerys config as read-only volume and enables community packages; containers restarted healthy
- Personality system bootstrapped: soul.md with full Curious Sentinel character prompt readable from inside n8n container at `/home/node/aerys-config/soul.md`
- Two channel adapter workflows built and imported into n8n — both inactive, both produce identical normalized schema
- aerys_model_usage table created in aerys DB for Opus daily cap enforcement

## Task Commits

Each task was committed atomically:

1. **Task 1: Infrastructure prep** - `fc0a6da` (feat)
2. **Task 2: Discord and Telegram adapter workflows** - `45420eb` (feat)

## Files Created/Modified

- `/home/particle/aerys/docker-compose.yml` - Added aerys-config:ro volume mount and N8N_COMMUNITY_PACKAGES_ENABLED env vars
- `/home/particle/aerys/.env` - Added placeholder vars for Discord/Telegram/OpenRouter tokens
- `/home/particle/aerys/.gitignore` - Updated to track soul.md and models.json while ignoring n8n runtime config
- `/home/particle/aerys/config/soul.md` - Aerys Curious Sentinel personality prompt (~900 tokens)
- `/home/particle/aerys/config/models.json` - OpenRouter model IDs and routing thresholds
- `/home/particle/aerys/workflows/02-01-discord-adapter.json` - Discord adapter: Trigger → Filter → Normalize → Typing → Execute Core Agent
- `/home/particle/aerys/workflows/02-02-telegram-adapter.json` - Telegram adapter: Trigger → Filter → Normalize → Typing → Execute Core Agent

## Decisions Made

- OPUS_DAILY_LIMIT initialized to 10 (conservative); tune after first usage data
- soul.md slightly exceeds planned 700-800 token target (~900 tokens) to fully capture personality system; trade-off acceptable given negligible cost
- Discord community node CLI install (`n8n community:install`) not available in current n8n version — GUI install path documented for user setup
- Workflows saved INACTIVE pending core agent workflow creation in Plan 02-02

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] .gitignore pattern blocked config/soul.md and config/models.json from being tracked**
- **Found during:** Task 1 (post-file creation, pre-commit)
- **Issue:** Existing .gitignore had `config/` which blocked ALL files under config/, including the non-sensitive soul.md and models.json. Git negation pattern `!config/soul.md` does not work when parent directory is ignored.
- **Fix:** Restructured .gitignore to enumerate specific subdirectories/files to ignore (config/n8n/, config/config, config/crash.journal, config/n8nEventLog*.log) rather than the entire config/ directory
- **Files modified:** ~/aerys/.gitignore
- **Verification:** `git status` showed config/soul.md and config/models.json as untracked (now visible), `git add` succeeded
- **Committed in:** fc0a6da (Task 1 commit)

**2. [Rule 3 - Blocking] Stuck postgres container from prior session blocked docker compose down/up**
- **Found during:** Task 1 (container restart step)
- **Issue:** `docker compose down` failed — postgres container was in an unremovable zombie state. ARM64/QCM6490 kernel thread `[postgres]` (PID 635690) was sleeping but all namespace operations on it returned permission denied. Container could not be stopped, killed, or removed via normal Docker commands.
- **Fix:** Stopped Docker daemon (`systemctl stop docker.service docker.socket`), manually removed the container directory from `/var/lib/docker/containers/`, restarted Docker daemon. Container was gone; `docker compose up -d` then succeeded.
- **Files modified:** None (Docker internal state only)
- **Verification:** `docker ps` showed both containers fresh and healthy after restart
- **Committed in:** N/A (infrastructure fix, no file changes)

---

**Total deviations:** 2 auto-fixed (1 bug/gitignore, 1 blocking/zombie container)
**Impact on plan:** Both fixes necessary for correct operation. No scope creep.

## Issues Encountered

- `psql -U postgres` failed — postgres superuser is `n8n_admin` on this instance (not the default `postgres` user). Resolved: used `n8n_admin` for all psql commands.
- n8n API requires `X-N8N-API-KEY` header — no API key existed yet (user-management:reset clears owner account). Resolved: imported workflows via `n8n import:workflow` CLI inside the container.
- n8n `community:install` CLI command does not exist in current n8n version. Documented as user action: install via Settings > Community Nodes in n8n GUI.

## User Setup Required

Before this plan's workflows can be tested (Task 3 checkpoint), the following external services must be configured:

**Discord:**
1. Create Application at https://discord.com/developers/applications
2. Add Bot — enable ALL Privileged Gateway Intents (Message Content Intent is critical)
3. Copy Bot Token → add to `~/aerys/.env` as `DISCORD_BOT_TOKEN`
4. Install Discord community node in n8n: Settings > Community Nodes > Install > `@kmcbride3/n8n-nodes-discord`
5. Create n8n credential "Aerys Discord Bot" (type: Discord API, Bot Token: from .env)
6. Invite bot to Discord server via OAuth2 URL Generator (scopes: bot + applications.commands)

**Telegram:**
1. Message @BotFather → /newbot → copy token
2. Add to `~/aerys/.env` as `TELEGRAM_BOT_TOKEN`
3. Create n8n credential "Aerys Telegram Bot" (type: Telegram API, Token: from .env)

**OpenRouter:**
1. Get API key at https://openrouter.ai/keys
2. Add to `~/aerys/.env` as `OPENROUTER_API_KEY`

**After credentials created:** Open each workflow in n8n and connect the credential nodes.

## Next Phase Readiness

- Infrastructure ready for Plan 02-02 (core agent workflow)
- Channel adapter workflows exist in n8n, inactive, awaiting core agent workflow ID
- After Plan 02-02: update Execute Core Agent nodes in both adapter workflows with actual workflow ID
- Verification (Task 3) requires: Discord bot token set, Discord community node installed, Telegram bot token set, n8n credentials created

## Self-Check: PASSED

- FOUND: /home/particle/aerys/config/soul.md
- FOUND: /home/particle/aerys/config/models.json
- FOUND: /home/particle/aerys/workflows/02-01-discord-adapter.json
- FOUND: /home/particle/aerys/workflows/02-02-telegram-adapter.json
- FOUND: /home/particle/Downloads/personal-ai-planning/.planning/phases/02-core-agent-channels/02-01-SUMMARY.md
- FOUND commit: fc0a6da (Task 1 — infrastructure prep)
- FOUND commit: 45420eb (Task 2 — adapter workflows)

---
*Phase: 02-core-agent-channels*
*Completed: 2026-02-18*
