# Phase 1: Infrastructure - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Set up the foundational stack for Aerys: PostgreSQL 16 with pgvector, n8n instance, and database schema — all running in Docker on the Particle Tachyon board. Everything downstream (channels, memory, sub-agents) builds on these decisions without revisiting infrastructure.

</domain>

<decisions>
## Implementation Decisions

### Docker setup
- Separate containers for n8n and PostgreSQL via Docker Compose
- Shared Postgres instance: one Postgres container, separate databases for n8n and Aerys
- Bind-mount volumes to `~/aerys/` (e.g., `~/aerys/data` for DB, `~/aerys/config` for n8n)
- Auto-restart policy (`restart: unless-stopped`) — Aerys comes back up on reboot
- Standard Docker Engine + Docker Compose on Debian-based OS (check if already installed on Tachyon)
- n8n image tag: `latest` (no version pinning)
- Architecture must be portable: copy `~/aerys/` to Jetson Orin Nano Super and `docker compose up`

### Database schema
- Individual message rows (not whole conversations) — granular, searchable
- Rich person profiles: name, platform IDs, timezone, preferences, relationship notes, interaction patterns, important dates, custom fields
- Memories support embeddings + category tags for hybrid retrieval (semantic search + tag filtering)
- Versioned SQL migration files (001_init.sql, 002_add_tags.sql, etc.) for schema evolution across phases
- Channel tracked on both conversation AND individual message level (supports cross-channel identity in Phase 3)
- Memories can be person-linked OR global (events, topics not tied to anyone)
- pgvector with 1536 dimensions (OpenAI text-embedding-3-small compatible)
- Soft-delete for messages and memories (mark as deleted, never hard-delete)
- Skip AI model usage tracking for v1

### n8n configuration
- n8n execution data stored in Postgres (not SQLite) — shared database, consistent backups
- Workflows version-controlled as exported JSON committed to git — reproducible, portable to Jetson
- Credentials managed via n8n's built-in encrypted credential store (not env vars)
- n8n authentication enabled (username/password) even behind Twingate
- Execution history pruned after 30 days to save disk

### Hardware & network
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

</decisions>

<specifics>
## Specific Ideas

- Aerys may migrate to the Jetson Orin Nano Super as she evolves — Docker Compose + bind-mount design specifically chosen for this portability
- a companion AI project already runs on the Jetson — Aerys is a separate entity with her own memory and personality
- n8nClaw architecture is the blueprint — Workflow-as-Tool pattern for sub-agents

</specifics>

<deferred>
## Deferred Ideas

- Local embedding models on the Tachyon's NPU — explore after v1 when API costs are understood
- 5G cellular as network fallback — not needed for v1
- AI model usage/cost tracking table — revisit if OpenRouter costs become a concern

</deferred>

---

*Phase: 01-infrastructure*
*Context gathered: 2026-02-16*
