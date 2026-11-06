-- Frete por transportadora (Correios e Melhor Envio).
--
-- A cotação real é feita pela Edge Function `frete-cotacao`, que grava o
-- resultado em `frete_cotacoes`. O checkout usa o ID da cotação para aplicar
-- o valor validado no servidor, sem confiar em valor enviado pelo app.
--
-- Secrets esperados nas Edge Functions:
--   CORREIOS_API_URL, CORREIOS_EMPRESA, CORREIOS_SENHA, CORREIOS_SERVICOS
--   MELHOR_ENVIO_TOKEN, MELHOR_ENVIO_ENV (production|sandbox)

begin;

alter table public.unidades drop constraint if exists unidades_frete_modo_check;
alter table public.unidades
  add constraint unidades_frete_modo_check
  check (frete_modo in ('fixo', 'distancia', 'faixas', 'correios', 'melhor_envio'))
  not valid;

create table if not exists public.frete_cotacoes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  unidade_id bigint not null references public.unidades(id) on delete cascade,
  provider text not null check (provider in ('correios', 'melhor_envio')),
  servico text,
  transportadora text,
  valor numeric not null check (valor >= 0),
  prazo_dias int,
  peso_kg numeric,
  cep_origem text,
  cep_destino text,
  payload jsonb,
  expira_em timestamptz not null default now() + interval '30 minutes',
  usado_em timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_frete_cotacoes_user
  on public.frete_cotacoes(user_id, expira_em);

alter table public.frete_cotacoes enable row level security;

drop policy if exists "frete_cotacoes_select_own" on public.frete_cotacoes;
create policy "frete_cotacoes_select_own" on public.frete_cotacoes
  for select to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() = 'admin');

revoke all on public.frete_cotacoes from anon, authenticated;
grant select on public.frete_cotacoes to authenticated;
grant all on public.frete_cotacoes to service_role;

-- Checkout v3: igual ao v2, mas aceita cotações externas validadas.
drop function if exists public.finalizar_checkout_v3(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb
);

create function public.finalizar_checkout_v3(
  p_user_id uuid,
  p_itens jsonb,
  p_cupom_desconto_total numeric default 0,
  p_cupom_id bigint default null,
  p_tipo_entrega text default 'retirada',
  p_endereco_entrega text default null,
  p_cep_entrega text default null,
  p_endereco_lat double precision default null,
  p_endereco_lng double precision default null,
  p_cotacoes jsonb default '[]'::jsonb
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
  v_cotacoes jsonb := '{}'::jsonb;
  v_cot record;
  v_quote record;
  v_cotacao_id uuid;
  v_unidade_cot bigint;
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

  -- Valida e congela as cotações externas (Correios/Melhor Envio).
  for v_cot in
    select value
      from jsonb_array_elements(coalesce(p_cotacoes, '[]'::jsonb))
  loop
    begin
      v_cotacao_id := (v_cot.value->>'cotacao_id')::uuid;
      v_unidade_cot := (v_cot.value->>'unidade_id')::bigint;
    exception when others then
      raise exception 'Cotação de frete inválida';
    end;

    select *
      into v_quote
      from public.frete_cotacoes
     where id = v_cotacao_id
       and user_id = p_user_id
       and unidade_id = v_unidade_cot
       and usado_em is null
       and expira_em > now()
       for update;

    if not found then
      raise exception 'Cotação de frete expirada. Calcule a entrega novamente.';
    end if;

    v_cotacoes := jsonb_set(
      v_cotacoes,
      array[v_unidade_cot::text],
      jsonb_build_object(
        'fora_area', false,
        'distancia_km', null,
        'valor', v_quote.valor,
        'previsao_entrega_min', coalesce(v_quote.prazo_dias, 0) * 1440,
        'gratis', v_quote.valor = 0,
        'provider', v_quote.provider,
        'servico', v_quote.servico,
        'transportadora', v_quote.transportadora,
        'cotacao_id', v_quote.id
      ),
      true
    );
  end loop;

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
      v_frete := null;

      if (v_cotacoes ? (v_linha.unidade_id::text)) then
        v_frete := v_cotacoes -> (v_linha.unidade_id::text);
      else
        if exists (
          select 1 from public.unidades u
           where u.id = v_linha.unidade_id
             and u.frete_modo in ('correios', 'melhor_envio')
        ) then
          raise exception 'Calcule o frete com a transportadora antes de finalizar o pedido';
        end if;

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

  -- Marca as cotações externas usadas; se o checkout falhou, nada foi marcado.
  for v_cot in
    select value
      from jsonb_array_elements(coalesce(p_cotacoes, '[]'::jsonb))
  loop
    update public.frete_cotacoes
       set usado_em = now()
     where id = (v_cot.value->>'cotacao_id')::uuid;
  end loop;

  return v_ret;
end $$;

revoke all on function public.finalizar_checkout_v3(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb
) from public, anon;
grant execute on function public.finalizar_checkout_v3(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision, jsonb
) to authenticated;

commit;
