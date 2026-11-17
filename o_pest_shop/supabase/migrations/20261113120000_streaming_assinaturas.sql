-- Assinaturas estilo streaming (planos por nível) com pagamento recorrente
-- via Mercado Pago (preapproval) e conteúdo exclusivo.
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
    else coalesce(
      (
        select max(p.nivel)
        from public.streaming_subscriptions s
        join public.streaming_plans p on p.id = s.plan_id
        where s.user_id = auth.uid()
          and s.status = 'ativa'
          and (s.current_period_end is null or s.current_period_end > now())
      ),
      0
    )
  end;
$$;

grant execute on function public.streaming_nivel_assinatura() to anon, authenticated;

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

-- A view é recriada para expor required_plan_level e manter a contagem de
-- episódios mesmo para quem ainda não é assinante.
-- O DROP é necessário porque a nova coluna entra antes das colunas de contagem.
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

-- Assinantes veem episódios exclusivos; visitantes e usuários sem plano não.
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

grant select on public.streaming_plans to anon, authenticated;
grant insert, update, delete on public.streaming_plans to authenticated;

grant select on public.streaming_subscriptions to authenticated;
grant insert, update, delete on public.streaming_subscriptions to authenticated;

grant select on public.streaming_subscription_events to authenticated;
grant insert, update, delete on public.streaming_subscription_events to authenticated;

revoke all on public.streaming_subscriptions from anon;
revoke all on public.streaming_subscription_events from anon;
revoke all on public.streaming_plans from anon;
grant select on public.streaming_plans to anon;

drop trigger if exists streaming_plans_updated_at on public.streaming_plans;
create trigger streaming_plans_updated_at
  before update on public.streaming_plans
  for each row execute function public.streaming_set_updated_at();

insert into public.streaming_plans (
  nome, slug, descricao, nivel, preco_centavos, periodo, trial_dias,
  max_telas, qualidade, beneficios, ativo, ordem
) values
  (
    'O Pest+ Básico',
    'opest-plus-basico',
    'Acesso aos conteúdos exclusivos da versão alternativa.',
    1, 0, 'mensal', 7, 1, 'HD',
    '["Conteúdos exclusivos","Novos episódios antes","Assista no app"]'::jsonb,
    false, 1
  ),
  (
    'O Pest+ Padrão',
    'opest-plus-padrao',
    'Mais telas e qualidade superior para acompanhar as séries.',
    2, 0, 'mensal', 7, 2, 'Full HD',
    '["Tudo do Básico","2 telas simultâneas","Qualidade Full HD"]'::jsonb,
    false, 2
  ),
  (
    'O Pest+ Premium',
    'opest-plus-premium',
    'A experiência completa do O Pest+, com mais telas e qualidade máxima.',
    3, 0, 'mensal', 7, 4, '4K quando disponível',
    '["Tudo do Padrão","4 telas simultâneas","Qualidade máxima","Conteúdos especiais"]'::jsonb,
    false, 3
  )
on conflict (slug) do nothing;
