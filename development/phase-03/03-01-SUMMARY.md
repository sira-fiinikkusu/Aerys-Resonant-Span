---
phase: 03-identity
plan: 01
subsystem: infra
tags: [cloudflare, cloudflared, tunnel, postgres, identity, platform-identities, n8n, sub-workflow]

# Dependency graph
requires:
  - phase: 02-core-agent-channels
    provides: persons table, aerys DB schema, n8n workflows (adapters + core agent)
provides:
  - Cloudflare Tunnel routing your-domain.example.com to n8n localhost:5678
  - platform_identities table: cross-platform person identity store with UNIQUE(platform, platform_user_id)
  - pending_links table: short-lived verification code store for account linking
  - 03-01 Identity Resolver sub-workflow (ID: YOUR_IDENTITY_RESOLVER_WORKFLOW_ID): returns person_id, display_name, is_new
affects:
  - 03-02 (slash commands workflow calls identity resolver)
  - 03-03 (DM adapter calls identity resolver)
  - 04-memory (person_id is the primary key for all memory associations)

# Tech tracking
tech-stack:
  added: [cloudflared 2026.2.0 (arm64 systemd service)]
  patterns:
    - Execute Sub-workflow Trigger pattern for shared identity resolution
    - ON CONFLICT DO NOTHING for idempotent platform identity creation
    - Postgres parameterized queries via queryReplacement option in n8n postgres node

key-files:
  created:
    - ~/aerys/config/cloudflare/config.yml
    - ~/aerys/migrations/002_identity.sql
    - ~/aerys/workflows/03-01-identity-resolver.json
  modified: []

key-decisions:
  - "cloudflared already installed (2026.2.0) and tunnel 'aerys' already created and running — no reinstall needed"
  - "Credentials file lives at /home/particle/.cloudflared/{UUID}.json (not /root/.cloudflared/) — running as particle not root"
  - "n8n postgres node typeVersion 2.5 uses 'queryReplacement' option for parameterized queries (not a top-level queryParams field)"
  - "Identity resolver uses Execute Sub-workflow Trigger (inputSource: passthrough) — callers pass platform, platform_user_id, username directly"
  - "ON CONFLICT DO NOTHING on platform_identities insert handles race conditions on concurrent first messages"

patterns-established:
  - "Sub-workflow pattern: Execute Sub-workflow Trigger -> processing nodes -> Set node return — callers use executeWorkflow node with workflow ID"
  - "Identity resolution flow: Cleanup expired codes -> Lookup -> Check Found (IF) -> Return Existing OR Create Person + Create Platform Identity -> Return New"
  - "Parameterized Postgres queries in n8n: set query with $1, $2 etc., provide queryReplacement as expression array in options"

requirements-completed: [IDEN-01, IDEN-02]

# Metrics
duration: 5min
completed: 2026-02-21
---

# Phase 3 Plan 01: Identity Foundation Summary

**Cloudflare Tunnel live (your-domain.example.com -> n8n), platform_identities + pending_links tables migrated, identity resolver sub-workflow active returning person_id/is_new**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-21T15:59:59Z
- **Completed:** 2026-02-21T16:05:15Z
- **Tasks:** 3
- **Files modified:** 3 (all new: config.yml, 002_identity.sql, 03-01-identity-resolver.json)

## Accomplishments
- Cloudflare Tunnel `aerys` (ID: 82fcc163) confirmed running as systemd service; your-domain.example.com returns HTTP 200 and resolves to Cloudflare edge IPs
- DB migration 002_identity.sql applied: platform_identities with UNIQUE(platform, platform_user_id) + FK to persons, pending_links with expiry support, 4 indexes total
- Identity Resolver sub-workflow (03-01, ID: YOUR_IDENTITY_RESOLVER_WORKFLOW_ID) active in n8n: 8-node chain that cleans expired codes, looks up or creates person+identity, returns person_id/display_name/is_new
- All three artifacts committed and pushed to infra branch (~/aerys/)

## Task Commits

Each task was committed atomically to the infra repo (`~/aerys/`):

1. **Task 1: Cloudflare Tunnel config** - `5d0a345` (feat) — infra branch
2. **Task 2: DB migration 002_identity.sql** - `e6712cd` (feat) — infra branch
3. **Task 3: Identity resolver sub-workflow** - `a3b02b5` (feat) — infra branch

**Plan metadata:** (docs commit — planning repo, see below)

## Files Created/Modified
- `~/aerys/config/cloudflare/config.yml` - Cloudflare Tunnel config routing your-domain.example.com to localhost:5678
- `~/aerys/migrations/002_identity.sql` - DDL for platform_identities and pending_links tables
- `~/aerys/workflows/03-01-identity-resolver.json` - n8n identity resolver sub-workflow export

## Decisions Made
- **cloudflared already installed and running:** Version 2026.2.0 was pre-installed, tunnel `aerys` already created and active. All Steps 1-6 from the plan were already complete. Proceeded directly to verification and config export.
- **Credentials file location:** Lives at `/home/particle/.cloudflared/{UUID}.json` (running as `particle` user, not `root`). Config at `/etc/cloudflared/config.yml` uses this path correctly.
- **n8n postgres queryReplacement:** The n8n postgres node v2.5 uses `options.queryReplacement` (not a top-level field) to pass parameterized query arguments as an expression array. Confirmed from existing workflow introspection.
- **Workflow testing via DB:** n8n API v1 doesn't support manual execution of non-webhook workflows via API. SQL logic verified directly against the database; workflow structure verified via API GET.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed as written. cloudflared tunnel was pre-configured from planning phase, which accelerated Task 1.

### Scope Difference
The plan's Task 1 Steps 1-6 (install cloudflared, login, create tunnel, write config, create DNS, install systemd service) were already complete from prior setup. Execution began at Step 7 (verification) and Step 9 (commit to infra). This is not a deviation — it reflects the planning system correctly discovering existing infrastructure state.

## Issues Encountered
- **n8n API manual execution:** POST /workflows/{id}/run returns "method not allowed" — the n8n v1 API does not support triggering manual-trigger or scheduled workflows via API. Tested sub-workflow SQL logic directly against the DB and verified workflow structure via GET. Discord Interactions Endpoint URL setting deferred to Plan 02 Task 2 as documented in the plan.

## User Setup Required
- **Discord Interactions Endpoint URL** must be set after Plan 02 (slash commands workflow) is active. URL: `https://your-domain.example.com/webhook/discord/aerys-commands`. Instructions in plan Task 1 Step 8.

## Next Phase Readiness
- Plan 02 (slash commands workflow) and Plan 03 (DM adapter) can now proceed — all prerequisites satisfied
- Both adapters should call identity resolver via executeWorkflow node with ID `YOUR_IDENTITY_RESOLVER_WORKFLOW_ID`
- Discord Interactions Endpoint URL validation requires Plan 02 slash command webhook to be active first

---
*Phase: 03-identity*
*Completed: 2026-02-21*

## Self-Check: PASSED

- FOUND: ~/aerys/config/cloudflare/config.yml
- FOUND: ~/aerys/migrations/002_identity.sql
- FOUND: ~/aerys/workflows/03-01-identity-resolver.json
- FOUND: .planning/phases/03-identity/03-01-SUMMARY.md
- FOUND commit: 5d0a345 (cloudflare tunnel config)
- FOUND commit: e6712cd (DB migration)
- FOUND commit: a3b02b5 (identity resolver workflow)
- DB: 2 tables present (platform_identities, pending_links)
- Workflow: active=True, name=03-01 Identity Resolver
