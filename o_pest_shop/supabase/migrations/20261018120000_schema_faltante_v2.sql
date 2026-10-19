-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · COMPLEMENTO DE SCHEMA + RLS (v2)
--
-- O banco restaurado veio sem as tabelas de academia/nutrição e sem
-- algumas colunas usadas pelo app. Este script:
--   1) adiciona as colunas faltantes em tabelas existentes
--   2) cria as tabelas faltantes (academia, nutrição, desafios, etc.)
--   3) cria as FKs necessárias para os JOINs do app (PostgREST)
--   4) liga RLS + policies de todas as tabelas novas
--   5) garante buckets + policies do Storage
--   6) recria o trigger de perfil no signup
--   7) imprime um RELATÓRIO DE AUDITORIA de RLS no final
--
-- Idempotente: pode rodar mais de uma vez.
-- Rode ANTES do 20261017120000_pagamentos_gateway.sql.
-- ═══════════════════════════════════════════════════════════════

-- ── 1) COLUNAS FALTANTES ───────────────────────────────────────
alter table public.unidades add column if not exists latitude double precision;
alter table public.unidades add column if not exists longitude double precision;
alter table public.unidades add column if not exists pix_copia_cola text;

alter table public.produtos add column if not exists vendas int default 0;
alter table public.produtos add column if not exists frete_gratis boolean default false;
alter table public.produtos add column if not exists percentual_desconto int default 0;
alter table public.produtos add column if not exists garantia text;
alter table public.produtos add column if not exists parcelas int default 12;

-- Profissional vinculado à conversa (acompanhamento de personal/nutri)
alter table public.conversas add column if not exists profissional_id uuid
  references public.perfis(id) on delete set null;

create index if not exists idx_conversas_profissional on public.conversas(profissional_id);

-- ── 2) TABELAS FALTANTES · ACADEMIA ────────────────────────────
create table if not exists public.aulas (
  id bigint generated always as identity primary key,
  unidade_id bigint references public.unidades(id) on delete cascade,
  nome text,
  instrutor text,
  dia_semana text,
  horario text,
  duracao int default 60,
  vagas int default 20,
  vagas_ocupadas int default 0,
  descricao text,
  created_at timestamptz not null default now()
);

create table if not exists public.aulas_inscricao (
  id bigint generated always as identity primary key,
  aula_id bigint not null references public.aulas(id) on delete cascade,
  user_id uuid not null references public.perfis(id) on delete cascade,
  data_aula date not null,
  created_at timestamptz not null default now(),
  unique (aula_id, user_id, data_aula)
);

create table if not exists public.personal_sessoes (
  id bigint generated always as identity primary key,
  unidade_id bigint references public.unidades(id),
  personal_id uuid not null references public.perfis(id) on delete cascade,
  aluno_id uuid not null references public.perfis(id) on delete cascade,
  data_hora timestamptz not null,
  duracao int default 60,
  status text default 'agendado',
  valor numeric(10,2),
  observacao text,
  concluido boolean default false,
  created_at timestamptz not null default now()
);

create table if not exists public.avaliacoes (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  unidade_id bigint references public.unidades(id),
  data_avaliacao date not null default current_date,
  peso numeric,
  altura numeric,
  percentual_gordura numeric,
  massa_muscular numeric,
  imc numeric,
  braco_esquerdo numeric,
  braco_direito numeric,
  cintura numeric,
  quadril numeric,
  coxa_esquerda numeric,
  coxa_direita numeric,
  created_at timestamptz not null default now()
);

create table if not exists public.progresso_fotos (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  foto_url text not null,
  data date not null default current_date,
  created_at timestamptz not null default now()
);

create table if not exists public.desafios (
  id bigint generated always as identity primary key,
  unidade_id bigint references public.unidades(id) on delete cascade,
  nome text not null,
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.desafios_participantes (
  id bigint generated always as identity primary key,
  desafio_id bigint not null references public.desafios(id) on delete cascade,
  user_id uuid not null references public.perfis(id) on delete cascade,
  progresso numeric default 0,
  created_at timestamptz not null default now(),
  unique (desafio_id, user_id)
);

create table if not exists public.indicacoes (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references public.perfis(id) on delete cascade,
  indicado_id uuid references public.perfis(id) on delete set null,
  codigo_indicacao text,
  pontos_ganhos int default 0,
  created_at timestamptz not null default now()
);

-- ── 3) TABELAS FALTANTES · NUTRIÇÃO / TREINOS ──────────────────
create table if not exists public.nutricionistas (
  id bigint generated always as identity primary key,
  nome text not null,
  email text,
  telefone text,
  crn text,
  bio text,
  avatar_url text,
  preco_consulta numeric(10,2),
  disponivel boolean default true,
  created_at timestamptz not null default now()
);

