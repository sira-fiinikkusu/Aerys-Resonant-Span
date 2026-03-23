---
phase: 01-infrastructure
plan: 02
subsystem: infra
tags: [postgres, n8n, backup, systemd, docker]

# Dependency graph
requires:
  - phase: 01-01
    provides: PostgreSQL 16 + pgvector + n8n running in Docker Compose with aerys schema
provides:
  - Data persistence verified through full docker compose down/up cycle
  - Automated daily backup script at ~/aerys/backup.sh (pg_dump, gzip, 7-day retention)
  - systemd user timer aerys-backup.timer firing daily at 3 AM
  - Backup files in ~/aerys/backups/ (local fallback; NAS not detected)
  - n8n 2.x owner account created and free community license activated
  - N8N_SECURE_COOKIE=false set in .env for HTTP LAN access
  - Phase 1 infrastructure fully operational and user-verified
affects: [02-channels, 03-memory, 04-ai-agents, 05-integrations, 06-polish]

# Tech tracking
tech-stack:
  added: [systemd user timers]
  patterns:
    - crontab unavailable on Tachyon/QCM6490; use systemd user timers (OnCalendar) instead
    - N8N_BASIC_AUTH_* removed in n8n 2.x; owner account created via built-in UI setup wizard
    - N8N_SECURE_COOKIE=false required for n8n behind plain HTTP on LAN (no TLS)

key-files:
  created:
    - ~/aerys/backup.sh
    - ~/.config/systemd/user/aerys-backup.service
    - ~/.config/systemd/user/aerys-backup.timer
  modified:
    - ~/aerys/.env (added N8N_SECURE_COOKIE=false)
    - ~/aerys/docker-compose.yml (removed N8N_BASIC_AUTH_* env vars)

key-decisions:
  - "NAS not detected: backup defaults to ~/aerys/backups/ local fallback; BACKUP_DIR env var allows override when NAS becomes available"
  - "crontab unavailable on Tachyon QCM6490: switched to systemd user timer (aerys-backup.timer) with OnCalendar=*-*-* 03:00:00"
  - "N8N_BASIC_AUTH_* deprecated and removed in n8n 2.x: owner account created via built-in wizard; removed dead env vars from docker-compose.yml"
  - "N8N_SECURE_COOKIE=false required for HTTP LAN access: n8n 2.x enforces secure cookies by default, breaking login over plain HTTP"
  - "Tachyon LAN IP is localhost (not localhost from earlier notes)"

patterns-established:
  - "Pattern 4: Use systemd --user timers instead of crontab on Tachyon; crontab binary unavailable in this environment"
  - "Pattern 5: n8n 2.x uses built-in owner account setup (first-run wizard); N8N_BASIC_AUTH_* env vars are deprecated and ignored"
  - "Pattern 6: Set N8N_SECURE_COOKIE=false in .env when running n8n over plain HTTP on LAN without TLS termination"

requirements-completed: []

# Metrics
duration: 45min
completed: 2026-02-17
---

# Phase 1 Plan 02: Persistence, Backups, and n8n Verification Summary

**Data persistence confirmed, daily pg_dump backups automated via systemd timer, and n8n 2.x UI verified accessible at http://localhost:5678/ after resolving secure-cookie and deprecated-auth-env deviations**

## Performance

- **Duration:** ~45 min (including checkpoint pause for human verification)
- **Started:** 2026-02-17
- **Completed:** 2026-02-17
- **Tasks:** 2 (1 auto, 1 human-verify checkpoint)
- **Files modified:** 5

## Accomplishments

- Data persistence verified: test row survived full `docker compose down && docker compose up` cycle
- Automated daily backup script created at ~/aerys/backup.sh: pg_dump of both `aerys` and `n8n` databases, gzip compressed, 7-day retention
- systemd user timer `aerys-backup.timer` scheduled for 03:00 daily; two successful backup runs confirmed (aerys_20260217_154032.sql.gz, n8n_20260217_154032.sql.gz)
- n8n 2.x owner account created via built-in setup wizard; free community license activated
- n8n UI confirmed accessible by user at http://localhost:5678/ — Phase 1 fully operational

