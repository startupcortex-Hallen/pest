-- Atribui unidade_id para produtos que estão sem unidade
UPDATE produtos SET unidade_id = 13 WHERE id = 21; -- Whey Bar → Ouro Branco
UPDATE produtos SET unidade_id = 3 WHERE id = 22;  -- Camiseta Fitness → Centro I
UPDATE produtos SET unidade_id = 4 WHERE id = 23;  -- Shorts Masculino → Centro II
UPDATE produtos SET unidade_id = 5 WHERE id = 24;  -- Legging Feminina → Guadalajara
UPDATE produtos SET unidade_id = 6 WHERE id = 25;  -- Top Feminino → Morada da Lua
UPDATE produtos SET unidade_id = 11 WHERE id = 26; -- Colágeno Hidrolisado → Vila Rica
UPDATE produtos SET unidade_id = 12 WHERE id = 27; -- Albumina → Barreirinhas
UPDATE produtos SET unidade_id = 13 WHERE id = 28; -- Termo Pro → Ouro Branco
UPDATE produtos SET unidade_id = 10 WHERE id = 29; -- Waxy Maize → Rio Grande

-- Atualiza estoque para ter variedade (80% com estoque > 0)
UPDATE produtos SET estoque = 15 WHERE id = 1;   -- Whey Protein Isolado
UPDATE produtos SET estoque = 8  WHERE id = 2;   -- Creatina Monohidratada
UPDATE produtos SET estoque = 0  WHERE id = 3;   -- Multivitamínico Daily (sem estoque)
UPDATE produtos SET estoque = 12 WHERE id = 4;   -- Pré-Treino Explosao
UPDATE produtos SET estoque = 0  WHERE id = 5;   -- BCAA Recovery (sem estoque)
UPDATE produtos SET estoque = 20 WHERE id = 6;   -- Whey 100% Pure
UPDATE produtos SET estoque = 5  WHERE id = 7;   -- Creatina Creapure (estoque baixo)
UPDATE produtos SET estoque = 3  WHERE id = 8;   -- Pré-Treino Venom (estoque baixo)
UPDATE produtos SET estoque = 10 WHERE id = 9;   -- Multivitamínico Homem
UPDATE produtos SET estoque = 0  WHERE id = 10;  -- BCAA em Pó (sem estoque)
UPDATE produtos SET estoque = 0  WHERE id = 11;  -- Termogênico Black (sem estoque)
UPDATE produtos SET estoque = 7  WHERE id = 12;  -- Hipercalórico Mass
UPDATE produtos SET estoque = 25 WHERE id = 13;  -- Barra de Proteína
UPDATE produtos SET estoque = 50 WHERE id = 14;  -- Coqueteleira Premium
UPDATE produtos SET estoque = 0  WHERE id = 15;  -- Omega 3 (sem estoque)
UPDATE produtos SET estoque = 18 WHERE id = 16;  -- Pasta de Amendoim
UPDATE produtos SET estoque = 4  WHERE id = 17;  -- Glutamina (estoque baixo)
UPDATE produtos SET estoque = 0  WHERE id = 18;  -- ZMA (sem estoque)
UPDATE produtos SET estoque = 6  WHERE id = 19;  -- Isolate Protein
UPDATE produtos SET estoque = 2  WHERE id = 20;  -- Pré-Treino Focus (estoque baixo)
UPDATE produtos SET estoque = 30 WHERE id = 21;  -- Whey Bar
UPDATE produtos SET estoque = 12 WHERE id = 22;  -- Camiseta Fitness
UPDATE produtos SET estoque = 8  WHERE id = 23;  -- Shorts Masculino
UPDATE produtos SET estoque = 15 WHERE id = 24;  -- Legging Feminina
UPDATE produtos SET estoque = 10 WHERE id = 25;  -- Top Feminino
UPDATE produtos SET estoque = 0  WHERE id = 26;  -- Colágeno Hidrolisado (sem estoque)
UPDATE produtos SET estoque = 0  WHERE id = 27;  -- Albumina (sem estoque)
UPDATE produtos SET estoque = 6  WHERE id = 28;  -- Termo Pro
-- Waxy Maize já tem estoque = 10

-- Confirma
SELECT id, nome, unidade_id, estoque FROM produtos ORDER BY id;
