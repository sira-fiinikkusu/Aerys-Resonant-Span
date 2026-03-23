---
phase: 01-infrastructure
plan: 01
subsystem: infra
tags: [docker, postgres, pgvector, n8n, docker-compose]

# Dependency graph
requires: []
provides:
  - PostgreSQL 16 with pgvector running in Docker at ~/aerys/data/postgres
  - n8n workflow engine running on port 5678, connected to Postgres
  - aerys database with persons, conversations, messages, memories schema
  - HNSW vector index on memories.embedding (vector(1536), cosine similarity)
  - Bind-mount infrastructure at ~/aerys/ (portable to Jetson Orin)
  - SQL migration files for schema evolution (000_extensions.sql, 001_init.sql)
affects: [02-channels, 03-memory, 04-ai-agents, 05-integrations, 06-polish]

# Tech tracking
tech-stack:
  added: [pgvector/pgvector:pg16, docker.n8n.io/n8nio/n8n:latest, Docker Engine 27.5.1, Docker Compose v2.35.1]
  patterns:
    - Numbered SQL migration files (000_, 001_, ...) via /docker-entrypoint-initdb.d for first-start schema provisioning
    - Bind-mounts to ~/aerys/ for all persistent data (portable to Jetson)
    - Secrets in .env (gitignored), never hardcoded in docker-compose.yml

key-files:
  created:
    - ~/aerys/docker-compose.yml
    - ~/aerys/.env
    - ~/aerys/.gitignore
    - ~/aerys/migrations/000_extensions.sql
    - ~/aerys/migrations/001_init.sql
  modified: []

key-decisions:
  - "CPU limits removed from docker-compose.yml: kernel 5.4.219 on QCM6490 uses cgroup v1 without CPU CFS quota support; memory limits retained (postgres: 2G, n8n: 1G)"
  - "config/n8n directory set to chmod 777: n8n runs as node (UID 1000), host user is particle (UID 5005), sticky write permissions required for encryption key persistence"
  - "aerys git repo initialized at ~/aerys/ separate from planning repo: infrastructure code tracked independently"

patterns-established:
  - 'Pattern 1: SQL migrations use \c aerys at start of each file to ensure correct database context'
  - 'Pattern 2: Phase 2+ schema changes applied via docker exec psql directly (initdb.d scripts don''t re-run after first start)'
  - 'Pattern 3: n8n credentials managed via built-in encrypted store (not env vars); N8N_ENCRYPTION_KEY in .env ensures credentials survive container recreation'

requirements-completed: [MEM-07]

# Metrics
duration: 14min
completed: 2026-02-17
---

# Phase 1 Plan 01: Infrastructure Setup Summary

**PostgreSQL 16 + pgvector and n8n running in Docker Compose with aerys database schema (persons, conversations, messages, memories) and HNSW vector index for 1536-dim cosine similarity search**

## Performance

- **Duration:** 14 min
- **Started:** 2026-02-17T20:16:49Z
- **Completed:** 2026-02-17T20:31:17Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Docker Compose stack running with PostgreSQL 16 (pgvector/pgvector:pg16) and n8n (docker.n8n.io/n8nio/n8n:latest) on arm64
- aerys database provisioned with four tables: persons (rich profiles), conversations, messages (individual rows), memories (vector search)
- HNSW index on memories.embedding column (vector(1536), vector_cosine_ops) for cosine similarity search
- All secrets in .env (gitignored), containers auto-restart via unless-stopped policy
- Data persists in ~/aerys/ bind-mounts (portable to Jetson Orin Nano Super)

## Task Commits

Each task was committed atomically to a new git repo initialized at ~/aerys/:

1. **Task 1: Create ~/aerys/ directory structure, Docker Compose file, and environment config** - `54510a5` (feat)
2. **Task 2: Create SQL migration files and start Docker Compose stack** - `c8a7fd5` (feat)

## Files Created/Modified

- `~/aerys/docker-compose.yml` - Service definitions for postgres and n8n containers
- `~/aerys/.env` - Generated secrets (POSTGRES_PASSWORD, N8N_ENCRYPTION_KEY, N8N_BASIC_AUTH_PASSWORD) - gitignored
- `~/aerys/.gitignore` - Excludes .env, data/, config/ from version control
- `~/aerys/migrations/000_extensions.sql` - Creates aerys database, enables pgvector + uuid-ossp
- `~/aerys/migrations/001_init.sql` - Core schema: persons, conversations, messages, memories with all indexes

