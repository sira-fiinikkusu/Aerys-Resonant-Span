# Phase 1: Infrastructure - Research

**Researched:** 2026-02-16
**Domain:** Docker Compose, PostgreSQL 16 + pgvector, n8n self-hosting
**Confidence:** HIGH (stack is stable, official docs consulted, well-trodden path)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Docker setup
- Separate containers for n8n and PostgreSQL via Docker Compose
- Shared Postgres instance: one Postgres container, separate databases for n8n and Aerys
- Bind-mount volumes to `~/aerys/` (e.g., `~/aerys/data` for DB, `~/aerys/config` for n8n)
- Auto-restart policy (`restart: unless-stopped`) — Aerys comes back up on reboot
- Standard Docker Engine + Docker Compose on Debian-based OS (check if already installed on Tachyon)
- n8n image tag: `latest` (no version pinning)
- Architecture must be portable: copy `~/aerys/` to Jetson Orin Nano Super and `docker compose up`

#### Database schema
- Individual message rows (not whole conversations) — granular, searchable
- Rich person profiles: name, platform IDs, timezone, preferences, relationship notes, interaction patterns, important dates, custom fields
- Memories support embeddings + category tags for hybrid retrieval (semantic search + tag filtering)
- Versioned SQL migration files (001_init.sql, 002_add_tags.sql, etc.) for schema evolution across phases
- Channel tracked on both conversation AND individual message level (supports cross-channel identity in Phase 3)
- Memories can be person-linked OR global (events, topics not tied to anyone)
- pgvector with 1536 dimensions (OpenAI text-embedding-3-small compatible)
- Soft-delete for messages and memories (mark as deleted, never hard-delete)
- Skip AI model usage tracking for v1

#### n8n configuration
- n8n execution data stored in Postgres (not SQLite) — shared database, consistent backups
- Workflows version-controlled as exported JSON committed to git — reproducible, portable to Jetson
- Credentials managed via n8n's built-in encrypted credential store (not env vars)
- n8n authentication enabled (username/password) even behind Twingate
- Execution history pruned after 30 days to save disk

#### Hardware & network
- Particle Tachyon board: Qualcomm QCM6490 8-core, 8GB RAM, 128GB flash, 12 TOPS NPU
- Tachyon also runs the development toolchain and OpenClaw — resource contention not a concern
- Wi-Fi connectivity only (5G cellular not activated)
- Network access via Twingate (existing anchors on same network) — no VPN setup needed on Tachyon
- NAS available on network for backups
- API-based embeddings via OpenRouter for v1 (NPU-based local embeddings deferred)
- Future migration path: Jetson Orin Nano Super (the target hardware) — plan Docker setup for portability

### Implementation Discretion
- Resource limits on Docker containers (decide based on shared Tachyon usage with the development toolchain/OpenClaw)
- DB backup strategy (whether to automate backups to NAS — lean toward yes given data importance)
- Phase 1 schema scope (only tables needed now vs skeleton for later — lean toward minimal, using migrations to add)
- Docker installation steps if not already present on the Tachyon

### Deferred Ideas (OUT OF SCOPE)
- Local embedding models on the Tachyon's NPU — explore after v1 when API costs are understood
- 5G cellular as network fallback — not needed for v1
- AI model usage/cost tracking table — revisit if OpenRouter costs become a concern
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MEM-07 | PostgreSQL 16 with pgvector extension running, schema provisioned for conversations, memories, and person profiles | Docker image `pgvector/pgvector:pg16` provides this. Schema design patterns documented below. HNSW index on `vector(1536)` columns. |
</phase_requirements>

---

## Summary

Phase 1 is a well-understood infrastructure setup with an official Docker Compose template provided by n8n themselves. The core stack — n8n `latest` + `pgvector/pgvector:pg16` — runs on arm64 without modification; both images publish multi-arch manifests. The only gotcha-heavy area is n8n's encryption key: if the `.n8n` bind-mount is lost, all stored credentials are permanently locked. Everything else follows standard Docker Compose patterns.

The schema design is straightforward PostgreSQL with one pgvector wrinkle: the HNSW index on a `vector(1536)` column should be created after the initial data load (not at table creation time) to avoid building an index over an empty dataset, though it works either way. For the migration file approach, PostgreSQL's `/docker-entrypoint-initdb.d/` mechanism runs scripts alphabetically on first container start, which maps cleanly to the `001_init.sql`, `002_add_tags.sql` convention.

