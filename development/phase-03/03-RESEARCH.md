# Phase 3: Identity - Research

**Researched:** 2026-02-21
**Domain:** Cross-platform identity mapping, verification code flows, PostgreSQL schema design, n8n command routing
**Confidence:** HIGH (schema extends existing live DB; patterns verified against live system and n8n docs)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Linking mechanism**
- Users self-link their accounts via a verification code flow
- Flow: user runs a link command on Platform A, receives a code, submits it on Platform B to confirm they control both
- One account per platform per person — no alt-account linking
- Pending verification codes expire after a time window (~10 minutes)
- No admin approval step required; the code itself is the proof of ownership

**Admin interface**
- Admin operations (force-link, unlink, inspect) are performed via bot commands sent to Aerys
- Admin status is determined by Discord role (a specific role grants elevated access)
- When an admin force-links two accounts, both affected users are notified on their respective platforms
- implementation discretion: whether to include a bot-side list command or rely on direct DB for audit

**Unlinked user behavior**
- Unlinked users are treated as full participants — no restrictions, no prompting to link
- When a user links their accounts, all past conversation history from both platform accounts is merged into the new canonical identity
- When a user unlinks, unified history is preserved as-is; new messages are tracked under platform-scoped IDs from that point forward
- Aerys may naturally acknowledge cross-platform awareness (e.g., "we talked about this on Discord") — identity resolution is not invisible infrastructure, it's part of Aerys's character

**Identity data scope**
- Store per person: canonical ID, platform IDs (discord_id, telegram_id), display name, metadata
- Display name: auto-populated from platform (Discord username / Telegram first name) and user-overridable via command (e.g., `!profile name Alice`)
- Metadata: JSONB catch-all for Phase 4 to populate — Phase 3 defines the column but not its schema
- Schema design, identity resolver placement, and user self-query scope: implementation discretion (design for Phase 4 compatibility)

### Implementation Discretion

- Schema design: whether to extend person_profiles or introduce a separate platform_identities join table
- Canonical ID format for unlinked users (e.g., `discord:123456` namespaced vs raw ID)
- Where the identity resolver runs in the n8n workflow graph (adapter-side vs Core Agent vs shared sub-workflow)
- Whether Phase 3 exposes a user self-query command — include only if it's needed by the linking flow itself

### Deferred Ideas (OUT OF SCOPE)

- Additional platform support (email, voice) as shared identity context — future phase (would extend the platform_identities pattern built here)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| IDEN-01 | A message from a user on Discord and a message from the same user on Telegram are linked to the same identity | Resolved by identity resolver sub-workflow: lookup by platform+user_id returns canonical person_id; upsert creates person row on first contact |
| IDEN-02 | Aerys does not treat a linked user as a stranger when they switch channels | Resolver returns same UUID for both platform IDs; history merge on link means past context survives; session_key stays person-scoped after linking |
| IDEN-03 | An admin can link or unlink platform accounts via a configurable mapping | Admin command router (in adapter) checks Discord role via REST API; routes to force-link/unlink handler that calls Postgres directly and notifies both users |
</phase_requirements>

---

## Summary

Phase 3 adds a cross-platform identity layer on top of the existing Phase 2 messaging infrastructure. The core mechanism is a verification code flow: a user issues `!link` on Platform A, gets a short-lived code, and redeems it on Platform B. Aerys stores the confirmed link in the existing `persons` table (which already has both `discord_id` and `telegram_id` columns). Every incoming message is routed through an **identity resolver sub-workflow** that turns raw platform user IDs into canonical person UUIDs before handing off to the Core Agent.

The existing schema from Phase 1 was explicitly designed for this phase: the `persons` table has UNIQUE columns for `discord_id` and `telegram_id`, both with partial indexes. No new top-level tables are strictly required — linking is just populating both platform columns on the same person row. However, a `pending_links` table is needed to hold unexpired verification codes between issuing and redeeming. A separate `platform_identities` join table is the more extensible design and should be introduced now to avoid a painful migration when Phase 5 adds additional platform types (Gmail sends to email, future voice).