## Decisions Made

- **CPU limits removed:** kernel 5.4.219 on Qualcomm QCM6490 uses cgroup v1 without CPU CFS quota support. `docker compose up` failed with "NanoCPUs can not be set". Removed `cpus:` fields from deploy.resources; memory limits retained (postgres: 2G, n8n: 1G).
- **config/n8n chmod 777:** n8n runs as UID 1000 (node) inside container; host user particle is UID 5005. The directory was chmod 755 (owned by particle) causing EACCES on /home/node/.n8n/config. Set to 777 to allow n8n to persist its encryption key and config.
- **Separate git repo at ~/aerys/:** Infrastructure code tracked independently from planning repo (~/Downloads/personal-ai-planning/). Initialized with git config for particle@aerys.local identity.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] CPU limits unsupported on cgroup v1 kernel**
- **Found during:** Task 2 (starting Docker Compose stack)
- **Issue:** `docker compose up` failed: "NanoCPUs can not be set, as your kernel does not support CPU CFS scheduler or the cgroup is not mounted". Kernel 5.4.219 on QCM6490 uses cgroup v1 without CPU CFS quota support.
- **Fix:** Removed `cpus:` limit and reservation fields from both postgres and n8n deploy.resources blocks. Memory limits retained. Added comment in docker-compose.yml explaining the omission.
- **Files modified:** ~/aerys/docker-compose.yml
- **Verification:** `docker compose up -d` succeeded, both containers started
- **Committed in:** c8a7fd5 (Task 2 commit)

**2. [Rule 1 - Bug] n8n config directory permission denied (Pitfall 5 from research)**
- **Found during:** Task 2 (n8n startup after containers started)
- **Issue:** n8n container crashed with "EACCES: permission denied, open '/home/node/.n8n/config'". n8n runs as node (UID 1000); host directory ~/aerys/config/n8n was owned by particle (UID 5005) with chmod 755.
- **Fix:** `chmod 777 ~/aerys/config/n8n` to allow UID 1000 write access. n8n restarted and came up successfully.
- **Files modified:** ~/aerys/config/n8n (directory permissions only, not a tracked file)
- **Verification:** `curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/` returned 200
- **Committed in:** n/a (directory permission change, not a file change)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both auto-fixes required for containers to run. CPU limit omission is hardware-specific; memory limits still enforce resource bounds. Permission fix is documented in research as Pitfall 5 — known issue, resolved correctly.

## Issues Encountered
- Docker images required downloading (~1.5GB total: pgvector 459MB + n8n 999MB) before first start; waited for pull to complete before starting stack.

## User Setup Required

None - no external service configuration required. n8n is accessible at http://localhost:5678 with basic auth credentials stored in ~/aerys/.env.

## Next Phase Readiness

- PostgreSQL 16 + pgvector running, aerys schema provisioned — ready for Phase 2 channel integrations
- n8n accessible on port 5678 — ready for workflow development
- Schema evolution path documented: Phase 2+ migrations via `docker exec aerys-postgres-1 psql` (not initdb.d which only runs on first start)
- Blocker noted: ~/aerys/.env must be backed up separately — it contains N8N_ENCRYPTION_KEY which is irreplaceable if lost

---
*Phase: 01-infrastructure*
*Completed: 2026-02-17*

## Self-Check: PASSED

**Files verified:**
- FOUND: ~/aerys/docker-compose.yml
- FOUND: ~/aerys/.env
- FOUND: ~/aerys/.gitignore
- FOUND: ~/aerys/migrations/000_extensions.sql
- FOUND: ~/aerys/migrations/001_init.sql
- FOUND: .planning/phases/01-infrastructure/01-01-SUMMARY.md

**Commits verified (aerys repo git log):**
- FOUND: 54510a5 feat(01-01): create directory structure, Docker Compose, and environment config
- FOUND: c8a7fd5 feat(01-01): add SQL migrations and start Docker Compose stack

**Stack verified:**
- aerys-postgres-1: healthy (pgvector/pgvector:pg16)
- aerys-n8n-1: running on port 5678 (docker.n8n.io/n8nio/n8n:latest)