The key discretionary decisions: apply soft container resource limits (2 CPU / 2GB Postgres, 2 CPU / 1GB n8n) to keep Tachyon headroom for the development toolchain and OpenClaw; automate NAS backups via a daily `pg_dump` cron; keep Phase 1 schema minimal (conversations, messages, memories, persons tables only — no channel-routing or embedding pipeline tables yet, those come in Phase 2+).

**Primary recommendation:** Use the official `n8n-io/n8n-hosting` Docker Compose template as the base, adapt it to bind-mounts at `~/aerys/`, add `pgvector/pgvector:pg16` as the database image, and provision schema via numbered SQL files mounted into `/docker-entrypoint-initdb.d/`.

---

## Standard Stack

### Core

| Component | Version/Tag | Purpose | Why Standard |
|-----------|------------|---------|--------------|
| `pgvector/pgvector` | `pg16` | PostgreSQL 16 + pgvector extension | Official pgvector Docker image; multi-arch (arm64 supported); pgvector v0.8.1 as of research date |
| `docker.n8n.io/n8nio/n8n` | `latest` | Workflow automation engine | Official n8n image; multi-arch arm64; `latest` per user decision |
| Docker Engine | 29.x | Container runtime | Official Debian apt repo; arm64 fully supported |
| Docker Compose Plugin | bundled with Engine | Service orchestration | `docker-compose-plugin` installs with Docker Engine v2 |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `postgres:16` (base) | 16 | If needing stock Postgres without pgvector | Don't use — use `pgvector/pgvector:pg16` which includes extension |
| n8n CLI (`n8n export:workflow`) | bundled with n8n | Export workflows to JSON for git | Run from inside the n8n container; used for workflow versioning |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `pgvector/pgvector:pg16` | `postgres:16` + manual extension install | Manual install requires Dockerfile or init script to `apt install` and `CREATE EXTENSION vector` — more fragile; pgvector official image is the right choice |
| bind-mounts to `~/aerys/` | Docker named volumes | Named volumes harder to inspect, copy, and migrate to Jetson; bind-mounts at `~/aerys/` give explicit control and match portability requirement |
| Separate n8n DB | Shared Postgres (n8n + Aerys in same instance, separate DBs) | User decision: shared Postgres, separate databases — saves RAM, one container to back up |

**Installation (on Tachyon if Docker not present):**
```bash
# Add Docker's apt repository
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Post-install: run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker run hello-world
docker compose version
```

---

## Architecture Patterns

### Recommended Directory Structure

```
~/aerys/
├── docker-compose.yml       # Service definitions
├── .env                     # Secrets (gitignored)
├── data/
│   └── postgres/            # PostgreSQL bind-mount (DB data files)
├── config/
│   └── n8n/                 # n8n bind-mount (.n8n directory)
├── migrations/
│   ├── 001_init.sql         # Base schema: conversations, messages, persons, memories
│   └── 002_*.sql            # Future phases add tables here
└── workflows/
    └── *.json               # Exported n8n workflows (git-tracked)
```

### Pattern 1: Docker Compose — Shared Postgres, Separate Databases

The official n8n-hosting template uses a non-root Postgres user for n8n and an init script to create it. For Aerys, we need two databases in one Postgres container: `n8n` (for n8n internal use) and `aerys` (for application data).

```yaml
# Source: https://github.com/n8n-io/n8n-hosting/blob/main/docker-compose/withPostgres/docker-compose.yml
# Adapted for Aerys with bind-mounts and pgvector image

services:
  postgres:
    image: pgvector/pgvector:pg16
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: n8n                    # n8n's database
    volumes:
      - ${HOME}/aerys/data/postgres:/var/lib/postgresql/data
      - ${HOME}/aerys/migrations:/docker-entrypoint-initdb.d  # runs 001_init.sql etc on first start
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U ${POSTGRES_USER} -d n8n']
      interval: 5s
      timeout: 5s
      retries: 10

  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    restart: unless-stopped
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: "720"      # 30 days = 720 hours
      EXECUTIONS_DATA_PRUNE_MAX_COUNT: "10000"
    ports:
      - "5678:5678"
    volumes:
      - ${HOME}/aerys/config/n8n:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G
        reservations:
          cpus: '0.25'
          memory: 256M
```

### Pattern 2: Migration Files via `/docker-entrypoint-initdb.d/`

