-- Frete por distância + peso, no estilo das grandes transportadoras:
--   * faixa de distância define a base (tabela frete_faixas);
--   * primeiro 1 kg incluso e cada kg extra tem valor configurável;
--   * distância fora das faixas cadastradas NÃO cai mais na taxa fixa;
--   * o checkout recalcula peso e distância no servidor.
--
-- Observação: é uma tabela de referência (distância + peso). A cotação
-- oficial dos Correios exige contrato e credenciais da API dos Correios;
-- quando o cliente tiver o contrato, basta trocar a fonte da tabela.

begin;

alter table public.unidades
  add column if not exists frete_peso_incluso_kg numeric not null default 1.0,
  add column if not exists frete_valor_kg_extra numeric not null default 2.50;

-- Garante que lojas com faixas cadastradas usem a tabela de distância,
-- mesmo que ainda estejam marcadas como "fixo".
update public.unidades u
   set frete_modo = 'faixas'
 where u.frete_modo = 'fixo'
   and exists (
     select 1 from public.frete_faixas f
      where f.unidade_id = u.id and f.ativo = true
   );

-- Remove as versões antigas (sem peso) para não haver ambiguidade de RPC.
drop function if exists public.finalizar_checkout_v2(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision
);
drop function if exists public.calcular_frete(
  bigint, double precision, double precision, numeric, boolean
);
drop function if exists public.fn_calcular_frete_unidade(
  bigint, double precision, double precision, numeric, boolean
);

