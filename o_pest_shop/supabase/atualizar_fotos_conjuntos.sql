-- ═══════════════════════════════════════════════════════════════
-- ATUALIZA AS FOTOS DOS CONJUNTOS FITNESS (teste tempo real)
-- 01-18: links novos enviados
-- 19: link antigo (só uma com o antigo)
-- 20: repete o 18º (só tinha 18 links)
-- ═══════════════════════════════════════════════════════════════

do $$
declare
  v_urls text[] := array[
    'https://images.tcdn.com.br/img/img_prod/1254843/conjunto_fitness_bicolor_mescla_legging_e_top_roupas_de_academia_feminina_67_2_e5b5d79409edf30a4cd17f38bd09b1d0.jpg',
    'https://i.pinimg.com/236x/85/d8/cc/85d8cc020325d56c853ab83a502a3545.jpg',
    'https://useempodere.com.br/cdn/shop/files/2464b5dbce90181db485b19b519b87bc.jpg?v=1762196298&width=1445',
    'https://images.tcdn.com.br/img/img_prod/858299/conjunto_fitness_menta_classic_top_calca_347_2_1e3b7991a5d23e519b82c5f4fba6d971.jpg',
    'https://images.tcdn.com.br/img/img_prod/858299/conjunto_fitness_lilas_com_bolso_e_forro_top_calca_341_1_1a09a048a6e7013fdf686f4c88d3d341.jpg',
    'https://acdn-us.mitiendanube.com/stores/001/708/863/products/foto-30-10-2025-20-41-08-ab4499ebd535b82abd17622516311568-480-0.webp',
    'https://images.tcdn.com.br/img/img_prod/1039984/conjunto_poliamida_canelado_3846_1_e17de58613a8fa3a245fd5d8de0d0336.jpg',
    'https://manalinda.cdn.magazord.com.br/img/2025/09/produto/6127/conjunto-basico-poliamida-rosa.jpg?ims=fit-in/465x695/filters:fill(white)',
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSnQ4xJ3EX-TZgZe1G-n1-aQB5b7yJAGbcDzSeSO_9H3XqBY49iWUt-2P0&s=10',
    'https://images.tcdn.com.br/img/img_prod/1270558/conjunto_legging_top_aveludado_de_compressao_romance_1127_1_2f7028e2f5edc526042186333b2cfa71.jpeg',
    'https://http2.mlstatic.com/D_NQ_NP_645305-MLB85117562572_052025-O-conjunto-fitness-toplegging-malha-canelado-poliester.webp',
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQARNsJo--230lkLXgXU5z4a6NPGCVwaUfqRbufBIGTH5Iy_-QUon47Czo&s=10',
    'https://http2.mlstatic.com/D_NQ_NP_917932-MLB110128598359_042026-O.webp',
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcReO295DlU3dqnrC4vzvfsV5FSa3cjBBUJvtqzCJAzF5ikWZlhKNdPdJ9J0&s=10',
    'https://adaptive-images.uooucdn.com.br/tr:w-1100,h-1594,c-at_max,pr-true,q-90/a22432-ogxytnpxyz0/pv/9b/f8/a6/6fdf5f31ee3865e2c7765a13fc.jpg',
    'https://http2.mlstatic.com/D_NQ_NP_766282-MLA111029928182_052026-O.webp',
    'https://http2.mlstatic.com/D_NQ_NP_793767-MLB108647561399_032026-O.webp',
    'https://elementomar.cdn.magazord.com.br/img/2026/01/produto/28453/23.jpg?ims=370x555'
  ];
  v_antigo text := 'https://images.tcdn.com.br/img/img_prod/1254843/conjunto_fitness_bicolor_mescla_legging_e_top_roupas_de_academia_feminina_67_1_132439b8f8af595e1ce127bedaae422a.jpg';
  i int;
  v_qtd int := 0;
begin
  -- 01-18: links novos
  for i in 1..18 loop
    update produtos
    set url_imagem = array[v_urls[i]]
    where nome = 'Conjunto Fitness ' || lpad(i::text, 2, '0');
    v_qtd := v_qtd + 1;
  end loop;

  -- 19: link antigo (só uma com o antigo)
  update produtos
  set url_imagem = array[v_antigo]
  where nome = 'Conjunto Fitness 19';
  v_qtd := v_qtd + 1;

  -- 20: repete o 18º (só tinha 18 links)
  update produtos
  set url_imagem = array[v_urls[18]]
  where nome = 'Conjunto Fitness 20';
  v_qtd := v_qtd + 1;

  raise notice 'Fotos atualizadas em % produtos', v_qtd;
end $$;

-- Verificação
select id, nome, url_imagem from produtos
where nome like 'Conjunto Fitness %' order by id;
