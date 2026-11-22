BEGIN;

INSERT INTO users (user_id, name, city)
VALUES ('00000000-0000-4000-8000-000000000001', 'CP4 benchmark user', 'Test City');

INSERT INTO users (name, city)
SELECT 'CP4 fixture user ' || n, 'Test City'
FROM generate_series(1, 999) AS n;

INSERT INTO conversations (
    conversation_id, user_id, title, is_archived, created_at, updated_at
)
SELECT
    CASE WHEN n = 1 THEN '00000000-0000-4000-8000-000000000101'::uuid
         ELSE gen_random_uuid() END,
    CASE WHEN n <= 100 THEN '00000000-0000-4000-8000-000000000001'::uuid
         ELSE (SELECT user_id FROM users ORDER BY user_id OFFSET (n % 1000) LIMIT 1)
    END,
    'CP4 conversation ' || n,
    n % 5 = 0,
    CURRENT_TIMESTAMP - (n || ' minutes')::interval,
    CURRENT_TIMESTAMP - (n || ' seconds')::interval
FROM generate_series(1, 10000) AS n;

INSERT INTO messages (conversation_id, message_order, role, content, created_at)
SELECT c.conversation_id,
       m.message_order,
       CASE WHEN m.message_order % 2 = 1 THEN 'user' ELSE 'assistant' END,
       'CP4 synthetic message ' || m.message_order,
       c.created_at + (m.message_order || ' seconds')::interval
FROM conversations AS c
CROSS JOIN generate_series(1, 25) AS m(message_order)
WHERE c.title LIKE 'CP4 conversation %';

ANALYZE conversations;
ANALYZE messages;

