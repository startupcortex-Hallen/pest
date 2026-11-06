# Go-live dos pagamentos — passo a passo

## Pré-requisitos

- [ ] Conta PagBank aprovada para e-commerce e homologada.
- [ ] Token de produção (ou sandbox para o primeiro teste).
- [ ] Chave PIX cadastrada no PagBank.
- [ ] Projeto Supabase `rudmeztnxsxipmfytuem` acessível.
- [ ] Domínio com HTTPS (para homologação do gateway).
- [ ] Supabase CLI (`npm i -g supabase` ou `npx supabase`).

## 1. Aplicar o banco (SQL Editor)

Rode nesta ordem:

0. `sql_schema_completo.sql` (schema base; obrigatório em base vazia)
1. `supabase/CONSOLIDACAO_FINAL.sql`
2. `supabase/migrations/20261018120000_schema_faltante_v2.sql`
3. `supabase/FASE2_ENDERECOS_FRETE.sql`
4. `supabase/migrations/20261017120000_pagamentos_gateway.sql`
5. `supabase/migrations/20261018130000_revogar_rpc_publicas.sql`
6. `supabase/migrations/20261019120000_pagamentos_blindagem.sql`
7. `supabase/migrations/20261027120000_frete_distancia_parceiros_ml.sql`
   (opcional; rode depois do 6 para frete por distância e painel de parceiros)
8. `supabase/migrations/20261030120000_admin_correcoes.sql`
   (corrige o CRUD de assinaturas no admin, leitura de perfis pelo gestor e a
   exclusão segura de usuários)
9. `supabase/migrations/20261030130000_frete_correios.sql`
   (frete por distância + peso e bloqueio de distância fora das faixas)
10. `supabase/migrations/20261030140000_frete_correios_melhor_envio.sql`
    (opções Correios/Melhor Envio e checkout com cotação validada)
11. `supabase/migrations/20261102120000_blindagem_compra_admin.sql`
    (obrigatório: checkout idempotente, valor revalidado, escrita direta
    bloqueada, histórico/auditoria e lista paginada de pedidos)
12. `supabase/migrations/20261103120000_correios_etiquetas.sql`
    (obrigatório para etiquetas oficiais: endereço estruturado, envios,
    bucket `etiquetas`, checkout v5, NF-e e status postado/em trânsito)
13. `supabase/migrations/20261103130000_pedidos_codigo_objeto.sql`
14. `supabase/migrations/20261103140000_pedidos_status_envio.sql`
15. `supabase/migrations/20261103150000_pedido_historico_perfil_fk.sql`
16. `supabase/migrations/20261104120000_seguranca_producao.sql`
    (obrigatório: checkout v6, LGPD, último admin, cupom por cliente,
    dashboard completo, cron versionado e RLS de perfis)
17. `supabase/migrations/20261104130000_cobranca_lock.sql`
18. `supabase/migrations/20261104140000_producao_final.sql`
    (obrigatório: storage de avatar, bloqueio de conta e revogação das RPCs
    antigas de checkout)
19. `supabase/migrations/20261104150000_fix_rls_recursao.sql`
    (obrigatório: RLS de perfis/pedidos/envios sem recursão)
20. `supabase/migrations/20261104160000_checkout_endereco_servidor.sql`
    (obrigatório: frete por distância só com endereço salvo e coordenadas do
    servidor)
21. `supabase/migrations/20261104170000_estoque_manual_auditavel.sql`
22. `supabase/migrations/20261104180000_banners.sql`
23. `supabase/migrations/20261104190000_admin_pedidos_filtros.sql`
24. `supabase/migrations/20261104200000_motivo_cancelamento.sql`
25. `supabase/migrations/20261105120000_hardening_escalabilidade.sql`
    (obrigatório: preço calculado no banco, lock atômico de cobrança,
    processamento serializado, views públicas, feature flags e índices.
    Rodar primeiro em staging.)

> Depois da migration 18, somente `finalizar_checkout_v6` pode ser chamado pelo
> app. As versões v2/v3/v4/v5 e o checkout base ficam restritas ao uso interno.

Confira no final:

