# Database Normalization for NEXA AI (CP1)

## 1. Introduction

NEXA AI is a personal assistant project with a React and TypeScript client and a Flask backend. The backend uses Ollama to generate replies and can route requests to utility tools. As the project grows, a PostgreSQL database will need to keep user profiles, preferences, conversations, messages, devices, model details, and tool activity organized and easy to retrieve.

At the moment, the backend saves one profile in `server/memory/user_profile.json` and conversation history in `server/memory/history.json`. The profile contains a name, city, and lists for preferences and devices. Each saved history entry has a role and message content. The client also has chat titles and message timestamps, but the backend does not save those fields. The project uses an Ollama model and has weather, date/time, and web-search tools; it does not yet store users, model records, registered tools, or tool runs in a database.

The schema in this document is a proposal for a later database-backed version. It assumes that a conversation has one owner, messages have an order within a conversation, each user preference is a named value, and each device belongs to one user. Model and tool records are shared catalogue entries. These are design assumptions, not descriptions of features already implemented. Authentication is not included because the app does not yet have an account system.

## 2. Entities and attributes

| Entity | Main attributes | Why it is included |
|---|---|---|
| `USERS` | `user_id`, `name`, `city`, `created_at`, `updated_at` | Keeps each user's profile in one place. |
| `AI_MODELS` | `model_id`, `provider`, `model_name`, `model_version`, `configuration`, timestamps | Holds reusable model details and provider-specific options. |
| `CONVERSATIONS` | `conversation_id`, `user_id`, `model_id`, `title`, `is_archived`, timestamps | Represents a user's chat and its optional default model. |
| `MESSAGES` | `message_id`, `conversation_id`, `message_order`, `role`, `content`, `created_at` | Stores each message in conversation order. |
| `USER_PREFERENCES` | `user_id`, `preference_key`, `preference_value`, timestamps | Stores one value for each named setting, such as `theme=dark`. |
| `USER_DEVICES` | `device_id`, `user_id`, `device_name`, `device_type`, `status`, timestamps | Keeps connected or registered devices associated with their owner. |
| `TOOL_INTEGRATIONS` | `tool_id`, `tool_code`, `display_name`, `category`, `is_enabled`, timestamps | Lists the tools the assistant can use, such as weather or web search. |
| `TOOL_INVOCATIONS` | `invocation_id`, `message_id`, `tool_id`, `status`, `input_payload`, `output_text`, `started_at`, `completed_at` | Can record a tool run and the message that led to it. This is a future capability. |

Model settings and tool inputs are stored as JSONB because their exact fields depend on the model provider or tool. For now, the database treats each payload as one value. If the app later needs to search or constrain individual payload fields, those fields can be given a relational design of their own. The current app does not save these records yet.

## 3. Functional dependencies

The dependencies below describe the proposed schema. An arrow means that the attribute or group on the left determines the values on the right. The unique constraints in the SQL schema create the alternate keys noted here.

- `user_id → name, city, created_at, updated_at`
- `model_id → provider, model_name, model_version, configuration, created_at, updated_at`
- `(provider, model_name, model_version) → model_id, configuration, created_at, updated_at`
- `conversation_id → user_id, model_id, title, is_archived, created_at, updated_at`
- `message_id → conversation_id, message_order, role, content, created_at`
- `(conversation_id, message_order) → message_id, role, content, created_at`
- `(user_id, preference_key) → preference_value, created_at, updated_at`
- `device_id → user_id, device_name, device_type, status, created_at, updated_at`
- `tool_id → tool_code, display_name, category, is_enabled, created_at, updated_at`
- `tool_code → tool_id, display_name, category, is_enabled, created_at, updated_at`
- `invocation_id → message_id, tool_id, status, input_payload, output_text, started_at, completed_at`

The design does not assume that a person's name determines their city, that a preference value is unique across users, or that a device name uniquely identifies a device. None of those dependencies is supported by the project requirements.

## 4. Unnormalized form (UNF)

The profile and conversation data could be imagined as one nested record for each user:

```text
USER_WORKSPACE_UNF(
  user_id, name, city,
  preferences = [{key, value}, ...],
  devices = [{device_name, device_type, status}, ...],
  conversations = [{conversation_id, title, archived, model,
    messages = [{order, role, content, timestamp,
      tool_invocations = [{tool, status, input, output}, ...]}, ...]}, ...]
)
```

This record contains lists inside a row: a user may have several preferences and devices, a conversation may contain many messages, and a message may lead to several tool runs. Keeping everything together makes it awkward to find or update one item. Expanding the lists into rows would also repeat the same user and conversation details many times. The current JSON files contain some of these lists, but not every field shown in this proposed example.

## 5. First Normal Form (1NF)

In 1NF, each field holds one value and repeating lists have been expanded into rows. The following flattened relation shows what that might look like:

```text
WORKSPACE_1NF(
  user_id, name, city,
  preference_key, preference_value,
  device_id, device_name, device_type, device_status,
  conversation_id, title, is_archived, model_id, model_provider, model_name,
  message_id, message_order, role, content, message_created_at,
  invocation_id, tool_id, tool_code, tool_status, input_payload, output_text
)
```

Each cell contains a single value. A fully populated row represents a combination of a user's preference, device, conversation, message, and tool invocation. Its composite key would need the identifiers for each of those items: `(user_id, preference_key, device_id, conversation_id, message_order, invocation_id)`. In real data, many of these values would be absent, so the flattened table would contain nulls and combinations of unrelated lists. It is useful here for showing the dependencies, but would be a poor table to implement.

