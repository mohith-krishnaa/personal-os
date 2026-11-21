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

# Latest handoff — subtask retry and activity-event idempotency (2026-11-21)

## Exact resume point

- Implementation/test HEAD: `0e9bd766acd6e0a25758de808d3f76ce8301c458`; [CI #526 passed on this exact HEAD](https://github.com/mohith-krishnaa/personal-os/actions/runs/44898421863).
- Starting HEAD: `73e5f7798461d5e4129949bd665721ef182be930`; CI #525 passed on that prior checkpoint.
- Branch: `feature/organization-v1`; main: `2b42dd17796b75dca79434a81d4e1f0cbf0fa043`.
- PR #11 is open, unmerged and mergeable; PR #12 is an open superseded draft.
- Repository migrations: 27. No migration was added.
- No local checkout is attached; remote branch/diff and CI were inspected, but local working-tree cleanliness is not independently certified.

## Completed

Audited `src/lib/subtasks.ts`, its server action, the subtask manager, the shared task-create idempotency helper, activity-event migrations, and the migration replay tests.

The server computes a payload fingerprint scoped to `kind: SUBTASK`, parent ID, requested project ID, normalized title, priority, due time and estimated minutes. It first looks up the request by authenticated owner and request UUID. Same-payload retries return the existing row before mutable parent/project preflight; different payload or parent reuse is rejected by the stored hash. New requests verify parent ownership and same-project relationships before the unique-key upsert.

The trusted task trigger emits `TASK_CREATED` for a non-recurring subtask and writes the event transactionally with the task INSERT. `ON CONFLICT DO NOTHING` means the losing duplicate does not run a second AFTER INSERT trigger.

Added two `subtasks.test.ts` tests for existing-row retry resolution and different-parent rejection. Extended `task-create-idempotency.sql` to create a parent and subtask, replay the same request key, and assert the original parent binding plus exactly one creation event. Converted `task-create-idempotency-concurrency.sh` to run two authenticated concurrent subtask requests under the same parent and assert one row/event. Updated the task-create idempotency architecture document.

## Verification

CI #526 on `0e9bd766acd6e0a25758de808d3f76ce8301c458`:
- PostgREST preflight: 33/33.
- PostgreSQL 17 migration replay: all 27 migrations passed, including sequential subtask duplicate/event checks, concurrent subtask retry and migration reapplication.
- Task hierarchy concurrency: passed.
- Application tests: 201/201.
- TypeScript typecheck: passed.
- Production build: passed.
- npm install audit: 0 vulnerabilities.
- No lint script is configured.

No production query or mutation was performed. The last recorded live migration baseline (8 applied vs 27 in the repository) was not refreshed in this run.

## Remaining acceptance gates

1. Owner-controlled complete schema/data/roles backup.
2. Offline manifest verification and successful restoration into a separate isolated Supabase project.
3. Extensions, roles/memberships, default ACLs, database settings, Vault, Auth trigger, `ensure_rls`, and reminder-function verification.
4. Checklist conflict disposition on the restored copy.
5. Apply the 19 branch-only migrations only to the isolated target.
6. Authenticated two-owner PostgREST acceptance.
7. Separate explicit owner decision on fail-closed `ensure_rls` behavior.

## Next action

Owner-controlled complete backup and isolated restoration. Do not repeat the subtask retry audit, apply branch-only migrations to production, deploy the fail-closed candidate, or merge PR #11.
---

# Latest handoff — tab-scoped task-create retry continuity (2026-11-21)

## Exact resume point

- Branch: `feature/organization-v1`.
- Implementation/test HEAD: `5e8152f41a3760c2f0a74430e3e1ba5d1a6b846b`; [CI #524 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44894326887).
- Starting HEAD: `d10ae221a66d5dcf61a639763bf8c8ba61c9193e`; [CI #522 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44889701706).
- PR #11 is open and unmerged; PR #12 is an open superseded draft.
- Repository migrations: 27. No migration was added.
- No local checkout is attached; remote branch/diff and CI were inspected, but local working-tree cleanliness is not independently certified.

## Completed

The quick-add, full task editor, and subtask editor now persist pending request identity across component remounts and page reloads in the same tab. The shared helper uses a SHA-256 payload fingerprint and stores only that digest, the UUID, and pending/completed state in sessionStorage. Separate React useId-based keys prevent independent forms from sharing IDs. Successful submissions mark their entry complete; different pending payloads remain isolated. Storage/Web Crypto failures fall back to in-memory behavior.

The first implementation commit `1caccb2e823311b6d53f6d3631bde9a0f3ddc26f` failed CI #523 at typecheck because the subtask manager remained a synchronous caller. Its 199 application tests, 33 preflight tests, migration replay and hierarchy checks passed; typecheck failed and build was skipped. The subtask manager was updated in `5e8152f41a3760c2f0a74430e3e1ba5d1a6b846b`; CI #524 then passed on that exact commit.

## Verification

CI #524:
- 33/33 PostgREST acceptance preflight tests.
- 27 repository migrations replayed with Organization/RLS assertions; reapplication checks passed.
- Task hierarchy concurrency checks passed.
- 199/199 application tests.
- TypeScript typecheck passed.
- Production build passed.
- npm install audit: 0 vulnerabilities.
- No lint script is configured.

The stored fingerprint is not encryption or authentication and may be guessable for low-entropy payloads. Pending state is tab-scoped, not cross-tab or cross-device. No raw task text, API keys, or credentials are stored by this helper.

## Production and rollout boundary

No production Supabase query or mutation occurred in this task. The last recorded live baseline remains 8 applied migrations versus 27 repository migrations (19 branch-only), not refreshed here. Do not apply migrations, alter RLS/roles, deploy the fail-closed `ensure_rls` candidate, or merge PR #11.

Still required:
1. Owner-controlled complete schema/data/roles backup.
2. Offline manifest verification and successful restoration into a separate isolated Supabase project.
3. Extensions, roles/memberships, default ACLs, database settings, Vault, Auth trigger, `ensure_rls`, and reminder-function verification.
4. Checklist conflict disposition on the restored copy.
5. Apply the 19 branch-only migrations only to the isolated target.
6. Authenticated two-owner PostgREST acceptance.
7. Separate explicit owner decision on fail-closed `ensure_rls` behavior.

## Next action

Owner-controlled complete backup and isolated restoration. If owner artifacts remain unavailable, audit the subtask creation/activity-event retry path as the next bounded Organization task. Do not start Analytics until Organization acceptance gates are verified.

---

# Latest handoff — marker-based PostgREST partial-failure cleanup (2026-11-21)

## Exact resume point

- Branch: feature/organization-v1.
- Implementation/test HEAD: 0d86584084a2f186da19ed0124b5ed08eddb1e5d; [CI #521 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44889487367).
- Starting HEAD: 8abfa26c132652281ff4548e29bfcecd26d46cd5; [CI #520 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44884605844).
- Main: 2b42dd17796b75dca79434a81d4e1f0cbf0fa043; branch was 600 commits ahead and 0 behind after the implementation commit.
- PR #11 is open, unmerged and mergeable; its head matched the implementation commit. PR #12 is an open superseded draft.
- Repository migrations: 27. No migration was added.
- No local checkout is attached; remote branch/diff and CI were inspected, but local working-tree cleanliness is not independently certified.

## Completed

The two-owner PostgREST harness now recovers rows whose INSERT may have committed even when the HTTP response did not return the row ID. It uses a validated lowercase-hex run marker, owner-scoped marker discovery for projects/tasks/canonical and legacy checklist rows, ID deduplication, explicit owner verification, and best-effort deletion that continues after an individual failure. The retained activity-event count includes recovered task IDs and is filtered by both owner and entity_type=TASK. It never deletes activity events; if task discovery/counting fails, the count is explicitly marked incomplete and the run marker is printed for manual isolated-target reconciliation.

Four unit tests were added. The cleanup runbook now documents the ambiguous-commit case. No application runtime behavior, migration, schema, RLS, or production data changed.

## Verification

CI #521 passed on the exact implementation/test HEAD:
- 33/33 PostgREST acceptance preflight tests.
- 27/27 PostgreSQL 17 migrations replayed with Organization/RLS assertions.
- Task hierarchy concurrency checks.
- 194/194 application tests.
- TypeScript typecheck.
- Production build.
- npm install audit: 0 vulnerabilities.
- No lint script is configured.

## Production and rollout boundary

No production Supabase query or mutation occurred in this task. The last recorded live baseline remains 8 applied migrations versus 27 in the repository (19 branch-only), not refreshed here. Do not apply migrations, alter RLS/roles, deploy the fail-closed ensure_rls candidate, or merge PR #11.

Still required:
1. Owner-controlled complete schema/data/roles backup.
2. Offline manifest verification and successful restoration into a separate isolated Supabase project.
3. Extensions, roles/memberships, default ACLs, database settings, Vault, Auth trigger, ensure_rls, and reminder function verification.
4. Checklist conflict disposition on the restored copy.
5. Apply the 19 branch-only migrations only to the isolated target.
6. Authenticated two-owner PostgREST acceptance.
7. Separate explicit owner decision on fail-closed ensure_rls behavior.

## Next action

Owner-controlled complete backup and isolated restoration. If owner artifacts remain unavailable, perform a different bounded Organization audit rather than repeating the same cleanup work or attempting unavailable backup operations. Do not start Analytics until Organization acceptance gates are verified.

---

# Latest handoff — strict legacy anon JWT structural preflight (2026-11-21)

## Exact resume point

- Branch: `feature/organization-v1`.
- Implementation/test HEAD: `40a61594fa0a84d2745813f3987511c0370a1be4`; [CI #519 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44884424453).
- Starting HEAD: `122f8bb5ad388920ab428b5eac858cf1784c0137`; [CI #515 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44880296409).
- Main: `2b42dd17796b75dca79434a81d4e1f0cbf0fa043); current implementation branch was 598 commits ahead and 0 behind main.
- PR #11 is open, unmerged, and mergeable; PR #12 is an open superseded draft.
- Repository migrations: 27. No migration was added.
- No local checkout is attached; remote branch/diff and CI were inspected, but local working-tree cleanliness is not independently certified.

## Completed

The PostgREST acceptance key preflight now validates legacy anon JWT structure: exactly three non-empty base64url segments, JSON-object header/payload, `alg=HS256`, optional `typ=JWT`, and payload `role=anon`. It rejects malformed header/payload JSON, invalid segments, unsupported algorithms/types, empty/malformed signatures, secret keys, opaque strings, and non-anon JWT roles. It does not verify the signature or expiry; Supabase validates the key server-side. Non-empty `sb_publishable_...` remains accepted; `sb_secret_...` remains denied.

Updated:
- `scripts/postgrest-organization-acceptance.ts`
- `scripts/postgrest-organization-acceptance.test.ts`
- `docs/operations/organization-v1-postgrest-acceptance.md`

Three structural regression cases were added, and the legacy JWT fixtures were corrected to use well-formed synthetic segments. No database or application runtime behavior changed.

## Verification

CI #516, #517, and #518 initially failed only in the isolated preflight test step due stale synthetic JWT fixtures/assertion expectations. Those failures were inspected and corrected.

CI #519 passed on the exact implementation/test HEAD:
- 29/29 PostgREST preflight tests.
- 27/27 PostgreSQL migration replay and Organization/RLS assertions.
- Task-hierarchy concurrency checks.
- 190/190 application tests.
- TypeScript typecheck.
- Production build.
- npm install audit: 0 vulnerabilities.
- No lint script is configured.

## Production and rollout boundary

No production Supabase query or mutation occurred in this task. The last recorded live baseline remains 8 applied migrations versus 27 in the repository (19 branch-only), not refreshed here. Do not apply migrations, alter RLS/roles, deploy the fail-closed `ensure_rls` candidate, or merge PR #11.

Still required:
1. Owner-controlled complete schema/data/roles backup.
2. Offline manifest verification and successful restoration into a separate isolated Supabase project.
3. Extensions, roles/memberships, default ACLs, database settings, Vault, Auth trigger, `ensure_rls`, and reminder function verification.
4. Checklist conflict disposition on the restored copy.
5. Apply the 19 branch-only migrations only to the isolated target.
6. Authenticated two-owner PostgREST acceptance.
7. Separate explicit owner decision on fail-closed `ensure_rls` behavior.

## Next action

Owner-controlled complete backup and isolated restoration. If owner artifacts remain unavailable, audit partial-failure cleanup and retained activity-event accounting in the acceptance harness as a distinct Organization task. Do not start Analytics until Organization acceptance gates are verified.

---

# Latest handoff — PostgREST acceptance key-class validation (2026-11-21)

## Exact resume point

- Branch: `feature/organization-v1`.
- Implementation/test HEAD: `c84dd038d3a4c4dd4253c0d7ca03931be823d92b`; [CI #513 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44880004720).
- Prior documentation HEAD: `1d76005fca0cd2a64940396cbda1295d259ac775`; [CI #514 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44880155910).
- Starting HEAD: `aeec41826b246abc8fc83d9ad1ab04af1d68cd88`; [CI #512 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44875025509).
- Main: `2b42dd17796b75dca79434a81d4e1f0cbf0fa043`; at the prior documentation checkpoint the branch was 593 commits ahead and 0 behind.
- PR #11 was open and unmerged with the prior documentation HEAD; it contained 117 changed files. PR #12 was an open superseded draft.
- Repository migrations: 27. The last verified production ledger: 8 versions, 19 branch-only; not refreshed in this task.

## Completed in this checkpoint

The PostgREST acceptance harness now accepts only a non-empty `sb_publishable_...` key or a legacy JWT with `role=anon`. It rejects secret-key prefixes, malformed JWTs, unknown opaque strings, empty publishable prefixes, missing role claims, and non-anon JWT roles. The check classifies format/role only; it does not cryptographically validate the key.

Added five tests to `scripts/postgrest-organization-acceptance.test.ts` and clarified `docs/operations/organization-v1-postgrest-acceptance.md`. No migrations or runtime product behavior changed.

## Exact CI evidence

CI #513 passed on `c84dd038d3a4c4dd4253c0d7ca03931be823d92b`:
- PostgREST acceptance preflight 26/26.
- PostgreSQL 17 replay 27/27.
- Organization/RLS and task hierarchy checks passed.
- Application tests 187/187.
- Typecheck and production build passed.
- npm audit reported 0 vulnerabilities.
- No lint script is configured.

CI #514 passed on the subsequent documentation checkpoint `1d76005fca0cd2a64940396cbda1295d259ac775`. Existing non-failing Node `punycode` deprecation and local PostgreSQL trust-authentication warnings remain. Expected SQL errors from negative tests were handled by assertions.

## Production and rollout boundary

No production Supabase query or mutation occurred in this task. Production remains read-only. Do not apply migrations, change RLS/roles, deploy the fail-closed `ensure_rls` candidate, or merge PR #11.

Still required:
1. Owner-controlled complete schema/data/roles backup.
2. Offline manifest verification and successful restore into a separate isolated Supabase project.
3. Extensions, roles/memberships, default ACLs, database settings, Vault, Auth trigger, `ensure_rls`, and reminder function verification.
4. Checklist reconciliation conflict disposition on the restored copy.
5. Apply the 19 branch-only migrations only to that isolated target.
6. Authenticated two-owner PostgREST acceptance.
7. Separate explicit owner decision on fail-closed `ensure_rls` behavior.

The isolated acceptance harness has not been run. Unit tests and disposable PostgreSQL replay are not live PostgREST acceptance evidence. There is no attached local checkout, so local working-tree cleanliness is not independently certified.

## Next action

Owner-controlled complete backup and isolated restoration. If the owner-controlled artifacts remain unavailable, perform another distinct bounded Organization audit; do not retry unavailable backup tooling or move to Analytics.

---

# Latest handoff — fail-closed ensure_rls candidate prepared (2026-11-21)

## Exact resume point

- Branch: `feature/organization-v1`.
- Implementation/test HEAD: `da37b785571cb97154cdc06f4448aa595a8cfce4`; [CI #510 passed on this exact HEAD](https://github.com/mohith-krishnaa/personal-os/actions/runs/44874851618).
- Starting HEAD: `13efdd68e9df8688aa533cae9117dffd79ffc5dd`; CI #506 passed there.
- PR #11: open, unmerged; PR #12: open superseded draft.
- Main: `2b42dd17796b75dca79434a81d4e1f0cbf0fa043`; branch ahead 587, behind 0.
- Repository migrations: 27. Fresh production ledger: 8 versions, 19 branch-only.
- Personal-OS Builder is enabled. The current recorded run is `dd63b7dd-7f48-832b-a29b-1d8b56de35d6` (in_progress, started 06:12:35.570864Z); the latest stored result `86d86403-c940-8320-bd42-59299fa73617` was created 05:50:14.386440Z and belongs to the preceding run.

## Production source contract — read-only

Project `gujzvkyytxsnervovvrt` is ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, `ap-southeast-1`. Live migration ledger contains exactly eight versions ending `20260905162251`. The current session is directly postgres while `rolsuper=false`. `public.rls_auto_enable()` is postgres-owned SECURITY DEFINER with `search_path=pg_catalog`, original source fingerprint `99be20677b456ea8d3be47bdd44fb369`, and direct EXECUTE grantees exactly postgres/service_role. `ensure_rls` is enabled and postgres-owned with the expected DDL tags.

## Work completed in this checkpoint

1. Added `supabase/operations/apply-ensure-rls-fail-closed.sql`. It is a candidate script, not a migration. It requires same-session isolated-target and explicit owner-approval attestations, direct postgres login, the exact reviewed source/candidate function fingerprint, owner/security/search-path, exact ACL, and exact enabled event-trigger contract.
2. The only behavior change is that an RLS-enable error is logged and re-raised. This makes the originating CREATE TABLE/CREATE TABLE AS/SELECT INTO fail rather than leave a public table without RLS.
3. Added `supabase/tests/ensure-rls-fail-closed-candidate.sql`. It verifies successful RLS enablement, error propagation and DDL rollback with a test-only fault injector, savepoint restoration, and candidate fingerprint/ACL/event-trigger assertions.
4. Extended `supabase/tests/organization-migrations.sh` with missing-target, missing-approval, wrong-role, double-apply and post-rollback baseline checks.
5. Updated `docs/operations/restore-customization-inventory.md` with the owner decision and isolated-only procedure.

Candidate `pg_proc.prosrc` fingerprint: `b95d4b52e100f89abf4b5afa270a4776`. Original source fingerprint: `99be20677b456ea8d3be47bdd44fb369`. The candidate script is idempotent for exactly those two fingerprints and refuses unknown function bodies or ACL/event-trigger drift. Run the normal `restore-ensure-rls-event-trigger.sql` first; if the candidate is approved and applied, do not rerun the original restore script afterward because that script intentionally requires the original source fingerprint.

The `app.personal_os_fail_closed_rls_approval='owner-approved'` GUC is an operator attestation, not proof of approval. **No owner approval was granted in this run.** The candidate was tested only in the disposable PostgreSQL CI transaction and was not applied to production or a live isolated Supabase project.

## CI evidence

- CI #509 passed on intermediate HEAD `e03d64483fa00841a5665c57380f89953adddc5c`.
- CI #510 passed on final implementation/test HEAD `da37b785571cb97154cdc06f4448aa595a8cfce4`: PostgREST preflight, 27-migration replay, Organization/RLS and hierarchy checks, fail-closed candidate gates/idempotence/exception propagation/rollback isolation, npm tests, typecheck, and production build.
- No lint script is configured; the workflow has no separate npm audit step.

## Next action

Obtain an explicit owner decision on the fail-closed behavior. If approved, apply the candidate only after complete owner-controlled backup and successful isolated restoration, using the two same-session GUC attestations and direct postgres login. Verify the actual Supautils event-trigger capability on that isolated Supabase target. Keep the production project read-only. Independently complete checklist conflict disposition and authenticated two-owner PostgREST acceptance. Do not apply the 19 branch-only migrations to production or merge PR #11. Keep Analytics queued.

---

# Latest handoff — ensure_rls restore role correction (2026-11-21)

## Exact resume point

- Branch: `feature/organization-v1`.
- Implementation/test HEAD: `2443e93dcdaf404c026841558ec4236a7504d703`; [CI #505 passed on this exact HEAD](https://github.com/mohith-krishnaa/personal-os/actions/runs/44872382080).
- Starting HEAD: `15fa5728227256d64dc89aa24a429caa5a4cca7f`; CI #501 passed there.
- PR #11: open, unmerged; PR #12: open superseded draft.
- Repository migrations: 27. Fresh production ledger: 8 versions, 19 branch-only.
- The latest automation result was older than the current recorded run; the automation is enabled. An `in_progress` record is not proof of worker liveness.

## Verified production role contract

A fresh read-only query on project `gujzvkyytxsnervovvrt` returned `session_user=current_user=postgres`, while `pg_roles.rolsuper=false` for postgres. The live `ensure_rls` event trigger is enabled, postgres-owned, and references postgres-owned SECURITY DEFINER `public.rls_auto_enable()` with `search_path=pg_catalog`. Direct EXECUTE ACL is exactly postgres/service_role; PUBLIC, anon, and authenticated are denied.

Supabase's Supautils permits the postgres role to create/manage event triggers without SUPERUSER ([official guide](https://supabase.com/docs/guides/database/postgres/event-triggers)). Do not use `rolsuper` as the gate or switch to `supabase_admin`.

## Completed in this checkpoint

1. Corrected `supabase/operations/restore-ensure-rls-event-trigger.sql` to require direct postgres session identity and to create the event trigger as postgres without an ownership-transfer statement.
2. Corrected the behavior-test gate to require the same session identity.
3. Added a negative test proving a different SUPERUSER role is rejected; the positive path runs as postgres.
4. Added read-only preflight query 22 for session/current identity and the postgres superuser flag. Query 21 already asserts the direct PUBLIC EXECUTE ACL.
5. Updated the offline static tests and the restore-customization runbook.
6. Preserved the existing source function body and its exception behavior; no production object was changed.

## CI history and exact final evidence

- #502 and #503: static test false positives because the broad `rolsuper` matcher also matched the comment `rolsuper=false`; 181/182 tests passed and typecheck/build were skipped.
- #504 passed, but its whitespace matcher was found to be over-escaped. It is not the authoritative proof for that matcher.
- #505 passed on `2443e93`: 21/21 PostgREST preflight, 27/27 migration replay, Organization/RLS and hierarchy assertions, ensure_rls restore/ACL/behavior tests, 182/182 application tests, typecheck, production build, and npm audit with 0 vulnerabilities. No lint script is configured.

## Known limitation

CI uses a local PostgreSQL postgres SUPERUSER. It verifies the direct-role identity gate and SQL behavior but does not emulate Supautils' hosted privilege hook. The restored Supabase target must still prove event-trigger creation under its actual non-superuser postgres role. The source `rls_auto_enable()` exception handler still logs and swallows inner RLS-enable failures; owner review is required before changing it.

## Next task

Owner-controlled complete backup of schema, data, and roles, followed by restoration into a separate isolated Supabase project. Re-run the 45-field backup manifest verifier, verify all managed-data zero gates, extensions, roles/default ACLs/settings, Auth trigger, `ensure_rls`, and `claim_due_reminders`; review checklist conflicts; then run authenticated two-owner PostgREST acceptance. Do not apply production migrations or merge PR #11. Keep Analytics queued.

---

# Latest handoff — schema-drift classification (2026-11-21)

## Exact resume point

- Branch: `feature/organization-v1`.
- Audit base HEAD: `a4703c27e619b7de4210b8f8f4066e9f6f98dba7`; CI #488 passed on this exact starting commit.
- PR #11: open, unmerged, mergeable; its head matched the audit base before this checkpoint. PR #12: open superseded draft.
- Main: `2b42dd17796b75dca79434a81d4e1f0cbf0fa043`; branch ahead 563, behind 0.
- Live migration ledger: 8 versions; repository: 27; 19 branch-only.

## Findings that supersede the previous handoff

1. `claim_due_reminders(integer)` is expected baseline state, not out-of-ledger drift. The live definition/config/owner/ACL match applied migration `20260830123420_atomize_reminder_delivery_claim.sql`. The branch-only `20261120000300_atomic_reminder_delivery.sql` is the intended atomic replacement and has not been applied to production.
2. `ensure_rls` / `public.rls_auto_enable()` is a project-installed optional customization. Supabase's official event-trigger guide describes it as an example to create, not a built-in automatically installed object. No repository migration creates it; the applied migration `20260905162251_restrict_rls_auto_enable_execute.sql` only revokes EXECUTE from anon/authenticated.
3. The live `rls_auto_enable()` function logs but swallows exceptions from enabling RLS. Supabase's current example re-raises. The live ACL excludes PUBLIC, anon, and authenticated and grants service_role, but the migration itself does not revoke PUBLIC. Treat this as an owner-reviewed restore/security contract, not an automatic fix.
4. The CI bootstrap's no-op stub does not reproduce the production event trigger. It exists only to replay the privilege migration.

## Work performed

- Fresh read-only project/migration inspection and catalog query for `claim_due_reminders`, `rls_auto_enable`, `ensure_rls`, Auth trigger, ACLs, and function definitions.
- Scanned all 112 PR file patches; among the 27 migration files, only `20260905162251_restrict_rls_auto_enable_execute.sql` references `rls_auto_enable`, and it contains only the privilege revoke.
- Added two static regression tests to the existing npm test suite.
- Corrected the CI fixture comment and current restore/preflight/migration documentation.
- No migration, runtime behavior, or production object was changed.

## CI verification

- CI #489 on `ed75d744ab885b5d6c6b9b900fa67afa62a01847` failed only at typecheck: the readonly tuple type of `REQUIRED_SOURCE_MIGRATIONS` rejected `20261120000300` in an `includes` assertion. Its 21/21 PostgREST preflight, 27-migration replay, Organization/RLS assertions, hierarchy concurrency, and 181/181 application tests passed; build was skipped after typecheck failed.
- The type-only issue was corrected in `ec92d85946001f261c87bc1059d9540edacf2ab3` by widening the local migration-version view to `readonly string[]`.
- CI #490 passed on that exact implementation/test HEAD: 21/21 preflight, 27/27 migration replay, Organization/RLS and hierarchy checks, 181/181 tests, typecheck, production build, and npm audit with 0 vulnerabilities. No lint script is configured.

## Production safety

No backup or isolated restore exists. Production was queried read-only only. No DDL/DML, migration, RLS, role, project setting, backup, restore, or merge was performed. The connected Supabase tools expose no backup/export action. Edge Function listing returned empty; Dashboard-only Auth/API/SMTP/JWT/Realtime/webhook settings remain owner inventory.

## Next task

If the owner-controlled backup remains unavailable, add a read-only preflight assertion that PUBLIC cannot execute `public.rls_auto_enable()`, then build an isolated-only restore/behavior test for `ensure_rls` that explicitly tests the exception path. Do not add or apply a production migration before complete backup and successful isolated restoration. Analytics remains queued.

# Latest handoff — CI-verified managed-schema restore audit (2026-11-21)

## Exact resume point

- Implementation/test HEAD: `293068da23e1f47b3c6b26b10fd21852bd1449e3`
- CI #487: <https://github.com/mohith-krishnaa/personal-os/actions/runs/44861473748> — passed on that exact HEAD.
- Branch: `feature/organization-v1`; PR #11 open/unmerged; PR #12 open superseded draft.
- Repository migrations 27; production project migration ledger 8; 19 branch-only.
- No migration was added.

## Completed

1. Read-only Supabase-managed customization inventory at `supabase/operations/restore-customization-inventory.sql`.
2. Isolated-only Auth trigger restore at `supabase/operations/restore-auth-user-trigger.sql`, guarded by same-session `app.personal_os_restore_target='isolated'`; CI tests refusal without the marker and two idempotent applications with it.
3. Offline manifest verifier requires 45 row-count keys and rejects any non-zero count among 36 managed/ephemeral data tables.
4. Runbook and project state/roadmap/handoff updated.

## CI #487 exact results

- PostgREST preflight 21/21.
- All 27 migration replay checks and Organization/RLS assertions passed.
- Task hierarchy concurrency passed.
- Isolated Auth trigger refusal/restore/idempotence assertions passed.
- Application tests 179/179.
- TypeScript typecheck and production build passed.
- npm install audit reported 0 vulnerabilities.
- No lint script is configured.

CI #479 had one assertion-wording failure; the verifier message was corrected and subsequent CI #480 and #487 passed.

## Production findings and blockers

- Source project ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, `ap-southeast-1`, Free plan.
- Nine public application tables and 36 managed/ephemeral data tables were all empty at the 2026-11-21 03:23 UTC snapshot. Re-run inventory immediately before export.
- Auth/Storage/Realtime provider ledgers: 84/81/97 rows; project migration ledger 8. Do not restore provider-managed ledgers.
- Standard Supabase CLI dump excludes managed schemas such as `auth`, `storage`, and extension-created schemas. The manual CLI path is allowed only while all 36 managed counts remain zero. If any become non-zero, stop and use a complete supported backup/restore path.
- Native Restore-to-New-Project requires a paid plan and physical backups; current organization is Free.
- Restore the custom Auth trigger separately on the isolated target. Verify `ensure_rls`/ `rls_auto_enable` after public schema restore.
- Review out-of-ledger `claim_due_reminders` drift: live `search_path=public`, branch migration expects `pg_catalog, public`.
- Secrets and Dashboard-only Auth/API/Storage/Realtime settings were not accessible; owner inventory is required.

## Next action

Owner-controlled backup and isolated restoration. If unavailable, do not churn on the same blocked step: use the private scratch diff workspace with only the eight live migrations to inspect `claim_due_reminders` and `ensure_rls` drift, and complete the Dashboard-only settings inventory. Keep production read-only and Analytics queued.

# Latest resume note — CI coverage for isolated-target guard (2026-11-21)

- Branch: `feature/organization-v1`
- Latest pre-follow-up HEAD: `fe918c9c165adda10d66cf73b5fccd66156d4949`
- CI #482 passed on prior head `ce77eef14abed0fe6fc37fc42f2401ff47e277b4`: 21/21 PostgREST preflight, 27 migration replay and Organization/RLS checks, 178/178 app tests, typecheck, build, 0 npm vulnerabilities.
- CI #482 does not cover the later session-GUC safety gate added to `restore-auth-user-trigger.sql`. A static regression test is being added for the guard, while the migration runner also exercises the missing-attestation refusal and two successful idempotent runs.
- Keep production read-only. No backup/restore, migration, DDL/DML, RLS change, or PR merge occurred.
- Next: verify the CI run on the actual final head; then resume owner-controlled backup/isolated restore. If blocked, inspect the known out-of-ledger `claim_due_reminders` and `ensure_rls` drift with the eight-migration scratch diff, without touching production.

# Latest handoff — managed-schema restore and isolated-target guard (2026-11-21)

## Exact resume point

- Branch: `feature/organization-v1`
- Latest verified branch HEAD before this handoff follow-up: `6364551e02fdb6f85963a8ba8d043688ac3e546a` (the immediately preceding isolated-target guard commit is `876b6ec92cd8e7c4ae89950d391aba0590b3fbf1`).
- PR #11: open, unmerged; PR #12: open superseded draft.
- Repository migrations: 27. Production project migration ledger: 8; 19 branch-only migrations.
- No migration was added during this task.

## Changes completed

1. Added read-only inventory SQL at `supabase/operations/restore-customization-inventory.sql`.
2. Added isolated-only Auth trigger restore at `supabase/operations/restore-auth-user-trigger.sql`, guarded by the session GUC `app.personal_os_restore_target='isolated'`. The migration runner verifies refusal without the GUC, then applies the script twice with the GUC and runs the assertion.
3. Expanded the offline manifest verifier to 45 row counts; all 36 managed/ephemeral data counts must be zero for the standard CLI logical-backup path.
4. Added the managed-schema restore runbook and updated Organization preflight, manifest verifier, project state, handoff, and roadmap.

## Critical source facts

- All nine public application tables and all 36 managed/ephemeral data tables were zero in the 2026-11-21 03:23 UTC snapshot. Re-run inventory immediately before export.
- Provider migration ledgers: Auth 84, Storage 81, Realtime 97; project migration ledger 8. Do not restore provider-owned migration ledgers.
- Four non-plpgsql extensions: `pg_stat_statements 1.11`, `pgcrypto 1.3`, `supabase_vault 0.3.1`, `uuid-ossp 1.1`.
- The default CLI dump excludes managed schemas such as `auth`, `storage`, and extension-created schemas. If any of the 36 managed/ephemeral data counts is non-zero, stop; the five CLI dump artifacts are not complete. The organization is Free; native Restore-to-New-Project requires a paid plan and physical backups.
- Custom Auth trigger: `auth.users.on_auth_user_created` calls `public.handle_new_user()`. The public function is in the public dump; the Auth trigger is not. Recreate it only on the isolated target after verifying the target project reference, setting `app.personal_os_restore_target='isolated'` in the same session, and applying the script.
- Verify public event trigger `ensure_rls` and `public.rls_auto_enable()` after schema restore.
- Out-of-ledger `public.claim_due_reminders(integer)` exists in production with `search_path=public`; the branch migration expects `pg_catalog, public`. Capture and review this drift; let the branch migration normalize only on the isolated target.
- No custom login roles, no managed-schema RLS policies, no custom schemas, no foreign servers, no `pg_cron`/`pg_net`/`wrappers`; publication `supabase_realtime` has no table members. No Edge Functions were listed; secrets and Dashboard Auth settings were not accessible.
- Source default ACLs are broad in several schemas. Compare target `pg_default_acl`, role memberships, role settings, and database settings after restore; do not leave target defaults revoked if source defaults are restored.

## CI evidence

CI #482: <https://github.com/mohith-krishnaa/personal-os/actions/runs/44861228036> passed on `ce77eef14abed0fe6fc37fc42f2401ff47e277b4`: PostgREST preflight 21/21, 27 migration replay, Organization/RLS assertions, 178/178 application tests, typecheck, production build, and 0 npm vulnerabilities. The explicit isolated-target GUC guard was added at `876b6ec92cd8e7c4ae89950d391aba0590b3fbf1` after CI #482. Check CI on the latest branch head before claiming the guard verified.

## Next action

Owner-controlled complete backup and isolated restore. If the owner cannot provide it, do not retry the same unavailable step. Use the private scratch diff workspace with only the eight live migrations to inspect `claim_due_reminders` and `ensure_rls` drift, and complete Dashboard-only Auth/Secrets/Realtime/Storage settings inventory. Keep production read-only, keep PR #11 unmerged, and keep Analytics queued.

# Latest handoff — managed-schema restore audit (2026-11-21)

## Exact resume point

- Branch: `feature/organization-v1`
- Checkpoint base HEAD before this handoff update: `4d13c537a075c8659be4bf0b555b392711b3cf0a`
- PR #11: open, unmerged. PR #12 remains a superseded open draft.
- Repository migrations: 27. Production project migration ledger: 8. Do not infer that the production schema equals the eight migrations; out-of-ledger objects were found.
- No migration was added in this task.

## What changed

1. Added the read-only source inventory query at `supabase/operations/restore-customization-inventory.sql`.
2. Added isolated-only Auth trigger restoration at `supabase/operations/restore-auth-user-trigger.sql` plus a regression assertion. The migration runner applies it twice on disposable PostgreSQL.
3. The offline manifest verifier now requires 45 row counts and rejects any non-zero count among 36 managed/ephemeral data tables.
4. Added `docs/operations/restore-customization-inventory.md`; updated the manifest and Organization preflight runbooks.
5. The new inventory query ran read-only on production. It did not read secret values or alter the project.

## Critical restore constraints

- The standard Supabase CLI logical dump excludes managed schemas such as `auth`, `storage`, and extension-created schemas. Storage object bytes and project-level settings are separate. The manual CLI path is permitted only while all 36 managed/ephemeral data counts remain zero. Re-run the inventory immediately before export. If any count is non-zero, stop and select a complete supported backup method; do not claim the five dump files are complete.
- Current organization plan is Free; Supabase Restore-to-New-Project requires a paid plan and physical backups. Do not upgrade/create paid resources without owner decision.
- No `supabase/config.toml` exists in the repository. For a source schema diff, create a private temporary CLI workspace and copy only the exact eight live migration files. Never diff all 27 branch migrations against the eight-version source baseline.
- Restore roles and prepare target defaults first; after schema restore, compare source/target `pg_default_acl`, role memberships, role settings, and database settings. Source default ACLs are broad in several schemas; do not leave target defaults revoked if the source dump restores explicit ACLs.
- Recreate `auth.users.on_auth_user_created` on the isolated target after `public.handle_new_user()` and `auth.users` exist, using the dedicated restore script. Verify `ensure_rls` and `public.rls_auto_enable()` after public schema restore.
- Source has out-of-ledger `public.claim_due_reminders(integer)`: live `search_path=public`, branch migration expects `pg_catalog, public`. Capture and review it; let the branch migration normalize only on the isolated target.
- Auth settings, API keys, Edge Function secrets, Storage API settings/objects, Realtime project settings, database webhooks, and read replicas require owner-controlled inventory. No Edge Functions were listed; secret names/values were not accessible. Never place secrets in manifests, CI, or Git.

## CI checkpoint

CI #478: <https://github.com/mohith-krishnaa/personal-os/actions/runs/44860969477> passed on `61b33d08f97b04f6776b7cf9f262cdeafddecdf8`: 27 migration replay, Organization/RLS assertions, Auth trigger restore script idempotence, 177/177 tests, typecheck, build, 0 npm vulnerabilities. The later inventory SQL contract test and error-message clarification were added after that SHA. Verify CI on the actual latest branch head before treating the run as fully verified.

## Next action

Owner-controlled complete backup and isolated restore. If the owner cannot provide the backup/restore, do not retry the unavailable operation. Use the private eight-migration scratch diff workflow to inspect the known `claim_due_reminders` and `ensure_rls` out-of-ledger objects, and complete the Dashboard-only Auth/Secrets/Realtime/Storage settings inventory. Keep production read-only, keep PR #11 unmerged, and keep Analytics queued.

# Latest handoff addendum — verifier fixture scan (2026-11-21)

Code/test fixture commit: \`f4e18514714333fc6cfd5a0916159d905082abef\`. The only delta since the fully verified implementation is a test-only rewrite that constructs the synthetic PostgreSQL connection string from fragments, eliminating the only credential-pattern scan match. Runtime behavior and verifier logic are unchanged. The previous full CI #471 passed on \`8400787cf015964d7e8e3e3cbc22381b12770060\`; the current final checkpoint must be verified by CI on its own HEAD.

The credential-pattern scan across all nine files changed in this run now has zero matches. No migration, production operation, backup, restore, or PR merge occurred. Continue with the owner-controlled complete backup and isolated restoration gate; do not start Analytics.

---

# Latest handoff — offline backup manifest verifier (2026-11-21)

Starting HEAD: \`95c8c9184551a979d3bdd2b3bd9fb03833ceed67\`.  
Corrected code/test HEAD: \`1dbd3ab6e73709ead9ae5d46c1d107d42d3295a4\` — [CI #468 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44855630997).  
Inventory hardening HEAD: \`8c925641e7a3b86d3baaa0f439c4bb28c39a88e3\` — [CI #470 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44855941859).  
Branch: \`feature/organization-v1\`. PR #11 open/unmerged; PR #12 open/superseded draft.

## Recovery and verified state

The latest stored automation result belonged to the prior backup/restore runbook audit, not the current run. Production is ACTIVE_HEALTHY, PostgreSQL 17.11.0.003; a fresh read-only migration listing returned the exact eight source versions documented in preflight. Repository inventory is 27 numbered migrations (19 branch-only).

## New offline verifier

~~~bash
npm run backup:manifest:verify -- --manifest "$BACKUP_DIR/manifest.json" --artifacts-dir "$BACKUP_DIR"
~~~

Run from a clean Git checkout whose HEAD equals \`source.repositoryCommit\`. Manifest and SQL artifacts must be outside the repository. The verifier checks eight source migration versions, all repository migration filenames, required extension names, 13 row-count keys, five export command exit statuses/target attestations, and five artifact sizes/SHA-256 digests. It rejects credentials, symlinks (including migration-file symlinks), unsafe paths, and repository-local backup paths.

Added a root \`.gitignore\` because none existed. It excludes generated dependencies/build output, local environment files, Supabase temporary state, logs, and the npm-generated lockfile. Backup SQL files remain outside Git by policy.

The verifier performs no network/database calls and reads no environment variables. It does not create a backup, parse SQL contents, prove the CLI Target line, or verify restoration. A successful result is not backup completeness or restore evidence. See \`docs/operations/backup-manifest-verifier.md\`.

## Verification

CI #467 failed three fixture assertions (172/175 passed); fixture lengths and credential-error expectation were corrected.

CI #468 passed on \`1dbd3ab\`: 21/21 PostgREST preflight, 27/27 migration replay, task hierarchy concurrency, 175/175 tests, typecheck and build.

CI #470 passed on \`8c92564\`: 21/21 PostgREST preflight, 27/27 migration replay, task hierarchy concurrency, 176/176 tests, typecheck and build. npm install reported 0 vulnerabilities. CI #469 passed on the intermediate documentation checkpoint. No lint script is configured.

## Next action

Owner must create and restore the complete backup into a separate isolated Supabase project. Run the verifier on private artifacts, then verify extensions, roles/default ACLs, Auth trigger, Vault decision, exact eight-version ledger, and checklist conflicts. Apply the 19 branch-only migrations only to the isolated target and run the two-owner PostgREST harness there. Do not modify production or merge PR #11.

No local checkout is attached, so local working-tree cleanliness is not certified. No production operation or backup/restore was performed.

---

# Latest handoff — offline backup manifest verifier (2026-11-21)

**Starting HEAD:** \`95c8c9184551a979d3bdd2b3bd9fb03833ceed67\`.  
**Corrected implementation/test HEAD:** \`1dbd3ab6e73709ead9ae5d46c1d107d42d3295a4\` — [CI #468 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44855630997).  
**Branch:** \`feature/organization-v1\`. **PR #11:** open/unmerged. **PR #12:** open/superseded draft.

## Recovery and verified state

The latest stored automation result belonged to the prior backup/restore runbook audit, not the current run. The actual branch started at \`95c8c9184551a979d3bdd2b3bd9fb03833ceed67\`. The current production project is ACTIVE_HEALTHY, PostgreSQL 17.11.0.003; a fresh read-only migration listing returned the exact eight source versions documented in preflight. Repository inventory is 27 numbered migrations (19 branch-only).

## New offline verifier

Use:

~~~bash
npm run backup:manifest:verify -- --manifest "$BACKUP_DIR/manifest.json" --artifacts-dir "$BACKUP_DIR"
~~~

Run from a clean Git checkout whose HEAD equals \`source.repositoryCommit\`. The manifest and SQL artifacts must be outside the repository. The verifier checks the exact eight source migration versions, all repository migration filenames, required extension names, 13 row-count keys, five command exit statuses/target attestations, and five artifact sizes/SHA-256 digests. It rejects credentials, symlinks, unsafe paths, and repository-local backup paths.

It performs no network/database calls and does not read environment variables. It does not create a backup, parse SQL contents, prove the CLI Target line, or verify restoration. A successful result is not backup completeness or restore evidence. See \`docs/operations/backup-manifest-verifier.md\`.

## Verification

CI #467 failed three new fixture assertions (172/175 passed). The size and hash fixtures had their lengths reversed, and the credential test expected the wrong first validation error. These were corrected in \`1dbd3ab\`.

CI #468 passed on corrected HEAD \`1dbd3ab6e73709ead9ae5d46c1d107d42d3295a4\`:
- PostgREST preflight 21/21;
- PostgreSQL 17 migration replay 27/27;
- task hierarchy concurrency passed;
- application tests 175/175;
- typecheck and production build passed;
- npm install reported 0 vulnerabilities.
No lint script is configured.

## Next action

Owner must create and restore the complete backup into a separate isolated Supabase project. Run the manifest verifier on the private artifacts, then verify extensions, roles/default ACLs, Auth trigger, Vault decision, exact eight-version ledger, and checklist conflicts. Apply the 19 branch-only migrations only to the isolated target and run the two-owner PostgREST harness there. Do not modify production or merge PR #11.

No local checkout is attached, so local working-tree cleanliness is not certified. No production operation or backup/restore was performed in this run.

---

# Latest handoff — owner backup gate and current Supabase CLI restore procedure (2026-11-21)

**Branch:** `feature/organization-v1`. **Runbook commit:** `1b9c2ca12145226f865d22414f95de6170729e54` — [CI #464 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44849631968).  
**Checkpoint docs commit:** `cd4ccb1c3accffec12e719b9b2f497079026ea55` — [CI #465 passed](https://github.com/mohith-krishnaa/personal-os/actions/runs/44849845193).

## Recovery

- Automation enabled. `last_run.id=2d21ded0-8264-8330-9b18-7be327a398ae` started `2026-11-21T01:12:18.900454Z` and was recorded `in_progress`; `latest_result.run_id=8fb5af3f-96c4-8325-8e43-c41bfa820204` was created `2026-11-21T00:28:15.554687Z`, so it belongs to the prior completed legacy-checklist audit.
- The actual branch already contained the trusted activity-event PostgREST acceptance harness (CI #450/#451). Do not recreate it. The latest completed repository task before this run was the legacy checklist caller audit and runtime guard.
- Repository migrations: 27. Live project ledger: eight. Branch-only migrations: 19. PR #11 remains open and unmerged; PR #12 remains an open superseded draft.

## Current backup/restore instructions

1. Use Supabase CLI v3+ and `supabase db dump --remote="$SOURCE_DB_URL"`; `--remote=<ref|branch|url>` is the current selector. The hosted docs page still shows `--db-url`, but current CLI source docs mark that alias deprecated in v3 and removed in v4. Verify the printed `Target:` line and Dashboard Connect details.
2. Export roles, schema, data, and `supabase_migrations` history separately; keep artifacts outside Git and record hashes, sizes, exit statuses, CLI version, and PostgreSQL version.
3. On a separate isolated target, restore `roles.sql` first. Before schema restore, revoke target default privileges for TABLES, FUNCTIONS, and SEQUENCES from `anon` and `authenticated` for each reviewed object-owner role.
4. Restore schema/data and migration history with `ON_ERROR_STOP`; recreate and verify the custom `auth.users.on_auth_user_created` trigger after `public.handle_new_user()` exists.
5. Verify the complete backup manifest, role/default ACLs, extensions, Vault root-key decision, Auth trigger, and exactly eight source migration versions before applying the 19 branch-only migrations to the isolated target.
6. Review checklist conflicts and run `scripts/postgrest-organization-acceptance.ts` only against the isolated target. Never run it against production.

## Verification and limitations

- Final runbook commit `1b9c2ca` passed CI #464: 21/21 PostgREST preflight tests, 27/27 PostgreSQL 17 migration replay, 152/152 application tests, task hierarchy concurrency, typecheck, production build, npm install audit summary: 0 vulnerabilities reported.
- `bash -n` passed on the documented shell snippets. Actual Supabase CLI/pg_dump/psql/Docker tools and a local repository checkout are absent in the automation container; no backup or restore was executed.
- The 2026-11-21 live Supabase inspection was read-only. Nine public tables are RLS-enabled and empty; auth.users, Storage buckets/objects, and Vault secrets are zero; four extension versions and 12 auth/storage triggers were inventoried; no Edge Functions or auth/storage RLS policies were listed.
- No production DDL/DML, migration, RLS change, backup, restore, or merge was performed. The backup/export action is unavailable through the connected Supabase tools.

## Next run

Wait for owner-controlled backup and isolated restore artifacts. If they are still unavailable, do not retry export. Implement an offline manifest verifier (file presence, byte size, SHA-256, command status) or perform another distinct Organization acceptance audit. Keep Analytics queued.

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
> **Verified checkpoint — 2026-11-21 (task/subtask create request idempotency).** Repository `mohith-krishnaa/personal-os`; branch `feature/organization-v1`; starting HEAD `a8f62ee5b46f92579bb3ca42cae50f45a3c7f758`. Code/test HEAD `a5cf780b089c8e9013557a05e73d6f96f36c47f5`; [CI #426](https://github.com/mohith-krishnaa/personal-os/actions/runs/44806749670) passed on that exact commit. Read-only preflight query 17 was then tightened to verify the exact ordered unique key; [CI #427](https://github.com/mohith-krishnaa/personal-os/actions/runs/44806843968) passed on preflight commit `5d63c397d57e6088c7ff1f32a7ed148a4c23d28f`. The final README architecture-summary checkpoint before this state update was `ce077a4a697bff8ec3f6b99213cabf1d4a448512`; [CI #432](https://github.com/mohith-krishnaa/personal-os/actions/runs/44807105433) passed on the preceding documentation HEAD `551dabf15c9066a603e6fdc08a3c1a8165f36118`, and [CI #433](https://github.com/mohith-krishnaa/personal-os/actions/runs/44807205535) passed on `ce077a4a697bff8ec3f6b99213cabf1d4a448512`. The state/handoff/roadmap refresh at HEAD `3ffaf1dc410ea4d1b643085f230d793a85b4242c` passed [CI #434](https://github.com/mohith-krishnaa/personal-os/actions/runs/44807436061). This record-only follow-up is verified separately on the resulting branch HEAD. PR #11 remains open/unmerged; no merge was authorized.
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

## Latest resume checkpoint — transactional task activity events (2026-11-21)

- Starting HEAD: `431f311281bb432f2d722d671c9ad515ad27d275`.
- Implementation commit: `daf399d7f09feea92f30e8b0e3429916f1d55400`.
- Final code/test HEAD: `e288c55768bca52e906d51fd6b9580f3ba0cff33`; CI #408 passed on that exact commit.
- Documentation checkpoints `7ff05d1` (CI #409), `f19cf15` (CI #410), and `014bd50e4a4d4835927daa762cf1cc53c615b545` (CI #411) all passed on their exact commits. The latter is the latest fully verified branch checkpoint before this documentation-only update.
- CI #408/#411 verified 17/17 PostgREST safety preflight tests; 23/23 PostgreSQL 17 migrations; task activity failure/rollback/retry and migration reapplication assertions; Organization/RLS, archive, hierarchy and concurrency assertions; 133/133 application tests; typecheck; production build; npm audit 0 vulnerabilities. CI #407 initially failed TypeScript typecheck because a test mock accessed a union member not present on every plan; the mock was corrected before #408.
- Migration `20261121000100_durable_task_activity_events.sql` installs a SECURITY INVOKER AFTER INSERT/UPDATE trigger on `public.tasks`. It writes task create/update/status/recurrence events in the same statement transaction. The app-side task event inserts were removed. Reminder delivery remains on its existing atomic RPC.
- The trigger skips no-op updates and recurring-root self-link initialization. `setTaskStatusForUser` retries recurrence generation when a task is already COMPLETED; the existing recurrence unique index prevents duplicate occurrences.
- SQL fault-injection tests prove failed TASK_CREATED/TASK_UPDATED/TASK_COMPLETED/TASK_RECURRENCE_GENERATED inserts roll back their task statement; retry succeeds; Owner A cannot read Owner B events. Read-only preflight query 16 reports the trigger contract.
- **Not solved:** stable client request idempotency for task/subtask creation; DELETE events; append-only/tamper-resistant activity log; historical backfill. `activity_events` remains owner-scoped but mutable and polymorphic. Do not treat event counts as user-intent counts or event absence as proof no delete occurred.
- Repository migration count: 23. Fresh read-only production inspection reconfirmed 8 live ledger versions, so 15 migrations are branch-only. The live tasks table has no activity trigger or `client_request_id` column; `activity_events_owner` remains FOR ALL, with authenticated and service_role INSERT privileges.
- PR #11 remains open/unmerged and mergeable; PR #12 remains a superseded open draft. No PR was merged or closed.
- No production DDL/DML, migration, RLS modification, backup, restore, or live PostgREST test was performed. Owner-controlled complete backup, isolated restore, checklist conflict review, and authenticated two-owner PostgREST acceptance remain mandatory.
- Remote diff from the starting HEAD contains 13 files (6 implementation/test/migration files and 7 documentation files). No local checkout is attached; local working-tree cleanliness is unverified.

**Next task:** implement stable client-generated request IDs for task and subtask creation, with a per-owner unique database key and tests for same-request retries and concurrent duplicate submissions. Do not start Analytics yet.

---

## Latest resume checkpoint — task update service tests (2026-11-20)

- Starting head: `0c9b9b979a53cdf78701f2f51c0f0d3c95f3f560`.
- Code/test head: `44ecc05f9b62a10175f9b7f608c1ff0636b1dbc3`.
- CI #403 passed on the exact code/test head: 17/17 PostgREST safety preflight tests; complete 22-migration PostgreSQL 17 replay and Organization/RLS/concurrency checks; 132/132 application tests; typecheck; production build; npm audit 0 vulnerabilities.
- `updateTaskForUser` now contains the owner-scoped update service logic; public `updateTask` still authenticates with the server Supabase client before delegating. Seven tests cover missing owner, omitted/null relationship semantics, partial parent changes, owner filters, ACTIVE-project reassignment, ARCHIVED-project rejection before mutation, and the update-column allowlist.
- Only `src/lib/tasks.ts` and `src/lib/tasks.test.ts` changed in the code/test diff. No migration or production change. Migration inventory remains 22. Lint is not configured.
- Do not infer a clean local working tree: no local checkout was attached. PR #11 head matched the code/test commit and remained open/unmerged; PR #12 remains superseded.
- Production acceptance is still blocked on the owner-controlled complete backup, isolated restore, restored-copy checklist reconciliation review, and two-user authenticated PostgREST harness. No production operation was performed.

**Next task:** inspect the update service's error/side-effect contract, especially whether a failed `TASK_UPDATED` activity insert after a successful task UPDATE is intentionally best-effort or can leave a required audit record missing. Do not change transaction semantics without a documented requirement and tests.

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

> **Verified checkpoint — 2026-11-20 (direct PostgreSQL subtask lifecycle regression).** Repository: `mohith-krishnaa/personal-os`; branch: `feature/organization-v1`; code/test commit: `91075f588cd42f88b7014bb7e8d9eab8a32e3ab6`. PR #11 remains open and unmerged.
>
> Added direct subtask INSERT coverage to `supabase/tests/project-archive-lifecycle.sql`, which is already invoked by the full migration runner. A direct subtask INSERT under ACTIVE succeeds and preserves the requested project/parent IDs. Direct subtask INSERTs under COMPLETED and ARCHIVED projects are rejected with the exact active-project check-violation message; failed IDs are asserted absent. An existing child remains attached to its archived project and parent. Existing direct foreign-owner/cross-project parent checks remain in `organization-task-hierarchy.sql`.
>
> No migration or runtime application code changed. Migration count remains 20. [CI #354](https://github.com/mohith-krishnaa/personal-os/actions/runs/44673853542) passed on the exact code commit: 20/20 PostgreSQL 17 migrations replayed; Organization/RLS and archive lifecycle SQL assertions passed; task hierarchy and concurrency checks passed; **90/90 application tests passed**; typecheck and production build passed; npm audit reported 0 vulnerabilities. The existing esbuild install-script allowlist warning remains; no security settings were changed. No lint script is configured.
>
> Fresh read-only live inspection: Supabase is ACTIVE_HEALTHY on PostgreSQL 17.11.0.003 with 8 ledger entries. Live `projects` has legacy `title/status`; live `tasks` has `project_id/parent_task_id`; RLS is enabled on both; no user-defined triggers are present on those tables. The branch-only active-project trigger is not deployed.
>
> Production remains read-only. The complete owner-controlled schema/data/roles backup and isolated restore, restored-copy checklist conflict review, and authenticated two-user PostgREST CRUD/isolation tests remain outstanding. No local checkout is attached; local `git status` is unavailable.
>
> **Next task:** add authenticated-role direct subtask INSERT assertions to the two-owner migration fixture, proving the SECURITY INVOKER active-project trigger rejects inactive-project subtask links while preserving owner/parent relationship restrictions.
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

# Personal-OS — Current Handoff

Date: 2026-11-20

## Verified repository state

- Repository: `mohith-krishnaa/personal-os`.
- Stable branch: `main` at `2b42dd17796b75dca79434a81d4e1f0cbf0fa043`.
- Organization branch: `feature/organization-v1`; code/test HEAD `569d384f88b2f137d78ec5da8b41f40e40b73b28` passed CI #343 (384 commits ahead of `main`, 0 behind at the code checkpoint).
- PR #11 is open, unmerged, non-draft, and mergeable; its head matches the current branch.
- [CI #309](https://github.com/mohith-krishnaa/personal-os/actions/runs/44576380568) passed on code/test commit `020877abbbf63719716a9d0c615160a097744716`: 19-migration PostgreSQL 17 replay, Organization/RLS assertions, FK guard recovery/idempotence/fail-closed tests, checklist conflict report, hierarchy concurrency, 58/58 application tests, typecheck, and build.
- [CI #312](https://github.com/mohith-krishnaa/personal-os/actions/runs/44577390309) passed on its historical checkpoint. [CI #343](https://github.com/mohith-krishnaa/personal-os/actions/runs/44652747495) passed on current code/test HEAD `569d384f88b2f137d78ec5da8b41f40e40b73b28`: 20-migration PostgreSQL 17 replay, active-project migration reapplication, archive lifecycle SQL assertions, task hierarchy concurrency, 87/87 application tests, typecheck, build, and npm audit (0 vulnerabilities).
- The branch contains 20 migrations: 8 live-ledger versions plus 12 branch-only migrations (9 Organization, 1 Progress compatibility, 2 RLS performance).
- The project/task FK guard never drops or rewrites existing constraints. It creates only a missing expected FK when no FK uses that source column, validates a sole exact NOT VALID FK, and aborts on unexpected/duplicate/composite definitions.
- Live Supabase: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, 8 applied migrations; all 9 public tables have RLS enabled and report zero rows. `projects.name`, both checklist tables, Organization user-defined triggers, `goals.unit`, and `goals.target` are absent. The three existing project/task FKs were read-only inspected and are exact and validated.
- No complete owner-controlled schema/data/roles backup or successful isolated restore exists. Authenticated two-user PostgREST CRUD/isolation is not verified.
- No production DDL, migration, data write, RLS change, backup restore, or PR merge was performed. No local checkout is attached, so local working-tree status cannot be verified.
- Personal-OS Builder is enabled; its recorded last run is `2137c85a-2500-832c-b819-9896e93be753` (in progress, no completion timestamp), while latest stored result `603cd95a-511c-8321-9ad7-6459f2953f51` predates it.



## Current checklist compatibility finding

The runtime audit is complete: 56 TypeScript/TSX/JavaScript files under `src/` and `lib/`, plus root `middleware.ts`, were inspected. No current application runtime module references `task_checklist_items`; `src/lib/checklists.ts` uses only canonical `checklist_items`. This does not rule out older deployed or external clients. The legacy table remains temporarily writable under its existing owner-scoped RLS policies; post-reconciliation writes can be reported as `missing_canonical`. Do not add synchronization, change legacy write permissions, or drop the table without an owner-approved compatibility window, telemetry, and rollback plan.

**Next action:** owner-controlled complete schema/data/roles backup and successful isolated restore, then run the checklist conflict report against the restored copy and complete authenticated two-user PostgREST CRUD/isolation tests. The runtime inventory is done and must not be repeated.

## Work completed in this checkpoint

- Added authenticated `listSubtasksAction`; the server action resolves the current user and delegates to the service.
- The subtask service verifies that the parent belongs to the requested user and filters child rows by both `user_id` and `parent_task_id`.
- Updated the dashboard subtask panel to lazy-load direct children, display them, and toggle completion using the existing task-status server action.
- Preserved existing subtask creation behavior.
- Added tests for owner/parent filtering and rejection of a foreign-owned parent.
- Hardened project listing: resolve the authenticated user, fail closed when unauthenticated, and explicitly filter project reads by `user_id`. Added tests for owner/status filtering and unauthenticated rejection.
- Hardened task listing: resolve the user on the same server-side Supabase client used for the query, reject missing sessions, and explicitly filter task reads by `user_id`; optional project filtering and due-date/creation-time ordering are preserved. Added three mocked-client tests.

## CI and quality

- [CI #163](https://github.com/mohith-krishnaa/personal-os/actions/runs/44023466322) passed on migration-history commit 30e490aaf1832d7003717473a0eb5b3d6a16ce8c: **56 passed, 0 failed**; install, typecheck, and production build succeeded; npm install reported 0 vulnerabilities.
- [CI #165](https://github.com/mohith-krishnaa/personal-os/actions/runs/44023928005) passed on documentation checkpoint ef203157d686565a4f62aa047a3c17ce1f8afb52: **56 passed, 0 failed**; install, typecheck, and production build succeeded; npm install reported 0 vulnerabilities.
- [CI #166](https://github.com/mohith-krishnaa/personal-os/actions/runs/44024104158) passed on documentation checkpoint `7f85384b0a89f5447f55d34b6bb367e9d8f527b3` with 56 tests, typecheck, production build, and 0 npm audit vulnerabilities.
- [CI #167](https://github.com/mohith-krishnaa/personal-os/actions/runs/44024323363) passed on code/documentation head `b8879c55a9439ea7586ea7400a73534ebd547ea8`: 56 tests, typecheck, production build, and 0 npm audit vulnerabilities.
- [CI #168](https://github.com/mohith-krishnaa/personal-os/actions/runs/44030918679) passed on documentation checkpoint `0ad4b9dd5acbcdf5542cb70e0a7c11bb3a03ee49`: 56 tests passed, 0 failed; typecheck and production build passed; npm install audited 43 packages and reported 0 vulnerabilities.
- [CI #169](https://github.com/mohith-krishnaa/personal-os/actions/runs/44031107574) passed on documentation checkpoint `18c814b26054e474a4c84c2bf6a0efb103b166b2` with 56 tests, typecheck, production build, and 0 npm audit vulnerabilities.
- [CI #170](https://github.com/mohith-krishnaa/personal-os/actions/runs/44031496258) passed on documentation checkpoint `0fe10995fbd3d5cb2e74c5a07d2257bc8ff623cc` with the same 56-test, typecheck, build, and audit results.
- No lint script or linter configuration exists; lint is unavailable and no lint pass is claimed.
- The workflow does not run live database integration or two-user RLS tests.

## Architecture / security boundaries

- Server actions use the authenticated server-side Supabase client and resolve the caller with `auth.getUser()`.
- Subtask listing checks parent ownership and applies owner + parent filters to the child query.
- PostgreSQL RLS and task-link validation triggers remain the intended authoritative persistence boundary. Mocked-client tests verify query construction, not live RLS.
- The UI change displays one level of direct subtasks. It does not claim recursive hierarchy navigation.
- `checklist_items` remains the canonical checklist table; the legacy `task_checklist_items` table is retained and reconciled forward.
- Project compatibility preserves legacy `projects.title` while supporting application-facing `projects.name`.

See [docs/architecture/organization-v1.md](docs/architecture/organization-v1.md) for the full trust boundaries and migration decisions. See [docs/operations/organization-v1-preflight.md](docs/operations/organization-v1-preflight.md) for the live schema, migration history, backup gate, and rollout sequence.

## Live Supabase state — read-only verified 2026-11-17

- Project gujzvkyytxsnervovvrt reports ACTIVE_HEALTHY, region ap-southeast-1, PostgreSQL 17.11.0.003. Read-only SQL, migration, table, policy, constraint, and advisor inspection now succeeds.
- The live migration ledger has exactly 8 rows. The exact SQL statements have been restored into repository files with matching live versions/names. The migration directory now has 8 applied core migrations, 7 local-only Organization migrations, and 1 local-only Progress compatibility migration; the duplicate non-ledger reminder migration was removed.
- Live projects has title, goal_id, priority, start_date, and target_date, but no name. Its status constraint includes ACTIVE, COMPLETED, and ARCHIVED.
- Live tasks has project_id and parent_task_id foreign keys, but the Organization validation trigger is absent.
- Neither checklist_items nor task_checklist_items exists. All nine public application tables have RLS enabled.
- Exact counts are zero for the nine public application tables, auth.users, and storage.objects.
- Projects/tasks use legacy owner-wide policies. goals has overlapping owner-wide and command-specific policies.
- Security and health advisors return no lints. Performance advisor reports 4 unindexed foreign keys, 14 auth_rls_initplan warnings, 13 unused-index findings, and 4 overlapping permissive-policy findings on goals.
- The read-only preflight SQL file was executed against the live project; all 8 SELECT statements succeeded.
- The Free Plan does not include scheduled backups. No manual backup has been created; the current automation runtime has no Docker daemon, pg_dump, or database password.
- No production migration, DDL, RLS change, data write, or merge was performed.

See [Organization V1 preflight and recovery runbook](docs/operations/organization-v1-preflight.md) and [read-only SQL preflight](supabase/operations/organization-v1-preflight.sql).

## Next safe actions

1. Create a private schema/data/role dump using the Supabase CLI on an owner-controlled machine with Docker Desktop; keep it out of Git.
2. Restore-test the dump against an isolated local database or disposable Supabase project. Recheck auth.users and storage.objects before backup because CLI db dump excludes managed schemas.
3. Run supabase migration list and confirm the eight applied versions match the reconstructed local files.
4. Test the seven Organization migrations against a disposable database matching the live legacy schema; do not run migration repair or migration up against production yet.
5. After explicit rollout approval and verified recovery, apply only reviewed Organization migrations and re-run the SQL preflight plus advisors.
6. Test authenticated project, task association, subtask, and checklist CRUD with two separate users, including direct API cross-user relationship attacks.
7. Merge PR #11 only after backup/recovery, migration, RLS, authenticated isolation, and current-head CI gates pass.

## Roadmap gate

Organization V1 remains the highest-priority incomplete milestone. Do not start Analytics V1 until live schema/RLS, recovery, migration rollout, advisors, authenticated CRUD, and cross-user isolation are verified. AI Assistant, Research Agent, Adaptive Scheduling, and production hardening remain queued behind it.


## 2026-11-17 — Subtask create/list consistency fix

- Live PR #11 pre-change head was `b466ee0ba32cae5b4a1763db50360a69e132ca28`; PR #11 remains the active Organization V1 review, while PR #12 is a superseded draft.
- Fixed a UI state bug where a successful create after a failed initial subtask read marked an incomplete local list as fully loaded. The panel now refreshes the canonical owner-scoped list in that case, retains the created row if refresh fails, and keeps retry available.
- The Add control is disabled while a list read is in flight to prevent overlapping read/create races.
- Added two unit tests for the state transition helper. CI run #122 (ID `43959430815`) passed on the implementation commit: 35 tests, typecheck, and production build passed; npm install reported 0 vulnerabilities. A subsequent documentation-only reconciliation must still have green current-head CI before merge.
- No schema, migration, RLS, or production data changes were made.
- Database rollout remains blocked: the Supabase project metadata is healthy, but migration listing, verbose table introspection, read-only SQL, and advisor requests fail with timeouts/hibernation. Live schema and migration ledger are unknown.
- Next safe action: restore supported database connectivity and inspect the live migration ledger/schema before any DDL or merge; verify the latest documentation-only PR head's CI before merge.


## 2026-11-17 — Checklist create/list recovery

- Live PR #11 remains open and unmerged; PR #12 remains a superseded draft.
- Fixed the checklist equivalent of the subtask partial-list bug. If the initial checklist read failed, a successful create now keeps the new row visible and refreshes through the existing authenticated `listChecklistItemsAction` instead of treating the local partial list as complete.
- The new helper preserves the service's canonical ordering: `position`, then `created_at`. The component tracks successful list loading, leaves the list retryable if refresh fails, and disables Add during a read.
- Added three regression tests in `src/lib/checklists.test.ts`. They cover loaded-list ordering, reload after a failed initial read, and retention of locally created rows while the list remains incomplete.
- No database schema, migrations, RLS, privilege, or server-action authorization changes were made.
- CI for the final PR head must be checked before merge. The repo has no lint script/configuration, so lint is not claimed.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but `list_migrations` and verbose `list_tables` timed out during this run. Live migration ledger and schema remain unknown; no production migration or data/schema change was made.

Next actions: verify final-head CI; restore DB connectivity; inspect migration ledger and Organization tables; confirm recovery readiness; then complete authenticated CRUD and two-user isolation tests before merge.


## Verified follow-up — Checklist recovery (2026-11-17)

- Latest verified PR #11 head at this checkpoint: `4bb083fe94fd36419f47149c3951bc9b594c98aa`; PR remains open, unmerged, non-draft, and mergeable. PR #12 remains a superseded draft.
- Checklist create after a failed list read now retains the created row and refreshes through the authenticated list action. If refresh fails, the row remains visible and Retry remains available. Locally appended items preserve service ordering by `position` then `created_at`.
- Three regression tests were added for canonical ordering and incomplete-list recovery.
- [CI #128](https://github.com/mohith-krishnaa/personal-os/actions/runs/43969545168) passed on the verified head: **38 tests passed, 0 failed**; `npm run typecheck` and `npm run build` passed; install audited 43 packages and reported 0 vulnerabilities.
- No lint script/configuration exists. No schema/RLS changes, production migrations, or production data writes were made.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but migration listing, verbose table introspection, read-only SQL, and security/performance/health advisors still fail with connection timeouts or hibernation responses. Live migration ledger/schema remain unknown.

Organization V1 remains blocked on live database inspection, recovery readiness, and authenticated two-user CRUD/isolation verification. Do not merge or start Analytics until those gates pass.


## 2026-11-17 — Checklist service ownership tests

- Current PR #11 head: `adfffa6f5e125ff9224e618a89ec177144663c9f`; PR remains open and unmerged. Raw GitHub PR metadata reports mergeable=true and mergeable_state=`unstable` while checks are pending.
- Added four mocked-service regression tests in `src/lib/checklists.test.ts`: list verifies task ownership and owner/task filters/order; a foreign-owned task is rejected before checklist query; create verifies owner/task/title/position insert payload after task validation; completion and deletion mutations filter by item ID and owner.
- No production code or database schema/permissions changed. These tests verify service query construction, not live PostgreSQL RLS.
- CI #131 (ID `43978680326`) was queued at last check. The previous head passed CI #130 with 38 tests, typecheck, production build, and 0 npm audit vulnerabilities. Do not claim the new test commit is green until #131 completes.
- Supabase project metadata reports `ACTIVE_HEALTHY`, but migration listing, verbose table introspection, and read-only SQL timed out. Security, performance, and health advisors report the project hibernated. Live migration ledger/schema remain unknown.
- No production migration, schema/data change, or merge was performed.

Next action: verify CI #131 on the current head, then continue database access recovery and live schema/migration inspection. Keep PR #11 unmerged and Analytics queued until the production authorization gates pass.


## Latest verified follow-up — checklist ownership tests (2026-11-17)

- Current PR #11 head: `bc82493c8c5533148e3d82aaf667374fd33b9ee1`; GitHub reports PR open, unmerged, non-draft, `mergeable=true`, `mergeable_state=clean`.
- Added four mocked Supabase service tests to `src/lib/checklists.test.ts`: owner/task filters and ordering on list; foreign-owned task rejection before checklist query; trusted owner/task/title/position insert payload; owner-scoped completion and deletion.
- CI #131/#132 failed because the new test file omitted imports for `listChecklistItems` and `setChecklistItemCompleted`. Those imports were added in the current head.
- [CI #135](https://github.com/mohith-krishnaa/personal-os/actions/runs/43978834178) passed on the current head: **42 passed, 0 failed**; dependency install audited 43 packages with 0 vulnerabilities; `npm run typecheck` passed; `npm run build` passed.
- No lint script/configuration exists. The tests use mocked Supabase clients and do not prove PostgreSQL RLS or authenticated two-user isolation.
- Supabase metadata reports `ACTIVE_HEALTHY`, but migration listing, verbose table introspection, and read-only SQL time out; security/performance/health advisors report hibernation. Live migration ledger/schema remain unknown.
- No production migration, schema/data write, or PR merge occurred.

Next action: restore supported Supabase database access, inspect the live ledger/schema, confirm backup/recovery readiness, then complete authenticated CRUD and two-user isolation. Keep Analytics queued until Organization's production gates pass.

 
## 2026-11-17 — Subtask retry-state correction

- Corrected `SubtaskManager.loadSubtasks()` failure handling. A failed refresh now retains known rows but sets `loaded=false`, ensuring a subsequent create triggers a canonical owner-scoped reload.
- Added a pure state helper and regression coverage for the failed-read → incomplete-list → create → reload sequence.
- [CI #140](https://github.com/mohith-krishnaa/personal-os/actions/runs/43987021956) passed on code-bearing commit `07c95f13a76435ec94976e61b8123143f46e4158`: 43 tests passed, 0 failed; typecheck and production build passed; 43 packages audited, 0 vulnerabilities.
- Lint remains unavailable because the repository has no lint script/configuration.
- Live DB status is unresolved: project listing says `ACTIVE_HEALTHY`, but direct project/migration/table/advisor requests return a hibernation error. Live schema and migration ledger are unknown; no production SQL or DDL was run.
- Do not merge until live schema/migration inspection, recovery readiness, authenticated CRUD, and two-user isolation are verified.

 
- Final documentation-head verification: [CI #141](https://github.com/mohith-krishnaa/personal-os/actions/runs/43987217774) passed on `7f72caff39f4e4efba2bdf65fdcb11ff29163360`: 43 tests passed, 0 failed; typecheck and production build passed; 43 packages audited, 0 vulnerabilities.


## 2026-11-17 — Project-list owner scoping

- PR #11 is the active Organization V1 review; it was open, unmerged, non-draft and mergeable at the start of this change. PR #12 remains an open draft superseded by PR #11. Stable main was 2b42dd17796b75dca79434a81d4e1f0cbf0fa043.
- Before this change, listProjects relied on database RLS without an explicit authenticated-owner filter. It now calls auth.getUser(), fails closed if no authenticated user is returned, and constrains project reads with .eq('user_id', user.id). Optional status filter and descending creation-time ordering remain intact.
- Added two tests covering owner/status filters and unauthenticated rejection before database access. These use mocked Supabase clients and do not establish PostgreSQL RLS or live cross-user isolation.
- Latest prior CI #142 passed on dd18922b228f0bb44a6a01e404e33d3b4d0444bd. New code CI is pending; verify the latest PR head before making a completion claim. The workflow currently runs install, tests, typecheck, and production build. No lint script/configuration exists.
- Supabase project metadata reports ACTIVE_HEALTHY, but migration listing, verbose table introspection and a read-only SQL probe fail with connection timeouts; advisor calls report hibernation. Live schema and migration ledger remain unknown. No production migration, schema/data change, or PR merge was performed.

Next safe actions: verify CI on the updated PR head; restore supported Supabase database-tool connectivity; inspect the live migration ledger and Organization table definitions; confirm backup/recovery readiness; then run authenticated CRUD and two-user isolation tests before production rollout or merge.

## Verification — project-list owner scoping (2026-11-17)

- Code-bearing commit 1106efd1b3a1be9e3b5aac18bd8a6e714476cb9f passed CI #143 (run ID 43994197614): 45 tests passed, 0 failed; npm install, typecheck, and production build passed; install output reported 0 vulnerabilities.
- Documentation checkpoint 2c618299c5bd3db2bf03aad7f4afecc6ab2521a7 passed CI #144 (run ID 43994283596) with the same checks and results.
- Lint is not available: there is no lint script or linter configuration.
- The project-list change is application-level defense in depth. Mocked tests do not establish PostgreSQL RLS behavior.
- Current live DB blocker is unchanged: project metadata ACTIVE_HEALTHY, but migration listing, verbose table introspection and read-only SQL time out; advisor calls report hibernation. Do not apply DDL or merge until the actual ledger/schema and recovery readiness are verified.


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


## 2026-11-17 — Task relationship ownership preflight

- Starting PR #11 head: `49d7faae9bd6b8f448e7ccf438862b04a4aeb4c1`; PR #11 was open, unmerged, non-draft, and mergeable. PR #12 was an open draft marked superseded.
- Inspected the current task services and Organization migration. The database trigger already validates owner/project consistency and rejects direct self-parenting; the application write paths did not preflight those relationships.
- Added `src/lib/task-relationships.ts`. Task creation now verifies any selected project and parent against the authenticated owner; task updates that change either link first load the current relationship using task ID + owner, resolve omitted relationship fields, then validate the resulting relationship.
- Parent must be owned by the caller and use the same project as the task. A selected project must also be owned by the caller. Direct self-parenting is rejected before querying.
- Six mocked-client tests cover valid links, foreign parent, mismatched project, foreign project, direct self-parent, and missing owner.
- The database trigger remains necessary for races and indirect cycles; mocked tests do not prove live RLS/trigger behavior.
- No database migration, schema/RLS change, production write, or merge was performed.
- [CI #153](https://github.com/mohith-krishnaa/personal-os/actions/runs/44009478456) passed on code-bearing commit `9bdaa29e60afddc893a7e6fa5a1e43ee37469a7d`: **54 tests passed, 0 failed**; `npm run typecheck` and `npm run build` passed; `npm install` audited 43 packages and reported 0 vulnerabilities. No lint script or linter configuration exists, so lint remains unavailable.
- Supabase project `gujzvkyytxsnervovvrt` reports `ACTIVE_HEALTHY`, but migration listing, verbose public-table introspection, and a read-only SQL query time out; security/performance/health advisors report hibernation. The live migration ledger/schema remain unknown.
- Next safe actions: verify CI on the new PR head; restore supported Supabase connectivity; inspect the live migration ledger and Organization tables; confirm recovery readiness; then run authenticated CRUD and two-user isolation before rollout/merge.


## Verification — task relationship ownership preflight (2026-11-17)

- Verified implementation head: `9bdaa29e60afddc893a7e6fa5a1e43ee37469a7d`.
- [CI #153](https://github.com/mohith-krishnaa/personal-os/actions/runs/44009478456) passed on code-bearing commit `9bdaa29e60afddc893a7e6fa5a1e43ee37469a7d`: **54 tests passed, 0 failed**; `npm run typecheck` and `npm run build` passed; `npm install` audited 43 packages and reported 0 vulnerabilities. No lint script or linter configuration exists, so lint remains unavailable.
- The workflow completed all four configured stages: dependency installation, unit tests, TypeScript check, and production build. Test output reported 54/54 passing.
- No lint step is configured. No live database integration or two-user RLS test ran.
- Current PR #11 remains open and unmerged. The latest CI does not satisfy the database rollout gate.
- Supabase project metadata is ACTIVE_HEALTHY, but migrations, table introspection, read-only SQL, and security/performance/health advisors remain unavailable due timeouts/hibernation. The live migration ledger and schema are unknown.
- Next safe action: restore supported database access, inspect the actual migration ledger/schema, confirm backup/recovery readiness, then run authenticated CRUD and two-user isolation before migration rollout or merge.


## Latest PR-head check — 2026-11-17

- Documentation head `f02a2145e7dc7aa05b8914188dee6ae322457650` passed [CI #154](https://github.com/mohith-krishnaa/personal-os/actions/runs/44009629263): 54 tests passed, TypeScript check passed, production build passed, and npm install reported 0 vulnerabilities.
- PR #11 remains open, unmerged, non-draft, and mergeable. This docs-only handoff cleanup will trigger a new current-head CI run; verify that run before any merge decision.


## Latest checkpoint — partial task relationship update semantics (2026-11-17)

- Latest verified PR #11 head: `b2526b832281e55c3feaaf854341dbf11af94e97`; PR remains open, unmerged, non-draft, and mergeable.
- Added `resolveTaskOrganizationLinks` and wired it into `updateTask`. Partial updates preserve omitted existing project/parent links; explicit `null` clears only the supplied relationship.
- Added two regression tests in `src/lib/tasks.test.ts` for omitted-field preservation and explicit-null clearing.
- [CI #156](https://github.com/mohith-krishnaa/personal-os/actions/runs/44016733596) passed on the exact code head: 56 tests, 0 failures; TypeScript and production build passed. Dependency installation, tests, typecheck, and build all completed successfully.
- No lint script/configuration exists. The repository has no package lockfile; CI currently uses `npm install`, so exact dependency versions are not pinned.
- Live Supabase status is still unresolved: metadata says `ACTIVE_HEALTHY`; migration listing, verbose table inspection, and read-only SQL time out; security/performance advisors report hibernation. Unified logs returned no Postgres rows in the default 24-hour window. Live migration ledger/schema remain unknown.
- No production migrations, schema/data changes, RLS changes, or merge were performed.

Next safe action: restore supported database connectivity, inspect the actual migration ledger/schema, confirm backup/recovery readiness, and run authenticated CRUD plus two-user isolation before merge. Analytics remains queued behind Organization.



## Latest checkpoint — CI action runtime upgrade (2026-11-17)

- Upgraded `.github/workflows/ci.yml` to `actions/checkout@v5` and `actions/setup-node@v5`; upstream action manifests confirm both run on Node 24.
- [CI #158](https://github.com/mohith-krishnaa/personal-os/actions/runs/44017017543) passed on the exact workflow head `6217e100777543ecc65590dbc1156ebd4dfc0aca`: 56 tests, 0 failures; typecheck and production build passed; npm install reported 0 vulnerabilities.
- The Node 20 deprecation warning observed in CI #157 is absent from CI #158.
- No application, database, migration, or RLS behavior changed in this workflow-only follow-up.
- Lint remains unavailable; no lint script/configuration or package lockfile exists.
- Supabase migration listing, verbose table inspection, and read-only SQL still time out; security/performance advisors report hibernation despite ACTIVE_HEALTHY project metadata. Live schema and migration ledger remain unknown.



## Documentation verification — 2026-11-17

- Documentation checkpoint `f5cdf41d3b42e95a9bee202f68db4d4ecd18b73d` passed [CI #159](https://github.com/mohith-krishnaa/personal-os/actions/runs/44017156115): 56 tests, 0 failures; typecheck and production build passed; npm install reported 0 vulnerabilities.
- CI #159 ran with `actions/checkout@v5` and `actions/setup-node@v5`; no Node 20 deprecation warning was emitted.
- This checkpoint changed documentation only. The latest application/workflow implementation remains code-bearing commit `6217e100777543ecc65590dbc1156ebd4dfc0aca`, verified by CI #158.



## 2026-11-17 — Supabase connectivity investigation

- Fresh diagnostics confirm the intended project `gujzvkyytxsnervovvrt` is listed as `ACTIVE_HEALTHY` in Supabase project metadata (region `ap-southeast-1`, PostgreSQL `17.6.1.155`). Project listing and API URL lookup succeed.
- A minimal read-only SQL probe (`SELECT 1`) and migration listing still fail with connection timeouts. Security/performance/health advisor calls return a contradictory “project is currently hibernated” response.
- Unified logs query endpoint responds, but the queried window returned no sources/rows. This is not evidence that the database has no errors; there are no log records available to diagnose the connection failure from this query.
- Official Supabase status page reports all systems operational on 2026-11-17; the Nov 12 database connection incident is marked resolved. This is not a platform-wide outage according to current status, but does not exclude a project-specific issue.
- Root cause is not proven. Current leading possibilities are project-specific Postgres runtime/connectivity trouble or stale/inconsistent state in the Supabase MCP/management integration. Do not assert that the project is paused: the authoritative project metadata says `ACTIVE_HEALTHY`.
- Did not call `restore_project`, pause/restart/resize compute, change credentials/settings, run DDL, apply migrations, alter data/RLS, or merge PR #11. An unconditional restore is not justified while metadata says healthy.
- Incident record and next safe diagnostic sequence: [Supabase connectivity incident](docs/operations/supabase-connectivity-incident-2026-11-17.md). Next, check Dashboard Database/Compute state and run `select now(), current_database(), version();` in the Dashboard SQL Editor. If Dashboard SQL succeeds, reconnect/re-authorize MCP; if it fails too, escalate to Supabase Support with project ref, region, timestamps, and exact errors.
- Organization V1 remains blocked on live migration/schema inspection, recovery readiness, advisors, and authenticated two-user isolation. Analytics remains queued.


## Latest verified checkpoint — migration-history reconciliation and state update (2026-11-17)

- Recovered the eight applied migration SQL statements directly from the live supabase_migrations.schema_migrations ledger and stored them under exact version/name filenames.
- Removed six timestamp-drifted or duplicate local core migration files. The resulting migration directory contains the eight exact applied migrations followed by six unapplied Organization migrations.
- Verified all eight local core migration files match the live ledger SQL statements exactly after trimming the trailing newline.
- Added a migration-history README, an Organization rollout runbook, and an eight-query read-only SQL preflight. Executed all eight SQL statements against the live project successfully.
- [CI #163](https://github.com/mohith-krishnaa/personal-os/actions/runs/44023466322) passed on migration-history head 30e490aaf1832d7003717473a0eb5b3d6a16ce8c. [CI #164](https://github.com/mohith-krishnaa/personal-os/actions/runs/44023774660), [CI #165](https://github.com/mohith-krishnaa/personal-os/actions/runs/44023928005), and [CI #166](https://github.com/mohith-krishnaa/personal-os/actions/runs/44024104158) passed on successive documentation checkpoints; each run completed 56 tests, typecheck, production build, and 0 npm audit vulnerabilities. Latest verified checkpoint: 7f85384b0a89f5447f55d34b6bb367e9d8f527b3.
- No production migration, DDL, RLS change, data write, or merge occurred. Backup/recovery remains the rollout blocker.


## Latest verified checkpoint — 2026-11-17 11:49 IST

- Latest verified code-bearing checkpoint: `b8879c55a9439ea7586ea7400a73534ebd547ea8` (CI #167). Latest verified documentation checkpoint: `0fe10995fbd3d5cb2e74c5a07d2257bc8ff623cc` (CI #170 passed: 56 tests, typecheck, production build, 0 npm audit vulnerabilities). PR #11 remains open, unmerged, non-draft, and mergeable; consult the live PR page for the exact current head. Lint is not configured.
- Live Supabase read-only access is working in this checkpoint. Project status is ACTIVE_HEALTHY; PostgreSQL is 17.11.0.003 in ap-southeast-1. The live migration ledger has 8 entries matching the 8 reconstructed core migration files.
- All 9 public application tables have RLS enabled and zero rows; `auth.users` and `storage.objects` also have zero rows. `projects.title` exists and `projects.name` does not. Both checklist tables and the task Organization validation trigger are absent.
- Security and health advisors return no lints. Performance advisor still reports 4 unindexed foreign keys, 14 auth_rls_initplan warnings, 13 unused-index findings, and 4 overlapping permissive-policy findings on goals.
- The earlier database connector timeouts are no longer reproducing, but their root cause is unknown. No infrastructure action was taken.
- Dashboard evidence confirms the Free Plan has no scheduled backups. No manual schema/data/role backup or restore test exists. The automation runtime has no Docker, pg_dump, or Supabase CLI.
- Static migration review identified an unverified concurrency edge: the cycle-prevention trigger walks ancestors but does not serialize concurrent hierarchy writes. Test this against disposable PostgreSQL and decide whether a per-user transaction lock is required before rollout.
- No production schema/data changes, migrations, RLS changes, or PR merge occurred.

Next safe action remains a private logical backup and isolated restore test, followed by disposable migration/concurrency tests and authenticated two-user direct-API isolation. Do not start Analytics or merge PR #11 before these gates pass.


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

## Latest documentation verification — 2026-11-17

- Code-bearing head `d872a6e6f530a9ee87e8851a1cf5465197240379` passed CI #176; documentation-only head `74979439c63e9ba27009a786cf2d929c4a15e68e` passed CI #177.
- Both runs completed the PostgreSQL 17 hierarchy integration, 56 application tests, typecheck, production build, and npm audit with 0 vulnerabilities.
- PR #11 remains open and unmerged. The live database is unchanged; do not apply migrations or merge until the private backup/restore, full migration-chain, and authenticated two-user isolation gates pass.


## Latest handoff — full migration replay and progress schema repair (2026-11-17)

### Implemented on `feature/organization-v1`

- Added a disposable PostgreSQL 17 migration replay that applies all 15 local SQL migrations in version order. The CI fixture seeds legacy project/checklist records before the compatibility migrations, then verifies checklist reconciliation, project `title`/`name` dual-write, owner-scoped RLS for two authenticated users, and the `rls_auto_enable()` client-execution restriction.
- The existing hierarchy integration still runs separately and verifies concurrent cycle rejection under two READ COMMITTED sessions plus invalid parent owner/project mutations.
- Live schema inspection exposed a Progress V1 mismatch: `public.goals` has no `unit` or `target`, while the dashboard progress service selects both. The original Progress V1 `CREATE TABLE IF NOT EXISTS` skipped those columns because the core migration had already created `goals`.
- Added forward migration `20261117000100_reconcile_progress_goal_metrics.sql`. It adds nullable `unit` and `target` columns with validation checks, preserving legacy goals without inventing a unit or target. The application now renders legacy goals safely and hides progress logging until both metrics are configured.
- Added a regression test for legacy goal summaries. Newly created measurable goals still require non-empty units and positive targets.

### Verification

- CI #189 passed on code head `3c23e01e3574b4fc91d15a1929e7c5e37eb16988`.
- CI #191 passed on the architecture/migration documentation head; CI #195 passed on the subsequent project-state/roadmap/handoff/runbook documentation checkpoint.
- All three runs (#189, #191, #195) passed the 15-migration replay, authenticated two-owner RLS checks, hierarchy concurrency, 58/58 application tests, typecheck, production build, and npm audit with 0 vulnerabilities.
- Lint remains unavailable because the repository has no lint script/configuration.

### Live Supabase — read-only and unchanged

- Project: `ACTIVE_HEALTHY`, ap-southeast-1, PostgreSQL 17.11.0.003.
- Migration ledger: 8 applied core migrations. Six Organization migrations and one Progress compatibility migration remain unapplied.
- Live `projects` has `title` but no `name`; both checklist tables and the task Organization trigger are absent.
- Live `goals` lacks `unit` and `target`; dashboard progress reads are expected to fail until the forward migration is applied.
- Security advisor: no lints. Performance findings: 4 unindexed foreign keys, 14 auth RLS initialization-plan warnings, 13 unused indexes, and 4 overlapping permissive policies on `goals`.
- Free Plan scheduled backups are unavailable; no manual logical export or restore test exists.
- No production DDL, migration, RLS change, data write, restore, or PR merge was performed.

Next safe action: create private schema/data/role exports, restore-test them in an isolated database, replay the 15 migrations against that restored snapshot, and run authenticated direct-API isolation tests. Keep production read-only until recovery is proven and rollout is explicitly approved. Organization remains the highest-priority incomplete roadmap milestone; Analytics stays queued.


## Latest Organization test improvement — 2026-11-17

- Added a valid Owner B legacy checklist row to the migration fixture; both owners' valid rows must reconcile, while the malformed Owner A-to-Owner B task association must not be copied.
- The authenticated RLS fixture now verifies each owner sees only their own projects, tasks, canonical checklist rows, and legacy checklist rows.
- Both owners directly attempt UPDATE and DELETE against the other owner's project, task, canonical checklist item, and legacy checklist item. Each operation must affect zero rows; neither owner's rows may be changed or removed.
- [CI #207](https://github.com/mohith-krishnaa/personal-os/actions/runs/44055203271) passed all configured steps on `a9f73bfc26de818679c101974544793a839f2c74`: migration replay, task hierarchy concurrency, application tests, TypeScript typecheck, and production build.
- Live Supabase remains unchanged. The migration ledger still has 8 applied entries; 7 Organization migrations and 1 Progress compatibility migration remain unapplied. No manual backup/restore test exists.


## 2026-11-17 — reciprocal insert and relationship isolation

- Commit e9ea11a85e9145698900d876edf34f289ca76b2f extends the authenticated Owner B fixture to attempt a spoofed project insert, a task insert linked to Owner A's project, canonical and legacy checklist inserts attached to Owner A's task, task project/parent reassignment to Owner A records, and canonical/legacy checklist reassignment to Owner A's task.
- Each attempt must be rejected with insufficient privilege; an unexpected success raises a test failure. Existing Owner A insert/link checks and reciprocal cross-owner UPDATE/DELETE checks remain in place.
- [CI #209](https://github.com/mohith-krishnaa/personal-os/actions/runs/44064242592) passed: all 15 SQL migrations replayed in PostgreSQL 17; Organization migration/RLS assertions and task-hierarchy concurrency checks passed; 58 application tests passed with 0 failures; typecheck and production build passed; npm install audited 43 packages and reported 0 vulnerabilities.
- The live Supabase project was re-inspected read-only. It remains ACTIVE_HEALTHY with 8 applied migrations, 9 public application tables with RLS enabled, and zero rows in those tables, auth.users, and storage.objects. No production DDL, migration, RLS change, or data write was performed.
- This remains disposable PostgreSQL verification. Production rollout is still blocked by the missing private backup/restore and live authenticated PostgREST checks.


## 2026-11-17 — checklist SELECT ownership hardening

- Added migration 20261117000200_harden_checklist_select_ownership.sql to require both checklist-row ownership and referenced-task ownership for SELECT on canonical and legacy checklist tables.
- Added malformed canonical and legacy checklist fixtures owned by Owner A but attached to Owner B's task. Owner A must not see either; both owners retain access to valid checklist rows.
- [CI #211](https://github.com/mohith-krishnaa/personal-os/actions/runs/44065216491) passed all 16 migrations, PostgreSQL RLS assertions, task hierarchy concurrency, 58 application tests, typecheck, and production build. [CI #212](https://github.com/mohith-krishnaa/personal-os/actions/runs/44065285214) passed the test-message correction.
- The live Supabase database was not modified. The new migration is local-only; no production backup/restore or live PostgREST verification exists yet.


## 2026-11-17 — anonymous Organization role isolation

- Extended the PostgreSQL 17 migration assertion fixture to grant table-level privileges to `anon` and then verify that RLS denies access independently of SQL grants.
- Anonymous role reads return zero rows across projects, tasks, canonical checklists, and legacy checklists. Anonymous inserts are rejected on all four tables; attempted updates/deletes cannot affect authenticated rows.
- [CI #216](https://github.com/mohith-krishnaa/personal-os/actions/runs/44072614729) passed the complete 16-migration replay, authenticated RLS checks, anonymous denial, hierarchy concurrency, application tests, TypeScript check, and production build.
- Live Supabase remains ACTIVE_HEALTHY with 8 applied migrations and 9 RLS-enabled public application tables. The Organization migrations remain unapplied. No production database change or PR merge occurred.
- Next safe action remains a private schema/data/role backup plus successful isolated restore, followed by migration replay and live PostgREST tests using anonymous and two distinct authenticated identities.


## Latest checkpoint — complete anonymous Organization CRUD denial matrix (2026-11-17)

- Code-bearing commit [fba0eee](https://github.com/mohith-krishnaa/personal-os/commit/fba0eeeda2b824afd8525d9f941050dca08e6a6a) extends the anonymous RLS fixture from representative write checks to the complete CRUD matrix.
- The test explicitly grants `anon` table-level SELECT, INSERT, UPDATE, and DELETE on `projects`, `tasks`, `checklist_items`, and `task_checklist_items`. Under an empty JWT subject it verifies zero visible rows, denied inserts, zero-row updates, and zero-row deletes on every table.
- [GitHub Actions run 44082207231](https://github.com/mohith-krishnaa/personal-os/actions/runs/44082207231) completed successfully: full 16-migration PostgreSQL 17 replay, task-hierarchy concurrency test, 58/58 application tests, TypeScript typecheck, production build, and npm audit with 0 vulnerabilities. No lint script/configuration exists.
- This is disposable PostgreSQL verification only. Live Supabase remains unchanged: ACTIVE_HEALTHY, PostgreSQL 17.11.0.003, 8 applied migrations, 8 local-only migrations, and 9 RLS-enabled public application tables with zero rows. The seven Organization migrations and one Progress compatibility migration remain unapplied.
- No production DDL, migration, RLS change, data write, restore, or PR merge was performed. Private backup/restore and live authenticated PostgREST verification remain the rollout blockers.


## 2026-11-18 — Organization foreign-key index verification

- Added full-chain assertions for the valid/ready indexes already defined by pending migrations: `tasks_project_id_idx`, `tasks_parent_task_id_idx`, and `projects_goal_id_idx`.
- Added read-only preflight query 9 for those three indexes plus the related `notifications_task_id_idx` finding. The query was executed against live Supabase and all four expected names were absent.
- CI #222 passed: 16-migration PostgreSQL 17 replay, task hierarchy concurrency, 58 application tests, typecheck, production build, npm audit 0 vulnerabilities. Lint is not configured.
- Live project remains ACTIVE_HEALTHY with 8 applied migrations; all eight local-only migrations remain unapplied. No production DDL, migration, index creation, RLS change, data write, restore, or PR merge occurred.
- Next safe action remains private schema/data/role export and isolated restore test, followed by migration replay and live JWT/PostgREST isolation tests. Analytics remains queued.


## 2026-11-18 — Automation pause and state reconciliation

- The latest code-bearing checkpoint passed CI #222; the subsequent documentation-only checkpoint passed CI #223 on current PR head `a97c180578d1712c9023a970b4eff091c6dbb0b0`.
- Progress & Streaks V1 is now explicitly labeled implementation-complete with live schema repair pending, matching the verified `public.goals` schema.
- This earlier pause note was superseded on 2026-11-19: the live automation record reports the Personal-OS Builder as enabled, and it continues safe repository-side work.

## 2026-11-19 — Goals RLS policy deduplication (branch-only)

- Read-only inspection confirmed `public.goals` has five authenticated policies: the core `goals_owner` policy for ALL commands plus four Progress V1 command-specific policies. The four duplicates use direct `auth.uid()`; the canonical policy uses `(select auth.uid())`.
- Added `20261119000100_deduplicate_goals_owner_policies.sql` to remove only the four redundant command-specific policies and retain the existing owner-scoped ALL policy.
- Added migration replay assertions for the retained canonical policy and absence of the four duplicate policies.
- Updated `supabase/migrations/README.md` and `PROJECT_STATE.md`.
- Latest docs commit: `e1c9986e3976d7422da12831bd163625bce4b3bd`. The new migration and assertion are committed on `feature/organization-v1`.
- CI status for this new head has not yet been verified. Do not claim tests pass until the workflow reports success.
- No live production DDL, policy changes, migration application, data writes, backup/restore, or PR merge occurred.
- Next: verify CI replay; then address the remaining RLS initialization warnings by reviewing each policy's exact authorization semantics before preparing any further migration. Do not drop unused indexes based only on zero-row usage statistics.

## 2026-11-19 — Reminder/progress RLS initialization-plan optimization

- Read-only inspection of `pg_policies` mapped the 14 advisor warnings to four duplicate goals policies, four reminder policies, two notification policies, and four progress-entry policies.
- Added `20261119000100_deduplicate_goals_owner_policies.sql`: removes four duplicate goals policies while retaining the core `goals_owner` authenticated ALL policy.
- Added `20261119000200_optimize_reminder_progress_rls.sql`: recreates the ten reminder/notification/progress policies using scalar `(select auth.uid())`, retaining command scopes and relationship ownership checks.
- Expanded `supabase/tests/organization-migration-assertions.sql` to assert goals policy deduplication and all ten initplan-safe policies.
- Updated `supabase/migrations/README.md` and `PROJECT_STATE.md`.
- The migrations are branch-only. No production policy change or migration application occurred.
- CI for the latest branch head is still unverified. Confirm the full migration replay before treating these changes as complete.
- Next: inspect CI, then re-run live advisors only after a backup-approved rollout. Do not delete unused indexes solely because current tables have zero rows.

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

**Next action:** owner-controlled complete schema/data/roles backup and successful isolated restore, then checklist conflict review and authenticated two-user PostgREST CRUD/isolation testing. CI #302 and #303 are already successful; do not repeat them. Keep production read-only and Analytics queued.
