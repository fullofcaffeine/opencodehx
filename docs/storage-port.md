# Storage Port

**Beads:** `opencodehx-014`, `opencodehx-e6g6`
**Upstream oracle:** `../opencode/packages/opencode/src/storage/db.ts`, `db.node.ts`, `json-migration.ts`, `session/session.sql.ts`, `session/projectors.ts`, and `session/message-v2.ts`

## Slice

This slice adds a Node-first SQLite seam for session persistence:

- `opencodehx.storage.SessionStore` defines the narrow store surface needed by early session/message work.
- `opencodehx.storage.SqliteSessionStore` creates upstream-shaped `project`, `session`, `message`, and `part` tables with the same core columns, JSON data blobs, indexes, and cascade behavior.
- Message rows store `data` without `id`/`sessionID`; part rows store `data` without `id`/`sessionID`/`messageID`, matching upstream projector behavior.
- `pageMessages` implements upstream-style newest-first selection, chronological page output, opaque cursor encoding, and part hydration.
- `opencodehx.session.SessionExport` builds the upstream CLI export payload shape from the store, including optional sanitization for sensitive transcript text and session path/title fields.
- `opencodehx.cli.Cli` wires the first non-interactive `export <sessionID> [--sanitize]` path through `StorageDatabasePath` and `SqliteSessionStore`, keeping JSON on stdout and progress/error diagnostics on stderr.
- `opencodehx.storage.SessionStore.listSessions` and `opencodehx.cli.Cli` support first non-interactive `run --session <id>` and `run --continue` validation/recovery over stored sessions.
- New and resumed CLI runs persist through the default `StorageDatabasePath` store, with `OPENCODE_DB` available as an override, making generated session IDs immediately exportable and resumed turns append-only.
- `StorageSmoke` covers create/read/update session, message/part upsert, pagination, part lookup/removal, and cascade delete.
- `opencodehx.storage.JsonStorageMigrationRuntime` migrates the legacy JSON subset currently owned by `SessionStore`: project, session, message, and part files. It preserves upstream's path-derived ID precedence so stale `id`, `projectID`, `sessionID`, and `messageID` fields inside JSON bodies cannot override filenames or parent directories.
- `StorageSmoke.jsonMigration` covers project filename ID precedence, session directory/filename ID precedence, message filename ID precedence, part filename/message-path precedence, legacy parts without `sessionID`, orphan session skipping, idempotent reruns, and missing storage directory empty stats.
- `opencodehx.storage.StorageDatabasePath` mirrors upstream channel database path selection: `latest`, `beta`, `prod`, and disabled channel DB use `opencode.db`; other channels are sanitized into `opencode-<channel>.db`; `OPENCODE_DB` supports `:memory:`, absolute paths, and data-dir-relative paths.
- `SessionPersistenceSmoke` covers store-backed raw and sanitized session export payloads, and `CliSmoke` covers the generated command path against a seeded temp SQLite database.

## Runtime Seam

Upstream currently uses `node:sqlite` through Drizzle in `db.node.ts`, but this workspace runs Node 20.19.3 where `node:sqlite` is unavailable. OpenCodeHX uses `better-sqlite3` for the first executable Node seam so the synchronous storage behavior can be proven now. When the project baseline moves to Node with `node:sqlite`, this adapter should be swapped behind the `SessionStore` interface rather than leaking a driver dependency through session code.

## Deferred Parity

This is not the full OpenCode storage service. Deferred work includes Drizzle migration compatibility, sync-event projector wiring, transactions/effect side effects, full project table parity, todo/session_entry/permission/session-share tables, JSON migration unreadable-file error collection, and storage service APIs outside session/message persistence.
