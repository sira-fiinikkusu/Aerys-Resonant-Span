# Phase 3: Identity - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Build a cross-platform identity system that maps Discord and Telegram user accounts to a single canonical person, maintains a unified profile per person, and exposes user-initiated linking and admin management via bot commands. Aerys uses the canonical identity on every message. Adding new platform types (email, voice) belongs in a future phase.

</domain>

<decisions>
## Implementation Decisions

### Linking mechanism
- Users self-link their accounts via a verification code flow
- Flow: user runs a link command on Platform A, receives a code, submits it on Platform B to confirm they control both
- One account per platform per person — no alt-account linking
- Pending verification codes expire after a time window (~10 minutes)
- No admin approval step required; the code itself is the proof of ownership

### Admin interface
- Admin operations (force-link, unlink, inspect) are performed via bot commands sent to Aerys
- Admin status is determined by Discord role (a specific role grants elevated access)
- When an admin force-links two accounts, both affected users are notified on their respective platforms
- Claude's discretion: whether to include a bot-side list command or rely on direct DB for audit

### Unlinked user behavior
- Unlinked users are treated as full participants — no restrictions, no prompting to link
- When a user links their accounts, all past conversation history from both platform accounts is merged into the new canonical identity
- When a user unlinks, unified history is preserved as-is; new messages are tracked under platform-scoped IDs from that point forward
- Aerys may naturally acknowledge cross-platform awareness (e.g., "we talked about this on Discord") — identity resolution is not invisible infrastructure, it's part of Aerys's character

### Identity data scope
- Store per person: canonical ID, platform IDs (discord_id, telegram_id), display name, metadata
- Display name: auto-populated from platform (Discord username / Telegram first name) and user-overridable via command (e.g., `!profile name Alice`)
- Metadata: JSONB catch-all for Phase 4 to populate — Phase 3 defines the column but not its schema
- Schema design, identity resolver placement, and user self-query scope: Claude's discretion (design for Phase 4 compatibility)

### Claude's Discretion
- Schema design: whether to extend person_profiles or introduce a separate platform_identities join table
- Canonical ID format for unlinked users (e.g., `discord:123456` namespaced vs raw ID)
- Where the identity resolver runs in the n8n workflow graph (adapter-side vs Core Agent vs shared sub-workflow)
- Whether Phase 3 exposes a user self-query command — include only if it's needed by the linking flow itself

</decisions>

<specifics>
## Specific Ideas

- Verification code flow is the core of user-initiated linking — code issued on Platform A, redeemed on Platform B
- Aerys naturally referencing cross-platform context is intentional and desirable (not hidden plumbing)
- Display name override command pattern: `!profile name <name>`

</specifics>

<deferred>
## Deferred Ideas

- Additional platform support (email, voice) as shared identity context — future phase (would extend the platform_identities pattern built here)

</deferred>

---

*Phase: 03-identity*
*Context gathered: 2026-02-20*
