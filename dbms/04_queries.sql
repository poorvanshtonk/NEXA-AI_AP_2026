-- NEXA AI database queries for CP2 (PostgreSQL).
-- Parameter notation: $1, $2, ... represents values supplied by the application.
-- Run these statements after 03_schema.sql. Each section is independent.

-- ---------------------------------------------------------------------------
-- 1. USERS
-- ---------------------------------------------------------------------------

-- Create a user. Returns the generated ID and timestamps.
INSERT INTO users (name, city)
VALUES ($1, $2)
RETURNING user_id, name, city, created_at;

-- Find a user by ID.
SELECT user_id, name, city, created_at, updated_at
FROM users
WHERE user_id = $1;

-- Update profile fields. Pass NULL for city to clear it.
UPDATE users
SET name = $2,
    city = $3
WHERE user_id = $1
RETURNING user_id, name, city, updated_at;

-- ---------------------------------------------------------------------------
-- 2. AI MODEL CATALOGUE
-- ---------------------------------------------------------------------------

-- Add a model, or refresh its configuration when its natural key already exists.
INSERT INTO ai_models (provider, model_name, model_version, configuration)
VALUES ($1, $2, $3, COALESCE($4::jsonb, '{}'::jsonb))
ON CONFLICT (provider, model_name, model_version)
DO UPDATE SET configuration = EXCLUDED.configuration
RETURNING model_id, provider, model_name, model_version, configuration;

-- List available models by provider.
SELECT model_id, provider, model_name, model_version, configuration
FROM ai_models
WHERE provider = $1
ORDER BY model_name, model_version;

-- ---------------------------------------------------------------------------
-- 3. CONVERSATIONS
-- ---------------------------------------------------------------------------

-- Create a conversation. Use NULL for model_id when no default model is chosen.
INSERT INTO conversations (user_id, model_id, title)
VALUES ($1, $2, COALESCE($3, 'New conversation'))
RETURNING conversation_id, user_id, model_id, title, created_at;

-- List a user's active conversations, most recently updated first.
SELECT c.conversation_id, c.title, c.model_id, m.provider, m.model_name,
       c.created_at, c.updated_at
FROM conversations AS c
LEFT JOIN ai_models AS m ON m.model_id = c.model_id
WHERE c.user_id = $1
  AND c.is_archived = FALSE
ORDER BY c.updated_at DESC
LIMIT $2 OFFSET $3;

-- List all conversations for a user, including archived ones.
SELECT conversation_id, title, is_archived, model_id, created_at, updated_at
FROM conversations
WHERE user_id = $1
ORDER BY updated_at DESC;

-- Rename a conversation or change its default model.
UPDATE conversations
SET title = $2,
    model_id = $3
WHERE conversation_id = $1
  AND user_id = $4
RETURNING conversation_id, title, model_id, updated_at;

-- Archive / unarchive a conversation. Supply the desired boolean as $2.
UPDATE conversations
SET is_archived = $2
WHERE conversation_id = $1
  AND user_id = $3
RETURNING conversation_id, is_archived, updated_at;

-- Delete a conversation owned by the user (messages and their tool runs cascade).
DELETE FROM conversations
WHERE conversation_id = $1
  AND user_id = $2
RETURNING conversation_id;

-- ---------------------------------------------------------------------------
-- 4. MESSAGES
-- ---------------------------------------------------------------------------

-- Append a message safely while assigning the next per-conversation order.
-- The row lock serializes concurrent appends to the same conversation.
-- Execute as one statement; no existing message order is changed.
WITH target AS (
    SELECT conversation_id
    FROM conversations
    WHERE conversation_id = $1
      AND user_id = $2
    FOR UPDATE
), next_order AS (
    SELECT COALESCE(MAX(msg.message_order), 0) + 1 AS message_order
    FROM target
    LEFT JOIN messages AS msg USING (conversation_id)
)
INSERT INTO messages (conversation_id, message_order, role, content)
SELECT target.conversation_id, next_order.message_order, $3, $4
FROM target CROSS JOIN next_order
RETURNING message_id, conversation_id, message_order, role, created_at;

-- Retrieve a conversation transcript in display order.
SELECT message_id, message_order, role, content, created_at
FROM messages
WHERE conversation_id = $1
ORDER BY message_order;

-- Retrieve the most recent N messages, returned in chronological order.
SELECT message_id, message_order, role, content, created_at
FROM (
    SELECT message_id, message_order, role, content, created_at
    FROM messages
    WHERE conversation_id = $1
    ORDER BY message_order DESC
    LIMIT $2
) AS recent
ORDER BY message_order;

-- Update a conversation's activity timestamp after adding a message.
UPDATE conversations
SET updated_at = CURRENT_TIMESTAMP
WHERE conversation_id = $1;

-- ---------------------------------------------------------------------------
-- 5. USER PREFERENCES
-- ---------------------------------------------------------------------------

-- Create or replace one preference value for a user.
INSERT INTO user_preferences (user_id, preference_key, preference_value)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, preference_key)
DO UPDATE SET preference_value = EXCLUDED.preference_value
RETURNING user_id, preference_key, preference_value, updated_at;

-- Read all preferences for a user.
SELECT preference_key, preference_value, updated_at
FROM user_preferences
WHERE user_id = $1
ORDER BY preference_key;