The identity resolver is a shared sub-workflow called by both platform adapters. It does a single Postgres lookup (SELECT by discord_id OR telegram_id), upserts a new person row on first contact, and returns a canonical `person_id`. The adapters then include `person_id` in the normalized message payload that flows to the Core Agent and Output Router.

**Primary recommendation:** Two-table schema (`persons` + `platform_identities`), resolver as a shared sub-workflow called from both adapters, command detection in adapter Code nodes before routing to Core Agent.

---

## Standard Stack

### Core

| Library / Node | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| PostgreSQL (existing) | 16 | Canonical identity store | Already live; `persons` table has discord_id/telegram_id columns with UNIQUE constraints |
| n8n Postgres node | built-in | SELECT, INSERT, upsert from workflows | Used in Phase 2 for Opus counter; proven working |
| n8n Execute Sub-workflow node | built-in | Identity resolver called from both adapters | Same pattern as Core Agent → Output Router call in Phase 2 |
| n8n HTTP Request node | built-in | Discord REST API for role check (guild member) | Bot token credential already stored in n8n |
| n8n Code node | built-in | Command detection, code generation, link merging | Phase 2 Code nodes proven; avoids shell-escaping traps |

### Supporting

| Library / Node | Purpose | When to Use |
|---------------|---------|-------------|
| `crypto.randomBytes` (Node.js built-in, available in n8n Code node) | Generate verification codes | Generate 6-char alphanumeric code in Code node — no npm dependency needed |
| Discord REST API `GET /guilds/{guild_id}/members/{user_id}` | Fetch guild member to check roles array | Admin role check — HTTP Request node with bot token header |
| Telegram `getChatMember` API | Check Telegram admin status (future) | Not needed for Phase 3 — admin role is Discord-only per decisions |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `platform_identities` join table | Extending `persons` with more platform columns directly | Join table wins: extensible to email/voice without schema changes; avoids ALTER TABLE in Phase 5 |
| Sub-workflow resolver | Inline Postgres SELECT in each adapter | Sub-workflow wins: single source of truth, easier to update, consistent behavior across platforms |
| 6-char alphanumeric code | UUID token | Short code wins: user types it cross-platform; UUID is 36 chars, unusable for manual entry |
| Postgres node "Insert or Update" for upsert | Execute Query with ON CONFLICT | n8n's built-in "Insert or Update" is reliable for simple upserts; use it for `persons`; use Execute Query with parameterized SQL for complex multi-step operations |

**Installation:** No new packages needed. All operations use existing n8n built-in nodes and the existing PostgreSQL instance.

---

## Architecture Patterns

### Recommended Project Structure

```
migrations/
├── 001_init.sql           (exists — persons, conversations, messages, memories)
└── 002_identity.sql       (new — platform_identities, pending_links tables)

workflows/
├── 02-01-discord-adapter.json    (exists — add command detection + resolver call)
├── 02-02-telegram-adapter.json   (exists — add resolver call)
├── 02-03-core-agent.json         (no changes needed)
├── 02-04-output-router.json      (no changes needed)
└── 03-01-identity-resolver.json  (new sub-workflow)
```

### Pattern 1: Platform Identities Join Table

**What:** A separate `platform_identities` table with `(person_id, platform, platform_user_id)` rows. Each person can have one identity per platform. The existing `persons.discord_id` and `persons.telegram_id` columns are kept for backward compatibility during Phase 3 but the authoritative store moves to `platform_identities`.

**When to use:** Any time a new platform is added. Resolver queries `platform_identities` first; falls back to `persons` columns for backward-compat rows already written by Phase 2.

**Recommended schema:**

