# Task creation idempotency

## Contract

Task creation uses a client-generated UUID scoped by the authenticated owner. The database unique constraint on `(user_id, client_request_id)` is the final concurrency boundary. The application stores a SHA-256 fingerprint of the normalized creation payload and rejects reuse of the same request ID with a different fingerprint.

The task activity-event trigger runs in the same database transaction as task insertion. A duplicate request that loses the unique-key race does not insert another task and therefore does not emit another `TASK_CREATED` event. The migration replay assertions cover owner-scoped uniqueness, immutable request identity, duplicate suppression, and exactly one creation event.

## Browser retry continuity

Both dashboard task-creation forms keep the pending request ID in component memory and in tab-scoped `sessionStorage`. The storage key is based on the form's React `useId()`, so independent form instances do not share pending IDs.

The persisted value contains only:
- the SHA-256 digest of the serialized form payload;
- the client request UUID;
- a pending/completed state.

Task titles, recurrence details, project IDs, and other payload fields are not written to browser storage.

A retry with the same payload in the same tab reuses the pending UUID, including after a component remount or page reload. A changed payload receives a different UUID while other pending payload fingerprints remain recoverable. After a successful server action, that fingerprint is marked completed so a later intentional creation with identical fields receives a fresh UUID.

If session storage or Web Crypto is unavailable, the helper falls back to the existing in-memory behavior. The database uniqueness constraint and server-side payload-hash check remain active, but retry continuity across a reload is not guaranteed in that fallback mode.

## Scope and limitations

- Pending state is tab-scoped; it is not shared across tabs, browsers, or devices.
- The stored fingerprint is a one-way SHA-256 digest, not encryption or authentication.
- The browser does not store API keys, credentials, or task payload text.
- The harness and database migration tests are separate from this client-side retry cache.
- This change does not alter database schema, RLS, migrations, or production data.
