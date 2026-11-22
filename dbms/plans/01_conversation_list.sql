EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT c.conversation_id, c.title, c.model_id, m.provider, m.model_name,
       c.created_at, c.updated_at
FROM conversations AS c
LEFT JOIN ai_models AS m ON m.model_id = c.model_id
WHERE c.user_id = '00000000-0000-4000-8000-000000000001'
  AND c.is_archived = FALSE
ORDER BY c.updated_at DESC
LIMIT 50;
