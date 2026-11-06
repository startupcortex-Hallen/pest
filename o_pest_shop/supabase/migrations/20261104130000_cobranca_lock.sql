-- Lock transacional para criação de cobrança no gateway.
-- O Edge Function `pagamentos` adquire este lock por (usuário, pedidos, método)
-- antes de consultar/criar a cobrança e libera no finally. Duas chamadas
-- simultâneas do mesmo checkout passam a ser serializadas, impedindo que o
-- cliente receba duas cobranças no PagBank.

begin;

create or replace function public.adquirir_lock_cobranca(p_chave text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select pg_try_advisory_lock(hashtextextended(coalesce(p_chave, ''), 0));
$$;

create or replace function public.liberar_lock_cobranca(p_chave text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select pg_advisory_unlock(hashtextextended(coalesce(p_chave, ''), 0));
$$;

revoke all on function public.adquirir_lock_cobranca(text) from public, anon, authenticated;
revoke all on function public.liberar_lock_cobranca(text) from public, anon, authenticated;
grant execute on function public.adquirir_lock_cobranca(text) to service_role;
grant execute on function public.liberar_lock_cobranca(text) to service_role;

notify pgrst, 'reload schema';

commit;
