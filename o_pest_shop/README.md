# O Pest - Shop

App Flutter (Android, iOS e Web) da **Loja Oficial O Pest**: catálogo de
suplementos/roupas/equipamentos, carrinho, checkout por unidade, cupons,
endereços, pedidos, painel administrativo e pagamentos reais via **PagBank**
(PIX, boleto e cartão de crédito/débito com 3DS no Web).

## Stack

- **Flutter** 3.41+ (Dart 3.11+)
- **Supabase**: Postgres, Auth, Realtime, Storage e Edge Functions (Deno)
- **PagBank Orders API**: PIX, boleto e cartão com 3DS
- **Provider** para estado, **GoRouter** para rotas

## Estrutura

```
o_pest_shop/
├── lib/
│   ├── core/            # helpers, tema, constantes
│   ├── models/          # produtos, pedidos, pagamento, endereço...
│   ├── providers/       # estado (auth, carrinho, cupom...)
│   ├── services/        # Supabase, checkout, pagamento, admin...
│   ├── ui/screens/      # cliente, admin, entregador
│   └── router/
├── supabase/
│   ├── functions/       # pagamentos + pagamentos-webhook
│   ├── migrations/      # pagamentos e blindagem
│   └── *.sql            # schema histórico (ver ordem abaixo)
├── test/                # testes unitários/widget
└── docs/                # checklist do cliente e go-live
```

## Rodar o app

```bash
cd o_pest_shop
flutter pub get
flutter run -d chrome        # Web (cartão com 3DS)
flutter run -d emulator-5554 # Android (PIX/boleto)
```

A URL e a chave pública do Supabase ficam em
`lib/core/constants/supabase_constants.dart`.

## Banco de dados

Em uma base nova, rode no SQL Editor do Supabase nesta ordem:

0. `sql_schema_completo.sql` (schema base: tabelas, buckets e policies iniciais)
1. `supabase/CONSOLIDACAO_FINAL.sql`
2. `supabase/migrations/20261018120000_schema_faltante_v2.sql`
3. `supabase/FASE2_ENDERECOS_FRETE.sql`
4. `supabase/migrations/20261017120000_pagamentos_gateway.sql`
5. `supabase/migrations/20261018130000_revogar_rpc_publicas.sql`
6. `supabase/migrations/20261019120000_pagamentos_blindagem.sql`
7. `supabase/migrations/20261027120000_frete_distancia_parceiros_ml.sql`
   (opcional: frete por distância, painel de parceiros e base do Mercado Livre.
   Só rode depois do item 6.)
8. `supabase/migrations/20261030120000_admin_correcoes.sql`
   (obrigatório: CRUD de assinaturas no admin, leitura de perfis pelo gestor e
   exclusão segura de usuários.)
9. `supabase/migrations/20261030130000_frete_correios.sql`
   (obrigatório para o frete por distância + peso; sem ele, distâncias fora das
   faixas continuam caindo na taxa fixa antiga.)
10. `supabase/migrations/20261030140000_frete_correios_melhor_envio.sql`
    (opções Correios/Melhor Envio no admin + checkout com cotação validada.)
11. `supabase/migrations/20261102120000_blindagem_compra_admin.sql`
    (obrigatório: fecha escrita direta em pedidos/pagamentos, checkout
    idempotente, validação de valor, pagamento manual auditável, histórico,
    rastreio e lista paginada de pedidos no admin.)
12. `supabase/migrations/20261103120000_correios_etiquetas.sql`
    (obrigatório para etiquetas oficiais dos Correios: endereço estruturado,
    envios, PDF no Storage, checkout v5, NF-e e status postado/em trânsito.)
13. `supabase/migrations/20261103130000_pedidos_codigo_objeto.sql`
14. `supabase/migrations/20261103140000_pedidos_status_envio.sql`
15. `supabase/migrations/20261103150000_pedido_historico_perfil_fk.sql`
16. `supabase/migrations/20261104120000_seguranca_producao.sql`
    (obrigatório: checkout v6, LGPD, último admin, cupom por cliente,
    dashboard completo, cron versionado e RLS de perfis.)
17. `supabase/migrations/20261104130000_cobranca_lock.sql`
18. `supabase/migrations/20261104140000_producao_final.sql`
    (obrigatório: storage de avatar, bloqueio de conta e revogação das RPCs
    antigas de checkout.)
19. `supabase/migrations/20261104150000_fix_rls_recursao.sql`
    (obrigatório: RLS de perfis/pedidos/envios sem recursão.)
20. `supabase/migrations/20261104160000_checkout_endereco_servidor.sql`
    (obrigatório: frete por distância só com endereço salvo e coordenadas do
    servidor.)
