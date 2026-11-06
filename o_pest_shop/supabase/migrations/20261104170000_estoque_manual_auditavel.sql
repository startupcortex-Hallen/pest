-- Registra movimentação de estoque quando o ajuste é feito manualmente por
-- admin/gestor/atendente no painel. O checkout (cliente) já grava a própria
-- movimentação de venda, então o trigger ignora funções de cliente.

begin;

create or replace function public.fn_registrar_estoque_manual()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estoque is distinct from old.estoque
     and auth.uid() is not null
     and public.funcao_usuario() in ('admin', 'atendente', 'gestor') then
    insert into public.estoque_movimentacoes
      (produto_id, tipo, quantidade, motivo, criado_por)
    values
      (new.id, 'ajuste', new.estoque - old.estoque,
       'Ajuste manual no painel', auth.uid());
  end if;
  return new;
end $$;

drop trigger if exists trg_registrar_estoque_manual on public.produtos;
create trigger trg_registrar_estoque_manual
  after update of estoque on public.produtos
  for each row execute function public.fn_registrar_estoque_manual();

notify pgrst, 'reload schema';

commit;