PostgreSQL's init directory runs `.sql` files alphabetically on first container start (when data directory is empty). Files do NOT re-run on subsequent starts.

**Critical implication:** The `migrations/` bind-mount handles Phase 1 initial schema. For schema changes in Phase 2+, use `psql` directly (or an n8n workflow that runs SQL) — the init scripts won't re-run.

```
~/aerys/migrations/
├── 000_extensions.sql   # CREATE EXTENSION vector; CREATE DATABASE aerys;
├── 001_init.sql         # Core schema: persons, conversations, messages, memories
```

The `000_extensions.sql` must run first (alphabetical order guaranteed) to enable the `vector` extension before `001_init.sql` references it.

### Pattern 3: pgvector Schema for Hybrid Retrieval

1536 dimensions = OpenAI `text-embedding-3-small` compatible. Use `vector_cosine_ops` distance operator (cosine similarity is standard for text embedding search). HNSW index preferred over IVFFlat: it builds without pre-existing data, better query performance for low-to-medium data sizes.

```sql
-- Source: pgvector GitHub README + neon.com/docs/extensions/pgvector

-- Enable extension (run in 000_extensions.sql)
CREATE EXTENSION IF NOT EXISTS vector;

-- Memories table with hybrid retrieval support
CREATE TABLE memories (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id   UUID REFERENCES persons(id) ON DELETE SET NULL,  -- NULL = global memory
    content     TEXT NOT NULL,
    summary     TEXT,
    category    TEXT[],                                           -- tags for filtering
    embedding   vector(1536),                                     -- OpenAI text-embedding-3-small
    channel     TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ                                       -- soft delete
);

-- HNSW index for cosine similarity search
-- Create AFTER initial data load for performance; works fine on empty table too
CREATE INDEX ON memories USING hnsw (embedding vector_cosine_ops);

-- Soft-delete filter index
CREATE INDEX ON memories (deleted_at) WHERE deleted_at IS NULL;
```

### Pattern 4: Workflow Export for Version Control

