import { adminClient, buscarIntegracao, mlFetch, statusPedidoMl } from '../_shared/mercadolivre.ts';

type Admin = ReturnType<typeof adminClient>;

function idDoResource(resource: string): string | null {
  const partes = resource.split('?')[0].split('/').filter(Boolean);
  return partes.length > 0 ? partes[partes.length - 1] : null;
}

async function enderecoDoEnvio(
  admin: Admin,
  integracao: any,
  shippingId: number | null | undefined,
): Promise<{ texto: string | null; cep: string | null; nome: string | null; telefone: string | null }> {
  if (!shippingId) return { texto: null, cep: null, nome: null, telefone: null };
  try {
    const shipment = await mlFetch(
      admin,
      integracao,
      `/shipments/${shippingId}?views=destination`,
      { headers: { 'X-Api-Version': '2' } },
    );
    const end = shipment?.receiver_address ?? {};
    const rua = end.street_name ?? end.address_line ?? '';
    const numero = end.street_number ?? '';
    const complemento = end.comment ?? '';
    const bairro = end.neighborhood?.name ?? '';
    const cidade = end.city?.name ?? '';
    const uf = end.state?.name ?? end.state?.id ?? '';
    const cep = String(end.zip_code ?? '').replace(/\D/g, '');
    const texto = [
      rua && `${rua}${numero ? `, ${numero}` : ''}`,
      complemento,
      bairro,
      cidade && `${cidade}${uf ? ` - ${uf}` : ''}`,
      cep && `CEP ${cep}`,
    ]
      .filter(Boolean)
      .join(', ');
    return {
      texto: texto || null,
      cep: cep || null,
      nome: end.receiver_name ?? null,
      telefone: end.receiver_phone ?? null,
    };
  } catch (e) {
    console.warn('Não foi possível buscar endereço do envio ML:', e);
    return { texto: null, cep: null, nome: null, telefone: null };
  }
}

