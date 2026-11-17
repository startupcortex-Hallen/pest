import 'package:flutter/material.dart';

import '../../../core/helpers/theme_colors.dart';
import '../../../core/helpers/youtube_url.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../services/streaming/streaming_admin_service.dart';
import 'admin_utils.dart';
import 'streaming_admin_widgets.dart';

class StreamingEpisodeImportScreen extends StatefulWidget {
  final List<Map<String, dynamic>> series;
  final List<Map<String, dynamic>> temporadas;
  final String? seriesInicialId;
  final String? seasonInicialId;

  const StreamingEpisodeImportScreen({
    super.key,
    required this.series,
    required this.temporadas,
    this.seriesInicialId,
    this.seasonInicialId,
  });

  @override
  State<StreamingEpisodeImportScreen> createState() =>
      _StreamingEpisodeImportScreenState();
}

class _StreamingEpisodeImportScreenState
    extends State<StreamingEpisodeImportScreen> {
  final _service = StreamingAdminService();
  final _linksCtrl = TextEditingController();

  late String _seriesId;
  late String _seasonId;
  List<_LinkValidado> _validados = [];
  bool _validando = false;
  bool _importando = false;
  String? _erro;

  List<Map<String, dynamic>> get _temporadasDaSerie =>
      widget.temporadas
          .where((item) => item['series_id']?.toString() == _seriesId)
          .toList()
        ..sort((a, b) {
          final numeroA = (a['season_number'] as num?)?.toInt() ?? 0;
          final numeroB = (b['season_number'] as num?)?.toInt() ?? 0;
          return numeroA.compareTo(numeroB);
        });

  @override
  void initState() {
    super.initState();
    _seriesId =
        widget.seriesInicialId ??
        (widget.series.isNotEmpty
            ? widget.series.first['id']?.toString() ?? ''
            : '');
    final temporadas = widget.temporadas
        .where((item) => item['series_id']?.toString() == _seriesId)
        .toList();
    _seasonId = widget.seasonInicialId ?? '';
    if (!temporadas.any((item) => item['id']?.toString() == _seasonId)) {
      _seasonId = temporadas.isEmpty
          ? ''
          : temporadas.first['id']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _linksCtrl.dispose();
    super.dispose();
  }

  void _alterarSerie(String? valor) {
    final novas = widget.temporadas
        .where((item) => item['series_id']?.toString() == valor)
        .toList();
    setState(() {
      _seriesId = valor ?? '';
      _seasonId = novas.isEmpty ? '' : novas.first['id']?.toString() ?? '';
      _validados = [];
      _erro = null;
    });
  }

  Future<void> _validarLinks() async {
    if (_seasonId.isEmpty) {
      _snack('Selecione a temporada.');
      return;
    }
    final linhas = _linksCtrl.text
        .split('\n')
        .map((linha) => linha.trim())
        .where((linha) => linha.isNotEmpty)
        .toList();
    if (linhas.isEmpty) {
      _snack('Cole pelo menos um link do YouTube.');
      return;
    }

    setState(() {
      _validando = true;
      _erro = null;
    });

    try {
      final existentes = await _service.fetchEpisodes(seasonId: _seasonId);
      final idsExistentes = existentes
          .map((item) => item['youtube_video_id']?.toString())
          .whereType<String>()
          .toSet();
      var proximoNumero = existentes.fold<int>(0, (maior, item) {
        final numero = (item['episode_number'] as num?)?.toInt() ?? 0;
        return numero > maior ? numero : maior;
      });
      var proximaOrdem = existentes.fold<int>(0, (maior, item) {
        final ordem = (item['display_order'] as num?)?.toInt() ?? 0;
        return ordem > maior ? ordem : maior;
      });

      final vistos = <String>{};
      final validados = <_LinkValidado>[];
      for (var i = 0; i < linhas.length; i++) {
        final partes = linhas[i].split('|');
        final url = partes.first.trim();
        final tituloInformado = partes.length > 1
            ? partes.sublist(1).join('|').trim()
            : '';
        final videoId = YoutubeUrl.extractId(url);

        String? erro;
        if (videoId == null) {
          erro = 'URL do YouTube inválida';
        } else if (idsExistentes.contains(videoId)) {
          erro = 'Já existe nesta temporada';
        } else if (vistos.contains(videoId)) {
          erro = 'Link repetido nesta importação';
        }

        _LinkValidado? item;
        if (videoId != null) {
          vistos.add(videoId);
        }
        if (erro == null && videoId != null) {
          proximoNumero++;
          proximaOrdem += 10;
          item = _LinkValidado(
            titulo: tituloInformado.isEmpty
                ? 'Episódio $proximoNumero'
                : tituloInformado,
            url: YoutubeUrl.watchUrl(videoId),
            videoId: videoId,
            epNumero: proximoNumero,
            ordem: proximaOrdem,
          );
        }

        validados.add(
          _LinkValidado(
            titulo: tituloInformado.isEmpty
                ? 'Linha ${i + 1}'
                : tituloInformado,
            url: url,
            videoId: videoId,
            epNumero: item?.epNumero,
            ordem: item?.ordem,
            erro: erro,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _validados = validados;
        _validando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validando = false;
        _erro = mapErroAdmin(e);
      });
    }
  }

  Future<void> _importar() async {
    final validos = _validados.where((item) => item.erro == null).toList();
    if (validos.isEmpty || _importando) return;

    setState(() => _importando = true);
    try {
      await _service.importarEpisodios(
        validos
            .map(
              (item) => <String, dynamic>{
                'season_id': _seasonId,
                'episode_number': item.epNumero,
                'title': item.titulo,
                'youtube_video_id': item.videoId,
                'youtube_url': item.url,
                'status': 'rascunho',
                'display_order': item.ordem,
                'is_featured': false,
                'required_plan_level': 0,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              },
            )
            .toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _importando = false);
      _snack(mapErroAdmin(e));
    }
  }

  void _snack(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    final temporadas = _temporadasDaSerie;
    final validos = _validados.where((item) => item.erro == null).length;
    final invalidos = _validados.length - validos;

    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.background(context),
        foregroundColor: ThemeColors.primaryText(context),
        title: const Text('Importar episódios'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          140,
        ),
        children: [
          const StreamingAdminSectionTitle(
            title: 'Links em lote',
            subtitle:
                'Cole um link do YouTube por linha. Para definir o título, use: URL | Título.',
          ),
          DropdownButtonFormField<String>(
            initialValue: _seriesId.isEmpty ? null : _seriesId,
            decoration: adminInputDec(context, 'Série*'),
            items: widget.series
                .map(
                  (serie) => DropdownMenuItem<String>(
                    value: serie['id']?.toString(),
                    child: Text(
                      serie['title']?.toString() ?? 'Série',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _alterarSerie,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('import-season-$_seriesId-$_seasonId'),
            initialValue:
                temporadas.any((item) => item['id']?.toString() == _seasonId)
                ? _seasonId
                : null,
            decoration: adminInputDec(context, 'Temporada*'),
            items: temporadas
                .map(
                  (temporada) => DropdownMenuItem<String>(
                    value: temporada['id']?.toString(),
                    child: Text(
                      'T${temporada['season_number']} • '
                      '${temporada['title'] ?? 'Temporada'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (valor) => setState(() {
              _seasonId = valor ?? '';
              _validados = [];
              _erro = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linksCtrl,
            minLines: 7,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            decoration: adminInputDec(
              context,
              'Links do YouTube',
              hint:
                  'https://www.youtube.com/watch?v=...\n'
                  'https://youtu.be/... | Título do episódio',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _validando ? null : _validarLinks,
            icon: _validando
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_rounded, size: 17),
            label: const Text('Validar links'),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(
              _erro!,
              style: TextStyle(color: ThemeColors.error(context), fontSize: 11),
            ),
          ],
          if (_validados.isNotEmpty) ...[
            const SizedBox(height: 16),
            StreamingAdminSectionTitle(
              title: 'Prévia da importação',
              subtitle:
                  '$validos válido(s) • $invalidos com problema • '
                  'Serão criados como rascunho.',
            ),
            ..._validados.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ThemeColors.surface(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: item.erro == null
                        ? ThemeColors.success(context).withValues(alpha: 0.4)
                        : ThemeColors.error(context).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      item.erro == null
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 18,
                      color: item.erro == null
                          ? ThemeColors.success(context)
                          : ThemeColors.error(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.erro == null
                                ? 'EP ${item.epNumero} • ${item.titulo}'
                                : item.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            item.erro ?? item.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: item.erro == null
                                  ? ThemeColors.secondaryText(context)
                                  : ThemeColors.error(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ElevatedButton.icon(
            onPressed: validos == 0 || _importando ? null : _importar,
            icon: _importando
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_done_rounded, size: 18),
            label: Text(
              _importando
                  ? 'Importando...'
                  : validos == 0
                  ? 'Nenhum link válido'
                  : 'Importar $validos episódio(s) como rascunho',
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkValidado {
  final String titulo;
  final String url;
  final String? videoId;
  final int? epNumero;
  final int? ordem;
  final String? erro;

  const _LinkValidado({
    required this.titulo,
    required this.url,
    this.videoId,
    this.epNumero,
    this.ordem,
    this.erro,
  });
}