```sql
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'pagamentos'
   and column_name in ('revisao_manual','revisao_motivo','estornado_em');

select proname, proacl from pg_proc
 where proname in ('confirmar_pagamento','processar_pagamento_cartao','cancelar_pendentes_expirados_todos');
```

`confirmar_pagamento` e `processar_pagamento_cartao` **não** podem ter
`authenticated` na ACL. Devem ser exclusivos de `service_role`.

Confira também a parte de etiquetas:

```sql
select to_regclass('public.envios') as envios,
       to_regclass('public.envio_eventos') as envio_eventos;

select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'pedidos'
   and column_name in ('endereco_rua','destinatario_cpf','etiqueta_status','codigo_objeto');
```

## 2. Login e link do projeto

```bash
cd o_pest_shop
npx supabase login
npx supabase link --project-ref rudmeztnxsxipmfytuem
```

O login abre o navegador. Se estiver em CI, use:

```bash
npx supabase login --token SEU_SUPABASE_ACCESS_TOKEN
```

## 3. Configurar secrets

### 3.0 Dados que o dono precisa enviar (PagBank)

Sem estes dados o app só funciona em simulação; nenhuma cobrança real é feita:

- Token de **produção** da conta PagBank (enviar por gerenciador de senhas).
- Confirmação de que a conta está aprovada para **e-commerce**.
- PIX, boleto, crédito, débito e **3DS** habilitados na conta.
- Chave PIX cadastrada na conta PagBank.
- CNPJ/razão social, endereço, e-mail e telefone de contato/antifraude.
- Dados bancários de repasse já configurados no PagBank.
- Domínio público do site com **HTTPS** para a homologação.
- Termos de uso, política de privacidade e política de troca/devolução publicados.

Enquanto esses dados não chegarem, mantenha `SIMULACAO_PAGAMENTO=true`. A tela
de pagamento mostra o aviso de simulação e o botão “Simular pagamento aprovado”.

```bash
npx supabase secrets set \
  PAGBANK_TOKEN=SEU_TOKEN \
  PAGBANK_ENV=sandbox \
  ALLOWED_ORIGINS=https://seudominio.com,https://startupcortex-hallen.github.io
```

- `PAGBANK_ENV=sandbox` usa `sandbox.api.pagseguro.com`.
- `PAGBANK_ENV=production` usa `api.pagseguro.com`.
- `ALLOWED_ORIGINS` deve conter o domínio final **sem barra no fim**.
- Para testar no emulador/Web local, inclua `http://localhost:8080`.

### 3.1 Correios (etiqueta/rastreio)

Quando o cliente entregar o contrato/CWS:

```bash
npx supabase secrets set \
  CORREIOS_ENV=homolog \
  CORREIOS_USUARIO=... \
  CORREIOS_CODIGO_ACESSO=... \
  CORREIOS_CNPJ=... \
  CORREIOS_CONTRATO=... \
  CORREIOS_CARTAO_POSTAGEM=... \
  CORREIOS_SERVICOS=03298:PAC,03220:SEDEX
```

Sem as credenciais, use `CORREIOS_SIMULACAO=true` para testar o fluxo.
Detalhes: [`CORREIOS_ETIQUETAS.md`](CORREIOS_ETIQUETAS.md).

## 4. Publicar as funções

```bash
npx supabase functions deploy pagamentos
npx supabase functions deploy pagamentos-webhook --no-verify-jwt
npx supabase functions deploy catalogo-publico --no-verify-jwt
npx supabase functions deploy frete-cotacao
npx supabase functions deploy frete-etiqueta
npx supabase functions deploy frete-rastreio --no-verify-jwt
```

O webhook **precisa** de `--no-verify-jwt`. Sem isso o PagBank recebe 401.

Verifique que saíram do 404:

```bash
curl -i -X POST \
  -H "apikey: SUA_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' \
  https://rudmeztnxsxipmfytuem.supabase.co/functions/v1/pagamentos
```

Resposta esperada: `401` (faça login) ou `422` (dados inválidos), **nunca
404**.

## 5. Teste sandbox

