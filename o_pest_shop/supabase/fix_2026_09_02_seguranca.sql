-- =====================================================================
-- O Pest - Shop | BLINDAGEM PARA VENDA REAL
-- Rodar no Supabase > SQL Editor. Idempotente.
--
-- Fecha 2 furos criticos que permitem prejuizo financeiro:
--   (A) O app enviava o total/preco do pedido e o servidor confiava.
--       Dava para comprar por R$ 0,01.
--   (B) Qualquer usuario autenticado podia se tornar admin
--       (update na propria linha de perfis mudando a coluna funcao).
-- =====================================================================

-- ---------------------------------------------------------------------
-- (A) PRECO SEMPRE VEM DO BANCO
-- ---------------------------------------------------------------------

-- 1) Ao inserir um item, o preco unitario e reescrito com o preco real
--    do produto (promocional quando em promocao). Ignora o que o app mandou.
create or replace function public.fn_pedido_item_preco_real()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preco numeric;
begin
  select case
           when p.em_promocao and p.preco_promocional is not null then p.preco_promocional
           else p.preco
         end
    into v_preco
  from public.produtos p
  where p.id = new.produto_id;

  if v_preco is not null then
    new.preco_unitario := v_preco;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_pedido_item_preco_real on public.pedido_itens;
create trigger trg_pedido_item_preco_real
  before insert on public.pedido_itens
  for each row execute function public.fn_pedido_item_preco_real();

-- 2) Sempre que um item entra/muda/sai, o total do pedido e recalculado
--    a partir dos itens gravados. O total enviado pelo cliente e descartado.
--    ATENCAO: desconto de cupom deixa de ser aplicado no total. Se for usar
--    cupom, o desconto precisa ser calculado aqui no servidor (proximo passo).
create or replace function public.fn_recalcula_total_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido integer;
begin
  v_pedido := coalesce(new.pedido_id, old.pedido_id);

  update public.pedidos p
     set total = coalesce((
           select sum(i.quantidade * i.preco_unitario)
           from public.pedido_itens i
           where i.pedido_id = v_pedido
         ), 0)
   where p.id = v_pedido;

  return null;
end;
$$;

drop trigger if exists trg_recalcula_total_pedido on public.pedido_itens;
create trigger trg_recalcula_total_pedido
  after insert or update or delete on public.pedido_itens
  for each row execute function public.fn_recalcula_total_pedido();

-- ---------------------------------------------------------------------
-- (B) NINGUEM VIRA ADMIN SOZINHO
-- ---------------------------------------------------------------------

-- Bloqueia troca da coluna funcao (e unidade_id) por quem nao e admin.
-- O proprio usuario continua podendo editar nome, telefone, avatar etc.
create or replace function public.protege_funcao_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao_atual text;
begin
  if new.funcao is distinct from old.funcao
     or new.unidade_id is distinct from old.unidade_id then

    select funcao into v_funcao_atual
    from public.perfis
    where id = auth.uid();

    -- admin pode tudo; admin do sistema (sem JWT, ex.: service_role) tambem.
    if coalesce(v_funcao_atual, '') <> 'admin' and auth.uid() is not null then
      raise exception 'Somente admin pode alterar funcao ou unidade de um perfil'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protege_funcao_perfil on public.perfis;
create trigger trg_protege_funcao_perfil
  before update on public.perfis
  for each row execute function public.protege_funcao_perfil();

-- ---------------------------------------------------------------------
-- (C) IMPEDE O CLIENTE DE MARCAR O PEDIDO COMO PAGO PELO APP
--     (toda transicao de status deve passar pelas RPCs, que validam papel)
-- ---------------------------------------------------------------------

create or replace function public.protege_status_pago()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text;
begin
  -- service_role / webhook nao tem auth.uid(): pode marcar como pago.
  if auth.uid() is null then
    return new;
  end if;

  if new.status = 'pago' and old.status is distinct from 'pago' then
    select funcao into v_funcao from public.perfis where id = auth.uid();
    if coalesce(v_funcao, '') not in ('admin', 'atendente', 'gestor') then
      raise exception 'Pagamento so pode ser confirmado pelo servidor'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protege_status_pago on public.pedidos;
create trigger trg_protege_status_pago
  before update on public.pedidos
  for each row execute function public.protege_status_pago();

-- ---------------------------------------------------------------------
-- (D) LIMPEZA: cartoes salvos com o numero COMPLETO (isso nunca deveria
--     ter sido gravado). Mantem apenas os 4 ultimos digitos.
--     Rode depois de conferir quantos registros serao afetados.
-- ---------------------------------------------------------------------
-- select count(*) from public.cartoes_usuario where numero_mascarado !~ '^\*';

update public.cartoes_usuario
   set numero_mascarado = '**** **** **** ' || right(regexp_replace(numero_mascarado, '\D', '', 'g'), 4)
 where numero_mascarado is not null
   and numero_mascarado !~ '^\*'
   and length(regexp_replace(numero_mascarado, '\D', '', 'g')) >= 4;
