-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · ESQUEMA COMPLETO DO BANCO (bootstrap)
-- OBS: projeto Novo Supabase está vazio — rode este script inteiro
--      UMA vez no SQL Editor. Ele é idempotente (pode rodar de novo).
-- ═══════════════════════════════════════════════════════════════

-- 1) TABELAS ─────────────────────────────────────────────────────

create table if not exists unidades (
  id bigint generated always as identity primary key,
  nome text not null,
  slug text,
  logo_url text,
  endereco text,
  bairro text,
  cidade text,
  foto_url text,
  pix_key text,
  pix_nome text,
  horario_seg text, horario_ter text, horario_qua text, horario_qui text,
  horario_sex text, horario_sab text, horario_dom text,
  ordem int,
  distancia text,
  ativa boolean default true,
  prazo_retirada_min int default 60,
  prazo_entrega_min int default 120,
  created_at timestamptz not null default now(),
  unique (slug)
);

create table if not exists perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  email text not null,
  perfil text default 'cliente',
  funcao text default 'usuario',
  telefone text,
  avatar_url text,
  nome_completo text,
  cpf text,
  unidade_id bigint references unidades(id),
  codigo text,
  pontos int default 0,
  objetivo text,
  created_at timestamptz not null default now()
);

create table if not exists categorias (
  id bigint generated always as identity primary key,
  nome text not null,
  icone text
);

create table if not exists marcas (
  id bigint generated always as identity primary key,
  nome text not null
);

create table if not exists produtos (
  id bigint generated always as identity primary key,
  nome text not null,
  descricao text,
  preco numeric,
  preco_promocional numeric,
  em_promocao boolean default false,
  url_imagem text[],
  categoria_id bigint references categorias(id),
  marca_id bigint references marcas(id),
  estoque int default 0,
  unidade_id bigint references unidades(id),
  created_at timestamptz not null default now()
);

create table if not exists galeria_produtos (
  id bigint generated always as identity primary key,
  produto_id bigint not null references produtos(id) on delete cascade,
  url_imagem text,
  ordem int
);

create table if not exists carrinho (
  id bigint generated always as identity primary key,
  user_id uuid not null references perfis(id) on delete cascade,
  produto_id bigint not null references produtos(id) on delete cascade,
  quantidade int default 1,
  created_at timestamptz not null default now(),
  unique (user_id, produto_id)
);

create table if not exists favoritos (
  id bigint generated always as identity primary key,
  user_id uuid not null references perfis(id) on delete cascade,
  produto_id bigint not null references produtos(id) on delete cascade,
  unique (user_id, produto_id)
);

create table if not exists cupons (
  id bigint generated always as identity primary key,
  codigo text unique,
  tipo text,
  valor numeric,
  valor_minimo numeric,
  data_validade date,
  uso_maximo int,
  usos_atuais int,
  ativo boolean default true
);

create table if not exists cartoes_usuario (
  id bigint generated always as identity primary key,
  user_id uuid not null references perfis(id) on delete cascade,
  apelido text,
  numero_mascarado text,
  bandeira text,
  titular text,
  mes_validade text,
  ano_validade text,
  padrao boolean default false
);

create table if not exists posts_feed (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references perfis(id),
  titulo text,
  descricao text,
  url_imagem text,
  url_youtube text,
  categoria text,
  unidade_id bigint references unidades(id),
  created_at timestamptz not null default now()
);

create table if not exists post_likes (
  id bigint generated always as identity primary key,
  post_id uuid not null references posts_feed(id) on delete cascade,
  user_id uuid not null references perfis(id) on delete cascade,
  unique (post_id, user_id)
);

create table if not exists post_comentarios (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts_feed(id) on delete cascade,
  user_id uuid not null references perfis(id) on delete cascade,
  texto text,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);

create table if not exists candidaturas (
  id bigint generated always as identity primary key,
  vaga_id uuid not null references posts_feed(id) on delete cascade,
  user_id uuid not null references perfis(id) on delete cascade,
  nome text,
  email text,
  telefone text,
  url_curriculo text,
  created_at timestamptz not null default now(),
  unique (vaga_id, user_id)
);

