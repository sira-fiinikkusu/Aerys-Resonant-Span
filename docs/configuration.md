# Configuration Reference

This document covers the runtime configuration systems that control Aerys's behavior: the personality system (`soul.md`), model routing (`models.json`), environment variables, n8n credentials, Docker volume mounts, and operational scripts.

## Personality System (soul.md)

**Location:** [`config/soul.md`](../config/soul.md)
**Loaded by:** Core Agent's Load Config node via `require('fs')` at runtime
**Changes take effect:** On the next incoming message — no workflow redeploy required

The personality file defines how Aerys communicates — tone, behavioral patterns, limitations handling, and hard rules. The public repository includes a commented-out template showing the full structure. To activate, uncomment the sections and customize.

### Section Structure

| Section | Purpose |
|---------|---------|
| **Who You Are** | Core identity, pronouns, personality archetype, warmth and curiosity style |
| **How You Show Up** | Behavioral patterns: default posture, energy matching, opinion delivery, praise style |
| **When You Can't Do Something** | Graceful limitation handling — no dead-end refusals, always redirect to what is possible |
| **Voice** | Tone, signature phrases, example responses for different contexts (casual, problem-solving, creative) |
| **What You Don't Do** | Anti-patterns to avoid: no micro-affirmations, no shame language, no performative disclaimers |
| **Hard Rules** | Non-negotiable behaviors: cite sources, no fabricated real-time data, lead with answers |
| **Personal Growth** | Evolving section for learned behaviors — updated as Aerys adapts over time |

### Customization

To create a custom personality:

1. Copy the template structure from `config/soul.md`
2. Uncomment all sections
3. Replace the personality traits, voice examples, and behavioral rules
4. Save — changes apply immediately to the next conversation

The personality system is intentionally file-based rather than database-driven. This makes personality changes auditable through version control and avoids coupling the AI's identity to database state.

## Model Routing (models.json)

**Location:** [`config/models.json`](../config/models.json)
**Loaded by:** Core Agent's Load Config node at runtime
**Purpose:** Maps intent classifications to AI model tiers via OpenRouter

### Configuration Structure

```json
{
  "models": {
    "haiku": "anthropic/claude-haiku-4.5",
    "sonnet": "anthropic/claude-sonnet-4.5",
    "opus": "anthropic/claude-opus-4-6"
  },
  "routing": {
    "greeting": "haiku",
    "simple_qa": "sonnet",
    "code_help": "sonnet",
    "research": "opus",
    "creative": "sonnet",
    "analysis": "opus",
    "system_task": "haiku"
  },
  "limits": {
    "opus_daily": 10
  }
}
```

### Tier Mapping

The Core Agent classifies each incoming message by intent, then routes to the appropriate model tier. Each tier runs as a separate n8n sub-workflow with its own AI Agent, memory access, and tool configuration.

| Tier Key | Intent Types | Default Model | Purpose |
|----------|-------------|---------------|---------|
| `haiku` | `greeting`, `system_task` | Fast, low-cost model | Sub-second responses for simple interactions |
| `sonnet` | `simple_qa`, `code_help`, `creative` | Mid-tier conversational model | Default tier for most conversations |
| `opus` | `research`, `analysis` | High-capability reasoning model | Complex tasks, capped at 10 per day |

> **Note on the `haiku` key:** The tier key in `models.json` is `haiku` for historical reasons (originally Claude Haiku). The actual model mapped to this key can be swapped to any fast, low-cost model via OpenRouter — Gemini Flash Lite, GPT-4o-mini, etc. The key name is a routing label, not a model constraint.

### Daily Caps

The `limits.opus_daily` value enforces a daily usage cap on the highest-cost tier. Usage is tracked in the `aerys_model_usage` database table. When the cap is reached, requests that would route to Opus fall back to Sonnet.

### Customizing Model Routing

To change which models handle which intents:

