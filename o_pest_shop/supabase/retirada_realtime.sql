-- ═══════════════════════════════════════════════════════════════
-- RETIRADA NA UNIDADE + ajustes — trigger fn_pedido_status
-- A loja (admin/atendente da unidade) confirma a retirada diretamente:
--   pronto_para_entrega → entregue (sem entregador, recebedor opcional)
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_pedido_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_funcao text;
  v_unidade int;
  v_item record;
  v_estoque int;
begin
  v_funcao := coalesce((select funcao from perfis where id = v_uid), '');
  v_unidade := (select unidade_id from perfis where id = v_uid);

  if tg_op = 'INSERT' then
    new.status := 'pendente';
    insert into pedido_historico (pedido_id, status, alterado_por) values (new.id, 'pendente', v_uid);
    return new;
  end if;

  if new.status = old.status and new.entregador_id is distinct from old.entregador_id then
    if v_funcao not in ('admin','atendente') then
      raise exception 'Somente a loja pode atribuir entregador';
    end if;
    if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    return new;
  end if;

  if new.status = old.status then return new; end if;

  if new.status = 'cancelado' then
    if v_uid = old.user_id then
      if old.status not in ('pendente','pago','em_preparo') then
        raise exception 'O pedido já saiu para entrega; somente a loja pode cancelar';
      end if;
    elsif v_funcao = 'admin' then
      null;
    elsif v_funcao = 'atendente' and v_unidade = old.unidade_id then
      null;
    else
      raise exception 'Sem permissão para cancelar este pedido';
    end if;

    if exists (select 1 from estoque_movimentacoes where pedido_id = old.id and tipo = 'venda')
       and not exists (select 1 from estoque_movimentacoes where pedido_id = old.id and tipo = 'devolucao') then
      for v_item in select * from pedido_itens where pedido_id = old.id loop
        update produtos set estoque = estoque + v_item.quantidade where id = v_item.produto_id;
        insert into estoque_movimentacoes (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values (v_item.produto_id, old.id, 'devolucao', v_item.quantidade,
                'Cancelamento do pedido ' || old.id, v_uid);
      end loop;
    end if;
    new.cancelado_em := now();
    insert into pedido_historico (pedido_id, status, alterado_por) values (old.id, 'cancelado', v_uid);
    return new;
  end if;

  if new.status = 'pago' then
    if old.status <> 'pendente' then
      raise exception 'Transição inválida: % → pago', old.status;
    end if;
    if v_uid <> old.user_id and v_funcao <> 'admin' then
      raise exception 'Apenas o cliente dono ou o admin podem confirmar o pagamento';
    end if;

    if not exists (select 1 from estoque_movimentacoes where pedido_id = old.id and tipo = 'venda') then
      for v_item in select * from pedido_itens where pedido_id = old.id loop
        select estoque into v_estoque from produtos where id = v_item.produto_id for update;
        if v_estoque is null then
          raise exception 'Produto % não encontrado', v_item.produto_id;
        end if;
        if v_estoque < v_item.quantidade then
          raise exception 'Estoque insuficiente para "%" (disponível: %, pedido: %)',
            (select nome from produtos where id = v_item.produto_id), v_estoque, v_item.quantidade;
        end if;
        update produtos set estoque = v_estoque - v_item.quantidade where id = v_item.produto_id;
        insert into estoque_movimentacoes (produto_id, pedido_id, tipo, quantidade, motivo, criado_por)
        values (v_item.produto_id, old.id, 'venda', -v_item.quantidade,
                'Venda do pedido ' || old.id, v_uid);
      end loop;
    end if;

    new.pago_em := now();
    insert into pedido_historico (pedido_id, status, alterado_por) values (old.id, 'pago', v_uid);

    new.status := 'em_preparo';
    insert into pedido_historico (pedido_id, status, alterado_por) values (old.id, 'em_preparo', v_uid);
    return new;
  end if;

  if new.status = 'pronto_para_entrega' then
    if old.status <> 'em_preparo' then
      raise exception 'Transição inválida: % → pronto_para_entrega', old.status;
    end if;
    if v_funcao not in ('admin','atendente') then
      raise exception 'Somente a loja pode marcar pronto para entrega';
    end if;
    if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
      raise exception 'Sem permissão para pedidos de outra unidade';
    end if;
    -- Retirada não precisa de entregador; entrega sim
    if old.tipo_entrega <> 'retirada' and new.entregador_id is null then
      raise exception 'Atribua um entregador antes de marcar pronto para entrega';
    end if;
  elsif new.status = 'saiu_para_entrega' then
    if old.status <> 'pronto_para_entrega' then
      raise exception 'Transição inválida: % → saiu_para_entrega', old.status;
    end if;
    if v_uid is distinct from old.entregador_id then
      raise exception 'Somente o entregador atribuído pode iniciar a entrega';
    end if;
  elsif new.status = 'entregue' then
    -- Entrega: pronto → saiu → entregue (entregador)
    -- Retirada: pronto → entregue (loja da unidade, sem entregador)
    if old.tipo_entrega = 'retirada' then
      if old.status <> 'pronto_para_entrega' then
        raise exception 'Transição inválida: % → entregue (retirada)', old.status;
      end if;
      if v_funcao not in ('admin','atendente') then
        raise exception 'Somente a loja pode confirmar a retirada';
      end if;
      if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
        raise exception 'Sem permissão para pedidos de outra unidade';
      end if;
    else
      if old.status <> 'saiu_para_entrega' then
        raise exception 'Transição inválida: % → entregue', old.status;
      end if;
      if v_uid is distinct from old.entregador_id then
        raise exception 'Somente o entregador atribuído pode confirmar a entrega';
      end if;
      if new.recebedor_nome is null or length(trim(new.recebedor_nome)) = 0 then
        raise exception 'Informe o nome de quem recebeu';
      end if;
    end if;
    new.entregue_em := now();
  else
    raise exception 'Transição não permitida: % → %', old.status, new.status;
  end if;

  insert into pedido_historico (pedido_id, status, alterado_por) values (old.id, new.status, v_uid);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_pedido_status on pedidos;
create trigger trg_pedido_status
  before insert or update on pedidos
  for each row execute function fn_pedido_status();
