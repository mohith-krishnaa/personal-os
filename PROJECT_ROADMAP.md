# Latest verified checkpoint — owner backup preflight revalidated (2026-11-21)

Starting branch `feature/organization-v1` was at `92e0fa88af8df5de58fe822e5e39051d4c048d5e`; PR #11 was open, unmerged, mergeable, and pointed to that exact HEAD. CI #540 passed on that starting HEAD. The branch was 622 commits ahead of main and 0 behind.

A fresh read-only source inventory reconfirmed 8 live project migrations versus 27 repository migrations (19 branch-only), all 9 public application tables empty, all 36 managed/ephemeral data counts zero, and the four required extensions at the recorded versions. The source remains eligible for the documented CLI logical-backup row-count gate, but no owner-controlled backup or successful isolated restoration exists. No isolated Supabase branch is available. No production mutation occurred.

**Organization V1 remains in progress. Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued.** The current blocker is owner-controlled backup and isolated restoration, not missing application-side checklist tests. The next action is the private owner export, manifest verification, isolated restore, customization/conflict review, isolated application of the 19 branch-only migrations, and authenticated two-owner PostgREST acceptance. Do not apply branch-only migrations to production or merge PR #11.

---

# Latest verified checkpoint — checklist reconciliation report determinism and repeatability (2026-11-21)

