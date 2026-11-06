import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/mercado_livre_service.dart';

class IntegracoesTab extends StatefulWidget {
  final int? unidadeFiltro;
  final bool permitirSelecionarLoja;

  const IntegracoesTab({
    super.key,
    this.unidadeFiltro,
    this.permitirSelecionarLoja = true,
  });

  @override
  State<IntegracoesTab> createState() => _IntegracoesTabState();
}

class _IntegracoesTabState extends State<IntegracoesTab> {
  final _client = Supabase.instance.client;
  final _ml = MercadoLivreService();

  List<Map<String, dynamic>> _unidades = [];
  List<Map<String, dynamic>> _produtos = [];
  List<Map<String, dynamic>> _anuncios = [];
  List<Map<String, dynamic>> _eventos = [];
  Map<String, dynamic>? _status;
  int? _unidadeId;
  bool _carregando = true;
  bool _executando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _unidadeId = widget.unidadeFiltro;
    _iniciar();
  }

  Future<void> _iniciar() async {
    if (widget.permitirSelecionarLoja) await _carregarUnidades();
    _unidadeId ??= _unidades.isNotEmpty
        ? (_unidades.first['id'] as num).toInt()
        : null;
    await _carregar();
  }

  Future<void> _carregarUnidades() async {
    try {
      final r = await _client.from('unidades').select('id, nome').order('nome');
      if (mounted) {
        setState(() => _unidades = (r as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  Future<void> _carregar() async {
    final unidadeId = _unidadeId;
    if (unidadeId == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resultados = await Future.wait([
        _ml.fetchStatus(unidadeId),
        _ml.fetchAnuncios(unidadeId),
        _ml.fetchEventos(),
        _client
            .from('produtos')
            .select('id, nome, sku, ml_item_id, ml_sync_enabled, ml_status, unidade_id')
            .eq('unidade_id', unidadeId)
            .order('nome'),
      ]);
      if (!mounted) return;
      setState(() {
        _status = resultados[0] as Map<String, dynamic>?;
        _anuncios = (resultados[1] as List).cast<Map<String, dynamic>>();
        _eventos = (resultados[2] as List).cast<Map<String, dynamic>>();
        _produtos = (resultados[3] as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'A integração ainda não está disponível no banco. '
              'Aplique a migration 20261027120000 e publique as Edge Functions.';
        });
      }
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _conectar() async {
    final unidadeId = _unidadeId;
    if (unidadeId == null) return;
    setState(() => _executando = true);
    try {
      final url = await _ml.iniciarConexao(unidadeId);
      final uri = Uri.tryParse(url);
      if (uri == null || !await canLaunchUrl(uri)) {
        throw StateError('URL de autorização inválida.');
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Finalize a autorização no Mercado Livre e volte para atualizar o status.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Não foi possível conectar. Verifique as secrets e a Edge Function ml-oauth-start.',
            ),
            backgroundColor: const Color(0xFFF23D4F),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  Future<void> _desconectar() async {
    final unidadeId = _unidadeId;
    if (unidadeId == null) return;
    setState(() => _executando = true);
    try {
      await _ml.desconectar(unidadeId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desconectar.')),
        );
      }
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  Future<void> _sincronizarTudo() async {
    final unidadeId = _unidadeId;
    if (unidadeId == null) return;
    setState(() => _executando = true);
    try {
      final r = await _ml.sincronizarLote(unidadeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sincronização solicitada: ${r['enviados'] ?? r['ok'] ?? 'ok'}',
            ),
          ),
        );
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao sincronizar. Veja o log de eventos.'),
            backgroundColor: Color(0xFFF23D4F),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  Future<void> _publicar(Map<String, dynamic> produto) async {
    setState(() => _executando = true);
    try {
      final action = produto['ml_item_id'] != null ? 'sincronizar' : 'publicar';
      final r = await _ml.publicarOuSincronizar(
        (produto['id'] as num).toInt(),
        action: action,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r['erro'] != null
                  ? 'Erro: ${r['erro']}'
                  : 'Mercado Livre: ${r['ml_item_id'] ?? 'sincronizado'}',
            ),
          ),
        );
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Falha ao publicar. Confira SKU, categoria e atributos do produto.',
            ),
            backgroundColor: Color(0xFFF23D4F),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_unidadeId == null) {
      return Center(
        child: Text(
          'Nenhuma loja disponível.',
          style: TextStyle(color: ThemeColors.secondaryText(context)),
        ),
      );
    }

    final conectado = _status != null &&
        _status!['status'] != null &&
        _status!['status'] != 'desconectado';

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_rounded,
                  color: Color(0xFFE50914), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mercado Livre',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _executando ? null : _carregar,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (widget.permitirSelecionarLoja) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _unidadeId,
              decoration: InputDecoration(
                labelText: 'Loja',
                isDense: true,
                filled: true,
                fillColor: ThemeColors.surface(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: _unidades
                  .map(
                    (u) => DropdownMenuItem<int>(
                      value: (u['id'] as num).toInt(),
                      child: Text(u['nome'] as String? ?? 'Loja'),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _unidadeId = v;
                  _status = null;
                  _anuncios = [];
                  _produtos = [];
                });
                _carregar();
              },
            ),
          ],
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFAD01).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _erro!,
                style: const TextStyle(fontSize: 11, color: Color(0xFFFFAD01)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: conectado
                    ? const Color(0xFF00A650).withValues(alpha: 0.35)
                    : ThemeColors.outline(context),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: conectado
                            ? const Color(0xFF00A650)
                            : const Color(0xFFF23D4F),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      conectado
                          ? 'Conectado como ${_status!['ml_nickname'] ?? _status!['ml_user_id'] ?? 'vendedor'}'
                          : 'Conta não conectada',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                if (_status?['erro'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_status!['erro']}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFF23D4F)),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _executando
                            ? null
                            : (conectado ? _sincronizarTudo : _conectar),
                        icon: Icon(
                          conectado
                              ? Icons.sync_rounded
                              : Icons.link_rounded,
                          size: 18,
                        ),
                        label: Text(
                          conectado ? 'Sincronizar catálogo' : 'Conectar conta',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (conectado) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Desconectar',
                        onPressed: _executando ? null : _desconectar,
                        icon: const Icon(Icons.link_off_rounded),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Produtos (${_produtos.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (_produtos.isEmpty)
            Text(
              'Nenhum produto nesta loja.',
              style: TextStyle(
                  fontSize: 12, color: ThemeColors.secondaryText(context)),
            ),
          ..._produtos.map(
            (p) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ThemeColors.surface(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['nome'] as String? ?? 'Produto',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'SKU: ${p['sku'] ?? '—'}  •  ${p['ml_item_id'] ?? 'não publicado'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: ThemeColors.secondaryText(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _executando ? null : () => _publicar(p),
                    child: Text(
                      p['ml_item_id'] != null ? 'Sincronizar' : 'Publicar',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Anúncios sincronizados (${_anuncios.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ..._anuncios.take(10).map(
                (a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.sell_outlined, size: 18),
                  title: Text(a['ml_item_id'] as String? ?? 'Anúncio'),
                  subtitle: Text(
                    '${a['status'] ?? '—'} • ${a['listing_type'] ?? ''}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: a['permalink'] != null
                      ? IconButton(
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          onPressed: () async {
                            final uri = Uri.tryParse('${a['permalink']}');
                            if (uri != null) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                        )
                      : null,
                ),
              ),
          const SizedBox(height: 18),
          Text(
            'Eventos recentes',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (_eventos.isEmpty)
            Text(
              'Nenhum evento recebido.',
              style: TextStyle(
                  fontSize: 12, color: ThemeColors.secondaryText(context)),
            ),
          ..._eventos.take(10).map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.notifications_none_rounded,
                      size: 18),
                  title: Text('${e['topic'] ?? ''} • ${e['status'] ?? ''}'),
                  subtitle: Text(
                    '${e['resource'] ?? ''}',
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
