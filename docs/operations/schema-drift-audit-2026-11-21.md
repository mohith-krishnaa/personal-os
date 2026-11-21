# Schema drift audit — reminder delivery and automatic RLS

**Date:** 2026-11-21  
**Repository:** `mohith-krishnaa/personal-os`  
**Branch:** `feature/organization-v1`  
**Audit base:** `a4703c27e619b7de4210b8f8f4066e9f6f98dba7`  
**Production project:** `gujzvkyytxsnervovvrt` (read-only inspection)

## Verified starting state

- Project status: ACTIVE_HEALTHY; PostgreSQL 17.11.0.003; region `ap-southeast-1`.
- Live project migration ledger: exactly eight versions: `20260829182309`, `20260830085036`, `20260830103327`, `20260830114218`, `20260830120132`, `20260830123420`, `20260830141616`, `20260905162251`.
- Repository migration count: 27; 19 are branch-only.
- PR #11 was open/unmerged and its head matched the audit base. CI #488 passed on that exact starting commit.

## 1. `claim_due_reminders(integer)`: expected pending migration, not drift

The live function is postgres-owned, SECURITY DEFINER, configured with `search_path=public`, and executable by `service_role` only. Its body locks due reminders with `FOR UPDATE SKIP LOCKED`, marks them delivered, and writes `REMINDER_DELIVERED`; it does not create a notification.

That definition matches the applied source-baseline migration `20260830123420_atomize_reminder_delivery_claim.sql`. Its version is present in the live ledger. Therefore, the previous description of this function as “out-of-ledger drift” was incorrect.

Branch-only migration `20261120000300_atomic_reminder_delivery.sql` is the intended replacement. It keeps the RPC signature, adds notification upsert/reuse, activity-event insertion, and the delivered marker in one transaction, changes the fixed search path to `pg_catalog, public`, and retains service_role-only EXECUTE. It is not in the live eight-version ledger and must be tested only on the isolated restored target.

## 2. `ensure_rls` / `public.rls_auto_enable()`: project-installed optional customization

The live catalog reports:

| Property | Source value |
|---|---|
| Event trigger | `ensure_rls` |
| Event | `ddl_command_end` |
| Enabled | Yes |
| Event-trigger owner | `postgres` |
| Function | `public.rls_auto_enable()` |
| Function owner | `postgres` |
| Security | SECURITY DEFINER |
| Function search path | `pg_catalog` |
| Effective EXECUTE | service_role true; anon/authenticated false |
| Function ACL | postgres and service_role only; no PUBLIC grant |

Supabase's [official Event Triggers guide](https://supabase.com/docs/guides/database/postgres/event-triggers) presents automatic RLS enablement as an optional example to create. It is not an automatically installed Supabase built-in. The installer/provenance of this project's instance cannot be determined from the database catalog.

A scan of all 112 PR #11 changed-file patches, including all 27 migration files, found only one migration reference: `20260905162251_restrict_rls_auto_enable_execute.sql`. That file only revokes EXECUTE from `anon` and `authenticated`; no repository migration creates the function or event trigger. The CI bootstrap creates a no-op function stub and pre-migration grants solely so that this privilege migration can replay. It does not test production behavior.

### Exception behavior risk

The live function's exception handler logs `rls_auto_enable: failed to enable RLS ...` but does not re-raise. Supabase's current documented example re-raises the exception. As a result, a failure in `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` can be swallowed and the original table-creation DDL can continue. This is a security-relevant difference and must not be silently normalized.

The event trigger only attempts to enable RLS for future public tables created by `CREATE TABLE`, `CREATE TABLE AS`, or `SELECT INTO`. It does not create policies and does not retroactively repair existing tables.

### ACL dependency

The live function ACL has no PUBLIC grant. However, migration `20260905162251_restrict_rls_auto_enable_execute.sql` only revokes from anon/authenticated; it does not revoke PUBLIC. The CI bootstrap explicitly revokes PUBLIC before granting the pre-migration roles. The isolated restore/preflight must therefore assert the PUBLIC ACL separately rather than infer it from the existing migration.

## 3. Restore implications

1. Do not assume the standard CLI schema dump preserves the database-level `ensure_rls` event trigger. Inspect the private `schema.sql` artifact and verify both function and event trigger on the isolated target.
2. If either object is absent, restore it only with an owner-reviewed, isolated-target procedure. Preserve the source behavior for the first comparison; any change to re-raise exceptions requires separate review and tests.
3. Verify function owner, SECURITY DEFINER, fixed search path, event-trigger owner/event/tags/enabled state, and exact ACL including PUBLIC.
4. Verify `claim_due_reminders` against the applied baseline, then apply `20261120000300_atomic_reminder_delivery.sql` only to the isolated target after the complete backup has been restored and verified.
5. Do not change production. No backup, restore, DDL/DML, migration, RLS/role/project-setting change, or PR merge was performed in this audit.

## 4. Remaining owner-controlled inventory

The connected Supabase tools list no Edge Functions. They do not expose Auth provider/SMTP/JWT settings, API keys, Realtime project settings, webhook configuration, or secret names/values. Those remain an owner-controlled inventory task; never place secret values in the manifest, repository, CI, or chat.

## 5. Regression coverage added

The existing `scripts/verify-backup-manifest.test.ts` suite now verifies:
- `rls_auto_enable` is referenced by exactly the privilege-restriction migration and is not created by repository migrations.
- The bootstrap describes its function as a no-op project-installed prerequisite stub.
- The eight-version source migration list includes the baseline reminder function but excludes the branch-only atomic replacement.
- The baseline and replacement retain their distinct search paths and notification-write contracts.

The tests protect migration classification; they do not prove the production event trigger is restored. CI for the audit commit is recorded in the latest project checkpoint after the workflow completes.
