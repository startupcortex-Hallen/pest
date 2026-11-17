-- Central de streaming de séries do aplicativo.
-- Conteúdo organizado por série > temporada > episódio, com reprodução
-- incorporada do YouTube e progresso individual por usuário.
-- Idempotente: pode ser executado novamente no SQL Editor.

create table if not exists public.streaming_series (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  description text,
  synopsis text,
  cover_url text,
  banner_url text,
  category text,
  age_rating text,
  release_year int check (release_year is null or release_year between 1900 and 2100),
  status text not null default 'rascunho'
    check (status in ('rascunho', 'publicado', 'arquivado')),
  is_featured boolean not null default false,
  display_order int not null default 0,
  trailer_youtube_id text,
  trailer_url text,
  cast_members text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.streaming_seasons (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.streaming_series(id) on delete cascade,
  season_number int not null check (season_number > 0),
  title text,
  description text,
  cover_url text,
  release_date date,
  status text not null default 'rascunho'
    check (status in ('rascunho', 'publicado', 'arquivado')),
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (series_id, season_number)
);

create table if not exists public.streaming_episodes (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.streaming_seasons(id) on delete cascade,
  episode_number int not null check (episode_number > 0),
  title text not null,
  description text,
  synopsis text,
  youtube_video_id text not null
    check (youtube_video_id ~ '^[A-Za-z0-9_-]{11}$'),
  youtube_url text,
  cover_url text,
  thumbnail_url text,
  duration_seconds int check (duration_seconds is null or duration_seconds >= 0),
  published_at timestamptz,
  status text not null default 'rascunho'
    check (status in ('rascunho', 'publicado', 'agendado', 'arquivado')),
  display_order int not null default 0,
  is_featured boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (season_id, episode_number)
);

alter table public.streaming_episodes
  add column if not exists cover_url text;

create table if not exists public.streaming_watch_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfis(id) on delete cascade,
  series_id uuid not null references public.streaming_series(id) on delete cascade,
  season_id uuid not null references public.streaming_seasons(id) on delete cascade,
  episode_id uuid not null references public.streaming_episodes(id) on delete cascade,
  progress_seconds double precision not null default 0 check (progress_seconds >= 0),
  duration_seconds double precision check (duration_seconds is null or duration_seconds >= 0),
  completed boolean not null default false,
  last_watched_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, episode_id)
);

create table if not exists public.streaming_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfis(id) on delete cascade,
  series_id uuid not null references public.streaming_series(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, series_id)
);

create table if not exists public.streaming_watch_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfis(id) on delete cascade,
  episode_id uuid not null references public.streaming_episodes(id) on delete cascade,
  watched_at timestamptz not null default now(),
  unique (user_id, episode_id)
);

create table if not exists public.streaming_home_config (
  id int primary key default 1 check (id = 1),
  hero_series_id uuid references public.streaming_series(id) on delete set null,
  sections jsonb not null default '[
    {"key": "continue_watching", "enabled": true},
    {"key": "featured", "enabled": true},
    {"key": "all_series", "enabled": true},
    {"key": "latest_episodes", "enabled": true}
  ]'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists streaming_series_status_order_idx
  on public.streaming_series (status, display_order, title);
create index if not exists streaming_series_featured_idx
  on public.streaming_series (is_featured) where is_featured = true;

create index if not exists streaming_seasons_series_order_idx
  on public.streaming_seasons (series_id, display_order, season_number);
create index if not exists streaming_seasons_status_idx
  on public.streaming_seasons (status);

create index if not exists streaming_episodes_season_order_idx
  on public.streaming_episodes (season_id, display_order, episode_number);
create index if not exists streaming_episodes_status_published_idx
  on public.streaming_episodes (status, published_at desc);

create index if not exists streaming_progress_user_recent_idx
  on public.streaming_watch_progress (user_id, last_watched_at desc);
create index if not exists streaming_progress_user_series_idx
  on public.streaming_watch_progress (user_id, series_id, last_watched_at desc);
create index if not exists streaming_history_user_recent_idx
  on public.streaming_watch_history (user_id, watched_at desc);
