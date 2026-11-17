-- Verificações de estrutura e segurança da central de streaming.
-- Rode no SQL Editor do ambiente de testes DEPOIS de aplicar a migration
-- 20261112120000_streaming_catalogo.sql.
-- O script apenas consulta metadados; não altera dados.

do $$
declare
  v_tabela text;
begin
  foreach v_tabela in array array[
    'streaming_series',
    'streaming_seasons',
    'streaming_episodes',
    'streaming_watch_progress',
    'streaming_favorites',
    'streaming_watch_history',
    'streaming_home_config'
  ] loop
    if to_regclass('public.' || v_tabela) is null then
      raise exception 'FALHOU: tabela public.% ausente', v_tabela;
    end if;

    if not exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = v_tabela
        and c.relrowsecurity
    ) then
      raise exception 'FALHOU: RLS desativada em public.%', v_tabela;
    end if;
  end loop;

  if to_regclass('public.streaming_series_catalogo') is null then
    raise exception 'FALHOU: view streaming_series_catalogo ausente';
  end if;

  if not has_table_privilege('anon', 'public.streaming_series', 'SELECT') then
    raise exception 'FALHOU: anon não lê séries publicadas';
  end if;
  if has_table_privilege('anon', 'public.streaming_series', 'INSERT') then
    raise exception 'FALHOU: anon pode inserir séries';
  end if;
  if has_table_privilege('anon', 'public.streaming_episodes', 'UPDATE') then
    raise exception 'FALHOU: anon pode editar episódios';
  end if;
  if has_table_privilege('anon', 'public.streaming_watch_progress', 'SELECT') then
    raise exception 'FALHOU: anon pode ler progresso de usuários';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'streaming_series'
      and policyname = 'streaming_series_admin'
  ) then
    raise exception 'FALHOU: policy de administração de séries ausente';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'streaming_watch_progress'
      and policyname = 'streaming_progress_proprio_update'
  ) then
    raise exception 'FALHOU: policy de progresso próprio ausente';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'streaming_favorites'
      and policyname = 'streaming_favorites_proprio_insert'
  ) then
    raise exception 'FALHOU: policy de favoritos próprios ausente';
  end if;

  if not exists (
    select 1 from storage.buckets where id = 'streaming' and public = true
  ) then
    raise exception 'FALHOU: bucket streaming ausente ou privado';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'streaming_storage_admin_insert'
  ) then
    raise exception 'FALHOU: policy de upload do bucket streaming ausente';
  end if;

  if exists (
    select 1 from public.streaming_series
    where slug = 'de-dentro-da-favela'
  ) then
    if not exists (
      select 1
      from public.streaming_episodes e
      join public.streaming_seasons t on t.id = e.season_id
      join public.streaming_series s on s.id = t.series_id
      where s.slug = 'de-dentro-da-favela'
        and e.youtube_video_id in ('PHVQ17ifaWo', 'VYVevDrfSeg')
    ) then
      raise exception 'FALHOU: episódios iniciais da série não foram cadastrados';
    end if;
  end if;
end $$;
