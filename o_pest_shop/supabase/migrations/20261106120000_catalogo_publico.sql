-- Catálogo público para visitantes anônimos.
-- Não expõe custo, PIX, repasse ou dados de usuário.
-- Idempotente: pode ser executado novamente no SQL Editor.

create or replace view public.produtos_publicos
with (security_invoker = false)
as
select
  p.id,
  p.nome,
  p.descricao,
  p.preco,
  p.preco_promocional,
  p.em_promocao,
  p.url_imagem,
  p.categoria_id,
  p.marca_id,
  p.estoque,
  p.unidade_id,
  p.vendas,
  p.frete_gratis,
  p.percentual_desconto,
  p.garantia,
  p.parcelas,
  p.cores,
  p.sku,
  p.gtin,
  p.peso_kg,
  p.comprimento_cm,
  p.largura_cm,
  p.altura_cm,
  p.condicao,
  p.ativo,
  p.created_at,
  c.nome as categoria_nome,
  m.nome as marca_nome,
  u.nome as unidade_nome
from public.produtos p
left join public.categorias c on c.id = p.categoria_id
left join public.marcas m on m.id = p.marca_id
left join public.unidades u on u.id = p.unidade_id
where coalesce(p.ativo, true) = true
  and coalesce(u.ativa, true) = true
  and u.deleted_at is null;

grant select on public.produtos_publicos to anon, authenticated;

create or replace view public.unidades_publicas
with (security_invoker = false)
as
select
  u.id, u.nome, u.slug, u.logo_url, u.endereco, u.bairro, u.cidade,
  u.foto_url, u.cep, u.numero, u.complemento, u.uf,
  u.horario_seg, u.horario_ter, u.horario_qua, u.horario_qui,
  u.horario_sex, u.horario_sab, u.horario_dom,
  u.ordem, u.distancia, u.ativa, u.prazo_retirada_min, u.prazo_entrega_min,
  u.created_at, u.latitude, u.longitude,
  u.taxa_entrega, u.frete_gratis_acima, u.frete_modo, u.frete_taxa_base,
  u.frete_valor_km, u.frete_km_minimo, u.frete_raio_max_km,
  u.frete_fator_rota, u.frete_tempo_km_min, u.frete_peso_incluso_kg,
  u.frete_valor_kg_extra, u.tipo_loja
from public.unidades u
where coalesce(u.ativa, true) = true
  and u.deleted_at is null;

grant select on public.unidades_publicas to anon, authenticated;

drop policy if exists "categorias_select_anon" on public.categorias;
create policy "categorias_select_anon" on public.categorias
  for select to anon using (true);
grant select on public.categorias to anon;

drop policy if exists "marcas_select_anon" on public.marcas;
create policy "marcas_select_anon" on public.marcas
  for select to anon using (true);
grant select on public.marcas to anon;

drop policy if exists "galeria_produtos_select_anon" on public.galeria_produtos;
create policy "galeria_produtos_select_anon" on public.galeria_produtos
  for select to anon using (true);
grant select on public.galeria_produtos to anon;

drop policy if exists "banners_select_anon" on public.banners;
create policy "banners_select_anon" on public.banners
  for select to anon
  using (
    ativo = true
    and (data_inicio is null or data_inicio <= now())
    and (data_fim is null or data_fim >= now())
  );
grant select on public.banners to anon;

revoke select on public.produtos from anon;
