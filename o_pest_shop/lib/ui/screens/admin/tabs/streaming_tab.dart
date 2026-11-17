import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/helpers/streaming_format.dart';
import '../../../../core/helpers/theme_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../models/streaming_models.dart';
import '../../../../services/streaming/streaming_admin_service.dart';
import '../../streaming/streaming_widgets.dart';
import '../streaming_episode_form_screen.dart';
import '../streaming_episode_import_screen.dart';
import '../streaming_season_form_screen.dart';
import '../streaming_series_form_screen.dart';
import '../streaming_admin_widgets.dart';
import '../admin_utils.dart';

class StreamingTab extends StatefulWidget {
  const StreamingTab({super.key});

  @override
  State<StreamingTab> createState() => _StreamingTabState();
}

class _StreamingTabState extends State<StreamingTab> {
  final _service = StreamingAdminService();

  List<Map<String, dynamic>> _series = [];
  List<Map<String, dynamic>> _temporadas = [];
  List<Map<String, dynamic>> _episodios = [];
  List<Map<String, dynamic>> _planos = [];
  List<Map<String, dynamic>> _assinaturas = [];
  List<Map<String, dynamic>> _codigos = [];
  Map<String, Map<String, int>> _contagensSeries = {};
  List<StreamingHomeSection> _secoes = List<StreamingHomeSection>.from(
    StreamingHomeConfig.secoesPadrao,
  );
  String? _heroId;
  bool _loading = true;
  bool _salvandoHome = false;
  int _subAba = 0;
  String? _filtroSerieTemporada;
  String? _filtroSerieEpisodio;
  String? _filtroTemporadaEpisodio;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final series = await _service.fetchSeries();
      final contagens = await _service.fetchSeriesContagens();
      final temporadas = await _service.fetchSeasons();
      final config = await _service.fetchHomeConfig();

      var filtroSerieTemporada = _filtroSerieTemporada;
      if (filtroSerieTemporada == null ||
          !series.any(
            (item) => item['id']?.toString() == filtroSerieTemporada,
          )) {
        filtroSerieTemporada = series.isEmpty
            ? null
            : series.first['id']?.toString();
      }

      var filtroSerieEpisodio = _filtroSerieEpisodio;
      if (filtroSerieEpisodio == null ||
          !series.any(
            (item) => item['id']?.toString() == filtroSerieEpisodio,
          )) {
        filtroSerieEpisodio = series.isEmpty
            ? null
            : series.first['id']?.toString();
      }

      final temporadasDaSerie = temporadas
          .where((item) => item['series_id']?.toString() == filtroSerieEpisodio)
          .toList();

      var filtroTemporadaEpisodio = _filtroTemporadaEpisodio;
      if (filtroTemporadaEpisodio == null ||
          !temporadasDaSerie.any(
            (item) => item['id']?.toString() == filtroTemporadaEpisodio,
          )) {
        filtroTemporadaEpisodio = temporadasDaSerie.isEmpty
            ? null
            : temporadasDaSerie.first['id']?.toString();
      }

      final episodios = filtroTemporadaEpisodio == null
          ? <Map<String, dynamic>>[]
          : await _service.fetchEpisodes(seasonId: filtroTemporadaEpisodio);

      var planos = <Map<String, dynamic>>[];
      var assinaturas = <Map<String, dynamic>>[];
      var codigos = <Map<String, dynamic>>[];
      try {
        planos = await _service.fetchPlanosAdmin();
        assinaturas = await _service.fetchAssinaturasAdmin();
        codigos = await _service.fetchCodigosAcesso();
      } catch (e) {
        debugPrint('Erro ao carregar assinaturas admin: $e');
      }