## Task Commits

Commits are in the aerys repo at ~/aerys/ (separate from planning repo):

1. **Task 1: Verify data persistence and set up automated NAS backups** - `35ef009` (feat)
2. **Task 2: Fix n8n secure cookie for LAN HTTP access** - `6b6c8c1` (fix — deviation auto-applied before user verification)
3. **Task 2: Human verification checkpoint** - N/A (human action, no commit)

## Files Created/Modified

- `~/aerys/backup.sh` - Daily pg_dump script for aerys + n8n databases; defaults BACKUP_DIR to ~/aerys/backups/ (NAS fallback)
- `~/.config/systemd/user/aerys-backup.service` - systemd service unit wrapping backup.sh
- `~/.config/systemd/user/aerys-backup.timer` - OnCalendar=*-*-* 03:00:00, enabled and running
- `~/aerys/.env` - Added N8N_SECURE_COOKIE=false
- `~/aerys/docker-compose.yml` - Removed deprecated N8N_BASIC_AUTH_* environment variables

## Decisions Made

- **NAS fallback to ~/aerys/backups/:** No NAS mount found at /mnt/nas, /media/nas, or via `mount`. Local fallback used. `BACKUP_DIR` env var in backup.sh allows override without editing the script when NAS is configured.
- **systemd timer over crontab:** `crontab` binary unavailable on Tachyon. Implemented equivalent with `aerys-backup.timer` (systemd --user). Enabled with `systemctl --user enable --now`.
- **n8n 2.x auth change:** N8N_BASIC_AUTH_USER / N8N_BASIC_AUTH_PASSWORD are deprecated in n8n 2.x and silently ignored. Owner account created through the built-in first-run wizard. Dead env vars removed from docker-compose.yml to avoid confusion.
- **N8N_SECURE_COOKIE=false:** n8n 2.x enforces secure cookies (HTTPS-only) by default. The LAN setup uses plain HTTP (no TLS). Setting false allows the session cookie to be set over HTTP. This is acceptable for a local-network-only deployment.
- **Tachyon IP correction:** LAN IP is localhost, not localhost (which was a previous network assumption). Updated in all references.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] crontab unavailable; switched to systemd user timer**
- **Found during:** Task 1 (adding daily backup cron entry)
- **Issue:** `crontab` command not found on Tachyon/QCM6490. Plan specified `(crontab -l 2>/dev/null; echo ...) | crontab -`.
- **Fix:** Created systemd user units `aerys-backup.service` and `aerys-backup.timer` at ~/.config/systemd/user/. Enabled and started the timer. Equivalent 3 AM daily schedule via `OnCalendar=*-*-* 03:00:00`.
- **Files modified:** ~/.config/systemd/user/aerys-backup.service, ~/.config/systemd/user/aerys-backup.timer
- **Verification:** `systemctl --user list-timers` shows aerys-backup.timer active, next trigger Wed 2026-02-18 03:00:00
- **Committed in:** 35ef009 (Task 1 commit)

**2. [Rule 1 - Bug] NAS not found; used local backup fallback**
- **Found during:** Task 1 (NAS discovery step)
- **Issue:** No NAS mount at /mnt/nas or /media/nas. `df -h` showed no network share.
- **Fix:** Set `BACKUP_DIR` default to `${HOME}/aerys/backups/` in backup.sh. Added comment directing user to override via env var or edit when NAS is configured.
- **Files modified:** ~/aerys/backup.sh
- **Verification:** Backup script ran successfully; files created in ~/aerys/backups/
- **Committed in:** 35ef009 (Task 1 commit)