**Implementation/test HEAD:** `bc7aded35e8451e544f262bc64b7780aa4bf530a` — [CI #539 passed on this exact commit](https://github.com/mohith-krishnaa/personal-os/actions/runs/44908479254).  
**Starting HEAD:** `8ab5f8d15e893a678f9ba10acc60706ffdc67eaa` — [CI #536 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44904330395).

## Continuity and repository recovery

- Personal-OS Builder is enabled. The recorded current run was marked `in_progress`, but that status was not treated as proof of worker liveness.
- The latest stored result was created before the current run started and belonged to the preceding recurring-task concurrency checkpoint, not this run.
- Starting branch `feature/organization-v1` was at `8ab5f8d15e893a678f9ba10acc60706ffdc67eaa`, matching PR #11. Main remained `2b42dd17796b75dca79434a81d4e1f0cbf0fa043).
- PR #11 was open and unmerged; PR #12 remained an open superseded draft.
- Repository migration count remained 27. No migration was added.
- No local checkout is attached, so local working-tree cleanliness cannot be independently certified.

## Checklist reconciliation audit

Inspected `supabase/operations/checklist-reconciliation-conflicts.sql`, the one-time reconciliation migration, its legacy/post-reconciliation fixtures, the migration assertions, the migration runner, the preflight, and the existing runbook references.

- The report is read-only, joins legacy rows to tasks and canonical rows by unique IDs, applies the documented classification priority, and orders output by `legacy.id`.
- The runner now executes the report twice inside separate `BEGIN READ ONLY` transactions against the same fixture snapshot and requires byte-identical output.
- It snapshots all row values from both checklist tables before and after report execution and requires no data change.
- It asserts the exact four seeded conflict IDs and classifications in ascending legacy-ID order, including the cross-owner/task collision, payload-only collision values/flags, and post-reconciliation `missing_canonical` row.
- The runner reapplies `20261015000200_reconcile_checklist_tables.sql` against an unchanged source snapshot and compares ordered JSONB snapshots of both tables before and after. The unchanged snapshot must remain identical.
- Important limitation: this is repeatability for an unchanged source snapshot, not a live synchronization mechanism. If a new valid legacy row is written after the original migration, manually rerunning the migration can copy that newly eligible row. The report flags it for owner review; migration reapplication is not an automatic catch-up process.

Added `docs/operations/checklist-reconciliation-report.md` and extended the disposable PostgreSQL runner. The implementation/test commit changes exactly two files: the runner and the new operations document. No application runtime code, production schema, RLS, or data changed.

## CI evidence

- CI #537 failed in the migration step because an over-escaped psql include was parsed as an invalid command. The log showed `invalid command \\`; the escaping was corrected.
- CI #538 passed on an intermediate revision that still contained a redundant helper definition.
- The redundant definition was removed. CI #539 passed on final implementation/test HEAD `bc7aded`.
- PostgREST acceptance preflight: 33/33 passed.
- PostgreSQL 17 migration replay: 27/27 passed. Checklist migration repeatability, read-only report execution, identical repeated output, row-snapshot preservation, exact classification/order assertions, Organization/RLS checks, and existing concurrency checks passed.
- Task hierarchy concurrency: passed.
- Application tests: 203/203 passed.
- TypeScript typecheck: passed.
- Production build: passed.
- npm install reported 0 vulnerabilities. Existing Node `punycode` deprecation and npm install-script allowlist warnings remain non-failing.
- No lint script is configured.

## Production and acceptance boundary

No production Supabase query or mutation occurred. The last recorded live baseline remains 8 applied migration versions versus 27 repository migrations (19 branch-only); it was not refreshed in this run. No owner-controlled backup or successful isolated restore was supplied or verified. No production DDL/DML, migration, RLS/role/project-setting change, backup, restore, or PR merge occurred.

Organization V1 remains incomplete. Still required: complete owner-controlled schema/data/roles backup; offline manifest verification; successful isolated restoration; extension, role/membership, default-ACL, database-setting, Vault, Auth-trigger, `ensure_rls`, and reminder-function verification; restored-copy checklist conflict disposition; application of the 19 branch-only migrations only to the isolated target; authenticated two-owner PostgREST acceptance; and the separate owner decision on the fail-closed `ensure_rls` candidate. Analytics remains queued.

## Next action

Owner-controlled complete backup and isolated restoration remain the primary gate. Verify the manifest, restore into a separate isolated Supabase project, then run customization, migration, checklist conflict disposition, and authenticated two-owner PostgREST acceptance there. Do not apply branch-only migrations to production, deploy the fail-closed candidate, or merge PR #11.

---

# Latest verified checkpoint — recurring occurrence concurrency and event idempotency (2026-11-21)

**Implementation/test HEAD:** f8d373116444bfa8886fe253ed4d4b0a5a82806a — [CI #533 passed on this exact commit](https://github.com/mohith-krishnaa/personal-os/actions/runs/44903880721).

## Continuity recovery

- Personal-OS Builder is enabled.
- The recorded current run is marked in_progress, but that state was not treated as proof of worker liveness.
- The latest stored result predates the recorded current-run start and belongs to the previous completed subtask retry/activity-event checkpoint, not this run.
- Starting branch feature/organization-v1 was at 6f60e687248fe0020262cb6836d5724c2e101578, matching PR #11. Main is 2b42dd17796b75dca79434a81d4e1f0cbf0fa043.
- Starting CI #527 passed on the exact starting HEAD. PR #11 remained open and unmerged; PR #12 remained an open superseded draft.
- Repository migration count remained 27. No migration was added.
- No local checkout is attached; local working-tree cleanliness cannot be independently certified.

## Recurring completion and occurrence audit

Inspected src/lib/tasks.ts, src/lib/tasks.test.ts, recurrence migrations, the task activity-event trigger, the SQL migration runner, and existing sequential recurrence assertions.

The application already uses the partial unique index tasks_recurring_occurrence_unique on (user_id, recurrence_parent_id, due_at). On SQLSTATE 23505, setTaskStatusForUser looks up the occurrence by authenticated owner, recurrence root, and due instant; if no matching row exists, it rethrows the original database error. Existing tests covered a retry after committed completion and a sequential duplicate, but not two concurrent completion requests.

Added four expected files:
- src/lib/tasks.test.ts: two tests cover resolving a unique-index race to the owner-scoped existing occurrence and rethrowing when the lookup finds no matching row. The query mock now models the chainable insert/select API.
- supabase/tests/recurring-occurrence-concurrency.sh: two authenticated PostgreSQL sessions model separate PostgREST completion and occurrence-insert transactions. The first commits the status transition and holds the occurrence INSERT transaction open. The second completion is a no-op, then its competing occurrence INSERT waits on the unique index and resolves to the committed winner. Assertions require one TASK_COMPLETED event, one occurrence, and one source-linked TASK_RECURRENCE_GENERATED event.
- supabase/tests/organization-migrations.sh invokes the new concurrency regression after task activity-event checks.
- docs/architecture/recurring-task-idempotency.md records the database, retry, event, and test contracts.

The concurrency test is a disposable PostgreSQL transaction/index test, not hosted Supabase/PostgREST end-to-end acceptance. No application runtime code or database migration changed.

## Verification — CI #533

- PostgREST acceptance preflight: 33/33 passed.
- PostgreSQL 17 migration replay: 27/27 passed; the new two-session recurring-completion/occurrence race ran and passed.
- Organization task-hierarchy concurrency: passed.
- Application tests: 203/203 passed.
- TypeScript typecheck: passed.
- Production build: passed.
- npm install reported 0 vulnerabilities; the existing install-script allowlist warning remains.
- No lint script is configured.

Three earlier attempts failed and were investigated rather than suppressed:
- CI #530 failed because an unquoted shell heredoc expanded the SQL dollar-quote tag under set -u (retry: unbound variable). The dollar-quote escaping was corrected.
- CI #531 failed because the test query mock returned a Promise from insert() instead of the chainable builder expected by insert().select(). The mock was corrected.
- CI #532 ran on the prior queued head and repeated the same mock failure. The corrected final head was then verified by CI #533.

The aggregate diff from the starting HEAD contains exactly the four expected files. A credential-pattern scan of all four files returned zero matches. No unrelated changes were found in the remote diff.

## Repository and production boundary

- Branch: feature/organization-v1.
- Implementation/test HEAD: f8d373116444bfa8886fe253ed4d4b0a5a82806a.
- Main HEAD: 2b42dd17796b75dca79434a81d4e1f0cbf0fa043.
- Branch comparison: 615 commits ahead, 0 behind.
- PR #11: open, unmerged, mergeable; head matches the implementation/test HEAD; 120 total changed files.
- PR #12: open superseded draft.
- No production Supabase query or mutation occurred. The last recorded live baseline remains 8 applied versions versus 27 repository migrations (19 branch-only); it was not refreshed during this run. No production DDL/DML, migration, RLS/role/project-setting change, backup, restore, or PR merge occurred.

Organization V1 remains incomplete. Still required: complete owner-controlled schema/data/roles backup; offline manifest verification; successful isolated restoration; extension, role/membership, default-ACL, database-setting, Vault, Auth-trigger, ensure_rls, and reminder-function verification; restored-copy checklist conflict disposition; application of the 19 branch-only migrations only to the isolated target; authenticated two-owner PostgREST acceptance; and the separate owner decision on the fail-closed ensure_rls candidate.

## Next action

Owner-controlled complete backup and isolated restoration remain the primary gate. Verify the manifest, restore into a separate isolated Supabase project, then run the customization, migration, checklist, and authenticated PostgREST acceptance sequence there. If owner artifacts remain unavailable, the next safe code-side task is a bounded audit of checklist reconciliation conflict-report determinism and idempotence on disposable PostgreSQL data. Do not apply branch-only migrations to production, deploy the fail-closed candidate, or merge PR #11.

---

## Current milestone status

| Milestone | Status |
|---|---|
| Organization V1 | In progress — backup/isolated restoration and authenticated acceptance remain blocked on owner-controlled artifacts |
| Analytics | Queued |
| AI Assistant | Queued |
| Research Agent | Queued |
| Adaptive Scheduling | Queued |
| Production hardening | Pending |

# Latest verified roadmap checkpoint — subtask retry and activity-event idempotency (2026-11-21)

## Organization V1 — active, not accepted

The subtask creation path is now explicitly covered for idempotent retries and activity-event accounting. The server fingerprint binds a request to `kind: SUBTASK`, parent task ID, requested project ID, normalized title, priority, due time and estimated minutes. Same-owner/same-payload retries return the existing subtask; reuse with a different parent is rejected. New requests still perform owner-scoped parent/project checks.

The trusted task trigger records one `TASK_CREATED` event for a non-recurring subtask in the same statement transaction. Sequential and two-session concurrent duplicate-subtask tests now verify that only one child row and one event are created.

Implementation/test HEAD: `0e9bd766acd6e0a25758de808d3f76ce8301c458`; [CI #526 passed on this exact HEAD](https://github.com/mohith-krishnaa/personal-os/actions/runs/44898421863). Verification: 33/33 PostgREST preflight tests; all 27 repository migrations replayed with Organization/RLS assertions, subtask retry/event checks, and migration reapplication; task-hierarchy concurrency; 201/201 application tests; typecheck; production build; npm install audit 0 vulnerabilities. No lint script is configured.

No migration, production schema, RLS policy, production data or project setting changed. No production query was performed; the last recorded live ledger remains 8 applied migrations versus 27 repository migrations (19 branch-only), not refreshed in this run.

**Organization V1 acceptance gates remain open:** complete owner-controlled schema/data/roles backup; successful isolated restoration; extension/role/default-ACL/database-setting/Auth-trigger/Vault/`ensure_rls`/reminder-function verification; checklist conflict disposition; authenticated two-owner PostgREST acceptance; and the separate owner decision on fail-closed `ensure_rls`. Analytics, AI Assistant, Research Agent, Adaptive Scheduling and production hardening remain queued behind Organization acceptance.

**Next task:** owner-controlled complete backup and isolated restoration. Verify the manifest, restore to a separate isolated Supabase project, then perform the customization, migration, checklist and authenticated two-owner acceptance sequence. Do not start Analytics based on CI alone.
---

# Latest verified roadmap checkpoint — tab-scoped task-create retry continuity (2026-11-21)

## Organization V1 — active, not accepted

The quick-add, full task editor, and subtask editor now retain pending request UUIDs across component remounts/page reloads in the same browser tab. The shared helper persists only a SHA-256 payload fingerprint, request UUID, and pending/completed state in sessionStorage; independent form instances use React useId-based keys. Successful requests are marked complete, while separate pending payloads remain recoverable. If storage or Web Crypto is unavailable, the code falls back to in-memory retry state.

Implementation/test HEAD: `5e8152f41a3760c2f0a74430e3e1ba5d1a6b846b`; [CI #524 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44894326887). Verification: 33/33 PostgREST preflight tests, repository migration replay with Organization/RLS assertions, task-hierarchy concurrency checks, 199/199 application tests, typecheck, production build, and npm install audit with 0 vulnerabilities. No lint script is configured. CI #523 exposed a missed synchronous subtask-manager caller; that typecheck failure was corrected before the authoritative #524 pass.

No migration, database schema, RLS policy, production data, or production project setting changed. The last recorded live ledger remains 8 applied migrations versus 27 repository migrations (19 branch-only); it was not refreshed in this task.

The stored SHA-256 fingerprint is not encryption or authentication and may be guessable for low-entropy payloads. Pending state is tab-scoped, not cross-tab or cross-device. The browser does not store task text, API keys, or credentials.

**Organization V1 acceptance gates remain open:** complete owner-controlled schema/data/roles backup; successful isolated restoration; extension/role/default-ACL/database-setting/Auth-trigger/Vault/`ensure_rls`/reminder-function verification; checklist conflict disposition; and authenticated two-owner PostgREST acceptance. The fail-closed `ensure_rls` candidate still requires explicit owner approval and isolated-target testing. Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance.

**Next task:** owner-controlled complete backup and isolated restoration. If owner artifacts remain unavailable, perform a distinct bounded audit of the subtask creation/activity-event retry path. Do not start Analytics based on passing CI alone.

---

# Latest verified roadmap checkpoint — PostgREST acceptance partial-failure cleanup (2026-11-21)

## Organization V1 — active, not accepted

The two-owner PostgREST acceptance harness now recovers marker-matched fixture rows when an INSERT may have committed but its HTTP response was lost. Recovery is scoped by the authenticated owner's user_id, validates owner identity again before deletion, deduplicates returned/recovered IDs, attempts all per-row deletes, and includes recovered task IDs in an owner- and entity_type=TASK-scoped retained-event count. The harness never deletes append-only activity events. If task recovery or event counting fails, the count is explicitly marked incomplete and the run marker is emitted for manual reconciliation.

Implementation/test HEAD: 0d86584084a2f186da19ed0124b5ed08eddb1e5d; [CI #521 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44889487367). Verification: 33/33 PostgREST preflight tests, 27/27 PostgreSQL 17 migrations replayed with Organization/RLS assertions, task-hierarchy concurrency checks, 194/194 application tests, typecheck, production build, and npm install audit with 0 vulnerabilities. No lint script is configured.

At the implementation checkpoint, branch feature/organization-v1 was 600 commits ahead and 0 behind main (2b42dd17796b75dca79434a81d4e1f0cbf0fa043). PR #11 remained open and unmerged; PR #12 remained an open superseded draft. Migration count remains 27. No migration or production change was made.

No production Supabase query or mutation occurred. The last recorded live ledger remains 8 applied migrations versus 27 repository migrations (19 branch-only); it was not refreshed in this task.

**Organization V1 acceptance gates remain open:** complete owner-controlled schema/data/roles backup; successful isolated restoration; extension/role/default-ACL/database-setting/Auth-trigger/Vault/ensure_rls verification; checklist conflict disposition; and authenticated two-owner PostgREST acceptance. The fail-closed ensure_rls candidate still requires explicit owner approval and isolated-target testing. Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance.

**Next task:** complete owner-controlled backup and isolated restore. If owner artifacts remain unavailable, continue a distinct bounded Organization audit. Do not start Analytics based on passing CI alone.

---

# Latest verified roadmap checkpoint — legacy anon JWT structural preflight (2026-11-21)

## Organization V1 — active, not accepted

The isolated PostgREST acceptance key gate now validates legacy anon JWT structure rather than trusting only the payload role. It requires three non-empty base64url segments, a JSON-object header/payload, `alg=HS256`, optional `typ=JWT`, and `role=anon`. It rejects malformed segments/JSON, unsupported algorithms/types, empty or malformed signatures, secret keys, unknown opaque strings, and non-anon roles. Signature and expiry verification remain server-side; the local gate is not cryptographic verification. Non-empty `sb_publishable_...` keys remain accepted.

Implementation/test HEAD: `40a61594fa0a84d2745813f3987511c0370a1be4`; [CI #519 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44884424453). Verification: 29/29 PostgREST preflight tests, 27/27 PostgreSQL 17 migrations replayed with Organization/RLS assertions and task-hierarchy concurrency checks, 190/190 application tests, typecheck, production build, and npm install audit with 0 vulnerabilities. No lint script is configured. CI #516–#518 exposed test-fixture and stale-assertion failures in the preflight suite; these were corrected before the authoritative #519 pass.

At the starting checkpoint, branch `feature/organization-v1` was 594 commits ahead and 0 behind main (`2b42dd17796b75dca79434a81d4e1f0cbf0fa043`). PR #11 remains open and unmerged; PR #12 remains an open superseded draft. The branch now contains four commits since starting HEAD `122f8bb5ad388920ab428b5eac858cf1784c0137`; only the acceptance harness, its tests, and its runbook changed. Migration count remains 27.

No production Supabase query or mutation occurred. The last recorded live ledger remains 8 applied migrations versus 27 repository migrations (19 branch-only); it was not refreshed here. No production schema, RLS, role, or data change occurred.

**Organization V1 acceptance gates remain open:** complete owner-controlled schema/data/roles backup; successful isolated restoration; extension/role/default-ACL/database-setting/Auth-trigger/Vault/`ensure_rls` verification; checklist conflict disposition; and authenticated two-owner PostgREST acceptance. The fail-closed `ensure_rls` candidate still requires explicit owner approval and isolated-target testing. Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance.

**Next task:** complete owner-controlled backup and isolated restore. If owner artifacts remain unavailable, perform a distinct Organization audit of partial-failure cleanup and retained activity-event accounting in the PostgREST harness. Do not start Analytics based on passing CI alone.

---

# Latest verified roadmap checkpoint — PostgREST acceptance key-class validation (2026-11-21)

## Organization V1 — active, not accepted

The isolated two-owner PostgREST acceptance harness now has a strict public-key format/role gate: it accepts a non-empty `sb_publishable_...` key or a legacy JWT with `role=anon`; it rejects secret keys, malformed JWTs, unknown opaque strings, missing roles, and all non-anon JWT roles. Five regression tests cover the accepted and rejected formats. The runbook explains that this is a local key-classification check, not cryptographic verification.

Implementation/test HEAD: `c84dd038d3a4c4dd4253c0d7ca03931be823d92b`; [CI #513 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44880004720). CI evidence: 26/26 PostgREST preflight tests, 27/27 PostgreSQL 17 migrations replayed, Organization/RLS and task-hierarchy checks passed, 187/187 application tests, typecheck, production build, and npm audit with 0 vulnerabilities. The subsequent documentation checkpoint `1d76005fca0cd2a64940396cbda1295d259ac775` passed [CI #514](https://github.com/mohith-krishnaa/personal-os/actions/runs/44880155910). No lint script is configured.

At the prior documentation checkpoint, the branch was `feature/organization-v1`, 593 commits ahead and 0 behind main (`2b42dd17796b75dca79434a81d4e1f0cbf0fa043`). PR #11 was open and unmerged; PR #12 remained an open superseded draft. No migration or production change was made. The last verified production ledger is still 8 applied versions versus 27 repository migrations (19 branch-only); it was not refreshed during this task.

**Acceptance gates remain open:** complete owner-controlled schema/data/roles backup; successful isolated restoration; extension/role/default-ACL/database-setting/Auth-trigger/Vault/`ensure_rls` verification; checklist conflict disposition; and authenticated two-owner PostgREST acceptance. The fail-closed `ensure_rls` candidate still requires an explicit owner decision and isolated-target testing. Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance.

**Next task:** complete the owner-controlled backup and isolated restore. If the owner action remains unavailable, continue a distinct bounded Organization audit without repeating unavailable export attempts.

---

# Latest verified roadmap checkpoint — fail-closed ensure_rls candidate (2026-11-21)

## Organization V1 — active, not accepted

A separately guarded fail-closed candidate for the project-installed `ensure_rls` event-trigger function is prepared and CI-tested. The production source function still logs and swallows RLS-enable errors; it was not changed. The candidate logs and re-raises, making the originating DDL fail instead of allowing a public table to remain without RLS. It is not a migration, is not approved, and must not be run against production. It requires same-session isolated-target and owner-approval attestations, direct postgres identity, exact function fingerprints, owner/security/search-path, exact ACL, and event-trigger checks.

Implementation/test HEAD: `da37b785571cb97154cdc06f4448aa595a8cfce4`; [CI #510 passed on this exact HEAD](https://github.com/mohith-krishnaa/personal-os/actions/runs/44874851618). Verification included PostgREST preflight, 27-migration PostgreSQL 17 replay, Organization/RLS and task-hierarchy checks, candidate missing-attestation/wrong-role rejection, double application, fail-closed DDL error propagation, savepoint restoration, outer transaction rollback to the original source function/event-trigger baseline, npm tests, typecheck, and production build. No lint script is configured; the CI workflow has no separate npm audit step.

Fresh production read-only inspection returned 8 applied migrations versus 27 repository migrations (19 branch-only), with postgres direct-session identity and `rolsuper=false`; the original `rls_auto_enable()` fingerprint is `99be20677b456ea8d3be47bdd44fb369`, and the reviewed candidate fingerprint is `b95d4b52e100f89abf4b5afa270a4776`. No migration was added and no production DDL/DML, RLS/role/project-setting change, backup, restore, or PR merge occurred.

**Acceptance gates remain open:** complete owner-controlled schema/data/roles backup; successful isolated restoration; extension/role/default-ACL/database-setting/Auth-trigger/Vault/ensure_rls verification; checklist conflict disposition on the restored copy; and authenticated two-owner PostgREST acceptance. The owner has not approved the fail-closed behavior. Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance.

**Next task:** obtain an explicit owner decision on the fail-closed candidate. If approved, test/apply it only on the fully restored isolated Supabase target; keep production read-only. Do not start Analytics based on disposable CI alone.

---

# Latest verified roadmap checkpoint — ensure_rls restore role correction (2026-11-21)

## Organization V1 — active, not accepted

The isolated `ensure_rls` restore procedure now matches Supabase's hosted role model. The source project's `postgres` role is not a PostgreSQL SUPERUSER, but Supautils permits it to create/manage event triggers. The restore script requires a direct postgres session, preserves the same-session isolated-target attestation, verifies the exact function body/security/search-path/ACL and event-trigger definition, and creates the event trigger as postgres. It rejects a different SUPERUSER identity rather than treating superuser status as sufficient.

Read-only preflight query 21 checks the PUBLIC EXECUTE ACL; query 22 reports the actual restore session identity and postgres `rolsuper` value. The source ACL is exactly postgres/service_role, with PUBLIC/anon/authenticated denied.

The behavior test verifies public-table RLS enablement, non-public-schema skip, and the source exception path. That path still logs and swallows an inner RLS-enable failure, so CREATE TABLE can continue without RLS; this is documented as a potential fail-open DDL behavior and requires owner review before any change.

**Implementation/test HEAD:** `2443e93dcdaf404c026841558ec4236a7504d703`; [CI #505 passed on this exact HEAD](https://github.com/mohith-krishnaa/personal-os/actions/runs/44872382080). Verification: PostgREST preflight 21/21; PostgreSQL 17 migration replay 27/27; Organization/RLS, hierarchy, ensure_rls restore/idempotence/ACL/exception assertions passed; 182/182 application tests; typecheck; production build; npm audit 0 vulnerabilities. No lint script is configured. CI #502/#503 exposed a false-positive static matcher, and #504's over-escaped matcher was corrected before the authoritative #505 pass.

No migration was added. Repository migration count remains 27; production ledger remains 8 (19 branch-only). Production was queried read-only; no DDL/DML, migration, RLS/role/project-setting change, backup, restore, or merge occurred.

**Acceptance gates remain open:** complete owner-controlled schema/data/roles backup; successful isolated restoration; extension/role/default-ACL/database-setting/Auth-trigger/Vault verification; restored-copy checklist conflict disposition; and authenticated two-owner PostgREST acceptance. CI's local PostgreSQL superuser does not emulate Supautils' hosted event-trigger capability; this must be verified on the restored Supabase target.

Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance. Do not start Analytics based on passing disposable CI or empty tables.

---

# Latest verified roadmap checkpoint — 2026-11-21

## Organization V1 — active, not accepted

The latest audit corrected two restore classifications:
- `claim_due_reminders(integer)` matches the applied eight-migration baseline. Branch-only `20261120000300_atomic_reminder_delivery.sql` is the pending atomic replacement, not out-of-ledger drift.
- `ensure_rls` / `rls_auto_enable()` is a project-installed optional event-trigger customization, not a Supabase-managed built-in or a repository-created object. The current function logs and swallows RLS-enable exceptions; the migration chain only revokes anon/authenticated EXECUTE and does not enforce the currently absent PUBLIC grant.

Two static regression tests protect these boundaries. The disposable bootstrap is explicitly documented as a no-op stub, not a production behavior simulation. No migration or production change was made. CI #489 exposed one TypeScript tuple-typing error after 181/181 tests passed; the assertion was corrected in `ec92d85946001f261c87bc1059d9540edacf2ab3`. CI #490 passed on that exact implementation/test HEAD: 21/21 preflight, 27/27 migrations, Organization/RLS and hierarchy checks, 181/181 tests, typecheck, build, and 0 npm vulnerabilities.

Organization acceptance remains blocked by complete owner-controlled backup, successful isolated restoration, managed/project settings verification, checklist conflict disposition, and authenticated two-owner PostgREST acceptance. Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued.

---

# Latest verified roadmap checkpoint — 2026-11-21

## Organization V1 — active, not accepted

Managed-schema/project-level restore audit is implemented and CI-verified. The offline manifest verifier requires 45 row-count keys; all 36 Auth/Storage/Vault/Realtime managed/ephemeral data counts must be zero for the manual CLI logical-backup path. The source snapshot at 2026-11-21 03:23 UTC showed nine public application tables and all 36 managed/ephemeral tables empty.

The isolated Auth trigger restore script requires explicit same-session `app.personal_os_restore_target='isolated'` attestation. The public `ensure_rls` event trigger and `public.rls_auto_enable()` must be verified after schema restore. The out-of-ledger `public.claim_due_reminders(integer)` function has live `search_path=public`, while the branch migration expects `pg_catalog, public`.

CI #487 passed on `293068da23e1f47b3c6b26b10fd21852bd1449e3`: PostgREST preflight 21/21, 27 migration replay/Organization-RLS checks, task hierarchy concurrency, isolated Auth trigger refusal and idempotent restore, 179/179 application tests, typecheck, production build, and 0 npm vulnerabilities. CI #479 had a test-message mismatch that was corrected; #480 and #487 passed.

**Acceptance gates remain open:** complete owner-controlled schema/data/roles backup, successful isolated restoration, extension/role/default-ACL/database-setting verification, checklist conflict disposition on the restored copy, and authenticated two-owner PostgREST acceptance. Current organization is Free; native Restore-to-New-Project is paid-plan-only. No production migration or PR merge is authorized.

Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance. Do not start Analytics based on empty tables or disposable CI alone.

# Latest CI follow-up — 2026-11-21

The isolated Auth trigger restore script now requires an explicit same-session `app.personal_os_restore_target='isolated'` attestation. The disposable migration runner verifies that the script refuses to run without the attestation and can be applied twice when the target is explicitly marked isolated.

CI #482 passed on `ce77eef14abed0fe6fc37fc42f2401ff47e277b4` with 21/21 PostgREST preflight, 27 migration replay/Organization-RLS checks, 178/178 application tests, typecheck, build, and 0 npm vulnerabilities. It predates the session-GUC guard; verify CI on the latest branch head before counting the guard as accepted.

Organization V1 remains in progress. Backup, isolated restoration, settings/ACL verification, checklist conflict disposition, and authenticated two-owner PostgREST acceptance remain open. Analytics and all later milestones remain queued.

# Latest roadmap checkpoint — 2026-11-21

## Organization V1 — active, not accepted

The managed-schema/project-settings audit and isolated Auth trigger restore guard are implemented. The manual CLI manifest verifier requires 45 row-count keys; all 36 Auth/Storage/Vault/Realtime managed/ephemeral data counts must be zero. The source snapshot at 2026-11-21 03:23 UTC showed all nine public application tables and all 36 managed/ephemeral tables empty.

Restore dependencies documented:
- Recreate `auth.users.on_auth_user_created` on the isolated target; the default CLI dump excludes the Auth schema even though the public function is included.
- Verify the public `ensure_rls` event trigger and `public.rls_auto_enable()`.
- Review out-of-ledger `public.claim_due_reminders(integer)` drift: live `search_path=public`, branch migration expects `pg_catalog, public`.
- Reconcile source/target extensions, default ACLs, role memberships/settings, database settings, Realtime publication, and Dashboard-only Auth/API/Storage/Vault/Secrets configuration.

CI #482 passed on `ce77eef14abed0fe6fc37fc42f2401ff47e277b4` with 21/21 PostgREST preflight tests, 27 migration replay, Organization/RLS assertions, 178/178 application tests, typecheck, build, and 0 npm vulnerabilities. The isolated-target session-GUC guard was added after that SHA; verify CI on the actual latest head.

**Acceptance gates remain open:** owner-controlled schema/data/roles backup, successful isolated restoration, extension/role/default-ACL/setting verification, checklist conflict disposition on the restored copy, and authenticated two-owner PostgREST acceptance. Current organization is Free; native Restore-to-New-Project is paid-plan-only. No production migration or PR merge is authorized.

Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance. Do not start Analytics based on empty tables or disposable CI alone.

# Latest roadmap checkpoint — 2026-11-21

## Organization V1 — active, not accepted

The managed-schema and project-setting restore audit is now documented. The manual CLI backup verifier requires 45 row-count keys; all 36 Auth/Storage/Vault/Realtime managed/ephemeral data counts must be zero. The read-only inventory snapshot at 2026-11-21 03:23 UTC showed all nine public application tables and all 36 managed/ephemeral tables empty.

The audit also identified the project-owned Auth trigger that must be restored separately, the `ensure_rls` event trigger that must be verified after public schema restore, and an out-of-ledger `claim_due_reminders` function whose live `search_path=public` differs from the branch migration's `pg_catalog, public` contract. No production change was made.

CI #478 passed on `61b33d08f97b04f6776b7cf9f262cdeafddecdf8` with 27 migration replay, Organization/RLS assertions, isolated Auth trigger restore, 177/177 application tests, typecheck, build, and 0 npm vulnerabilities. A later inventory-contract test and error-text clarification were committed after that run; check CI on the actual latest head.

**Acceptance gates still open:** complete owner-controlled schema/data/roles backup, successful isolated restoration, extension/role/default-ACL/setting verification, checklist conflict disposition on the restored copy, and authenticated two-owner PostgREST acceptance. The current organization is Free; the native Restore-to-New-Project feature is paid-plan-only. No production migrations or PR merge are authorized.

Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind Organization acceptance. Do not start Analytics based on empty tables or passing disposable CI.

# Latest roadmap addendum — verifier fixture scan (2026-11-21)

The offline backup manifest verifier remains the latest Organization V1 code-side improvement. A test-only follow-up commit \`f4e18514714333fc6cfd5a0916159d905082abef\` rewrites the synthetic connection-string fixture as fragments to avoid a false-positive credential-pattern scan. Runtime behavior and manifest contract are unchanged. CI #471 passed on the preceding HEAD; the final checkpoint must be verified on its own commit. The nine-file credential-pattern scan now returns zero matches.

Organization V1 remains in progress and blocked on owner-controlled complete backup, successful isolated restore, checklist conflict disposition, and authenticated two-owner PostgREST acceptance. Analytics remains queued.

---

# Latest roadmap checkpoint — offline backup manifest verifier (2026-11-21)

Branch: \`feature/organization-v1\`. Corrected code/test HEAD \`1dbd3ab6e73709ead9ae5d46c1d107d42d3295a4\` passed CI #468. Inventory hardening HEAD \`8c925641e7a3b86d3baaa0f439c4bb28c39a88e3\` passed [CI #470](https://github.com/mohith-krishnaa/personal-os/actions/runs/44855941859). PR #11 remains open/unmerged; PR #12 remains an open superseded draft.

## Organization V1

- **Completed:** offline backup-manifest verifier, 24 regression tests, and root ignore rules. It validates current clean Git commit, exact eight-version source ledger, repository migration inventory, required extension names, 13 row-count fields, five export command status/target attestations, and five artifact sizes/SHA-256 hashes. It rejects symlinked migration files and artifact paths.
- **Safety boundary:** verifier is offline/read-only. It does not create a backup, prove CLI target output, inspect SQL dump completeness, or verify a restore. Backup manifest and dump files must remain outside the repository.
- **CI:** #467 initially failed three fixture assertions (172/175 passed); corrected. #468 passed 175/175 tests. #469 passed on documentation checkpoint. #470 passed on hardened code/test HEAD: PostgREST preflight 21/21, PostgreSQL 17 migrations 27/27, task hierarchy concurrency, 176/176 tests, typecheck, production build, npm install audit 0 vulnerabilities.
- **Still blocked:** owner-controlled complete backup and successful isolated restore; project-level Auth/Realtime/webhook/secret inventory; extension/Vault root-key/Auth trigger/default-ACL verification; restored-copy checklist conflict disposition; authenticated two-owner PostgREST acceptance.
- **Next:** owner creates private backup and manifest, runs verifier from exact clean commit, restores into a separate isolated project, and completes all restore gates. Production remains read-only.

## Roadmap order

- **Organization V1:** in progress; do not mark complete before isolated restore and authenticated acceptance.
- **Analytics:** queued until Organization acceptance is genuinely verified.
- **AI Assistant:** queued.
- **Research Agent:** queued.
- **Adaptive Scheduling:** queued.
- **Production hardening:** pending.

---

# Latest roadmap checkpoint — offline backup manifest verifier (2026-11-21)

**Branch:** \`feature/organization-v1\`. **Corrected code/test HEAD:** \`1dbd3ab6e73709ead9ae5d46c1d107d42d3295a4\` — [CI #468 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44855630997).  
**PR #11:** open/unmerged. **PR #12:** open/superseded draft.

## Organization V1

- **Completed in this run:** offline backup-manifest verifier and 23 regression tests. It validates the current clean Git commit, exact eight-version source ledger, current repository migration inventory, required extension names, 13 row-count fields, five successful export command attestations, and five artifact file sizes/SHA-256 hashes.
- **Safety boundary:** verifier is offline/read-only and rejects credentials, symlinks, unsafe paths, and repository-local backup artifacts. It does not create a backup, prove CLI target output, inspect SQL dump completeness, or verify a restore.
- **CI:** #467 initially failed three fixture assertions (172/175 passed); corrections were made. CI #468 passed on the corrected code/test HEAD: 21/21 PostgREST preflight, 27/27 PostgreSQL 17 migrations, task hierarchy concurrency, 175/175 application tests, typecheck, production build, and npm install audit 0 vulnerabilities.
- **Still blocked:** owner-controlled complete backup and successful isolated restore; project-level Auth/Realtime/webhook/secret inventory; extensions/Vault root-key/Auth trigger/default-ACL verification; restored-copy checklist conflict disposition; authenticated two-owner PostgREST acceptance.
- **Next:** owner creates the private backup and manifest, runs the verifier from the exact clean commit, then restores into a separate isolated project and completes all restore gates. Production remains read-only.

## Roadmap order

- **Organization V1:** in progress; do not mark complete before isolated restore and authenticated acceptance.
- **Analytics:** queued until Organization acceptance is genuinely verified.
- **AI Assistant:** queued.
- **Research Agent:** queued.
- **Adaptive Scheduling:** queued.
- **Production hardening:** pending.

---

# Latest roadmap checkpoint — Organization backup/restore preflight (2026-11-21)

**Branch:** `feature/organization-v1`. **Runbook commit:** `1b9c2ca12145226f865d22414f95de6170729e54` — [CI #464 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44849631968).  
**Checkpoint docs commit:** `cd4ccb1c3accffec12e719b9b2f497079026ea55` — [CI #465 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44849845193).

## Current milestone status

- **Organization V1 — in progress.** Runtime checklist access is canonical-only with a regression guard; trusted activity-event PostgREST acceptance harness is implemented. The backup/restore runbook now uses current Supabase CLI v3/v4 `--remote=<url>` syntax, imports roles before target default-ACL preparation, revokes target defaults for tables/functions/sequences, and records a fresh 2026-11-21 source inventory. None of the 19 branch-only migrations has been applied to production.
- **Analytics — queued.** Do not start until the complete backup has been restored in isolation, the 19 migrations pass on that restored copy, checklist conflicts are dispositioned, and authenticated two-owner PostgREST acceptance passes.
- **AI Assistant — queued.**
- **Research Agent — queued.**
- **Adaptive Scheduling — queued.**
- **Production hardening — pending.**

## Verified source baseline and blockers

- Live Supabase project is ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, region `ap-southeast-1`; eight project migrations are applied. The branch contains 27 migrations, leaving 19 branch-only.
- Nine public application tables are RLS-enabled and empty; `checklist_items` and `task_checklist_items` are absent from the source baseline. `auth.users`, Storage buckets/objects, and Vault secrets are zero. Four extension versions, the custom Auth profile trigger, 12 auth/storage triggers, and absence of auth/storage RLS policies are documented in the preflight runbook.
- A complete owner-controlled schema/data/roles backup and successful isolated restore are still missing. The environment has no backup/export connector action or local Supabase CLI/Docker/pg_dump/psql. Production remains read-only.

## Next action

Owner-controlled backup and isolated restore using the updated preflight runbook. If that owner action remains unavailable, continue with a distinct safe Organization task such as an offline backup-manifest verifier; do not repeatedly attempt export and do not start Analytics.

---
# Latest verified checkpoint — legacy checklist runtime audit and cutover guard (2026-11-21)

**Starting branch HEAD:** `ba5b1548c492ff79cccbca9b9a88d36724624fd8` — CI #455 passed.  
**Code/test HEAD:** `c8a5fdc75165f32654dcd22bdb8017d2b193f3ee` — [CI #456 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44843369999).  
**Branch:** `feature/organization-v1`. **Repository migrations:** 27; no migration was added.  
**PR #11:** open and unmerged. **PR #12:** open, superseded draft.

## Continuity recovery

- The latest stored automation result predates the recorded current run and belongs to the previous checklist-conflict audit; it was not attributed to the current run.
- The previous completed task was checklist reconciliation conflict disposition. No partial code change was left to recover.
- The current branch and PR head were verified through GitHub. No local checkout is attached; a clone attempt failed because this environment could not resolve `github.com`. Remote working-tree cleanliness therefore cannot be certified.

## Legacy checklist caller audit

A recursive Git tree walk at the starting HEAD enumerated 62 TypeScript/TSX/JavaScript/JSX files across `src/` and `lib/`, plus root `middleware.ts`. All 63 files were fetched and scanned.

- No runtime application module references `task_checklist_items`.
- `src/lib/checklists.ts` uses only canonical `checklist_items`; authenticated dashboard actions resolve the user with `auth.getUser()` and pass that user ID to the service.
- `src/lib/checklists.test.ts` asserts canonical table selection and owner/task filters.
- The only non-test script intentionally writing the legacy table is `scripts/postgrest-organization-acceptance.ts`. It creates, updates, and deletes uniquely marked rows in both tables through two disposable authenticated owners to test the compatibility surface. This is not product runtime or evidence of external-client traffic.
- SQL fixtures and migration assertions also exercise legacy CRUD/RLS and conflict handling; these are test-only references.

The 27 migration files were scanned. Relevant legacy-table behavior is limited to:
- `20260905170100_organization_v1_checklists.sql`: creates the transitional table and authenticated owner/task-scoped CRUD policies.
- `20261015000200_reconcile_checklist_tables.sql`: one-time same-owner copy into canonical `checklist_items`, preserving canonical ID collisions with `ON CONFLICT (id) DO NOTHING`.
- `20261117000200_harden_checklist_select_ownership.sql`: adds task-owner validation to legacy SELECT visibility.

No migration installs a legacy-to-canonical synchronization trigger. A valid legacy write after reconciliation can remain absent from the application-facing canonical table and appear as `missing_canonical` in the read-only conflict report. Authenticated legacy INSERT/UPDATE/DELETE remains permitted by the transitional policies.

External or already-deployed client usage is unknown. The last recorded production inspection (2026-11-19) found eight applied migrations and neither checklist table present. Production was not queried during this audit, so that baseline is not being represented as a fresh observation and no production legacy-traffic measurement is available.

## Regression guard and CI #456

Added `scripts/legacy-checklist-runtime-guard.test.ts` and included it in `npm test`. It scans non-test runtime files under `src/`, `lib/`, and root `middleware.ts`, failing if the transitional table name is introduced into runtime code.

Verified on code/test HEAD `c8a5fdc75165f32654dcd22bdb8017d2b193f3ee`:
- npm install: 0 vulnerabilities reported.
- PostgREST safety preflight: **21/21 passed**.
- PostgreSQL 17 migration replay: **27/27 passed**.
- Task hierarchy concurrency: passed.
- Application tests: **152/152 passed**, including the new runtime guard.
- TypeScript typecheck: passed.
- Production build: passed.
- No lint script is configured.

Non-failing CI warnings: Node's `punycode` deprecation notice and npm's install-script review advisory. No check failed.

## Legacy checklist deprecation decision

1. **Keep the current compatibility state.** Current application runtime uses canonical `checklist_items`; retain legacy owner-scoped writes until external-client usage can be measured. Do not add dual-write or synchronization behavior.
2. **Observe only after an approved rollout creates the table in the target environment.** Inventory deployed clients and observe PostgREST/API logs for legacy SELECT/INSERT/UPDATE/DELETE over an owner-approved window. Keep the exact window and evidence private; synthetic acceptance-harness traffic is not client telemetry.
3. **Freeze writes separately.** Only after zero observed use, conflict-report disposition, and owner sign-off, use a reviewed forward migration to restrict legacy INSERT/UPDATE/DELETE while retaining SELECT/export for a defined rollback and retention window. Re-run two-owner RLS tests and the conflict report.
4. **Preserve rollback.** Keep the table and read/export path during the rollback window. If an old client is found, restore the prior write policy through a reviewed forward migration; do not rewrite migration history.
5. **Remove later, separately.** Drop the legacy table only in a later migration after retention, rollback, export, and owner-approval criteria are satisfied. Do not combine write freeze and table removal.

## Safety boundary and next action

No production query, DDL/DML, migration, RLS change, backup, restore, or PR merge was performed. The complete owner-controlled schema/data/roles backup and successful isolated restoration remain outstanding, followed by restored-copy checklist conflict disposition and authenticated two-owner PostgREST acceptance. The last recorded live baseline is not freshly revalidated.

**Next owner action:** create the complete backup and restore it into a separate isolated project; verify the eight-version source baseline, reviewed Auth trigger/extensions/roles/RLS/Vault requirements, then apply the 19 branch-only migrations only to that isolated target, review the conflict report, and execute the PostgREST harness. Do not retry an unavailable export or use production as a test target. If the owner gate remains unavailable, continue a different bounded Organization audit rather than repeating this completed legacy-caller scan.

## Roadmap status

- **Organization V1:** in progress; legacy runtime caller audit and regression guard are complete, while backup/restore, conflict disposition, and authenticated PostgREST acceptance remain outstanding.
- **Analytics:** queued until Organization acceptance and activity-event API acceptance are verified.
- **AI Assistant:** queued.
- **Research Agent:** queued.
- **Adaptive Scheduling:** queued.
- **Production hardening:** pending.

---

# Previous checkpoint — checklist reconciliation operator disposition audit (2026-11-21)

**Implementation/test HEAD:** `44cde434c6507f1c492b373b6d53b60f5214bb8f` — [CI #454 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44837508847).  
**Starting HEAD:** `818442304c8419d093d55089352cb30571ed9f6b`.  
**Audit/test attempt:** `cdb6d6a5dc61c4d8e0a3875564cab2888b36adb2` — CI #453 exposed an outdated Owner A visibility assertion; the fixture counts were corrected in the implementation/test HEAD above.

## Repository recovery

- Personal-OS Builder is enabled. The latest stored automation result belonged to an older run than the recorded current run; it was not treated as the current run's result.
- Branch: `feature/organization-v1`.
- PR #11 remains open and unmerged. PR #12 remains an open superseded draft.
- The actual branch head at recovery was `8184423`; CI #452 had passed on that exact documentation head.
- No local repository checkout is attached, so local working-tree cleanliness cannot be certified. The remote diff and commit contents were inspected.

## Checklist reconciliation audit and changes

- `supabase/operations/checklist-reconciliation-conflicts.sql` remains SELECT-only. It now returns side-by-side legacy/canonical values for title, completion, position, created_at, and updated_at, plus per-field mismatch flags.
- `canonical_id_collision` is explicitly an umbrella category: owner/task differences and payload-only differences are distinguished by the flags and values.
- Added a payload-only collision fixture with the same owner, task, and ID but different title/completion/position. Migration assertions verify that the existing canonical row and legacy source both remain unchanged.
- The report test now covers four conflicts: task-owner mismatch, cross-owner/task ID collision, payload-only ID collision, and a valid legacy-only write after one-time reconciliation. The two valid rows copied by the migration remain absent from the report.
- The migration runner requires exactly four seeded conflict rows and checks the payload-only field mismatch shape. The Owner A RLS fixture now expects two canonical and three legacy rows after adding the new scenario.
- No migration was added. Repository migration count remains 27; the last recorded live ledger is 8, leaving 19 branch-only migrations. Live state was not rechecked during this static audit.

## CI #454 — implementation/test verification

- PostgREST safety preflight: **21/21 passed**.
- PostgreSQL 17 migration replay: **27/27 passed**; checklist reconciliation report and four conflict fixtures passed.
- Task hierarchy concurrency: passed.
- Application tests: **151/151 passed**.
- TypeScript typecheck: passed.
- Production build: passed.
- npm audit: **0 vulnerabilities**.
- No lint script is configured.
- CI #453 failed because Owner A's expected canonical/legacy checklist visibility counts were not updated for the new payload-only fixture. The assertions were corrected to 2 canonical and 3 legacy rows; CI #454 passed.

## Production and acceptance boundary

No production Supabase query, DDL, DML, migration, RLS modification, backup, restore, or PR merge was performed in this task. The last recorded live baseline remains 8 migrations versus 27 in the branch, but it was not freshly queried here.

Still required: owner-controlled complete schema/data/roles backup; successful isolated restoration including reviewed Auth trigger, extensions, roles, RLS and Vault requirements; checklist conflict disposition against that restored copy; authenticated two-owner PostgREST acceptance; and explicit approval before any production schema change.

## Next safe task

While the owner-controlled restore remains unavailable, audit every remaining legacy `task_checklist_items` write path and client caller. Establish a safe deprecation/cutover plan and identify whether any supported client still writes the legacy table. Do not add automatic synchronization, disable legacy writes, change RLS, or mutate production as part of that audit. Keep Analytics queued.

---

# Latest verified checkpoint — application-role append-only activity events (2026-11-21)

**Code/test HEAD:** `03217aefdefb88fee593629f217d7efaf36d538d`  
**Verification:** [CI #442](https://github.com/mohith-krishnaa/personal-os/actions/runs/44820579479) passed.

The preceding code commit `1c428b50b681905ab983f10b4663a8dcc16827a0` failed CI #441 because `organization-migration-assertions.sql` applied a broad fixture grant after migration 26 and re-granted activity-event UPDATE/DELETE. The fixture now reapplies the intended activity-event privilege contract after its generic grants. CI #442 passed on the corrected code/test HEAD.

## Verified changes

- Added migration `20261121000400_activity_events_append_only.sql` (migration 26).
- Replaced the broad `activity_events_owner FOR ALL` policy with separate authenticated owner-scoped SELECT and INSERT policies.
- Revoked all activity-event table privileges from PUBLIC and anon; authenticated and service_role now receive SELECT/INSERT only. Neither application role has UPDATE, DELETE, or TRUNCATE.
- The `postgres` table owner retains controlled maintenance privileges. The existing `auth.users ON DELETE CASCADE` remains, so account deletion can still remove that account's events. This is application-role append-only protection, **not** a tamper-proof or immutable audit log.
- Added `supabase/tests/activity-event-append-only.sql` covering policy shape, owner isolation, cross-owner INSERT rejection, authenticated/service_role UPDATE/DELETE/TRUNCATE denial, anon privilege denial, owner maintenance, and Auth-account cascade.
- Updated the migration runner to expect 26 migrations, run the new regression, and reapply migration 26 to verify idempotence. Added read-only preflight query 19.

## Access and retention audit

Inspected the current branch's application TypeScript modules under `src/`, root `lib/supabase` helpers, and the PostgREST acceptance scripts. No application module directly reads `activity_events` or issues UPDATE/DELETE against it. The two direct DELETE callers are test cleanup in `reminder-delivery-concurrency.sh` and `task-create-idempotency-concurrency.sh`; both default to `PGUSER=postgres` and retain owner-level cleanup access. No scheduled retention job, retention interval, archive table, or user-facing event reader is defined. No retention policy was invented in this change.

## CI #442 evidence

- PostgREST acceptance preflight: 17/17 passed.
- PostgreSQL 17 migration replay: 26/26 passed; migration 26 reapplication passed.
- Organization/RLS assertions, task hierarchy and concurrency checks, reminder delivery concurrency, task activity and deletion rollback/cascade tests, create-idempotency tests, and append-only event access tests passed.
- Application tests: 147/147 passed.
- TypeScript typecheck: passed.
- Production build: passed.
- npm audit: 0 vulnerabilities.
- No lint script is configured.

## Production remains unchanged

Fresh read-only inspection on 2026-11-21 reconfirmed eight production migration-ledger versions versus 26 repository migrations (18 branch-only). Production `activity_events` still has RLS enabled, owner `postgres`, the old `FOR ALL` policy, and SELECT/INSERT/UPDATE/DELETE/TRUNCATE grants to anon, authenticated, and service_role. This is the expected pre-migration state. Migration 26 has **not** been applied to production; no production DDL/DML, RLS change, backup, restore, or PR merge occurred.

Outstanding Organization acceptance gates remain: complete owner-controlled schema/data/roles backup, successful isolated restoration, restored-copy checklist conflict review, and authenticated two-owner PostgREST CRUD/isolation. Keep Analytics queued.

**Next repository task:** audit the activity-event event-type/entity-ID and retry/idempotency contract before Analytics design. Do not add a retention schedule or event reader without a defined product requirement. If owner backup/restore remains unavailable, do not retry the blocked production step.

---

> **Verified checkpoint — 2026-11-21 (transactional TASK_DELETED events).** Repository `mohith-krishnaa/personal-os`; branch `feature/organization-v1`; starting HEAD `047207c7af55422d283766459342f3e29aa0dd5d`; code/test HEAD `2ee721b051f52174fada5a803da6690ed5a9806e`; [CI #438](https://github.com/mohith-krishnaa/personal-os/actions/runs/44810205162) passed on that exact code/test HEAD. CI #436 failed after the DELETE regression itself passed because its task UUIDs collided with the existing task-create idempotency fixture (`92000000…001`). CI #437 exposed a second collision with the concurrent request winner (`93000000…001`). The delete test IDs were moved to the independently checked `94000000…` namespace after scanning all SQL test fixtures; CI #438 passed. No application behavior changed in these fixture corrections.
>
> Added branch-only migration `20261121000300_task_delete_activity_events.sql`; repository inventory is **25 migrations**. Fresh read-only Supabase inspection reconfirmed project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 in `ap-southeast-1`, with **8** live migration-ledger versions and therefore **17 branch-only migrations**. The live `tasks_parent_task_id_fkey`, `tasks_user_id_fkey`, and `activity_events_user_id_fkey` retain validated `ON DELETE CASCADE`; `tasks_owner` and `activity_events_owner` remain authenticated owner-only `FOR ALL` policies. No production trigger or schema change was made.
>
> Migration 25 replaces `public.record_task_activity_event()` as a SECURITY INVOKER function with `search_path = pg_catalog, public` and extends the task trigger to DELETE. An authenticated owner delete emits one `TASK_DELETED` snapshot event with title, status, project, parent, and recurrence-parent identifiers. Cascaded task descendants each emit their own event in the same statement transaction. Any event insertion failure rolls back the direct deletion or entire descendant cascade. The event is written only when `auth.uid() = OLD.user_id`. Service-role/admin cleanup and Auth-account cascades intentionally skip per-task DELETE events because both task and activity-event rows cascade from `auth.users`; attempting to insert a new event for an account being deleted could violate the existing FK and block account cleanup.
>
> Added `supabase/tests/task-delete-activity-events.sql`; the migration runner expects **25** migrations, runs direct/cascade delete assertions, and reapplies migration 25 after the earlier activity-event migration. Tests cover direct delete success/failure rollback, repeat-delete behavior, three-level descendant cascade, descendant failure rolling back the full cascade, Owner A/B delete isolation, event visibility, and Auth account cleanup. Read-only preflight query **18** reports trigger/function security and all three cascade FKs. Query 18 was executed against production and returned the expected pre-deployment state: trigger absent, cascade FKs present.
>
> CI #436/#437 failed only after the DELETE regression passed, due to fixture UUID collisions with existing idempotency tests. The unique namespace correction was verified by [CI #438](https://github.com/mohith-krishnaa/personal-os/actions/runs/44810205162): **17/17** PostgREST safety preflight tests; **25/25** PostgreSQL 17 migration replay; task DELETE rollback/cascade/owner isolation/Auth cleanup, task-create idempotency/concurrency, migration reapplication, Organization/RLS, reminder delivery, and hierarchy assertions passed; **147/147** application tests; TypeScript typecheck; production build; npm audit **0 vulnerabilities** (43 packages audited). No lint script is configured.
>
> **Remaining:** `activity_events` remains mutable under its owner `FOR ALL` policy and is not an immutable audit log. Service-role/Auth-account cleanup intentionally does not emit `TASK_DELETED`. Task deletion removes `client_request_id`; a durable tombstone against a very late create retry after deletion is not implemented. Complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-owner PostgREST acceptance remain mandatory. No production DDL/DML, migration, RLS change, backup, restore, or merge occurred. Analytics remains queued.
>
> **Next task:** audit every `activity_events` UPDATE/DELETE caller, retention requirement, and reader before designing an append-only/immutable event contract. Keep production read-only and Analytics queued.
>
> ---
>
> **Verified checkpoint — 2026-11-21 (task/subtask create request idempotency).** Repository `mohith-krishnaa/personal-os`; branch `feature/organization-v1`; starting HEAD `a8f62ee5b46f92579bb3ca42cae50f45a3c7f758`. Code/test HEAD `a5cf780b089c8e9013557a05e73d6f96f36c47f5`; [CI #426](https://github.com/mohith-krishnaa/personal-os/actions/runs/44806749670) passed on that exact commit. Read-only preflight query 17 was then tightened to verify the exact ordered unique key; [CI #427](https://github.com/mohith-krishnaa/personal-os/actions/runs/44806843968) passed on preflight commit `5d63c397d57e6088c7ff1f32a7ed148a4c23d28f`. The final README architecture-summary checkpoint before this state update was `ce077a4a697bff8ec3f6b99213cabf1d4a448512`; [CI #432](https://github.com/mohith-krishnaa/personal-os/actions/runs/44807105433) passed on the preceding documentation HEAD `551dabf15c9066a603e6fdc08a3c1a8165f36118`, and [CI #433](https://github.com/mohith-krishnaa/personal-os/actions/runs/44807205535) passed on `ce077a4a697bff8ec3f6b99213cabf1d4a448512`. This state/handoff/roadmap refresh is documentation-only and is verified separately on the resulting branch HEAD. PR #11 remains open/unmerged; no merge was authorized.
>
> Added branch-only migration `20261121000200_task_create_request_idempotency.sql` (repository inventory: **24 migrations**). Fresh read-only Supabase inspection reconfirmed project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 in `ap-southeast-1`; the live migration ledger has exactly **8** versions; `public.tasks` has **0** rows and neither `client_request_id` nor `client_request_hash` exists. Therefore **16 migrations are branch-only**. No production DDL/DML, migration, RLS change, backup, restore, or merge occurred.
>
> The migration adds a non-null UUID request key, a nullable SHA-256 create-payload fingerprint, a unique `(user_id, client_request_id)` constraint, a 64-character hash check, and a SECURITY INVOKER immutable-identity trigger. First-party task editor, quick-add, and subtask forms retain one client UUID for an unchanged payload; changed payloads get a new key. Server services resolve same-key retries before mutable relationship preflight, use conflict-ignore upsert for concurrent requests, compare the winning row's fingerprint, and reject key reuse with different task details. Recurrence occurrence creation continues to use its existing unique index; internal inserts receive a generated request UUID.
>
> Added helper/service/UI regression coverage and disposable PostgreSQL assertions. CI #426/#427 verified **17/17** PostgREST safety preflight tests, **24/24** PostgreSQL 17 migration replay, task-create same-owner duplicate suppression, per-owner key reuse, immutable request metadata, hash validation, a two-session concurrent duplicate race, existing Organization/RLS/hierarchy/archive/reminder assertions, **147/147** application tests, TypeScript typecheck, production build, and npm audit with **0 vulnerabilities**. CI #425 initially failed typecheck because the dashboard quick-add caller had not yet supplied a request UUID; `src/app/dashboard/task-actions.tsx` was corrected, and CI #426 passed. No lint script is configured.
>
> **Remaining:** task DELETE events are not captured; `activity_events` remains mutable and polymorphic, and task deletion removes the request key so a very late retry after deletion is not covered by a durable tombstone ledger. The owner-controlled complete schema/data/roles backup, successful isolated restore, checklist conflict review, and authenticated two-owner PostgREST acceptance remain rollout gates. Analytics stays queued.
>
> **Next task:** design and test atomic `TASK_DELETED` events for direct task deletion and descendant cascades, including rollback, owner isolation, and event persistence. Keep production read-only.

## Organization V1 — latest verified engineering checkpoint (2026-11-21)

Task INSERT/UPDATE activity events are now written by a SECURITY INVOKER PostgreSQL trigger in the same statement transaction as the task mutation. Migration `20261121000100_durable_task_activity_events.sql` is branch-only. The trigger covers task/subtask creation, meaningful task updates, status transitions, and recurring occurrence inserts; event insertion failure rolls back the corresponding task statement. No-op updates and recurring-root self-link initialization do not emit duplicate events. Repeated completion requests retry missing recurrence generation, while the existing recurrence unique index prevents duplicate occurrences.

[CI #408](https://github.com/mohith-krishnaa/personal-os/actions/runs/44802872792) passed on code HEAD `e288c55768bca52e906d51fd6b9580f3ba0cff33`. Documentation checkpoints #409, #410, and #411 passed on their exact commits, with #411 verifying `014bd50e4a4d4835927daa762cf1cc53c615b545`. The workflows verified 17/17 PostgREST safety preflight tests; 23/23 PostgreSQL 17 migrations; task-event fault-injection/retry and migration reapplication; Organization/RLS, archive, hierarchy and concurrency assertions; 133/133 application tests; typecheck; production build; npm audit 0 vulnerabilities. CI #407 exposed a TypeScript test-mock union error; it was corrected before #408.

The task-event contract is not fully idempotent at the user-intent level. Task/subtask create requests do not yet carry a stable client request key, so a retried create can produce a second task row and a second valid TASK_CREATED event. DELETE events are not captured. `activity_events` remains mutable and polymorphic, not an immutable audit log. Analytics must not interpret event counts as counts of user intent, nor infer that an absent event proves no task deletion occurred.

Organization V1 remains **in progress**. The branch contains 23 migrations; fresh read-only production inspection reconfirmed 8 live ledger versions, so 15 are branch-only. Complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist reconciliation review, and authenticated two-owner PostgREST acceptance remain mandatory. Analytics remains queued.

**Next bounded task:** add stable client-generated request IDs for task and subtask creation, enforce a per-owner unique request key, and test same-key retries and concurrent duplicate submissions. Do not make Analytics depend on user-intent event counts until this gap and DELETE semantics are resolved.

---

## Organization V1 — latest verified engineering checkpoint (2026-11-20)

The task update service now has direct service-path regression coverage. Code/test head `44ecc05f9b62a10175f9b7f608c1ff0636b1dbc3` passed [CI #403](https://github.com/mohith-krishnaa/personal-os/actions/runs/44782848704): 17/17 PostgREST safety preflight tests, complete 22-migration PostgreSQL 17 replay with Organization/RLS and hierarchy/concurrency assertions, 132/132 application tests, TypeScript typecheck, production build, and npm install audit with 0 vulnerabilities.

The update logic was extracted into `updateTaskForUser` while the public `updateTask` continues to authenticate and delegates with the authenticated owner ID. Seven tests cover omitted versus explicit-null project/parent links, partial parent reassignment, owner-scoped reads and writes, ACTIVE-project requirements, ARCHIVED-project rejection before mutation, and the explicit update-column allowlist. No migration or production schema change was made.

Organization V1 remains **in progress**. The isolated PostgREST harness is prepared but has not been run against a restored copy. Complete owner-controlled schema/data/roles backup, successful isolated restore, checklist reconciliation review, and two-owner authenticated PostgREST acceptance remain mandatory. Analytics remains queued.

Next bounded task: audit `updateTask` lookup/update/activity-event failure semantics and test only a demonstrated consistency defect.

> **Verified checkpoint — 2026-11-20 (runtime task/project relationship audit and authorization-error propagation).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; starting HEAD `eb8610888b21b4d158de068a7b33f2d7610b0c22`; code/test HEAD `065d114a2047ad0794618e5b43eb570c0f4c05cb`; [CI #400](https://github.com/mohith-krishnaa/personal-os/actions/runs/44773159878) passed on that exact code/test HEAD. PR #11 remains open and unmerged; PR #12 remains an open superseded draft.
>
> Audited the runtime project/task callers: `createTask` derives `user_id` from the authenticated user, validates owner-scoped parent/project links and requires ACTIVE for new project assignments; `updateTask` first reads the current task under `id + user_id`, resolves omitted versus explicit-null relationship fields, validates the resulting links, builds an explicit update allowlist, and constrains the UPDATE by both task ID and owner; subtask server actions authenticate before passing the owner ID to `createSubtask`, which verifies parent ownership, same-project consistency, and ACTIVE-project eligibility before inserting with that owner; `listSubtasks` verifies the parent and filters children by both owner and parent; project create/update paths derive or verify the authenticated owner and owner-scope mutations. The UI callers display caught `Error.message` values. The database triggers remain authoritative for direct PostgREST writes and race conditions.
>
> Found a real error-handling defect: task relationship preflight and subtask parent/project lookups converted **every** Supabase lookup error into “Parent task not found” or “Project not found.” This concealed SQLSTATE 42501 authorization failures and operational errors. Added `throwIfUnexpectedLookupError`: PostgREST `PGRST116` still becomes the owner-safe generic not-found result; SQLSTATE `42501` becomes a safe `Error` message (“You are not authorized to access the requested task or project.”) with the code retained; other PostgREST error objects are converted to `Error` instances with their message/code so client components do not fall back to generic “could not” text. Both task-link preflight and subtask create/list lookups use the helper.
>
> Added six regression tests across `src/lib/tasks.test.ts` and `src/lib/subtasks.test.ts` for parent/project authorization errors, error propagation through subtask create/list, and the PGRST116 owner-safe not-found case. No application API contract, migration, database function, trigger, or RLS policy changed; repository migration count remains 22.
>
> CI #398 and #399 failed because the newly inserted direct-self-parenting test header in `tasks.test.ts` was missing its opening block brace; the test file failed to parse at line 198, so typecheck/build were skipped. The syntax was corrected in commit `065d114a2047ad0794618e5b43eb570c0f4c05cb`. [CI #400](https://github.com/mohith-krishnaa/personal-os/actions/runs/44773159878) then passed on the corrected code/test HEAD: PostgREST safety preflight **17/17**; full PostgreSQL 17/22-migration replay and Organization/RLS assertions passed; hierarchy/concurrency checks passed; application tests **125/125**; TypeScript typecheck passed; production build passed; npm install audit reported **0 vulnerabilities**. No lint script is configured.
>
> This run did not inspect or mutate production Supabase. The last verified production checkpoint remains eight live migration-ledger entries versus 22 branch migrations; that state was not refreshed here. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. The complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-owner PostgREST acceptance remain outstanding. Local working-tree cleanliness cannot be certified because no local checkout is attached; the remote diff from the starting HEAD contains only the four task/subtask source and test files.
>
> **Next action:** add focused unit coverage around the actual `updateTask` service path (owner-scoped current-row read, explicit-null versus omitted relationship patch, and owner-scoped UPDATE allowlist) without introducing a migration. If the owner-controlled backup is still unavailable, keep production read-only and do not start Analytics.

---

> **Verified checkpoint — 2026-11-20 (Organization migration dependency and FK-contract audit).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test HEAD `b91e63bddb1decace36be78b3849dce02133fb9b`; [CI #396](https://github.com/mohith-krishnaa/personal-os/actions/runs/44762846651) passed on that exact HEAD. PR #11 remains open and unmerged; PR #12 remains an open superseded draft.

> Fresh read-only Supabase inspection: project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 in `ap-southeast-1`. The live migration ledger has exactly eight versions: 20260829182309, 20260830085036, 20260830103327, 20260830114218, 20260830120132, 20260830123420, 20260830141616, and 20260905162251. The branch contains 22 numbered SQL migrations, so 14 remain branch-only. All nine live public tables have RLS enabled and currently report zero rows.

> The live legacy schema matches the expected eight-version baseline: `projects.title/status` exist while `projects.name` is absent; `goals.unit/target` are absent; both checklist tables are absent; task/project/goal/reminder/notification FKs exist with the expected targets and delete actions; `notifications_reminder_unique` is a valid unique index on `notifications(reminder_id)`. The six baseline FKs inspected are validated, MATCH SIMPLE, NOT DEFERRABLE, and use ON UPDATE NO ACTION. The custom `auth.users.on_auth_user_created` trigger exists. `rls_auto_enable()` is SECURITY DEFINER with `search_path=pg_catalog`, and effective EXECUTE is denied to PUBLIC/anon/authenticated and granted to service_role. Installed extensions: pg_stat_statements 1.11, pgcrypto 1.3, supabase_vault 0.3.1, uuid-ossp 1.1.

> The 14 branch-only migrations were reviewed in timestamp order against those exact ledger versions and live catalog contracts. No missing prerequisite or dependency-order inversion was found. The migration replay script counts 22 files, replays them lexicographically, seeds legacy checklist fixtures after the legacy table is created and before reconciliation, and runs the read-only conflict report after replay.

> The audit found a fail-closed gap: the project/task FK guard and the reminder/notification migration verified ON DELETE and target columns but did not require the baseline ON UPDATE NO ACTION action when recognizing the old single-column FK. A noncanonical ON UPDATE CASCADE constraint could therefore be accepted as the expected legacy contract and then replaced with a different default action. The live baseline itself is canonical; this was a migration-guard weakness, not a detected live-schema mismatch.

> Corrected `20261119000300_ensure_project_task_foreign_keys.sql` and `20261120000200_enforce_reminder_notification_ownership.sql` to require ON UPDATE NO ACTION when matching the legacy contracts. Updated preflight query 11 to report and match the expected update action. Added rollback-only negative tests that install NOT VALID ON UPDATE CASCADE variants for project/task, reminder/task, and notification/reminder FKs and require the guards to fail closed. Migration count remains 22; no new migration was added.

> [CI #396](https://github.com/mohith-krishnaa/personal-os/actions/runs/44762846651) passed on code/test HEAD `b91e63bddb1decace36be78b3849dce02133fb9b`: acceptance preflight 17/17; PostgreSQL 17 migration replay 22/22; Organization/RLS, archive lifecycle, hierarchy/concurrency, and the new noncanonical ON UPDATE rejection cases passed; application tests 119/119; typecheck and production build passed; npm install audited 43 packages and reported 0 vulnerabilities. The workflow has no lint step. Expected SQL errors from the negative tests were matched by the runner and the step passed.

> No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. The complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and live two-owner PostgREST acceptance remain outstanding. The static audit and CI replay do not replace those owner gates.

> **Next action:** owner-controlled complete backup and isolated restore, then apply the 14 branch-only migrations only to that isolated target, review the checklist conflict report, and execute the authenticated two-owner PostgREST harness. If the owner action is still unavailable, do not retry production operations; continue with a static audit of runtime task/project create/update callers against the active-project and ownership triggers. Keep Analytics queued.

---

> **Verified checkpoint — 2026-11-20 (owner backup/restore and checklist reconciliation audit).** Repository: mohith-krishnaa/personal-os; branch: feature/organization-v1; inspected starting HEAD: 0632d89c17c67a66fea01d880f5de2b45748e8c3. CI #392 passed on that exact starting HEAD. PR #11 is open, unmerged, and its head matches the branch; PR #12 remains an open superseded draft. This run changes documentation only; the new documentation commit must receive its own CI result.
>
> Fresh read-only Supabase inspection: project gujzvkyytxsnervovvrt is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 in ap-southeast-1. The live migration ledger contains exactly eight versions (20260829182309, 20260830085036, 20260830103327, 20260830114218, 20260830120132, 20260830123420, 20260830141616, 20260905162251); the branch has 22 migrations, 14 pending relative to that ledger. No production DDL/DML, migration, RLS change, backup, restore, or merge occurred.
>
> Read-only source snapshot: all nine public application tables have zero rows; auth.users=0; storage.buckets=0; storage.objects=0; vault.secrets=0. auth.schema_migrations has 84 platform-managed rows and storage.migrations has 81; these are provider metadata, not application records to copy into a new project. Installed non-plpgsql extensions are pg_stat_statements 1.11, pgcrypto 1.3, supabase_vault 0.3.1, and uuid-ossp 1.1. There are no deployed Edge Functions and no RLS policies in auth/storage.
>
> The restore audit found one custom managed-schema object that the default Supabase CLI dump omits: auth.users.on_auth_user_created invokes public.handle_new_user(). The function is SECURITY INVOKER with search_path=public and inserts public.profiles. Its trigger DDL is in the already-applied baseline migration 20260829182309_create_personal_os_core.sql, so it must be explicitly restored/verified on the isolated copy; a schema diff against that same eight-migration baseline may not emit it. The other 11 non-internal auth/storage triggers are Storage platform triggers owned by supabase_storage_admin and must not be copied manually.
>
> The existing backup instructions were incomplete: they assumed supabase link from the repository despite no supabase/config.toml, did not preserve the supabase_migrations history separately, and did not call out the auth trigger, installed extensions, Vault root-key boundary, or Storage object bytes. The preflight and PostgREST runbooks now specify the exact artifact set, isolated restore sequence, evidence manifest, migration-history check, conflict report review, and harness gate.
>
> No backup was created. The automation container has no repository checkout, Docker, Supabase CLI, pg_dump, or psql; the connected Supabase tools expose read-only inspection but no backup-export action. The last recorded Dashboard check says the Free Plan has no scheduled backups; recheck billing at the time of the owner action. Analytics remains queued.
>
> **Next owner action:** from a private owner-controlled workstation, create roles/schema/data and migration-history exports; capture the custom auth.users trigger and any managed-schema customizations; record SHA-256 hashes and a source manifest; restore to a separate isolated Supabase project; verify extension versions, exact eight-version history, row counts, RLS/catalog contracts, and the auth trigger; then apply only the 14 branch-only migrations to that isolated target, run the checklist conflict report, and execute the two-owner PostgREST harness. Never use production for these tests.

---

> **Verified checkpoint — 2026-11-20 (isolated two-owner PostgREST acceptance harness and fail-fast CI preflight).** Repository: \`mohith-krishnaa/personal-os\`; branch: \`feature/organization-v1\`; code/CI commit \`be2b4657777522b8687e5bdad7f09482d166e49c\`; [CI #391](https://github.com/mohith-krishnaa/personal-os/actions/runs/44745594557) passed on that exact commit. The preceding implementation commit \`994b80e148932d195e40ecffbbe5ed75a56955ac\` passed [CI #389](https://github.com/mohith-krishnaa/personal-os/actions/runs/44745116701), and the documentation checkpoint \`f9abdc74213492e722587bc15f072e2cf75a7336\` passed [CI #390](https://github.com/mohith-krishnaa/personal-os/actions/runs/44745373172). PR #11 remains open and unmerged.

> Added \`scripts/postgrest-organization-acceptance.ts\`, its safety-gate tests, and the [isolated PostgREST acceptance runbook](docs/operations/organization-v1-postgrest-acceptance.md). The live harness uses two distinct password-authenticated sessions and only the isolated project's anon/publishable key; JWT service-role and \`sb_secret_\` keys are rejected. It verifies both owners' project/task/subtask CRUD, canonical \`checklist_items\` and legacy \`task_checklist_items\` CRUD, reciprocal cross-owner SELECT/INSERT/UPDATE/DELETE restrictions, cross-owner project/task/parent associations, and parent-delete cascades. Cleanup is limited to IDs returned by this run's inserts and proceeds child-first.

> The environment gate requires \`--execute\`, three explicit isolated-target/backup-restore attestations, a project ref matching the URL, two distinct test emails, and either a standard HTTPS Supabase project URL or the exact local loopback endpoint. The known production ref \`gujzvkyytxsnervovvrt\` is permanently blocked; custom domains, path/query URLs, conflicting \`NEXT_PUBLIC_SUPABASE_URL\`/\`SUPABASE_URL\`, and service/secret keys are refused. The confirmation variables are operator attestations, not proof of backup completeness or restore success.

> The first implementation CI #386 failed TypeScript typecheck because the default \`ReturnType<typeof createClient>\` inferred a \`never\` schema; migration replay, hierarchy concurrency, and 116/116 tests had passed. The fix explicitly instantiates the Supabase client generic, makes cleanup child-first, and uses \`pathToFileURL\` for cross-platform CLI detection. [CI #387](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744569497) passed with 118/118 tests; [CI #388](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744843739) passed on the documentation checkpoint; [CI #389](https://github.com/mohith-krishnaa/personal-os/actions/runs/44745116701) passed with symmetric subtask CRUD and secret-key-prefix coverage; [CI #390](https://github.com/mohith-krishnaa/personal-os/actions/runs/44745373172) passed on the next documentation checkpoint.

> Added \`npm run test:acceptance:preflight\` and a CI step that runs the **17 safety-gate tests before PostgreSQL client installation and migration replay**. The same tests remain in the full application suite. [CI #391](https://github.com/mohith-krishnaa/personal-os/actions/runs/44745594557) passed: preflight **17/17**; PostgreSQL 17 replay **22/22 migrations**; Organization/RLS, archive, hierarchy and concurrency assertions passed; full application tests **119/119**; TypeScript typecheck and production build passed; npm install audited 43 packages and reported **0 vulnerabilities**. No lint script is configured.

> No migration, schema, RLS policy, production data, or live Supabase endpoint was changed or queried in this harness-preparation run. Repository migration count remains **22**. The authenticated PostgREST harness has **not** been executed: no owner-verified complete schema/data/roles backup and isolated restore is available in this run, and no isolated test-user credentials were supplied. Unit tests exercise the safety gate only; they are not evidence of live PostgREST isolation.

> **Next owner action:** create a complete owner-controlled schema/data/roles backup; restore it into a separate isolated project; verify the restore and checklist reconciliation conflict report; create two disposable confirmed Auth users; then run the documented harness. Do not use production. Keep Analytics queued until Organization's production acceptance gates are genuinely satisfied.

> ---

> **Verified checkpoint — 2026-11-20 (isolated two-owner PostgREST acceptance harness prepared).** Repository: \`mohith-krishnaa/personal-os\`; branch: \`feature/organization-v1\`; final implementation/test commit \`994b80e148932d195e40ecffbbe5ed75a56955ac\`; [CI #389](https://github.com/mohith-krishnaa/personal-os/actions/runs/44745116701) passed on that exact commit. The preceding documentation checkpoint \`50f48930f7e5c355006c6cac2843ea93ce15733a\` also passed [CI #388](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744843739). PR #11 remains open and unmerged.

> Added \`scripts/postgrest-organization-acceptance.ts\`, \`scripts/postgrest-organization-acceptance.test.ts\`, and the [isolated PostgREST acceptance runbook](docs/operations/organization-v1-postgrest-acceptance.md). The live harness uses two distinct password-authenticated sessions and only the isolated project's anon/publishable key; JWT service-role and \`sb_secret_\` keys are rejected. It verifies both owners' project/task/subtask CRUD, canonical \`checklist_items\` and legacy \`task_checklist_items\` CRUD, reciprocal cross-owner SELECT/INSERT/UPDATE/DELETE restrictions, cross-owner project/task/parent associations, and parent-delete cascades. Both owners' subtasks now have explicit read/update/delete coverage. Cleanup is restricted to IDs returned by this run's inserts and deletes child-first.

> The environment gate requires \`--execute\`, three explicit isolated-target/backup-restore attestations, a project ref matching the URL, two distinct test emails, and either a standard HTTPS Supabase project URL or the exact local loopback endpoint. The known production ref \`gujzvkyytxsnervovvrt\` is permanently blocked; custom domains, path/query URLs, conflicting \`NEXT_PUBLIC_SUPABASE_URL\`/\`SUPABASE_URL\`, and service/secret keys are refused. The confirmation variables are operator attestations, not proof of backup completeness or restore success.

> [CI #386](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744300279) initially failed TypeScript typecheck because the default \`ReturnType<typeof createClient>\` inferred a \`never\` schema; migration replay, hierarchy concurrency, and 116/116 tests had passed. The fix explicitly instantiates the Supabase client generic, makes cleanup child-first, and uses \`pathToFileURL\` for cross-platform CLI detection. [CI #387](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744569497) passed with 118/118 tests; [CI #388](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744843739) passed on its documentation checkpoint; [CI #389](https://github.com/mohith-krishnaa/personal-os/actions/runs/44745116701) passed on the final implementation: PostgreSQL 17 replay **22/22 migrations**; Organization/RLS, archive, hierarchy and concurrency assertions passed; **119/119 application tests passed**; TypeScript typecheck and production build passed; npm install audited 43 packages and reported **0 vulnerabilities**. No lint script is configured.

> No migration, schema, RLS policy, production data, or live Supabase endpoint was changed or queried in this harness-preparation run. Repository migration count remains **22**. The authenticated PostgREST harness has **not** been executed: no owner-verified complete schema/data/roles backup and isolated restore is available in this run, and no isolated test-user credentials were supplied. Unit tests exercise the safety gate only; they are not evidence of live PostgREST isolation.

> **Next owner action:** create a complete owner-controlled schema/data/roles backup; restore it into a separate isolated project; verify the restore and checklist reconciliation conflict report; create two disposable confirmed Auth users; then run the documented harness. Do not use production. Keep Analytics queued until Organization's production acceptance gates are genuinely satisfied.

> ---

> **Verified checkpoint — 2026-11-20 (isolated two-owner PostgREST acceptance harness prepared).** Repository: \`mohith-krishnaa/personal-os\`; branch: \`feature/organization-v1\`; implementation commit \`278ba73b7efe5400f931c12197cc46c8c5f57093\` initially passed migration replay and 116 application tests but failed TypeScript typecheck because the Supabase client's default generic resolved its schema to \`never\`. Corrected in \`c9c24e2635d18336121f85cffb1ecfe9cccfc7d4\`; [CI #387](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744569497) passed on that exact code/test commit. PR #11 remains open and unmerged.

> Added \`scripts/postgrest-organization-acceptance.ts\` and its preflight tests. The live harness uses two separate password-authenticated sessions and only the isolated project's anon/publishable key; JWT service-role keys and \`sb_secret_\` keys are rejected. It exercises project, task, subtask, canonical \`checklist_items\`, and legacy \`task_checklist_items\` CRUD; reciprocal cross-owner SELECT/INSERT/UPDATE/DELETE restrictions; cross-owner project/parent/task associations; and parent-delete checklist/task cascade behavior. Cleanup is limited to IDs returned by this run's inserts and proceeds child-first.

> The environment gate requires \`--execute\`, explicit isolated-target and restored-backup attestations, a matching project ref, two different test emails, and an HTTPS standard Supabase project URL (or the exact local loopback endpoint). The known production ref \`gujzvkyytxsnervovvrt\` is permanently blocked; custom domains and conflicting \`NEXT_PUBLIC_SUPABASE_URL\`/\`SUPABASE_URL\` values are refused. No service-role key is accepted or used. The confirmation variables are operator attestations, not proof of a backup or restore.

> [CI #386](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744300279) exposed the initial type mismatch after migration replay, hierarchy concurrency, and 116/116 tests passed; typecheck failed and build was skipped. The fix instantiated the Supabase client generic explicitly, made cleanup child-first, and used \`pathToFileURL\` for cross-platform CLI detection. Two additional safety tests cover generic URL mismatch and path/query rejection. [CI #387](https://github.com/mohith-krishnaa/personal-os/actions/runs/44744569497) passed: PostgreSQL 17 replay **22/22 migrations**; Organization/RLS, archive, hierarchy and concurrency assertions passed; **118/118 application tests passed**; TypeScript typecheck and production build passed; npm install audited 43 packages and reported **0 vulnerabilities**. No lint script is configured.

> No migration, schema, RLS policy, production data, or live Supabase endpoint was changed or queried in this harness-preparation run. Repository migration count remains **22**. The authenticated PostgREST harness has **not** been executed: there is no owner-verified complete schema/data/roles backup and isolated restore available in this run, and no isolated test-user credentials were supplied. Unit tests only verify the preflight gate; they are not evidence of live PostgREST isolation.

> **Next owner action:** create a complete owner-controlled backup of schema, data, and roles; restore it into a separate isolated project; verify the restore and checklist reconciliation conflict report; create two disposable confirmed Auth users; then run the documented harness. Do not use production. Keep Analytics queued until Organization's production acceptance gates are genuinely satisfied.

> ---

> **Verified checkpoint — 2026-11-20 (reminder delivery route contract).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `b49dfe13a175fee78bd20f7c34a5c651633ac812`; [CI #384](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734936277) passed. PR #11 remains open and unmerged.
>
> Extracted the reminder delivery request logic into `src/lib/reminder-delivery-handler.ts`, with the route exporting the same handler for GET and POST. `getReminderWorkerSecret()` preserves the existing precedence (`REMINDER_WORKER_SECRET`, then `CRON_SECRET`). No deployed secret values were read or committed. The existing `vercel.json` cron still targets `/api/reminders/deliver` every five minutes.
>
> Added `src/lib/reminder-delivery-handler.test.ts` to `npm test`. Both GET and POST are tested for missing configuration, missing/wrong credentials, no admin-client creation before authorization, exactly one `claim_due_reminders({ p_limit: 100 })` RPC on success, response count mapping, empty claims, returned RPC errors, and rejected RPC promises. Thrown transport/client errors return a generic HTTP 500 without exposing the thrown detail or worker token.
>
> The first test attempt [CI #381](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734618309) failed because the generated authorization regex contained a double-escaped whitespace token; corrected in `aae5007aa31b18b2e4ec84ee2efa42443c0dc49d`. [CI #382](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734660774) then exposed a test-fixture bug: passing `undefined` activated the harness default secret, so the missing-secret case was not actually missing; corrected in `c391ac9bbeb4e206f1f5dd3f0ec62c929010b7a0`. [CI #383](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734731617) passed migration replay and all 102 application tests but failed typecheck because `ProcessEnv` did not overlap with the narrow environment object type. The resolver now accepts `Record<string, string | undefined>`.
>
> [CI #384](https://github.com/mohith-krishnaa/personal-os/actions/runs/44734936277) passed on the exact code/test commit `b49dfe13a175fee78bd20f7c34a5c651633ac812`: PostgreSQL 17 replayed **22/22 migrations**; Organization/RLS, archive, task hierarchy, and concurrency checks passed; **102/102 application tests passed**; TypeScript typecheck and production build passed. npm install audited 43 packages and reported **0 vulnerabilities**; the existing install-script allowlist warning remains. No lint script is configured.
>
> No database migration, application schema, RLS policy, or production record changed in this task. Repository migration count remains **22**. No production Supabase operation was performed; the last verified live checkpoint remains 8 migration-ledger entries versus 22 in the branch, but live state was not rechecked during this route-only task. Production rollout remains blocked on a complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation testing.
>
> **Next task:** prepare an isolated-environment authenticated two-user PostgREST acceptance harness and explicit environment preflight. It must refuse production project URLs, require an explicitly supplied isolated/restored target, test owner-scoped CRUD and cross-user denial, and never apply migrations or write to production. Keep Analytics queued.
>
> ---
>
> **Verified checkpoint — 2026-11-20 (atomic reminder delivery).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `2953e1eb29955d2464b2e565e80b41ad16a85510`; [CI #378](https://github.com/mohith-krishnaa/personal-os/actions/runs/44727301882) passed. PR #11 remains open and unmerged.
>
> A fresh read-only Supabase inspection found project `gujzvkyytxsnervovvrt` ACTIVE_HEALTHY on PostgreSQL 17.11.0.003, with 8 live migration-ledger entries and 9 public tables with RLS enabled. The live `claim_due_reminders(integer)` is still the older SECURITY DEFINER function: it locks due reminders with `FOR UPDATE SKIP LOCKED`, marks them delivered, and inserts the activity event, but it does not create the notification. Its execution is granted to `service_role` only. No production write was attempted.
>
> The branch worker previously performed notification upsert, delivered-marker update, and activity-event insert as separate PostgREST requests. If the final event insert failed after the delivered marker committed, the next run excluded that reminder and could not repair the missing event. The existing SQL claim function was not called by the route and did not create notifications.
>
> Added local-only migration `20261120000300_atomic_reminder_delivery.sql`, which replaces the claim function without changing its signature. Each claimed reminder now creates or safely reuses its matching notification, inserts `REMINDER_DELIVERED`, and only then sets `delivered_at` inside the same RPC transaction. An existing notification is reused only when its owner and task match; its read state is preserved. Any notification/event/update failure aborts the RPC statement and rolls back all writes, leaving the reminder retryable. The function remains SECURITY DEFINER with `search_path = pg_catalog, public`; EXECUTE is revoked from PUBLIC/anon/authenticated and granted only to service_role.
>
> `src/app/api/reminders/deliver/route.ts` retains its existing bearer-secret check and now calls only `claim_due_reminders(p_limit => 100)`; it no longer makes separate notification, reminder, and activity-event writes. The repository's `vercel.json` schedules this endpoint every five minutes; deployed secret configuration was not inspected.
>
> Added disposable-PostgreSQL fault-injection assertions for notification-insert and activity-event-insert failures, proving all writes roll back and retries succeed. Tests also verify an existing notification is reused without clearing `read_at`, repeated delivery produces no duplicate event/notification, and the RPC remains service_role-only. A separate two-session test proves Worker B completes with zero claims while Worker A holds the row lock, then exactly one notification, event, and delivered marker exist after Worker A commits. The migration is reapplied in CI to verify idempotence. Read-only preflight query 15 reports the function/security/locking contract.
>
> [CI #378](https://github.com/mohith-krishnaa/personal-os/actions/runs/44727301882) passed on the exact code/test commit: PostgreSQL 17 replayed **22/22 migrations**; the new migration reapplication, injected notification/event failure rollback and retry cases, existing-notification reuse, duplicate-call idempotency, two-session `SKIP LOCKED` concurrency, Organization/RLS, archive lifecycle, and hierarchy/project concurrency checks passed; **90/90 application tests passed**; TypeScript typecheck and production build passed. npm install audited 43 packages and reported **0 vulnerabilities**; the existing `esbuild@0.28.2` install-script allowlist warning remains. No lint script is configured.
>
> Repository migration count is **22**: 8 versions match the live ledger and 14 are branch-only (11 Organization/related, 1 Progress compatibility, 2 RLS performance). The new migration and route change are not deployed. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. Production rollout still requires a complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation.
>
> **Next task:** add route-level tests for the reminder endpoint's bearer-secret rejection, successful RPC result mapping, and RPC error handling; verify the cron route/secret contract without reading or exposing secret values. Keep Analytics queued until Organization acceptance is genuinely complete.
>
> ---
>
> **Verified checkpoint — 2026-11-20 (reminder/notification owner-link integrity).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `8fbf83e18fa15dc60a9a8bc8ab58563738d00df0`; PR #11 remains open and unmerged.
>
> Fresh read-only Supabase inspection confirms project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003, with 8 live migration-ledger entries and 9 public tables with RLS enabled. Live `reminders_owner_insert/update` and `notifications_owner_update` policies check `auth.uid() = user_id` only. Live `reminders.task_id`, `notifications.reminder_id`, and `notifications.task_id` are single-column foreign keys. These contracts admit cross-owner reminder/task and notification/reminder/task associations through direct authenticated SQL/PostgREST if a caller supplies its own `user_id` with another owner's existing UUID. No production write was attempted.
>
> Added local-only migration `20261120000200_enforce_reminder_notification_ownership.sql`. It fails closed if existing rows contain mismatched owners or reminder/task pairs, adds the supporting unique keys `tasks(id,user_id)` and `reminders(id,user_id,task_id)`, and replaces the weak single-column reminder/task and notification/reminder foreign keys with composite owner-aware keys. Existing `ON DELETE CASCADE` behavior is preserved; the notification's task must match its reminder's task, and a reminder task cannot be changed while a notification references it. RLS policies and application runtime code were not changed.
>
> Extended `supabase/tests/organization-migration-assertions.sql` for Owner A and Owner B under `SET ROLE authenticated`: same-owner reminder INSERT and task reassignment succeed; cross-owner reminder INSERT/UPDATE fails; same-owner notification pair reassignment and read-state updates succeed; cross-owner task/reminder references and mismatched same-owner pairs fail without changing prior links. A `service_role` fixture verifies valid worker inserts still succeed while BYPASSRLS does not bypass the composite constraints. The migration runner now expects **21 migrations**, reapplies the migration to verify idempotence, and proves unexpected additional foreign keys fail closed. Read-only preflight queries 13–14 report the new FK and supporting unique-key contracts.
>
> [CI #375](https://github.com/mohith-krishnaa/personal-os/actions/runs/44719688076) passed on the exact code/test commit: PostgreSQL 17 replayed **21/21 migrations**; authenticated Owner A/B reminder/notification ownership assertions, service-role integrity assertions, migration reapplication, unexpected-FK negative tests, Organization/RLS, archive lifecycle, and hierarchy/project concurrency checks passed; **90/90 application tests passed**; TypeScript typecheck and production build passed. npm install reported **0 vulnerabilities**. No lint script is configured.
>
> The first code/test attempt `0336eef34d4dfffd7bc498d896aadfbc1af31128` failed CI #374 because Owner A's negative notification UPDATE reused Owner B's reminder that already had a notification; the pre-existing `notifications_reminder_unique` index correctly rejected the duplicate before the new composite FK was evaluated. The test fixture was corrected by adding unused foreign-owner reminder IDs (`810...005` and `810...006`) and targeting those IDs, so the regression now isolates the composite owner FK. No production data was involved. Corrected code/test commit `8fbf83e18fa15dc60a9a8bc8ab58563738d00df0` passed CI #375. Documentation checkpoint `4329dc2c88a528d2caaacba88ddd5dafaf34866d` passed CI #376 on the exact documentation HEAD.
>
> The live project remains at 8 migrations versus 21 in the branch (13 branch-only: 10 Organization/related, 1 Progress compatibility, 2 RLS performance). The new migration has not been applied to production. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. The live schema/policy evidence is read-only; the disposable PostgreSQL authenticated-role tests are not a live PostgREST test.
>
> **Next task:** audit the reminder delivery worker's service-role notification upsert and retry/claim behavior against the new composite FK contract; keep the valid worker path covered and verify duplicate delivery remains idempotent. Production rollout remains blocked on a complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation.

> ---
>
> **Verified checkpoint — 2026-11-20 (authenticated hierarchy-cycle rejection on UPDATE).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; corrected code/test commit: `2af3b4615241c28fbbad8f10f7458bbe1aa76b5b`; PR #11 remains open and unmerged.
>
> Extended `supabase/tests/organization-migration-assertions.sql` with authenticated-role cycle tests for both owners. Owner A creates a three-level same-project chain, attempts to reparent its root beneath the descendant, requires the exact `Task hierarchy cannot contain cycles.` check violation, and verifies the original root NULL parent plus both existing descendant links remain unchanged. Owner B repeats the same attack inside its own project and verifies its root/child links remain intact. The tests run under `SET ROLE authenticated` with each owner's JWT subject and RLS enabled; no superuser bypass is used.
>
> The first test commit `041f56b8e04786b5f9dd9065edc512a05f3afa30` failed CI #367 because the Owner B PL/pgSQL block used `error_message` without declaring it. The workflow log identified the exact error (`"error_message" is not a known variable`). Corrected in `2af3b4615241c28fbbad8f10f7458bbe1aa76b5b` by declaring the diagnostic variable in Owner B's block. [CI #368](https://github.com/mohith-krishnaa/personal-os/actions/runs/44701628837) passed on the corrected commit: all **20/20 migrations** replayed in PostgreSQL 17; Organization/RLS and authenticated Owner A/B assertions passed; project archive lifecycle, hierarchy and two-session concurrency checks passed; **90/90 application tests passed**; TypeScript typecheck and production build passed. npm install reported **0 vulnerabilities**; the existing esbuild install-script allowlist warning remains. No lint script is configured.
>
> No migration, runtime application code, RLS policy, or production record changed; repository migration count remains 20. Production Supabase was not accessed during this test-only run. The last verified read-only production checkpoint remains 8 live migration-ledger entries versus 20 repository migrations; complete owner-controlled schema/data/roles backup and isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation remain mandatory rollout gates. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred.
>
> **Next task:** audit authenticated task deletion/cascade semantics. Inspect every task-delete caller and the `tasks.parent_task_id ON DELETE CASCADE` contract first; verify that deleting an owned parent removes only its intended descendant chain, unrelated tasks remain, and cross-owner deletes remain blocked by RLS. Do not change deletion behavior unless a concrete mismatch is found. Keep Analytics queued until Organization production acceptance is genuinely complete.
>
> ---
>
> **Verified checkpoint — 2026-11-20 (authenticated parent-task reassignment).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `0a4bd7e623cee437580d425d0fb71e5758febb47`; PR #11 remains open and unmerged.
>
> Extended `supabase/tests/organization-migration-assertions.sql` to exercise `parent_task_id` UPDATEs under the actual disposable-database `authenticated` role with RLS enabled. Owner A can reparent a task to another parent in the same owned project; a parent from another project owned by A is rejected with the exact same-project check violation; a parent hidden by RLS because it belongs to Owner B is rejected with insufficient privilege. Both rejected updates must preserve the original parent link. After Owner A's project is archived, the existing task can still be reparented within that historical project without changing its project link. The reciprocal Owner B cross-owner attempt also verifies its previous NULL parent remains unchanged.
>
> [CI #364](https://github.com/mohith-krishnaa/personal-os/actions/runs/44694065363) passed on the exact code/test commit. The workflow replayed all **20/20 repository migrations** in disposable PostgreSQL 17; Organization/RLS, authenticated Owner A/B and anonymous denial assertions passed; project archive lifecycle, task hierarchy and two-session concurrency checks passed; **90/90 application tests passed**; TypeScript typecheck and production build passed; npm install reported **0 vulnerabilities**. The configured workflow has no separate `npm audit` step, and no lint script is configured.
>
> No migration, application runtime code, RLS policy, or production record changed; the repository remains at 20 migration files. Fresh read-only Supabase inspection found the project ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 with **8 live migration-ledger entries** and 9 public application tables with RLS enabled. Live `projects.title/status` and `tasks.project_id/parent_task_id` exist; `projects.name` and user-defined triggers on `projects`/`tasks` remain absent. These tests run on disposable PostgreSQL and are not live PostgREST verification. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred.
>
> **Next task:** add authenticated-role UPDATE coverage for hierarchy-cycle rejection: attempt to reparent a parent beneath its descendant, require the exact cycle check violation, and verify the prior parent relationship remains unchanged. Keep Analytics queued until Organization production acceptance is genuinely complete.
>
> ---

> **Verified checkpoint — 2026-11-20 (authenticated task project reassignment).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `0da6239761d1f2fc1adf9b34d2a418517f9ae458`; PR #11 remains open and unmerged.
>
> Extended `supabase/tests/organization-migration-assertions.sql` so task project assignment and reassignment run under the actual disposable-database `authenticated` role with Owner A's JWT subject and RLS enabled. The fixture creates a second ACTIVE project owned by Owner A and exercises: an unassigned task assigned to an ACTIVE project; reassignment from one owned ACTIVE project to another; rejection of reassignment into a COMPLETED project; rejection of reassignment into an ARCHIVED project; and rejection of reassignment to Owner B's project. Rejected updates must leave the original `project_id` unchanged. The existing authenticated same-link update after archive remains covered, as do cross-owner parent INSERT denials.
>
> [CI #360](https://github.com/mohith-krishnaa/personal-os/actions/runs/44687024395) passed on the exact code/test commit. The workflow replayed all **20/20 migrations** in disposable PostgreSQL 17; Organization/RLS and authenticated/anonymous isolation assertions passed; project archive lifecycle and two-session task hierarchy/project-status concurrency checks passed; **90/90 application tests passed**; TypeScript typecheck passed; and the production build passed. The configured workflow does not run `npm audit`; no lint script is configured. No migration or runtime application code changed, and the repository remains at 20 migration files.
>
> Production Supabase was not accessed or modified during this test-only run. The last documented read-only checkpoint remains 8 live migration-ledger entries with the Organization trigger not deployed; that is not a fresh inspection for this run. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. No local checkout is attached, so local `git status` cannot be certified.
>
> **Next task:** add authenticated-role UPDATE coverage for `parent_task_id` changes: same-owner/same-project parent reassignment should succeed where valid; cross-owner and cross-project parent reassignment must fail without changing the prior relationship; existing historical tasks in completed/archived projects must remain maintainable without weakening the task-link guard. Keep Analytics queued until Organization acceptance is genuinely complete.
> ---
>
> **Verified checkpoint — 2026-11-20 (authenticated-role subtask enforcement).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test HEAD: `eb194521e6d1bb12147058530c84ce7315395a44`; PR #11 remains open and unmerged.
>
> Extended `supabase/tests/organization-migration-assertions.sql` so the task-link checks execute under the actual disposable-database `authenticated` role with Owner A/Owner B JWT subjects. The fixture explicitly verifies `current_user = authenticated` and that the role is neither superuser nor `BYPASSRLS`. Owner A can create a subtask in its ACTIVE project with the correct parent/project links; after the project is changed to COMPLETED or ARCHIVED, equivalent subtask INSERTs fail with the exact active-project check violation and leave no rows. An unchanged historical project link remains valid for authenticated updates after archive. Cross-owner parent attempts are rejected in both directions, and Owner B's existing cross-owner project-link attempt remains rejected.
>
> [CI #357](https://github.com/mohith-krishnaa/personal-os/actions/runs/44680309313) passed on the exact code/test HEAD: **20/20 migrations replayed** in disposable PostgreSQL 17; Organization/RLS, authenticated isolation and anonymous denial assertions passed; project archive lifecycle and both two-session concurrency checks passed; **90/90 application tests passed**; TypeScript typecheck and production build passed. npm install audited 43 packages and found 0 vulnerabilities. The existing esbuild install-script allowlist warning remains; no security settings were changed. No lint script is configured. Next.js reported its normal tsconfig auto-adjustment during the ephemeral CI build; no local checkout is attached to verify any local working-tree state.
>
> No migration was added or modified; the repository remains at 20 migrations. Fresh read-only Supabase inspection: project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 with 8 applied migration versions; all 9 public tables have RLS enabled. Live `projects` retains legacy `title/status`, live `tasks` has `project_id/parent_task_id`, and no user-defined triggers are present on live `projects` or `tasks`. The branch-only active-project trigger is not deployed. These authenticated-role assertions run against the disposable PostgreSQL fixture; they are not a live PostgREST/API test.
>
> Production remains read-only. No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. Owner-controlled complete schema/data/roles backup and successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation remain rollout gates. No local checkout is attached, so local `git status` cannot be certified.
>
> **Next task:** add authenticated-role UPDATE/reassignment coverage for the active-project guard: assignment to ACTIVE succeeds; reassignment into COMPLETED/ARCHIVED is rejected; same-link historical updates remain valid; cross-owner reassignment stays blocked. Keep Analytics queued until Organization acceptance is genuinely complete.
> ---

> **Verified checkpoint — 2026-11-20 (direct PostgreSQL subtask lifecycle regression).** Organization V1 remains the active milestone. Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `91075f588cd42f88b7014bb7e8d9eab8a32e3ab6`; PR #11 remains open and unmerged.
>
> The disposable lifecycle fixture now verifies direct subtask INSERTs independently of application preflight: ACTIVE project succeeds with the correct parent link; COMPLETED and ARCHIVED project links fail with the expected check violation and leave no row; an existing archived child remains attached to its archived project and parent. The existing hierarchy fixture continues to reject foreign-owner and cross-project parent links and hierarchy cycles.
>
> No migration or runtime code changed; the migration count remains 20. [CI #354](https://github.com/mohith-krishnaa/personal-os/actions/runs/44673853542) passed the full PostgreSQL 17 20-migration replay, Organization/RLS and archive lifecycle assertions, hierarchy/concurrency checks, **90/90 application tests**, typecheck, and production build. npm audit found 0 vulnerabilities; the existing esbuild install-script allowlist warning remains. No lint script is configured.
>
> Fresh read-only Supabase inspection confirms ACTIVE_HEALTHY on PostgreSQL 17.11.0.003, 8 applied migrations, legacy `projects.title/status`, task project/parent columns, RLS enabled on `projects` and `tasks`, and no user-defined triggers on those live tables. No production changes were made.
>
> Production rollout still requires a complete owner-controlled schema/data/roles backup restored successfully in isolation, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation tests. Local working-tree status is unavailable because no checkout is attached.
>
> **Next:** extend the authenticated two-owner migration fixture to test direct subtask INSERTs through the authenticated role, including ACTIVE success and COMPLETED/ARCHIVED rejection. Organization remains in progress; Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued.
> ---

> **Verified checkpoint — 2026-11-20 (two-session project archive/task-assignment serialization).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test HEAD: `c016f78410eac0ddcfd521be19890853bd5268b2` (388 commits ahead of `main`, 0 behind at this code checkpoint). PR #11 remains open, unmerged, and mergeable.
>
> The previous archive-lifecycle checkpoint left one explicit gap: the `FOR SHARE` lock in `require_active_project_for_new_task_links` had only sequential coverage. Extended the disposable task-hierarchy fixture with a project status column and included the branch-only active-project migration, then added two-session READ COMMITTED races to `organization-task-hierarchy-concurrency.sh`. The test observes the actual blocker with `pg_blocking_pids`, verifies final rows, and checks that both sessions terminate.
>
> **Assignment-first:** task assignment acquires the project row's `FOR SHARE` lock; a concurrent ARCHIVED status update is observed waiting for that transaction. After assignment commits, archive commits and the existing task/project link remains intact. **Completion-first:** the project status update commits while holding the row lock; a concurrent task assignment waits, then is rejected with the dedicated check-violation message, leaving the task unassigned. The existing concurrent hierarchy-cycle test remains in the same CI step.
>
> CI #346 failed in the new test harness because `psql -c` sends SQL directly and does not expand psql's `:'variable'` syntax; logs showed a syntax error at the colon and the probe timed out before reaching its sleep. The correction in `c016f78410eac0ddcfd521be19890853bd5268b2` uses fixed test-owned application-name literals in those read-only polling queries. [CI #347](https://github.com/mohith-krishnaa/personal-os/actions/runs/44659601808) passed on that exact code/test HEAD: all 20 PostgreSQL 17 migrations replayed; Organization/RLS and project archive lifecycle assertions passed; both project/task lock-order races and the existing hierarchy-cycle concurrency check passed; **87/87 application tests passed**; TypeScript typecheck and production build passed. No lint script is configured.
>
> No migration was added or modified; the repository remains at 20 migration files. Fresh read-only Supabase inspection confirms project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003, the live ledger still contains exactly 8 migrations, legacy `projects.title/status` and `tasks.project_id/parent_task_id` exist, `projects.name` is absent, and no user-defined triggers are present on the live `projects` or `tasks` tables. The new trigger and concurrency behavior are branch/CI-only and have not been applied to production.
>
> No production DDL/DML, migration, RLS change, backup, restore, or PR merge occurred. The owner-controlled complete schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation remain rollout gates. No local checkout is attached, so local `git status` is unverified.
>
> **Next task:** audit every runtime task INSERT/creation path (including recurring generation and subtasks) to confirm it either uses the ACTIVE-project service preflight or remains protected by the database trigger, with owner filters preserved. Do not start Analytics until Organization acceptance is genuinely complete.
>
> ---

> **Verified checkpoint — 2026-11-20 (legacy COMPLETED project status compatibility).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `7a4ec295972c0d64ff8f44a280563130ed375d40` (379 commits ahead of `main`, 0 behind). PR #11 remains open, unmerged, and non-draft.
>
> The legacy core schema permits project statuses `ACTIVE`, `COMPLETED`, and `ARCHIVED`, while the TypeScript `ProjectStatus` contract previously omitted `COMPLETED`. The project manager also rendered only active projects, hiding valid legacy completed projects. The type now represents all three persisted states; `ProjectStatusUpdate` intentionally excludes `COMPLETED`, so this compatibility fix does not introduce a new completion transition. The project manager displays completed projects in a separate section; rows are not editable, but each offers an explicit Archive action. The task-creation selector remains ACTIVE-only; existing task labels still resolve because the dashboard retains the full owner-scoped project list.
>
> Added regression coverage for active/completed/archive grouping, filtering and preserving a completed row without rewriting its status, and rejecting an application transition into `COMPLETED`. Changed exactly four code/test files: `src/types/project.ts`, `src/lib/projects.ts`, `src/lib/projects.test.ts`, and `src/app/dashboard/project-manager.tsx`. No migration, RLS policy, schema, or package script changed; the migration chain remains 19 files.
>
> [CI #338](https://github.com/mohith-krishnaa/personal-os/actions/runs/44644299182) passed on exact code/test HEAD `7a4ec295972c0d64ff8f44a280563130ed375d40`: all 19 PostgreSQL 17 migrations replayed; Organization/RLS assertions and task-hierarchy concurrency passed; **78/78 application tests passed**; TypeScript typecheck and production build passed. No lint script is configured.
>
> No local checkout is attached, so local `git status` cannot be certified. Production Supabase was not rechecked or changed in this application-only run; the last documented live ledger remains at 8 migrations. The complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation gates remain outstanding. No production DDL/DML, migration, RLS change, backup/restore, or PR merge occurred.
>
> **Next task:** continue the Organization audit with a focused review of project archive lifecycle and task-link compatibility. Preserve completed/archived semantics and existing owner filters; do not add a migration without a demonstrated schema defect.
>
> ---

> **Verified checkpoint — 2026-11-20 (project name/title compatibility audit).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test HEAD: `7cb91b4871038d866af439117ed0584af9d0e17f` (374 commits ahead of `main`, 0 behind). PR #11 is open, unmerged, non-draft, and mergeable; PR #12 remains a superseded open draft.
>
> Audited `src/lib/projects.ts`, project actions, `project-manager.tsx`, `task-editor.tsx`, dashboard task labels, the legacy core projects schema, `20260905170000_organization_v1.sql`, and `20261016000100_projects_name_title_compatibility.sql`. Current application reads and writes use canonical `projects.name`; project creation/rename derive the owner from the authenticated session, and task/project UI labels use the canonical name. No runtime `title` fallback is needed in current app code. The compatibility trigger retains the legacy `title` column for older clients and synchronizes both directions.
>
> The trigger's same-statement conflict rule was implicit but untested. Added SQL assertions that conflicting dual-column INSERT and UPDATE statements deterministically prefer canonical `name`, plus application-service assertions that create/rename payloads do not send legacy `title`. The exact net code diff from the prior head changes only `supabase/tests/organization-migration-assertions.sql` and `src/lib/projects.test.ts`. No runtime source, migration, RLS policy, or package script changed; migration count remains 19.
>
> [CI #335](https://github.com/mohith-krishnaa/personal-os/actions/runs/44636928070) passed on exact code/test HEAD `7cb91b4871038d866af439117ed0584af9d0e17f`: all 19 PostgreSQL 17 migrations replayed; Organization/RLS and project name/title assertions passed; task hierarchy concurrency passed; **75/75 application tests passed**; TypeScript typecheck passed; production build passed; npm audit found 0 vulnerabilities. npm emitted the existing install-script allowlist warning for `esbuild@0.28.2`; no security setting was changed. No lint script is configured.
>
> No local repository checkout is attached, so local `git status` cannot be certified. Production Supabase was not rechecked or changed during this application/test-only run. The last verified live checkpoint remains 8 applied migrations versus 19 in the repository; the complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation gates remain outstanding. No production DDL/DML, migration, RLS change, backup/restore, or PR merge was performed.
>
> **Next task:** audit the legacy `projects.status = 'COMPLETED'` contract against `ProjectStatus`, project-manager visibility, and task-editor selection. Do not change the schema or broaden this task without a concrete compatibility defect and tests.
>
> ---
>
> **Verified checkpoint — 2026-11-20 (legacy-goal dashboard presentation).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test head: `beedd5778a45d5ea72cf46a8675ed4bfd35099f6` (368 commits ahead of `main`, 0 behind). PR #11 remains open, unmerged, non-draft, and mergeable.
>
> The dashboard previously displayed `0%` and an empty progress bar for legacy goals with NULL/invalid measurement metadata. That was misleading: zero is not a measured percentage when no valid target/unit exists. Added `getGoalProgressPresentation` and wired the Goals & Streaks card to distinguish measurable from historical goals. Measurable goals retain total/target/unit, percentage, accessible progress bar, and progress form. Historical goals retain their summed total and streaks; the total includes a known unit when available or explicitly says the unit is unavailable. Missing target/unit details are identified, and no percentage, progress bar, or progress-entry form is rendered.
>
> Added four presentation regression cases: both metrics missing; target missing while a unit remains known; unit unavailable while a target exists; and valid measurable metrics. The net code diff from the prior checkpoint changes exactly three files: `src/lib/progress.ts`, `src/lib/progress.test.ts`, and `src/app/dashboard/page.tsx`. No migration, RLS policy, package script, or production database changed; the migration chain remains 19.
>
> CI #331 on intermediate code commit `a45440022cc14d15f83d77945cf2fb6580855c25` ran the full 19-migration PostgreSQL 17 replay, hierarchy checks, and **75/75 application tests successfully**, but typecheck failed with TS18047 because TypeScript did not narrow nullable `goal.unit` through the boolean helper. The unit is now normalized into a local string before formatting. [CI #332](https://github.com/mohith-krishnaa/personal-os/actions/runs/44628264813) passed on exact code/test head `beedd5778a45d5ea72cf46a8675ed4bfd35099f6`: migration replay, hierarchy checks, **75/75 tests**, typecheck, and production build all succeeded. npm audit reported 0 vulnerabilities. No lint script is configured.
>
> No local repository checkout is attached, so local `git status` cannot be certified. Production Supabase was not accessed or changed during this UI-only run. The previously documented owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation gates remain outstanding. No production migration, DDL/DML, RLS change, backup/restore, or PR merge was performed.
>
> **Next task:** continue Organization V1 with a read-only audit of the legacy project `title` / canonical `name` compatibility path across project service, project manager, and task editor. Do not change production or start Analytics until Organization acceptance gates are satisfied.
>
> ---
>
> **Verified checkpoint — 2026-11-20 (legacy goal progress aggregation).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test HEAD: `c9329a95b770b55168e85d349b1bd2fbde3e8bd8` (362 commits ahead of `main`, 0 behind). PR #11 is open, unmerged, non-draft, and GitHub reports it mergeable.
>
> Continued the documented Progress compatibility audit. `getGoalsWithProgress` already retained goals whose legacy `unit` and `target` are NULL, but had no direct regression coverage. Added five service tests proving that legacy goals remain in the result, their historical entries are grouped only under their own goal while preserving query order, totals and streaks remain available without fabricating a target/unit, measurable-goal percentages remain correct, empty-goal results skip the entries query, and both goals-query and progress-entry-query errors propagate. The grouping loop now appends to existing arrays rather than repeatedly copying them, keeping aggregation linear in the number of returned entries.
>
> The initial code/test commit `f98b63080aef9a3316119be736c9e078660ec080` failed CI #326 because the copied date-validation regular expression was over-escaped. The failure was inspected in the job logs and corrected in `c9329a95b770b55168e85d349b1bd2fbde3e8bd8`. [CI #327](https://github.com/mohith-krishnaa/personal-os/actions/runs/44617741781) passed on that exact corrected HEAD: PostgreSQL 17 replay of all 19 migrations, Organization/RLS assertions, task hierarchy checks, **71/71 application tests**, TypeScript typecheck, and production build. No lint script is configured.
>
> The code/test change touches only `src/lib/progress-service.ts` and `src/lib/progress-service.test.ts`. No migration, application UI, RLS policy, or production database was changed; migration count remains 19. No local checkout is attached, so local `git status` cannot be certified. Production was not rechecked during this application-only run; the last known backup/isolated-restore and authenticated two-user PostgREST gates remain outstanding.
>
> Personal-OS Builder is enabled. The automation record at recovery showed last run `9ba7d5ee-a1fc-8327-a46e-c10062739613` marked `in_progress` (started `2026-11-19T21:18:02.738390Z`, no completion timestamp); latest stored result `27abdbf5-2e34-8330-b103-a96a5eb49783` was created at `2026-11-19T20:21:42.209282Z` and belongs to an older run. An in-progress marker does not establish worker liveness.
>
> **Next task:** audit the Progress dashboard's presentation of legacy goals with historical entries, ensuring the visible total/streak remain understandable without a target/unit and that no progress-entry form is offered. Keep Analytics queued until Organization production acceptance is genuinely complete.
>
> ---

> **Verified checkpoint — 2026-11-20 (Progress legacy-metric enforcement).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `771f2b133bafc9cc834442449a07f1bfb4def5f4` (359 commits ahead of `main`, 0 behind). PR #11 is open, unmerged, non-draft, and mergeable.
>
> The application audit found two gaps: the client form only checked null metrics (so blank/invalid metadata could still reach the form path), and `logProgress` trusted the UI and inserted without re-reading the goal. Added shared `hasUsableGoalMetrics` validation (trimmed non-empty unit plus finite positive target), used it in `ProgressForm`, and added an owner-filtered goal lookup in `logProgress` before insertion. Missing/non-owned goals and goals without usable metrics are rejected. `createGoal` remains strict for new measurable goals.
>
> Added regression coverage for valid/invalid measurement metadata, create-goal validation, owner-filtered goal lookup, valid progress insertion, rejection for legacy/unconfigured and missing/non-owned goals, and date-format validation. The migration chain remains at 19 files; no migration, RLS policy, or production database was changed.
>
> Intermediate commit `e59d65b4b4b4b66d350652e21a1d23c9be04194e` failed CI #323 because the date-validation regex was over-escaped in that intermediate tree. The regex was corrected in `771f2b133bafc9cc834442449a07f1bfb4def5f4`; [CI #324](https://github.com/mohith-krishnaa/personal-os/actions/runs/44607370912) passed on that exact head: PostgreSQL 17 replay of all 19 migrations, hierarchy concurrency, **66/66 application tests**, TypeScript typecheck, and production build. No lint script is configured.
>
> Personal-OS Builder is enabled. At recovery, last run `27abdbf5-2e34-8330-b103-a96a5eb49783` was marked `in_progress` (started `2026-11-19T20:15:52Z`, no completion timestamp); latest stored result `546365dd-9274-8323-bdbb-d8c18357a5e0` was created at `2026-11-19T19:24:57Z` and belongs to an older run. This does not prove worker liveness.
>
> No production database was accessed or changed in this application-only run. The last verified production checkpoint still reported 8 applied migrations, 9 public tables with RLS enabled, and absent Organization/Progress compatibility objects; that state was not rechecked in this run. The complete owner-controlled schema/data/roles backup, successful isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation tests remain outstanding. No local checkout is attached, so local `git status` is unavailable.
>
> **Next task:** add focused regression coverage for `getGoalsWithProgress` so legacy goals with null measurement metadata remain in the result set and their historical progress entries are grouped without inventing a target or unit. Keep Organization ahead of Analytics until the production acceptance gates are genuinely complete.
>
> ---

> **Verified checkpoint — 2026-11-20 (Progress goal-metric preflight and regression coverage).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test head before this documentation refresh: `9cf0327b94c0238783cdd3c9d0a95978f01ce035` (356 commits ahead of `main`, 0 behind). PR #11 is open, unmerged, non-draft, and mergeable.
>
> A read-only static audit found that preflight query 4 omitted `goals.unit` and `goals.target`, even though branch-only migration `20261117000100_reconcile_progress_goal_metrics.sql` adds them. The preflight now reports those columns and query 12 reports their types, nullability, named check constraints, validation state, and definitions. New disposable-PostgreSQL regression coverage verifies nullable legacy metrics, valid measurable goals, rejection of whitespace-only units, and rejection of zero/negative targets. The test runs in a transaction and rolls back. The migration chain remains at 19 files; no migration was added or modified.
>
> Code/test commit `9cf0327b94c0238783cdd3c9d0a95978f01ce035` passed [CI #321](https://github.com/mohith-krishnaa/personal-os/actions/runs/44597240060): all 19 PostgreSQL 17 migrations replayed; Organization/RLS and hierarchy checks passed; the new Progress goal-metric regression test passed as part of migration replay; `npm run test`, `npm run typecheck`, and `npm run build` all passed. No lint script is configured.
>
> Fresh read-only Supabase inspection: project `gujzvkyytxsnervovvrt` is `ACTIVE_HEALTHY` on PostgreSQL 17.11.0.003; the live ledger still has 8 migrations; all 9 public tables have RLS enabled and report zero rows. Both `goals.unit` and `goals.target` are absent, and the new query 12 correctly reports both columns and their constraints absent. The live goals table still has the core `goals_owner` policy plus four legacy command-specific policies; the pending deduplication migration targets those four names. Reminder/notification/progress policies still use the existing direct `auth.uid()` predicates targeted by the pending initplan-safe migration. Existing project/task foreign keys remain exact and validated.
>
> Personal-OS Builder is enabled. Its recorded last run `546365dd-9274-8323-bdbb-d8c18357a5e0` is marked `in_progress`, started at `2026-11-19T19:16:37Z`, with no completion timestamp. Latest stored result `2137c85a-2500-832c-b819-9896e93be753` was created at `2026-11-19T18:31:15Z` and belongs to an older run. The in-progress marker does not prove worker liveness.
>
> No local checkout is attached, so local `git status` cannot be verified. No production migration, DDL/DML, RLS change, backup/restore, or PR merge was performed. Production rollout remains blocked on an owner-controlled complete schema/data/roles backup successfully restored in isolation, checklist conflict review against that restore, and authenticated two-user PostgREST CRUD/isolation tests.
>
> **Next task:** audit the Progress service and dashboard rendering against nullable legacy goal metrics, confirming creation still requires both unit and target while legacy goals without metrics remain readable and do not expose a progress-entry form. Keep Analytics queued until Organization acceptance is genuinely complete.
>
> ---

# Personal OS — Project Roadmap & Mind Map

> Single source of truth for project direction. Verify GitHub/Supabase/CI before making claims.
> Last reconciled: 2026-11-21. Organization V1 implementation/test commit `8b2cf9426cb899817c1e7bb92015b39bab3cac85` passed [CI #450](https://github.com/mohith-krishnaa/personal-os/actions/runs/44836136933): 21/21 PostgREST safety/event assertion tests, 27 PostgreSQL 17 migrations, 151/151 application tests, typecheck, production build, and npm audit with 0 vulnerabilities.

## Current position

**Completed:** Core productivity, Recurring Tasks V1, and Reminders V1. Progress & Streaks V1 application implementation is complete, but live schema compatibility repair remains pending.

**In progress:** Organization V1 remains under review on `feature/organization-v1` / PR #11. The branch contains 27 migrations; the fresh live Supabase ledger contains 8, leaving 19 branch-only. All 27 replay in disposable PostgreSQL 17. The branch includes owner-scoped Organization workflows, checklist reconciliation, task/project relationship guards, atomic reminder delivery, transactional task activity events, per-owner task-create idempotency, append-only application-role event access, and trusted event writers.

**Activity-event API acceptance prepared:** The isolated two-owner PostgREST harness now checks direct authenticated event INSERT denial, trusted `TASK_CREATED` generation, owner read access, cross-owner read isolation, and retained test-event accounting. CI #450 passed, but the live harness has not been executed.

**Production acceptance blocked:** No complete owner-controlled schema/data/roles backup has been successfully restored in isolation. The custom Auth profile-bootstrap trigger and extension/Vault restore requirements must be included. The restored-copy checklist conflict report and authenticated two-owner PostgREST acceptance remain outstanding. Production remains unchanged.

**Queued:** Analytics V1 follows Organization production acceptance. AI Assistant, Research Agent, Adaptive Scheduling, and broader production hardening remain later milestones.

## Mind map

```text
PERSONAL OS
│
├── CORE PRODUCTIVITY [DONE]
│   ├── Authentication / Dashboard / Tasks
│   ├── Status / Priority / Duration
│   ├── Activity events
│   └── Day / Week / Month calendar
│
├── TIME & SCHEDULING [PARTIAL]
│   ├── Due date/time [DONE]
│   ├── Scheduled start/end [DONE]
│   ├── Recurring tasks [DONE — PR #5]
│   ├── Reminders [DONE — PR #7]
│   └── Conflict-aware scheduling [LATER]
│
├── GOALS & PROGRESS [IMPLEMENTED — LIVE SCHEMA REPAIR PENDING]
│   ├── Generic measurable goals
│   ├── Custom units
│   ├── Progress history
│   ├── Current + longest streaks
│   └── Batched dashboard loading
│
├── ORGANIZATION [IN PROGRESS — production rollout gated]
│   ├── Projects
│   ├── Subtasks
│   ├── Checklists
│   └── Core organization workflows
│
├── ORGANIZATION EXTENSIONS [DEFERRED]
│   ├── Notes / advanced tags
│   └── Attachments (evaluate separately)
│
├── ANALYTICS [PLANNED]
│   ├── Daily / Weekly / Monthly reviews
│   ├── Planned vs actual time
│   ├── Completion + progress trends
│   └── Behavioral insights
│
├── AI ASSISTANT [LATER]
│   ├── Brain dump → tasks
│   ├── Task breakdown
│   ├── Daily briefing / review
│   └── Validated tool-based actions
│
├── RESEARCH AGENT [LATER]
│   ├── Web research
│   ├── Source extraction
│   └── Source-backed resources
│
└── ADAPTIVE PERSONAL OS [FUTURE]
    ├── Learn actual duration
    ├── Detect overload/procrastination
    ├── Predict workload
    └── Adapt schedules from behavior
```

## Execution order

1. Recurring Tasks V1 — DONE
2. Reminders V1 — DONE
3. Progress & Streaks V1 — application implementation complete; live `goals.unit` / `goals.target` compatibility repair pending
4. **Organization V1 — IN PROGRESS:** 27-migration branch implementation and disposable PostgreSQL 17 verification pass. Production backup/restore, checklist conflict review, and authenticated two-owner PostgREST acceptance remain open.
5. Analytics V1 — queued until Organization production acceptance and activity-event API acceptance are verified
6. AI Assistant V1
7. Research Agent V1
8. Adaptive Scheduling
9. Production hardening

## Definition of done — every feature

1. Data model/schema
2. Authorization/RLS
3. Backend/application logic
4. Edge cases/failure states
5. Unit/integration/regression tests
6. UI/UX
7. CI/build
8. Migration/recovery implications
9. Documentation + `PROJECT_STATE.md`

## Quality rules

- PostgreSQL/Supabase is the source of truth for persisted data.
- Never invent schema or authorization behavior.
- Preserve activity history for future analytics/adaptive scheduling.
- AI uses validated application tools rather than direct database writes.
- Merge only after CI is green.
- Security/performance findings are fixed or explicitly tracked.
- Project state must be reconciled after each milestone.

## Current engineering priorities

### P0 — Product correctness
- Keep `main` green.
- Verify authentication and owner isolation.
- Maintain regression coverage for task, recurrence, reminder and progress flows.
- Live Supabase `public.goals` was last verified without `unit` and `target`, while the dashboard progress service selects both on every load. A forward-only migration, null-safe legacy rendering, and server-side refusal to log against unconfigured goals are branch-tested; production compatibility remains pending backup/restore and migration approval.

### P1 — Organization V1
- PR #11 is the intended review path and remains open, unmerged, and non-draft. PR #12 is an open superseded draft; do not merge it separately.
- The branch contains 27 migrations: 8 match the current live ledger and 19 are branch-only. CI #450 passed the full PostgreSQL 17 replay and all Organization/RLS assertions.
- The application includes owner-scoped projects/tasks, subtasks, canonical and legacy checklists, active-project task-link guards, hierarchy-cycle protection, reminder/notification ownership, and atomic reminder delivery.
- Activity events now have transactional task INSERT/UPDATE/DELETE writers, per-owner task-create idempotency, application-role append-only access, and a trusted SECURITY DEFINER task-event writer. Authenticated users can SELECT only; direct event INSERT is rejected. The postgres owner and Auth-account cascade retain maintenance/deletion behavior, so this is not a tamper-proof audit log.
- The isolated two-owner PostgREST harness now verifies event INSERT denial, exactly one trusted TASK_CREATED event, owner read access, cross-owner read isolation, and retained test-event artifact counts. It has not been executed against a live isolated target.
- CI #450 passed: 21/21 PostgREST safety/event assertion tests, 27/27 PostgreSQL 17 migrations, task hierarchy concurrency, 151/151 application tests, typecheck, production build, and npm audit with 0 vulnerabilities. No lint script is configured.
- Fresh read-only Supabase inspection: ACTIVE_HEALTHY PostgreSQL 17.11.0.003, 8 applied migrations, 9 public tables with RLS enabled and zero reported rows. No branch migration has been applied to production.
- Production rollout remains blocked on the complete owner-controlled schema/data/roles backup, successful isolated restore (including custom Auth trigger and reviewed extensions/Vault requirements), checklist reconciliation conflict review, authenticated two-owner PostgREST acceptance, and explicit migration approval.
- Next safe engineering task while the owner restore is unavailable: audit the checklist conflict report's operator disposition workflow for `task_owner_mismatch`, `canonical_id_collision`, and `missing_canonical`, without automatic mutation. Do not start Analytics until Organization production acceptance passes.
### P2 — Production hardening
- Review foreign-key indexes and query performance.
- Complete timezone/DST semantics for reminders when scheduling requirements are defined.
- Add observability and recovery documentation.

## Branch map

- `main` — stable integrated product.
- Historical feature branches remain for traceability; do not treat them as current work unless GitHub confirms an active PR.

## Decision log

- 2026-08-30: Established persistent project-state hierarchy and mind tree.
- 2026-08-30: Scheduler/calendar integrated.
- 2026-08-30: Progress/streaks designed as a generic system rather than book-specific logic.
- 2026-09-05: Recurring Tasks V1, Reminders V1 and Progress & Streaks V1 verified as merged.
- 2026-09-05: Security issue #6 remediated and closed; security verification reported 0 lints.
- 2026-09-05: Organization V1 promoted to the next roadmap milestone.
- 2026-11-17: Keep Organization V1 fail-closed until a private logical backup is restore-tested, all local migrations are replayed against that restored snapshot, concurrent hierarchy-cycle behavior is tested, and authenticated two-user live PostgREST isolation passes. Disposable full-chain/RLS and concurrency tests now pass in CI; Free Plan scheduled backups are unavailable.


## Historical checkpoint — 2026-10-16

- Organization V1 implementation is under review in PR #11 (`feature/organization-v1`), not yet merged.
- GitHub Actions run #95 passed after the checklist migration was made repeat-safe, and run #96 passed `npm install`, `npm run test`, and `npm run build` on docs commit `04b185b0afc744a61b0a20ad5a7b169874952dd1` (https://github.com/mohith-krishnaa/personal-os/actions/runs/38873921256). Re-check CI against the current PR head before merge. Organization RLS policies use `(select auth.uid())`; the compatibility migration conditionally indexes legacy `projects.goal_id` when present. Live database rollout and authenticated end-to-end CRUD/isolation checks remain pending.
- Live database access is restored for the intended Supabase project `gujzvkyytxsnervovvrt` (`puttamohithkrishnaa@gmail.com's Project`, ACTIVE_HEALTHY). The live ledger does not yet include Organization V1 migrations; `projects` has legacy `title` and supports `COMPLETED` status.
- Next steps: finish migration review; plan a safe rollout with recovery checks; apply/verify migrations only after preflight; run Supabase security/performance advisors; then exercise authenticated owner-isolation and CRUD flows. Do not mark Organization V1 complete until these checks pass.
- Scope after Organization V1: Analytics V1, AI Assistant V1, Research Agent V1, Adaptive Scheduling, and production hardening. Each milestone needs schema/RLS, application logic, edge-case tests, UI, CI, and recovery documentation.


## Current checkpoint — 2026-11-16

- GitHub confirms PR #11 is open, unmerged, non-draft, and mergeable. The branch is `feature/organization-v1`, targeting `main`; the verified head at checkpoint start was `aa26a556cd6627a0ccd19efd914fe62be76f0ed9`.
- CI run #104 (ID `43928396020`) passed on commit `f2b9e43564663c74ac51e7f1e2356163633e21c3`: install, tests, explicit typecheck, and production build all succeeded. The following documentation refresh triggers a new CI run; verify the latest head before merge.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but migration listing, table introspection, read-only SQL, and advisor calls time out; advisors also report the project as hibernated. The live migration ledger and schema are currently unknown.
- No migrations or production data changes were made. The next safe action is to restore supported DB connectivity, inspect the live ledger/schema, confirm backup/recovery readiness, then apply reviewed migrations and test authenticated owner isolation.
- Analytics, AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain behind Organization V1 in the execution order.

## Decision log

- 2026-11-16: Keep Organization V1 as the active milestone. Do not infer live schema from repository migrations or stale October notes.
- 2026-11-16: Do not apply production DDL, create a replacement database, or merge PR #11 while the live migration ledger/schema and authenticated isolation behavior are unverified.
- 2026-11-16: Make TypeScript checking an explicit CI step (`tsc --noEmit`) rather than relying only on the Next.js production build to surface type errors.


## Current checkpoint — 2026-11-17

- PR #11 remains the active Organization V1 review: open, unmerged, non-draft, and mergeable status must be rechecked live before any merge. PR #12 is still an open draft explicitly marked superseded by PR #11; do not merge it separately.
- CI run #115 (ID `43938573918`) passed on PR head `91cd88fedef768a65286381c361b72f46d67ee29`: dependency installation, `npm run test`, `npm run typecheck`, and `npm run build` all succeeded. The run includes the new project owner-boundary tests.
- Added `docs/architecture/organization-v1.md` to record ownership boundaries, compatibility decisions, migration/recovery rules, and verification limits.
- Added service-level regression coverage proving project creation derives `user_id` from the authenticated session, updates filter by both project ID and authenticated owner, and unauthenticated updates stop before database access. These mocked-client tests do not prove live RLS or cross-user database isolation.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but repeated migration listing and verbose table inspection still fail with database connection timeouts. Read-only SQL probes time out, and advisor calls report the project as hibernated. The live migration ledger and schema remain unknown.
- No production migrations, schema changes, data changes, or PR merge were performed. Do not start Analytics until Organization's live schema, RLS, CRUD, recovery, and CI gates are verified.
- No lint script or linter configuration exists in the repository; lint is not a verified check.
- Next action: restore supported Supabase database access, inspect the live migration ledger and Organization tables, confirm recovery readiness, then continue authenticated CRUD and cross-user isolation testing.

Architecture note: [docs/architecture/organization-v1.md](docs/architecture/organization-v1.md).


## Current checkpoint — 2026-11-17 (subtask visibility)

- PR #11 remains open and unmerged; PR #12 remains an open draft superseded by PR #11.
- Added an authenticated `listSubtasksAction`. It resolves the current user server-side, validates ownership of the parent task, and reads children filtered by both `user_id` and `parent_task_id`.
- Updated the dashboard subtask panel to load children only when expanded, display their completion state, and toggle completion through the existing task-status server action. Existing create behavior remains available.
- Added service tests proving the child query includes both owner and parent filters and that a foreign-owned parent is rejected before child listing.
- CI run #120 (ID `43947823009`) passed on implementation commit `b8a686664e5e39b2ebc042192a9ea291c6d1bec7`: 33 tests passed, typecheck passed, production build passed, and npm audit reported 0 vulnerabilities. Documentation changes after that commit require the current PR head's checks to remain green.
- Lint remains unavailable because the repository has no lint script/configuration.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but migration listing, verbose table introspection, and read-only SQL still time out; security/performance advisors report hibernation. The live schema and migration ledger remain unknown.
- No production migration, schema/data write, or PR merge was performed.

Decision: keep Organization V1 active; do not begin Analytics or merge until live schema/RLS, recovery readiness, migration rollout, advisors, and authenticated cross-user CRUD are verified.


## Current checkpoint — 2026-11-17 (subtask create/list consistency)

- Live GitHub inspection confirms PR #11 is open, unmerged, non-draft, and mergeable; current pre-change head was `b466ee0ba32cae5b4a1763db50360a69e132ca28`. PR #12 remains an open draft explicitly superseded by PR #11.
- Found a UI state bug: if the initial lazy-load failed and the user then created a subtask, the component marked its partial local list as fully loaded. That hid any pre-existing subtasks until a page refresh.
- Added a small state transition helper. After creation, an already-loaded list is appended locally; an incomplete list remains marked incomplete and is refreshed through the authenticated owner-scoped read action. A failed refresh keeps the created row visible and leaves retry available.
- Disabled the Add control during an in-flight list read to prevent overlapping read/create races.
- Added regression tests for both loaded and incomplete list transitions. CI run #122 (ID `43959430815`) passed on implementation commit `3de585c8a2ba7e511f50ed0cd0be8c37d9bd1bf2`: 35/35 tests, typecheck, and production build passed; npm install reported 0 vulnerabilities. Lint is unavailable.
- No database schema or authorization behavior changed.
- Live Supabase database calls continue to fail; live migration ledger/schema remain unknown. No migration, production data/schema write, or PR merge was performed.


## Verification follow-up — 2026-11-17

- CI run #122 passed on the subtask create/list consistency implementation commit: 35 tests passed, typecheck passed, production build passed, and npm install reported 0 vulnerabilities.
- A documentation-only reconciliation follows that implementation commit; verify the resulting latest PR head's CI before merge.


## Current checkpoint — 2026-11-17 (checklist consistency)

- Organization V1 remains the active milestone in PR #11. PR #12 remains an open draft superseded by PR #11.
- Fixed a checklist UI consistency defect: creating an item after a failed list read previously displayed only the newly created row and could hide pre-existing rows. The component now refreshes the authenticated checklist list when the prior read was incomplete, retains the new row if refresh fails, exposes retry, and blocks create while loading.
- Added `src/lib/checklist-state.ts` and three regression tests for canonical ordering and incomplete-list recovery. No schema or authorization behavior changed.
- The checklist service continues to use `public.checklist_items`, verifies task ownership, and filters records by authenticated `user_id` and `task_id`.
- Latest code changes require CI verification on the current PR head. Lint remains unavailable because the repository has no lint script/configuration.
- Supabase metadata reports `ACTIVE_HEALTHY`, but live migration listing and verbose table introspection timed out again. Live schema/ledger remain unknown; no migrations or production writes were performed.
- Next priority remains database inspection and safe Organization rollout, not Analytics. Do not merge PR #11 until live schema/RLS, recovery readiness, advisors, authenticated CRUD, cross-user isolation, and current-head CI are verified.


## Verification checkpoint — 2026-11-17 (checklist recovery)

- PR #11 remains the active Organization V1 implementation; PR #12 remains superseded.
- Checklist create/list recovery is implemented and covered by three new tests. A create after an incomplete list read refreshes the authenticated canonical list, retains the created row if refresh fails, and keeps retry available. Loaded lists preserve server ordering.
- CI #128 (ID `43969545168`) passed on head `4bb083fe94fd36419f47149c3951bc9b594c98aa`: 38 tests passed, typecheck passed, production build passed, and install reported 0 vulnerabilities.
- Lint remains unavailable. Supabase metadata is `ACTIVE_HEALTHY`, but live migration/table/SQL/advisor calls fail with timeout or hibernation responses; live schema and ledger remain unknown.
- No production migration, data change, or merge was performed. Organization remains the priority; Analytics stays queued until live schema/RLS, recovery, migration, advisor, authenticated CRUD, and cross-user isolation gates pass.


## Verification checkpoint — checklist ownership coverage (2026-11-17)

- Added four service-level regression tests for checklist task-owner validation, list filters/order, foreign-task rejection, owner assignment on insert, and owner-scoped completion/deletion mutations.
- No production service, UI, schema, migration, RLS policy, or credential behavior changed in this task; only `src/lib/checklists.test.ts` changed.
- Current PR #11 head is `adfffa6f5e125ff9224e618a89ec177144663c9f`. CI #131 (ID `43978680326`) was queued at last check; test/typecheck/build results for this commit are pending.
- CI #130 passed on the parent head with 38 tests, typecheck, production build, and 0 npm audit vulnerabilities.
- Supabase project metadata is `ACTIVE_HEALTHY`; migration listing, verbose table inspection, and read-only SQL timed out. Security/performance/health advisors report hibernation. Live schema and migration ledger remain unknown.
- No production DDL, data changes, or PR merge occurred.

Organization remains the active milestone. Analytics must not start until live schema/RLS, recovery, migration, advisor, authenticated CRUD, and cross-user isolation gates are verified.


## Latest verification — checklist ownership regression coverage (2026-11-17)

- Added four checklist service tests for owner/task list filters, foreign-task rejection, owner assignment on create, and owner-scoped completion/deletion.
- CI #135 passed on current PR #11 head `bc82493c8c5533148e3d82aaf667374fd33b9ee1`: 42 tests passed, 0 failed; typecheck and production build passed; install audited 43 packages with 0 vulnerabilities.
- Initial CI #131/#132 failures were caused by missing imports in the new test file. The import correction is included in the verified head.
- Supabase project metadata remains `ACTIVE_HEALTHY`, but live migration/table/SQL calls time out and advisors report hibernation. Live schema and migration ledger remain unknown.
- No production database changes or PR merge occurred. Organization remains in progress; Analytics remains blocked behind its production acceptance gates.

- 2026-11-17: Failed subtask-list refreshes now mark the client list incomplete while retaining visible rows; the next create forces a canonical reload. Regression coverage passed in CI #140 (43 tests, typecheck, production build). This is a UI consistency rule, not an authorization or RLS substitute.


## Organization V1 checkpoint — authenticated project-list boundary (2026-11-17)

- PR #11 remains the active Organization V1 work; PR #12 is a superseded draft. main is 2b42dd17796b75dca79434a81d4e1f0cbf0fa043 and the pre-change PR #11 head was dd18922b228f0bb44a6a01e404e33d3b4d0444bd.
- Added explicit server-side caller resolution and user_id filtering to listProjects. Optional status filtering and descending creation ordering are unchanged. Added tests for owner/status filtering and fail-closed unauthenticated reads.
- Latest prior CI #142 passed on the pre-change head; CI for this new code is pending. Lint remains unavailable because the repository has no lint script/configuration.
- Supabase metadata reports ACTIVE_HEALTHY, but migration listing, verbose table introspection and read-only SQL time out; advisors report hibernation. Live schema and applied migration ledger remain unknown. No production DDL/data change was made.
- Highest-priority remaining work remains database connectivity, live ledger/schema inspection, recovery readiness, safe migration review, advisors, and authenticated two-user CRUD/isolation. Analytics remains blocked behind Organization V1 acceptance.

## Verification — authenticated project-list boundary (2026-11-17)

- CI #143 passed on the code-bearing commit 1106efd1b3a1be9e3b5aac18bd8a6e714476cb9f: 45/45 tests, typecheck, production build, and install audit output with 0 vulnerabilities.
- CI #144 passed on documentation checkpoint 2c618299c5bd3db2bf03aad7f4afecc6ab2521a7: 45/45 tests, typecheck, production build, and install audit output with 0 vulnerabilities.
- No lint script/configuration exists. The live Supabase migration ledger/schema remain unverified because migration/table/SQL operations time out and advisors report hibernation despite ACTIVE_HEALTHY project metadata.
- Organization V1 remains incomplete. Do not advance to Analytics until live database inspection, recovery readiness, migration review/rollout, advisors, authenticated CRUD and two-user RLS isolation pass.


## Task-list ownership boundary — 2026-11-17

- Organization task reads now apply an explicit application-level owner filter in addition to PostgreSQL RLS.
- `listTasks` resolves the user with `auth.getUser()` on the same server-side Supabase client used for the query and fails closed when the session is missing or invalid.
- The extracted `listTasksForUser` query applies `user_id = authenticated user id`, preserves the optional project filter, and retains the existing due-date ascending / creation-time descending ordering.
- Added three mocked-client tests for owner + project filtering, optional project filtering, and rejecting a missing owner before database access. These tests verify query construction only; they do not prove PostgreSQL RLS or two-user isolation.
- Code-bearing commit `8f5eac4fd9d314a9fb3125de46789fe7858beac3` passed CI #150 (run ID `44002396846`): 48 tests passed, 0 failed; TypeScript check and production build passed; npm install audited 43 packages and reported 0 vulnerabilities.
- No lint script or linter configuration exists. No schema, migration, RLS policy, privilege, production data, or production infrastructure was changed.
- Fresh Supabase inspection: project metadata remains `ACTIVE_HEALTHY`, while migration listing, verbose public-table introspection, and a read-only information_schema query time out. Security, performance, and health advisor calls report the project as hibernated. The live migration ledger and schema remain unknown.
- PR #11 remains open and unmerged; PR #12 remains an open draft explicitly superseded by PR #11. The live PR page is authoritative for the current documentation head.
- Next safe action: restore supported database connectivity, inspect the actual migration ledger and Organization tables, confirm backup/recovery readiness, then run authenticated CRUD and cross-user isolation against the live database before migration rollout or merge.


## Engineering checkpoint — task relationship ownership preflight (2026-11-17)

- Organization V1 remains the active milestone.
- Task creation and relationship-changing updates now preflight project and parent ownership through the authenticated server-side Supabase client. Parent and task must belong to the same user and project; direct self-parenting is rejected before the write.
- The PostgreSQL validation trigger remains the authoritative protection against races and indirect cycles. The new checks are defense in depth, not a replacement for RLS/constraints.
- Six mocked-client tests were added. They do not verify live PostgreSQL RLS or cross-user isolation. CI for the new PR head is pending.
- The live Supabase migration ledger/schema remains unknown: project metadata is ACTIVE_HEALTHY, but migration listing, verbose table introspection and read-only SQL time out; advisors report hibernation.
- Next: verify current-head CI; restore database access; inspect actual migrations/schema; confirm backup/recovery; then complete authenticated CRUD and two-user isolation. Analytics remains blocked behind Organization V1.


## Verification checkpoint — task relationship ownership preflight (2026-11-17)

- Organization V1 remains the highest-priority incomplete milestone.
- Task creation and relationship-changing updates now validate project/parent ownership in application code before writing. The current task relationship is loaded with task ID + owner filters when an update changes either relationship field.
- Six new mocked-client tests cover valid links, foreign parent, cross-project parent, foreign project, direct self-parent, and missing owner.
- [CI #153](https://github.com/mohith-krishnaa/personal-os/actions/runs/44009478456) passed on code-bearing commit `9bdaa29e60afddc893a7e6fa5a1e43ee37469a7d`: **54 tests passed, 0 failed**; `npm run typecheck` and `npm run build` passed; `npm install` audited 43 packages and reported 0 vulnerabilities. No lint script or linter configuration exists, so lint remains unavailable.
- The database trigger remains authoritative for concurrent writes and indirect hierarchy cycles. These tests do not prove live RLS or two-user isolation.
- Live Supabase migration/schema inspection remains blocked by connection timeouts and advisor hibernation despite project metadata reporting ACTIVE_HEALTHY. Do not merge or begin Analytics until this is resolved and the remaining Organization acceptance criteria pass.


## Latest live database checkpoint — 2026-11-17

Read-only access has recovered. The live ledger contains eight applied core migrations and the repository now contains exact versioned copies of their SQL statements. The six Organization migrations are still unapplied. The live schema has the legacy project title field, no checklist tables, and no Organization task-link trigger. The Free Plan has no scheduled backup and no manual backup has been created. See [Organization V1 preflight and recovery runbook](docs/operations/organization-v1-preflight.md) and [read-only SQL preflight](supabase/operations/organization-v1-preflight.sql).

CI #163 through #168 passed on successive migration/documentation checkpoints; each run completed 56 tests, typecheck, production build, and 0 npm audit vulnerabilities. Latest verified documentation checkpoint: 0fe10995fbd3d5cb2e74c5a07d2257bc8ff623cc; the live PR page is authoritative for any later docs-only head. Organization remains the active milestone; Analytics is not started.


## Latest engineering checkpoint — concurrent task hierarchy protection (2026-11-17 12:47 IST)

- Updated the unapplied `20261015000300_prevent_task_hierarchy_cycles.sql` migration to acquire an owner-scoped transaction advisory lock before validating project/parent links and walking ancestors. Relationship-changing writes for one owner serialize until commit. Owner transfers acquire old/new owner lock keys in deterministic order; hash collisions can only add serialization, not bypass validation.
- Added a disposable PostgreSQL fixture covering valid same-owner/same-project links, direct self-parent rejection, foreign-parent rejection, cross-project rejection, foreign-project rejection, and a sequential indirect cycle.
- Added a two-session READ COMMITTED test. Writer A creates one edge and holds its transaction open; writer B attempts the inverse edge, is observed waiting on the advisory lock, then must fail with the cycle-constraint error after writer A commits.
- CI now provisions PostgreSQL 17 and runs this database integration test before the existing application tests, typecheck, and production build.
- [CI #173](https://github.com/mohith-krishnaa/personal-os/actions/runs/44038158510) passed on `482e1921ada6bc723a65c167b3cbea72b916bcf4`: PostgreSQL integration check passed (including concurrent cycle rejection); 56/56 application tests passed; `npm run typecheck` passed; `npm run build` passed; npm install audited 43 packages and reported 0 vulnerabilities.
- The CI service resolved PostgreSQL 17.12. This is a disposable integration fixture, not a restore test and not a test against the live Supabase database's exact 17.11.0.003 patch level. The fixture validates the trigger function and trigger event contract; it does not apply the full six-migration chain or prove live RLS/two-user PostgREST isolation.
- Live Supabase remains unchanged: ACTIVE_HEALTHY in ap-southeast-1 on 17.11.0.003; the ledger still has 8 applied core migrations; both checklist tables and the Organization trigger remain absent from production. No production DDL, migration, data/RLS change, restore, or PR merge was performed.
- Free Plan scheduled backups remain unavailable and no manual schema/data/role export or restore test exists. PR #11 remains open and unmerged. Analytics remains queued.
- Lint remains unavailable because the repository has no lint script or configuration.

Next safe action: create and restore-test the private logical backup on an owner-controlled machine, then run the full six-migration sequence and authenticated two-user direct-API isolation against a disposable database matching the live legacy schema. Only then consider production rollout or PR #11 merge.

## Latest engineering checkpoint — parent/child invariant hardening (2026-11-17)

- Extended the unapplied task-relationship trigger migration to reject moving a parent task to another project or owner when existing children would be left with a different project or owner. This complements the per-owner transaction advisory lock: parent changes and child relationship writes serialize under the same owner lock, and the trigger checks both the proposed parent link and existing direct children.
- Extended the PostgreSQL integration fixture to verify that a parent project move and an owner transfer are rejected while existing children would become inconsistent.
- [CI #176](https://github.com/mohith-krishnaa/personal-os/actions/runs/44038758029) passed on `d872a6e6f530a9ee87e8851a1cf5465197240379`: PostgreSQL 17 hierarchy integration (including the two-session cycle race and parent/child mutation checks), 56/56 application tests, typecheck, production build, and npm install audit with 0 vulnerabilities.
- Two intermediate CI attempts failed before the corrected run: #172 used shell connection defaults that were accidentally escaped as literals; #175 had malformed dollar-quoted SQL in the newly added DO blocks. Both were corrected in subsequent commits. #173 passed the original concurrency test, and #176 passed the expanded test suite on the latest code head.
- Live Supabase remains unchanged: ACTIVE_HEALTHY in ap-southeast-1 on PostgreSQL 17.11.0.003; 8 applied core migrations; 6 Organization migrations remain unapplied; live projects.name, checklist tables, and the Organization task trigger are still absent. No production DDL, migration, RLS/data write, restore, or PR merge occurred.
- The CI fixture is a disposable PostgreSQL 17.12 service and exercises the actual migration function with the trigger event definition. It does not apply the full six-migration sequence, restore a production backup, or prove live RLS/PostgREST two-user isolation.
- Free Plan scheduled backups remain unavailable and no manual schema/data/role export or restore test exists. PR #11 remains open and unmerged; PR #12 remains a superseded draft. Analytics remains queued. Lint is not configured.

Next safe action: create and restore-test the private logical backup on an owner-controlled machine, then run the full six-migration sequence and authenticated two-user direct-API isolation against a disposable database matching the live legacy schema. Only then consider production rollout or PR #11 merge.

Documentation verification: [CI #177](https://github.com/mohith-krishnaa/personal-os/actions/runs/44039076954) passed on latest PR head `74979439c63e9ba27009a786cf2d929c4a15e68e`; this docs-only checkpoint preserves the code-bearing verification from CI #176.

- CI now replays the complete 15-file local migration chain on a disposable legacy-schema fixture and verifies two-owner RLS behavior. This does not restore production or test live PostgREST. Next: create and restore-test a private schema/data/role backup, replay migrations against that restored snapshot, verify authenticated direct-API isolation against the restored database, then re-run advisors before any production rollout or merge.


## Latest engineering checkpoint — full migration replay and progress schema repair (2026-11-17)

- Re-inspected the live Supabase project: `ACTIVE_HEALTHY`, ap-southeast-1, PostgreSQL 17.11.0.003; the authoritative migration ledger still has 8 applied migrations. The live public schema has 9 application tables, all with RLS enabled and zero rows. The six Organization migrations and the new Progress compatibility migration remain unapplied.
- Added a PostgreSQL 17 CI replay harness for all 15 local SQL migrations. It bootstraps Supabase roles/auth helpers, seeds legacy project/checklist records before the relevant migrations, verifies owner-safe checklist reconciliation, validates project title/name dual-write, and exercises authenticated Owner A/Owner B read/write isolation.
- The hierarchy concurrency test remains separate and continues to verify the two-session READ COMMITTED cycle race and parent/child invariant checks.
- Live schema inspection found a second concrete mismatch: `public.goals` has no `unit` or `target`, but `getGoalsWithProgress` selects both. The original Progress V1 `CREATE TABLE IF NOT EXISTS` skipped those columns because the core migration had already created `goals`. Added forward-only migration `20261117000100_reconcile_progress_goal_metrics.sql`; it adds nullable metrics without inventing values for legacy goals. The dashboard now renders such goals safely and omits progress logging until metrics are present.
- Added regression coverage for null-target legacy goal summaries. CI #189 and #191 passed: 15-migration replay, authenticated two-owner RLS checks, hierarchy concurrency, 58/58 tests, typecheck, production build, and 0 npm audit vulnerabilities. Lint remains unconfigured.
- Security advisor returned no lints. Performance advisor still reports 4 unindexed foreign keys, 14 auth RLS initialization-plan warnings, 13 unused-index findings, and 4 overlapping permissive policies on `goals`.
- The Free Plan has no scheduled backups. No manual logical backup or restore test exists. No production DDL, migration, RLS change, data write, restore, or PR merge was performed.

Next safe action: create and restore-test a private logical backup, run the migration chain against the restored production snapshot, and test authenticated direct-API isolation there. Keep production read-only until those gates and explicit rollout approval are satisfied. Analytics remains queued behind Organization.


### Organization authorization regression — 2026-11-17
- Expanded the disposable migration replay to seed valid legacy checklist rows for both owners and verify canonical reconciliation for both; malformed cross-owner task associations are excluded.
- Added reciprocal two-owner visibility checks and direct SQL UPDATE/DELETE attempts in both directions across projects, tasks, and both checklist tables. Every cross-owner mutation must affect zero rows.
- [CI #207](https://github.com/mohith-krishnaa/personal-os/actions/runs/44055203271) passed the full migration replay, hierarchy concurrency, application tests, typecheck, and production build on `a9f73bfc26de818679c101974544793a839f2c74`.
- This strengthens Organization's CI acceptance evidence only; it is not a live PostgREST test or a production rollout.


### Organization direct-API relationship regression — 2026-11-17
- Added reciprocal Owner B attempts to spoof a project owner, attach a task to Owner A's project, insert canonical/legacy checklist items for Owner A's task, and reassign Owner B task/checklist relationships to Owner A records.
- The fixture fails if any prohibited operation succeeds. Existing two-owner UPDATE/DELETE denial checks remain reciprocal.
- [CI #209](https://github.com/mohith-krishnaa/personal-os/actions/runs/44064242592) passed the 15-migration PostgreSQL 17 replay, Organization RLS assertions, hierarchy concurrency, 58 application tests, typecheck, and production build.
- These are disposable-database checks only. They do not replace a restore-tested production backup or live PostgREST JWT isolation.


### Organization checklist SELECT ownership hardening — 2026-11-17
- Added a forward-only migration that scopes canonical and legacy checklist SELECT policies to both the checklist row owner and the referenced task owner.
- The PostgreSQL 17 replay seeds malformed canonical and legacy checklist rows owned by Owner A but attached to Owner B's task. Owner A must not be able to read either row; valid checklist rows remain visible.
- [CI #211](https://github.com/mohith-krishnaa/personal-os/actions/runs/44065216491) passed the 16-migration replay, hierarchy concurrency, 58 application tests, typecheck, and production build. [CI #212](https://github.com/mohith-krishnaa/personal-os/actions/runs/44065285214) passed the corrected test assertion message.
- This is disposable-database verification only. Production still lacks the checklist tables and policy migration; backup/restore and live JWT/API checks remain required.


### Organization anonymous-role denial — 2026-11-17
- The disposable migration fixture now grants table-level SELECT/INSERT/UPDATE/DELETE to `anon` as well as authenticated/service roles, so the test cannot pass merely because anonymous SQL privileges are missing.
- With an empty JWT subject, `anon` sees zero rows in projects, tasks, canonical checklists, and legacy checklists. Anonymous inserts are rejected on all four tables; updates and deletes affect zero authenticated rows.
- [CI #216](https://github.com/mohith-krishnaa/personal-os/actions/runs/44072614729) passed the full 16-migration PostgreSQL 17 replay, authenticated RLS checks, anonymous denial checks, hierarchy concurrency, application tests, typecheck, and production build.
- This remains disposable-database evidence only. Production schema, backup/restore, and live PostgREST authorization gates remain unchanged. No production change was made.


## Latest checkpoint — complete anonymous Organization CRUD denial matrix (2026-11-17)

- Code-bearing commit [fba0eee](https://github.com/mohith-krishnaa/personal-os/commit/fba0eeeda2b824afd8525d9f941050dca08e6a6a) extends the anonymous RLS fixture from representative write checks to the complete CRUD matrix.
- The test explicitly grants `anon` table-level SELECT, INSERT, UPDATE, and DELETE on `projects`, `tasks`, `checklist_items`, and `task_checklist_items`. Under an empty JWT subject it verifies zero visible rows, denied inserts, zero-row updates, and zero-row deletes on every table.
- [GitHub Actions run 44082207231](https://github.com/mohith-krishnaa/personal-os/actions/runs/44082207231) completed successfully: full 16-migration PostgreSQL 17 replay, task-hierarchy concurrency test, 58/58 application tests, TypeScript typecheck, production build, and npm audit with 0 vulnerabilities. No lint script/configuration exists.
- This is disposable PostgreSQL verification only. Live Supabase remains unchanged: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, 8 applied migrations, 8 local-only migrations, and 9 RLS-enabled public application tables with zero rows. The seven Organization migrations and one Progress compatibility migration remain unapplied.
- No production DDL, migration, RLS change, data write, restore, or PR merge was performed. Private backup/restore and live authenticated PostgREST verification remain the rollout blockers.


## Latest checkpoint — 2026-11-18 (foreign-key index verification)

Organization remains the active milestone. The full local migration replay now fails if the three indexes already defined by the pending Organization/compatibility migrations are missing, invalid, or not ready. CI #222 passed the 16-migration replay, hierarchy concurrency, 58 application tests, typecheck, production build, and npm audit (0 vulnerabilities). The read-only live preflight confirms those indexes and the separate notifications.task_id index are still absent in production. This is test/preflight coverage, not a production index change. Backup/restore and live authenticated PostgREST acceptance remain open; Analytics stays queued.

## Verified checkpoint — 2026-11-19 (project/task foreign-key contract)

- Branch: `feature/organization-v1`; code/test commit: `9805fe3d24279cf38dfa688f8132c1b942cea7cb`; PR #11 remains open and unmerged. The code commit changes only `supabase/tests/organization-migration-assertions.sql` and `supabase/operations/organization-v1-preflight.sql`.
- Migration replay assertions now require exactly one single-column FK for each relationship: `tasks.project_id -> projects.id ON DELETE SET NULL`, `tasks.parent_task_id -> tasks.id ON DELETE CASCADE`, and `projects.goal_id -> goals.id ON DELETE SET NULL`. Each must target the exact table/column and be validated. This catches an incorrect pre-existing FK that the Organization migration's current column-based existence check could otherwise mistake for the required constraint.
- Read-only preflight query 11 reports each expected relationship, the matching constraint definition, validation state, and the count of single-column FKs on that source column. It contains SELECT/catalog inspection only.
- No migration was added or modified. The repository tree contains 18 numbered SQL migration files; the migration-count fixture remains 18.
- Live read-only verification against Supabase project `gujzvkyytxsnervovvrt`: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, exactly 8 applied migration versions, and 9 public tables with RLS enabled. The three live FK definitions match the expected target columns, are validated, and have the expected SET NULL/CASCADE actions. No production write or DDL was executed.
- Current live advisors: security 0 lints; health 0 lints; performance still reports 4 unindexed FKs, 14 auth-RLS initialization-plan warnings, 13 unused-index findings, and 4 overlapping permissive goals-policy findings. Pending branch migrations are not applied to production.
- CI #298 passed on the preceding head `38a1a730ae6151753122a429c80fdf63aaf9f27c`. CI #299 passed on exact code/test commit `9805fe3d24279cf38dfa688f8132c1b942cea7cb`: npm install, PostgreSQL-client installation, full 18-migration PostgreSQL 17 replay, Organization RLS assertions, read-only preflight execution including query 11, task-hierarchy concurrency checks, 58/58 application tests, TypeScript typecheck, and production build all succeeded. No lint script/configuration is present.
- The current execution environment has no attached repository checkout, no `psql`, `pg_dump`, Docker, or Supabase CLI. Local working-tree status and local execution cannot be verified. The remote branch/PR are authoritative for this checkpoint.
- Production rollout remains blocked on an owner-controlled complete schema/data/roles backup successfully restored in isolation, followed by authenticated two-user PostgREST CRUD/isolation tests. The available Supabase connector exposes no backup/export workflow. No production migration, DDL, DML, RLS change, backup/restore, or PR merge was performed.

**Next action:** verify CI #299 on the exact code head. If it passes, retain this assertion/preflight improvement and continue the Organization recovery gate; if it fails, inspect the failing step and fix only the regression introduced by this commit. Do not start Analytics or alter production before the Organization acceptance gates pass.