```sql
-- Migration 002_identity.sql

\c aerys

-- Extensible platform identity store
CREATE TABLE IF NOT EXISTS platform_identities (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id   UUID NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    platform    TEXT NOT NULL,              -- 'discord', 'telegram', 'email'
    platform_user_id TEXT NOT NULL,        -- raw platform ID (Discord snowflake, Telegram int, etc.)
    username    TEXT,                      -- display name from platform at time of link
    linked_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (platform, platform_user_id)    -- one account per platform per person
);

CREATE INDEX idx_platform_identities_person ON platform_identities(person_id);
CREATE INDEX idx_platform_identities_lookup ON platform_identities(platform, platform_user_id);

-- Temporary code store for verification flow
CREATE TABLE IF NOT EXISTS pending_links (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code        TEXT NOT NULL UNIQUE,
    person_id   UUID NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    platform    TEXT NOT NULL,             -- platform where code was issued
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_pending_links_code ON pending_links(code);
CREATE INDEX idx_pending_links_expires ON pending_links(expires_at);
```

### Pattern 2: Identity Resolver Sub-Workflow

**What:** A dedicated sub-workflow `03-01-identity-resolver` called by both Discord and Telegram adapters immediately after Normalize Message. Accepts `{platform, platform_user_id, username}`, returns `{person_id, is_new}`.

**When to use:** Every incoming message. Runs synchronously (waitForSubWorkflow: true).

**Flow inside resolver:**
1. Postgres SELECT from `platform_identities` WHERE `platform = $1 AND platform_user_id = $2`
2. If found: return `{person_id: row.person_id, is_new: false}`
3. If not found: INSERT into `persons` (display_name = username), then INSERT into `platform_identities`. Return `{person_id: new_id, is_new: true}`

**Key constraint:** Use parameterized queries (`$1`, `$2` placeholders with Query Parameters field). Do not string-interpolate platform_user_id into SQL — Discord snowflakes are long integers that can cause type coercion issues, and SQL injection risk exists for username field.

```javascript
// Code node: Resolve or Create Person
const platform = $input.item.json.platform;         // 'discord' or 'telegram'
const platformUserId = $input.item.json.platform_user_id;  // string
const username = $input.item.json.username || 'Unknown';

return [{ json: { platform, platform_user_id: platformUserId, username } }];
```

```sql
-- Execute Query: lookup
SELECT pi.person_id, p.display_name
FROM platform_identities pi
JOIN persons p ON p.id = pi.person_id
WHERE pi.platform = $1 AND pi.platform_user_id = $2
LIMIT 1;
```

### Pattern 3: Command Detection in Adapter

**What:** A Code node placed BEFORE the resolver call that checks if the normalized message is a command (`!link`, `!unlink`, `!profile`, `!admin`). Commands bypass the Core Agent and go directly to a command handler Code node, then reply directly.

**When to use:** In both Discord and Telegram adapters. Commands are identified by prefix (`!` or `/` for Telegram native slash commands).

**Flow:**

```
Normalize Message
       ↓
Detect Command (Code node)
       ↓
    Switch node
   /          \
Commands    Chat (normal flow)
   ↓               ↓
Resolve Identity   Resolve Identity (sub-workflow)
   ↓               ↓
Command Router  Core Agent
```

**Command detection pattern:**

```javascript
// Code node: Detect Command
const msg = $input.item.json;
const text = msg.message_text.trim();

const COMMAND_PREFIX = '!';
const isCommand = text.startsWith(COMMAND_PREFIX);

let command = null;
let args = [];

if (isCommand) {
  const parts = text.slice(1).split(/\s+/);
  command = parts[0].toLowerCase();   // 'link', 'unlink', 'profile', 'admin'
  args = parts.slice(1);
}

return [{ json: { ...msg, is_command: isCommand, command, command_args: args } }];
```

**Supported commands (Phase 3):**

| Command | Platform | Auth | Action |
|---------|----------|------|--------|
| `!link` | both | any user | Issue/redeem verification code |
| `!unlink` | both | own account | Unlink own accounts |
| `!profile name <name>` | both | own account | Override display name |
| `!admin link <discord_id> <telegram_id>` | Discord only | admin role | Force-link two accounts |
| `!admin unlink <platform> <id>` | Discord only | admin role | Force-unlink an account |

### Pattern 4: Admin Role Check via Discord REST API

**What:** Before executing any `!admin` command, verify the issuer has the designated admin Discord role. Use the Discord REST API (`GET /guilds/{guild_id}/members/{user_id}`) via HTTP Request node. Compare returned `roles` array against a hardcoded (or n8n variable) admin role ID.

