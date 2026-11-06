# Checklist do cliente — o que pedir para colocar a loja no ar

> Entregue este documento ao cliente e peça que preencha os itens marcados com
> **[obrigatório]** antes do go-live. Tokens e senhas devem ser enviados por
> cofre/gerenciador de senhas (1Password, Bitwarden, etc.), **nunca** por
> WhatsApp, e-mail ou chat.

## 1. Decisões comerciais (responder antes de configurar o gateway)

- [ ] A loja é **única** (CNPJ recebe direto) ou **marketplace** com repasse
      para as unidades? Se houver repasse, o PagBank precisa de split e o
      contrato/fiscal mudam.
- [ ] A entrega será **somente Web**, **Web + Android/iOS com PIX/boleto** ou
      **Web + apps com cartão**? Hoje o cartão com 3DS funciona só no Web.
- [ ] NF-e/NFS-e no MVP ou processo manual documentado?
- [ ] Frete real (Correios/Melhor Envio) no MVP ou taxa fixa por unidade?
- [ ] A loja venderá somente produtos físicos ou também serviços/experiências?

## 2. Dados da empresa e jurídico

- [ ] **[obrigatório]** CNPJ, razão social, nome fantasia e inscrição estadual
      (se houver).
- [ ] Endereço completo da sede e endereço de cada unidade/loja.
- [ ] E-mail, telefone e WhatsApp de atendimento.
- [ ] Responsável legal e responsável técnico pelo e-commerce.
- [ ] **[obrigatório]** Termos de uso.
- [ ] **[obrigatório]** Política de privacidade (LGPD).
- [ ] **[obrigatório]** Política de troca, devolução e reembolso.
- [ ] Dados da empresa que devem aparecer no rodapé/site.
- [ ] Encarregado de dados (DPO) ou canal para solicitações LGPD.

## 3. PagBank (o caminho crítico)

- [ ] **[obrigatório]** Conta PagBank **aprovada para e-commerce**.
- [ ] **[obrigatório]** Token de **produção** da conta (e token de sandbox, se
      ainda for homologar).
- [ ] **[obrigatório]** Chave PIX cadastrada na conta.
- [ ] Confirmar se a conta já está **homologada** para vender com cartão,
      boleto e PIX.
- [ ] URL do site que será enviada ao PagBank na homologação.
- [ ] E-mail/telefone que o PagBank usa para contato e antifraude.
- [ ] Taxa/parcelamento: o lojista absorve juros ou repassa ao cliente?
- [ ] Prazo de repasse e dados bancários já cadastrados no PagBank.
- [ ] Confirmar se o 3DS está habilitado na conta.
- [ ] Quem aprova estornos/cancelamentos no dia a dia?

## 3.1 Correios (etiquetas de envio)

- [ ] **[obrigatório para etiqueta oficial]** Contrato ou cartão de postagem
      ativo nos Correios (não basta ter conta no Meu Correios).
- [ ] **[obrigatório]** Código de acesso do CWS
      (`cws.correios.com.br`) com as APIs Preço, Prazo, Pré-Postagem e Rastro
      liberadas.
- [ ] Códigos dos serviços habilitados no contrato (PAC/SEDEX podem variar).
- [ ] Endereço completo do remetente (rua, número, complemento, bairro,
      cidade, UF, CEP), CNPJ, inscrição estadual, telefone e e-mail.
- [ ] Peso e dimensões (comprimento x largura x altura) de cada produto.
- [ ] Definir se a loja é **contribuinte do ICMS** (etiqueta exige chave da
      NF-e) ou se usará **DC-e** (declaração de conteúdo).
- [ ] Quem emite a NF-e e em qual prazo.
- [ ] Confirmar se o contrato permite etiqueta para todos os serviços
      desejados e se o faturamento está ativo.

## 4. Domínio, hospedagem e certificados

- [ ] **[obrigatório]** Domínio definitivo (ex.: `loja.opest.com.br`).
- [ ] Acesso ao registrador/DNS (ou alguém que possa criar os registros).
- [ ] Onde o site vai rodar: GitHub Pages, Vercel, Netlify, VPS, outro?
- [ ] HTTPS válido no domínio.
- [ ] Se GitHub Pages: repositório/organização e permissão de deploy.
- [ ] E-mail do domínio (para remetente transacional).

## 5. Supabase

- [ ] **[obrigatório]** Organização/projeto onde a loja vai rodar.
- [ ] Convidar o desenvolvedor como **Owner/Developer** ou fornecer um
      **Personal Access Token** com escopo no projeto.