21. `supabase/migrations/20261104170000_estoque_manual_auditavel.sql`
22. `supabase/migrations/20261104180000_banners.sql`
23. `supabase/migrations/20261104190000_admin_pedidos_filtros.sql`
24. `supabase/migrations/20261104200000_motivo_cancelamento.sql`
25. `supabase/migrations/20261105120000_hardening_escalabilidade.sql`
    (obrigatório: preço no banco, lock atômico, views públicas, flags e índices)

> A partir da migration 20261104140000, somente `finalizar_checkout_v6` fica
> exposto ao app. v2/v3/v4/v5 e o checkout base continuam existindo apenas para
> uso interno (security definer).

O script 6 é obrigatório: ele reserva estoque no checkout, devolve
estoque/cupom no cancelamento, corrige a expiração de PIX/boleto e fecha as
RPCs antigas de confirmação manual de pagamento.

O script 11 é obrigatório para produção: sem ele o cliente ainda consegue
inserir/alterar pedidos direto pela API e o valor cobrado não é revalidado
pelos itens. Ele também adiciona a chave de idempotência usada pelo app.

## Frete por distância

Os scripts 7, 9 e 10 adicionam `frete_modo`, coordenadas da loja, `frete_faixas`,
`enderecos_usuario.latitude/longitude`, cotação server-side (`calcular_frete`)
e o checkout `finalizar_checkout_v2`. O cálculo local usa a faixa de distância
e o peso dos produtos (1 kg incluso + valor por kg extra); distância fora das
faixas cadastradas é tratada como fora de área, sem cair na taxa fixa.

Além disso, o modo de frete pode ser **Correios (API)** ou **Melhor Envio
(API)**. Nesses modos o app chama a Edge Function `frete-cotacao`, que consulta
a transportadora, grava a cotação em `frete_cotacoes` e o checkout aplica o
valor validado pela RPC `finalizar_checkout_v3`.

No admin, em **Lojas**, edite a loja:

1. Informe o endereço/CEP e toque em **Localizar origem no mapa**.
2. Escolha o modo de frete (`fixo`, `distancia` ou `faixas`).
3. Para distância: taxa base, valor por km, km inclusos, raio máximo, fator de
   rota e minutos por km.
4. Para faixas: adicione as faixas de km e valor.

No cliente, o endereço é geocodificado via BrasilAPI/Nominatim. O carrinho
mostra distância, prazo estimado e valor; o servidor recalcula tudo no checkout.
Retirada continua grátis e lojas com frete grátis por produto/valor não cobram.

### Correios e Melhor Envio

No cadastro da loja, escolha **Correios (API)** ou **Melhor Envio (API)** no
campo de frete. A Edge Function `frete-cotacao` consulta a transportadora e o
checkout usa a cotação gravada em `frete_cotacoes`.

- Correios: usa o endpoint de cálculo de preço/prazo. Informe contrato/credenciais
  em `CORREIOS_EMPRESA`, `CORREIOS_SENHA` e, se necessário, `CORREIOS_API_URL`.
- Melhor Envio: informe o token em `MELHOR_ENVIO_TOKEN`. Use
  `MELHOR_ENVIO_ENV=sandbox` para homologação.

Sem essas credenciais a opção fica configurada, mas a cotação retorna erro claro
no carrinho. A cotação só é aplicada no pedido depois de validada no servidor.

> A geocodificação usa serviços públicos (BrasilAPI e OpenStreetMap/Nominatim).
> Para alto volume, troque por Google Geocoding/Distance Matrix ou OSRM.

## Edge Functions

```bash
cd o_pest_shop
supabase login
supabase link --project-ref SEU_PROJECT_REF

supabase secrets set \
  PAGBANK_TOKEN=SEU_TOKEN \
  PAGBANK_ENV=sandbox \
  ALLOWED_ORIGINS=https://seudominio.com

# Frete: use Correios, Melhor Envio ou os dois.
supabase secrets set \
  CORREIOS_API_URL=https://ws.correios.com.br/calculador/CalcPrecoPrazo.asmx/CalcPrecoPrazo \
  CORREIOS_EMPRESA=SUA_EMPRESA \
  CORREIOS_SENHA=SUA_SENHA \
  CORREIOS_SERVICOS=04014,04510 \
  MELHOR_ENVIO_TOKEN=SEU_TOKEN \
  MELHOR_ENVIO_ENV=production

supabase functions deploy pagamentos
supabase functions deploy pagamentos-webhook --no-verify-jwt
supabase functions deploy pagamentos-conciliacao --no-verify-jwt
supabase functions deploy catalogo-publico --no-verify-jwt
supabase functions deploy frete-cotacao
supabase functions deploy frete-etiqueta
supabase functions deploy frete-rastreio --no-verify-jwt
```

