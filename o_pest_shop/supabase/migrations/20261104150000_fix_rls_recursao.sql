-- Corrige recursão infinita de RLS em `perfis`.
-- As policies não podem consultar `perfis`/`pedidos` diretamente; usamos
-- funções SECURITY DEFINER que rodam como dono e não reavaliam RLS.

begin;

create or replace function public.unidade_usuario()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select unidade_id from public.perfis where id = auth.uid();
$$;

create or replace function public.entregador_ve_cliente(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.pedidos
     where entregador_id = auth.uid()
       and user_id = p_user_id
  );
$$;

revoke all on function public.unidade_usuario() from public, anon;
revoke all on function public.entregador_ve_cliente(uuid) from public, anon;
grant execute on function public.unidade_usuario() to authenticated;
grant execute on function public.entregador_ve_cliente(uuid) to authenticated;

-- PERFIS: admin vê tudo; equipe vê a própria loja; entregador vê a si e aos
-- clientes dos pedidos atribuídos a ele.
drop policy if exists "perfis_select_equipe" on public.perfis;
create policy "perfis_select_equipe" on public.perfis
  for select to authenticated
  using (
    id = auth.uid()
    or public.funcao_usuario() = 'admin'
    or (
      public.funcao_usuario() in ('atendente', 'gestor')
      and unidade_id = public.unidade_usuario()
    )
    or (
      public.funcao_usuario() = 'entregador'
      and (
        id = auth.uid()
        or public.entregador_ve_cliente(id)
      )
    )
  );

-- PEDIDOS
drop policy if exists "pedidos_select" on public.pedidos;
create policy "pedidos_select" on public.pedidos
  for select to authenticated
  using (
    user_id = auth.uid()
    or entregador_id = auth.uid()
    or public.funcao_usuario() = 'admin'
    or (
      public.funcao_usuario() in ('atendente', 'gestor')
      and unidade_id = public.unidade_usuario()
    )
  );

-- ENVIOS
drop policy if exists "envios_select" on public.envios;
create policy "envios_select" on public.envios
  for select to authenticated
  using (
    public.funcao_usuario() = 'admin'
    or exists (
      select 1 from public.pedidos o
       where o.id = envios.pedido_id
         and (
           o.user_id = auth.uid()
           or o.entregador_id = auth.uid()
           or (
             public.funcao_usuario() in ('atendente', 'gestor')
             and o.unidade_id = public.unidade_usuario()
           )
         )
    )
  );

-- EVENTOS DE ENVIO
drop policy if exists "envio_eventos_select" on public.envio_eventos;
create policy "envio_eventos_select" on public.envio_eventos
  for select to authenticated
  using (
    exists (
      select 1 from public.envios e
      join public.pedidos o on o.id = e.pedido_id
       where e.id = envio_eventos.envio_id
         and (
           public.funcao_usuario() = 'admin'
           or o.user_id = auth.uid()
           or o.entregador_id = auth.uid()
           or (
             public.funcao_usuario() in ('atendente', 'gestor')
             and o.unidade_id = public.unidade_usuario()
           )
         )
    )
  );

-- PAGAMENTOS
drop policy if exists "pagamentos_select" on public.pagamentos;
create policy "pagamentos_select" on public.pagamentos
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.funcao_usuario() = 'admin'
    or (
      public.funcao_usuario() in ('atendente', 'gestor')
      and exists (
        select 1 from public.pedidos o
         where o.pagamento_id = pagamentos.id
           and o.unidade_id = public.unidade_usuario()
      )
    )
  );

notify pgrst, 'reload schema';

commit;
