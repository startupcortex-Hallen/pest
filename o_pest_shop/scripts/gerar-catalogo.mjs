import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const saida = resolve(raiz, process.env.SAIDA ?? 'web/data');
const pagina = Number(process.env.PAGINA ?? 1000);
const maxProdutos = Number(process.env.MAX_PRODUTOS ?? 20000);
const timeoutMs = Number(process.env.TIMEOUT_MS ?? 20000);

const COLUNAS_PRODUTO = [
  'id', 'nome', 'descricao', 'preco', 'preco_promocional', 'em_promocao',
  'url_imagem', 'categoria_id', 'marca_id', 'estoque', 'unidade_id', 'vendas',
  'frete_gratis', 'percentual_desconto', 'garantia', 'parcelas', 'cores',
  'sku', 'gtin', 'peso_kg', 'comprimento_cm', 'largura_cm', 'altura_cm',
  'condicao', 'ativo', 'created_at', 'categoria_nome', 'marca_nome',
  'unidade_nome',
].join(',');

const COLUNAS_UNIDADE = [
  'id', 'nome', 'slug', 'bairro', 'cidade', 'endereco', 'foto_url', 'logo_url',
  'horario_seg', 'horario_ter', 'horario_qua', 'horario_qui', 'horario_sex',
  'horario_sab', 'horario_dom', 'ordem', 'distancia', 'prazo_retirada_min',
  'prazo_entrega_min',
].join(',');

const COLUNAS_BANNER =
  'id,titulo,imagem_url,link_url,ordem,data_inicio,data_fim';

const COLUNAS_PRODUTO_BASE = [
  'id', 'nome', 'descricao', 'preco', 'preco_promocional', 'em_promocao',
  'url_imagem', 'categoria_id', 'marca_id', 'estoque', 'unidade_id', 'vendas',
  'frete_gratis', 'percentual_desconto', 'garantia', 'parcelas', 'cores',
  'sku', 'gtin', 'peso_kg', 'comprimento_cm', 'largura_cm', 'altura_cm',
  'condicao', 'ativo', 'created_at',
].join(',');

async function credenciais() {
  let url = (process.env.SUPABASE_URL ?? '').trim().replace(/\/+$/, '');
  let key = (process.env.SUPABASE_ANON_KEY ?? '').trim();

  if (!url || !key) {
    const arquivo = join(raiz, 'lib/core/constants/supabase_constants.dart');
    const texto = await readFile(arquivo, 'utf8');
    url ||= texto.match(/static const String url = '([^']+)'/)?.[1] ?? '';
    key ||= texto.match(/static const String anonKey =\s*'([^']+)'/)?.[1] ?? '';
  }

  if (!url || !key) {
    throw new Error(
      'Informe SUPABASE_URL e SUPABASE_ANON_KEY ou mantenha supabase_constants.dart.',
    );
  }

  return { url, key };
}

