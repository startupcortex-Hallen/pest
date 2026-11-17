-- Assinaturas estilo streaming (planos por nÃ­vel) com pagamento recorrente
-- via Mercado Pago (preapproval) e conteÃºdo exclusivo.
-- Idempotente: pode ser executado novamente no SQL Editor.

create table if not exists public.streaming_plans (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  slug text not null unique,
  descricao text,
  nivel int not null default 1 check (nivel between 1 and 3),
  preco_centavos int not null default 0 check (preco_centavos >= 0),
  periodo text not null default 'mensal' check (periodo in ('mensal', 'anual')),
  trial_dias int not null default 0 check (trial_dias between 0 and 90),
  max_telas int not null default 1 check (max_telas > 0),
  qualidade text,
  beneficios jsonb not null default '[]'::jsonb,
  ativo boolean not null default false,
  ordem int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.streaming_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfis(id) on delete cascade,
  plan_id uuid not null references public.streaming_plans(id) on delete restrict,
  gateway text not null default 'mercadopago',
  status text not null default 'pendente'
    check (status in ('pendente', 'ativa', 'pausada', 'cancelada', 'expirada', 'inadimplente')),
  plan_nome text,
  plan_nivel int,
  preco_centavos int,
  periodo text,
  preapproval_id text unique,
  init_point text,
  payer_email text,
  started_at timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  last_payment_at timestamptz,
  last_sync_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists streaming_subscriptions_user_idx
  on public.streaming_subscriptions (user_id, created_at desc);
create index if not exists streaming_subscriptions_status_idx
  on public.streaming_subscriptions (status, current_period_end);
create unique index if not exists streaming_subscriptions_uma_ativa_idx
  on public.streaming_subscriptions (user_id)
  where status in ('pendente', 'ativa', 'pausada', 'inadimplente');

create table if not exists public.streaming_subscription_events (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid references public.streaming_subscriptions(id) on delete cascade,
  user_id uuid references public.perfis(id) on delete set null,
  tipo text not null,
  status text,
  payload jsonb,
  created_at timestamptz not null default now()
);

create index if not exists streaming_subscription_events_sub_idx
  on public.streaming_subscription_events (subscription_id, created_at desc);

create table if not exists public.streaming_access_codes (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  plano_nivel int not null default 1 check (plano_nivel between 1 and 3),
  duracao_dias int not null default 30 check (duracao_dias between 1 and 3650),
  usos_maximos int not null default 1 check (usos_maximos > 0),
  usos int not null default 0 check (usos >= 0),
  ativo boolean not null default true,
  expira_em timestamptz,
  observacao text,
  criado_por uuid references public.perfis(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists streaming_access_codes_codigo_idx
  on public.streaming_access_codes (upper(codigo));
create index if not exists streaming_access_codes_status_idx
  on public.streaming_access_codes (ativo, expira_em);

create table if not exists public.streaming_access_code_redemptions (
  id uuid primary key default gen_random_uuid(),
  code_id uuid not null references public.streaming_access_codes(id) on delete cascade,
  user_id uuid not null references public.perfis(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  expires_at timestamptz not null,
  unique (user_id, code_id)
);

create index if not exists streaming_access_redemptions_user_idx
  on public.streaming_access_code_redemptions (user_id, expires_at desc);

alter table public.streaming_series
  add column if not exists required_plan_level int not null default 0
    check (required_plan_level between 0 and 3);
alter table public.streaming_episodes
  add column if not exists required_plan_level int not null default 0
    check (required_plan_level between 0 and 3);

create or replace function public.streaming_nivel_assinatura()
returns int
language sql
security definer
stable
set search_path = public
as $$
  select case
    when public.funcao_usuario() = 'admin' then 3
    else greatest(
      coalesce(
        (
          select max(p.nivel)
          from public.streaming_subscriptions s
          join public.streaming_plans p on p.id = s.plan_id
          where s.user_id = auth.uid()
            and s.status = 'ativa'
            and (s.current_period_end is null or s.current_period_end > now())
        ),
        0
      ),
      coalesce(
        (
          select max(c.plano_nivel)
          from public.streaming_access_code_redemptions r
          join public.streaming_access_codes c on c.id = r.code_id
          where r.user_id = auth.uid()
            and r.expires_at > now()
        ),
        0
      )
    )
  end;
$$;

grant execute on function public.streaming_nivel_assinatura() to anon, authenticated;

create or replace function public.streaming_resgatar_codigo(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code public.streaming_access_codes%rowtype;
  v_expira timestamptz;
  v_existente timestamptz;
begin
  if v_user is null then
    raise exception 'FaÃ§a login para resgatar um cÃ³digo.';
  end if;
  if p_codigo is null or length(trim(p_codigo)) = 0 then
    raise exception 'Informe um cÃ³digo de acesso.';
  end if;

  select * into v_code
  from public.streaming_access_codes
  where upper(codigo) = upper(trim(p_codigo))
  for update;

  if not found then
    raise exception 'CÃ³digo invÃ¡lido.';
  end if;
  if not v_code.ativo then
    raise exception 'Este cÃ³digo estÃ¡ desativado.';
  end if;
  if v_code.expira_em is not null and v_code.expira_em < now() then
    raise exception 'Este cÃ³digo expirou.';
  end if;

  select expires_at into v_existente
  from public.streaming_access_code_redemptions
  where code_id = v_code.id and user_id = v_user;

  if found then
    if v_existente > now() then
      return jsonb_build_object(
        'ok', true,
        'reutilizado', true,
        'plano_nivel', v_code.plano_nivel,
        'expires_at', v_existente
      );
    end if;
    raise exception 'VocÃª jÃ¡ utilizou este cÃ³digo.';
  end if;

  if v_code.usos >= v_code.usos_maximos then
    raise exception 'Este cÃ³digo atingiu o limite de usos.';
  end if;

  v_expira := now() + make_interval(days => v_code.duracao_dias);

  insert into public.streaming_access_code_redemptions (
    code_id, user_id, redeemed_at, expires_at
  ) values (
    v_code.id, v_user, now(), v_expira
  );

  update public.streaming_access_codes
  set usos = usos + 1, updated_at = now()
  where id = v_code.id;

  return jsonb_build_object(
    'ok', true,
    'reutilizado', false,
    'plano_nivel', v_code.plano_nivel,
    'expires_at', v_expira
  );
end;
$$;

grant execute on function public.streaming_resgatar_codigo(text) to authenticated;

create or replace function public.streaming_has_plan_level(nivel_minimo int)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(nivel_minimo, 0) <= 0
    or public.streaming_nivel_assinatura() >= coalesce(nivel_minimo, 0);
$$;

grant execute on function public.streaming_has_plan_level(int) to anon, authenticated;

create or replace function public.streaming_has_active_subscription()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.streaming_nivel_assinatura() > 0;
$$;

grant execute on function public.streaming_has_active_subscription() to authenticated;

create or replace function public.streaming_contar_episodios(p_series_id uuid)
returns int
language sql
security definer
stable
set search_path = public
as $$
  select count(*)::int
  from public.streaming_episodes ep
  join public.streaming_seasons se on se.id = ep.season_id
  join public.streaming_series s on s.id = se.series_id
  where se.series_id = p_series_id
    and se.status = 'publicado'
    and s.status = 'publicado'
    and (
      (ep.status = 'publicado'
        and (ep.published_at is null or ep.published_at <= now()))
      or (ep.status = 'agendado'
        and ep.published_at is not null
        and ep.published_at <= now())
    );
$$;

grant execute on function public.streaming_contar_episodios(uuid) to anon, authenticated;

-- A view Ã© recriada para expor required_plan_level e manter a contagem de
-- episÃ³dios mesmo para quem ainda nÃ£o Ã© assinante.
-- O DROP Ã© necessÃ¡rio porque a nova coluna entra antes das colunas de contagem.
drop view if exists public.streaming_series_catalogo;

create view public.streaming_series_catalogo
with (security_invoker = true)
as
select
  s.*,
  (
    select count(*)::int
    from public.streaming_seasons se
    where se.series_id = s.id and se.status = 'publicado'
  ) as seasons_count,
  public.streaming_contar_episodios(s.id) as episodes_count
from public.streaming_series s;

grant select on public.streaming_series_catalogo to anon, authenticated;

-- Assinantes veem episÃ³dios exclusivos; visitantes e usuÃ¡rios sem plano nÃ£o.
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
            coalesce(streaming_episodes.required_plan_level, 0)
          )
        )
    )
  );

alter table public.streaming_plans enable row level security;
alter table public.streaming_subscriptions enable row level security;
alter table public.streaming_subscription_events enable row level security;
alter table public.streaming_access_codes enable row level security;
alter table public.streaming_access_code_redemptions enable row level security;

drop policy if exists streaming_plans_publicos on public.streaming_plans;
create policy streaming_plans_publicos
  on public.streaming_plans for select to anon, authenticated
  using (ativo = true);

drop policy if exists streaming_plans_admin on public.streaming_plans;
create policy streaming_plans_admin
  on public.streaming_plans for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

drop policy if exists streaming_subscriptions_propria on public.streaming_subscriptions;
create policy streaming_subscriptions_propria
  on public.streaming_subscriptions for select to authenticated
  using (user_id = auth.uid());

drop policy if exists streaming_subscriptions_admin on public.streaming_subscriptions;
create policy streaming_subscriptions_admin
  on public.streaming_subscriptions for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

drop policy if exists streaming_subscription_events_admin
  on public.streaming_subscription_events;
create policy streaming_subscription_events_admin
  on public.streaming_subscription_events for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

drop policy if exists streaming_access_codes_admin on public.streaming_access_codes;
create policy streaming_access_codes_admin
  on public.streaming_access_codes for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

drop policy if exists streaming_access_redemptions_propria
  on public.streaming_access_code_redemptions;
create policy streaming_access_redemptions_propria
  on public.streaming_access_code_redemptions for select to authenticated
  using (user_id = auth.uid());

drop policy if exists streaming_access_redemptions_admin
  on public.streaming_access_code_redemptions;
create policy streaming_access_redemptions_admin
  on public.streaming_access_code_redemptions for all to authenticated
  using (public.funcao_usuario() = 'admin')
  with check (public.funcao_usuario() = 'admin');

grant select on public.streaming_plans to anon, authenticated;
grant insert, update, delete on public.streaming_plans to authenticated;

grant select on public.streaming_subscriptions to authenticated;
grant insert, update, delete on public.streaming_subscriptions to authenticated;

grant select on public.streaming_subscription_events to authenticated;
grant insert, update, delete on public.streaming_subscription_events to authenticated;

grant select, insert, update, delete on public.streaming_access_codes to authenticated;
grant select on public.streaming_access_code_redemptions to authenticated;
grant insert, update, delete on public.streaming_access_code_redemptions to authenticated;

revoke all on public.streaming_subscriptions from anon;
revoke all on public.streaming_subscription_events from anon;
revoke all on public.streaming_access_codes from anon;
revoke all on public.streaming_access_code_redemptions from anon;
revoke all on public.streaming_plans from anon;
grant select on public.streaming_plans to anon;

drop trigger if exists streaming_plans_updated_at on public.streaming_plans;
create trigger streaming_plans_updated_at
  before update on public.streaming_plans
  for each row execute function public.streaming_set_updated_at();

delete from public.streaming_plans
where slug in ('opest-plus-basico', 'opest-plus-padrao', 'opest-plus-premium')
  and not exists (
    select 1 from public.streaming_subscriptions s
    where s.plan_id = public.streaming_plans.id
  );

insert into public.streaming_plans (
  nome, slug, descricao, nivel, preco_centavos, periodo, trial_dias,
  max_telas, qualidade, beneficios, ativo, ordem
) values (
  'O Pest+',
  'opest-plus-mensal',
  'Acesso completo Ã s 12 temporadas e aos conteÃºdos exclusivos do O Pest+.',
  1, 1499, 'mensal', 0, 1, 'HD',
  '["12 temporadas completas","10 episÃ³dios por temporada","Novos episÃ³dios antes","Assista no celular"]'::jsonb,
  true, 1
)
on conflict (slug) do update set
  nome = excluded.nome,
  descricao = excluded.descricao,
  nivel = excluded.nivel,
  preco_centavos = excluded.preco_centavos,
  periodo = excluded.periodo,
  trial_dias = excluded.trial_dias,
  max_telas = excluded.max_telas,
  qualidade = excluded.qualidade,
  beneficios = excluded.beneficios,
  ativo = true,
  ordem = excluded.ordem,
  updated_at = now();

-- ============================================================
-- CatÃ¡logo de teste: 12 temporadas x 10 episÃ³dios
-- Os links abaixo sÃ£o placeholders pÃºblicos do YouTube para teste.
-- O administrador deve substituÃ­-los pelos vÃ­deos oficiais/privados.
-- ============================================================

do $$
declare
  v_series_id uuid;
  v_season_id uuid;
  v_season int;
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
  select id into v_series_id
  from public.streaming_series
  where slug = 'de-dentro-da-favela';

  if v_series_id is null then
    insert into public.streaming_series (
      title, slug, description, synopsis, cover_url, banner_url,
      category, status, is_featured, display_order, required_plan_level
    ) values (
      'De Dentro da Favela',
      'de-dentro-da-favela',
      'WebsÃ©rie do canal O Pest.',
      'De Dentro da Favela, produÃ§Ã£o do canal O Pest.',
      'https://img.youtube.com/vi/PHVQ17ifaWo/hqdefault.jpg',
      'https://img.youtube.com/vi/PHVQ17ifaWo/hqdefault.jpg',
      'WebsÃ©rie',
      'publicado',
      true,
      0,
      1
    )
    returning id into v_series_id;
  end if;

  update public.streaming_series
  set required_plan_level = 1,
      status = 'publicado',
      is_featured = true,
      updated_at = now()
  where id = v_series_id;

  for v_season in 1..12 loop
    insert into public.streaming_seasons (
      series_id, season_number, title, status, display_order
    ) values (
      v_series_id,
      v_season,
      v_season || 'Âª temporada',
      'publicado',
      v_season
    )
    on conflict (series_id, season_number) do update set
      title = excluded.title,
      status = 'publicado',
      display_order = excluded.display_order,
      updated_at = now()
    returning id into v_season_id;

    for v_ep in 1..10 loop
      v_video_id := v_ids[((v_ep - 1) % array_length(v_ids, 1)) + 1];

      insert into public.streaming_episodes (
        season_id, episode_number, title, youtube_video_id, youtube_url,
        status, display_order, published_at
      ) values (
        v_season_id,
        v_ep,
        'EpisÃ³dio ' || v_ep,
        v_video_id,
        'https://www.youtube.com/watch?v=' || v_video_id,
        'publicado',
        v_ep,
        now()
      )
      on conflict (season_id, episode_number) do update set
        title = excluded.title,
        youtube_video_id = excluded.youtube_video_id,
        youtube_url = excluded.youtube_url,
        status = 'publicado',
        display_order = excluded.display_order,
        published_at = coalesce(
          streaming_episodes.published_at,
          excluded.published_at
        ),
        updated_at = now();
    end loop;
  end loop;

  update public.streaming_home_config
  set hero_series_id = v_series_id,
      updated_at = now()
  where id = 1;
end $$;

-- Realtime para o painel/admin refletir alteraÃ§Ãµes de links e metadados no app.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'streaming_episodes'
  ) then
    execute 'alter publication supabase_realtime add table public.streaming_episodes';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'streaming_seasons'
  ) then
    execute 'alter publication supabase_realtime add table public.streaming_seasons';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'streaming_series'
  ) then
    execute 'alter publication supabase_realtime add table public.streaming_series';
  end if;
end $$;