create index if not exists streaming_favorites_user_idx
  on public.streaming_favorites (user_id, created_at desc);

create or replace function public.streaming_set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists streaming_series_updated_at on public.streaming_series;
create trigger streaming_series_updated_at
  before update on public.streaming_series
  for each row execute function public.streaming_set_updated_at();

drop trigger if exists streaming_seasons_updated_at on public.streaming_seasons;
create trigger streaming_seasons_updated_at
  before update on public.streaming_seasons
  for each row execute function public.streaming_set_updated_at();

drop trigger if exists streaming_episodes_updated_at on public.streaming_episodes;
create trigger streaming_episodes_updated_at
  before update on public.streaming_episodes
  for each row execute function public.streaming_set_updated_at();

-- Uma vez concluído, o episódio permanece concluído mesmo se o usuário
-- reassistir. O progresso continua sendo atualizado normalmente.
create or replace function public.streaming_preserva_conclusao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if old.completed then
      new.completed = true;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists streaming_progress_preserva_conclusao
  on public.streaming_watch_progress;
create trigger streaming_progress_preserva_conclusao
  before insert or update on public.streaming_watch_progress
  for each row execute function public.streaming_preserva_conclusao();

-- Catálogo com contadores de temporadas e episódios visíveis. A view usa
-- security_invoker para respeitar as policies das tabelas de origem.
create or replace view public.streaming_series_catalogo
with (security_invoker = true)
as
select
  s.*,
  (
    select count(*)::int
    from public.streaming_seasons se
    where se.series_id = s.id and se.status = 'publicado'
  ) as seasons_count,
  (
    select count(*)::int
    from public.streaming_episodes ep
    join public.streaming_seasons se2 on se2.id = ep.season_id
    where se2.series_id = s.id
      and se2.status = 'publicado'
      and (
        (ep.status = 'publicado'
          and (ep.published_at is null or ep.published_at <= now()))
        or (ep.status = 'agendado'
          and ep.published_at is not null
          and ep.published_at <= now())
      )
  ) as episodes_count
from public.streaming_series s;

grant select on public.streaming_series_catalogo to anon, authenticated;

-- Contagens usadas pelo painel administrativo. A view respeita a RLS das
-- tabelas de origem; por isso usuários comuns só enxergam o conteúdo público.
create or replace view public.streaming_series_contagens
with (security_invoker = true)
as
select
  s.id as series_id,
  (
    select count(*)::int
    from public.streaming_seasons se
    where se.series_id = s.id
  ) as seasons_count,
  (
    select count(*)::int
    from public.streaming_episodes ep
    join public.streaming_seasons se2 on se2.id = ep.season_id
    where se2.series_id = s.id
  ) as episodes_count
from public.streaming_series s;

grant select on public.streaming_series_contagens to authenticated;

create or replace view public.streaming_temporadas_contagens
with (security_invoker = true)
as
select
  se.*,
  (
    select count(*)::int
    from public.streaming_episodes ep
    where ep.season_id = se.id
  ) as episodes_count
from public.streaming_seasons se;

grant select on public.streaming_temporadas_contagens to authenticated;

-- ============================================================
-- RLS
-- ============================================================

alter table public.streaming_series enable row level security;
alter table public.streaming_seasons enable row level security;
alter table public.streaming_episodes enable row level security;
alter table public.streaming_watch_progress enable row level security;
alter table public.streaming_favorites enable row level security;
alter table public.streaming_watch_history enable row level security;
alter table public.streaming_home_config enable row level security;

drop policy if exists streaming_series_leitura_publica on public.streaming_series;
create policy streaming_series_leitura_publica
  on public.streaming_series for select to anon, authenticated
  using (status = 'publicado');

drop policy if exists streaming_series_admin on public.streaming_series;
create policy streaming_series_admin
  on public.streaming_series for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

drop policy if exists streaming_seasons_leitura_publica on public.streaming_seasons;
create policy streaming_seasons_leitura_publica
  on public.streaming_seasons for select to anon, authenticated
  using (
    status = 'publicado'
    and exists (
      select 1 from public.streaming_series s
      where s.id = series_id and s.status = 'publicado'
    )
  );