create table if not exists public.consultas (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  nutricionista_id bigint references public.nutricionistas(id) on delete set null,
  data_hora timestamptz not null,
  status text default 'agendada',
  created_at timestamptz not null default now()
);

create table if not exists public.treinos (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  nome text,
  dia_semana text,
  ordem int default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.exercicios (
  id bigint generated always as identity primary key,
  treino_id bigint not null references public.treinos(id) on delete cascade,
  nome text,
  aparelho text,
  grupo_muscular text,
  series int,
  repeticoes text,
  carga_sugerida text,
  observacao text,
  ordem int default 0,
  concluido boolean default false,
  created_at timestamptz not null default now()
);

create table if not exists public.plano_refeicoes (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  dia_semana text,
  tipo text,
  horario text,
  calorias int,
  descricao text,
  icone text,
  concluido boolean default false,
  created_at timestamptz not null default now()
);

create table if not exists public.agua_registro (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  data date not null default current_date,
  ml int default 0,
  unique (user_id, data)
);

create table if not exists public.perfis_unidades (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.perfis(id) on delete cascade,
  unidade_id bigint not null references public.unidades(id) on delete cascade,
  principal boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, unidade_id)
);

-- ── 4) ÍNDICES ─────────────────────────────────────────────────
create index if not exists idx_aulas_unidade on public.aulas(unidade_id);
create index if not exists idx_aulas_inscricao_user on public.aulas_inscricao(user_id, data_aula);
create index if not exists idx_personal_sessoes_aluno on public.personal_sessoes(aluno_id, data_hora desc);
create index if not exists idx_personal_sessoes_personal on public.personal_sessoes(personal_id);
create index if not exists idx_avaliacoes_user on public.avaliacoes(user_id, data_avaliacao desc);
create index if not exists idx_progresso_fotos_user on public.progresso_fotos(user_id, data desc);
create index if not exists idx_desafios_unidade on public.desafios(unidade_id, ativo);
create index if not exists idx_desafios_part_user on public.desafios_participantes(user_id);
create index if not exists idx_indicacoes_usuario on public.indicacoes(usuario_id);
create index if not exists idx_consultas_user on public.consultas(user_id, data_hora desc);
create index if not exists idx_treinos_user on public.treinos(user_id, ordem);
create index if not exists idx_exercicios_treino on public.exercicios(treino_id, ordem);
create index if not exists idx_plano_refeicoes_user on public.plano_refeicoes(user_id, dia_semana);
create index if not exists idx_agua_registro_user on public.agua_registro(user_id, data desc);
create index if not exists idx_perfis_unidades_user on public.perfis_unidades(user_id);
create index if not exists idx_perfis_unidades_unidade on public.perfis_unidades(unidade_id);

-- ── 5) RLS + POLICIES · ACADEMIA ───────────────────────────────
alter table public.aulas enable row level security;
drop policy if exists "aulas_select" on public.aulas;
create policy "aulas_select" on public.aulas
  for select to authenticated using (true);
drop policy if exists "aulas_admin_all" on public.aulas;
create policy "aulas_admin_all" on public.aulas
  for all to authenticated
  using (public.funcao_usuario() in ('admin', 'atendente'))
  with check (public.funcao_usuario() in ('admin', 'atendente'));

alter table public.aulas_inscricao enable row level security;
drop policy if exists "aulas_inscricao_select" on public.aulas_inscricao;
create policy "aulas_inscricao_select" on public.aulas_inscricao
  for select to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));
drop policy if exists "aulas_inscricao_insert" on public.aulas_inscricao;
create policy "aulas_inscricao_insert" on public.aulas_inscricao
  for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists "aulas_inscricao_delete" on public.aulas_inscricao;
create policy "aulas_inscricao_delete" on public.aulas_inscricao
  for delete to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));

