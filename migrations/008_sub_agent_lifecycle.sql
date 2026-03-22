-- Migration 008: Sub-agent lifecycle state + dependency declarations
-- Source: p6-sub-agent-lifecycle-state.md + p6-sub-agent-dependency-declarations.md
-- Purpose: Add state column (ready/failed/disabled) for health-aware tool routing
--          Add dependencies JSONB column for service dependency declarations

ALTER TABLE sub_agents ADD COLUMN IF NOT EXISTS state TEXT NOT NULL DEFAULT 'ready';
ALTER TABLE sub_agents ADD COLUMN IF NOT EXISTS dependencies JSONB DEFAULT '[]';

-- Add check constraint (idempotent via DO block)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sub_agents_state_check'
  ) THEN
    ALTER TABLE sub_agents ADD CONSTRAINT sub_agents_state_check
      CHECK (state IN ('ready', 'failed', 'disabled'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sub_agents_state ON sub_agents(state);

-- Populate dependencies for existing agents
UPDATE sub_agents SET dependencies = '[
  {"service": "openrouter", "credential_id": "YOUR_OPENROUTER_CREDENTIAL_ID", "optional": false}
]'::jsonb WHERE capability_id = 'media';

UPDATE sub_agents SET dependencies = '[
  {"service": "tavily", "credential_id": "YOUR_TAVILY_CREDENTIAL_ID", "optional": false}
]'::jsonb WHERE capability_id = 'research.web';

UPDATE sub_agents SET dependencies = '[
  {"service": "gmail_aerys", "credential_id": "YOUR_GMAIL_AERYS_CREDENTIAL_ID", "optional": false},
  {"service": "gmail_user", "credential_id": "YOUR_GMAIL_USER_CREDENTIAL_ID", "optional": true}
]'::jsonb WHERE capability_id = 'email';
