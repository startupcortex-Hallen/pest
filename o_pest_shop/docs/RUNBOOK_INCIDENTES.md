# Runbook de Incidentes — O Pest Shop

## 1. Contatos e acessos

- Responsável técnico: ____________________
- Supabase: projeto/ref ____________________
- PagBank: conta/loja ____________________
- Cloudflare: conta/zona ____________________
- Domínio/DNS: ____________________
- Suporte PagBank: ____________________

## 2. Sintomas e primeiras ações

### 2.1 Site lento ou 5xx

1. Verificar status da Cloudflare/Supabase.
2. Ver dashboards: CPU/RAM do banco, pooler wait, Edge 5xx, cache hit.
3. Se o gargalo for catálogo: aumentar TTL de cache temporariamente.
4. Se o gargalo for checkout: ativar modo de manutenção do checkout
   (`app_config.checkout.ativo = false`) ou PIX-only.
5. Comunicar clientes com mensagem clara; não apagar pedidos.

### 2.2 Pagamentos não confirmam

1. Ver `pagamentos` pendentes e `pagamentos_eventos` com erro.
2. Rodar/verificar `pagamentos-conciliacao` (cron a cada 2 min).
3. Ver logs da function `pagamentos-webhook`.
4. Confirmar `PAGBANK_TOKEN`, `PAGBANK_ENV` e assinatura.
5. Se webhook estiver instável, manter conciliação e PIX ativo; não pedir ao
   cliente para pagar de novo sem checar o gateway.

### 2.3 Cobrança duplicada

1. Localizar pagamentos ativos do pedido/checkout.
2. Não criar nova cobrança enquanto houver ativa.
3. Estornar a duplicada no PagBank; registrar motivo em
   `pedido_auditoria`.
4. Verificar `cobranca_locks` e `processando_em`.

### 2.4 Estoque negativo/oversell

1. Pausar checkout (`checkout.ativo=false`).
2. Comparar `pedido_itens`, `estoque_movimentacoes` e `pedidos`.
3. Corrigir estoque via admin/ajuste auditável; não editar direto sem registro.
4. Reabrir checkout após conferência.

### 2.5 Auth 429 no cadastro/login

1. Verificar rate limits da Auth e WAF.
2. Aumentar limites com cautela + CAPTCHA/Turnstile.
3. Evitar desligar proteção; priorizar browse anônimo e login.
4. Comunicar janela de instabilidade.

## 3. Kill switches

```sql
-- Desligar checkout (o app e a RPC v6 passam a bloquear)
select public.admin_definir_config('checkout', '{"ativo": false}'::jsonb);

-- Voltar
select public.admin_definir_config('checkout', '{"ativo": true}'::jsonb);

-- Forçar PIX-only
select public.admin_definir_config(
  'pagamentos',
  '{"ativo": true, "pix_only": true}'::jsonb
);

-- Manutenção com mensagem
select public.admin_definir_config(
  'manutencao',
  '{"ativo": true, "mensagem": "Estamos ajustando a loja. Volte em instantes."}'::jsonb
);
```

## 4. Rollback

- App: reverter deploy para o commit anterior (GitHub Pages/Cloudflare Pages).
- Functions: manter versão anterior publicada; redeploy do commit anterior.
- Banco: não reverter migration que só cria estruturas sem necessidade; usar
  backup/PITR se houver perda de dados.
- Cache: purgar cache do catálogo/imagens na Cloudflare após rollback.

## 5. Pós-incidente

- Registrar linha do tempo, causa raiz, impacto e ações.
- Atualizar testes de carga/alertas.
- Revisar se o gatilho de upgrade para Pro/Team foi atingido.
- Comunicar clientes afetados e registrar estornos.