1. Update the model identifiers in the `models` object (use [OpenRouter model IDs](https://openrouter.ai/models))
2. Adjust intent-to-tier mapping in the `routing` object
3. Modify daily caps in the `limits` object as needed
4. Save — changes apply on the next message

## Environment Variables

All environment variables are defined in [`.env.example`](../.env.example) and referenced by `docker-compose.yml`. Copy to `.env` and fill in values before starting.

### Required Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `POSTGRES_USER` | PostgreSQL username for both databases | `aerys` |
| `POSTGRES_PASSWORD` | PostgreSQL password | Generate a strong password |
| `N8N_ENCRYPTION_KEY` | Encrypts n8n credentials at rest in the database | `openssl rand -hex 32` |
| `WEBHOOK_URL` | Public HTTPS URL for Discord/Telegram webhook callbacks | `https://your-domain.example.com/` |
| `N8N_EDITOR_BASE_URL` | Base URL for the n8n editor interface | `https://your-domain.example.com` |
| `GENERIC_TIMEZONE` | System timezone for scheduled workflows | `America/New_York` |

### Docker Compose Variables (Set Automatically)

These are configured in `docker-compose.yml` and generally do not need modification:

| Variable | Value | Purpose |
|----------|-------|---------|
| `DB_TYPE` | `postgresdb` | Tells n8n to use PostgreSQL instead of SQLite |
| `DB_POSTGRESDB_HOST` | `postgres` | Docker service name for the database container |
| `DB_POSTGRESDB_PORT` | `5432` | Standard PostgreSQL port |
| `N8N_SECURE_COOKIE` | `false` | Allows non-HTTPS cookie handling (required for local/tunnel setups) |
| `N8N_COMMUNITY_PACKAGES_ENABLED` | `true` | Enables community node packages |
| `N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE` | `true` | Allows community nodes as LangChain tools |
| `NODE_FUNCTION_ALLOW_BUILTIN` | `fs` | Enables `require('fs')` in Code nodes (needed for config file loading) |
| `NODE_OPTIONS` | `--max-old-space-size=1536` | Node.js heap limit (prevents OOM on large workflows) |
| `EXECUTIONS_DATA_PRUNE` | `true` | Automatically prunes old execution data |
| `EXECUTIONS_DATA_MAX_AGE` | `720` | Maximum age of execution data in hours (30 days) |
| `EXECUTIONS_DATA_PRUNE_MAX_COUNT` | `10000` | Maximum number of stored executions |

## n8n Credentials

Credentials are created and managed in the n8n web UI (**Settings > Credentials**). They are not stored in configuration files — n8n encrypts them in its database using the `N8N_ENCRYPTION_KEY`.

| Credential Name | Type | Auth Method | Used By |
|----------------|------|-------------|---------|
| OpenRouter API | HTTP Header Auth | `Authorization: Bearer YOUR_KEY` | AI model calls, embedding generation |
| Postgres (Aerys DB) | Postgres | Host/port/database/user/password | Memory, identity, profiles, all application data |
| Discord Bot API | HTTP Header Auth | Bot token | Sending messages to Discord channels |
| Discord Bot Trigger | Discord API credentials | Bot token + webhook URL | Receiving messages from Discord |
| Telegram API | Telegram credentials | Bot token | Telegram adapter (send + receive) |
| Gmail — Full Access | OAuth2 | Client ID + Client Secret + Refresh Token | Email sub-agent: send, read, search |
| Gmail — Read Only | OAuth2 | Client ID + Client Secret + Refresh Token | Email trigger: inbox monitoring |
| Tavily API | HTTP Header Auth | API key | Research sub-agent: web search |

> **Two Gmail credentials:** The full-access credential operates the assistant's own inbox (send, read, search). The read-only credential monitors a user's inbox for the morning brief and email notifications. Both are optional — the email sub-agent only activates when Gmail credentials are configured.

> **Postgres credential target:** The application Postgres credential connects to the `aerys` database, not the `n8n` database. Both share the same PostgreSQL instance but serve different purposes. See [Schema Documentation](schema.md) for the database architecture.

## Docker Volumes

The `docker-compose.yml` mounts four host directories into the containers:

| Host Path | Container Path | Purpose | Access |
|-----------|---------------|---------|--------|
| `~/aerys/data/postgres` | `/var/lib/postgresql/data` | PostgreSQL data directory — all databases and tables | Read/write |
| `~/aerys/config/n8n` | `/home/node/.n8n` | n8n internal configuration — encrypted credentials, settings | Read/write |
| `~/aerys/config` | `/home/node/aerys-config` | Application config files (`soul.md`, `models.json`) | Read-only |
| `~/aerys/evals` | `/home/node/aerys-evals` | Evaluation test cases for the LLM-as-judge suite | Read-only |

Application config and eval files are mounted read-only to prevent accidental modification by workflow code.

### Backup Considerations

Critical data to back up:

- **`data/postgres/`** — contains all databases (n8n workflows, Aerys memories, identity records)
- **`config/n8n/`** — contains encrypted credentials (re-creating these requires re-entering all API keys)
- **`config/soul.md`** and **`config/models.json`** — personality and routing configuration

## Scripts

### discord-adapter-watcher.sh

**Location:** [`scripts/discord-adapter-watcher.sh`](../scripts/discord-adapter-watcher.sh)
**Purpose:** Manages Discord adapter activation order to prevent the IPC race condition

The Discord trigger nodes (guild adapter and DM adapter) share a single IPC process managed by the `katerlol` community package. When n8n starts or restarts, only the last-activated adapter registers with the IPC process. This script ensures both adapters register correctly by:

1. Waiting for n8n to pass health checks
2. Deactivating both Discord adapters
3. Activating the DM adapter first
4. Waiting 8 seconds for IPC stabilization
5. Activating the guild adapter last (this restarts the IPC process, which re-registers all active Discord trigger workflows)

The script watches for Docker container restart events and re-runs the fix sequence automatically. It is designed to run as a systemd user service for unattended operation:

```bash
# Example systemd user service (place in ~/.config/systemd/user/)
[Unit]
Description=Aerys Discord Adapter Watcher

[Service]
ExecStart=/path/to/scripts/discord-adapter-watcher.sh
Restart=always

[Install]
WantedBy=default.target
```

> **Note:** The script uses placeholder values (`YOUR_GUILD_ADAPTER_WORKFLOW_ID`, `YOUR_DM_ADAPTER_WORKFLOW_ID`, `YOUR_N8N_API_KEY`) that must be replaced with actual values from the local n8n instance.