alter table public.personal_sessoes enable row level security;
drop policy if exists "personal_sessoes_select" on public.personal_sessoes;
create policy "personal_sessoes_select" on public.personal_sessoes
  for select to authenticated
  using (aluno_id = auth.uid() or personal_id = auth.uid()
         or public.funcao_usuario() in ('admin', 'atendente'));
drop policy if exists "personal_sessoes_insert" on public.personal_sessoes;
create policy "personal_sessoes_insert" on public.personal_sessoes
  for insert to authenticated
  with check (aluno_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));
drop policy if exists "personal_sessoes_update" on public.personal_sessoes;
create policy "personal_sessoes_update" on public.personal_sessoes
  for update to authenticated
  using (personal_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'))
  with check (personal_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));

alter table public.avaliacoes enable row level security;
drop policy if exists "avaliacoes_select" on public.avaliacoes;
create policy "avaliacoes_select" on public.avaliacoes
  for select to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente', 'personal', 'nutricionista'));
drop policy if exists "avaliacoes_insert" on public.avaliacoes;
create policy "avaliacoes_insert" on public.avaliacoes
  for insert to authenticated
  with check (user_id = auth.uid()
    or public.funcao_usuario() in ('admin', 'atendente', 'personal', 'nutricionista'));
drop policy if exists "avaliacoes_admin_all" on public.avaliacoes;
create policy "avaliacoes_admin_all" on public.avaliacoes
  for all to authenticated
  using (public.funcao_usuario() in ('admin', 'atendente'))
  with check (public.funcao_usuario() in ('admin', 'atendente'));

alter table public.progresso_fotos enable row level security;
drop policy if exists "progresso_fotos_select" on public.progresso_fotos;
create policy "progresso_fotos_select" on public.progresso_fotos
  for select to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));
drop policy if exists "progresso_fotos_insert" on public.progresso_fotos;
create policy "progresso_fotos_insert" on public.progresso_fotos
  for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists "progresso_fotos_delete" on public.progresso_fotos;
create policy "progresso_fotos_delete" on public.progresso_fotos
  for delete to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));

alter table public.desafios enable row level security;
drop policy if exists "desafios_select" on public.desafios;
create policy "desafios_select" on public.desafios
  for select to authenticated using (true);
drop policy if exists "desafios_admin_all" on public.desafios;
create policy "desafios_admin_all" on public.desafios
  for all to authenticated
  using (public.funcao_usuario() in ('admin', 'atendente'))
  with check (public.funcao_usuario() in ('admin', 'atendente'));

alter table public.desafios_participantes enable row level security;
drop policy if exists "desafios_part_select" on public.desafios_participantes;
create policy "desafios_part_select" on public.desafios_participantes
  for select to authenticated using (true);
drop policy if exists "desafios_part_insert" on public.desafios_participantes;
create policy "desafios_part_insert" on public.desafios_participantes
  for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists "desafios_part_update" on public.desafios_participantes;
create policy "desafios_part_update" on public.desafios_participantes
  for update to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'))
  with check (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));

alter table public.indicacoes enable row level security;
drop policy if exists "indicacoes_select" on public.indicacoes;
create policy "indicacoes_select" on public.indicacoes
  for select to authenticated
  using (usuario_id = auth.uid() or indicado_id = auth.uid()
         or public.funcao_usuario() in ('admin', 'atendente'));
drop policy if exists "indicacoes_insert" on public.indicacoes;
create policy "indicacoes_insert" on public.indicacoes
  for insert to authenticated
  with check (usuario_id = auth.uid());

-- ── 6) RLS + POLICIES · NUTRIÇÃO / TREINOS ─────────────────────
alter table public.nutricionistas enable row level security;
drop policy if exists "nutricionistas_select" on public.nutricionistas;
create policy "nutricionistas_select" on public.nutricionistas
  for select to authenticated using (true);
drop policy if exists "nutricionistas_admin_all" on public.nutricionistas;
create policy "nutricionistas_admin_all" on public.nutricionistas
  for all to authenticated
  using (public.funcao_usuario() in ('admin', 'atendente'))
  with check (public.funcao_usuario() in ('admin', 'atendente'));

alter table public.consultas enable row level security;
drop policy if exists "consultas_select" on public.consultas;
create policy "consultas_select" on public.consultas
  for select to authenticated
  using (user_id = auth.uid()
    or public.funcao_usuario() in ('admin', 'atendente', 'nutricionista'));