Ou use o script:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/publicar-pagamentos.ps1
```

Para Correios (etiqueta/rastreio), use `scripts/publicar-correios.ps1`.
Com `-Simulacao` o fluxo inteiro é testado sem contrato/CWS.

O webhook **precisa** de `--no-verify-jwt` (o PagBank não envia JWT). A
segurança dele é a assinatura `x-authenticity-token` (SHA-256 do token +
payload), validada dentro da função.

### Conciliação automática de pagamentos

O webhook pode se perder. A função `pagamentos-conciliacao` consulta no PagBank
as cobranças pendentes e aplica o comprovante pela mesma trilha do webhook.

```bash
supabase secrets set CONCILIACAO_SECRET=UM_SEGREDO_LONGO
supabase functions deploy pagamentos-conciliacao --no-verify-jwt
```

Agende no **Supabase Dashboard > Integrations > Cron** (ou em um agendador
externo) uma chamada a cada 2 minutos:

- URL: `https://SEU_PROJECT.supabase.co/functions/v1/pagamentos-conciliacao`
- Método: `POST`
- Header: `x-conciliacao-secret: UM_SEGREDO_LONGO`

Sem esse agendamento, o admin ainda pode usar o botão de sincronizar na aba
**Pedidos**.

## Testes

```bash
flutter analyze
flutter test
```

## Limitações conhecidas (MVP)

- **Cartão só funciona no Web**: o SDK 3DS do PagBank é JavaScript. No
  Android/iOS o cliente paga com PIX ou boleto. Para cartão no app é preciso
  integrar o SDK nativo/WebView (avaliar com o cliente).
- **Frete por distância** usa Haversine + fator de rota e geocodificação
  pública; para distância de rua real, integre Google/OSRM ou Melhor Envio.
- **Etiqueta oficial** é gerada pela Pré-Postagem dos Correios; exige
  contrato/cartão de postagem e acesso CWS. Sem credenciais, use
  `CORREIOS_SIMULACAO=true` para testar o fluxo. A etiqueta pelo Melhor Envio
  ainda não está implementada (só a cotação).
- **Lojas parceiras** já têm cadastro e escopo de painel, mas o repasse
  financeiro continua na conta PagBank principal (split/repasse é uma evolução
  comercial/jurídica).
- **E-mail/WhatsApp transacional** e **NF-e** dependem de credenciais e
  processos do cliente.
- **Mercado Livre** tem a base de dados e as Edge Functions `ml-*`, mas depende
  de aplicativo/credenciais e homologação no ML para operar em produção.

## Hardening para alto tráfego (05/11/2026)

A migration `supabase/migrations/20261105120000_hardening_escalabilidade.sql`
deve ser aplicada **depois de todas as anteriores**. Ela adiciona:

- preço de item sempre calculado no banco (bloqueia adulteração);
- lock atômico de cobrança (`cobranca_locks`) e processamento serializado de
  comprovantes;
- views públicas `produtos_publicos` / `unidades_publicas` (sem custo/PIX);
- RPCs admin para leitura de campos sensíveis;
- catálogo/feed públicos para leitura anônima;
- feature flags `checkout`, `pagamentos`, `frete`, `manutencao`;
- índices e limpeza de registros temporários.

Publique também a função de catálogo:

```bash
supabase functions deploy catalogo-publico --no-verify-jwt
supabase functions deploy pagamentos
supabase functions deploy pagamentos-webhook --no-verify-jwt
supabase functions deploy pagamentos-conciliacao --no-verify-jwt
```

A home usa o snapshot `catalogo-publico` com cache local; se a função ainda
não estiver publicada, cai automaticamente nas consultas públicas antigas.
O checkout **sempre** valida preço/estoque no banco.

Documentação:

- [`docs/RELATORIO_ESCALABILIDADE.md`](docs/RELATORIO_ESCALABILIDADE.md)
- [`docs/ARQUITETURA_ALTO_TRAFEGO.md`](docs/ARQUITETURA_ALTO_TRAFEGO.md)
- [`docs/PLANO_ESCALABILIDADE.md`](docs/PLANO_ESCALABILIDADE.md)
- [`docs/RELATORIO_TESTES_CARGA.md`](docs/RELATORIO_TESTES_CARGA.md)
- [`docs/RUNBOOK_INCIDENTES.md`](docs/RUNBOOK_INCIDENTES.md)

## Entrega

- Checklist de dados/credenciais do cliente: [`docs/CHECKLIST_CLIENTE.md`](docs/CHECKLIST_CLIENTE.md)
- Passo a passo de pagamentos: [`supabase/PAGBANK_SETUP.md`](supabase/PAGBANK_SETUP.md)
- Etiquetas oficiais dos Correios: [`docs/CORREIOS_ETIQUETAS.md`](docs/CORREIOS_ETIQUETAS.md)
- Go-live e testes: [`docs/GO_LIVE.md`](docs/GO_LIVE.md)