create table if not exists pedidos (
  id bigint generated always as identity primary key,
  user_id uuid not null references perfis(id) on delete cascade,
  unidade_id bigint references unidades(id),
  status text default 'pendente',
  total numeric,
  pix_copia_cola text,
  pagamento text,
  tipo_entrega text default 'retirada',
  endereco_entrega text,
  cep_entrega text,
  recebedor_nome text,
  entregador_id uuid references perfis(id),
  pago_em timestamptz,
  entregue_em timestamptz,
  cancelado_em timestamptz,
  updated_at timestamptz default now(),
  created_at timestamptz not null default now()
);

create table if not exists pedido_itens (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references pedidos(id) on delete cascade,
  produto_id bigint references produtos(id),
  quantidade int,
  preco_unitario numeric
);

create table if not exists pedido_historico (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references pedidos(id) on delete cascade,
  status text,
  alterado_por uuid,
  created_at timestamptz not null default now()
);

create table if not exists estoque_movimentacoes (
  id bigint generated always as identity primary key,
  produto_id bigint references produtos(id),
  pedido_id bigint references pedidos(id),
  tipo text,
  quantidade int,
  motivo text,
  criado_por uuid,
  created_at timestamptz not null default now()
);

create table if not exists assinaturas (
  id bigint generated always as identity primary key,
  user_id uuid not null references perfis(id) on delete cascade,
  plano text default 'basico',
  status text default 'ativo',
  valor numeric,
  data_inicio date,
  data_fim date,
  bonus boolean default false
);

create table if not exists conversas (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references perfis(id) on delete cascade,
  unidade_id bigint references unidades(id),
  ultima_mensagem text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists mensagens (
  id bigint generated always as identity primary key,
  conversa_id bigint not null references conversas(id) on delete cascade,
  remetente_id uuid not null references perfis(id) on delete cascade,
  texto text,
  created_at timestamptz not null default now()
);

-- 2) FUNÇÕES DE ESTOQUE ──────────────────────────────────────────

create or replace function decrementar_estoque(produto_id bigint, quantidade int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estoque int;
begin
  if quantidade <= 0 then
    raise exception 'Quantidade inválida';
  end if;

  select estoque into v_estoque from produtos where id = produto_id for update;
  if v_estoque is null then
    raise exception 'Produto não encontrado';
  end if;
  if v_estoque < quantidade then
    raise exception 'Estoque insuficiente para o produto % (disponível: %)', produto_id, v_estoque;
  end if;

  update produtos set estoque = v_estoque - quantidade where id = produto_id;
  return v_estoque - quantidade;
end;
$$;

-- 3) TRIGGER DE STATUS DO PEDIDO (fluxo completo pendente → entregue) ──

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
      raise exception 'Sem permissão para pedidos de outra loja';
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
      raise exception 'Sem permissão para pedidos de outra loja';
    end if;
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
    if old.tipo_entrega = 'retirada' then
      if old.status <> 'pronto_para_entrega' then
        raise exception 'Transição inválida: % → entregue (retirada)', old.status;
      end if;
      if v_funcao not in ('admin','atendente') then
        raise exception 'Somente a loja pode confirmar a retirada';
      end if;
      if v_funcao = 'atendente' and v_unidade is distinct from old.unidade_id then
        raise exception 'Sem permissão para pedidos de outra loja';
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

-- 4) ROW LEVEL SECURITY ──────────────────────────────────────────

-- Função helper: lê a função do usuário SEM subconsulta recursiva
-- (security definer roda como dono da tabela, sem disparar o RLS)
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

alter table perfis enable row level security;
alter table produtos enable row level security;
alter table categorias enable row level security;
alter table marcas enable row level security;
alter table galeria_produtos enable row level security;
alter table carrinho enable row level security;
alter table favoritos enable row level security;
alter table cupons enable row level security;
alter table cartoes_usuario enable row level security;
alter table posts_feed enable row level security;
alter table post_likes enable row level security;
alter table post_comentarios enable row level security;
alter table candidaturas enable row level security;
alter table pedidos enable row level security;
alter table pedido_itens enable row level security;
alter table pedido_historico enable row level security;
alter table estoque_movimentacoes enable row level security;
alter table assinaturas enable row level security;
alter table conversas enable row level security;
alter table mensagens enable row level security;

