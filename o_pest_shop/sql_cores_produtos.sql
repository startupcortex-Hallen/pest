-- O PEST - SHOP · CORES DOS PRODUTOS
-- Rode no SQL Editor do Supabase novo projeto

-- 1) Coluna de cores nos produtos
alter table produtos add column if not exists cores text[];

-- 2) Cores iniciais dos produtos já cadastrados
update produtos set cores = array['Preto'] where id = 1;
update produtos set cores = array['Preto', 'Branco'] where id = 2;