# Setup Guide

This guide covers everything needed to deploy a working Aerys instance: infrastructure prerequisites, API account setup, n8n credential configuration, workflow import order, and verification. By the end, Aerys will be processing messages across Discord, Telegram, and email with persistent memory, cross-platform identity, and multi-model AI routing.

## Prerequisites

### Infrastructure

- **Docker Engine 20.10+** and **Docker Compose v2** — all services run as containers
- **Git** — for cloning the repository
- **Linux host with 4GB+ RAM** — any Docker-capable machine works; tested on ARM64 (Qualcomm QCM6490) and x86_64

### API Accounts

Each integration requires its own API credentials. Core messaging needs the first three; the rest are optional.

| Service | Purpose | Required |
|---------|---------|----------|
| [OpenRouter](https://openrouter.ai) | Multi-model AI access (Gemini, Sonnet, Opus) | Yes |
| [Discord](https://discord.com/developers/applications) | Guild and DM messaging adapter | Yes |
| [Telegram](https://t.me/BotFather) | Telegram messaging adapter | Yes |
| [Gmail API](https://console.cloud.google.com) | Email sub-agent (read, search, send, morning brief) | Optional |
| [Tavily](https://tavily.com) | Research sub-agent (web search + synthesis) | Optional |

### Network

- A **publicly accessible HTTPS URL** for Discord and Telegram webhook callbacks. Options:
  - Domain with a reverse proxy and TLS certificate
  - [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) pointing to the local n8n port (5678)
- If running in a local-only configuration without webhooks, set `N8N_SECURE_COOKIE=false` in the environment

## Environment Setup

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/Aerys-Resonant-Span.git
cd Aerys-Resonant-Span
```

### 2. Configure Environment Variables

```bash
cp .env.example .env
```

Edit `.env` and fill in the values:

| Variable | Purpose | How to Generate |
|----------|---------|-----------------|
| `POSTGRES_USER` | Database username | Choose a username (default: `aerys`) |
| `POSTGRES_PASSWORD` | Database password | Generate a strong password |
| `N8N_ENCRYPTION_KEY` | Encrypts stored credentials at rest | `openssl rand -hex 32` |
| `WEBHOOK_URL` | Public URL for webhook callbacks | Your HTTPS domain with trailing slash |
| `N8N_EDITOR_BASE_URL` | n8n editor URL | Same domain, no trailing slash |
| `GENERIC_TIMEZONE` | System timezone | e.g., `America/New_York` |

See [`.env.example`](../.env.example) for the full template with inline documentation.

### 3. Start the Infrastructure

```bash
docker compose up -d
```

This starts two containers:

- **postgres** — pgvector-enabled PostgreSQL 16, with health checks and memory limits
- **n8n** — workflow automation platform, connected to Postgres for execution storage

### 4. Verify Startup

```bash
curl http://localhost:5678
```

The n8n web UI should be accessible. Create an admin account on first launch.

### 5. Database Migrations

Migrations run automatically on first start. The `migrations/` directory is mounted to PostgreSQL's `docker-entrypoint-initdb.d/`, which executes all `.sql` files in alphabetical order during initial database creation. This creates the Aerys application database with all required tables, indexes, and extensions.

See [`migrations/`](../migrations/) for the full migration set (8 files covering extensions, identity, memory, profiles, and sub-agents).

> **Note:** Migrations only run on a fresh database. If re-deploying with an existing data directory, apply new migrations manually through n8n's Postgres query nodes.

## API Key Setup

### OpenRouter (Required)

1. Create an account at [openrouter.ai](https://openrouter.ai)
2. Navigate to **Keys** and generate a new API key
3. Note the key — it will be used for the OpenRouter HTTP Header Auth credential in n8n
4. Fund the account with credits (usage-based pricing; Gemini Flash Lite is ~$0.10/M input tokens)

### Discord (Required)

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a **New Application** — note the Application ID
3. Navigate to **Bot** and create a bot — note the Bot Token
4. Under **Bot > Privileged Gateway Intents**, enable:
   - **Message Content Intent** (required for reading message text)
   - **Server Members Intent** (required for identity resolution)
5. Navigate to **OAuth2 > URL Generator**:
   - Select scopes: `bot`, `applications.commands`
   - Select permissions: `Send Messages`, `Read Message History`, `Use Slash Commands`
   - Use the generated URL to invite the bot to a server
6. Note the **Guild ID** (right-click server name > Copy Server ID with Developer Mode enabled)

### Telegram (Required)

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts to create a bot
3. Note the **Bot Token** provided by BotFather

### Gmail (Optional)

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project and enable the **Gmail API**
3. Create **OAuth 2.0 credentials** (Web application type)
4. Set the redirect URI to `https://your-domain.example.com/rest/oauth2-credential/callback`
5. Note the Client ID and Client Secret

Two Gmail credentials are used: one with full access (send + read for the assistant's own inbox) and one with read-only access (for monitoring a user's inbox).

### Tavily (Optional)

1. Create an account at [tavily.com](https://tavily.com)
2. Navigate to the dashboard and copy the API key

## n8n Credential Configuration

Credentials are created in the n8n web UI under **Settings > Credentials** (not in configuration files). Each credential type maps to one or more workflows.

| Credential Type | Auth Method | Used By |
|----------------|-------------|---------|
| **OpenRouter API** | HTTP Header Auth (`Authorization: Bearer YOUR_KEY`) | AI model calls, embedding generation |
| **Postgres (Aerys DB)** | Postgres connection (host: `postgres`, port: `5432`, database: `aerys`) | Memory, identity, profiles, all data access |
| **Discord Bot API** | Bot token | Sending messages via Discord API |
| **Discord Bot Trigger** | Bot token + webhook URL | Receiving messages from Discord |
| **Telegram API** | Bot token | Telegram adapter (send + receive) |
| **Gmail — Full Access** | OAuth2 (Client ID + Secret) | Email sub-agent: send, read, search |
| **Gmail — Read Only** | OAuth2 (Client ID + Secret) | Email trigger: inbox monitoring |
| **Tavily API** | API key (HTTP Header Auth) | Research sub-agent: web search |

> **Important:** The Postgres credential for Aerys data connects to the `aerys` database, not the `n8n` database. Both databases run on the same Postgres instance but serve different purposes. See [Schema Documentation](schema.md) for details.

## Workflow Creation Order

Workflows must be imported in dependency order — later workflows reference earlier ones via Execute Workflow nodes. After importing all workflows, update the `workflowId` values in each Execute Workflow node to match the IDs assigned by the local n8n instance.

Import the workflow JSON files from [`workflows/`](../workflows/) in this order:

### Phase 2: Core Messaging Loop

| # | File | Purpose |
|---|------|---------|
| 1 | `02-01-discord-adapter.json` | Discord guild message handler — normalizes incoming messages |
| 2 | `02-02-telegram-adapter.json` | Telegram message handler — normalizes incoming messages |
| 3 | `02-03-core-agent.json` | Central intent router — classifies messages and routes to model tiers |
| 4 | `02-04-output-router.json` | Platform-specific response formatting and delivery |

### Phase 3: Identity

| # | File | Purpose |
|---|------|---------|
| 5 | `03-01-identity-resolver.json` | Cross-platform person resolution — maps platform IDs to person records |
| 6 | `03-02-discord-slash-commands.json` | Discord slash command handler (`/link`, `/memory`, `/profile`) |
| 7 | `03-02-register-commands.json` | One-time execution — registers slash commands with Discord API |
| 8 | `03-03-discord-dm-adapter.json` | Discord DM handler — separate adapter for direct messages |

### Phase 4: Memory

| # | File | Purpose |
|---|------|---------|
| 9 | `04-02-memory-retrieval.json` | Hybrid memory search — pgvector similarity + keyword matching |
| 10 | `04-02-memory-batch-extraction.json` | Scheduled memory extraction from conversation history |
| 11 | `04-03-profile-api.json` | Per-person profile injection into AI prompts |
| 12 | `04-03-guardian.json` | Profile promotion — elevates recurring observations to core claims |
| 13 | `04-03-override-api.json` | Profile override management — user corrections to profile data |
| 14 | `04-03-memory-commands.json` | User-facing memory commands (`/memory search`, `/memory forget`) |

### Phase 5: Sub-Agents

| # | File | Purpose |
|---|------|---------|
| 15 | `05-01-media-sub-agent.json` | Image analysis, PDF/DOCX/TXT extraction, YouTube transcripts |
| 16 | `05-02-research-sub-agent.json` | Tavily web search with AI synthesis |
| 17 | `05-03-email-sub-agent.json` | Gmail integration — read, search, send, draft-then-confirm |
| 18 | `05-03-gmail-trigger.json` | Email trigger — monitors inbox for new messages |

### Phase 6: Reliability and Architecture

| # | File | Purpose |
|---|------|---------|
| 19 | `06-03-central-error.json` | Central error handler — catches failures, notifies debug channel |
| 20 | `06-05-sonnet-agent.json` | Sonnet tier sub-workflow (default conversational) |
| 21 | `06-05-opus-agent.json` | Opus tier sub-workflow (complex reasoning, daily cap) |
| 22 | `06-05-gemini-agent.json` | Gemini tier sub-workflow (fast, low-cost) |
| 23 | `06-05-pdf-extractor.json` | PDF content extraction tool |
| 24 | `06-05-docx-extractor.json` | DOCX content extraction tool |
| 25 | `06-05-youtube-extractor.json` | YouTube transcript extraction tool |

### Optional

| # | File | Purpose |
|---|------|---------|
| 26 | `06-01-eval-suite.json` | LLM-as-judge evaluation framework for regression testing |

### Post-Import Configuration

After importing all workflows:

1. **Update workflow references** — each Execute Workflow node contains a `workflowId` field that must be updated to match the IDs assigned by the local n8n instance
2. **Assign credentials** — open each workflow and assign the appropriate credentials to nodes that require them (Postgres, OpenRouter, Discord, etc.)
3. **Run the command registration** — execute `03-02-register-commands.json` once to register Discord slash commands
4. **Activate workflows** — activate all workflows in reverse dependency order (Phase 6 first, Phase 2 last) to avoid trigger race conditions

## Verification

After setup, verify the system is operational:

1. **Send a message in Discord** — mention the bot or send a message in a monitored channel. Aerys should respond within a few seconds.
2. **Send a message in Telegram** — the same person should be recognized if cross-platform identity linking has been configured (via the `/link` slash command in Discord).
3. **Check the debug channel** — if a `#debug` channel is configured, thought traces (model tier used, memory retrieved, intent classification) appear after each response.
4. **Verify memory extraction** — after several conversations, check that the batch extraction workflow is running on schedule and populating the memories table.

## Common Issues

### Discord Adapter IPC Race Condition

The Discord trigger nodes share an IPC process. If only one adapter (guild or DM) receives messages, the activation order was incorrect. The [`scripts/discord-adapter-watcher.sh`](../scripts/discord-adapter-watcher.sh) script automates the correct sequence:

1. Deactivate both adapters
2. Activate DM adapter first
3. Wait 8 seconds
4. Activate guild adapter last (this restarts the IPC process and re-registers both)

The script can be run as a systemd user service to automatically fix the race condition on every n8n restart.

### Webhook URL Not Accessible

Discord and Telegram require a publicly accessible HTTPS URL for webhook callbacks. If messages are not being received:

- Verify `WEBHOOK_URL` in `.env` points to a reachable HTTPS endpoint
- Confirm the reverse proxy or Cloudflare Tunnel is forwarding traffic to port 5678
- Check n8n logs for webhook registration errors

### Secure Cookie Errors

If the n8n UI fails to load or session cookies are rejected on non-HTTPS setups, the `N8N_SECURE_COOKIE` environment variable is already set to `false` in `docker-compose.yml`. Verify this setting has not been overridden.

### Memory Limits

The `docker-compose.yml` sets memory limits (2GB per container) and reservations (512MB). If containers are being OOM-killed on lower-memory hardware, adjust these values. The `NODE_OPTIONS: --max-old-space-size=1536` setting controls the Node.js heap for n8n.
