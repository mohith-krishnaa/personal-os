-- rls_auto_enable is an event-trigger function, not a client RPC.
-- Keep privileged database execution while preventing public client roles
-- from invoking the SECURITY DEFINER function through PostgREST.
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon, authenticated;