async function buscar(url, opcoes = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...opcoes, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function restGet(base, headers, caminho, params = {}) {
  const url = new URL(`${base}/rest/v1/${caminho}`);
  for (const [chave, valor] of Object.entries(params)) {
    url.searchParams.set(chave, String(valor));
  }
  const resposta = await buscar(url, { headers });
  if (!resposta.ok) {
    throw new Error(`${caminho}: HTTP ${resposta.status} ${await resposta.text()}`);
  }
  return resposta.json();
}

async function buscarSnapshot(base, headers) {
  try {
    const resposta = await buscar(`${base}/functions/v1/catalogo-publico`, {
      headers,
    });
    if (!resposta.ok) return null;
    const dados = await resposta.json();
    if (!dados || typeof dados !== 'object' || Array.isArray(dados)) {
      return null;
    }
    return dados;
  } catch {
    return null;
  }
}

async function buscarProdutosTabela(base, headers, tabela, filtroAtivo) {
  const produtos = [];
  const params = {
    select: filtroAtivo ? COLUNAS_PRODUTO_BASE : COLUNAS_PRODUTO,
    order: 'id.asc',
    limit: pagina,
    offset: 0,
  };
  if (filtroAtivo) params.ativo = 'eq.true';

  for (let offset = 0; offset < maxProdutos; offset += pagina) {
    params.offset = offset;
    const lote = await restGet(base, headers, tabela, params);
    if (!Array.isArray(lote) || lote.length === 0) break;
    produtos.push(...lote);
    if (lote.length < pagina) break;
  }
  return produtos;
}

async function buscarProdutos(base, headers, snapshot) {
  try {
    const produtos = await buscarProdutosTabela(
      base,
      headers,
      'produtos_publicos',
      false,
    );
    if (produtos.length > 0) return produtos;
  } catch (erro) {
    console.warn(`Aviso: produtos_publicos indisponível (${erro.message}).`);
  }

  const produtos = await buscarProdutosTabela(
    base,
    headers,
    'produtos',
    true,
  );

  const categorias = new Map(
    (snapshot.categorias ?? []).map((c) => [c.id, c.nome]),
  );
  const marcas = new Map((snapshot.marcas ?? []).map((m) => [m.id, m.nome]));
  const unidades = new Map(
    (snapshot.unidades ?? []).map((u) => [u.id, u.nome]),
  );
  const idsUnidades = new Set(unidades.keys());

  return produtos
    .filter((p) =>
      p.unidade_id == null || idsUnidades.size === 0 ||
      idsUnidades.has(p.unidade_id)
    )
    .map((p) => ({
      ...p,
      categoria_nome: categorias.get(p.categoria_id) ?? null,
      marca_nome: marcas.get(p.marca_id) ?? null,
      unidade_nome: unidades.get(p.unidade_id) ?? null,
    }));
}

function bannersVigentes(banners) {
  const agora = Date.now();
  if (!Array.isArray(banners)) return [];
  return banners.filter((banner) => {
    const inicio = banner?.data_inicio
      ? Date.parse(String(banner.data_inicio))
      : Number.NaN;
    const fim = banner?.data_fim
      ? Date.parse(String(banner.data_fim))
      : Number.NaN;
    return (!Number.isFinite(inicio) || inicio <= agora) &&
      (!Number.isFinite(fim) || fim >= agora);
  });
}

async function buscarUnidades(base, headers) {
  const publicas = await restGet(base, headers, 'unidades_publicas', {
    select: COLUNAS_UNIDADE,
    order: 'ordem.asc',
  }).catch(() => []);
  if (Array.isArray(publicas) && publicas.length > 0) return publicas;

  return restGet(base, headers, 'unidades', {
    select: COLUNAS_UNIDADE,
    ativa: 'eq.true',
    order: 'ordem.asc',
  }).catch(() => []);
}

async function fallback(base, headers) {
  const [categorias, marcas, banners, unidades] = await Promise.all([
    restGet(base, headers, 'categorias', {
      select: 'id,nome,icone',
      order: 'nome.asc',
    }).catch(() => []),
    restGet(base, headers, 'marcas', {
      select: 'id,nome',
      order: 'nome.asc',
    }).catch(() => []),
    restGet(base, headers, 'banners', {
      select: COLUNAS_BANNER,
      ativo: 'eq.true',
      order: 'ordem.asc',
    }).catch(() => []),
    buscarUnidades(base, headers),
  ]);

  return {
    categorias,
    marcas,
    produtos: [],
    promocoes: [],
    banners: bannersVigentes(banners),
    unidades,
  };
}

async function main() {
  const { url, key } = await credenciais();
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    Accept: 'application/json',
  };

  const snapshot = (await buscarSnapshot(url, headers)) ??
    (await fallback(url, headers));

  if (!Array.isArray(snapshot.marcas) || snapshot.marcas.length === 0) {
    snapshot.marcas = await restGet(url, headers, 'marcas', {
      select: 'id,nome',
      order: 'nome.asc',
    }).catch(() => []);
  }

  let produtos = [];
  try {
    produtos = await buscarProdutos(url, headers, snapshot);
  } catch (erro) {
    console.warn(`Aviso: catálogo público indisponível (${erro.message}).`);
  }

  const produtosSnapshot = Array.isArray(snapshot.produtos)
    ? snapshot.produtos
    : [];
  const produtosHome = produtosSnapshot.length > 0
    ? produtosSnapshot.slice(0, 50)
    : produtos.slice(0, 50);

  if (produtos.length === 0) {
    produtos = produtosHome;
  }

  if (produtos.length === 0) {
    console.warn('Nenhum produto público retornado; nada foi gravado.');
    return;
  }

  const promocoes = Array.isArray(snapshot.promocoes) &&
      snapshot.promocoes.length > 0
    ? snapshot.promocoes.slice(0, 20)
    : produtos.filter((p) => p.em_promocao === true).slice(0, 20);

  const categorias = Array.isArray(snapshot.categorias)
    ? snapshot.categorias
    : [];
  const banners = bannersVigentes(snapshot.banners);
  const unidades = Array.isArray(snapshot.unidades) ? snapshot.unidades : [];
  const versao = typeof snapshot.versao === 'string' && snapshot.versao
    ? snapshot.versao
    : new Date().toISOString();

  const catalogo = {
    versao,
    categorias,
    produtos: produtosHome,
    promocoes,
    banners,
    unidades,
  };

  const produtosDoc = {
    versao,
    total: produtos.length,
    produtos,
  };

  await mkdir(saida, { recursive: true });
  await writeFile(
    join(saida, 'catalogo.json'),
    JSON.stringify(catalogo),
    'utf8',
  );
  await writeFile(
    join(saida, 'produtos.json'),
    JSON.stringify(produtosDoc),
    'utf8',
  );

  console.log(
    `Catálogo gerado: ${produtos.length} produtos, ` +
      `${categorias.length} categorias, ${banners.length} banners, ` +
      `${unidades.length} lojas em ${saida}.`,
  );
}

main().catch((erro) => {
  console.warn(`Aviso: catálogo estático não gerado (${erro.message}).`);
  process.exitCode = 0;
});
