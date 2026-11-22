# CP4: Query timings and execution plans

## Scope

This report measures the two read paths that dominate the chat UI: listing a
user's most recently updated active conversations and loading a conversation's
messages in display order. The SQL matches the access patterns supported by the
indexes in [`03_schema.sql`](03_schema.sql). It does not change the schema.

## Queries and supporting indexes

| Operation | Query shape | Supporting index |
|---|---|---|
| Active conversation list | Filter by `user_id` and `is_archived = false`, sort by `updated_at DESC`, return the first 50 | `idx_conversations_user_active (user_id, updated_at DESC) WHERE is_archived = FALSE` |
| Message history | Filter by `conversation_id`, sort by `message_order` | Unique index for `uq_messages_conversation_order (conversation_id, message_order)`; the separate `idx_messages_conversation_order` has the same key order |

The unique constraint on message order already creates a B-tree index with the
same leading columns as `idx_messages_conversation_order`. Keeping both indexes
duplicates write and storage work. CP4 records this finding; the schema is left
unchanged so any index removal can be evaluated as a separate reviewed change.

## Measurement status

No measured execution times are reported from this checkout. There was no
PostgreSQL server accepting connections at `localhost:5432`, and an isolated
local server could not start because the environment denied PostgreSQL shared
memory creation. Reporting fabricated timings or plan output would be
misleading. Run the commands below against a disposable PostgreSQL database to
populate this report with environment-specific measurements.

## Reproduce

Use a disposable database with the schema from `03_schema.sql` already
installed. The fixture script inserts 10,000 conversations and 250,000
messages, collects planner statistics, and keeps all fixture data in a
transaction. Keep the same `psql` session open while running both plan files;
finish with `ROLLBACK` to discard the fixture.

Run all three files from one interactive `psql` session. The fixture leaves its
transaction open so the plan files see the synthetic rows; finish with
`ROLLBACK;`:

```text
\i dbms/plans/00_benchmark_fixture.sql
\i dbms/plans/01_conversation_list.sql
\i dbms/plans/02_conversation_messages.sql
ROLLBACK;
```

`EXPLAIN ANALYZE` executes the reads and reports actual rows, planning time,
execution time, and buffer activity. Repeat each plan several times and record
the median execution time, PostgreSQL version, machine, and cache state here.
The first execution may include cold-cache I/O, so report cold and warm results
separately when they matter.

## Expected plan checks

- The conversation list should be able to use the partial
  `idx_conversations_user_active` index for the owner filter and descending
  update order. The `LIMIT 50` should stop the scan early. A sequential scan can
  still be the rational plan for a tiny fixture/table; inspect row counts and
  buffer reads before drawing conclusions.
- The message history query should use an index beginning with
  `conversation_id`, and return rows in `message_order` without a separate sort.
  The unique-constraint index is sufficient for that access pattern.
- Compare actual rows with estimated rows. Large differences can signal stale
  statistics or skewed data; run `ANALYZE` before comparing plans.

## Plan artifacts

- [`plans/00_benchmark_fixture.sql`](plans/00_benchmark_fixture.sql) — isolated synthetic data fixture
- [`plans/01_conversation_list.sql`](plans/01_conversation_list.sql) — active conversation list plan
- [`plans/02_conversation_messages.sql`](plans/02_conversation_messages.sql) — ordered message history plan