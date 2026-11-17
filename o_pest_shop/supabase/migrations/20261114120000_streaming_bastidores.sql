-- Reestruturação do modelo de acesso:
--   1. As 12 temporadas principais ficam grátis (conteúdo público do YouTube).
--   2. É criada uma série separada de bastidores, com uma temporada grátis
--      e temporadas exclusivas para assinantes/códigos O Pest+.
--   3. O acesso passa a ser controlado também por temporada.
-- Idempotente: pode ser executado novamente.

alter table public.streaming_seasons
  add column if not exists required_plan_level int not null default 0
    check (required_plan_level between 0 and 3);

drop view if exists public.streaming_temporadas_contagens;

create view public.streaming_temporadas_contagens
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
        and public.streaming_has_plan_level(
          greatest(
            coalesce(s.required_plan_level, 0),
            coalesce(se.required_plan_level, 0),
            coalesce(streaming_episodes.required_plan_level, 0)
          )
        )
    )
  );

do $$
declare
  v_main_id uuid;
  v_back_id uuid;
  v_season_id uuid;
  v_s int;
  v_ep int;
  v_video_id text;
  v_ids text[] := array[
    'aqz-KE-bpKQ',
    'M7lc1UVf-VE',
    'jNQXAC9IVRw',
    'dQw4w9WgXcQ',
    '9bZkp7q19f0',
    'kJQP7kiw5Fk',
    'L_jWHffIx5E',
    'OPf0YbXqDm0',
    'RgKAFK5djSk',
    'fJ9rUzIMcZQ'
  ];
begin
  select id into v_main_id
  from public.streaming_series
  where slug = 'de-dentro-da-favela';

  if v_main_id is null then
    raise exception 'Série principal De Dentro da Favela não encontrada.';
  end if;

  -- As 12 temporadas principais ficam grátis.
  update public.streaming_series
  set required_plan_level = 0,
      status = 'publicado',
      is_featured = true,
      updated_at = now()
  where id = v_main_id;

  update public.streaming_seasons
  set required_plan_level = 0,
      status = 'publicado',
      updated_at = now()
  where series_id = v_main_id;

  update public.streaming_episodes e
  set required_plan_level = 0,
      updated_at = now()
  from public.streaming_seasons s
  where s.id = e.season_id
    and s.series_id = v_main_id;

  -- Série separada de bastidores.
  select id into v_back_id
  from public.streaming_series
  where slug = 'bastidores-de-dentro-da-favela';

  if v_back_id is null then
    insert into public.streaming_series (
      title, slug, description, synopsis, cover_url, banner_url,
      category, status, is_featured, display_order, required_plan_level
    ) values (
      'Bastidores - De Dentro da Favela',
      'bastidores-de-dentro-da-favela',
      'Bastidores, extras e conteudos exclusivos da webserie.',
      'Uma parte e gratis para todos. As temporadas de bastidores por tras de cada temporada principal sao exclusivas do O Pest+.',
      'https://img.youtube.com/vi/VYVevDrfSeg/hqdefault.jpg',
      'https://img.youtube.com/vi/VYVevDrfSeg/hqdefault.jpg',
      'Bastidores',
      'publicado',
      true,
      1,
      0
    )
    returning id into v_back_id;
  else
    update public.streaming_series
    set title = 'Bastidores - De Dentro da Favela',
        description = 'Bastidores, extras e conteudos exclusivos da webserie.',
        synopsis = 'Uma parte e gratis para todos. As temporadas de bastidores por tras de cada temporada principal sao exclusivas do O Pest+.',
        category = 'Bastidores',
        status = 'publicado',
        is_featured = true,
        required_plan_level = 0,
        display_order = 1,
        updated_at = now()
    where id = v_back_id;
  end if;

  -- Temporada 1: bastidores grátis (5 episódios).
  insert into public.streaming_seasons (
    series_id, season_number, title, description, status,
    display_order, required_plan_level
  ) values (
    v_back_id,
    1,
    'Bastidores Gratis',
    'Uma amostra gratis dos bastidores para todos os fas.',
    'publicado',
    1,
    0
  )
  on conflict (series_id, season_number) do update set
    title = excluded.title,
    description = excluded.description,
    status = 'publicado',
    display_order = excluded.display_order,
    required_plan_level = 0,
    updated_at = now()
  returning id into v_season_id;

  for v_ep in 1..5 loop
    v_video_id := v_ids[((v_ep - 1) % array_length(v_ids, 1)) + 1];

    insert into public.streaming_episodes (
      season_id, episode_number, title, youtube_video_id, youtube_url,
      status, display_order, published_at, required_plan_level
    ) values (
      v_season_id,
      v_ep,
      'Bastidor ' || v_ep,
      v_video_id,
      'https://www.youtube.com/watch?v=' || v_video_id,
      'publicado',
      v_ep,
      now(),
      0
    )
    on conflict (season_id, episode_number) do update set
      title = excluded.title,
      youtube_video_id = excluded.youtube_video_id,
      youtube_url = excluded.youtube_url,
      status = 'publicado',
      display_order = excluded.display_order,
      required_plan_level = 0,
      updated_at = now();
  end loop;

  -- Temporadas 2..13: bastidores exclusivos de cada uma das 12 temporadas.
  for v_s in 1..12 loop
    insert into public.streaming_seasons (
      series_id, season_number, title, description, status,
      display_order, required_plan_level
    ) values (
      v_back_id,
      v_s + 1,
      'Bastidores - Temporada ' || v_s,
      'Conteudo exclusivo dos bastidores da temporada ' || v_s || '.',
      'publicado',
      v_s + 1,
      1
    )
    on conflict (series_id, season_number) do update set
      title = excluded.title,
      description = excluded.description,
      status = 'publicado',
      display_order = excluded.display_order,
      required_plan_level = 1,
      updated_at = now()
    returning id into v_season_id;

    for v_ep in 1..5 loop
      v_video_id := v_ids[
        (
          ((v_s - 1) * 5 + (v_ep - 1)) % array_length(v_ids, 1)
        ) + 1
      ];

      insert into public.streaming_episodes (
        season_id, episode_number, title, youtube_video_id, youtube_url,
        status, display_order, published_at, required_plan_level
      ) values (
        v_season_id,
        v_ep,
        'Bastidor ' || v_ep,
        v_video_id,
        'https://www.youtube.com/watch?v=' || v_video_id,
        'publicado',
        v_ep,
        now(),
        0
      )
      on conflict (season_id, episode_number) do update set
        title = excluded.title,
        youtube_video_id = excluded.youtube_video_id,
        youtube_url = excluded.youtube_url,
        status = 'publicado',
        display_order = excluded.display_order,
        required_plan_level = 0,
        updated_at = now();
    end loop;
  end loop;

  update public.streaming_home_config
  set hero_series_id = v_main_id,
      updated_at = now()
  where id = 1;
end $$;

-- Realtime para refletir mudanças de links também nas temporadas.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'streaming_seasons'
  ) then
    execute 'alter publication supabase_realtime add table public.streaming_seasons';
  end if;
end $$;
