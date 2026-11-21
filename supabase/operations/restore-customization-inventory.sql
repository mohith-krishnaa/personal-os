-- Read-only inventory for a Supabase logical backup/isolated restore.
-- This query does not read secret values, change schema, write rows, or call APIs.
-- Save the JSON result privately and hash it; never commit source identifiers or row-level data.
WITH managed_data_counts AS (
  SELECT 'auth.users' AS table_name, count(*)::bigint AS row_count FROM auth.users
  UNION ALL SELECT 'auth.instances', count(*)::bigint FROM auth.instances
  UNION ALL SELECT 'auth.identities', count(*)::bigint FROM auth.identities
  UNION ALL SELECT 'auth.refresh_tokens', count(*)::bigint FROM auth.refresh_tokens
  UNION ALL SELECT 'auth.sessions', count(*)::bigint FROM auth.sessions
  UNION ALL SELECT 'auth.audit_log_entries', count(*)::bigint FROM auth.audit_log_entries
  UNION ALL SELECT 'auth.mfa_factors', count(*)::bigint FROM auth.mfa_factors
  UNION ALL SELECT 'auth.mfa_challenges', count(*)::bigint FROM auth.mfa_challenges
  UNION ALL SELECT 'auth.mfa_amr_claims', count(*)::bigint FROM auth.mfa_amr_claims
  UNION ALL SELECT 'auth.sso_providers', count(*)::bigint FROM auth.sso_providers
  UNION ALL SELECT 'auth.sso_domains', count(*)::bigint FROM auth.sso_domains
  UNION ALL SELECT 'auth.saml_providers', count(*)::bigint FROM auth.saml_providers
  UNION ALL SELECT 'auth.saml_relay_states', count(*)::bigint FROM auth.saml_relay_states
  UNION ALL SELECT 'auth.flow_state', count(*)::bigint FROM auth.flow_state
  UNION ALL SELECT 'auth.one_time_tokens', count(*)::bigint FROM auth.one_time_tokens
  UNION ALL SELECT 'auth.oauth_clients', count(*)::bigint FROM auth.oauth_clients
  UNION ALL SELECT 'auth.oauth_authorizations', count(*)::bigint FROM auth.oauth_authorizations
  UNION ALL SELECT 'auth.oauth_consents', count(*)::bigint FROM auth.oauth_consents
  UNION ALL SELECT 'auth.oauth_client_states', count(*)::bigint FROM auth.oauth_client_states
  UNION ALL SELECT 'auth.custom_oauth_providers', count(*)::bigint FROM auth.custom_oauth_providers
  UNION ALL SELECT 'auth.webauthn_credentials', count(*)::bigint FROM auth.webauthn_credentials
  UNION ALL SELECT 'auth.webauthn_challenges', count(*)::bigint FROM auth.webauthn_challenges
  UNION ALL SELECT 'auth.scim_users', count(*)::bigint FROM auth.scim_users
  UNION ALL SELECT 'auth.scim_tokens', count(*)::bigint FROM auth.scim_tokens
  UNION ALL SELECT 'auth.mfa_recovery_code_sets', count(*)::bigint FROM auth.mfa_recovery_code_sets
  UNION ALL SELECT 'auth.mfa_recovery_codes', count(*)::bigint FROM auth.mfa_recovery_codes
  UNION ALL SELECT 'storage.buckets', count(*)::bigint FROM storage.buckets
  UNION ALL SELECT 'storage.objects', count(*)::bigint FROM storage.objects
  UNION ALL SELECT 'storage.s3_multipart_uploads', count(*)::bigint FROM storage.s3_multipart_uploads
  UNION ALL SELECT 'storage.s3_multipart_uploads_parts', count(*)::bigint FROM storage.s3_multipart_uploads_parts
  UNION ALL SELECT 'storage.buckets_analytics', count(*)::bigint FROM storage.buckets_analytics
  UNION ALL SELECT 'storage.buckets_vectors', count(*)::bigint FROM storage.buckets_vectors
  UNION ALL SELECT 'storage.vector_indexes', count(*)::bigint FROM storage.vector_indexes
  UNION ALL SELECT 'vault.secrets', count(*)::bigint FROM vault.secrets
  UNION ALL SELECT 'realtime.messages', count(*)::bigint FROM realtime.messages
  UNION ALL SELECT 'realtime.subscription', count(*)::bigint FROM realtime.subscription
),
public_app_counts AS (
  SELECT 'public.profiles' AS table_name, count(*)::bigint AS row_count FROM public.profiles
  UNION ALL SELECT 'public.goals', count(*)::bigint FROM public.goals
  UNION ALL SELECT 'public.projects', count(*)::bigint FROM public.projects
  UNION ALL SELECT 'public.tasks', count(*)::bigint FROM public.tasks
  UNION ALL SELECT 'public.notes', count(*)::bigint FROM public.notes
  UNION ALL SELECT 'public.activity_events', count(*)::bigint FROM public.activity_events
  UNION ALL SELECT 'public.reminders', count(*)::bigint FROM public.reminders
  UNION ALL SELECT 'public.notifications', count(*)::bigint FROM public.notifications
  UNION ALL SELECT 'public.progress_entries', count(*)::bigint FROM public.progress_entries
),
provider_ledgers AS (
  SELECT 'auth.schema_migrations' AS table_name, count(*)::bigint AS row_count FROM auth.schema_migrations
  UNION ALL SELECT 'storage.migrations', count(*)::bigint FROM storage.migrations
  UNION ALL SELECT 'realtime.schema_migrations', count(*)::bigint FROM realtime.schema_migrations
  UNION ALL SELECT 'supabase_migrations.schema_migrations', count(*)::bigint FROM supabase_migrations.schema_migrations
),
installed_extensions AS (
  SELECT e.extname, e.extversion, n.nspname AS schema_name
  FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
  WHERE e.extname <> 'plpgsql'
),
nonplatform_schemas AS (
  SELECT n.nspname AS schema_name
  FROM pg_namespace n
  WHERE n.nspname NOT LIKE 'pg_%'
    AND n.nspname NOT IN (
      'information_schema','public','auth','storage','extensions','vault','realtime',
      'graphql','graphql_public','supabase_functions','supabase_migrations','net',
      'cron','pgbouncer'
    )
),
public_functions AS (
  SELECT n.nspname AS schema_name, p.proname AS function_name,
         pg_get_function_identity_arguments(p.oid) AS arguments,
         pg_get_userbyid(p.proowner) AS owner, p.prosecdef AS security_definer,
         p.proconfig AS settings, p.proacl::text AS acl
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prokind IN ('f','p')
),
noninternal_triggers AS (
  SELECT n.nspname AS schema_name, c.relname AS table_name, t.tgname AS trigger_name,
         pn.nspname AS function_schema, p.proname AS function_name,
         pg_get_userbyid(p.proowner) AS function_owner, p.prosecdef AS security_definer,
         p.proconfig AS function_settings, pg_get_triggerdef(t.oid) AS definition
  FROM pg_trigger t
  JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_proc p ON p.oid=t.tgfoid
  JOIN pg_namespace pn ON pn.oid=p.pronamespace
  WHERE NOT t.tgisinternal AND n.nspname IN ('public','auth','storage','realtime')
),
managed_policies AS (
  SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  FROM pg_policies WHERE schemaname IN ('auth','storage','realtime')
),
event_triggers AS (
  SELECT e.evtname, e.evtevent, e.evtenabled,
         pg_get_userbyid(e.evtowner) AS owner, n.nspname AS function_schema,
         p.proname AS function_name, p.prosecdef AS security_definer, p.proconfig AS function_settings
  FROM pg_event_trigger e JOIN pg_proc p ON p.oid=e.evtfoid
  JOIN pg_namespace n ON n.oid=p.pronamespace
),
default_privileges AS (
  SELECT pg_get_userbyid(d.defaclrole) AS owner,
         COALESCE(n.nspname,'<global>') AS schema_name,
         d.defaclobjtype AS object_type, d.defaclacl::text AS acl
  FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
),
role_settings AS (
  SELECT COALESCE(r.rolname,'<all roles>') AS role_name,
         COALESCE(db.datname,'<all databases>') AS database_name,
         setting
  FROM pg_db_role_setting s
  LEFT JOIN pg_roles r ON r.oid=s.setrole
  LEFT JOIN pg_database db ON db.oid=s.setdatabase
  CROSS JOIN LATERAL unnest(s.setconfig) AS setting
  WHERE setting ~ '^(search_path|statement_timeout|idle_in_transaction_session_timeout|row_security|timezone|log_min_duration_statement)='
),
database_settings AS (
  SELECT name, setting, source
  FROM pg_settings
  WHERE source NOT IN ('default','override')
    AND name IN ('search_path','statement_timeout','idle_in_transaction_session_timeout','row_security','timezone','log_min_duration_statement')
),
publications AS (
  SELECT p.pubname,p.puballtables,p.pubinsert,p.pubupdate,p.pubdelete,p.pubtruncate,
         COALESCE((SELECT jsonb_agg(format('%I.%I', t.schemaname, t.tablename) ORDER BY t.schemaname,t.tablename)
                   FROM pg_publication_tables t WHERE t.pubname=p.pubname),'[]'::jsonb) AS tables
  FROM pg_publication p
),
login_roles AS (
  SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls
  FROM pg_roles WHERE rolcanlogin ORDER BY rolname
),
role_memberships AS (
  SELECT parent.rolname AS granted_role, member.rolname AS member_role,
         grantor.rolname AS grantor_role, m.admin_option, m.inherit_option, m.set_option
  FROM pg_auth_members m
  JOIN pg_roles parent ON parent.oid=m.roleid
  JOIN pg_roles member ON member.oid=m.member
  JOIN pg_roles grantor ON grantor.oid=m.grantor
),
foreign_servers AS (
  SELECT s.srvname, w.fdwname, pg_get_userbyid(s.srvowner) AS owner
  FROM pg_foreign_server s JOIN pg_foreign_data_wrapper w ON w.oid=s.srvfdw
)
SELECT jsonb_build_object(
  'inspected_at', now(),
  'database_name', current_database(),
  'postgres_version', current_setting('server_version'),
  'nonplatform_schemas',(SELECT COALESCE(jsonb_agg(schema_name ORDER BY schema_name),'[]'::jsonb) FROM nonplatform_schemas),
  'installed_extensions',(SELECT COALESCE(jsonb_agg(to_jsonb(installed_extensions) ORDER BY extname),'[]'::jsonb) FROM installed_extensions),
  'public_application_row_counts',(SELECT COALESCE(jsonb_agg(to_jsonb(public_app_counts) ORDER BY table_name),'[]'::jsonb) FROM public_app_counts),
  'managed_schema_data_row_counts',(SELECT COALESCE(jsonb_agg(to_jsonb(managed_data_counts) ORDER BY table_name),'[]'::jsonb) FROM managed_data_counts),
  'provider_migration_ledgers',(SELECT COALESCE(jsonb_agg(to_jsonb(provider_ledgers) ORDER BY table_name),'[]'::jsonb) FROM provider_ledgers),
  'public_functions',(SELECT COALESCE(jsonb_agg(to_jsonb(public_functions) ORDER BY function_name,arguments),'[]'::jsonb) FROM public_functions),
  'noninternal_triggers',(SELECT COALESCE(jsonb_agg(to_jsonb(noninternal_triggers) ORDER BY schema_name,table_name,trigger_name),'[]'::jsonb) FROM noninternal_triggers),
  'managed_schema_policies',(SELECT COALESCE(jsonb_agg(to_jsonb(managed_policies) ORDER BY schemaname,tablename,policyname),'[]'::jsonb) FROM managed_policies),
  'event_triggers',(SELECT COALESCE(jsonb_agg(to_jsonb(event_triggers) ORDER BY evtname),'[]'::jsonb) FROM event_triggers),
  'default_privileges',(SELECT COALESCE(jsonb_agg(to_jsonb(default_privileges) ORDER BY owner,schema_name,object_type),'[]'::jsonb) FROM default_privileges),
  'role_settings',(SELECT COALESCE(jsonb_agg(to_jsonb(role_settings) ORDER BY role_name,database_name,setting),'[]'::jsonb) FROM role_settings),
  'database_settings',(SELECT COALESCE(jsonb_agg(to_jsonb(database_settings) ORDER BY name),'[]'::jsonb) FROM database_settings),
  'publications',(SELECT COALESCE(jsonb_agg(to_jsonb(publications) ORDER BY pubname),'[]'::jsonb) FROM publications),
  'login_roles',(SELECT COALESCE(jsonb_agg(to_jsonb(login_roles) ORDER BY rolname),'[]'::jsonb) FROM login_roles),
  'role_memberships',(SELECT COALESCE(jsonb_agg(to_jsonb(role_memberships) ORDER BY granted_role,member_role),'[]'::jsonb) FROM role_memberships),
  'foreign_servers',(SELECT COALESCE(jsonb_agg(to_jsonb(foreign_servers) ORDER BY srvname),'[]'::jsonb) FROM foreign_servers),
  'pg_cron_installed',(SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron')),
  'pg_net_installed',(SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_net')),
  'wrappers_installed',(SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='wrappers'))
) AS restore_inventory;