n8n does not have a native file-watch/git-push mechanism in the community edition (that's Enterprise). The community approach: export manually via UI or CLI, commit JSON to git.

```bash
# Export all workflows from inside the running n8n container
docker exec -it aerys-n8n-1 n8n export:workflow --all --output=/home/node/.n8n/workflows/

# On host, the workflows appear at:
# ~/aerys/config/n8n/workflows/*.json
# Commit these to git
```

Alternatively, export individual workflows via the n8n UI: "Download" button exports JSON. Import via "Import from file" or URL.

**Note:** Exported workflow JSON does NOT include credential data — credentials must be re-created manually on import. Only the credential names/types are preserved.

### Pattern 5: n8n Basic Auth

Authentication via environment variables (applicable to community edition self-hosting):

```bash
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=aerys-admin
N8N_BASIC_AUTH_PASSWORD=<strong-random-password>
```

These go in the `.env` file (never committed to git).

### Anti-Patterns to Avoid

- **Hardcoding secrets in docker-compose.yml**: All passwords, the encryption key, and auth credentials belong in `.env`. The `.env` file must be gitignored.
- **Named volumes instead of bind-mounts**: Named volumes cannot be easily inspected or moved to Jetson. The portability requirement mandates bind-mounts at `~/aerys/`.
- **Omitting the N8N_ENCRYPTION_KEY env var**: If not set, n8n generates a random key stored in `/home/node/.n8n/config`. If the bind-mount is ever lost, all credentials are permanently unrecoverable. Setting it explicitly in `.env` means it survives container re-creation.
- **Creating HNSW index before extension**: `CREATE EXTENSION vector` must exist before any `vector(1536)` column type or index. Run in a separate `000_extensions.sql` that sorts before `001_init.sql`.
- **Expecting init scripts to re-run**: `/docker-entrypoint-initdb.d/` only fires when the data directory is empty (first start). Subsequent schema changes require direct `psql` execution.
- **Forgetting the Aerys database in init scripts**: The Postgres container creates only the `n8n` database by default (via `POSTGRES_DB`). A `000_extensions.sql` script must `CREATE DATABASE aerys` explicitly.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Vector similarity search | Custom cosine distance SQL functions | `pgvector` HNSW index + `<=>` operator | pgvector handles IVFFlat vs HNSW trade-offs, index maintenance, distance operators — extremely complex to replicate |
| Container health checks | Custom wait scripts in entrypoint | `healthcheck` + `depends_on: condition: service_healthy` | Docker Compose has built-in health check orchestration; custom wait loops are fragile |
| DB backup scheduling | Custom backup service container | `docker exec postgres pg_dump` via host cron | Simpler, no additional container; host cron survives container restarts |
| Schema migration tracking | Custom migration state table | Numbered file prefix + init-only approach for Phase 1; use Flyway/Liquibase only if migrations become complex | Phase 1 has one init run; a migration framework is overhead until needed |
| n8n authentication | Custom reverse proxy auth layer | `N8N_BASIC_AUTH_ACTIVE` env var | Built-in basic auth is sufficient behind Twingate; no proxy complexity needed |

**Key insight:** pgvector replaces the need for any external vector database (Pinecone, Weaviate, Qdrant). The 1536-dimension HNSW index handles all Phase 1-3 similarity search needs from within Postgres.

---

## Common Pitfalls

### Pitfall 1: Lost Encryption Key = Lost Credentials
**What goes wrong:** n8n container is re-created or the `.n8n` bind-mount is accidentally deleted. n8n generates a new encryption key. All stored credentials (API keys, OAuth tokens) decrypt to garbage. Every credential must be re-entered manually.
**Why it happens:** n8n auto-generates `N8N_ENCRYPTION_KEY` on first start and stores it in `~/.n8n/config` if not explicitly set. If the volume disappears, the key is gone.
**How to avoid:** Set `N8N_ENCRYPTION_KEY` as an explicit environment variable in `.env`. Back up the `.env` file separately from the `~/aerys/` directory. The key is a 32-character hex string — generate once with `openssl rand -hex 32`.
**Warning signs:** n8n shows "Bad credentials" errors on existing connections after any container operation.

### Pitfall 2: Init Scripts Don't Re-Run
**What goes wrong:** Developer adds `002_add_column.sql` to `~/aerys/migrations/`, restarts Docker Compose, and the column doesn't appear.
**Why it happens:** `/docker-entrypoint-initdb.d/` only executes when the PostgreSQL data directory is empty (i.e., first container initialization). Subsequent starts skip the scripts entirely.
**How to avoid:** For Phase 1 initial setup, init scripts work perfectly. For Phase 2+ schema changes, apply migrations via: `docker exec -it aerys-postgres-1 psql -U $POSTGRES_USER -d aerys -f /path/to/migration.sql`
**Warning signs:** New SQL files added to migrations directory have no effect after the first container start.

### Pitfall 3: Missing `CREATE DATABASE aerys` in Init Scripts
**What goes wrong:** `001_init.sql` tries to create tables in the `aerys` database, but only the `n8n` database exists (set by `POSTGRES_DB` env var). Init script fails, schema is never provisioned.
**Why it happens:** The Postgres container only creates one database automatically (the one named in `POSTGRES_DB`). All other databases must be created explicitly.
**How to avoid:** In `000_extensions.sql` (which runs first alphabetically), include: `CREATE DATABASE aerys;` before switching to `\c aerys` to create extensions and tables. The n8n-hosting repo's `init-data.sh` pattern creates a non-root user — follow the same pattern for the `aerys` DB.
**Warning signs:** `psql -d aerys` reports "database does not exist".

### Pitfall 4: `vector` Extension Not Found in Aerys Database
**What goes wrong:** `CREATE EXTENSION IF NOT EXISTS vector` is only run in the default `n8n` database. When connecting to the `aerys` database, pgvector is unavailable and `vector(1536)` columns fail.
**Why it happens:** PostgreSQL extensions are per-database. Installing in one database does not make it available in another.
**How to avoid:** In `000_extensions.sql`, connect to the `aerys` database with `\c aerys` and run `CREATE EXTENSION IF NOT EXISTS vector` there.
**Warning signs:** `ERROR: type "vector" does not exist` when running schema migration in `aerys` database.

### Pitfall 5: bind-mount Permissions (n8n runs as non-root)
**What goes wrong:** n8n container starts but can't write to `~/aerys/config/n8n/` — permission denied errors, fails to create `config` file, encryption key not saved.
**Why it happens:** n8n runs as user `node` (UID 1000) inside the container. If the host directory is owned by root or another UID, writes fail.
**How to avoid:** Create the directory before first start and ensure it's owned by the current user: `mkdir -p ~/aerys/config/n8n && chmod 755 ~/aerys/config/n8n`. The `node` user inside the container maps to UID 1000 — on most Debian systems the first regular user is also UID 1000, so ownership usually works automatically.
**Warning signs:** n8n logs show `EACCES: permission denied` during startup.

### Pitfall 6: Docker Compose `deploy.resources` Requires Swarm Context (Older Versions)
**What goes wrong:** Resource limits defined under `deploy.resources` are silently ignored when running `docker compose up` (not Swarm mode) with older Docker Compose v3 syntax.
**Why it happens:** In Compose spec v3, `deploy` was originally a Swarm-only section. Docker Compose v2 (the plugin) honors `deploy.resources.limits` for standalone containers, but this depends on the compose plugin version.
**How to avoid:** Use Docker Compose plugin v2.x (bundled with Docker Engine 28+). Verify limits are applied with `docker stats`. The current recommended syntax (under compose-spec) works correctly.
**Warning signs:** `docker stats` shows containers using more RAM than the specified limit.

---

## Code Examples

Verified patterns from official sources:

### Full `.env` Template

```bash
# Source: n8n-hosting README + pgvector docs
# Never commit this file

POSTGRES_USER=n8n_admin
POSTGRES_PASSWORD=<generate: openssl rand -hex 24>

# n8n app credentials for Aerys database (create in 000_extensions.sql)
AERYS_DB_USER=aerys_app
AERYS_DB_PASSWORD=<generate: openssl rand -hex 24>

# n8n encryption key — generate once, never change
N8N_ENCRYPTION_KEY=<generate: openssl rand -hex 32>

# n8n UI login
N8N_BASIC_AUTH_USER=aerys-admin
N8N_BASIC_AUTH_PASSWORD=<generate: openssl rand -hex 16>
```

### `000_extensions.sql` — Database + Extension Setup

```sql
-- Runs first (alphabetically) in /docker-entrypoint-initdb.d/
-- Connected to default 'n8n' database as superuser at this point

-- Enable vector in n8n database (in case n8n ever needs it)
CREATE EXTENSION IF NOT EXISTS vector;

-- Create Aerys application database
CREATE DATABASE aerys;

-- Create app user with least-privilege access
CREATE USER aerys_app WITH PASSWORD 'PLACEHOLDER_REPLACED_BY_ENV';
GRANT ALL PRIVILEGES ON DATABASE aerys TO aerys_app;

-- Switch to aerys database and enable extension
\c aerys

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant schema permissions to app user
GRANT ALL ON SCHEMA public TO aerys_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO aerys_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO aerys_app;
```

**Note:** The password literal in SQL can't read env vars. Use an init shell script (`.sh` file in initdb.d) to substitute env vars, as the n8n-hosting `init-data.sh` does — or accept the superuser creates the database and the app connects with the superuser credentials for v1 simplicity.

### `001_init.sql` — Core Aerys Schema (Phase 1 minimal)

```sql
-- Source: schema design based on project requirements in CONTEXT.md
-- Run in /aerys database context after 000_extensions.sql

\c aerys

-- Persons: rich profiles for cross-channel identity
CREATE TABLE persons (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name        TEXT NOT NULL,
    discord_id          TEXT UNIQUE,
    telegram_id         TEXT UNIQUE,
    email               TEXT UNIQUE,
    timezone            TEXT,
    preferences         JSONB DEFAULT '{}',
    relationship_notes  TEXT,
    interaction_notes   TEXT,
    important_dates     JSONB DEFAULT '{}',
    custom_fields       JSONB DEFAULT '{}',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

-- Conversations: thread/session grouping per channel
CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id       UUID REFERENCES persons(id) ON DELETE SET NULL,
    channel         TEXT NOT NULL,      -- 'discord', 'telegram', 'gmail'
    channel_thread_id TEXT,             -- Discord thread ID, Gmail thread ID, etc.
    summary         TEXT,               -- updated after conversation ends
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at        TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);

-- Messages: individual message rows (granular, searchable)
CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    person_id       UUID REFERENCES persons(id) ON DELETE SET NULL,
    channel         TEXT NOT NULL,      -- redundant with conversation for direct querying
    role            TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content         TEXT NOT NULL,
    content_type    TEXT DEFAULT 'text', -- 'text', 'voice', 'image', 'document'
    raw_metadata    JSONB DEFAULT '{}',  -- original channel-specific payload
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

-- Memories: long-term with embeddings + tags for hybrid retrieval
CREATE TABLE memories (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id       UUID REFERENCES persons(id) ON DELETE SET NULL,  -- NULL = global
    source_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    content         TEXT NOT NULL,
    summary         TEXT,
    category        TEXT[],             -- tags: ['preference', 'fact', 'event', 'instruction']
    embedding       vector(1536),       -- text-embedding-3-small (1536 dims)
    channel         TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_persons_discord ON persons (discord_id) WHERE discord_id IS NOT NULL;
CREATE INDEX idx_persons_telegram ON persons (telegram_id) WHERE telegram_id IS NOT NULL;
CREATE INDEX idx_persons_email ON persons (email) WHERE email IS NOT NULL;

CREATE INDEX idx_conversations_person ON conversations (person_id);
CREATE INDEX idx_conversations_channel ON conversations (channel);

CREATE INDEX idx_messages_conversation ON messages (conversation_id);
CREATE INDEX idx_messages_person ON messages (person_id);
CREATE INDEX idx_messages_channel ON messages (channel);
CREATE INDEX idx_messages_created ON messages (created_at DESC);

CREATE INDEX idx_memories_person ON memories (person_id);
CREATE INDEX idx_memories_category ON memories USING GIN (category);
CREATE INDEX idx_memories_active ON memories (deleted_at) WHERE deleted_at IS NULL;

-- HNSW index for vector similarity search (cosine distance, standard for text embeddings)
-- Note: created here works fine on empty table; could defer to after initial data load
CREATE INDEX idx_memories_embedding ON memories USING hnsw (embedding vector_cosine_ops);
```

### Execution Pruning Variables (30-day retention)

```bash
# Source: n8n-docs/docs/hosting/scaling/execution-data.md
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=720          # 720 hours = 30 days (user decision)
EXECUTIONS_DATA_PRUNE_MAX_COUNT=10000
```

### NAS Backup via Host Cron

```bash
# Add to host crontab: crontab -e
# Daily backup at 3 AM, retain 7 days
0 3 * * * docker exec aerys-postgres-1 pg_dump -U n8n_admin aerys | gzip > /mnt/nas/aerys-backups/aerys_$(date +\%Y\%m\%d).sql.gz
0 3 * * * docker exec aerys-postgres-1 pg_dump -U n8n_admin n8n | gzip > /mnt/nas/aerys-backups/n8n_$(date +\%Y\%m\%d).sql.gz
# Prune backups older than 7 days
30 3 * * * find /mnt/nas/aerys-backups/ -name "*.sql.gz" -mtime +7 -delete
```

---

## Discretionary Recommendations

### Resource Limits
The Tachyon has 8GB RAM and 8 cores, shared with the development toolchain and OpenClaw. Recommended limits:

| Container | CPU limit | Memory limit | Rationale |
|-----------|-----------|--------------|-----------|
| postgres | 2.0 | 2G | DB needs headroom for queries; 2G leaves 6G for other processes |
| n8n | 2.0 | 1G | n8n workflows are lightweight; 1G is generous |
| Total reserved | 4 cores | 3G | Leaves 4 cores + 5G for the development toolchain + OpenClaw |

Use `deploy.resources` in Docker Compose v2 plugin syntax (verified working with standalone compose, not just Swarm).

### DB Backup Strategy
Automate — data importance justifies it. Use host cron + `pg_dump` piped to gzip, stored on NAS. No additional container needed. Retain 7 days on NAS. This covers both the `aerys` and `n8n` databases in one step.

### Phase 1 Schema Scope
Lean minimal: provision only the four tables needed for Phase 2 (conversations, messages, persons, memories). Do NOT pre-create channel routing tables, sub-agent tables, or analytics tables — those come in their respective phases via numbered migration files. The HNSW index on memories can be created at schema time (works on empty tables with HNSW, unlike IVFFlat which needs data for centroid training).

### Docker Installation
Check first: `docker --version && docker compose version`. If present, skip installation. If absent, use the official Debian apt repo method (documented in Code Examples above).

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| `docker-compose` (v1, standalone binary) | `docker compose` (v2, plugin bundled with Docker Engine) | Use `docker compose` not `docker-compose`; v2 supports `deploy.resources` for standalone containers |
| IVFFlat as default pgvector index | HNSW as recommended default | HNSW builds without data, better performance for <1M vectors, preferred for new deployments |
| `N8N_BASIC_AUTH_ACTIVE` + username/password | Same (community edition) | n8n Enterprise has SSO/LDAP; community edition uses basic auth — this is correct for the use case |
| SQLite for n8n execution data | PostgreSQL for n8n execution data | User decision already aligns with best practice for production deployments |
| `version:` field in docker-compose.yml | Omit `version:` field | Docker Compose v2 ignores the version field; including it generates a warning. Omit it. |

**Deprecated/outdated:**
- `docker-compose` (v1 binary): replaced by `docker compose` plugin. Always use `docker compose` (with space).
- `version: "3.8"` in compose files: the compose-spec no longer uses a version declaration. Omit entirely.
- IVFFlat index as default pgvector choice: HNSW is now the standard recommendation for new deployments where you don't need to minimize memory usage.

---

## Open Questions

1. **Is Docker already installed on the Tachyon?**
   - What we know: Tachyon runs the development toolchain and OpenClaw, both of which may use Docker
   - What's unclear: Whether Docker Engine + Docker Compose plugin are present
   - Recommendation: First task in Plan 01-01 should be `docker --version && docker compose version` check; install only if absent

2. **NAS mount point on Tachyon**
   - What we know: NAS is available on the network
   - What's unclear: Whether the NAS is already mounted on the Tachyon and at what path
   - Recommendation: Plan should include a step to verify NAS mount and establish the backup path; `/mnt/nas/` is a conventional location but needs validation

3. **Init script password injection for `aerys_app` user**
   - What we know: SQL init scripts can't read Docker environment variables directly
   - What's unclear: Whether to use a shell `.sh` init script (which can read env vars) or accept superuser-only access for v1
   - Recommendation: For v1 simplicity, connect as superuser (`POSTGRES_USER`). Add a dedicated `aerys_app` user in Phase 2 when security posture matters. Document this as technical debt.

4. **n8n `latest` image and arm64 support**
   - What we know: n8n publishes multi-arch images; arm64 is listed in Docker Hub manifests
   - What's unclear: Whether the absolute latest tag at time of deployment is arm64-compatible (very unlikely to be an issue, but worth confirming on first pull)
   - Recommendation: `docker pull docker.n8n.io/n8nio/n8n:latest` and verify `docker inspect` shows arm64 architecture

---

## Sources

### Primary (HIGH confidence)
- `https://github.com/n8n-io/n8n-hosting/blob/main/docker-compose/withPostgres/docker-compose.yml` — Official n8n Docker Compose template for Postgres
- `https://github.com/n8n-io/n8n-docs/blob/main/docs/hosting/scaling/execution-data.md` — Execution pruning env vars with defaults
- `https://github.com/pgvector/pgvector` — pgvector README: index types, operators, version (v0.8.1)
- `https://neon.com/docs/extensions/pgvector` — Index creation syntax, distance operators, 1536-dim guidance
- `https://docs.docker.com/engine/install/debian/` — Docker Engine arm64 installation on Debian

### Secondary (MEDIUM confidence)
- `https://hub.docker.com/r/pgvector/pgvector` — pgvector Docker image (`pg16` tag); arm64 support confirmed by architecture listings
- `https://docs.n8n.io/hosting/configuration/environment-variables/credentials/` — N8N_BASIC_AUTH_* variables
- `https://docs.docker.com/reference/compose-file/deploy/` — deploy.resources.limits syntax for Docker Compose v2
- Multiple n8n community forum posts confirming N8N_ENCRYPTION_KEY behavior and persistence requirements

### Tertiary (LOW confidence — flagged for validation)
- Community consensus that `docker compose` (plugin v2) honors `deploy.resources.limits` for standalone containers without Swarm mode — verified by Docker docs but behavior with older compose versions varied; validate with `docker stats` after deployment

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — official Docker images, official n8n hosting template, official pgvector docs
- Architecture: HIGH — patterns from official n8n-hosting repo + pgvector docs
- Schema design: MEDIUM — based on requirements in CONTEXT.md, follows standard PostgreSQL patterns; specific column choices not validated against Phase 2+ needs (by design — minimal scope)
- Pitfalls: HIGH — encryption key issue is well-documented in n8n community; init script behavior is official PostgreSQL documentation
- Discretionary recommendations: MEDIUM — resource limits based on available hardware spec; backup approach standard but NAS mount path is unknown

**Research date:** 2026-02-16
**Valid until:** 2026-08-16 (stable infrastructure stack; pgvector and n8n release frequently but API is stable)
