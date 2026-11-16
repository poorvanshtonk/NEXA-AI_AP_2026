-- NEXA AI database schema for CP2.
-- these tables describe the planned database-backed version.

BEGIN;

CREATE TABLE users (
    user_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL CHECK (length(btrim(name)) > 0),
    city         TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Model options differ by provider, so they stay in a JSONB object until the
-- project has stable fields that need to be queried or constrained.
CREATE TABLE ai_models (
    model_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider       TEXT NOT NULL CHECK (length(btrim(provider)) > 0),
    model_name     TEXT NOT NULL CHECK (length(btrim(model_name)) > 0),
    model_version  TEXT NOT NULL DEFAULT '',
    configuration  JSONB NOT NULL DEFAULT '{}'::jsonb
                   CHECK (jsonb_typeof(configuration) = 'object'),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_ai_models_identity UNIQUE (provider, model_name, model_version)
);

CREATE TABLE conversations (
    conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    model_id        UUID REFERENCES ai_models(model_id) ON DELETE SET NULL,
    title           TEXT NOT NULL DEFAULT 'New conversation',
    is_archived     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_conversations_title CHECK (length(btrim(title)) > 0)
);

CREATE TABLE messages (
    message_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    message_order   INTEGER NOT NULL CHECK (message_order > 0),
    role            TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'tool')),
    content         TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_messages_conversation_order UNIQUE (conversation_id, message_order)
);

CREATE TABLE user_preferences (
    user_id          UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    preference_key   TEXT NOT NULL CHECK (length(btrim(preference_key)) > 0),
    preference_value TEXT NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, preference_key)
);

CREATE TABLE user_devices (
    device_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    device_name TEXT NOT NULL CHECK (length(btrim(device_name)) > 0),
    device_type TEXT NOT NULL CHECK (length(btrim(device_type)) > 0),
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'connected', 'disconnected', 'revoked')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tool_integrations (
    tool_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tool_code    TEXT NOT NULL UNIQUE CHECK (length(btrim(tool_code)) > 0),
    display_name TEXT NOT NULL CHECK (length(btrim(display_name)) > 0),
    category     TEXT NOT NULL CHECK (length(btrim(category)) > 0),
    is_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Tool inputs vary from one integration to another. Keep the run metadata in
-- columns and store each integration's input as an object-valued JSONB payload.
CREATE TABLE tool_invocations (
    invocation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id    UUID NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
    tool_id       UUID NOT NULL REFERENCES tool_integrations(tool_id) ON DELETE RESTRICT,
    status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'succeeded', 'failed', 'cancelled')),
    input_payload JSONB NOT NULL DEFAULT '{}'::jsonb
                  CHECK (jsonb_typeof(input_payload) = 'object'),
    output_text   TEXT,
    started_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at  TIMESTAMPTZ,
    CONSTRAINT ck_tool_invocations_times
        CHECK (completed_at IS NULL OR completed_at >= started_at)
);

-- Indexes for the queries the app is likely to make most often: a user's chats,
-- messages in order, a user's devices, and recent runs of a particular tool.
CREATE INDEX idx_conversations_user_created
    ON conversations (user_id, created_at DESC);
CREATE INDEX idx_conversations_user_active
    ON conversations (user_id, updated_at DESC) WHERE is_archived = FALSE;
CREATE INDEX idx_messages_conversation_order
    ON messages (conversation_id, message_order);
CREATE INDEX idx_user_devices_user
    ON user_devices (user_id);
CREATE INDEX idx_tool_invocations_message
    ON tool_invocations (message_id);
CREATE INDEX idx_tool_invocations_tool_started
    ON tool_invocations (tool_id, started_at DESC);

-- Refresh updated_at automatically whenever one of the mutable records changes.
CREATE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ai_models_updated_at
    BEFORE UPDATE ON ai_models FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_conversations_updated_at
    BEFORE UPDATE ON conversations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_user_preferences_updated_at
    BEFORE UPDATE ON user_preferences FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_user_devices_updated_at
    BEFORE UPDATE ON user_devices FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_tool_integrations_updated_at
    BEFORE UPDATE ON tool_integrations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE users IS 'User profile for the assistant. Login credentials are outside the current project scope.';
COMMENT ON TABLE conversations IS 'A chat owned by one user, with an optional default AI model.';
COMMENT ON TABLE messages IS 'Messages in a conversation; message_order keeps them in display order.';
COMMENT ON TABLE user_preferences IS 'One preference value for each user and preference key.';
COMMENT ON TABLE ai_models IS 'Reusable model details and provider-specific options.';
COMMENT ON TABLE tool_integrations IS 'The tools available to the assistant.';
COMMENT ON TABLE tool_invocations IS 'A record of a tool run linked to the message that requested it.';

COMMIT;
