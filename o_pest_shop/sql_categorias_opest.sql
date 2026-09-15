-- Categorias iniciais - O Pest Shop
-- Ícones usam os nomes do mapa categoriaIcones (lib/core/helpers/categoria_icons.dart)
-- checkroom = vestuário | styler = camiseta | coffee = caneca

INSERT INTO categorias (id, nome, icone)
VALUES
  (1, 'Boné', 'checkroom'),
  (2, 'Camisa', 'styler'),
  (3, 'Caneca', 'coffee')
ON CONFLICT (id) DO UPDATE SET
  nome = EXCLUDED.nome,
  icone = EXCLUDED.icone;