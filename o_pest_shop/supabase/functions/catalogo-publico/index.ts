// Catálogo público distribuível por CDN.
//
// Deploy:
//   supabase functions deploy catalogo-publico --no-verify-jwt
//
// Segurança:
//   - Não recebe nem devolve dados de usuário.
//   - Usa service_role apenas no servidor para ler as views públicas.
//   - Retorna somente produtos/lojas ativos e banners vigentes.
//
// Cache:
//   - Cloudflare/CDN pode cachear a URL por 60s (s-maxage).
//   - O app usa o snapshot como stale-while-revalidate e o checkout sempre
//     revalida preço/estoque no banco.

import { createClient } from 'npm:@supabase/supabase-js@2';
import { getCorsHeaders } from '../_shared/cors.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const CACHE_CONTROL =
  'public, max-age=30, s-maxage=60, stale-while-revalidate=300';

const PRODUTO_COLUNAS = [
  'id', 'nome', 'descricao', 'preco', 'preco_promocional', 'em_promocao',
  'url_imagem', 'categoria_id', 'marca_id', 'estoque', 'unidade_id', 'vendas',
  'frete_gratis', 'percentual_desconto', 'garantia', 'parcelas', 'cores',
  'sku', 'gtin', 'peso_kg', 'comprimento_cm', 'largura_cm', 'altura_cm',
  'condicao', 'ativo', 'created_at', 'categoria_nome', 'marca_nome',
  'unidade_nome',
].join(',');

function etagDe(texto: string): Promise<string> {
  return crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto))
    .then((d) => Array.from(new Uint8Array(d))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join(''));
}

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, OPTIONS' },
    });
  }
  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ erro: 'Método não permitido.' }), {
      status: 405,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });

  const [categorias, produtos, promocoes, banners, unidades] = await Promise.all([
    admin.from('categorias').select('id,nome,icone').order('nome'),
    admin
      .from('produtos_publicos')
      .select(PRODUTO_COLUNAS)
      .order('id', { ascending: true })
      .limit(50),
    admin
      .from('produtos_publicos')
      .select(PRODUTO_COLUNAS)
      .eq('em_promocao', true)
      .order('id', { ascending: true })
      .limit(20),
    admin
      .from('banners')
      .select('id,titulo,imagem_url,link_url,ordem,data_inicio,data_fim')
      .eq('ativo', true)
      .order('ordem')
      .order('id', { ascending: false }),
    admin
      .from('unidades_publicas')
      .select(
        'id,nome,slug,bairro,cidade,endereco,foto_url,logo_url,horario_seg,horario_ter,horario_qua,horario_qui,horario_sex,horario_sab,horario_dom,ordem,distancia,prazo_retirada_min,prazo_entrega_min',
      )
      .order('ordem', { ascending: true }),
  ]);

  const erro = [categorias, produtos, promocoes, banners, unidades]
    .find((r) => r.error)?.error;
  if (erro) {
    console.error('catalogo-publico:', erro.message);
    return new Response(JSON.stringify({ erro: 'Catálogo indisponível.' }), {
      status: 503,
      headers: {
        ...cors,
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      },
    });
  }

  const agora = Date.now();
  const bannersAtivos = ((banners.data ?? []) as Array<Record<string, unknown>>)
    .filter((b) => {
      const inicio = b['data_inicio'] ? Date.parse(String(b['data_inicio'])) : NaN;
      const fim = b['data_fim'] ? Date.parse(String(b['data_fim'])) : NaN;
      return (!Number.isFinite(inicio) || inicio <= agora) &&
        (!Number.isFinite(fim) || fim >= agora);
    });

  // O ETag é calculado só com os dados (sem timestamp), para permitir 304
  // de verdade. A versão textual muda a cada geração, mas não invalida o cache.
  const dados = {
    categorias: categorias.data ?? [],
    produtos: produtos.data ?? [],
    promocoes: promocoes.data ?? [],
    banners: bannersAtivos,
    unidades: unidades.data ?? [],
  };
  const etag = `"${await etagDe(JSON.stringify(dados))}"`;
  const corpo = JSON.stringify({
    versao: new Date().toISOString(),
    ...dados,
  });

  if (req.headers.get('if-none-match') === etag) {
    return new Response(null, {
      status: 304,
      headers: { ...cors, 'ETag': etag, 'Cache-Control': CACHE_CONTROL },
    });
  }

  return new Response(corpo, {
    status: 200,
    headers: {
      ...cors,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': CACHE_CONTROL,
      'ETag': etag,
      'X-Content-Type-Options': 'nosniff',
    },
  });
});