**3. [Rule 1 - Bug] N8N_BASIC_AUTH_* deprecated in n8n 2.x; removed dead env vars**
- **Found during:** Task 2 (n8n login attempt — credentials from .env did not work)
- **Issue:** n8n 2.x removed basic auth env var support. N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD are silently ignored. No login prompt appeared — n8n redirected to owner setup wizard instead.
- **Fix:** Completed owner account setup via the built-in wizard (set email, password, name). Removed deprecated N8N_BASIC_AUTH_* vars from docker-compose.yml.
- **Files modified:** ~/aerys/docker-compose.yml
- **Verification:** n8n login works with owner credentials; workflow editor loads
- **Committed in:** 6b6c8c1 (fix commit after Task 2 checkpoint discovery)

**4. [Rule 1 - Bug] N8N_SECURE_COOKIE=false needed for HTTP LAN access**
- **Found during:** Task 2 (post-owner-setup login — session cookie not being set)
- **Issue:** n8n 2.x enforces `secure` flag on session cookies by default. Browser on LAN over plain HTTP rejects secure cookies, making login impossible even with correct credentials.
- **Fix:** Added `N8N_SECURE_COOKIE=false` to ~/aerys/.env. Restarted n8n container.
- **Files modified:** ~/aerys/.env
- **Verification:** Login succeeded; user confirmed n8n UI accessible at http://localhost:5678/
- **Committed in:** 6b6c8c1 (fix commit)

---

**Total deviations:** 4 auto-fixed (2 bugs, 1 missing/deprecated feature handling, 1 environment fallback)
**Impact on plan:** All fixes required for correct operation. crontab → systemd is equivalent functionality. NAS fallback is documented with clear override path. n8n 2.x auth changes are breaking but well-handled. Secure cookie fix is necessary for plain-HTTP LAN deployment.

## Issues Encountered

- n8n 2.x introduced silent breaking changes to auth env vars and cookie security defaults — both resolved before user verification checkpoint.
- Tachyon IP localhost from earlier planning notes was incorrect; actual LAN address is localhost.

## User Setup Required

**Pending manual action:** Back up ~/aerys/.env separately — it contains N8N_ENCRYPTION_KEY which is irreplaceable if lost. If this key is lost, all stored n8n credentials (API keys, OAuth tokens) become unrecoverable.

**NAS backup migration (when available):** When a NAS is mounted, update the default BACKUP_DIR in ~/aerys/backup.sh or set it via environment variable. The backup script supports override via `BACKUP_DIR=/mnt/nas/aerys-backups ~/aerys/backup.sh`.

## Next Phase Readiness

- Phase 1 infrastructure fully operational: PostgreSQL 16 + pgvector + n8n 2.x running on Tachyon (localhost)
- n8n owner account created, free community license active, workflow editor accessible
- Data persistence confirmed, automated daily backups running via systemd timer
- Schema evolution path: Phase 2+ migrations via `docker exec aerys-postgres-1 psql` (not initdb.d, which only runs on first container start)
- Ready for Phase 2: channel integrations (Telegram, Discord, etc.) via n8n workflows

---
*Phase: 01-infrastructure*
*Completed: 2026-02-17*

## Self-Check: PASSED

**Files verified:**
- FOUND: ~/aerys/backup.sh (executable, produces .sql.gz files)
- FOUND: ~/.config/systemd/user/aerys-backup.timer (active, next trigger 2026-02-18 03:00:00)
- FOUND: ~/aerys/backups/ (aerys_20260217_154032.sql.gz, n8n_20260217_154032.sql.gz confirmed)
- FOUND: .planning/phases/01-infrastructure/01-02-SUMMARY.md (this file)

**Commits verified (aerys repo):**
- FOUND: 35ef009 feat(01-02): add automated daily database backup script
- FOUND: 6b6c8c1 fix(01-02): disable secure cookie for LAN HTTP access

**n8n verified:**
- User confirmed: n8n UI accessible at http://localhost:5678/ (approved)
- Owner account created, community license activated
