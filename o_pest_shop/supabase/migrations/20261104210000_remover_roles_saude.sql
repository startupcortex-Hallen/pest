-- Remove os cargos herdados de nutrição/fitness do fluxo do app.
-- As tabelas e o histórico permanecem no banco (sem perda de dados); apenas
-- os usuários que ainda tinham esses cargos passam a ser clientes.

begin;

update public.perfis
   set funcao = 'cliente'
 where funcao in ('nutricionista', 'personal');

commit;
