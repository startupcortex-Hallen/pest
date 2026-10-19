# Pagamentos reais (PagBank) — Passo a passo

A loja agora cobra de verdade: **PIX, cartão de crédito, cartão de débito (3DS)
e boleto**, com confirmação automática via webhook e comprovante no painel
admin e no pedido do cliente.

## 1. Criar a conta e pegar o token

1. Crie a conta no portal dev do PagBank (aceita **CPF** para começar e depois
   migra os dados para CNPJ sem refazer a integração):
   https://portaldev.pagbank.com.br
2. No iBanking, gere o **token de acesso** da conta
   (https://developer.pagbank.com.br → Obter access token).
3. Cadastre uma **chave PIX** na conta (obrigatório para gerar QR Code).

## 2. Aplicar os SQLs no banco

No SQL Editor do Supabase (ou `supabase db push`), nesta ordem:

1. `supabase/migrations/20261018120000_schema_faltante_v2.sql`
   - cria as tabelas de academia/nutrição que faltavam, colunas
     (`unidades.latitude/longitude`, `produtos.vendas/frete_gratis/...`),
     FKs, RLS das tabelas novas, buckets do Storage e o trigger de perfil.
   - no final imprime um **relatório de auditoria de RLS** (tabela, RLS ligada, qtd. policies).
2. `supabase/migrations/20261017120000_pagamentos_gateway.sql`
   - cria `pagamentos` / `pagamentos_eventos`, vincula pedidos, RLS, realtime
   - **revoga** do cliente as RPCs antigas `confirmar_pagamento` e
     `processar_pagamento_cartao` (fim do "Já paguei" — confirmação agora
     só pelo webhook assinado).

> O segundo script precisa rodar **por último** entre os de pagamento.
> Depois dele, rode também `20261018130000_revogar_rpc_publicas.sql`, que
> fecha o furo das funções antigas (EXECUTE herdado de PUBLIC).

## 3. Configurar secrets e publicar as Edge Functions

```bash
# na pasta o_pest_shop
supabase login
supabase link --project-ref SEU_PROJECT_REF

supabase secrets set PAGBANK_TOKEN=SEU_TOKEN_AQUI PAGBANK_ENV=sandbox

supabase functions deploy pagamentos
supabase functions deploy pagamentos-webhook --no-verify-jwt
```

> O webhook precisa ser publicado com `--no-verify-jwt` (o PagBank não envia
> JWT). A segurança dele é a assinatura `x-authenticity-token` (SHA-256 do
> token da conta + payload), validada dentro da função.

O app envia automaticamente `notification_urls` apontando para
`https://SEU_PROJECT.supabase.co/functions/v1/pagamentos-webhook`.

## 4. Testar no sandbox

- Use os cartões de teste do PagBank:
  https://developer.pagbank.com.br/docs/cartoes-de-teste
- PIX e boleto têm simuladores no sandbox (Simulador de pagamento).
- O webhook também pode ser reenviado manualmente: gere o header
  `x-authenticity-token` = `sha256(PAGBANK_TOKEN + "-" + corpo_exato)`.

## 5. Ir para produção

1. Solicite a homologação da conta sandbox no portal dev.
2. Depois de aprovada, atualize os dados da conta para CNPJ (se aplicável).
3. Troque os secrets:
   ```bash
   supabase secrets set PAGBANK_TOKEN=TOKEN_DE_PRODUCAO PAGBANK_ENV=production
   ```
4. Nenhuma alteração de código é necessária — as URLs de produção são
   selecionadas pelo `PAGBANK_ENV`.

## Onde o comprovante aparece

- **Cliente**: Meus Pedidos → Detalhe do pedido → "Comprovante de pagamento"
  (método, status, IDs, PIX/boleto/cartão, botão copiar e abrir boleto em PDF).
- **Admin**: Admin → Pedidos → expandir o pedido → mesmo comprovante + linha
  de pagamento no resumo do card ("PIX • pago", "Boleto • aguardando" etc.).

## Observações de segurança

- **Cartão de débito exige 3DS** e o **crédito também está com 3DS obrigatório**
  (proteção contra cartão clonado/chargeback). O SDK do PagBank abre o desafio
  do banco no navegador — funciona no **web**; PIX/boleto funcionam em qualquer
  plataforma.
- Os dados do cartão são criptografados **no navegador** com a chave pública do
  PagBank (RSA) — o número do cartão nunca é salvo no nosso banco. Cartões
  "salvos" guardam apenas o token do gateway (`CARD_...`), bandeira e últimos 4;
  o **CVV nunca é armazenado** (pedido a cada compra).
- **CPF** é validado (dígito verificador) no app e no servidor. Nos cartões
  salvos guardamos só o CPF mascarado (`***.456.789-**`); o CPF completo fica
  apenas em `perfis` (LGPD).
- **Rate limit**: a Edge Function limita 5 cobranças por 10 min e 3 tentativas
  de cartão por 15 min por usuário (HTTP 429) — proteção contra teste de cartão.
- **CORS restrito** ao domínio da loja + localhost (ajuste com o secret
  `ALLOWED_ORIGINS=https://seudominio.com` se mudar de domínio).
- **Webhook** valida a assinatura `x-authenticity-token` (SHA-256) e é
  idempotente; sem `PAGBANK_TOKEN` configurado ele recusa tudo (fail closed).
- Boleto libera o pedido só após a compensação (1–2 dias úteis) — o status
  muda sozinho pelo webhook.
- Valores são **recalculados no servidor** a partir dos pedidos — o app nunca
  envia preço.

## Adicionar cartões salvos

O cartão é salvo durante o pagamento com crédito, marcando **"Salvar cartão
para a próxima compra"**. A tela `/cartoes` só exibe/remove cartões — cartões
antigos (criados manualmente, sem token do gateway) aparecem como
"Reativar no pagamento" e não são cobrados.