- [ ] Confirmar o **project ref** e a região.
- [ ] Plano do Supabase (Free/Pro) e se PITR/backup está contratado.
- [ ] Se haverá **staging** separado da produção.
- [ ] Quem pode aplicar migrations no banco de produção.
- [ ] Nunca enviar a `service_role key` por chat: configurar direto nos
      secrets da Edge Function.

## 6. Fiscal (NF-e/NFS-e)

- [ ] Emissor: sistema próprio, contador, PlugNotas, Focus NFe, Bling etc.
- [ ] Regime tributário e CFOP/NCM dos produtos.
- [ ] Inscrição municipal (se serviço).
- [ ] Quem emite a nota e em qual prazo.
- [ ] E-mail que recebe XML/DANFE.

## 7. E-mail e WhatsApp transacional

- [ ] Provedor: Resend, SendGrid, Amazon SES, Brevo, Zenvia, Twilio etc.
- [ ] **[obrigatório se usar e-mail]** API key e domínio de envio verificado.
- [ ] Templates desejados: pedido criado, pagamento aprovado, boleto vencendo,
      saiu para entrega, entregue, cancelado/estornado.
- [ ] WhatsApp: número, API oficial ou link `wa.me` manual?
- [ ] Quem responde o atendimento e em qual horário.

## 8. Operação e logística

- [ ] Endereço/horário de retirada de cada unidade.
- [ ] Taxa de entrega por unidade e valor mínimo para frete grátis.
- [ ] Prazo de retirada/entrega.
- [ ] Contrato/credenciais dos Correios (empresa, senha, contrato e serviços)
      e/ou token do Melhor Envio para cotação automática.
- [ ] Entregadores: nomes, e-mails e unidades.
- [ ] Política de estoque: reserva no checkout (recomendado) ou baixa só no
      pagamento.
- [ ] O que fazer quando o pagamento aprova e o estoque acabou (estorno?
      contato? troca?).
- [ ] Rotina de conciliação diária (pedidos x pagamentos x gateway).

## 9. Acessos e segurança

- [ ] Conta admin da loja (e-mail) para testes.
- [ ] Ativar 2FA no Supabase, GitHub, PagBank e e-mail.
- [ ] Quem aprova criação de novos admins/atendentes.
- [ ] Política de senhas e rotação de tokens.
- [ ] Backup/PITR e teste de restauração.

## 10. Conteúdo e catálogo

- [ ] Fotos dos produtos (mínimo 3 por produto, fundo limpo).
- [ ] Nome, descrição, preço, preço promocional, estoque e categoria.
- [ ] Variações (cor/tamanho) e SKU.
- [ ] Marcas e logos.
- [ ] Banner da home, logo e ícone do app.
- [ ] Textos institucionais e redes sociais.

## 11. O que já pode ser feito sem esses dados

- Correções de código do pagamento (CPF no PIX, 3DS com endereço real,
  webhook, estorno, estoque/cupom).
- Migrations de blindagem e scripts de deploy.
- Testes de CRUD no emulador.
- Documentação, README, PWA e checklist.
- Preparação do painel admin e do comprovante.

## 12. Ordem recomendada de entrega

1. Cliente envia CNPJ/conta PagBank e token de sandbox.
2. Aplicar SQL e publicar Edge Functions.
3. Testar PIX, boleto, crédito e débito no sandbox.
4. Homologar a conta no PagBank.
5. Trocar para token de produção e domínio definitivo.
6. Teste real de R$ 1,00 + estorno.
7. Treinamento e entrega do runbook.

## 13. Campanha de alto tr�fego (obrigat�rio antes do link)

- [ ] Data/hora e volume previsto (visitantes simult�neos e pedidos/min).
- [ ] Conta Cloudflare (DNS/proxy), dom�nio e HTTPS.
- [ ] Cache rules para cat�logo, imagens e assets; bypass para checkout/admin.
- [ ] Rate limiting/WAF nas rotas de Auth e pagamentos.
- [ ] SMTP pr�prio com dom�nio verificado e quota para o volume.
- [ ] CAPTCHA/Turnstile no cadastro/login (avaliar com o cliente).
- [ ] Backup externo do banco e teste de restaura��o.
- [ ] Teste de carga aprovado para o volume prometido.
- [ ] Plano de upgrade Supabase Pro/Team se os gatilhos forem atingidos.
- [ ] Runbook de incidentes e pessoa de plant�o.
