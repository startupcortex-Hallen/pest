-- Ajusta o texto do plano para refletir o novo modelo:
-- 12 temporadas principais gratuitas + bastidores exclusivos no O Pest+.
update public.streaming_plans
set descricao = 'Acesso aos bastidores exclusivos e conteudos especiais do O Pest+.',
    beneficios = '["Bastidores exclusivos das 12 temporadas","Conteudos especiais","Novos episodios antes","Assista no celular"]'::jsonb,
    updated_at = now()
where slug = 'opest-plus-mensal';
