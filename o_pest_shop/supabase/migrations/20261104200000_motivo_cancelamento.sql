-- Motivo do cancelamento (auditoria) e RPC única para admin/loja/cliente.

begin;

alter table public.pedidos
  add column if not exists motivo_cancelamento text;

create or replace function public.cancelar_pedido_com_motivo(
  p_pedido_id bigint,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text := public.funcao_usuario();
  v_unidade bigint := public.unidade_usuario();
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
  v_pedido public.pedidos%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  select * into v_pedido from public.pedidos where id = p_pedido_id;
  if v_pedido.id is null then
    raise exception 'Pedido não encontrado';
  end if;

  if v_pedido.user_id <> auth.uid()
     and v_funcao <> 'admin'
     and not (
       v_funcao in ('atendente', 'gestor')
       and v_pedido.unidade_id = v_unidade
     ) then
    raise exception 'Sem permissão para cancelar este pedido';
  end if;

  if exists (
    select 1
      from public.pagamentos p
     where p.id = v_pedido.pagamento_id
       and p.status in ('pago', 'pendente', 'em_analise')
  ) then
    raise exception 'Pedido com cobrança ativa: use o cancelamento/estorno pelo gateway';
  end if;

  update public.pedidos
     set status = 'cancelado',
         motivo_cancelamento = coalesce(v_motivo, motivo_cancelamento),
         updated_at = now()
   where id = p_pedido_id
     and status <> 'cancelado';

  if v_motivo is not null then
    insert into public.pedido_auditoria (pedido_id, usuario_id, acao, detalhe)
    values (
      p_pedido_id,
      auth.uid(),
      'cancelamento',
      jsonb_build_object('motivo', v_motivo)
    );
  end if;
end $$;

revoke all on function public.cancelar_pedido_com_motivo(bigint, text)
  from public, anon;
grant execute on function public.cancelar_pedido_com_motivo(bigint, text)
  to authenticated;

notify pgrst, 'reload schema';

commit;
