# Supabase connectivity incident — 2026-11-17

## Summary

Organization V1 production verification is blocked by a contradiction between Supabase control-plane metadata and database-tool responses. This investigation did not establish that the project itself is paused or unhealthy.

## Target project

- Project ref: `gujzvkyytxsnervovvrt`
- Region: `ap-southeast-1`
- Database host: `db.gujzvkyytxsnervovvrt.supabase.co`
- PostgreSQL: `17.6.1.155`
- Supabase `get_project`: `ACTIVE_HEALTHY`
- Project listing: same project and status.
- Project URL lookup: succeeded.

## Live diagnostics

| Check | Result |
|---|---|
| Project metadata | `ACTIVE_HEALTHY` |
| Project listing | Succeeded |
| API URL lookup | Succeeded |
| Read-only SQL (`SELECT 1`) | Connection terminated due to connection timeout |
| Migration listing | Connection terminated due to connection timeout |
| Security advisor | Reports internal project 48591712 is hibernated |
| Performance advisor | Same hibernation response |
| Health advisor | Same hibernation response |
| Unified logs query | Query endpoint responds; no rows/sources returned for the queried window |

A second minimal SQL probe also timed out. Repeating the same SQL path is not a useful next step until the underlying connection path is corrected.

## Platform status cross-check

The official Supabase status page reported all systems operational on 2026-11-17, including the relevant region and database services. The November 12, 2026 database connection incident is marked resolved. This does not rule out a project-specific fault.

References:
- https://status.supabase.com/
- https://status.supabase.com/history
- https://supabase.com/changelog

## Assessment

**Confirmed:** the Supabase management/control-plane route can read the project and says it is healthy; the database SQL and migration-listing routes time out; advisor routes return a conflicting hibernation response.

**Not confirmed:** whether the underlying Postgres compute is actually hibernated, whether the MCP/connector has stale project-state/cache/connection metadata, or whether the database host/network path is dropping connections. No Postgres logs were available in the queried log window, so logs do not identify a server-side root cause.

Do not label this as a Supabase-wide outage. The current evidence points to either a project-specific database-runtime/connectivity issue or a Supabase MCP/management integration inconsistency.

## Actions deliberately not taken

- Did not call `restore_project`: project metadata currently reports `ACTIVE_HEALTHY`, so an unconditional restore would be an unjustified infrastructure operation.
- Did not pause/restart/resize the project.
- Did not change database settings, credentials, network restrictions, schema, migrations, RLS, or data.
- Did not attempt production DDL.
- Did not merge Organization PR #11.

## Next safe diagnostic sequence

1. In Supabase Dashboard, open project `gujzvkyytxsnervovvrt` and inspect Database/Compute status and recent project events. Confirm whether the database is running, restarting, or paused. Do not click restore/restart unless the dashboard explicitly reports a paused or unhealthy compute state.
2. From the Dashboard SQL Editor, run the read-only probe `select now(), current_database(), version();`. This distinguishes a working database from a failing MCP SQL path.
3. If Dashboard SQL works but MCP SQL still times out, reconnect/re-authorize the Supabase MCP integration and retry one read-only SQL query; escalate the connector mismatch to Supabase if it persists.
4. If Dashboard SQL also fails while project metadata remains healthy, open Supabase support with the project ref, region, UTC timestamps, and exact timeout/hibernation messages. Ask them to inspect the database runtime/connection state and reconcile the contradictory status.
5. Only after read-only SQL works, inspect the live migration ledger and Organization tables, then confirm backup/recovery readiness. Do not apply migrations until those checks are complete.

## Roadmap impact

Organization V1 remains the highest-priority incomplete milestone. Live schema/migration verification, backup/recovery readiness, database advisor review, and authenticated two-user RLS isolation remain blocked. Analytics stays queued behind Organization.