async function processarPedido(
  admin: Admin,
  integracao: any,
  orderId: string,
): Promise<number> {
  const order = await mlFetch(
    admin,
    integracao,
    `/orders/${orderId}?x-format-new=true`,
  );

  const existente = await admin
    .from('ml_pedidos')
    .select('*')
    .eq('ml_order_id', Number(order.id))
    .maybeSingle();

  if (existente.data?.pedido_id) {
    const status = statusPedidoMl(order);
    await admin
      .from('pedidos')
      .update({
        status,
        codigo_rastreio: order.shipping?.tracking_number ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', existente.data.pedido_id);
    await admin
      .from('ml_pedidos')
      .update({
        ml_status: order.status ?? null,
        ml_status_detail: order.status_detail ?? null,
        shipping_id: order.shipping?.id ?? null,
        raw: order,
        last_sync_at: new Date().toISOString(),
      })
      .eq('id', existente.data.id);
    return Number(existente.data.pedido_id);
  }

  const itens: Array<{
    produto: any;
    quantidade: number;
    preco: number;
    cor: string | null;
  }> = [];

  for (const oi of order.order_items ?? []) {
    const sku = oi?.item?.seller_sku ?? null;
    const itemId = oi?.item?.id ?? null;
    let produto: any = null;

    if (sku) {
      const { data } = await admin
        .from('produtos')
        .select('*')
        .eq('unidade_id', integracao.unidade_id)
        .eq('sku', sku)
        .maybeSingle();
      produto = data;
    }
    if (!produto && itemId) {
      const { data } = await admin
        .from('produtos')
        .select('*')
        .eq('unidade_id', integracao.unidade_id)
        .eq('ml_item_id', itemId)
        .maybeSingle();
      produto = data;
    }
    if (!produto && itemId) {
      const { data: anuncio } = await admin
        .from('ml_anuncios')
        .select('produto_id')
        .eq('ml_item_id', itemId)
        .maybeSingle();
      if (anuncio?.produto_id) {
        const { data } = await admin
          .from('produtos')
          .select('*')
          .eq('id', anuncio.produto_id)
          .maybeSingle();
        produto = data;
      }
    }

    if (!produto) {
      throw new Error(
        `Pedido ${order.id}: item ${oi?.item?.id ?? '?'} (SKU ${sku ?? 'sem SKU'}) não está vinculado a um produto da loja.`,
      );
    }

    const variacao = (oi?.item?.variation_attributes ?? []) as any[];
    const cor =
      variacao.find((v) => v?.id === 'COLOR' || v?.name === 'Cor')?.value_name ??
      null;

    itens.push({
      produto,
      quantidade: Number(oi.quantity ?? 1),
      preco: Number(oi.unit_price ?? 0),
      cor,
    });
  }

  const endereco = await enderecoDoEnvio(admin, integracao, order.shipping?.id);
  const total = Number(order.total_amount ?? order.paid_amount ?? 0);
  const status = statusPedidoMl(order);

  const { data: pedido, error } = await admin
    .from('pedidos')
    .insert({
      user_id: null,
      unidade_id: integracao.unidade_id,
      status,
      total,
      taxa_entrega: 0,
      tipo_entrega: 'entrega',
      endereco_entrega: endereco.texto,
      cep_entrega: endereco.cep,
      origem: 'mercadolivre',
      canal: 'mercadolivre',
      ml_order_id: Number(order.id),
      comprador_nome:
        endereco.nome ??
        `Comprador Mercado Livre #${order.buyer?.id ?? order.id}`,
      comprador_telefone: endereco.telefone,
      codigo_rastreio: order.shipping?.tracking_number ?? null,
      created_at: order.date_created ?? new Date().toISOString(),
      pix_copia_cola: null,
      pagamento: 'mercadolivre',
    })
    .select('id')
    .single();

  if (error || !pedido) {
    throw new Error(`Falha ao criar pedido ML ${order.id}: ${error?.message}`);
  }

  for (const item of itens) {
    const { error: itemError } = await admin.from('pedido_itens').insert({
      pedido_id: pedido.id,
      produto_id: item.produto.id,
      quantidade: item.quantidade,
      preco_unitario: item.preco,
      cor: item.cor,
    });
    if (itemError) throw new Error(itemError.message);

    const estoqueAtual = Number(item.produto.estoque ?? 0);
    const novoEstoque = Math.max(estoqueAtual - item.quantidade, 0);
    await admin
      .from('produtos')
      .update({ estoque: novoEstoque })
      .eq('id', item.produto.id);

    await admin.from('estoque_movimentacoes').insert({
      produto_id: item.produto.id,
      pedido_id: pedido.id,
      tipo: 'venda',
      quantidade: -item.quantidade,
      motivo: `Venda Mercado Livre (pedido ${order.id})`,
      criado_por: null,
    });
  }

  await admin.from('pedido_historico').insert({
    pedido_id: pedido.id,
    status,
    alterado_por: null,
  });

  await admin.from('ml_pedidos').insert({
    pedido_id: pedido.id,
    integracao_id: integracao.id,
    ml_order_id: Number(order.id),
    ml_pack_id: order.pack_id ?? null,
    ml_status: order.status ?? null,
    ml_status_detail: order.status_detail ?? null,
    shipping_id: order.shipping?.id ?? null,
    raw: order,
    last_sync_at: new Date().toISOString(),
  });

  return Number(pedido.id);
}

async function processarShipment(
  admin: Admin,
  integracao: any,
  shipmentId: string,
): Promise<void> {
  const shipment = await mlFetch(admin, integracao, `/shipments/${shipmentId}`);
  const { data: vinculo } = await admin
    .from('ml_pedidos')
    .select('*')
    .eq('shipping_id', Number(shipmentId))
    .maybeSingle();
  if (!vinculo?.pedido_id) return;

  const status = String(shipment.status ?? '');
  let novo: string | null = null;
  if (status === 'shipped') novo = 'saiu_para_entrega';
  if (status === 'delivered') novo = 'entregue';
  if (status === 'cancelled') novo = 'cancelado';
  if (!novo) return;

  await admin
    .from('pedidos')
    .update({
      status: novo,
      codigo_rastreio: shipment.tracking_number ?? null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', vinculo.pedido_id);

  await admin.from('pedido_historico').insert({
    pedido_id: vinculo.pedido_id,
    status: novo,
    alterado_por: null,
  });
}

Deno.serve(async (req) => {
  const secret = Deno.env.get('ML_CRON_SECRET');
  if (!secret) {
    return new Response(JSON.stringify({ erro: 'ML_CRON_SECRET não configurado' }), {
      status: 503,
      headers: { 'content-type': 'application/json' },
    });
  }
  if (req.headers.get('x-ml-cron-secret') !== secret) {
    return new Response(JSON.stringify({ erro: 'não autorizado' }), {
      status: 401,
      headers: { 'content-type': 'application/json' },
    });
  }

  const admin = adminClient();
  const { data: eventos, error } = await admin
    .from('ml_eventos')
    .select('*')
    .eq('status', 'pendente')
    .lt('attempts', 8)
    .order('created_at', { ascending: true })
    .limit(25);
  if (error) {
    return new Response(JSON.stringify({ erro: error.message }), { status: 500 });
  }

  let processados = 0;
  const erros: any[] = [];

  for (const evento of eventos ?? []) {
    try {
      const { data: integracao } = await admin
        .from('integracoes_loja')
        .select('*')
        .eq('ml_user_id', evento.ml_user_id)
        .eq('plataforma', 'mercadolivre')
        .maybeSingle();
      if (!integracao) throw new Error('Integração não encontrada para o user_id do evento.');

      const id = idDoResource(String(evento.resource ?? ''));
      if (!id) throw new Error('Resource sem ID.');

      if (evento.topic === 'orders_v2' || evento.topic === 'orders') {
        await processarPedido(admin, integracao, id);
      } else if (evento.topic === 'items') {
        const item = await mlFetch(admin, integracao, `/items/${id}`);
        await admin
          .from('ml_anuncios')
          .update({
            status: item.status ?? null,
            permalink: item.permalink ?? null,
            raw: item,
            last_sync_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq('ml_item_id', id);
        await admin
          .from('produtos')
          .update({ ml_status: item.status ?? null, ml_permalink: item.permalink ?? null })
          .eq('ml_item_id', id);
      } else if (evento.topic === 'shipments') {
        await processarShipment(admin, integracao, id);
      }

      await admin
        .from('ml_eventos')
        .update({
          status: 'processado',
          attempts: Number(evento.attempts ?? 0) + 1,
          processed_at: new Date().toISOString(),
          erro: null,
        })
        .eq('id', evento.id);
      processados++;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      const tentativas = Number(evento.attempts ?? 0) + 1;
      erros.push({ id: evento.id, erro: msg });
      await admin
        .from('ml_eventos')
        .update({
          status: tentativas >= 8 ? 'erro' : 'pendente',
          attempts: tentativas,
          erro: msg,
          processed_at: new Date().toISOString(),
        })
        .eq('id', evento.id);
    }
  }

  return new Response(
    JSON.stringify({ ok: true, processados, erros }),
    { status: 200, headers: { 'content-type': 'application/json' } },
  );
});
