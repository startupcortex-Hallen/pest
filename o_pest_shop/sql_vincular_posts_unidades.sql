-- Lista os posts sem unidade (para conferência)
SELECT id, titulo, unidade_id, created_at FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at;

-- Distribui os 18 posts entre as 11 unidades (2 para as 7 primeiras, 1 para as 4 últimas)
UPDATE posts_feed SET unidade_id = 3 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 2);

UPDATE posts_feed SET unidade_id = 4 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 2);

UPDATE posts_feed SET unidade_id = 5 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 2);

UPDATE posts_feed SET unidade_id = 6 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 2);

UPDATE posts_feed SET unidade_id = 7 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 2);

UPDATE posts_feed SET unidade_id = 8 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 2);

UPDATE posts_feed SET unidade_id = 9 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 2);

UPDATE posts_feed SET unidade_id = 10 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 2);

UPDATE posts_feed SET unidade_id = 11 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 1);

UPDATE posts_feed SET unidade_id = 12 
WHERE id IN (SELECT id FROM posts_feed WHERE unidade_id IS NULL ORDER BY created_at LIMIT 1);

-- Confirma que não ficou nenhum sem unidade
SELECT id, titulo, unidade_id FROM posts_feed WHERE unidade_id IS NULL;