-- Helper inline: cria policy se não existir (usa o padrão do projeto)
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'perfis_select') then
    execute 'create policy "perfis_select" on perfis for select to authenticated
             using (id = auth.uid() or public.funcao_usuario() = ''admin'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'perfis_insert') then
    execute 'create policy "perfis_insert" on perfis for insert to authenticated
             with check (id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'perfis_update') then
    execute 'create policy "perfis_update" on perfis for update to authenticated
             using (id = auth.uid() or public.funcao_usuario() = ''admin'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'perfis_delete') then
    execute 'create policy "perfis_delete" on perfis for delete to authenticated
             using (id = auth.uid() or public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'unidades_select') then
    execute 'create policy "unidades_select" on unidades for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'unidades_admin_all') then
    execute 'create policy "unidades_admin_all" on unidades for all to authenticated
             using (public.funcao_usuario() = ''admin'')
             with check (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'categorias_select') then
    execute 'create policy "categorias_select" on categorias for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'categorias_admin_all') then
    execute 'create policy "categorias_admin_all" on categorias for all to authenticated
             using (public.funcao_usuario() = ''admin'')
             with check (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'marcas_select') then
    execute 'create policy "marcas_select" on marcas for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'marcas_admin_all') then
    execute 'create policy "marcas_admin_all" on marcas for all to authenticated
             using (public.funcao_usuario() = ''admin'')
             with check (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'produtos_select') then
    execute 'create policy "produtos_select" on produtos for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'produtos_admin_all') then
    execute 'create policy "produtos_admin_all" on produtos for all to authenticated
             using (public.funcao_usuario() = ''admin'')
             with check (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'galeria_produtos_admin_all') then
    execute 'create policy "galeria_produtos_admin_all" on galeria_produtos for all to authenticated
             using (public.funcao_usuario() = ''admin'')
             with check (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'carrinho_select') then
    execute 'create policy "carrinho_select" on carrinho for select to authenticated using (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'carrinho_insert') then
    execute 'create policy "carrinho_insert" on carrinho for insert to authenticated with check (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'carrinho_update') then
    execute 'create policy "carrinho_update" on carrinho for update to authenticated using (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'carrinho_delete') then
    execute 'create policy "carrinho_delete" on carrinho for delete to authenticated using (user_id = auth.uid())';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'favoritos_select') then
    execute 'create policy "favoritos_select" on favoritos for select to authenticated using (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'favoritos_insert') then
    execute 'create policy "favoritos_insert" on favoritos for insert to authenticated with check (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'favoritos_delete') then
    execute 'create policy "favoritos_delete" on favoritos for delete to authenticated using (user_id = auth.uid())';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'cupons_select') then
    execute 'create policy "cupons_select" on cupons for select to authenticated using (ativo = true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'cupons_admin_all') then
    execute 'create policy "cupons_admin_all" on cupons for all to authenticated
             using (public.funcao_usuario() = ''admin'')
             with check (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'cartoes_select') then
    execute 'create policy "cartoes_select" on cartoes_usuario for select to authenticated using (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'cartoes_insert') then
    execute 'create policy "cartoes_insert" on cartoes_usuario for insert to authenticated with check (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'cartoes_update') then
    execute 'create policy "cartoes_update" on cartoes_usuario for update to authenticated using (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'cartoes_delete') then
    execute 'create policy "cartoes_delete" on cartoes_usuario for delete to authenticated using (user_id = auth.uid())';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'posts_feed_select') then
    execute 'create policy "posts_feed_select" on posts_feed for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'posts_feed_admin_all') then
    execute 'create policy "posts_feed_admin_all" on posts_feed for all to authenticated
             using (public.funcao_usuario() = ''admin'')
             with check (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'post_likes_select') then
    execute 'create policy "post_likes_select" on post_likes for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'post_likes_insert') then
    execute 'create policy "post_likes_insert" on post_likes for insert to authenticated with check (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'post_likes_delete') then
    execute 'create policy "post_likes_delete" on post_likes for delete to authenticated using (user_id = auth.uid())';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'post_comentarios_select') then
    execute 'create policy "post_comentarios_select" on post_comentarios for select to authenticated using (true)';
  end if;
  if not exists (select 1 from pg_policy where polname = 'post_comentarios_insert') then
    execute 'create policy "post_comentarios_insert" on post_comentarios for insert to authenticated with check (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'post_comentarios_delete') then
    execute 'create policy "post_comentarios_delete" on post_comentarios for delete to authenticated
             using (user_id = auth.uid() or public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'candidaturas_select') then
    execute 'create policy "candidaturas_select" on candidaturas for select to authenticated
             using (user_id = auth.uid() or public.funcao_usuario() = ''admin'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'candidaturas_insert') then
    execute 'create policy "candidaturas_insert" on candidaturas for insert to authenticated with check (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'candidaturas_admin_all') then
    execute 'create policy "candidaturas_admin_all" on candidaturas for all to authenticated
             using (public.funcao_usuario() = ''admin'')
             with check (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'pedidos_select') then
    execute 'create policy "pedidos_select" on pedidos for select to authenticated
             using (user_id = auth.uid()
                or entregador_id = auth.uid()
                or public.funcao_usuario() = ''admin''
                or (public.funcao_usuario() in (''atendente'',''gestor'')
                    and unidade_id = (select unidade_id from perfis where id = auth.uid())))';
  end if;
  if not exists (select 1 from pg_policy where polname = 'pedidos_proprio_insert') then
    execute 'create policy "pedidos_proprio_insert" on pedidos for insert to authenticated with check (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'pedidos_update') then
    execute 'create policy "pedidos_update" on pedidos for update to authenticated
             using (user_id = auth.uid()
                or entregador_id = auth.uid()
                or public.funcao_usuario() = ''admin''
                or (public.funcao_usuario() in (''atendente'',''gestor'')
                    and unidade_id = (select unidade_id from perfis where id = auth.uid())))';
  end if;
end $$;

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
        or (
          public.funcao_usuario() in ('atendente','gestor')
          and pedidos.unidade_id = (select unidade_id from perfis where id = auth.uid())
        )
      )
  )
);

