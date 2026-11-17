import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/helpers/streaming_format.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/streaming_models.dart';
import '../../../providers/streaming_provider.dart';
import 'streaming_widgets.dart';

class StreamingSubscriptionScreen extends StatefulWidget {
  const StreamingSubscriptionScreen({super.key});

  @override
  State<StreamingSubscriptionScreen> createState() =>
      _StreamingSubscriptionScreenState();
}

class _StreamingSubscriptionScreenState
    extends State<StreamingSubscriptionScreen>
    with WidgetsBindingObserver {
  bool _processando = false;
  bool _verificando = false;
  bool _checkoutAberto = false;
  String? _planoProcessando;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StreamingProvider>().loadIfStale();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _checkoutAberto) {
      _checkoutAberto = false;
      _verificar(silencioso: true);
    }
  }

  String _statusLabel(StreamingSubscription assinatura) {
    if (assinatura.ativa) return 'Assinatura ativa';
    switch (assinatura.status) {
      case 'pendente':
        return 'Pagamento pendente';
      case 'pausada':
        return 'Assinatura pausada';
      case 'inadimplente':
        return 'Pagamento em atraso';
      case 'cancelada':
        return 'Assinatura cancelada';
      case 'expirada':
        return 'Assinatura expirada';
      default:
        return assinatura.status;
    }
  }

  Color _statusColor(BuildContext context, StreamingSubscription assinatura) {
    if (assinatura.ativa) return ThemeColors.success(context);
    if (assinatura.status == 'pendente') return ThemeColors.warning(context);
    return ThemeColors.error(context);
  }

  Future<void> _abrirCheckout(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw StateError('Link de pagamento inválido.');
    }
    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abriu) {
      throw StateError('Não foi possível abrir o Mercado Pago.');
    }
    _checkoutAberto = true;
  }

  Future<void> _assinar(StreamingPlan plano) async {
    final provider = context.read<StreamingProvider>();
    if (!provider.isLoggedIn) {
      context.push('/login');
      return;
    }
    if (_processando) return;

    setState(() {
      _processando = true;
      _planoProcessando = plano.id;
    });
    try {
      final url = await provider.assinar(plano.id);
      await _abrirCheckout(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Finalize o pagamento no Mercado Pago e volte para o app. '
              'A assinatura será confirmada automaticamente.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final mensagem = e is StateError ? e.message : e.toString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mensagem)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _processando = false;
          _planoProcessando = null;
        });
      }
    }
  }

  Future<void> _verificar({bool silencioso = false}) async {
    if (_verificando) return;
    setState(() => _verificando = true);
    try {
      final assinatura = await context
          .read<StreamingProvider>()
          .sincronizarAssinatura();
      if (!mounted) return;
      if (!silencioso) {
        final mensagem = assinatura == null
            ? 'Nenhuma assinatura encontrada para esta conta.'
            : assinatura.ativa
            ? 'Assinatura ativa! Aproveite o O Pest+.'
            : 'Status: ${_statusLabel(assinatura)}.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mensagem)));
      }
    } catch (e) {
      if (!mounted) return;
      if (!silencioso) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Não foi possível verificar o pagamento agora.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _cancelar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar assinatura'),
        content: const Text(
          'A renovação será interrompida no Mercado Pago. '
          'Você mantém o acesso até o fim do período já pago.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Manter assinatura'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar assinatura'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _processando = true);
    try {
      await context.read<StreamingProvider>().cancelarAssinatura();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Assinatura cancelada.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Não foi possível cancelar agora. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StreamingProvider>();
    final assinatura = provider.subscription;

    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.background(context),
        foregroundColor: ThemeColors.primaryText(context),
        title: const Text(
          'O Pest+',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Verificar pagamento',
            onPressed: _verificando ? null : _verificar,
            icon: _verificando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            100,
          ),
          children: [
            _hero(),
            const SizedBox(height: 16),
            if (!provider.isLoggedIn) _loginCard(),
            if (provider.isLoggedIn && assinatura != null)
              _assinaturaCard(provider, assinatura),
            const SizedBox(height: 16),
            Text(
              'Planos',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Escolha o plano para assistir aos conteúdos exclusivos.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeColors.secondaryText(context),
              ),
            ),
            const SizedBox(height: 12),
            if (provider.plans.isEmpty)
              const StreamingEmptyState(
                title: 'Nenhum plano disponível',
                message:
                    'O administrador precisa cadastrar um plano ativo com preço para liberar as assinaturas.',
                icon: Icons.workspace_premium_outlined,
              )
            else
              ...provider.plans.map(
                (plano) => _planoCard(provider, plano, assinatura),
              ),
            const SizedBox(height: 16),
            Text(
              'O valor é cobrado pelo Mercado Pago em assinatura recorrente. '
              'Você pode cancelar quando quiser; o acesso continua até o fim '
              'do período já pago.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ThemeColors.secondaryText(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeColors.primary(context).withValues(alpha: 0.9),
            ThemeColors.primary(context).withValues(alpha: 0.35),
            ThemeColors.surface(context),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ThemeColors.primary(context).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'O Pest+',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      'Conteúdos exclusivos e versão alternativa',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Assista antes, veja produções exclusivas e apoie novas temporadas '
            'da websérie. Cancele quando quiser.',
            style: TextStyle(color: Colors.white, height: 1.45, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _loginCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeColors.outline(context)),
      ),
      child: Row(
        children: [
          const Icon(Icons.login_rounded, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Entre na sua conta para assinar e liberar os conteúdos exclusivos.',
              style: TextStyle(fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/login'),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  Widget _assinaturaCard(
    StreamingProvider provider,
    StreamingSubscription assinatura,
  ) {
    final cor = _statusColor(context, assinatura);
    final fim = formatarDataStreaming(assinatura.currentPeriodEnd);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _statusLabel(assinatura),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              StreamingBadge(
                label: 'NÍVEL ${assinatura.planNivel}',
                color: cor,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            assinatura.planNome ?? 'Plano O Pest+',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (fim.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              assinatura.ativa
                  ? 'Próxima renovação: $fim'
                  : 'Período atual até: $fim',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ThemeColors.secondaryText(context),
              ),
            ),
          ],
          if (assinatura.ativa) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _processando ? null : _cancelar,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Cancelar assinatura'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeColors.error(context),
                      side: BorderSide(
                        color: ThemeColors.error(
                          context,
                        ).withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (assinatura.pendente) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (assinatura.initPoint != null) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _processando
                          ? null
                          : () async {
                              try {
                                await _abrirCheckout(assinatura.initPoint!);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Continuar pagamento'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _verificando ? null : _verificar,
                    icon: const Icon(Icons.sync_rounded, size: 16),
                    label: const Text('Verificar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _planoCard(
    StreamingProvider provider,
    StreamingPlan plano,
    StreamingSubscription? assinatura,
  ) {
    final atual = assinatura?.ativa == true && assinatura?.planId == plano.id;
    final processando = _processando && _planoProcessando == plano.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: atual
              ? ThemeColors.success(context)
              : ThemeColors.outline(context).withValues(alpha: 0.7),
          width: atual ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plano.nome,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              StreamingBadge(
                label: 'NÍVEL ${plano.nivel}',
                color: ThemeColors.primary(context),
              ),
            ],
          ),
          if (plano.descricao != null) ...[
            const SizedBox(height: 3),
            Text(
              plano.descricao!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeColors.secondaryText(context),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                plano.precoFormatado,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeColors.primary(context),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  plano.periodoLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ThemeColors.secondaryText(context),
                  ),
                ),
              ),
            ],
          ),
          if (plano.trialDias > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${plano.trialDias} dias grátis para testar',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ThemeColors.success(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              StreamingInfoChip(
                label: '${plano.maxTelas} tela(s)',
                icon: Icons.devices_rounded,
              ),
              if (plano.qualidade != null)
                StreamingInfoChip(
                  label: plano.qualidade!,
                  icon: Icons.hd_rounded,
                ),
            ],
          ),
          if (plano.beneficios.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...plano.beneficios.map(
              (beneficio) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: ThemeColors.success(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        beneficio,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: ThemeColors.secondaryText(context),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: atual
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Plano atual'),
                  )
                : ElevatedButton.icon(
                    onPressed: _processando ? null : () => _assinar(plano),
                    icon: processando
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.workspace_premium_rounded, size: 17),
                    label: Text(
                      provider.isLoggedIn
                          ? 'Assinar com Mercado Pago'
                          : 'Entrar para assinar',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
