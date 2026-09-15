-- ═══════════════════════════════════════════════════════════════
-- FILIAÇÃO DE PROFISSIONAIS ÀS UNIDADES (perfis_unidades)
-- Nutricionista: pode se afiliar a VÁRIAS unidades, 1 é principal
-- Personal:      pode se afiliar a apenas 1 unidade
-- ═══════════════════════════════════════════════════════════════

create table if not exists perfis_unidades (
  id bigint generated always as identity primary key,
  user_id uuid not null references perfis(id) on delete cascade,
  unidade_id bigint not null references unidades(id) on delete cascade,
  principal boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, unidade_id)
);

comment on table perfis_unidades is 'Filiações de profissionais (nutricionista/personal) às unidades';

create index if not exists idx_perfis_unidades_user on perfis_unidades (user_id);
create index if not exists idx_perfis_unidades_unidade on perfis_unidades (unidade_id);

alter table perfis_unidades enable row level security;

-- Admin: acesso total (vê tudo, gerencia filiações)
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'perfis_unidades_admin_all') then
    execute 'create policy "perfis_unidades_admin_all" on perfis_unidades
             for all to authenticated
             using ((select funcao from perfis where id = auth.uid()) = ''admin'')
             with check ((select funcao from perfis where id = auth.uid()) = ''admin'')';
  end if;
end $$;

-- Profissional: vê apenas as próprias filiações
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'perfis_unidades_proprio_select') then
    execute 'create policy "perfis_unidades_proprio_select" on perfis_unidades
             for select to authenticated
             using (user_id = auth.uid())';
  end if;
end $$;
