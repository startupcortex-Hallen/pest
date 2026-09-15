-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · FIX RLS — RECURSÃO INFINITA EM PERFIS
-- Problema: policies usavam subconsulta na própria tabela perfis
-- (select funcao from perfis where id = auth.uid()) → recursão.
-- Solução padrão: função SECURITY DEFINER que lê a função do usuário
-- sem disparar o RLS, + todas as policies recriadas usando ela.
-- RODE ESTE SCRIPT INTEIRO UMA VEZ.
-- ═══════════════════════════════════════════════════════════════

-- 1) FUNÇÃO HELPER (roda como dono da tabela — sem RLS, sem recursão)

create or replace function public.funcao_usuario()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select funcao from public.perfis where id = auth.uid();
$$;

grant execute on function public.funcao_usuario() to authenticated;

-- 2) PERFIS --------------------------------------------------------

drop policy if exists "perfis_select" on perfis;
drop policy if exists "perfis_update" on perfis;
drop policy if exists "perfis_delete" on perfis;

create policy "perfis_select" on perfis for select to authenticated
using (id = auth.uid() or public.funcao_usuario() = 'admin');

create policy "perfis_update" on perfis for update to authenticated
using (id = auth.uid() or public.funcao_usuario() = 'admin');

create policy "perfis_delete" on perfis for delete to authenticated
using (id = auth.uid() or public.funcao_usuario() = 'admin');

-- 3) DEMANDAS ADMIN -------------------------------------------------

drop policy if exists "unidades_admin_all" on unidades;
create policy "unidades_admin_all" on unidades for all to authenticated
using (public.funcao_usuario() = 'admin')
with check (public.funcao_usuario() = 'admin');

drop policy if exists "categorias_admin_all" on categorias;
create policy "categorias_admin_all" on categorias for all to authenticated
using (public.funcao_usuario() = 'admin')
with check (public.funcao_usuario() = 'admin');

drop policy if exists "marcas_admin_all" on marcas;
create policy "marcas_admin_all" on marcas for all to authenticated
using (public.funcao_usuario() = 'admin')
with check (public.funcao_usuario() = 'admin');

drop policy if exists "produtos_admin_all" on produtos;
create policy "produtos_admin_all" on produtos for all to authenticated
using (public.funcao_usuario() = 'admin')
with check (public.funcao_usuario() = 'admin');

drop policy if exists "galeria_produtos_admin_all" on galeria_produtos;
create policy "galeria_produtos_admin_all" on galeria_produtos for all to authenticated
using (public.funcao_usuario() = 'admin')
with check (public.funcao_usuario() = 'admin');

drop policy if exists "cupons_admin_all" on cupons;
create policy "cupons_admin_all" on cupons for all to authenticated
using (public.funcao_usuario() = 'admin')
with check (public.funcao_usuario() = 'admin');

drop policy if exists "posts_feed_admin_all" on posts_feed;
create policy "posts_feed_admin_all" on posts_feed for all to authenticated
using (public.funcao_usuario() = 'admin')
with check (public.funcao_usuario() = 'admin');

drop policy if exists "post_comentarios_delete" on post_comentarios;
create policy "post_comentarios_delete" on post_comentarios for delete to authenticated
using (user_id = auth.uid() or public.funcao_usuario() = 'admin');

drop policy if exists "candidaturas_select" on candidaturas;
create policy "candidaturas_select" on candidaturas for select to authenticated
using (user_id = auth.uid() or public.funcao_usuario() = 'admin');

drop policy if exists "candidaturas_admin_all" on candidaturas;
create policy "candidaturas_admin_all" on candidaturas for all to authenticated
using (public.funcao_usuario() = 'admin')
with check (public.funcao_usuario() = 'admin');

drop policy if exists "assinaturas_select" on assinaturas;
create policy "assinaturas_select" on assinaturas for select to authenticated
using (user_id = auth.uid() or public.funcao_usuario() = 'admin');

drop policy if exists "assinaturas_update" on assinaturas;
create policy "assinaturas_update" on assinaturas for update to authenticated
using (user_id = auth.uid() or public.funcao_usuario() = 'admin');

-- 4) PEDIDOS / HISTÓRICO / ESTOQUE ----------------------------------

drop policy if exists "pedidos_select" on pedidos;
create policy "pedidos_select" on pedidos for select to authenticated
using (
  user_id = auth.uid()
  or entregador_id = auth.uid()
  or public.funcao_usuario() = 'admin'
  or (public.funcao_usuario() in ('atendente','gestor')
      and unidade_id = (select unidade_id from perfis where id = auth.uid()))
);

drop policy if exists "pedidos_update" on pedidos;
create policy "pedidos_update" on pedidos for update to authenticated
using (
  user_id = auth.uid()
  or entregador_id = auth.uid()
  or public.funcao_usuario() = 'admin'
  or (public.funcao_usuario() in ('atendente','gestor')
      and unidade_id = (select unidade_id from perfis where id = auth.uid()))
);

drop policy if exists "pedido_itens_select" on pedido_itens;
create policy "pedido_itens_select" on pedido_itens for select to authenticated
using (
  exists (
    select 1 from pedidos
    where pedidos.id = pedido_itens.pedido_id
      and (
        pedidos.user_id = auth.uid()
        or pedidos.entregador_id = auth.uid()
        or public.funcao_usuario() = 'admin'
        or (public.funcao_usuario() in ('atendente','gestor')
            and pedidos.unidade_id = (select unidade_id from perfis where id = auth.uid()))
      )
  )
);

drop policy if exists "pedido_historico_select" on pedido_historico;
create policy "pedido_historico_select" on pedido_historico for select to authenticated
using (
  public.funcao_usuario() = 'admin'
  or exists (
    select 1 from pedidos
    where pedidos.id = pedido_historico.pedido_id
      and (pedidos.user_id = auth.uid() or pedidos.entregador_id = auth.uid())
  )
);

drop policy if exists "estoque_movimentacoes_select" on estoque_movimentacoes;
create policy "estoque_movimentacoes_select" on estoque_movimentacoes for select to authenticated
using (public.funcao_usuario() = 'admin');

-- 5) CONVERSAS / MENSAGENS ------------------------------------------

drop policy if exists "conversas_select" on conversas;
create policy "conversas_select" on conversas for select to authenticated
using (
  usuario_id = auth.uid()
  or public.funcao_usuario() = 'admin'
  or (public.funcao_usuario() in ('atendente','gestor')
      and unidade_id = (select unidade_id from perfis where id = auth.uid()))
);

drop policy if exists "conversas_update" on conversas;
create policy "conversas_update" on conversas for update to authenticated
using (
  usuario_id = auth.uid()
  or public.funcao_usuario() = 'admin'
  or (public.funcao_usuario() in ('atendente','gestor')
      and unidade_id = (select unidade_id from perfis where id = auth.uid()))
);

drop policy if exists "mensagens_select" on mensagens;
create policy "mensagens_select" on mensagens for select to authenticated
using (
  remetente_id = auth.uid()
  or exists (
    select 1 from conversas
    where conversas.id = mensagens.conversa_id
      and (
        conversas.usuario_id = auth.uid()
        or public.funcao_usuario() = 'admin'
        or (public.funcao_usuario() in ('atendente','gestor')
            and conversas.unidade_id = (select unidade_id from perfis where id = auth.uid()))
      )
  )
);