drop policy if exists "consultas_insert" on public.consultas;
create policy "consultas_insert" on public.consultas
  for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists "consultas_update" on public.consultas;
create policy "consultas_update" on public.consultas
  for update to authenticated
  using (public.funcao_usuario() in ('admin', 'atendente', 'nutricionista'))
  with check (public.funcao_usuario() in ('admin', 'atendente', 'nutricionista'));

alter table public.treinos enable row level security;
drop policy if exists "treinos_select" on public.treinos;
create policy "treinos_select" on public.treinos
  for select to authenticated
  using (user_id = auth.uid()
    or public.funcao_usuario() in ('admin', 'atendente', 'personal', 'nutricionista'));
drop policy if exists "treinos_owner_all" on public.treinos;
create policy "treinos_owner_all" on public.treinos
  for all to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'))
  with check (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));

alter table public.exercicios enable row level security;
drop policy if exists "exercicios_select" on public.exercicios;
create policy "exercicios_select" on public.exercicios
  for select to authenticated
  using (exists (
    select 1 from public.treinos t
     where t.id = exercicios.treino_id
       and (t.user_id = auth.uid()
            or public.funcao_usuario() in ('admin', 'atendente', 'personal', 'nutricionista'))
  ));
drop policy if exists "exercicios_owner_all" on public.exercicios;
create policy "exercicios_owner_all" on public.exercicios
  for all to authenticated
  using (exists (
    select 1 from public.treinos t
     where t.id = exercicios.treino_id
       and (t.user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'))
  ))
  with check (exists (
    select 1 from public.treinos t
     where t.id = exercicios.treino_id
       and (t.user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'))
  ));

alter table public.plano_refeicoes enable row level security;
drop policy if exists "plano_refeicoes_select" on public.plano_refeicoes;
create policy "plano_refeicoes_select" on public.plano_refeicoes
  for select to authenticated
  using (user_id = auth.uid()
    or public.funcao_usuario() in ('admin', 'atendente', 'nutricionista'));
drop policy if exists "plano_refeicoes_owner_all" on public.plano_refeicoes;
create policy "plano_refeicoes_owner_all" on public.plano_refeicoes
  for all to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'))
  with check (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));

alter table public.agua_registro enable row level security;
drop policy if exists "agua_registro_select" on public.agua_registro;
create policy "agua_registro_select" on public.agua_registro
  for select to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));
drop policy if exists "agua_registro_owner_all" on public.agua_registro;
create policy "agua_registro_owner_all" on public.agua_registro
  for all to authenticated
  using (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'))
  with check (user_id = auth.uid() or public.funcao_usuario() in ('admin', 'atendente'));

-- ── 7) PERFIS_UNIDADES (filiação de profissionais) ─────────────
alter table public.perfis_unidades enable row level security;
drop policy if exists "perfis_unidades_admin_all" on public.perfis_unidades;
create policy "perfis_unidades_admin_all" on public.perfis_unidades
  for all to authenticated
  using (public.funcao_usuario() in ('admin', 'atendente'))
  with check (public.funcao_usuario() in ('admin', 'atendente'));
drop policy if exists "perfis_unidades_proprio_select" on public.perfis_unidades;
create policy "perfis_unidades_proprio_select" on public.perfis_unidades
  for select to authenticated
  using (user_id = auth.uid());

-- ── 8) STORAGE: buckets + policies ─────────────────────────────
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

-- ── 9) PERFIL AUTOMÁTICO NO SIGNUP ─────────────────────────────
create or replace function public.criar_perfil_apos_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfis (id, nome, email, perfil, funcao)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'nome',
      new.raw_user_meta_data ->> 'full_name',
      split_part(new.email, '@', 1)
    ),
    new.email,
    'cliente',
    'usuario'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.criar_perfil_apos_signup();

-- ── 10) RELATÓRIO DE AUDITORIA DE RLS ──────────────────────────
-- Rode este SELECT no final para conferir tabela por tabela.
select
  t.tablename as tabela,
  case when t.rowsecurity then 'OK' else 'SEM RLS' end as rls,
  count(p.policyname) as qtd_policies
from pg_tables t
left join pg_policies p
  on p.schemaname = t.schemaname and p.tablename = t.tablename
where t.schemaname = 'public'
group by t.tablename, t.rowsecurity
order by t.tablename;
