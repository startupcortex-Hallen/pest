import { createClient } from 'npm:@supabase/supabase-js@2';
import { getCorsHeaders, json } from '../_shared/cors.ts';
import {
  adminClient,
  buscarIntegracao,
  mlFetch,
} from '../_shared/mercadolivre.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

type Produto = Record<string, any>;

function precoAtual(p: Produto): number {
  const promo = Number(p.preco_promocional ?? 0);
  if (p.em_promocao === true && promo > 0) return promo;
  return Number(p.preco ?? 0);
}

function imagens(p: Produto): string[] {
  const raw = p.url_imagem;
  const lista: string[] = [];
  if (Array.isArray(raw)) {
    for (const u of raw) if (typeof u === 'string' && u.startsWith('https://')) lista.push(u);
  } else if (typeof raw === 'string' && raw.startsWith('https://')) {
    lista.push(raw);
  }
  return [...new Set(lista)].slice(0, 6);
}

function atributos(p: Produto): any[] {
  const base: any[] = [];
  if (p.sku) base.push({ id: 'SELLER_SKU', value_name: String(p.sku) });
  const condicao = String(p.condicao ?? 'new');
  base.push({
    id: 'ITEM_CONDITION',
    value_name:
      condicao === 'used'
        ? 'Usado'
        : condicao === 'not_specified'
          ? 'Não especificado'
          : 'Novo',
  });
  if (Array.isArray(p.ml_attributes)) {
    for (const attr of p.ml_attributes) {
      if (attr && typeof attr === 'object') base.push(attr);
    }
  }
  return base;
}

