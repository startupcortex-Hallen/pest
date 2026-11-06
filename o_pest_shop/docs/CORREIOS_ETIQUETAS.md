# Correios oficial — cotação, etiqueta e rastreio

> Relatório de implementação + checklist de go-live.
> Última atualização: 03/11/2026.

## 1. O que foi implementado

Fluxo completo no app, sem depender da Nuvemshop:

1. Cliente informa o endereço/CEP no carrinho.
2. O app cota **PAC e SEDEX** na API oficial dos Correios e mostra as opções.
3. O cliente escolhe o serviço; o checkout grava a cotação escolhida.
4. O pedido é pago pelo PagBank.
5. No admin, o pedido pago mostra **Gerar etiqueta**.
6. O backend cria a **Pré-Postagem** nos Correios e baixa o **PDF oficial**.
7. O admin clica em **Imprimir** (A4 ou térmica 100x150).
8. O admin posta o objeto nos Correios.
9. O rastreio é sincronizado e o status aparece no pedido do cliente.

### Arquivos principais

| Camada | Arquivo |
|---|---|
| Banco | `supabase/migrations/20261103120000_correios_etiquetas.sql` |
| Regras Correios | `supabase/functions/_shared/correios.ts` |
| Cotação | `supabase/functions/frete-cotacao/index.ts` |
| Etiqueta | `supabase/functions/frete-etiqueta/index.ts` |
| Rastreio (cron) | `supabase/functions/frete-rastreio/index.ts` |
| Deploy | `scripts/publicar-correios.ps1` |
| App | `lib/models/frete.dart`, `lib/services/frete_service.dart`, `lib/services/checkout_service.dart` |
| Carrinho | `lib/ui/screens/cart/cart_screen.dart` |
| Admin | `lib/ui/screens/admin/pedido_admin_detail_screen.dart`, `lib/ui/screens/admin/unidade_form_screen.dart` |
| Cliente | `lib/ui/screens/pedidos/pedido_detail_screen.dart` |
| Status | `lib/core/helpers/pedido_status.dart` |

### Banco de dados

- `unidades`: número, complemento, UF, inscrição estadual, contribuinte do
  ICMS e nome do remetente.
- `pedidos`: endereço estruturado (rua, número, complemento, bairro, cidade,
  UF, CEP), CPF/telefone do destinatário, provider/serviço/transportadora,
  cotação escolhida, status da etiqueta, ID/código do objeto, PDF, datas de
  postagem/entrega e chave/número da NF-e.
- `envios`: uma linha por pedido com pré-postagem, PDF, peso/dimensões,
  status e última sincronização.
- `envio_eventos`: histórico de rastreio (idempotente).
- Bucket privado `etiquetas` (PDFs).
- `finalizar_checkout_v5`: guarda endereço/CPF/frete escolhido no checkout.
- `fn_pedido_status`: aceita `postado`, `em_transito` e `entregue` vindos do
  rastreio (service_role), sem quebrar o fluxo de retirada/entrega local.
- `atualizar_nota_fiscal_pedido`: admin/loja informa a NF-e antes da etiqueta.

### Segurança

- Credenciais dos Correios **nunca** vão para o app nem para o banco: ficam nos
  secrets das Edge Functions (`CORREIOS_*`).
- Token dos Correios é cacheado no servidor (24 h, limite de 3 req/s).
- PDF da etiqueta fica em bucket privado; o admin recebe URL assinada de 1 h.
- RLS em `envios`/`envio_eventos`: cliente vê o próprio envio; admin vê tudo;
  atendente/gestor veem a própria loja.
- A geração de etiqueta é exclusiva de admin/atendente/gestor.
- Logs não imprimem token/CPF/endereço.

## 2. Configuração (quando o cliente entregar os dados)

### 2.1 O que o cliente precisa ter

- Conta **Meu Correios** (CNPJ).
- **Contrato** ou **cartão de postagem** ativo.
- **Código de acesso do CWS** (`cws.correios.com.br`) com as APIs liberadas:
  Preço, Prazo, Pré-Postagem e Rastro.
- Serviços habilitados no contrato (códigos de PAC/SEDEX podem variar).
- Endereço completo do remetente (rua, número, complemento, bairro, cidade,
  UF, CEP), CNPJ, inscrição estadual e telefone/e-mail.
- Decisão fiscal: contribuinte do ICMS (NF-e obrigatória) ou não (DC-e).

> Ter conta no Meu Correios **não** é ter contrato. Sem contrato/cartão e CWS,
> a API oficial não emite etiqueta.

### 2.2 Secrets

```bash
npx supabase secrets set \
  CORREIOS_ENV=homolog \
  CORREIOS_USUARIO=... \
  CORREIOS_CODIGO_ACESSO=... \
  CORREIOS_CNPJ=... \
  CORREIOS_CONTRATO=... \
  CORREIOS_CARTAO_POSTAGEM=... \
  CORREIOS_DR=... \
  CORREIOS_SERVICOS=03298:PAC,03220:SEDEX \
  CORREIOS_LAYOUT=PADRAO
```

- `CORREIOS_ENV=production` troca o host para `api.correios.com.br`.
- `CORREIOS_SERVICOS` usa `codigo:NOME` separado por vírgula.
- `CORREIOS_LAYOUT` aceita `PADRAO`, `LINEAR_100_150`, `LINEAR_100_80`,
  `LINEAR_A4`, `LINEAR_A`.

