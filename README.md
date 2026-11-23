# NEXA AI — Database Design

This repository contains the DBMS coursework deliverables for a proposed PostgreSQL data layer for NEXA AI. The schema is a design proposal; it does not replace the application's current JSON-backed storage.

## Deliverables

Files are numbered in review order:

| Order | File | Contents |
|---|---|---|
| 1 | [`dbms/01_normalization.md`](dbms/01_normalization.md) | UNF-to-3NF normalization and design assumptions |
| 2 | [`dbms/02_er_diagram.md`](dbms/02_er_diagram.md) | ER diagram, entities, relationships, and constraints |
| 3 | [`dbms/02_er_diagram.png`](dbms/02_er_diagram.png) | Rendered ER diagram referenced by the Markdown document |
| 4 | [`dbms/03_schema.sql`](dbms/03_schema.sql) | PostgreSQL tables, constraints, indexes, and timestamp triggers |
| 5 | [`dbms/04_queries.sql`](dbms/04_queries.sql) | Parameterized examples for CRUD, chat history, tools, and reporting |
| 6 | [`dbms/05_query_timings.md`](dbms/05_query_timings.md) | Query-plan measurement scope, reproduction steps, and interpretation |

The benchmark scripts are kept under [`dbms/plans/`](dbms/plans/): a transactional fixture followed by plans for the conversation list and message history reads.

## Working with the SQL

Install the schema in a disposable PostgreSQL database with `psql`:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f dbms/03_schema.sql
```

`04_queries.sql` is a reference collection, not a single runnable migration: `$1`, `$2`, and similar markers are application-supplied parameters, and each example is intended to be run separately with suitable values.

To reproduce the benchmark, connect to a disposable database where the schema is installed, then run these commands in the same interactive `psql` session:

```text
\i dbms/plans/00_benchmark_fixture.sql
\i dbms/plans/01_conversation_list.sql
\i dbms/plans/02_conversation_messages.sql
ROLLBACK;
```

The fixture opens a transaction and inserts synthetic data. `ROLLBACK` removes it after both plans have run. See [`dbms/05_query_timings.md`](dbms/05_query_timings.md) for the current measurement status and reporting guidance.

## Scope

The proposed schema covers users, model catalogue entries, conversations, ordered messages, preferences, devices, tool integrations, and tool invocations. Authentication, shared conversations, and a migration from the existing JSON files are outside this coursework scope.