create function public.fn_calcular_frete_unidade(
  p_unidade_id bigint,
  p_lat double precision,
  p_lng double precision,
  p_subtotal numeric default 0,
  p_todos_frete_gratis boolean default false,
  p_peso_kg numeric default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_u record;
  v_dist numeric;
  v_valor numeric;
  v_eta int;
  v_gratis boolean;
  v_peso numeric;
  v_peso_extra numeric;
begin
  select *
    into v_u
    from public.unidades
   where id = p_unidade_id
     and coalesce(ativa, true) = true
     and deleted_at is null;

  if not found then
    raise exception 'Loja indisponível para entrega';
  end if;

  if p_lat is null or p_lng is null then
    raise exception 'Endereço sem localização. Informe o endereço e calcule a entrega novamente.';
  end if;

  if v_u.latitude is not null and v_u.longitude is not null then
    v_dist := public.fn_haversine_km(
      v_u.latitude::double precision,
      v_u.longitude::double precision,
      p_lat,
      p_lng
    ) * coalesce(v_u.frete_fator_rota, 1.30);
  else
    v_dist := null;
  end if;

  -- Peso mínimo de 300 g para não zerar encomendas sem peso cadastrado.
  v_peso := greatest(coalesce(p_peso_kg, 0), 0.3);
  v_peso_extra := greatest(
    ceil(v_peso - coalesce(v_u.frete_peso_incluso_kg, 1.0)),
    0
  ) * coalesce(v_u.frete_valor_kg_extra, 2.50);

  v_gratis := coalesce(p_todos_frete_gratis, false)
    or (v_u.frete_gratis_acima is not null and p_subtotal >= v_u.frete_gratis_acima);

  if v_gratis then
    v_valor := 0;
    v_peso_extra := 0;
  elsif v_u.frete_modo = 'distancia' and v_dist is not null then
    if v_u.frete_raio_max_km is not null and v_dist > v_u.frete_raio_max_km then
      return jsonb_build_object(
        'fora_area', true,
        'distancia_km', round(v_dist::numeric, 2),
        'valor', 0,
        'previsao_entrega_min', null,
        'gratis', false,
        'peso_kg', round(v_peso::numeric, 2),
        'peso_extra_kg', round(v_peso_extra::numeric, 2),
        'mensagem', 'Endereço fora do raio de entrega da loja'
      );
    end if;

    v_valor := coalesce(v_u.frete_taxa_base, 0)
      + greatest(v_dist - coalesce(v_u.frete_km_minimo, 0), 0)
        * coalesce(v_u.frete_valor_km, 0)
      + v_peso_extra;
  elsif v_u.frete_modo = 'faixas' and v_dist is not null then
    select f.valor
      into v_valor
      from public.frete_faixas f
     where f.unidade_id = p_unidade_id
       and f.ativo
       and v_dist >= f.km_inicio
       and v_dist <= f.km_fim
     order by f.km_inicio
     limit 1;

    if v_valor is null then
      -- Antes caía na taxa fixa (ex.: R$ 8,99) para qualquer distância.
      -- Agora deixa claro que a distância está fora da cobertura.
      return jsonb_build_object(
        'fora_area', true,
        'distancia_km', round(v_dist::numeric, 2),
        'valor', 0,
        'previsao_entrega_min', null,
        'gratis', false,
        'peso_kg', round(v_peso::numeric, 2),
        'peso_extra_kg', round(v_peso_extra::numeric, 2),
        'mensagem', 'Distância fora das faixas de entrega cadastradas pela loja'
      );
    end if;

    v_valor := v_valor + v_peso_extra;
  else
    v_valor := coalesce(v_u.taxa_entrega, 0);
    v_peso_extra := 0;
  end if;

  v_valor := round(greatest(coalesce(v_valor, 0), 0)::numeric, 2);
  v_eta := coalesce(v_u.prazo_entrega_min, 120)
    + ceil(coalesce(v_dist, 0) * coalesce(v_u.frete_tempo_km_min, 3))::int;

  return jsonb_build_object(
    'fora_area', false,
    'distancia_km', case when v_dist is null then null else round(v_dist::numeric, 2) end,
    'valor', v_valor,
    'previsao_entrega_min', v_eta,
    'gratis', v_gratis,
    'peso_kg', round(v_peso::numeric, 2),
    'peso_extra_kg', round(v_peso_extra::numeric, 2),
    'mensagem', null
  );
end $$;

create function public.calcular_frete(
  p_unidade_id bigint,
  p_lat double precision,
  p_lng double precision,
  p_subtotal numeric default 0,
  p_todos_frete_gratis boolean default false,
  p_peso_kg numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Faça login para calcular o frete';
  end if;

  return public.fn_calcular_frete_unidade(
    p_unidade_id, p_lat, p_lng, p_subtotal, p_todos_frete_gratis, p_peso_kg
  );
end $$;

revoke all on function public.calcular_frete(
  bigint, double precision, double precision, numeric, boolean, numeric
) from public, anon;
grant execute on function public.calcular_frete(
  bigint, double precision, double precision, numeric, boolean, numeric
) to authenticated;

create function public.finalizar_checkout_v2(
  p_user_id uuid,
  p_itens jsonb,
  p_cupom_desconto_total numeric default 0,
  p_cupom_id bigint default null,
  p_tipo_entrega text default 'retirada',
  p_endereco_entrega text default null,
  p_cep_entrega text default null,
  p_endereco_lat double precision default null,
  p_endereco_lng double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ret jsonb;
  v_linha record;
  v_item jsonb;
  v_frete jsonb;
  v_fretes jsonb := '{}'::jsonb;
  v_subtotal numeric;
  v_todos_gratis boolean;
  v_peso numeric;
  v_old_taxa numeric;
  v_new_taxa numeric;
  v_dist numeric;
  v_eta int;
  v_total numeric;
  v_cupom_unidade bigint;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;

  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;

  if p_cupom_id is not null then
    select unidade_id into v_cupom_unidade
      from public.cupons
     where id = p_cupom_id;

    if v_cupom_unidade is not null then
      if exists (
        select 1
          from jsonb_array_elements(p_itens) as t(item)
          join public.produtos p on p.id = (t.item->>'produto_id')::bigint
         where coalesce(p.unidade_id, coalesce((t.item->>'unidade_id')::bigint, 1))
               <> v_cupom_unidade
      ) then
        raise exception 'Este cupom é válido apenas para a loja selecionada';
      end if;
    end if;
  end if;

  if p_tipo_entrega = 'entrega' then
    for v_linha in
      select coalesce(p.unidade_id, coalesce((t.item->>'unidade_id')::bigint, 1)) as unidade_id,
             sum(
               coalesce(
                 case when p.em_promocao and p.preco_promocional is not null
                      then p.preco_promocional else p.preco end,
                 0
               ) * (t.item->>'quantidade')::int
             ) as subtotal,
             sum(
               coalesce(p.peso_kg, 0) * (t.item->>'quantidade')::int
             ) as peso_kg,
             bool_and(coalesce(p.frete_gratis, false)) as todos_gratis
        from jsonb_array_elements(p_itens) as t(item)
        join public.produtos p on p.id = (t.item->>'produto_id')::bigint
       group by 1
    loop
      if p_endereco_lat is null or p_endereco_lng is null then
        if exists (
          select 1 from public.unidades u
           where u.id = v_linha.unidade_id
             and u.frete_modo in ('distancia', 'faixas')
        ) then
          raise exception 'Calcule a entrega pelo endereço antes de finalizar o pedido';
        end if;
        v_frete := jsonb_build_object(
          'fora_area', false, 'distancia_km', null, 'valor', null
        );
      else
        v_frete := public.fn_calcular_frete_unidade(
          v_linha.unidade_id,
          p_endereco_lat,
          p_endereco_lng,
          coalesce(v_linha.subtotal, 0),
          coalesce(v_linha.todos_gratis, false),
          coalesce(v_linha.peso_kg, 0)
        );
      end if;

      if coalesce((v_frete->>'fora_area')::boolean, false) then
        raise exception 'Uma das lojas não entrega neste endereço. %',
          coalesce(v_frete->>'mensagem', '');
      end if;

      v_fretes := jsonb_set(v_fretes, array[v_linha.unidade_id::text], v_frete, true);
    end loop;
  end if;

  v_ret := public.finalizar_checkout(
    p_user_id,
    p_itens,
    p_cupom_desconto_total,
    p_cupom_id,
    p_tipo_entrega,
    p_endereco_entrega,
    p_cep_entrega
  );

  for v_linha in
    select value as item, ordinality as ord
      from jsonb_array_elements(v_ret) with ordinality
  loop
    v_item := v_linha.item;
    v_old_taxa := coalesce((v_item->>'taxa_entrega')::numeric, 0);
    v_new_taxa := v_old_taxa;
    v_dist := null;
    v_eta := null;

    if p_tipo_entrega = 'entrega' then
      v_frete := v_fretes -> (v_item->>'unidade_id');
      if v_frete is not null and (v_frete->>'valor') is not null then
        v_new_taxa := coalesce((v_frete->>'valor')::numeric, v_old_taxa);
        v_dist := (v_frete->>'distancia_km')::numeric;
        v_eta := (v_frete->>'previsao_entrega_min')::int;
      end if;
    end if;

    update public.pedidos
       set taxa_entrega = v_new_taxa,
           distancia_km = v_dist,
           previsao_entrega_min = v_eta,
           frete_detalhe = case when v_frete is null then null else v_frete end,
           total = greatest(coalesce(total, 0) - v_old_taxa + v_new_taxa, 0)
     where id = (v_item->>'id')::bigint;

    v_total := greatest(
      coalesce((v_item->>'total')::numeric, 0) - v_old_taxa + v_new_taxa,
      0
    );

    v_item := jsonb_set(v_item, '{taxa_entrega}', to_jsonb(v_new_taxa));
    v_item := jsonb_set(v_item, '{total}', to_jsonb(v_total));
    if v_dist is not null then
      v_item := jsonb_set(v_item, '{distancia_km}', to_jsonb(v_dist));
    end if;
    if v_eta is not null then
      v_item := jsonb_set(v_item, '{previsao_entrega_min}', to_jsonb(v_eta));
    end if;

    v_ret := jsonb_set(v_ret, array[(v_linha.ord - 1)::text], v_item, true);
  end loop;

  return v_ret;
end $$;

revoke all on function public.finalizar_checkout_v2(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision
) from public, anon;
grant execute on function public.finalizar_checkout_v2(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision
) to authenticated;

commit;