drop policy if exists streaming_seasons_admin on public.streaming_seasons;
create policy streaming_seasons_admin
  on public.streaming_seasons for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

drop policy if exists streaming_episodes_leitura_publica on public.streaming_episodes;
create policy streaming_episodes_leitura_publica
  on public.streaming_episodes for select to anon, authenticated
  using (
    (
      (status = 'publicado'
        and (published_at is null or published_at <= now()))
      or (status = 'agendado'
        and published_at is not null
        and published_at <= now())
    )
    and exists (
      select 1
      from public.streaming_seasons se
      join public.streaming_series s on s.id = se.series_id
      where se.id = season_id
        and se.status = 'publicado'
        and s.status = 'publicado'
    )
  );

drop policy if exists streaming_episodes_admin on public.streaming_episodes;
create policy streaming_episodes_admin
  on public.streaming_episodes for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

drop policy if exists streaming_progress_proprio_select on public.streaming_watch_progress;
create policy streaming_progress_proprio_select
  on public.streaming_watch_progress for select to authenticated
  using (user_id = auth.uid());

drop policy if exists streaming_progress_proprio_insert on public.streaming_watch_progress;
create policy streaming_progress_proprio_insert
  on public.streaming_watch_progress for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists streaming_progress_proprio_update on public.streaming_watch_progress;
create policy streaming_progress_proprio_update
  on public.streaming_watch_progress for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists streaming_progress_proprio_delete on public.streaming_watch_progress;
create policy streaming_progress_proprio_delete
  on public.streaming_watch_progress for delete to authenticated
  using (user_id = auth.uid());

drop policy if exists streaming_favorites_proprio_select on public.streaming_favorites;
create policy streaming_favorites_proprio_select
  on public.streaming_favorites for select to authenticated
  using (user_id = auth.uid());

drop policy if exists streaming_favorites_proprio_insert on public.streaming_favorites;
create policy streaming_favorites_proprio_insert
  on public.streaming_favorites for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists streaming_favorites_proprio_update on public.streaming_favorites;
create policy streaming_favorites_proprio_update
  on public.streaming_favorites for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists streaming_favorites_proprio_delete on public.streaming_favorites;
create policy streaming_favorites_proprio_delete
  on public.streaming_favorites for delete to authenticated
  using (user_id = auth.uid());

drop policy if exists streaming_history_proprio_select on public.streaming_watch_history;
create policy streaming_history_proprio_select
  on public.streaming_watch_history for select to authenticated
  using (user_id = auth.uid());

drop policy if exists streaming_history_proprio_insert on public.streaming_watch_history;
create policy streaming_history_proprio_insert
  on public.streaming_watch_history for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists streaming_history_proprio_update on public.streaming_watch_history;
create policy streaming_history_proprio_update
  on public.streaming_watch_history for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists streaming_history_proprio_delete on public.streaming_watch_history;
create policy streaming_history_proprio_delete
  on public.streaming_watch_history for delete to authenticated
  using (user_id = auth.uid());

drop policy if exists streaming_home_config_leitura on public.streaming_home_config;
create policy streaming_home_config_leitura
  on public.streaming_home_config for select to anon, authenticated
  using (true);

drop policy if exists streaming_home_config_admin on public.streaming_home_config;
create policy streaming_home_config_admin
  on public.streaming_home_config for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

grant select on public.streaming_series to anon, authenticated;
grant select on public.streaming_seasons to anon, authenticated;
grant select on public.streaming_episodes to anon, authenticated;
grant select on public.streaming_home_config to anon, authenticated;

grant insert, update, delete on public.streaming_series to authenticated;
grant insert, update, delete on public.streaming_seasons to authenticated;
grant insert, update, delete on public.streaming_episodes to authenticated;
grant insert, update, delete on public.streaming_home_config to authenticated;

grant select, insert, update, delete on public.streaming_watch_progress to authenticated;
grant select, insert, update, delete on public.streaming_favorites to authenticated;
grant select, insert, update, delete on public.streaming_watch_history to authenticated;