### 2.3 Deploy

```bash
npx supabase functions deploy frete-cotacao
npx supabase functions deploy frete-etiqueta
npx supabase functions deploy frete-rastreio --no-verify-jwt
```

Ou:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/publicar-correios.ps1
```

### 2.4 Cron do rastreio

No Supabase Dashboard > Integrations > Cron, a cada 15 minutos:

- URL: `https://SEU_PROJECT.supabase.co/functions/v1/frete-rastreio`
- Método: `POST`
- Header: `x-conciliacao-secret: <CONCILIACAO_SECRET>`

Sem cron, o admin pode usar **Sincronizar** no detalhe do pedido.

## 3. Teste sem as credenciais (simulação)

Enquanto o cliente não manda o contrato, tudo pode ser testado:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/publicar-correios.ps1 -Simulacao
```

Com `CORREIOS_SIMULACAO=true`:

- a cotação retorna PAC/SEDEX fictícios;
- a etiqueta gera um PDF de teste com o código do objeto fictício;
- o botão **Simular evento** cria postado/em trânsito/entregue/ocorrência;
- nenhuma chamada real é feita aos Correios.

Ao receber as credenciais, rode o script sem `-Simulacao` (ou defina
`CORREIOS_SIMULACAO=false`) e reimplante as funções.

## 4. Checklist do fluxo (cliente → admin → Correios)

### Cliente

- [x] CEP/endereço validado no carrinho.
- [x] Cotação PAC/SEDEX com preço e prazo.
- [x] Escolha do serviço (dropdown por loja).
- [x] Checkout grava endereço estruturado + CPF + serviço escolhido.
- [x] Pedido pago entra em `em_preparo`.
- [ ] Endereço/CPF completos no perfil do cliente (validação no admin).

### Admin

- [x] Card **Envio / Etiqueta** no detalhe do pedido.
- [x] Botão **Gerar etiqueta** (só pedido pago + entrega + Correios).
- [x] Botão **Imprimir** (PDF oficial, A4/térmica).
- [x] Botão **Sincronizar** (rastreio).
- [x] Botão **Cancelar etiqueta**.
- [x] Botão **NF-e** (chave/número).
- [x] Botão **Simular evento** (só em simulação).
- [x] Timeline de eventos no card.
- [x] Código do objeto copiável.

### Correios

- [x] Token OAuth do CWS com cache.
- [x] Cotação Preço/Prazo.
- [x] Pré-Postagem com remetente/destinatário/itens/DC-e ou NF-e.
- [x] Solicitação assíncrona do PDF + retry.
- [x] Cancelamento da pré-postagem.
- [x] Rastreio SRO com eventos e status.
- [x] Bucket privado + URL assinada.

### Pós-venda

- [x] Pedido vira `postado` quando o rastreio confirma a postagem.
- [x] Pedido vira `em_transito` durante o transporte.
- [x] Pedido vira `entregue` na baixa.
- [x] Cliente vê código e link de rastreio.
- [ ] Notificação por e-mail/WhatsApp (módulo separado, depende de provedor).

## 5. Auditoria do que foi validado

| Verificação | Resultado |
|---|---|
| `flutter analyze` | Sem erros (apenas warnings/infos legados) |
| `flutter test` | 36 testes passando |
| `deno check` das funções Correios | Sem erros de tipo |
| Migration idempotente | Sim (`if not exists` / `create or replace`) |
| Checkout retrocompatível | Sim (v5 → v4 → v3 → v2) |
| Etiqueta sem credenciais | Modo simulação |
| Etiqueta com credenciais | Depende do contrato/CWS do cliente |
| Rastreio automático | Depende do cron + credenciais |
| PDF privado | Sim (bucket `etiquetas`) |
| RLS de envios | Sim |

## 6. Limitações atuais

- Só a etiqueta **Correios** está implementada neste ciclo. Se a loja estiver
  em `melhor_envio`, a cotação funciona, mas a etiqueta retorna aviso para
  configurar Correios.
- Um volume por pedido (a API suporta múltiplos volumes; evolução futura).
- DC-e é usada quando não há NF-e e a loja não é contribuinte do ICMS.
- NF-e é digitada manualmente no admin; integração com emissor fiscal é um
  módulo separado.
- Sem notificação automática de mudança de status (e-mail/WhatsApp).
- O rastreio depende de cron; sem ele, use o botão **Sincronizar**.
- Homologação real dos Correios ainda precisa ser feita com as credenciais do
  cliente (SLA e validação da conta são dos Correios).

## 7. Ordem de teste recomendada

1. Aplicar a migration `20261103120000_correios_etiquetas.sql`.
2. Rodar o script com `-Simulacao` e publicar as funções.
3. Fazer um pedido de teste, escolher PAC/SEDEX e pagar no sandbox.
4. No admin: **Gerar etiqueta** → **Imprimir** → **Simular evento**.
5. Conferir timeline do cliente e status `postado`/`em_transito`/`entregue`.
6. Quando o cliente enviar contrato/CWS, trocar para `homolog` e refazer.
7. Homologação aprovada → `production` + pedido real de R$ 1,00 + etiqueta real.
