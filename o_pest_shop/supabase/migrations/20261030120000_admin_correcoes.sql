-- Correções do painel admin:
--   1. Admin pode criar/editar/excluir assinaturas de qualquer usuário.
--   2. Gestor de loja consegue ler os perfis dos clientes/entregadores.
--   3. Exclusão de usuário remove o login (auth.users), não só o perfil,
--      bloqueando quando há pedidos ou quando é o último admin.

begin;

-- 1) ASSINATURAS ------------------------------------------------
do $$
begin
  if to_regclass('public.assinaturas') is not null then
    execute 'drop policy if exists "assinaturas_admin_all" on public.assinaturas';
    execute $sql$
      create policy "assinaturas_admin_all" on public.assinaturas
        for all to authenticated
        using (public.funcao_usuario() = 'admin')
        with check (public.funcao_usuario() = 'admin')
    $sql$;
  end if;
end $$;

-- 2) LEITURA DE PERFIS PELA EQUIPE -------------------------------
-- Inclui gestor, que antes não conseguia ver nome/telefone nos pedidos
-- nem listar entregadores no painel da loja.
do $$
begin
  if to_regclass('public.perfis') is not null then
    execute 'drop policy if exists "perfis_select_equipe" on public.perfis';
    execute $sql$
      create policy "perfis_select_equipe" on public.perfis
        for select to authenticated
        using (public.funcao_usuario() in ('admin','atendente','entregador','gestor'))
    $sql$;
  end if;
end $$;

-- 3) EXCLUSÃO DE USUÁRIO PELO ADMIN ------------------------------
-- Remove o auth.users (o perfil cai em cascata). Nunca apaga pedidos:
-- bloqueia a exclusão se o usuário tiver histórico de compras.
create or replace function public.admin_excluir_usuario(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text;
  v_admins int;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  select funcao into v_funcao from public.perfis where id = auth.uid();
  if coalesce(v_funcao, '') <> 'admin' then
    raise exception 'Sem permissão para excluir usuários';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Você não pode excluir a própria conta';
  end if;

  if exists (select 1 from public.pedidos where user_id = p_user_id limit 1) then
    raise exception 'Usuário possui pedidos e não pode ser excluído';
  end if;

  if exists (select 1 from public.perfis where id = p_user_id and funcao = 'admin') then
    select count(*) into v_admins from public.perfis where funcao = 'admin';
    if v_admins <= 1 then
      raise exception 'Não é possível excluir o último admin';
    end if;
  end if;

  -- Preserva pedidos antigos em que o usuário era entregador.
  update public.pedidos set entregador_id = null where entregador_id = p_user_id;

  delete from auth.users where id = p_user_id;
end;
$$;

revoke all on function public.admin_excluir_usuario(uuid) from public, anon;
grant execute on function public.admin_excluir_usuario(uuid) to authenticated;

commit;
