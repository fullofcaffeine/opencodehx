# Storage Port

**Bead:** `opencodehx-014`  
**Upstream oracle:** `../opencode/packages/opencode/src/storage/db.ts`, `db.node.ts`, `session/session.sql.ts`, `session/projectors.ts`, and `session/message-v2.ts`

## Slice

This slice adds a Node-first SQLite seam for session persistence:

- `opencodehx.storage.SessionStore` defines the narrow store surface needed by early session/message work.
- `opencodehx.storage.SqliteSessionStore` creates upstream-shaped `project`, `session`, `message`, and `part` tables with the same core columns, JSON data blobs, indexes, and cascade behavior.
- Message rows store `data` without `id`/`sessionID`; part rows store `data` without `id`/`sessionID`/`messageID`, matching upstream projector behavior.
- `pageMessages` implements upstream-style newest-first selection, chronological page output, opaque cursor encoding, and part hydration.
- `StorageSmoke` covers create/read/update session, message/part upsert, pagination, part lookup/removal, and cascade delete.

## Runtime Seam

Upstream currently uses `node:sqlite` through Drizzle in `db.node.ts`, but this workspace runs Node 20.19.3 where `node:sqlite` is unavailable. OpenCodeHX uses `better-sqlite3` for the first executable Node seam so the synchronous storage behavior can be proven now. When the project baseline moves to Node with `node:sqlite`, this adapter should be swapped behind the `SessionStore` interface rather than leaking a driver dependency through session code.

## Deferred Parity

This is not the full OpenCode storage service. Deferred work includes Drizzle migration compatibility, global database path/channel selection, sync-event projector wiring, transactions/effect side effects, project table parity, todo/session_entry/permission tables, JSON migration, and storage service APIs outside session/message persistence.
