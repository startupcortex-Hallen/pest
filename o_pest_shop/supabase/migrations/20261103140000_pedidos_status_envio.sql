-- Status de envio por transportadora também são status válidos do pedido.
--
-- A máquina de estados (`fn_pedido_status`) já aceitava `postado` e
-- `em_transito`, mas o CHECK `chk_status_valido` continuava limitado ao ciclo
-- de retirada/entrega local. Com isso o UPDATE do rastreio falhava e o cliente
-- não via "Postado"/"Em trânsito" na timeline.

alter table public.pedidos
  drop constraint if exists chk_status_valido;

alter table public.pedidos
  add constraint chk_status_valido
  check (
    status in (
      'pendente',
      'pago',
      'em_preparo',
      'pronto_para_entrega',
      'postado',
      'em_transito',
      'saiu_para_entrega',
      'entregue',
      'cancelado'
    )
  );

notify pgrst, 'reload schema';