drop policy if exists "pedido_itens_proprio_insert" on pedido_itens;
create policy "pedido_itens_proprio_insert" on pedido_itens for insert to authenticated
with check (
  exists (
    select 1 from pedidos
    where pedidos.id = pedido_itens.pedido_id
      and pedidos.user_id = auth.uid()
  )
);

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'pedido_historico_select') then
    execute 'create policy "pedido_historico_select" on pedido_historico for select to authenticated
             using (public.funcao_usuario() = ''admin''
                 or exists (select 1 from pedidos where pedidos.id = pedido_historico.pedido_id
                            and (pedidos.user_id = auth.uid() or pedidos.entregador_id = auth.uid())))';
  end if;
  if not exists (select 1 from pg_policy where polname = 'estoque_movimentacoes_select') then
    execute 'create policy "estoque_movimentacoes_select" on estoque_movimentacoes for select to authenticated
             using (public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'assinaturas_select') then
    execute 'create policy "assinaturas_select" on assinaturas for select to authenticated
             using (user_id = auth.uid() or public.funcao_usuario() = ''admin'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'assinaturas_insert') then
    execute 'create policy "assinaturas_insert" on assinaturas for insert to authenticated with check (user_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'assinaturas_update') then
    execute 'create policy "assinaturas_update" on assinaturas for update to authenticated
             using (user_id = auth.uid() or public.funcao_usuario() = ''admin'')';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'conversas_select') then
    execute 'create policy "conversas_select" on conversas for select to authenticated
             using (usuario_id = auth.uid()
                 or public.funcao_usuario() = ''admin''
                 or (public.funcao_usuario() in (''atendente'',''gestor'')
                     and unidade_id = (select unidade_id from perfis where id = auth.uid())))';
  end if;
  if not exists (select 1 from pg_policy where polname = 'conversas_insert') then
    execute 'create policy "conversas_insert" on conversas for insert to authenticated with check (usuario_id = auth.uid())';
  end if;
  if not exists (select 1 from pg_policy where polname = 'conversas_update') then
    execute 'create policy "conversas_update" on conversas for update to authenticated
             using (usuario_id = auth.uid()
                 or public.funcao_usuario() = ''admin''
                 or (public.funcao_usuario() in (''atendente'',''gestor'')
                     and unidade_id = (select unidade_id from perfis where id = auth.uid())))';
  end if;
end $$;

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
        or (
          public.funcao_usuario() in ('atendente','gestor')
          and conversas.unidade_id = (select unidade_id from perfis where id = auth.uid())
        )
      )
  )
);

