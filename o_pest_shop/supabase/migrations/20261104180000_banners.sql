-- Banners da home com ordenação, ativação e período de exibição.

begin;

create table if not exists public.banners (
  id bigint generated always as identity primary key,
  titulo text,
  imagem_url text not null,
  link_url text,
  ordem int not null default 0,
  ativo boolean not null default true,
  data_inicio timestamptz,
  data_fim timestamptz,
  unidade_id bigint references public.unidades(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_banners_home
  on public.banners(ativo, ordem, data_inicio, data_fim);

alter table public.banners enable row level security;

drop policy if exists "banners_select" on public.banners;
create policy "banners_select" on public.banners
  for select to authenticated
  using (
    (
      ativo = true
      and (data_inicio is null or data_inicio <= now())
      and (data_fim is null or data_fim >= now())
    )
    or public.funcao_usuario() = 'admin'
  );

drop policy if exists "banners_admin_all" on public.banners;
create policy "banners_admin_all" on public.banners
  for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

revoke all on public.banners from anon, authenticated;
grant select, insert, update, delete on public.banners to authenticated;
grant all on public.banners to service_role;

notify pgrst, 'reload schema';

commit;