1. Crie/complete o perfil com **nome completo**, **CPF válido** e telefone.
2. Coloque um produto no carrinho e finalize o pedido.
3. Gere PIX e pague no simulador do PagBank.
4. Gere boleto e pague no simulador.
5. No Web, pague com os cartões de teste do PagBank (crédito e débito/3DS).
6. Confira:
   - [ ] `pagamentos.status` mudou para `pago`;
   - [ ] pedido saiu de `pendente` para `em_preparo`;
   - [ ] estoque baixou **uma única vez**;
   - [ ] cupom foi consumido uma única vez;
   - [ ] comprovante aparece em Meus Pedidos e no Admin;
   - [ ] webhook respondeu 200 e o evento ficou em `pagamentos_eventos`;
   - [ ] cancelamento de pedido pago gerou estorno no PagBank.

### Reenvio manual do webhook (sandbox)

```bash
BODY='{"id":"ORDE_...","charges":[{"id":"CHAR_...","status":"PAID"}]}'
TOKEN='SEU_PAGBANK_TOKEN'
SIG=$(printf '%s-%s' "$TOKEN" "$BODY" | sha256sum | cut -d' ' -f1)
curl -i -X POST \
  -H "Content-Type: application/json" \
  -H "x-authenticity-token: $SIG" \
  --data "$BODY" \
  https://rudmeztnxsxipmfytuem.supabase.co/functions/v1/pagamentos-webhook
```

## 6. Produção

1. Homologue a conta no portal dev do PagBank.
2. Troque os secrets:

```bash
npx supabase secrets set \
  PAGBANK_TOKEN=TOKEN_DE_PRODUCAO \
  PAGBANK_ENV=production \
  SIMULACAO_PAGAMENTO=false
```

3. Configure a conciliação/rastreio (secret + Vault + cron). O cron já está
   versionado na migration `20261104120000_seguranca_producao.sql`; ele só agenda
   quando `o_pest_project_url` e `o_pest_conciliacao_secret` existem no Vault.
   Gere um segredo longo e rode:

```sql
select vault.create_secret('https://SEU_PROJECT.supabase.co', 'o_pest_project_url');
select vault.create_secret('SEGREDO_LONGO', 'o_pest_conciliacao_secret');
```

4. Reimplante as funções (secrets são lidos em runtime, mas reimplante garante
   o bundle atual):

```bash
npx supabase functions deploy pagamentos
npx supabase functions deploy pagamentos-webhook --no-verify-jwt
npx supabase functions deploy catalogo-publico --no-verify-jwt
npx supabase functions deploy frete-cotacao
npx supabase functions deploy frete-etiqueta
npx supabase functions deploy frete-rastreio --no-verify-jwt
```

5. Faça um pedido real de **R$ 1,00** com PIX.
6. Faça um pedido real de **R$ 1,00** com cartão e **estorne** pelo Admin.
7. Confira o repasse no PagBank e a baixa no Supabase.

## 7. Se a função continuar 404

- Confirme o project ref: `npx supabase projects list`.
- Confirme o link: `npx supabase link --project-ref rudmeztnxsxipmfytuem`.
- Liste as funções no dashboard: **Edge Functions** deve mostrar
  `pagamentos` e `pagamentos-webhook`.
- Veja os logs: `npx supabase functions logs pagamentos`.
- 404 em **todas** as rotas REST indica projeto pausado/removido; verifique o
  dashboard.

## 8. Checklist de aceite

- [ ] PIX com CPF ausente retorna erro claro (não gera cobrança).
- [ ] Boleto não é cancelado antes do vencimento.
- [ ] Pagamento aprovado libera o pedido ou entra em revisão manual.
- [ ] Estorno no Admin devolve o dinheiro no gateway.
- [ ] Cancelamento do cliente em pedido pago estorna.
- [ ] Webhook com erro devolve 500 e é reenviado.
- [ ] Cupom e estoque voltam ao cancelar.
- [ ] CORS só aceita o domínio da loja.
- [ ] Nenhuma RPC de confirmação manual está liberada para o cliente.
- [ ] Logs sem PAN/CVV/token.
- [ ] Endereço salvo com latitude/longitude e edição funcionando.
- [ ] Loja com modo `distancia` cobra taxa base + km e respeita o raio máximo.
- [ ] Loja com `faixas` usa a faixa correta; retirada continua grátis.
- [ ] Checkout recalcula distância/taxa no servidor e grava `distancia_km`.
