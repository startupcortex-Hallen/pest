-- ═══════════════════════════════════════════════════════════════
-- CRIA 20 CONJUNTOS FITNESS (teste) — categoria Roupa Fitness
-- 1. Limpa os produtos antigos de teste ("Produto Teste Layout")
-- 2. Garante a categoria Roupa Fitness
-- 3. Cria Conjunto Fitness 01..20 com a mesma foto
-- ═══════════════════════════════════════════════════════════════

do $$
declare
  v_cat_id bigint;
  v_marca_id bigint := 1;       -- Growth Supplements
  v_unidade_id bigint := 3;     -- Aires Health - Centro I
  v_url text := 'https://images.tcdn.com.br/img/img_prod/1254843/conjunto_fitness_bicolor_mescla_legging_e_top_roupas_de_academia_feminina_67_1_132439b8f8af595e1ce127bedaae422a.jpg';
  i int;
begin
  -- 1) Limpa os produtos de teste antigos
  delete from carrinho
    where produto_id in (select id from produtos where nome like 'Produto Teste Layout %');
  delete from favoritos
    where produto_id in (select id from produtos where nome like 'Produto Teste Layout %');
  delete from produtos where nome like 'Produto Teste Layout %';
  delete from categorias where nome = 'Teste Layout 20';

  -- 2) Garante a categoria Roupa Fitness
  select id into v_cat_id from categorias where nome = 'Roupa Fitness' limit 1;
  if v_cat_id is null then
    insert into categorias (nome, icone) values ('Roupa Fitness', 'accessibility') returning id into v_cat_id;
  end if;

  -- 3) Cria os 20 conjuntos
  for i in 1..20 loop
    insert into produtos (
      nome, descricao, preco, em_promocao, url_imagem,
      categoria_id, marca_id, estoque, unidade_id
    ) values (
      'Conjunto Fitness ' || lpad(i::text, 2, '0'),
      'Conjunto fitness bicolor mescla — legging e top. Produto de teste.',
      149.90,
      false,
      array[v_url],
      v_cat_id,
      v_marca_id,
      50,
      v_unidade_id
    );
  end loop;

  raise notice 'Criados 20 conjuntos fitness na categoria Roupa Fitness (id %)', v_cat_id;
end $$;

-- Verificação
select id, nome, categoria_id, em_promocao from produtos
where nome like 'Conjunto Fitness %' order by id;