-- Remove one preference.
DELETE FROM user_preferences
WHERE user_id = $1
  AND preference_key = $2
RETURNING preference_key;

-- ---------------------------------------------------------------------------
-- 6. USER DEVICES
-- ---------------------------------------------------------------------------

-- Register a device (status defaults to 'pending').
INSERT INTO user_devices (user_id, device_name, device_type)
VALUES ($1, $2, $3)
RETURNING device_id, device_name, device_type, status, created_at;

-- List a user's devices.
SELECT device_id, device_name, device_type, status, created_at, updated_at
FROM user_devices
WHERE user_id = $1
ORDER BY created_at DESC;

-- Change a device status.
UPDATE user_devices
SET status = $2
WHERE device_id = $1
  AND user_id = $3
RETURNING device_id, status, updated_at;

-- ---------------------------------------------------------------------------
-- 7. TOOLS AND INVOCATIONS
-- ---------------------------------------------------------------------------

-- Register or update a tool by its unique code.
INSERT INTO tool_integrations (tool_code, display_name, category, is_enabled)
VALUES ($1, $2, $3, COALESCE($4, TRUE))
ON CONFLICT (tool_code)
DO UPDATE SET display_name = EXCLUDED.display_name,
              category = EXCLUDED.category,
              is_enabled = EXCLUDED.is_enabled
RETURNING tool_id, tool_code, display_name, category, is_enabled;

-- List enabled tools, optionally filtered by category ($1; NULL means all).
SELECT tool_id, tool_code, display_name, category
FROM tool_integrations
WHERE is_enabled = TRUE
  AND ($1::text IS NULL OR category = $1)
ORDER BY category, display_name;

-- Start a tool invocation for the message that requested it.
INSERT INTO tool_invocations (message_id, tool_id, input_payload)
SELECT $1, t.tool_id, COALESCE($3::jsonb, '{}'::jsonb)
FROM tool_integrations AS t
WHERE t.tool_id = $2
  AND t.is_enabled = TRUE
RETURNING invocation_id, status, started_at;

-- Finish a tool invocation. $2 is one of succeeded, failed, or cancelled.
UPDATE tool_invocations
SET status = $2,
    output_text = $3,
    completed_at = CURRENT_TIMESTAMP
WHERE invocation_id = $1
  AND status = 'pending'
RETURNING invocation_id, status, started_at, completed_at;

-- Inspect tool runs associated with a message.
SELECT ti.invocation_id, tool.tool_code, tool.display_name,
       ti.status, ti.input_payload, ti.output_text,
       ti.started_at, ti.completed_at
FROM tool_invocations AS ti
JOIN tool_integrations AS tool ON tool.tool_id = ti.tool_id
WHERE ti.message_id = $1
ORDER BY ti.started_at;

-- Recent runs for one tool, newest first.
SELECT ti.invocation_id, tool.tool_code, ti.status,
       ti.started_at, ti.completed_at, ti.output_text
FROM tool_invocations AS ti
JOIN tool_integrations AS tool ON tool.tool_id = ti.tool_id
WHERE ti.tool_id = $1
ORDER BY ti.started_at DESC
LIMIT $2;

-- ---------------------------------------------------------------------------
-- 8. REPORTING / AGGREGATES
-- ---------------------------------------------------------------------------

-- Per-user conversation and message totals.
SELECT u.user_id, u.name,
       COUNT(DISTINCT c.conversation_id) AS conversation_count,
       COUNT(msg.message_id) AS message_count
FROM users AS u
LEFT JOIN conversations AS c ON c.user_id = u.user_id
LEFT JOIN messages AS msg ON msg.conversation_id = c.conversation_id
WHERE u.user_id = $1
GROUP BY u.user_id, u.name;

-- Conversation overview with its latest message timestamp and message count.
SELECT c.conversation_id, c.title, c.is_archived,
       COUNT(msg.message_id) AS message_count,
       MAX(msg.created_at) AS last_message_at
FROM conversations AS c
LEFT JOIN messages AS msg ON msg.conversation_id = c.conversation_id
WHERE c.user_id = $1
GROUP BY c.conversation_id, c.title, c.is_archived
ORDER BY COALESCE(MAX(msg.created_at), c.created_at) DESC;

-- Tool success/failure counts over a time window ($1 start, $2 end).
SELECT tool.tool_code, tool.display_name,
       COUNT(*) AS total_runs,
       COUNT(*) FILTER (WHERE ti.status = 'succeeded') AS succeeded_runs,
       COUNT(*) FILTER (WHERE ti.status = 'failed') AS failed_runs,
       AVG(EXTRACT(EPOCH FROM (ti.completed_at - ti.started_at)))
           FILTER (WHERE ti.completed_at IS NOT NULL) AS avg_duration_seconds
FROM tool_invocations AS ti
JOIN tool_integrations AS tool ON tool.tool_id = ti.tool_id
WHERE ti.started_at >= $1
  AND ti.started_at < $2
GROUP BY tool.tool_id, tool.tool_code, tool.display_name
ORDER BY total_runs DESC;

-- Count registered devices by status.
SELECT status, COUNT(*) AS device_count
FROM user_devices
WHERE user_id = $1
GROUP BY status
ORDER BY status;