-- ═══════════════════════════════════════════════════════════════
-- O PEST - SHOP · PERFIL AUTOMÁTICO
-- Cria um registro em perfis sempre que um usuário é criado no auth
-- (signup). Backfill garante perfil para quem já existia, inclusive
-- no próximo login. funcao padrão = 'usuario'
-- ═══════════════════════════════════════════════════════════════

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

-- Backfill: usuários do auth que ainda não têm perfil
insert into public.perfis (id, nome, email, perfil, funcao)
select
  au.id,
  coalesce(
    au.raw_user_meta_data ->> 'nome',
    au.raw_user_meta_data ->> 'full_name',
    split_part(au.email, '@', 1)
  ),
  au.email,
  'cliente',
  'usuario'
from auth.users au
left join public.perfis p on p.id = au.id
where p.id is null
on conflict (id) do nothing;