Some dependencies in this 1NF relation are `user_id → name, city`, `(user_id, preference_key) → preference_value`, `device_id → user_id, device_name, device_type, device_status`, `conversation_id → user_id, title, is_archived, model_id`, `(conversation_id, message_order) → role, content, message_created_at`, and `invocation_id → message_id, tool_id, tool_status, input_payload, output_text`. These facts depend on only part of the flattened key, so the relation is not yet in 2NF.

## 6. Second Normal Form (2NF)

2NF requires 1NF and removes partial dependencies: each non-key field must depend on the whole key. In the flattened table, a user's name and city depend only on `user_id`. A preference value depends on `(user_id, preference_key)`, device details on `device_id`, conversation details on `conversation_id`, and invocation details on `invocation_id`. Message details depend on the conversation and its message order. Those values do not depend on the entire flattened key.

We can remove these partial dependencies by splitting the table into relations for the separate entities:

```text
USERS_2NF(user_id PK, name, city)
USER_PREFERENCES_2NF(user_id PK/FK, preference_key PK, preference_value)
USER_DEVICES_2NF(device_id PK, user_id FK, device_name, device_type, status)
AI_MODELS_2NF(model_id PK, provider, model_name, model_version, configuration)
CONVERSATIONS_2NF(conversation_id PK, user_id FK, model_id FK, title, is_archived)
MESSAGES_2NF(message_id PK, conversation_id FK, message_order, role, content, created_at)
TOOL_INTEGRATIONS_2NF(tool_id PK, tool_code, display_name, category, is_enabled)
TOOL_INVOCATIONS_2NF(invocation_id PK, message_id FK, tool_id FK, status, input_payload, output_text, started_at, completed_at)
```

The key for a preference is the pair `(user_id, preference_key)`, since one user can have several settings. Messages use a generated `message_id` as their primary key, while `(conversation_id, message_order)` remains unique so the same position cannot be used twice in one conversation.

## 7. Third Normal Form (3NF)

3NF builds on 2NF by removing transitive dependencies, where a non-key fact depends on another non-key fact. For example, if model details were copied into every conversation, the conversation would determine a model ID, and that model ID would determine its provider and configuration: `conversation_id → model_id → configuration`. The `AI_MODELS` table stores those details once, and a conversation refers to the model by ID. Tool names and descriptions are handled the same way: they live in `TOOL_INTEGRATIONS`, while each invocation stores the tool ID and the details of that particular run.

In the final relations, each non-key field depends on a key, the whole key, and no other non-key field. For example, a preference value depends on both `user_id` and `preference_key`. The model and tool identities have unique constraints, and conversations and invocations refer to those catalogue records instead of copying their descriptive fields.

## 8. Final 3NF relational schema

This is the logical schema. PostgreSQL types, constraints, and indexes are defined in [`03_schema.sql`](03_schema.sql).

```text
USERS(
  user_id PK, name, city, created_at, updated_at
)
AI_MODELS(
  model_id PK, provider, model_name, model_version,
  configuration, created_at, updated_at,
  UNIQUE(provider, model_name, model_version)
)
CONVERSATIONS(
  conversation_id PK, user_id FK → USERS, model_id FK → AI_MODELS NULL,
  title, is_archived, created_at, updated_at
)
MESSAGES(
  message_id PK, conversation_id FK → CONVERSATIONS,
  message_order, role, content, created_at,
  UNIQUE(conversation_id, message_order)
)
USER_PREFERENCES(
  user_id PK/FK → USERS, preference_key PK, preference_value,
  created_at, updated_at
)
USER_DEVICES(
  device_id PK, user_id FK → USERS, device_name, device_type, status,
  created_at, updated_at
)
TOOL_INTEGRATIONS(
  tool_id PK, tool_code UNIQUE, display_name, category, is_enabled,
  created_at, updated_at
)
TOOL_INVOCATIONS(
  invocation_id PK, message_id FK → MESSAGES, tool_id FK → TOOL_INTEGRATIONS,
  status, input_payload, output_text, started_at, completed_at
)
```

### Relationships and deletion behavior

- A user can have many conversations, preferences, and devices. Deleting a user also deletes those owned records and their conversation messages and tool runs.
- A conversation can contain many messages. Deleting a conversation removes its messages and related tool runs. Message order only needs to be unique inside its conversation.
- A conversation can use one default model. If that model is removed, the conversation remains and its `model_id` becomes null.
- Each tool run points to one message and one registered tool. A tool cannot be deleted while invocation records still refer to it, so the history remains meaningful.
- Mutable records have `updated_at` timestamps. Messages and tool runs are treated as events and keep their event timestamps instead.

## 9. Anomalies the design avoids

The flattened table would make routine changes risky:

- **Update anomaly:** If a user's name were copied onto 40 message rows, every copy would need to be changed. Missing one would leave conflicting names. In this design, the name is stored once in `USERS`.
- **Insertion anomaly:** A model or tool could not be added until a conversation or message used it if everything lived in one combined table. Separate catalogue tables let the app record those items independently.
- **Deletion anomaly:** Removing a user's only conversation from a combined table could accidentally remove their profile, preferences, device, and model/tool details as well. Separate tables preserve those independent records.

## 10. Scope and limitations

This schema is a proposed destination for a future migration; it does not change the current JSON-backed app. It assumes one owner per conversation and one scalar value per preference key. Model configurations and tool inputs remain JSONB while their structure is still provider- or tool-specific. If the app later needs to query individual fields as business data, those fields should be modeled explicitly. Authentication, shared conversations, attachments, and device telemetry are not part of the current project scope. The SQL file defines the physical schema, and the ER diagram should stay aligned with it.
