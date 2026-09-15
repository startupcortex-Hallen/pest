-- ═══════════════════════════════════════════════════════════════
-- ENTREGA V2: CEP + nome de quem recebeu
-- ═══════════════════════════════════════════════════════════════

alter table pedidos add column if not exists cep_entrega text;
alter table pedidos add column if not exists recebedor_nome text;