**Key facts:**
- Endpoint: `GET https://discord.com/api/v10/guilds/{guild_id}/members/{user_id}`
- Auth header: `Authorization: Bot {token}`
- Response includes `roles: ["role_id_1", "role_id_2", ...]`
- Bot must have SERVER MEMBERS INTENT enabled (already enabled in Phase 2 setup via katerlol node)
- The same Bot API credential (`YOUR_DISCORD_BOT_CREDENTIAL_ID`) already stored in n8n can be used for raw HTTP calls

```javascript
// Code node: Check Admin Result
const memberData = $input.item.json;
const ADMIN_ROLE_ID = 'YOUR_ROLE_ID_HERE';  // hardcoded or n8n variable

const roles = memberData.roles || [];
const isAdmin = roles.includes(ADMIN_ROLE_ID);

if (!isAdmin) {
  return [{ json: { ...memberData, _admin_denied: true } }];
}

return [{ json: { ...memberData, _admin_allowed: true } }];
```

**n8n variable for admin role ID:** Store as n8n variable (Settings > Variables) so it's configurable without editing nodes. Reference as `$vars.AERYS_ADMIN_ROLE_ID`. This avoids the `process.env` sandbox block.

### Pattern 5: Verification Code Flow

**What:** User on Platform A runs `!link`. Aerys generates a 6-character alphanumeric code, inserts into `pending_links` with a 10-minute expiry, and replies with the code. User then runs `!link <code>` on Platform B. Aerys looks up the code, confirms it's unexpired, merges the identities, deletes the pending row, and notifies the user on Platform B.

**Code generation (in n8n Code node — crypto is available):**

```javascript
// Generate 6-char alphanumeric code
const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  // remove confusable chars
let code = '';
const buf = require('crypto').randomBytes(6);
for (let i = 0; i < 6; i++) {
  code += chars[buf[i] % chars.length];
}
// code is now e.g. "K7MN2P"
return [{ json: { code, expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString() } }];
```

**Issue flow SQL:**

```sql
-- Insert pending link (parameterized)
INSERT INTO pending_links (code, person_id, platform, expires_at)
VALUES ($1, $2, $3, $4);
```

**Redeem flow SQL:**

```sql
-- Find valid pending link
SELECT pl.person_id as source_person_id, pl.platform as source_platform
FROM pending_links pl
WHERE pl.code = $1 AND pl.expires_at > NOW();
```

**Identity merge on redeem:**