async function publicarProduto(
  admin: ReturnType<typeof adminClient>,
  integracao: any,
  produto: Produto,
): Promise<Record<string, any>> {
  const itemId = produto.ml_item_id as string | null;
  const price = precoAtual(produto);
  const estoque = Math.max(Number(produto.estoque ?? 0), 0);

  if (price <= 0) throw new Error('Produto sem preço válido.');
  if (!produto.sku) throw new Error('Informe o SKU do produto.');
  if (!produto.ml_category_id) throw new Error('Informe a categoria do Mercado Livre.');

  if (itemId) {
    const atualizado = await mlFetch(admin, integracao, `/items/${itemId}`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        price,
        available_quantity: estoque,
        attributes: atributos(produto),
      }),
    });

    await admin
      .from('produtos')
      .update({
        ml_status: atualizado.status ?? null,
        ml_permalink: atualizado.permalink ?? produto.ml_permalink ?? null,
        ml_last_sync_at: new Date().toISOString(),
        ml_sync_error: null,
      })
      .eq('id', produto.id);

    await admin.from('ml_anuncios').upsert(
      {
        unidade_id: produto.unidade_id,
        produto_id: produto.id,
        integracao_id: integracao.id,
        ml_item_id: itemId,
        category_id: produto.ml_category_id,
        domain_id: produto.ml_domain_id ?? null,
        listing_type: produto.ml_listing_type ?? null,
        status: atualizado.status ?? null,
        permalink: atualizado.permalink ?? null,
        raw: atualizado,
        last_sync_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        erro: null,
      },
      { onConflict: 'unidade_id,produto_id' },
    );

    return {
      ok: true,
      ml_item_id: itemId,
      permalink: atualizado.permalink ?? null,
      status: atualizado.status ?? null,
      atualizado: true,
    };
  }

  const pictures = imagens(produto);
  if (pictures.length === 0) {
    throw new Error('Produto precisa de pelo menos uma imagem HTTPS pública.');
  }

  const payload: Record<string, any> = {
    title: String(produto.nome ?? '').slice(0, 60),
    category_id: String(produto.ml_category_id),
    price,
    currency_id: 'BRL',
    available_quantity: estoque,
    buying_mode: 'buy_it_now',
    condition: String(produto.condicao ?? 'new'),
    listing_type_id: String(produto.ml_listing_type ?? 'gold_special'),
    pictures: pictures.map((source) => ({ source })),
    attributes: atributos(produto),
    shipping: {
      mode: produto.ml_shipping_mode ?? 'not_specified',
      local_pick_up: false,
      free_shipping: produto.frete_gratis === true,
    },
    channels: ['marketplace'],
  };

  const criado = await mlFetch(admin, integracao, '/items', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (produto.descricao && String(produto.descricao).trim().length > 0) {
    try {
      await mlFetch(admin, integracao, `/items/${criado.id}/description`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ plain_text: String(produto.descricao).slice(0, 50000) }),
      });
    } catch (e) {
      console.warn('Falha ao enviar descrição ML:', e);
    }
  }

  await admin
    .from('produtos')
    .update({
      ml_item_id: criado.id,
      ml_status: criado.status ?? null,
      ml_permalink: criado.permalink ?? null,
      ml_last_sync_at: new Date().toISOString(),
      ml_sync_error: null,
    })
    .eq('id', produto.id);

  await admin.from('ml_anuncios').upsert(
    {
      unidade_id: produto.unidade_id,
      produto_id: produto.id,
      integracao_id: integracao.id,
      ml_item_id: criado.id,
      category_id: produto.ml_category_id,
      domain_id: produto.ml_domain_id ?? null,
      listing_type: produto.ml_listing_type ?? null,
      status: criado.status ?? null,
      permalink: criado.permalink ?? null,
      raw: criado,
      last_sync_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      erro: null,
    },
    { onConflict: 'unidade_id,produto_id' },
  );

  return {
    ok: true,
    ml_item_id: criado.id,
    permalink: criado.permalink ?? null,
    status: criado.status ?? null,
    criado: true,
  };
}

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405, cors);

  try {
    const anon = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      auth: { persistSession: false },
    });
    const { data: auth, error: authError } = await anon.auth.getUser();
    if (authError || !auth.user) return json({ erro: 'Faça login.' }, 401, cors);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? '');
    const admin = adminClient();

    const { data: perfil } = await admin
      .from('perfis')
      .select('funcao, unidade_id')
      .eq('id', auth.user.id)
      .maybeSingle();

    const podeUnidade = (unidadeId: number) =>
      perfil?.funcao === 'admin' ||
      ((perfil?.funcao === 'gestor' || perfil?.funcao === 'atendente') &&
        Number(perfil?.unidade_id) === unidadeId);

    if (action === 'desconectar') {
      const unidadeId = Number(body.unidade_id);
      if (!Number.isFinite(unidadeId) || !podeUnidade(unidadeId)) {
        return json({ erro: 'Sem permissão.' }, 403, cors);
      }
      await admin
        .from('integracoes_loja')
        .update({
          access_token: null,
          refresh_token: null,
          token_expira_em: null,
          refresh_expira_em: null,
          status: 'desconectado',
          erro: null,
          updated_at: new Date().toISOString(),
        })
        .eq('unidade_id', unidadeId)
        .eq('plataforma', 'mercadolivre');
      return json({ ok: true, status: 'desconectado' }, 200, cors);
    }

    if (action === 'sincronizar_lote') {
      const unidadeId = Number(body.unidade_id);
      if (!Number.isFinite(unidadeId) || !podeUnidade(unidadeId)) {
        return json({ erro: 'Sem permissão.' }, 403, cors);
      }
      const integracao = await buscarIntegracao(admin, unidadeId);
      if (!integracao || integracao.status !== 'conectado') {
        return json({ erro: 'Loja sem conta Mercado Livre conectada.' }, 422, cors);
      }
      const { data: produtos } = await admin
        .from('produtos')
        .select('*')
        .eq('unidade_id', unidadeId)
        .eq('ml_sync_enabled', true)
        .not('sku', 'is', null)
        .limit(100);

      let enviados = 0;
      const erros: any[] = [];
      for (const produto of produtos ?? []) {
        try {
          await publicarProduto(admin, integracao, produto);
          enviados++;
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          erros.push({ produto_id: produto.id, erro: msg });
          await admin
            .from('produtos')
            .update({ ml_sync_error: msg })
            .eq('id', produto.id);
        }
      }
      return json({ ok: true, enviados, erros }, 200, cors);
    }

    if (action === 'publicar' || action === 'sincronizar') {
      const produtoId = Number(body.produto_id);
      if (!Number.isFinite(produtoId)) {
        return json({ erro: 'produto_id inválido' }, 422, cors);
      }
      const { data: produto } = await admin
        .from('produtos')
        .select('*')
        .eq('id', produtoId)
        .maybeSingle();
      if (!produto) return json({ erro: 'Produto não encontrado.' }, 404, cors);
      if (!podeUnidade(Number(produto.unidade_id))) {
        return json({ erro: 'Sem permissão para esta loja.' }, 403, cors);
      }
      if (!produto.sku) {
        return json({ erro: 'Informe o SKU antes de publicar.' }, 422, cors);
      }
      if (!produto.ml_category_id) {
        return json({ erro: 'Informe a categoria do Mercado Livre.' }, 422, cors);
      }
      if (!produto.ml_sync_enabled) {
        await admin
          .from('produtos')
          .update({ ml_sync_enabled: true })
          .eq('id', produto.id);
      }

      const integracao = await buscarIntegracao(admin, Number(produto.unidade_id));
      if (!integracao || integracao.status !== 'conectado') {
        return json({ erro: 'Conecte a conta Mercado Livre desta loja primeiro.' }, 422, cors);
      }

      try {
        const resultado = await publicarProduto(admin, integracao, {
          ...produto,
          ml_sync_enabled: true,
        });
        return json(resultado, 200, cors);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await admin
          .from('produtos')
          .update({ ml_sync_error: msg })
          .eq('id', produto.id);
        await admin.from('ml_anuncios').upsert(
          {
            unidade_id: produto.unidade_id,
            produto_id: produto.id,
            integracao_id: integracao.id,
            erro: msg,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'unidade_id,produto_id' },
        );
        return json({ erro: msg }, 422, cors);
      }
    }

    return json({ erro: 'Ação desconhecida.' }, 422, cors);
  } catch (e) {
    console.error('ml-sync:', e);
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500, cors);
  }
});
