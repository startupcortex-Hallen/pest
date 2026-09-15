-- ═══════════════════════════════════════════════════════════════
-- TESTE VISUAL DE LAYOUT — 20 produtos idênticos
-- Cria a categoria "Teste Layout 20" com 20 produtos iguais na
-- unidade id 3 (Aires Health - Centro I) e marca id 1 (Growth).
--
-- Para ver o efeito "Recomendados voltando junto":
--   1. Abra QUALQUER produto da unidade 3 no app
--   2. A linha "Recomendados" mostra até 10 desses produtos iguais
--   3. Toque em um e volte — os Heroes voam de volta juntos
--
-- Pode rodar quantas vezes quiser (recria do zero).
-- ═══════════════════════════════════════════════════════════════

do $$
declare
  v_cat_id bigint;
  v_marca_id bigint := 1;        -- Growth Supplements
  v_unidade_id bigint := 3;      -- Aires Health - Centro I
  v_url text := 'https://picsum.photos/seed/aires-test/400/400';
  i int;
begin
  -- Limpa execuções anteriores (produtos de teste)
  delete from carrinho
    where produto_id in (select id from produtos where nome like 'Produto Teste Layout %');
  delete from favoritos
    where produto_id in (select id from produtos where nome like 'Produto Teste Layout %');
  delete from produtos where nome like 'Produto Teste Layout %';
  delete from categorias where nome = 'Teste Layout 20';

  -- Cria a categoria de teste
  insert into categorias (nome, icone)
  values ('Teste Layout 20', 'fitness_center')
  returning id into v_cat_id;

  -- 20 produtos idênticos
  for i in 1..20 loop
    insert into produtos (
      nome, descricao, preco, em_promocao, url_imagem,
      categoria_id, marca_id, estoque, unidade_id
    ) values (
      'Produto Teste Layout ' || lpad(i::text, 2, '0'),
      'Produto idêntico criado apenas para teste visual de layout e animação de Hero.',
      99.90,
      false,
      array[v_url],
      v_cat_id,
      v_marca_id,
      50,
      v_unidade_id
    );
  end loop;

  raise notice 'Criados 20 produtos de teste na categoria % (id %)', 'Teste Layout 20', v_cat_id;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- LIMPEZA (quando terminar o teste, rode só este bloco):
--
-- delete from carrinho
--   where produto_id in (select id from produtos where nome like 'Produto Teste Layout %');
-- delete from favoritos
--   where produto_id in (select id from produtos where nome like 'Produto Teste Layout %');
-- delete from produtos where nome like 'Produto Teste Layout %';
-- delete from categorias where nome = 'Teste Layout 20';
-- ═══════════════════════════════════════════════════════════════
