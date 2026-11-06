-- Código do objeto dos Correios também no pedido.
--
-- A Edge Function `frete-etiqueta` grava o código em `envios.codigo_objeto`
-- e espelha em `pedidos.codigo_rastreio`/`url_rastreio` para o cliente.
-- A coluna `pedidos.codigo_objeto` faltava, fazendo o UPDATE inteiro falhar
-- e deixando o cliente sem etiqueta/rastreio no detalhe do pedido.

alter table public.pedidos
  add column if not exists codigo_objeto text;

comment on column public.pedidos.codigo_objeto is
  'Código do objeto gerado na Pré-Postagem dos Correios.';

notify pgrst, 'reload schema';