revoke all on public.streaming_series from anon;
revoke all on public.streaming_seasons from anon;
revoke all on public.streaming_episodes from anon;
revoke all on public.streaming_home_config from anon;
grant select on public.streaming_series to anon;
grant select on public.streaming_seasons to anon;
grant select on public.streaming_episodes to anon;
grant select on public.streaming_home_config to anon;

-- ============================================================
-- Storage: capas, banners e miniaturas
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'streaming',
  'streaming',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists streaming_storage_leitura on storage.objects;
create policy streaming_storage_leitura
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'streaming');

drop policy if exists streaming_storage_admin_insert on storage.objects;
create policy streaming_storage_admin_insert
  on storage.objects for insert to authenticated
  with check (bucket_id = 'streaming' and public.funcao_usuario() = 'admin');

drop policy if exists streaming_storage_admin_update on storage.objects;
create policy streaming_storage_admin_update
  on storage.objects for update to authenticated
  using (bucket_id = 'streaming' and public.funcao_usuario() = 'admin')
  with check (bucket_id = 'streaming' and public.funcao_usuario() = 'admin');

drop policy if exists streaming_storage_admin_delete on storage.objects;
create policy streaming_storage_admin_delete
  on storage.objects for delete to authenticated
  using (bucket_id = 'streaming' and public.funcao_usuario() = 'admin');

-- ============================================================
-- Catálogo inicial verificado
-- Série do canal O Pest com os dois episódios de referência informados.
-- Capas usam a miniatura padrão do YouTube derivada dos próprios vídeos;
-- o administrador pode substituir por imagens próprias no painel.
-- ============================================================

do $$
declare
  v_series_id uuid;
  v_season_id uuid;
begin
  if not exists (
    select 1 from public.streaming_series where slug = 'de-dentro-da-favela'
  ) then
    insert into public.streaming_series (
      title, slug, description, synopsis, cover_url, banner_url,
      category, status, is_featured, display_order
    ) values (
      'De Dentro da Favela',
      'de-dentro-da-favela',
      'Websérie do canal O Pest.',
      'De Dentro da Favela, produção do canal O Pest.',
      'https://img.youtube.com/vi/PHVQ17ifaWo/hqdefault.jpg',
      'https://img.youtube.com/vi/PHVQ17ifaWo/hqdefault.jpg',
      'Websérie',
      'publicado',
      true,
      0
    )
    returning id into v_series_id;

    insert into public.streaming_seasons (
      series_id, season_number, title, status, display_order
    ) values (
      v_series_id, 1, '1ª temporada', 'publicado', 1
    )
    returning id into v_season_id;

    insert into public.streaming_episodes (
      season_id, episode_number, title, youtube_video_id, youtube_url,
      status, display_order
    ) values (
      v_season_id, 1, 'Episódio 1',
      'PHVQ17ifaWo',
      'https://www.youtube.com/watch?v=PHVQ17ifaWo',
      'publicado', 1
    );

    insert into public.streaming_seasons (
      series_id, season_number, title, status, display_order
    ) values (
      v_series_id, 5, '5ª temporada', 'publicado', 5
    )
    returning id into v_season_id;

    insert into public.streaming_episodes (
      season_id, episode_number, title, youtube_video_id, youtube_url,
      status, display_order
    ) values (
      v_season_id, 1, 'Episódio 1',
      'VYVevDrfSeg',
      'https://www.youtube.com/watch?v=VYVevDrfSeg',
      'publicado', 1
    );

    insert into public.streaming_home_config (id, hero_series_id, sections)
    values (
      1,
      v_series_id,
      '[
        {"key": "continue_watching", "enabled": true},
        {"key": "featured", "enabled": true},
        {"key": "all_series", "enabled": true},
        {"key": "latest_episodes", "enabled": true}
      ]'::jsonb
    )
    on conflict (id) do nothing;
  end if;
end $$;

insert into public.streaming_home_config (id, hero_series_id, sections)
select
  1,
  s.id,
  '[
    {"key": "continue_watching", "enabled": true},
    {"key": "featured", "enabled": true},
    {"key": "all_series", "enabled": true},
    {"key": "latest_episodes", "enabled": true}
  ]'::jsonb
from public.streaming_series s
where s.slug = 'de-dentro-da-favela'
on conflict (id) do nothing;
