-- O detalhe do pedido no admin busca `pedido_historico(*, perfis(nome))`.
-- A coluna `alterado_por` guarda o usuário que mudou o status, mas não tinha
-- FK para `perfis`; o PostgREST respondia PGRST200 e a tela inteira falhava.
-- Sem órfãos no banco, a FK pode ser criada com segurança.

alter table public.pedido_historico
  drop constraint if exists pedido_historico_alterado_por_fkey;

alter table public.pedido_historico
  add constraint pedido_historico_alterado_por_fkey
  foreign key (alterado_por) references public.perfis(id)
  on delete set null;

notify pgrst, 'reload schema';