      if (!mounted) return;
      setState(() {
        _series = series;
        _temporadas = temporadas;
        _episodios = episodios;
        _planos = planos;
        _assinaturas = assinaturas;
        _codigos = codigos;
        _contagensSeries = {
          for (final item in contagens)
            if (item['series_id'] != null)
              item['series_id'].toString(): {
                'seasons_count': (item['seasons_count'] as num?)?.toInt() ?? 0,
                'episodes_count':
                    (item['episodes_count'] as num?)?.toInt() ?? 0,
              },
        };
        _filtroSerieTemporada = filtroSerieTemporada;
        _filtroSerieEpisodio = filtroSerieEpisodio;
        _filtroTemporadaEpisodio = filtroTemporadaEpisodio;
        if (config == null) {
          _secoes = List<StreamingHomeSection>.from(
            StreamingHomeConfig.secoesPadrao,
          );
          _heroId = null;
        } else {
          final home = StreamingHomeConfig.fromJson(config);
          _secoes = List<StreamingHomeSection>.from(home.sections);
          _heroId = home.heroSeriesId;
        }
        _loading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar admin streaming: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  Future<void> _carregarEpisodios(String? seasonId) async {
    setState(() => _episodios = []);
    try {
      final episodios = seasonId == null
          ? <Map<String, dynamic>>[]
          : await _service.fetchEpisodes(seasonId: seasonId);
      if (!mounted) return;
      setState(() => _episodios = episodios);
    } catch (e) {
      if (mounted) _snack(mapErroAdmin(e));
    }
  }

  List<Map<String, dynamic>> _temporadasDaSerie(String? seriesId) {
    final lista =
        _temporadas
            .where((item) => item['series_id']?.toString() == seriesId)
            .toList()
          ..sort((a, b) {
            final ordemA = (a['display_order'] as num?)?.toInt() ?? 0;
            final ordemB = (b['display_order'] as num?)?.toInt() ?? 0;
            if (ordemA != ordemB) return ordemA.compareTo(ordemB);
            final numeroA = (a['season_number'] as num?)?.toInt() ?? 0;
            final numeroB = (b['season_number'] as num?)?.toInt() ?? 0;
            return numeroA.compareTo(numeroB);
          });
    return lista;
  }

  List<Map<String, dynamic>> _episodiosDaTemporada(String? seasonId) {
    return _episodios
        .where((item) => item['season_id']?.toString() == seasonId)
        .toList()
      ..sort((a, b) {
        final ordemA = (a['display_order'] as num?)?.toInt() ?? 0;
        final ordemB = (b['display_order'] as num?)?.toInt() ?? 0;
        if (ordemA != ordemB) return ordemA.compareTo(ordemB);
        final numeroA = (a['episode_number'] as num?)?.toInt() ?? 0;
        final numeroB = (b['episode_number'] as num?)?.toInt() ?? 0;
        return numeroA.compareTo(numeroB);
      });
  }

  int _temporadasCount(String seriesId) =>
      _contagensSeries[seriesId]?['seasons_count'] ??
      _temporadas
          .where((item) => item['series_id']?.toString() == seriesId)
          .length;

  int _episodiosCountDaSerie(String seriesId) =>
      _contagensSeries[seriesId]?['episodes_count'] ?? 0;

  int _episodiosCountDaTemporada(Map<String, dynamic> temporada) =>
      (temporada['episodes_count'] as num?)?.toInt() ??
      _episodios
          .where(
            (item) =>
                item['season_id']?.toString() == temporada['id']?.toString(),
          )
          .length;

  Future<void> _abrirFormularioSerie([Map<String, dynamic>? serie]) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StreamingSeriesFormScreen(serie: serie),
      ),
    );
    if (salvou == true) _carregar();
  }

  Future<void> _abrirFormularioTemporada([
    Map<String, dynamic>? temporada,
  ]) async {
    if (_series.isEmpty) {
      _snack('Cadastre uma série antes de criar temporadas.');
      return;
    }
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StreamingSeasonFormScreen(
          temporada: temporada,
          series: _series,
          seriesInicialId: _filtroSerieTemporada,
        ),
      ),
    );
    if (salvou == true) _carregar();
  }

  Future<void> _abrirImportacaoEpisodios() async {
    if (_series.isEmpty) {
      _snack('Cadastre uma série e uma temporada antes de importar links.');
      return;
    }
    if (_temporadas.isEmpty) {
      _snack('Cadastre uma temporada antes de importar links.');
      return;
    }
    final importou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StreamingEpisodeImportScreen(
          series: _series,
          temporadas: _temporadas,
          seriesInicialId: _filtroSerieEpisodio,
          seasonInicialId: _filtroTemporadaEpisodio,
        ),
      ),
    );
    if (importou == true) _carregar();
  }

  Future<void> _abrirFormularioEpisodio([
    Map<String, dynamic>? episodio,
  ]) async {
    if (_series.isEmpty) {
      _snack('Cadastre uma série e uma temporada antes de criar episódios.');
      return;
    }
    if (_temporadas.isEmpty) {
      _snack('Cadastre uma temporada antes de criar episódios.');
      return;
    }
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StreamingEpisodeFormScreen(
          episodio: episodio,
          series: _series,
          temporadas: _temporadas,
          seasonInicialId: _filtroTemporadaEpisodio,
        ),
      ),
    );
    if (salvou == true) _carregar();
  }

  Future<void> _excluirSerie(Map<String, dynamic> serie) async {
    final id = serie['id']?.toString() ?? '';
    final temporadas = _temporadasCount(id);
    final episodios = _episodiosCountDaSerie(id);
    final confirmar = await _confirmarExclusaoCritica(
      titulo: 'Excluir série',
      mensagem:
          'Isso apaga "${serie['title']}" e também $temporadas temporada(s), '
          '$episodios episódio(s), progresso, favoritos e histórico vinculados. '
          'Esta ação não pode ser desfeita.',
    );
    if (!confirmar) return;
    try {
      await _service.excluirSerie(id);
      _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  Future<void> _excluirTemporada(Map<String, dynamic> temporada) async {
    final id = temporada['id']?.toString() ?? '';
    final episodios = _episodiosCountDaTemporada(temporada);
    final confirmar = episodios > 0
        ? await _confirmarExclusaoCritica(
            titulo: 'Excluir temporada',
            mensagem:
                'Esta temporada tem $episodios episódio(s). Todos serão apagados '
                'junto com o progresso e histórico vinculados. Digite EXCLUIR para confirmar.',
          )
        : await confirmarExclusao(
            context,
            titulo: 'Excluir temporada',
            mensagem: 'Remover esta temporada?',
          );
    if (!confirmar) return;
    try {
      await _service.excluirTemporada(id);
      _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  Future<void> _excluirEpisodio(Map<String, dynamic> episodio) async {
    final confirmar = await confirmarExclusao(
      context,
      titulo: 'Excluir episódio',
      mensagem:
          'Remover "${episodio['title']}"? O progresso e o histórico deste '
          'episódio também serão apagados.',
    );
    if (!confirmar) return;
    try {
      await _service.excluirEpisodio(episodio['id']?.toString() ?? '');
      _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  Future<bool> _confirmarExclusaoCritica({
    required String titulo,
    required String mensagem,
  }) async {
    final controle = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final digitou = controle.text.trim() == 'EXCLUIR';
          return AlertDialog(
            title: Text(titulo),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mensagem),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controle,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Digite EXCLUIR para confirmar',
                    ),
                    onChanged: (_) => setDialog(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: digitou ? () => Navigator.pop(ctx, true) : null,
                child: Text(
                  'Excluir',
                  style: TextStyle(
                    color: digitou ? ThemeColors.error(ctx) : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    controle.dispose();
    return confirmado == true;
  }

  Future<void> _reordenar({
    required List<Map<String, dynamic>> lista,
    required int index,
    required int delta,
    required Future<void> Function(String id, int ordem) atualizar,
  }) async {
    final novoIndice = index + delta;
    if (novoIndice < 0 || novoIndice >= lista.length) return;

    final copia = List<Map<String, dynamic>>.from(lista);
    final item = copia.removeAt(index);
    copia.insert(novoIndice, item);
    try {
      for (var i = 0; i < copia.length; i++) {
        final id = copia[i]['id']?.toString();
        if (id != null) await atualizar(id, (i + 1) * 10);
      }
      await _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  Future<void> _salvarHome() async {
    setState(() => _salvandoHome = true);
    try {
      await _service.saveHomeConfig(heroSeriesId: _heroId, sections: _secoes);
      _snack('Página inicial atualizada.');
    } catch (e) {
      _snack(mapErroAdmin(e));
    } finally {
      if (mounted) setState(() => _salvandoHome = false);
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _subAbas(),
        Expanded(
          child: switch (_subAba) {
            0 => _seriesTab(),
            1 => _temporadasTab(),
            2 => _episodiosTab(),
            3 => _homeTab(),
            _ => _assinaturasTab(),
          },
        ),
      ],
    );
  }

  Widget _subAbas() {
    final itens = [
      ('Séries', Icons.movie_rounded),
      ('Temporadas', Icons.video_library_rounded),
      ('Episódios', Icons.playlist_play_rounded),
      ('Home', Icons.dashboard_customize_rounded),
      ('Assinaturas', Icons.workspace_premium_rounded),
    ];
    return Container(
      color: ThemeColors.surface(context),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.md, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(itens.length, (index) {
            final item = itens[index];
            final ativo = _subAba == index;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _subAba = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: ativo
                        ? ThemeColors.primary(context).withValues(alpha: 0.16)
                        : ThemeColors.surfaceVariant(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ativo
                          ? ThemeColors.primary(context)
                          : ThemeColors.outline(context),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$2,
                        size: 15,
                        color: ativo
                            ? ThemeColors.primary(context)
                            : ThemeColors.secondaryText(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        item.$1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ativo
                              ? ThemeColors.primary(context)
                              : ThemeColors.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _seriesTab() {
    return Column(
      children: [
        _cabecalhoLista(
          titulo: '${_series.length} séries cadastradas',
          botao: 'Nova série',
          onNovo: () => _abrirFormularioSerie(),
        ),
        Expanded(
          child: _series.isEmpty
              ? const StreamingEmptyState(
                  title: 'Nenhuma série cadastrada',
                  message:
                      'Crie a primeira produção para começar a montar o catálogo.',
                  icon: Icons.movie_filter_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    80,
                  ),
                  itemCount: _series.length,
                  itemBuilder: (context, index) {
                    final serie = _series[index];
                    final id = serie['id']?.toString() ?? '';
                    final status = serie['status']?.toString() ?? 'rascunho';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: ThemeColors.surface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ThemeColors.outline(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _abrirFormularioSerie(serie),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 52,
                                  height: 78,
                                  child: StreamingNetworkImage(
                                    url:
                                        serie['cover_url']?.toString() ??
                                        serie['banner_url']?.toString(),
                                    memCacheWidth: 220,
                                    fallbackIcon: Icons.movie_outlined,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      serie['title']?.toString() ?? 'Série',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
                                      children: [
                                        StreamingStatusChip(status: status),
                                        if (serie['is_featured'] == true)
                                          StreamingBadge(
                                            label: 'DESTAQUE',
                                            color: ThemeColors.primary(context),
                                          ),
                                        if ((serie['required_plan_level']
                                                    as num? ??
                                                0) >
                                            0)
                                          StreamingBadge(
                                            label: 'EXCLUSIVO',
                                            color: ThemeColors.primary(context),
                                          ),
                                        if (serie['category'] != null)
                                          StreamingBadge(
                                            label: serie['category']
                                                .toString()
                                                .toUpperCase(),
                                            color: ThemeColors.secondaryText(
                                              context,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_temporadasCount(id)} temporada(s) • '
                                      '${_episodiosCountDaSerie(id)} episódio(s)'
                                      '${serie['release_year'] != null ? ' • ${serie['release_year']}' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: ThemeColors.secondaryText(
                                              context,
                                            ),
                                            fontSize: 9,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (acao) async {
                                  switch (acao) {
                                    case 'editar':
                                      _abrirFormularioSerie(serie);
                                      break;
                                    case 'publicar':
                                      await _service.atualizarStatusSerie(
                                        id,
                                        'publicado',
                                      );
                                      _carregar();
                                      break;
                                    case 'despublicar':
                                      await _service.atualizarStatusSerie(
                                        id,
                                        'rascunho',
                                      );
                                      _carregar();
                                      break;
                                    case 'arquivar':
                                      await _service.atualizarStatusSerie(
                                        id,
                                        'arquivado',
                                      );
                                      _carregar();
                                      break;
                                    case 'destacar':
                                      await _service.destacarSerie(
                                        id,
                                        serie['is_featured'] != true,
                                      );
                                      _carregar();
                                      break;
                                    case 'subir':
                                      await _reordenar(
                                        lista: _series,
                                        index: index,
                                        delta: -1,
                                        atualizar: _service.atualizarOrdemSerie,
                                      );
                                      break;
                                    case 'descer':
                                      await _reordenar(
                                        lista: _series,
                                        index: index,
                                        delta: 1,
                                        atualizar: _service.atualizarOrdemSerie,
                                      );
                                      break;
                                    case 'excluir':
                                      await _excluirSerie(serie);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'editar',
                                    child: Text('Editar'),
                                  ),
                                  if (status == 'publicado')
                                    const PopupMenuItem(
                                      value: 'despublicar',
                                      child: Text('Despublicar'),
                                    )
                                  else
                                    const PopupMenuItem(
                                      value: 'publicar',
                                      child: Text('Publicar'),
                                    ),
                                  if (status != 'arquivado')
                                    const PopupMenuItem(
                                      value: 'arquivar',
                                      child: Text('Arquivar'),
                                    ),
                                  PopupMenuItem(
                                    value: 'destacar',
                                    child: Text(
                                      serie['is_featured'] == true
                                          ? 'Remover destaque'
                                          : 'Destacar',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'subir',
                                    child: Text('Mover para cima'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'descer',
                                    child: Text('Mover para baixo'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'excluir',
                                    child: Text('Excluir'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _temporadasTab() {
    final lista = _temporadasDaSerie(_filtroSerieTemporada);
    return Column(
      children: [
        _seletorSerie(
          valor: _filtroSerieTemporada,
          onChanged: (valor) => setState(() => _filtroSerieTemporada = valor),
        ),
        _cabecalhoLista(
          titulo: '${lista.length} temporada(s)',
          botao: 'Nova temporada',
          onNovo: () => _abrirFormularioTemporada(),
        ),
        Expanded(
          child: _series.isEmpty
              ? const StreamingEmptyState(
                  title: 'Cadastre uma série primeiro',
                  message: 'As temporadas pertencem a uma série já cadastrada.',
                  icon: Icons.video_library_outlined,
                )
              : lista.isEmpty
              ? const StreamingEmptyState(
                  title: 'Nenhuma temporada',
                  message:
                      'Crie a primeira temporada desta série para organizar os episódios.',
                  icon: Icons.video_library_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    80,
                  ),
                  itemCount: lista.length,
                  itemBuilder: (context, index) {
                    final temporada = lista[index];
                    final id = temporada['id']?.toString() ?? '';
                    final status =
                        temporada['status']?.toString() ?? 'rascunho';
                    final episodios = _episodiosCountDaTemporada(temporada);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: ThemeColors.surface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ThemeColors.outline(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
                      ),
                      child: ListTile(
                        onTap: () => _abrirFormularioTemporada(temporada),
                        leading: CircleAvatar(
                          backgroundColor: ThemeColors.surfaceVariant(context),
                          child: Text(
                            'T${temporada['season_number'] ?? '?'}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          temporada['title']?.toString() ??
                              'Temporada ${temporada['season_number']}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 5,
                            runSpacing: 3,
                            children: [
                              StreamingStatusChip(status: status),
                              StreamingBadge(
                                label: '$episodios EPISÓDIO(S)',
                                color: ThemeColors.secondaryText(context),
                              ),
                            ],
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (acao) async {
                            switch (acao) {
                              case 'editar':
                                _abrirFormularioTemporada(temporada);
                                break;
                              case 'publicar':
                                await _service.atualizarStatusTemporada(
                                  id,
                                  'publicado',
                                );
                                _carregar();
                                break;
                              case 'despublicar':
                                await _service.atualizarStatusTemporada(
                                  id,
                                  'rascunho',
                                );
                                _carregar();
                                break;
                              case 'subir':
                                await _reordenar(
                                  lista: lista,
                                  index: index,
                                  delta: -1,
                                  atualizar: _service.atualizarOrdemTemporada,
                                );
                                break;
                              case 'descer':
                                await _reordenar(
                                  lista: lista,
                                  index: index,
                                  delta: 1,
                                  atualizar: _service.atualizarOrdemTemporada,
                                );
                                break;
                              case 'excluir':
                                await _excluirTemporada(temporada);
                                break;
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'editar',
                              child: Text('Editar'),
                            ),
                            if (status == 'publicado')
                              const PopupMenuItem(
                                value: 'despublicar',
                                child: Text('Despublicar'),
                              )
                            else
                              const PopupMenuItem(
                                value: 'publicar',
                                child: Text('Publicar'),
                              ),
                            const PopupMenuItem(
                              value: 'subir',
                              child: Text('Mover para cima'),
                            ),
                            const PopupMenuItem(
                              value: 'descer',
                              child: Text('Mover para baixo'),
                            ),
                            const PopupMenuItem(
                              value: 'excluir',
                              child: Text('Excluir'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _episodiosTab() {
    final temporadas = _temporadasDaSerie(_filtroSerieEpisodio);
    final lista = _episodiosDaTemporada(_filtroTemporadaEpisodio);
    return Column(
      children: [
        _seletorSerie(
          valor: _filtroSerieEpisodio,
          onChanged: (valor) {
            final temporadasDaSerie = _temporadasDaSerie(valor);
            final primeira = temporadasDaSerie.isEmpty
                ? null
                : temporadasDaSerie.first['id']?.toString();
            setState(() {
              _filtroSerieEpisodio = valor;
              _filtroTemporadaEpisodio = primeira;
            });
            _carregarEpisodios(primeira);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: DropdownButtonFormField<String>(
            key: ValueKey('filtro-temporada-${_filtroSerieEpisodio ?? ''}'),
            initialValue:
                temporadas.any(
                  (item) => item['id']?.toString() == _filtroTemporadaEpisodio,
                )
                ? _filtroTemporadaEpisodio
                : null,
            decoration: const InputDecoration(
              labelText: 'Filtrar por temporada',
              isDense: true,
            ),
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
            onChanged: (valor) {
              setState(() => _filtroTemporadaEpisodio = valor);
              _carregarEpisodios(valor);
            },
          ),
        ),
        _cabecalhoLista(
          titulo: '${lista.length} episódio(s)',
          botao: 'Novo episódio',
          onNovo: () => _abrirFormularioEpisodio(),
          botaoSecundario: 'Importar links',
          onSecundario: _abrirImportacaoEpisodios,
        ),
        Expanded(
          child: _series.isEmpty || _temporadas.isEmpty
              ? const StreamingEmptyState(
                  title: 'Estrutura incompleta',
                  message:
                      'Cadastre uma série e pelo menos uma temporada antes dos episódios.',
                  icon: Icons.playlist_add_rounded,
                )
              : lista.isEmpty
              ? const StreamingEmptyState(
                  title: 'Nenhum episódio',
                  message: 'Adicione o primeiro episódio desta temporada.',
                  icon: Icons.playlist_remove_rounded,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    80,
                  ),
                  itemCount: lista.length,
                  itemBuilder: (context, index) {
                    final episodio = lista[index];
                    final id = episodio['id']?.toString() ?? '';
                    final status = episodio['status']?.toString() ?? 'rascunho';
                    final publicadoEm = DateTime.tryParse(
                      episodio['published_at']?.toString() ?? '',
                    );
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: ThemeColors.surface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ThemeColors.outline(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _abrirFormularioEpisodio(episodio),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 108,
                                  height: 61,
                                  child: StreamingNetworkImage(
                                    url:
                                        episodio['thumbnail_url']?.toString() ??
                                        (episodio['youtube_video_id'] != null
                                            ? 'https://img.youtube.com/vi/'
                                                  '${episodio['youtube_video_id']}/hqdefault.jpg'
                                            : null),
                                    memCacheWidth: 320,
                                    fallbackIcon:
                                        Icons.play_circle_outline_rounded,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'EP ${episodio['episode_number']} • '
                                      '${episodio['title'] ?? 'Episódio'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 3,
                                      children: [
                                        StreamingStatusChip(status: status),
                                        if (publicadoEm != null)
                                          StreamingBadge(
                                            label: formatarDataStreaming(
                                              publicadoEm,
                                            ),
                                            color: ThemeColors.secondaryText(
                                              context,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (acao) async {
                                  switch (acao) {
                                    case 'editar':
                                      _abrirFormularioEpisodio(episodio);
                                      break;
                                    case 'publicar':
                                      await _service.atualizarStatusEpisodio(
                                        id,
                                        'publicado',
                                      );
                                      _carregar();
                                      break;
                                    case 'despublicar':
                                      await _service.atualizarStatusEpisodio(
                                        id,
                                        'rascunho',
                                      );
                                      _carregar();
                                      break;
                                    case 'subir':
                                      await _reordenar(
                                        lista: lista,
                                        index: index,
                                        delta: -1,
                                        atualizar:
                                            _service.atualizarOrdemEpisodio,
                                      );
                                      break;
                                    case 'descer':
                                      await _reordenar(
                                        lista: lista,
                                        index: index,
                                        delta: 1,
                                        atualizar:
                                            _service.atualizarOrdemEpisodio,
                                      );
                                      break;
                                    case 'excluir':
                                      await _excluirEpisodio(episodio);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'editar',
                                    child: Text('Editar'),
                                  ),
                                  if (status == 'publicado')
                                    const PopupMenuItem(
                                      value: 'despublicar',
                                      child: Text('Despublicar'),
                                    )
                                  else
                                    const PopupMenuItem(
                                      value: 'publicar',
                                      child: Text('Publicar agora'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'subir',
                                    child: Text('Mover para cima'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'descer',
                                    child: Text('Mover para baixo'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'excluir',
                                    child: Text('Excluir'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  int _centavosDoTexto(String texto) {
    var t = texto.replaceAll(RegExp(r'[^0-9,.]'), '').trim();
    if (t.isEmpty) return 0;
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      final partes = t.split('.');
      if (partes.length > 1 && partes.last.length != 2) {
        t = t.replaceAll('.', '');
      }
    }
    return ((double.tryParse(t) ?? 0) * 100).round();
  }

  String _slugPlano(String nome) {
    final base = nome
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return base.isEmpty
        ? 'plano-${DateTime.now().millisecondsSinceEpoch}'
        : base;
  }

  Future<void> _abrirFormularioPlano([Map<String, dynamic>? plano]) async {
    final nomeCtrl = TextEditingController(
      text: plano?['nome']?.toString() ?? '',
    );
    final slugCtrl = TextEditingController(
      text: plano?['slug']?.toString() ?? '',
    );
    final descricaoCtrl = TextEditingController(
      text: plano?['descricao']?.toString() ?? '',
    );
    final precoCtrl = TextEditingController(
      text: plano == null
          ? ''
          : ((plano['preco_centavos'] as num? ?? 0) / 100)
                .toStringAsFixed(2)
                .replaceAll('.', ','),
    );
    final trialCtrl = TextEditingController(
      text: plano?['trial_dias']?.toString() ?? '0',
    );
    final telasCtrl = TextEditingController(
      text: plano?['max_telas']?.toString() ?? '1',
    );
    final qualidadeCtrl = TextEditingController(
      text: plano?['qualidade']?.toString() ?? '',
    );
    final beneficiosCtrl = TextEditingController(
      text:
          (plano?['beneficios'] as List?)
              ?.map((item) => item.toString())
              .join('\n') ??
          '',
    );
    final ordemCtrl = TextEditingController(
      text: plano?['ordem']?.toString() ?? '0',
    );
    var nivel = (plano?['nivel'] as num?)?.toInt() ?? 1;
    var periodo = plano?['periodo']?.toString() ?? 'mensal';
    var ativo = plano?['ativo'] == true;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(plano == null ? 'Novo plano' : 'Editar plano'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomeCtrl,
                    decoration: const InputDecoration(labelText: 'Nome'),
                  ),
                  TextField(
                    controller: slugCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Slug',
                      hintText: 'opest-plus-mensal',
                    ),
                  ),
                  TextField(
                    controller: descricaoCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: precoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Preço (R\$)',
                            hintText: '19,90',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: periodo,
                          decoration: const InputDecoration(
                            labelText: 'Período',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'mensal',
                              child: Text('Mensal'),
                            ),
                            DropdownMenuItem(
                              value: 'anual',
                              child: Text('Anual'),
                            ),
                          ],
                          onChanged: (valor) =>
                              setDialog(() => periodo = valor ?? 'mensal'),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: nivel,
                          decoration: const InputDecoration(labelText: 'Nível'),
                          items: const [
                            DropdownMenuItem(
                              value: 1,
                              child: Text('1 — Básico'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('2 — Padrão'),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text('3 — Premium'),
                            ),
                          ],
                          onChanged: (valor) =>
                              setDialog(() => nivel = valor ?? 1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: ordemCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Ordem'),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: trialCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Dias grátis',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: telasCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Telas'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: qualidadeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Qualidade',
                      hintText: 'HD, Full HD, 4K...',
                    ),
                  ),
                  TextField(
                    controller: beneficiosCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Benefícios (um por linha)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: ativo,
                    onChanged: (valor) => setDialog(() => ativo = valor),
                    title: const Text('Plano ativo'),
                    subtitle: const Text(
                      'Só planos ativos aparecem para os usuários.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;
    final nome = nomeCtrl.text.trim();
    if (nome.isEmpty) {
      _snack('Informe o nome do plano.');
      return;
    }
    final beneficios = beneficiosCtrl.text
        .split('\n')
        .map((linha) => linha.trim())
        .where((linha) => linha.isNotEmpty)
        .toList();

    try {
      await _service.salvarPlano({
        'nome': nome,
        'slug': slugCtrl.text.trim().isEmpty
            ? _slugPlano(nome)
            : slugCtrl.text.trim(),
        'descricao': descricaoCtrl.text.trim().isEmpty
            ? null
            : descricaoCtrl.text.trim(),
        'nivel': nivel,
        'preco_centavos': _centavosDoTexto(precoCtrl.text),
        'periodo': periodo,
        'trial_dias': int.tryParse(trialCtrl.text.trim()) ?? 0,
        'max_telas': int.tryParse(telasCtrl.text.trim()) ?? 1,
        'qualidade': qualidadeCtrl.text.trim().isEmpty
            ? null
            : qualidadeCtrl.text.trim(),
        'beneficios': beneficios,
        'ativo': ativo,
        'ordem': int.tryParse(ordemCtrl.text.trim()) ?? 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, id: plano?['id']?.toString());
      _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  Future<void> _excluirPlano(Map<String, dynamic> plano) async {
    final confirmar = await confirmarExclusao(
      context,
      titulo: 'Excluir plano',
      mensagem:
          'Remover "${plano['nome']}"? Planos com assinaturas vinculadas não podem ser excluídos.',
    );
    if (!confirmar) return;
    try {
      await _service.excluirPlano(plano['id']?.toString() ?? '');
      _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  String _gerarCodigo() {
    const letras = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    String bloco() =>
        List.generate(4, (_) => letras[random.nextInt(letras.length)]).join();
    return 'PEST-${bloco()}-${bloco()}';
  }

  String? _dataIsoCodigo(String texto) {
    final limpo = texto.trim();
    if (limpo.isEmpty) return null;
    final partes = limpo.split('/');
    if (partes.length == 3) {
      final dia = int.tryParse(partes[0]);
      final mes = int.tryParse(partes[1]);
      final ano = int.tryParse(partes[2]);
      if (dia != null && mes != null && ano != null) {
        return DateTime.utc(ano, mes, dia).toIso8601String();
      }
    }
    return DateTime.tryParse(limpo)?.toUtc().toIso8601String();
  }

  Future<void> _abrirFormularioCodigo([Map<String, dynamic>? codigo]) async {
    final codigoCtrl = TextEditingController(
      text: codigo?['codigo']?.toString() ?? _gerarCodigo(),
    );
    final duracaoCtrl = TextEditingController(
      text: codigo?['duracao_dias']?.toString() ?? '30',
    );
    final usosCtrl = TextEditingController(
      text: codigo?['usos_maximos']?.toString() ?? '1',
    );
    final expiraCtrl = TextEditingController(
      text: codigo?['expira_em'] == null
          ? ''
          : formatarDataStreaming(
              DateTime.tryParse(codigo!['expira_em'].toString()),
            ),
    );
    final obsCtrl = TextEditingController(
      text: codigo?['observacao']?.toString() ?? '',
    );
    var nivel = (codigo?['plano_nivel'] as num?)?.toInt() ?? 1;
    var ativo = codigo?['ativo'] != false;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(codigo == null ? 'Novo código' : 'Editar código'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codigoCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código',
                      hintText: 'PEST-XXXX-XXXX',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: duracaoCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Duração (dias)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: usosCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Usos máximos',
                          ),
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: nivel,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Nível liberado',
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 — O Pest+')),
                      DropdownMenuItem(value: 2, child: Text('2 — Superior')),
                      DropdownMenuItem(value: 3, child: Text('3 — Premium')),
                    ],
                    onChanged: (valor) => setDialog(() => nivel = valor ?? 1),
                  ),
                  TextField(
                    controller: expiraCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Validade do código',
                      hintText: 'dd/mm/aaaa',
                    ),
                  ),
                  TextField(
                    controller: obsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Observação (ex.: sorteio do Instagram)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: ativo,
                    onChanged: (valor) => setDialog(() => ativo = valor),
                    title: const Text('Código ativo'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;
    final textoCodigo = codigoCtrl.text.trim().toUpperCase();
    if (textoCodigo.isEmpty) {
      _snack('Informe o código.');
      return;
    }
    final duracao = int.tryParse(duracaoCtrl.text.trim()) ?? 0;
    final usos = int.tryParse(usosCtrl.text.trim()) ?? 0;
    if (duracao <= 0 || usos <= 0) {
      _snack('Duração e usos devem ser maiores que zero.');
      return;
    }

    try {
      await _service.salvarCodigoAcesso({
        'codigo': textoCodigo,
        'plano_nivel': nivel,
        'duracao_dias': duracao,
        'usos_maximos': usos,
        'ativo': ativo,
        'expira_em': _dataIsoCodigo(expiraCtrl.text),
        'observacao': obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, id: codigo?['id']?.toString());
      _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  Future<void> _desativarCodigo(Map<String, dynamic> codigo) async {
    try {
      await _service.salvarCodigoAcesso({
        'ativo': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, id: codigo['id']?.toString());
      _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  Future<void> _excluirCodigo(Map<String, dynamic> codigo) async {
    final confirmar = await _confirmarExclusaoCritica(
      titulo: 'Excluir código',
      mensagem:
          'O código "${codigo['codigo']}" e os acessos temporários vinculados '
          'serão removidos. Digite EXCLUIR para confirmar.',
    );
    if (!confirmar) return;
    try {
      await _service.excluirCodigoAcesso(codigo['id']?.toString() ?? '');
      _carregar();
    } catch (e) {
      _snack(mapErroAdmin(e));
    }
  }

  Future<void> _copiarCodigo(String codigo) async {
    await Clipboard.setData(ClipboardData(text: codigo));
    _snack('Código copiado: $codigo');
  }

  Widget _assinaturasTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        100,
      ),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Planos e assinaturas',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _abrirFormularioPlano(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Novo plano'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Planos definem o nível de acesso. O conteúdo exclusivo exige que o '
          'assinante tenha nível igual ou superior ao definido na série/episódio.',
          style: TextStyle(
            fontSize: 11,
            color: ThemeColors.secondaryText(context),
          ),
        ),
        const SizedBox(height: 12),
        if (_planos.isEmpty)
          const StreamingEmptyState(
            title: 'Nenhum plano cadastrado',
            message:
                'Crie um plano, configure o preço e ative para liberar as assinaturas.',
            icon: Icons.workspace_premium_outlined,
          )
        else
          ..._planos.map((plano) {
            final ativo = plano['ativo'] == true;
            final beneficios = plano['beneficios'] is List
                ? (plano['beneficios'] as List).length
                : 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: ThemeColors.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ThemeColors.outline(context).withValues(alpha: 0.6),
                ),
              ),
              child: ListTile(
                onTap: () => _abrirFormularioPlano(plano),
                leading: CircleAvatar(
                  backgroundColor: ThemeColors.surfaceVariant(context),
                  child: Text(
                    'N${plano['nivel'] ?? 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(
                  plano['nome']?.toString() ?? 'Plano',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    children: [
                      StreamingBadge(
                        label: ativo ? 'ATIVO' : 'INATIVO',
                        color: ativo
                            ? ThemeColors.success(context)
                            : ThemeColors.hint(context),
                      ),
                      StreamingBadge(
                        label: formatarMoeda(
                          ((plano['preco_centavos'] as num? ?? 0) / 100),
                        ),
                        color: ThemeColors.primary(context),
                      ),
                      StreamingBadge(
                        label: (plano['periodo']?.toString() ?? 'mensal')
                            .toUpperCase(),
                        color: ThemeColors.secondaryText(context),
                      ),
                      StreamingBadge(
                        label: '$beneficios BENEFÍCIO(S)',
                        color: ThemeColors.secondaryText(context),
                      ),
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (acao) {
                    if (acao == 'editar') {
                      _abrirFormularioPlano(plano);
                    } else if (acao == 'excluir') {
                      _excluirPlano(plano);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'editar', child: Text('Editar')),
                    PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Códigos de acesso',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _abrirFormularioCodigo(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Novo código'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Códigos liberam acesso temporário sem cobrança. '
          'Use para sorteios e fãs.',
          style: TextStyle(
            fontSize: 11,
            color: ThemeColors.secondaryText(context),
          ),
        ),
        const SizedBox(height: 8),
        if (_codigos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                'Nenhum código cadastrado.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          )
        else
          ..._codigos.map((codigo) {
            final ativo = codigo['ativo'] == true;
            final expira = DateTime.tryParse(
              codigo['expira_em']?.toString() ?? '',
            );
            final expirado = expira != null && expira.isBefore(DateTime.now());
            final usos = (codigo['usos'] as num?)?.toInt() ?? 0;
            final maxUsos = (codigo['usos_maximos'] as num?)?.toInt() ?? 0;
            final cor = ativo && !expirado
                ? ThemeColors.success(context)
                : ThemeColors.error(context);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: ThemeColors.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ThemeColors.outline(context).withValues(alpha: 0.6),
                ),
              ),
              child: ListTile(
                onTap: () => _abrirFormularioCodigo(codigo),
                leading: Icon(
                  Icons.confirmation_number_rounded,
                  color: cor,
                  size: 22,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        codigo['codigo']?.toString() ?? 'CÓDIGO',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copiar',
                      onPressed: () =>
                          _copiarCodigo(codigo['codigo']?.toString() ?? ''),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    children: [
                      StreamingBadge(
                        label: ativo && !expirado ? 'ATIVO' : 'INATIVO',
                        color: cor,
                      ),
                      StreamingBadge(
                        label: 'N${codigo['plano_nivel'] ?? 1}',
                        color: ThemeColors.primary(context),
                      ),
                      StreamingBadge(
                        label: '${codigo['duracao_dias'] ?? 30} DIAS',
                        color: ThemeColors.secondaryText(context),
                      ),
                      StreamingBadge(
                        label: '$usos/$maxUsos USOS',
                        color: ThemeColors.secondaryText(context),
                      ),
                      if (expira != null)
                        StreamingBadge(
                          label: 'ATÉ ${formatarDataStreaming(expira)}',
                          color: ThemeColors.secondaryText(context),
                        ),
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (acao) {
                    if (acao == 'editar') {
                      _abrirFormularioCodigo(codigo);
                    } else if (acao == 'desativar') {
                      _desativarCodigo(codigo);
                    } else if (acao == 'excluir') {
                      _excluirCodigo(codigo);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'editar', child: Text('Editar')),
                    if (ativo)
                      const PopupMenuItem(
                        value: 'desativar',
                        child: Text('Desativar'),
                      ),
                    const PopupMenuItem(
                      value: 'excluir',
                      child: Text('Excluir'),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 20),
        Text(
          'Assinaturas',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          '${_assinaturas.length} assinatura(s) registrada(s)',
          style: TextStyle(
            fontSize: 11,
            color: ThemeColors.secondaryText(context),
          ),
        ),
        const SizedBox(height: 8),
        if (_assinaturas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'Nenhuma assinatura ainda.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          )
        else
          ..._assinaturas.map((assinatura) {
            final status = assinatura['status']?.toString() ?? 'pendente';
            final perfil = assinatura['perfis'] is Map
                ? Map<String, dynamic>.from(assinatura['perfis'] as Map)
                : <String, dynamic>{};
            final nome =
                perfil['nome']?.toString() ??
                assinatura['payer_email']?.toString() ??
                'Usuário';
            final email =
                perfil['email']?.toString() ??
                assinatura['payer_email']?.toString() ??
                '';
            final fim = formatarDataStreaming(
              DateTime.tryParse(
                assinatura['current_period_end']?.toString() ?? '',
              ),
            );
            final cor = status == 'ativa'
                ? ThemeColors.success(context)
                : status == 'pendente'
                ? ThemeColors.warning(context)
                : ThemeColors.error(context);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: ThemeColors.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ThemeColors.outline(context).withValues(alpha: 0.6),
                ),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.workspace_premium_rounded,
                  color: cor,
                  size: 22,
                ),
                title: Text(
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 5,
                        runSpacing: 3,
                        children: [
                          StreamingBadge(
                            label: status.toUpperCase(),
                            color: cor,
                          ),
                          StreamingBadge(
                            label:
                                assinatura['plan_nome']?.toString() ?? 'Plano',
                            color: ThemeColors.primary(context),
                          ),
                          if (fim.isNotEmpty)
                            StreamingBadge(
                              label: 'ATÉ $fim',
                              color: ThemeColors.secondaryText(context),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (acao) async {
                    try {
                      await _service.atualizarStatusAssinatura(
                        assinatura['id']?.toString() ?? '',
                        acao,
                        dias: assinatura['periodo'] == 'anual' ? 365 : 30,
                      );
                      _carregar();
                    } catch (e) {
                      _snack(mapErroAdmin(e));
                    }
                  },
                  itemBuilder: (_) => [
                    if (status != 'ativa')
                      const PopupMenuItem(
                        value: 'ativa',
                        child: Text('Ativar manualmente'),
                      ),
                    if (status == 'ativa' ||
                        status == 'pendente' ||
                        status == 'pausada')
                      const PopupMenuItem(
                        value: 'cancelada',
                        child: Text('Cancelar assinatura'),
                      ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: ThemeColors.surfaceVariant(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Ativar/cancelar manualmente não altera a cobrança no Mercado Pago. '
            'Use o painel do Mercado Pago para cancelar a recorrência oficial.',
            style: TextStyle(fontSize: 10, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _homeTab() {
    final seriesPublicadas = _series
        .where((item) => item['status']?.toString() == 'publicado')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        100,
      ),
      children: [
        const StreamingAdminSectionTitle(
          title: 'Banner principal',
          subtitle:
              'A série escolhida aparece no destaque cinematográfico da aba Séries.',
        ),
        DropdownButtonFormField<String>(
          initialValue:
              _heroId != null &&
                  _series.any((item) => item['id']?.toString() == _heroId)
              ? _heroId
              : null,
          decoration: const InputDecoration(
            labelText: 'Série em destaque',
            isDense: true,
          ),
          items: seriesPublicadas
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
          onChanged: (valor) => setState(() => _heroId = valor),
        ),
        if (seriesPublicadas.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Publique uma série para escolher o banner principal.',
              style: TextStyle(
                color: ThemeColors.warning(context),
                fontSize: 11,
              ),
            ),
          ),
        const SizedBox(height: 20),
        const StreamingAdminSectionTitle(
          title: 'Seções da página inicial',
          subtitle:
              'Ative, desative e ordene as seções exibidas na aba Séries.',
        ),
        ...List.generate(_secoes.length, (index) {
          final secao = _secoes[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: ThemeColors.surface(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: ThemeColors.outline(context).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 8),
                    value: secao.enabled,
                    onChanged: (valor) {
                      setState(() {
                        _secoes[index] = secao.copyWith(enabled: valor);
                      });
                    },
                    title: Text(
                      secao.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: index == 0
                      ? null
                      : () {
                          setState(() {
                            final item = _secoes.removeAt(index);
                            _secoes.insert(index - 1, item);
                          });
                        },
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
                IconButton(
                  onPressed: index == _secoes.length - 1
                      ? null
                      : () {
                          setState(() {
                            final item = _secoes.removeAt(index);
                            _secoes.insert(index + 1, item);
                          });
                        },
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _salvandoHome ? null : _salvarHome,
          icon: _salvandoHome
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded),
          label: Text(_salvandoHome ? 'Salvando...' : 'Salvar página inicial'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _seletorSerie({
    required String? valor,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: DropdownButtonFormField<String>(
        initialValue: _series.any((item) => item['id']?.toString() == valor)
            ? valor
            : null,
        decoration: const InputDecoration(labelText: 'Série', isDense: true),
        items: _series
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
        onChanged: onChanged,
      ),
    );
  }

  Widget _cabecalhoLista({
    required String titulo,
    required String botao,
    required VoidCallback onNovo,
    String? botaoSecundario,
    VoidCallback? onSecundario,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (botaoSecundario != null && onSecundario != null) ...[
            OutlinedButton.icon(
              onPressed: onSecundario,
              icon: const Icon(Icons.link_rounded, size: 16),
              label: Text(
                botaoSecundario,
                style: const TextStyle(fontSize: 11),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            onPressed: onNovo,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(botao, style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}
