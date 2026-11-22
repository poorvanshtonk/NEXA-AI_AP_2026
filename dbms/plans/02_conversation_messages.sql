EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT message_id, message_order, role, content, created_at
FROM messages
WHERE conversation_id = '00000000-0000-4000-8000-000000000101'
ORDER BY message_order;