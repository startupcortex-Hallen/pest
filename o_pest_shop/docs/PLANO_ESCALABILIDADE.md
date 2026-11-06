# Plano de Escalabilidade — O Pest Shop

## Fase 0 — Preparação (sem mudar produção)

- [ ] Revisar e commitar o hardening em branch.
- [ ] Criar projeto Supabase de staging (mesmo schema, plano Free).
- [ ] Rodar `20261105120000_hardening_escalabilidade.sql` no staging.
- [ ] Publicar functions de staging (PagBank sandbox).
- [ ] Exportar backup do banco (`pg_dump`) antes de qualquer campanha.
- [ ] Configurar Sentry/alertas e métricas do Supabase/Cloudflare.
- [ ] Avisar Supabase e PagBank sobre o volume previsto.

## Fase 1 — Segurança financeira (P0)

- [ ] Testar preço adulterado: chamar checkout com `preco_atual` baixo e
      confirmar que o total e a cobrança usam o preço do banco.
- [ ] Testar concorrência: 100 checkouts no último item; deve haver 1 venda e
      os demais recebem “estoque insuficiente”.
- [ ] Testar duplo clique no checkout e reenvio de webhook.
- [ ] Testar estorno concorrente com pagamento aprovado.
- [ ] Confirmar que `produtos.custo` e `unidades.pix_key` não são legíveis por
      cliente comum via PostgREST.
- [ ] Confirmar que apenas `finalizar_checkout_v6` está exposta ao app.

## Fase 2 — Redução de requisições

- [ ] Medir home antes/depois: deve sair de 3–4 consultas + banners para 1
      snapshot Edge (ou 1 cache local).
- [ ] Medir polling: 5s → 20s local + 60s sync.
- [ ] Confirmar cache local (offline/stale) no Web e Android.
- [ ] Verificar índices com `EXPLAIN (ANALYZE, BUFFERS)` das consultas:
      catálogo, busca, pedidos do usuário, admin.
- [ ] Verificar limpeza de temporários (`limpar_registros_temporarios`).

## Fase 3 — Cache e imagens

- [ ] Comprimir imagens existentes para WebP/AVIF (300/800/1600 px).
- [ ] Configurar Cloudflare Pages/Proxy + cache rules.
- [ ] Configurar cache longo para assets versionados e imagens.
- [ ] Medir cache hit > 90% no pico simulado.
- [ ] Avaliar R2/Cloudflare Images se o egress do Storage passar de 60%.
- [ ] Pré-aquecer cache (home, top produtos, banners) antes da divulgação.

## Fase 4 — Proteção de tráfego e Auth

- [ ] Configurar rate limits da Auth (signup/login/recover/token).
- [ ] Configurar SMTP próprio e testar recuperação de senha.
- [ ] Avaliar CAPTCHA/Turnstile no cadastro.
- [ ] Configurar WAF/rate limiting Cloudflare nas rotas sensíveis.
- [ ] Testar NAT: 100 logins do mesmo IP (deve haver plano, não bloqueio
      silencioso).
- [ ] Revisar 2FA/controle de sessão e rotação de tokens.

## Fase 5 — Testes de carga

Ordem obrigatória, sem pular etapas:

1. 50 usuários simultâneos.
2. 100 usuários.
3. 300 usuários.
4. 500 usuários.
5. 2.000 usuários (somente com infraestrutura externa de teste).
6. 5.000 e 10.000 (geradores distribuídos; ambiente de teste).
7. 50.000 somente com infraestrutura paga dimensionada e aval de capacidade.

Critérios para avançar:

- Erro < 1%; p95 catálogo < 800 ms; checkout < 2 s.
- Zero oversell e zero cobrança duplicada.
- DB < 70% CPU/RAM; sem 429/5xx em cascata.
- Cache hit > 90% no catálogo.
- Webhook processado < 2 min.

## Fase 6 — Decisão de infraestrutura

Sair do Free quando qualquer gatilho ocorrer:

- CPU/RAM > 60–70% persistente.
- Egress > 70% da franquia (5 GB).
- 429/5xx crescentes ou p95 degradando.
- Fila de checkout acima da capacidade.
- Necessidade de backup/PITR/SLA.

Migração: Free → Pro (compute Large/XL no pico, PITR, log drain) → Team se
precisar de SLA. A camada Cloudflare/Edge e as regras de negócio permanecem.

## Checklist de go-live

- [ ] Backup externo restaurável.
- [ ] Feature flags conferidas (`checkout`, `pagamentos`, `frete`).
- [ ] Teste real de R$ 1,00 + estorno.
- [ ] Etiqueta/rastreio (se Correios) com credenciais reais.
- [ ] SMTP e recuperação de senha testados.
- [ ] Cache pré-aquecido e monitoração aberta.
- [ ] Runbook de incidentes e on-call definidos.
- [ ] Capacidade mínima comprovada por teste.
- [ ] Plano de rollback e kill switch.
