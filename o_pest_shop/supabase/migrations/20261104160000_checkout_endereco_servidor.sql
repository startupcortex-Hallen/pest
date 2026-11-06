-- Endurece o checkout v6 para frete por distância/faixas:
-- o endereço PRECISA existir em `enderecos_usuario`; as coordenadas usadas
-- são sempre as do banco, nunca as enviadas pelo app.
--
-- Estratégia sem reescrever a função inteira: renomeia o v6 atual para
-- `finalizar_checkout_v6_legacy` e cria um v6 público que valida o endereço
-- e chama o legado com as coordenadas do servidor.

begin;

alter function public.finalizar_checkout_v6(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb, bigint
) rename to finalizar_checkout_v6_legacy;

revoke all on function public.finalizar_checkout_v6_legacy(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb, bigint
) from public, anon, authenticated;

create function public.finalizar_checkout_v6(
  p_user_id uuid,
  p_itens jsonb,
  p_cupom_desconto_total numeric default 0,
  p_cupom_id bigint default null,
  p_tipo_entrega text default 'retirada',
  p_endereco_entrega text default null,
  p_cep_entrega text default null,
  p_endereco_lat double precision default null,
  p_endereco_lng double precision default null,
  p_cotacoes jsonb default '[]'::jsonb,
  p_idempotency_key uuid default null,
  p_endereco jsonb default null,
  p_destinatario_cpf text default null,
  p_destinatario_telefone text default null,
  p_fretes jsonb default '[]'::jsonb,
  p_endereco_usuario_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cep text := regexp_replace(
    coalesce(p_cep_entrega, p_endereco->>'cep', ''),
    '\D', '', 'g'
  );
  v_endereco record;
  v_lat double precision := p_endereco_lat;
  v_lng double precision := p_endereco_lng;
  v_precisa_endereco boolean;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'Você não pode criar pedidos para outro usuário';
  end if;

  if p_tipo_entrega = 'entrega' then
    if length(v_cep) <> 8 then
      raise exception 'Informe um CEP válido para entrega';
    end if;

    select exists (
      select 1
        from jsonb_array_elements(p_itens) as t(item)
        join public.produtos p on p.id = (t.item->>'produto_id')::bigint
        join public.unidades u on u.id = coalesce(p.unidade_id, (t.item->>'unidade_id')::bigint, 1)
       where u.frete_modo in ('distancia', 'faixas')
    ) into v_precisa_endereco;

    if v_precisa_endereco then
      if p_endereco_usuario_id is null then
        raise exception 'Salve o endereço com localização antes de finalizar a entrega';
      end if;

      select * into v_endereco
        from public.enderecos_usuario
       where id = p_endereco_usuario_id
         and user_id = p_user_id;

      if not found then
        raise exception 'Endereço não encontrado. Salve o endereço novamente.';
      end if;
      if v_endereco.latitude is null or v_endereco.longitude is null then
        raise exception 'Endereço sem localização. Informe o endereço e calcule a entrega novamente.';
      end if;
      if regexp_replace(coalesce(v_endereco.cep, ''), '\D', '', 'g') <> v_cep then
        raise exception 'O CEP do endereço não confere com o informado';
      end if;

      -- Ignora completamente as coordenadas enviadas pelo cliente.
      v_lat := v_endereco.latitude;
      v_lng := v_endereco.longitude;
    end if;
  end if;

  return public.finalizar_checkout_v6_legacy(
    p_user_id, p_itens, p_cupom_desconto_total, p_cupom_id,
    p_tipo_entrega, p_endereco_entrega, v_cep,
    v_lat, v_lng, p_cotacoes, p_idempotency_key,
    p_endereco, p_destinatario_cpf, p_destinatario_telefone,
    p_fretes, p_endereco_usuario_id
  );
end $$;

revoke all on function public.finalizar_checkout_v6(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb, bigint
) from public, anon;
grant execute on function public.finalizar_checkout_v6(
  uuid, jsonb, numeric, bigint, text, text, text, double precision, double precision,
  jsonb, uuid, jsonb, text, text, jsonb, bigint
) to authenticated;

notify pgrst, 'reload schema';

commit;