drop policy if exists "mensagens_insert" on mensagens;
create policy "mensagens_insert" on mensagens for insert to authenticated
with check (remetente_id = auth.uid());

-- 5) ÍNDICES ─────────────────────────────────────────────────────

create index if not exists idx_produtos_categoria_id on produtos(categoria_id);
create index if not exists idx_produtos_unidade_id on produtos(unidade_id);
create index if not exists idx_produtos_marca_id on produtos(marca_id);
create index if not exists idx_produtos_em_promocao on produtos(em_promocao) where em_promocao = true;
create index if not exists idx_posts_feed_unidade_id on posts_feed(unidade_id);
create index if not exists idx_posts_feed_created_at on posts_feed(created_at desc);
create index if not exists idx_post_comentarios_post_id on post_comentarios(post_id);
create index if not exists idx_carrinho_user_id on carrinho(user_id);
create index if not exists idx_favoritos_user_id on favoritos(user_id);
create index if not exists idx_pedidos_user_id on pedidos(user_id);
create index if not exists idx_pedidos_created_at on pedidos(created_at desc);
create index if not exists idx_pedido_itens_pedido_id on pedido_itens(pedido_id);
create index if not exists idx_cupons_codigo on cupons(codigo);
create index if not exists idx_pedido_historico_pedido_id on pedido_historico(pedido_id);
create index if not exists idx_estoque_movimentacoes_produto on estoque_movimentacoes(produto_id);
create index if not exists idx_conversas_usuario on conversas(usuario_id);
create index if not exists idx_conversas_unidade on conversas(unidade_id);
create index if not exists idx_mensagens_conversa on mensagens(conversa_id);

-- 6) STORAGE (buckets + políticas) ───────────────────────────────

insert into storage.buckets (id, name, public)
values ('Produtos', 'Produtos', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('fotos_perfil', 'fotos_perfil', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('Curriculos', 'Curriculos', false)
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policy where polname = 'Produtos_admin_write') then
    execute 'create policy "Produtos_admin_write" on storage.objects for all to authenticated
             using (bucket_id = ''Produtos'' and public.funcao_usuario() = ''admin'')
             with check (bucket_id = ''Produtos'' and public.funcao_usuario() = ''admin'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'fotos_perfil_proprio_write') then
    execute 'create policy "fotos_perfil_proprio_write" on storage.objects for insert to authenticated
             with check (bucket_id = ''fotos_perfil'' and auth.uid()::text = (storage.foldername(name))[1])';
  end if;
  if not exists (select 1 from pg_policy where polname = 'fotos_perfil_select') then
    execute 'create policy "fotos_perfil_select" on storage.objects for select to authenticated
             using (bucket_id = ''fotos_perfil'')';
  end if;
  if not exists (select 1 from pg_policy where polname = 'Curriculos_proprio_insert') then
    execute 'create policy "Curriculos_proprio_insert" on storage.objects for insert to authenticated
             with check (bucket_id = ''Curriculos'' and auth.uid()::text = (storage.foldername(name))[1])';
  end if;
  if not exists (select 1 from pg_policy where polname = 'Curriculos_admin_select') then
    execute 'create policy "Curriculos_admin_select" on storage.objects for select to authenticated
             using (bucket_id = ''Curriculos'' and public.funcao_usuario() = ''admin'')';
  end if;
end $$;

-- 7) CATEGORIAS INICIAIS ─────────────────────────────────────────

insert into categorias (nome, icone)
values ('Boné', 'checkroom'), ('Camisa', 'styler'), ('Caneca', 'coffee')
on conflict do nothing;