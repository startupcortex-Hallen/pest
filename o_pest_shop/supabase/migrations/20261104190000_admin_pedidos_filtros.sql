-- Lista e contadores de pedidos 100% no servidor (filtros e paginação).
-- A UI não precisa mais baixar 50 pedidos e filtrar no cliente.

begin;

create or replace function public.admin_listar_pedidos_v2(
  p_busca text default null,
  p_statuses text[] default null,
  p_unidade_id bigint default null,
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade bigint;
  v_limit int := greatest(least(coalesce(p_limit, 50), 200), 1);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_busca text := nullif(trim(coalesce(p_busca, '')), '');
begin
  if v_funcao not in ('admin', 'atendente', 'gestor') then
    raise exception 'Sem permissão para listar pedidos';
  end if;

  if v_funcao in ('atendente', 'gestor') then
    v_unidade := public.unidade_usuario();
    if v_unidade is null then
      raise exception 'Usuário sem loja vinculada';
    end if;
  end if;

  return coalesce((
    select jsonb_agg(t.obj order by t.created_at desc)
    from (
      select
        o.created_at,
        to_jsonb(o) || jsonb_build_object(
          'pedido_itens', coalesce((
            select jsonb_agg(
              to_jsonb(i) || jsonb_build_object(
                'produtos', jsonb_build_object('nome', pr.nome, 'url_imagem', pr.url_imagem)
              )
              order by i.id
            )
            from public.pedido_itens i
            left join public.produtos pr on pr.id = i.produto_id
            where i.pedido_id = o.id
          ), '[]'::jsonb),
          'perfis', (
            select jsonb_build_object('nome', pf.nome, 'email', pf.email, 'telefone', pf.telefone)
            from public.perfis pf
            where pf.id = o.user_id
          ),
          'unidades', (
            select jsonb_build_object('nome', u.nome)
            from public.unidades u
            where u.id = o.unidade_id
          ),
          'pagamentos', (
            select to_jsonb(pg)
            from public.pagamentos pg
            where pg.id = o.pagamento_id
          )
        ) as obj
      from public.pedidos o
      where (p_statuses is null or cardinality(p_statuses) = 0 or o.status = any(p_statuses))
        and (p_unidade_id is null or o.unidade_id = p_unidade_id)
        and (v_funcao = 'admin' or o.unidade_id = v_unidade)
        and (
          v_busca is null
          or o.id::text = v_busca
          or coalesce(o.comprador_nome, '') ilike '%' || v_busca || '%'
          or coalesce(o.comprador_email, '') ilike '%' || v_busca || '%'
          or exists (
            select 1 from public.perfis pf
            where pf.id = o.user_id
              and (
                coalesce(pf.nome, '') ilike '%' || v_busca || '%'
                or coalesce(pf.email, '') ilike '%' || v_busca || '%'
              )
          )
        )
      order by o.created_at desc
      limit v_limit offset v_offset
    ) t
  ), '[]'::jsonb);
end $$;

create or replace function public.admin_contar_pedidos(
  p_unidade_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade bigint;
begin
  if v_funcao not in ('admin', 'atendente', 'gestor') then
    raise exception 'Sem permissão para contar pedidos';
  end if;

  if v_funcao in ('atendente', 'gestor') then
    v_unidade := public.unidade_usuario();
    if v_unidade is null then
      raise exception 'Usuário sem loja vinculada';
    end if;
  end if;

  return (
    select jsonb_build_object(
      'total', count(*),
      'aguardando_pagamento', count(*) filter (where status = 'pendente'),
      'em_andamento', count(*) filter (
        where status in (
          'pago', 'em_preparo', 'pronto_para_entrega',
          'postado', 'em_transito', 'saiu_para_entrega'
        )
      ),
      'entregues', count(*) filter (where status = 'entregue'),
      'cancelados', count(*) filter (where status = 'cancelado')
    )
    from public.pedidos o
    where (p_unidade_id is null or o.unidade_id = p_unidade_id)
      and (v_funcao = 'admin' or o.unidade_id = v_unidade)
  );
end $$;

revoke all on function public.admin_listar_pedidos_v2(text, text[], bigint, int, int)
  from public, anon;
grant execute on function public.admin_listar_pedidos_v2(text, text[], bigint, int, int)
  to authenticated;

revoke all on function public.admin_contar_pedidos(bigint) from public, anon;
grant execute on function public.admin_contar_pedidos(bigint) to authenticated;

notify pgrst, 'reload schema';

commit;
