-- Ajustes finais de produção: storage de avatares e fechamento das RPCs
-- antigas de checkout (somente o v6, validado no servidor, fica exposto).

begin;

-- ── 1) AVATAR: bucket público + caminho por usuário ────────────────────
-- O app passa a enviar em `${uid}/arquivo.jpg`. O bucket público resolve a
-- URL pública usada pelos widgets; a policy continua exigindo a pasta do uid.

insert into storage.buckets (id, name, public)
values ('fotos_perfil', 'fotos_perfil', true)
on conflict (id) do update set public = true;

drop policy if exists "fotos_perfil_proprio_write" on storage.objects;
create policy "fotos_perfil_proprio_write" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'fotos_perfil'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "fotos_perfil_proprio_update" on storage.objects;
create policy "fotos_perfil_proprio_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'fotos_perfil'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'fotos_perfil'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "fotos_perfil_proprio_delete" on storage.objects;
create policy "fotos_perfil_proprio_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'fotos_perfil'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "Curriculos_proprio_insert" on storage.objects;
create policy "Curriculos_proprio_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'Curriculos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "Curriculos_proprio_select" on storage.objects;
create policy "Curriculos_proprio_select" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'Curriculos'
    and (
      auth.uid()::text = (storage.foldername(name))[1]
      or public.funcao_usuario() = 'admin'
    )
  );

-- ── 2) CONTA BLOQUEADA NÃO CRIA PEDIDO ─────────────────────────────────

create or replace function public.fn_bloqueia_pedido_conta_bloqueada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  select status_conta into v_status from public.perfis where id = new.user_id;
  if coalesce(v_status, 'ativo') <> 'ativo' then
    raise exception 'Sua conta está bloqueada. Fale com o suporte.';
  end if;
  return new;
end $$;

drop trigger if exists trg_bloqueia_pedido_conta_bloqueada on public.pedidos;
create trigger trg_bloqueia_pedido_conta_bloqueada
  before insert on public.pedidos
  for each row execute function public.fn_bloqueia_pedido_conta_bloqueada();

-- ── 3) SOMENTE O CHECKOUT V6 FICA EXPOSTO ──────────────────────────────
-- v2/v3/v4/v5 e o checkout base continuam existindo para chamadas internas
-- (security definer), mas não podem ser invocados direto pelo app/API.

revoke all on function public.finalizar_checkout_v5(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb
) from public, anon, authenticated;

revoke all on function public.finalizar_checkout_v4(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb, uuid
) from public, anon, authenticated;

revoke all on function public.finalizar_checkout_v3(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb
) from public, anon, authenticated;

revoke all on function public.finalizar_checkout_v2(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision
) from public, anon, authenticated;

revoke all on function public.finalizar_checkout(
  uuid, jsonb, numeric, bigint, text, text, text
) from public, anon, authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'finalizar_checkout_v6'
  ) then
    grant execute on function public.finalizar_checkout_v6(
      uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
      jsonb, uuid, jsonb, text, text, jsonb, bigint
    ) to authenticated;
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