If the redeeming user already has a `person_id` (they've chatted on Platform B before), a merge is needed:
1. The newer person row is the "loser" (typically the Platform B person)
2. UPDATE `platform_identities` SET `person_id = winner_id` WHERE `person_id = loser_id`
3. UPDATE `conversations`, `messages`, `memories` SET `person_id = winner_id` WHERE `person_id = loser_id`
4. DELETE the loser `persons` row (or soft-delete by setting `deleted_at`)
5. UPDATE `persons` SET `telegram_id = <value>` (for backward compat columns) WHERE `id = winner_id`
6. DELETE from `pending_links` WHERE `code = $1`

This merge is a multi-step transaction. Use a single Code node that builds all the SQL statements and executes them via separate Postgres nodes in sequence (n8n does not have a native transaction wrapper, but these are idempotent writes on distinct rows — partial failure is recoverable by re-running link).

**Alternative:** Execute the entire merge as a single stored procedure or DO block via Execute Query:

```sql
-- Single atomic merge via DO block
DO $$
DECLARE
    v_winner UUID := $1;  -- source person (Platform A)
    v_loser  UUID := $2;  -- target person (Platform B, may be same if new user)
BEGIN
    IF v_winner = v_loser THEN RETURN; END IF;
    UPDATE platform_identities SET person_id = v_winner WHERE person_id = v_loser;
    UPDATE conversations SET person_id = v_winner WHERE person_id = v_loser;
    UPDATE messages SET person_id = v_winner WHERE person_id = v_loser;
    UPDATE memories SET person_id = v_winner WHERE person_id = v_loser;
    UPDATE persons SET deleted_at = NOW() WHERE id = v_loser;
END;
$$;
```

Note: n8n's Postgres node "Execute Query" supports DO blocks. Test this in the live DB first since DO blocks with parameters use `$1` syntax that overlaps with n8n's Query Parameters token system — may need to use a Code node with `$node["Postgres"].item` pattern or pass values differently.

### Anti-Patterns to Avoid

- **Inline SQL string interpolation:** Never build SQL by concatenating `platform_user_id` or `username` directly into a query string. Use `$1`/`$2` parameters with the Query Parameters field.
- **Identity resolver inline in each adapter:** Don't duplicate the lookup SQL in both Discord and Telegram adapters. One sub-workflow, two callers.
- **Blocking the Core Agent with command logic:** Commands (`!link`, `!admin`) should be fully handled in the adapter tier and never reach the Core Agent. The Core Agent should receive only chat messages with a resolved `person_id`.
- **Hardcoding admin role ID in workflow nodes:** Use n8n variables (`$vars.AERYS_ADMIN_ROLE_ID`) — role IDs change when Discord servers are rebuilt.
- **Deleting pending_links rows only on success:** Always DELETE expired codes on every redeem attempt (success or fail) to prevent accumulation. A periodic cleanup is ideal; a WHERE `expires_at < NOW()` DELETE at the start of each redeem flow is sufficient for v1.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Time-limited token storage | In-memory expiry, Redis, external cache | `pending_links` Postgres table with `expires_at` column | PostgreSQL is already the DB of record; add `WHERE expires_at > NOW()` to every lookup; cleanup on read |
| Secure code generation | Math.random(), timestamp-based codes | `crypto.randomBytes()` available in n8n Code node | Math.random is predictable; crypto.randomBytes is CSPRNG |
| Admin permission system | Custom role table, separate auth service | Discord REST API + n8n variable for role ID | Discord already manages roles; one HTTP call is sufficient |
| Identity merge transaction | Manual Postgres client transactions | PostgreSQL DO block (PL/pgSQL) via Execute Query | Atomicity without needing application-level transaction management |
| Command routing | AI intent classification for commands | Code node with prefix check (`startsWith('!')`) | Commands are deterministic; AI adds latency and cost where it's unnecessary |

**Key insight:** The `persons` table and its indexes were purpose-built in Phase 1 for exactly this phase. The heavy lifting (unique constraints, partial indexes on platform IDs) is already deployed — Phase 3 is wiring identity lookup into the message flow, not building a new persistence layer from scratch.

---

## Common Pitfalls

### Pitfall 1: n8n Query Parameters Comma-Split Bug

**What goes wrong:** When using the Query Parameters field in n8n's Postgres Execute Query node, if any parameter value contains a comma (e.g., a display name like "Smith, John"), n8n splits it into two parameters, misaligning `$1`/`$2` positions.

**Why it happens:** The Query Parameters field expects a comma-delimited list when provided as a string expression. Display names, messages, and platform usernames can contain commas.

**How to avoid:** Pass Query Parameters as a JavaScript array, not a comma-separated string. Or use the built-in "Insert or Update" operation for simple upserts where possible. For complex SQL where you must use Execute Query, build a Code node that does the INSERT/UPDATE using a Postgres Code approach or ensures values are array-encoded.

**Warning signs:** SQL parameter mismatch errors (`$2 not found`, `parameter count mismatch`) when usernames contain commas.

### Pitfall 2: n8n Code Node Sandbox — No `process.env` or `$env`

**What goes wrong:** Trying to read the admin role ID or any config from environment variables in a Code node results in undefined/error.

**Why it happens:** n8n sandboxes Code nodes; both `process.env` and `$env` are blocked.

**How to avoid:** Use n8n Variables (Settings > Variables > create `AERYS_ADMIN_ROLE_ID`). Reference as `$vars.AERYS_ADMIN_ROLE_ID` in expressions. For Code nodes specifically, pass the variable via a Set node upstream and reference via `$input.item.json.admin_role_id`.

**Warning signs:** `process.env.ADMIN_ROLE_ID` returns `undefined` silently; `$env` throws.

### Pitfall 3: Persons Table Backward-Compat Columns

**What goes wrong:** Phase 2 may have written rows to `persons` using the `discord_id` and `telegram_id` columns directly (future memory pipeline in Phase 4 will likely do this). If Phase 3 adds `platform_identities` but doesn't backfill from `persons`, the resolver may create duplicate person rows.

**Why it happens:** Two sources of truth for the same identity data.

**How to avoid:** The resolver should check BOTH `platform_identities` AND the legacy `persons.discord_id`/`persons.telegram_id` columns, in that order. On first match via legacy column, migrate that row to `platform_identities` and continue. OR: write migration 002 to backfill all existing `persons` rows with `discord_id`/`telegram_id` set into `platform_identities` at migration time.

**Warning signs:** Two `persons` rows with the same real user; Aerys greets the same person as a stranger after linking.

**Current state (verified live):** The `persons` table is empty (0 rows) as of 2026-02-21 — no active Phase 2 data to backfill. The migration can be written without backfill concern for now, but the resolver should still check both columns for future safety.

### Pitfall 4: Discord katerlol Trigger Doesn't Expose Member Roles in Event Payload

**What goes wrong:** The Discord message trigger event payload (`raw.author`) includes `id`, `username`, `globalName` but NOT the sender's guild roles. Checking `raw.member.roles` may be undefined depending on the event type.

**Why it happens:** The katerlol node's message event does not guarantee full guild member data in all event types.

**How to avoid:** Always fetch guild member roles explicitly via Discord REST API (`GET /guilds/{guild_id}/members/{user_id}`) using an HTTP Request node when admin role check is required. Don't rely on the trigger payload's roles field. The `guild_id` is already in the normalized message (`msg.guild_id`).

**Warning signs:** `raw.member` is undefined or `raw.member.roles` is an empty array for commands sent from a server.

### Pitfall 5: Sub-Workflow Timing — Resolver Must Return Before Core Agent Runs

**What goes wrong:** If the identity resolver sub-workflow is called asynchronously, the Core Agent receives the message without a `person_id` and can't route memory correctly.

**Why it happens:** Forgetting to set `waitForSubWorkflow: true` in the Execute Sub-workflow node.

**How to avoid:** Always set `waitForSubWorkflow: true` in the Execute Sub-workflow node parameters. This is the same pattern already used by both adapters when calling the Core Agent (verified in Phase 2 workflow JSON: `"waitForSubWorkflow": true`).

**Warning signs:** `person_id` is null or missing in Core Agent input; memory session_key uses raw platform ID instead of canonical UUID.

### Pitfall 6: DO Block Parameter Syntax Conflict with n8n Query Parameters

**What goes wrong:** PostgreSQL DO blocks use `$1`, `$2` internally for PL/pgSQL anonymous procedures, which conflicts with n8n's Query Parameters token system. Passing parameters into a DO block via n8n's Execute Query may produce syntax errors or incorrect binding.

**Why it happens:** n8n replaces `$1` tokens with Query Parameter values before sending to Postgres. Inside a DO block, `$1` has no meaning (DO blocks don't take parameters). The result is a malformed query.

**How to avoid:** For the identity merge operation, either:
1. Use individual Postgres node steps in sequence (UPDATE platform_identities → UPDATE conversations → UPDATE messages → UPDATE memories → soft-delete persons) — each step is a simple parameterized query
2. Or create a real PostgreSQL function (stored procedure) that takes parameters and call it with `SELECT merge_identities($1, $2)` — functions do accept `$1`/`$2` parameter binding from n8n

**Recommendation for Phase 3:** Use sequential individual Postgres nodes (5 steps). Simpler to debug, no stored procedure maintenance. Acceptable for the rare merge event.

---

## Code Examples

Verified patterns from the live system and official sources:

### Identity Resolver: Lookup with Parameterized Query

```sql
-- Source: n8n Postgres node Execute Query, Query Parameters = ["discord", "123456789"]
SELECT pi.person_id, p.display_name
FROM platform_identities pi
JOIN persons p ON p.id = pi.person_id
WHERE pi.platform = $1 AND pi.platform_user_id = $2
LIMIT 1;
```

### Identity Resolver: Upsert New Person (n8n Postgres "Insert or Update")

Use n8n's built-in "Insert or Update" operation on `persons` table:
- Operation: Insert or Update
- Conflict column: (use Execute Query instead — "Insert or Update" requires a unique column name, use `id` or generate UUID in Code node first)
- Preferred: INSERT via Execute Query with ON CONFLICT:

```sql
-- Parameterized INSERT with conflict ignore (safe for n8n with array params)
-- Query Parameters (as array): [display_name]
INSERT INTO persons (display_name)
VALUES ($1)
RETURNING id, display_name;
```

Then INSERT into platform_identities:

```sql
-- Query Parameters: [person_id, platform, platform_user_id, username]
INSERT INTO platform_identities (person_id, platform, platform_user_id, username)
VALUES ($1, $2, $3, $4)
ON CONFLICT (platform, platform_user_id) DO NOTHING
RETURNING id, person_id;
```

### Command Detection in Adapter (Code Node)

```javascript
// Source: Phase 2 pattern — extended for command detection
const msg = $input.item.json;
const text = (msg.message_text || '').trim();

const isCommand = text.startsWith('!');
let command = null;
let commandArgs = [];

if (isCommand) {
  const parts = text.slice(1).trim().split(/\s+/);
  command = parts[0].toLowerCase();
  commandArgs = parts.slice(1);
}

return [{
  json: {
    ...msg,
    is_command: isCommand,
    command: command,          // null for non-commands
    command_args: commandArgs  // [] for non-commands
  }
}];
```

### Verification Code Generation (Code Node)

```javascript
// crypto.randomBytes is available in n8n Code nodes (Node.js built-in, not sandboxed)
const crypto = require('crypto');
const CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  // omit 0,O,1,I for readability
const buf = crypto.randomBytes(6);
let code = '';
for (let i = 0; i < 6; i++) {
  code += CHARS[buf[i] % CHARS.length];
}
const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

return [{ json: { verification_code: code, expires_at: expiresAt } }];
```

### Discord Admin Role Check (HTTP Request Node)

```
Method: GET
URL: https://discord.com/api/v10/guilds/{{ $json.guild_id }}/members/{{ $json.user_id }}
Headers:
  Authorization: Bot {{ $credentials.discordBotApi.token }}
```

Then in Code node:
```javascript
const member = $input.item.json;
const adminRoleId = $vars.AERYS_ADMIN_ROLE_ID;  // n8n variable
const roles = member.roles || [];
const isAdmin = roles.includes(adminRoleId);
return [{ json: { ...member, _is_admin: isAdmin } }];
```

### Expired Code Cleanup (Execute Query — run at start of every redeem attempt)

```sql
-- Query Parameters: [] (no parameters)
DELETE FROM pending_links WHERE expires_at < NOW();
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Storing platform IDs directly on persons table | `platform_identities` join table | Phase 3 design | Enables future platforms without schema changes |
| n8n `process.env` for config | n8n Variables (`$vars.*`) | n8n 2.x | Variables survive upgrades and are UI-configurable |
| Trust trigger payload for member roles | Fetch guild member via REST on demand | n8n community node limitation | Required for accurate role checks |

**Deprecated/outdated:**
- `persons.discord_id` / `persons.telegram_id` columns: Keep for backward compat but treat as secondary; `platform_identities` is the authoritative store from Phase 3 forward
- Basic Auth for n8n (`N8N_BASIC_AUTH_*`): Already removed in Phase 1 (deprecated in n8n 2.x)

---

## Open Questions

1. **Admin role ID configuration**
   - What we know: Admin check uses a Discord role ID; role IDs are server-specific
   - What's unclear: The specific role ID for the admin role on the target Discord server — must be looked up from the Discord server settings
   - Recommendation: Store in n8n Variables as `AERYS_ADMIN_ROLE_ID` so the plan can reference `$vars.AERYS_ADMIN_ROLE_ID` without hardcoding; plan step should include "set this variable to your admin role ID"

2. **Whether Phase 3 needs a `!whoami` / self-query command**
   - What we know: CONTEXT.md says "include only if needed by the linking flow itself"
   - What's unclear: The linking flow doesn't strictly require it, but it's useful for users to confirm their linking status
   - Recommendation: Implement `!status` (shows: linked accounts, display name) as it's trivially implemented alongside the link commands and reduces user confusion; 1 Postgres SELECT, 1 Code node

3. **Session key after linking**
   - What we know: Phase 2 uses `session_key: 'discord_' + channelId` for Postgres Chat Memory; after linking, the same person has two session keys
   - What's unclear: Should session_key change to `person:UUID` after linking, or remain channel-scoped?
   - Recommendation: Keep session_key channel-scoped for now (it's the n8n Postgres Chat Memory `sessionId`). Phase 4 memory system will unify this properly. The identity resolver provides `person_id` for profile lookup; short-term conversational memory can stay channel-scoped without breaking Phase 3's success criteria.

4. **Notification dispatch to both platforms after admin force-link**
   - What we know: Admin force-link must notify both users on their respective platforms
   - What's unclear: The Output Router currently dispatches based on `source_channel` field from the incoming message. Force-link notifications must go to TWO different channels (Discord + Telegram) from a single workflow execution.
   - Recommendation: In the admin force-link handler, make two separate HTTP API calls (one to Discord send endpoint, one to Telegram sendMessage endpoint) directly from Code nodes, bypassing the Output Router. This is simpler than making the Output Router multi-target aware.

---

## Sources

### Primary (HIGH confidence)

- Live aerys DB schema (`docker exec aerys-postgres-1 psql`) — `persons`, `conversations`, `messages`, `memories` table structure confirmed; persons table is empty (0 rows)
- Phase 2 workflow JSON exports (`~/aerys/workflows/02-01-discord-adapter.json`, `02-03-core-agent.json`) — normalized message schema, Execute Sub-workflow pattern, Code node patterns confirmed
- Phase 1 migration files (`~/aerys/migrations/001_init.sql`) — existing schema design intent confirmed
- n8n Postgres node docs (GitHub n8n-docs) — 6 operations: Delete, Execute Query, Insert, Insert or Update, Select, Update; Query Parameters use `$1`/`$2` placeholders with SQL injection prevention
- n8n Sub-workflows docs — Execute Sub-workflow + Execute Sub-workflow Trigger pattern; `waitForSubWorkflow: true` is the correct synchronous call pattern

### Secondary (MEDIUM confidence)

- n8n community forum — Query Parameters comma-split bug confirmed (multiple reports 2024-2025); workaround: pass as JS array not comma-separated string; "Insert or Update" operation more reliable than raw ON CONFLICT for simple cases
- Discord REST API docs — `GET /guilds/{guild_id}/members/{user_id}` returns `roles: [role_id, ...]`; bots cannot use `/guilds/{id}/roles/{role_id}/member-ids` (403)
- Telegram Bot API — `getChatMember` for group membership check; not needed for Phase 3 (admin is Discord-only)

### Tertiary (LOW confidence)

- n8n Code node crypto availability: `require('crypto')` believed available based on Node.js sandbox knowledge, but not tested in this specific n8n version on Tachyon. Verify in first plan step before building the code generation logic on it.
- PostgreSQL DO block parameter conflict with n8n Query Parameters: inferred from known Query Parameters token behavior; not tested with DO blocks specifically. Use sequential individual nodes as the safe alternative.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all nodes are existing Phase 2 nodes; schema is live and verified
- Architecture: HIGH — patterns follow Phase 2's proven sub-workflow and Code node conventions
- Pitfalls: MEDIUM-HIGH — bugs verified from community (comma issue, env block); katerlol roles behavior inferred from source inspection
- Open questions: LOW-MEDIUM — session key and multi-channel notification are genuinely uncertain; flagged for planner decision

**Research date:** 2026-02-21
**Valid until:** 2026-04-21 (stable stack; n8n patch versions may shift but node APIs are stable)
