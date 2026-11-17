import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/helpers/streaming_format.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/helpers/youtube_url.dart';
import '../../../core/theme/app_spacing.dart';
import '../streaming/widgets/youtube_preview_dialog.dart';
import 'admin_utils.dart';
import 'streaming_admin_widgets.dart';

class StreamingEpisodeFormScreen extends StatefulWidget {
  final Map<String, dynamic>? episodio;
  final List<Map<String, dynamic>> series;
  final List<Map<String, dynamic>> temporadas;
  final String? seasonInicialId;

  const StreamingEpisodeFormScreen({
    super.key,
    this.episodio,
    required this.series,
    required this.temporadas,
    this.seasonInicialId,
  });

  @override
  State<StreamingEpisodeFormScreen> createState() =>
      _StreamingEpisodeFormScreenState();
}

class _StreamingEpisodeFormScreenState
    extends State<StreamingEpisodeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numero;
  late final TextEditingController _titulo;
  late final TextEditingController _descricao;
  late final TextEditingController _sinopse;
  late final TextEditingController _youtube;
  late final TextEditingController _duracao;
  late final TextEditingController _publicacao;
  late final TextEditingController _ordem;
  late final TextEditingController _capa;
  late final TextEditingController _miniatura;

  late String _seriesId;
  late String _seasonId;
  late String _status;
  late bool _destaque;
  late int _nivelPlano;
  String? _youtubeId;
  bool _salvando = false;

  bool get _editando => widget.episodio != null;

  List<Map<String, dynamic>> get _temporadasDaSerie =>
      widget.temporadas
          .where((item) => item['series_id']?.toString() == _seriesId)
          .toList()
        ..sort((a, b) {
          final ordemA = (a['display_order'] as num?)?.toInt() ?? 0;
          final ordemB = (b['display_order'] as num?)?.toInt() ?? 0;
          if (ordemA != ordemB) return ordemA.compareTo(ordemB);
          final numeroA = (a['season_number'] as num?)?.toInt() ?? 0;
          final numeroB = (b['season_number'] as num?)?.toInt() ?? 0;
          return numeroA.compareTo(numeroB);
        });

  @override
  void initState() {
    super.initState();
    final e = widget.episodio;
    final seasonId =
        e?['season_id']?.toString() ??
        widget.seasonInicialId ??
        (widget.temporadas.isNotEmpty
            ? widget.temporadas.first['id']?.toString() ?? ''
            : '');
    Map<String, dynamic>? temporada;
    for (final item in widget.temporadas) {
      if (item['id']?.toString() == seasonId) {
        temporada = item;
        break;
      }
    }

    _numero = TextEditingController(
      text: e?['episode_number']?.toString() ?? '1',
    );
    _titulo = TextEditingController(text: e?['title']?.toString() ?? '');
    _descricao = TextEditingController(
      text: e?['description']?.toString() ?? '',
    );
    _sinopse = TextEditingController(text: e?['synopsis']?.toString() ?? '');
    _youtube = TextEditingController(
      text:
          e?['youtube_url']?.toString() ??
          (e?['youtube_video_id'] != null
              ? YoutubeUrl.watchUrl(e!['youtube_video_id'].toString())
              : ''),
    );
    _duracao = TextEditingController(
      text: e?['duration_seconds'] != null
          ? formatarTempoReproducao((e!['duration_seconds'] as num).toDouble())
          : '',
    );
    _publicacao = TextEditingController(
      text: _dataHoraTexto(e?['published_at']),
    );
    _ordem = TextEditingController(
      text: e?['display_order']?.toString() ?? '9999',
    );
    _capa = TextEditingController(text: e?['cover_url']?.toString() ?? '');
    _miniatura = TextEditingController(
      text: e?['thumbnail_url']?.toString() ?? '',
    );
    _status = e?['status']?.toString() ?? 'rascunho';
    _destaque = e?['is_featured'] == true;
    _nivelPlano = (e?['required_plan_level'] as num?)?.toInt() ?? 0;
    _seriesId =
        temporada?['series_id']?.toString() ??
        (widget.series.isNotEmpty
            ? widget.series.first['id']?.toString() ?? ''
            : '');
    _seasonId = seasonId;
    final videoIdInicial = e?['youtube_video_id']?.toString() ?? '';
    _youtubeId = YoutubeUrl.extractId(
      _youtube.text.isEmpty ? videoIdInicial : _youtube.text,
    );
  }

  String _dataHoraTexto(dynamic valor) {
    if (valor == null) return '';
    final data = DateTime.tryParse(valor.toString())?.toLocal();
    if (data == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(data.day)}/${p(data.month)}/${data.year} '
        '${p(data.hour)}:${p(data.minute)}';
  }

  DateTime? _dataHora(String texto) {
    final limpo = texto.trim();
    if (limpo.isEmpty) return null;

    final partes = limpo.split(' ');
    final dataPartes = partes.first.split('/');
    if (dataPartes.length == 3) {
      final dia = int.tryParse(dataPartes[0]);
      final mes = int.tryParse(dataPartes[1]);
      final ano = int.tryParse(dataPartes[2]);
      if (dia != null && mes != null && ano != null) {
        var hora = 0;
        var minuto = 0;
        if (partes.length > 1) {
          final horaPartes = partes[1].split(':');
          hora = int.tryParse(horaPartes[0]) ?? 0;
          minuto = horaPartes.length > 1 ? int.tryParse(horaPartes[1]) ?? 0 : 0;
        }
        return DateTime(ano, mes, dia, hora, minuto);
      }
    }

    final data = DateTime.tryParse(limpo);
    return data?.toLocal();
  }

  int? _duracaoSegundos(String texto) {
    final limpo = texto.trim();
    if (limpo.isEmpty) return null;
    if (limpo.contains(':')) {
      final partes = limpo.split(':').map(int.tryParse).toList();
      if (partes.any((item) => item == null)) return null;
      if (partes.length == 3) {
        return partes[0]! * 3600 + partes[1]! * 60 + partes[2]!;
      }
      if (partes.length == 2) {
        return partes[0]! * 60 + partes[1]!;
      }
      return null;
    }
    return int.tryParse(limpo);
  }

  @override
  void dispose() {
    _numero.dispose();
    _titulo.dispose();
    _descricao.dispose();
    _sinopse.dispose();
    _youtube.dispose();
    _duracao.dispose();
    _publicacao.dispose();
    _ordem.dispose();
    _capa.dispose();
    _miniatura.dispose();
    super.dispose();
  }

  void _alterarSerie(String? valor) {
    final novo = valor ?? '';
    final temporadas = widget.temporadas
        .where((item) => item['series_id']?.toString() == novo)
        .toList();
    setState(() {
      _seriesId = novo;
      _seasonId = temporadas.isNotEmpty
          ? temporadas.first['id']?.toString() ?? ''
          : '';
    });
  }

  Future<void> _salvar({bool publicar = false}) async {
    if (_salvando) return;
    if (!_formKey.currentState!.validate()) return;
    if (_seasonId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione a temporada do episódio.')),
      );
      return;
    }

    final youtubeId = YoutubeUrl.extractId(_youtube.text);
    if (youtubeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma URL válida de vídeo do YouTube.'),
        ),
      );
      return;
    }

    final publicacao = _dataHora(_publicacao.text);
    var status = publicar ? 'publicado' : _status;
    var publicadoEm = publicacao;

    if (publicar) {
      publicadoEm = publicacao ?? DateTime.now();
      status = publicadoEm.isAfter(DateTime.now()) ? 'agendado' : 'publicado';
    }

    if (status == 'agendado' && publicadoEm == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe a data de publicação do episódio agendado.'),
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final dados = <String, dynamic>{
        'season_id': _seasonId,
        'episode_number': int.tryParse(_numero.text.trim()) ?? 1,
        'title': _titulo.text.trim(),
        'description': _descricao.text.trim().isEmpty
            ? null
            : _descricao.text.trim(),
        'synopsis': _sinopse.text.trim().isEmpty ? null : _sinopse.text.trim(),
        'youtube_video_id': youtubeId,
        'youtube_url': YoutubeUrl.watchUrl(youtubeId),
        'cover_url': _capa.text.trim().isEmpty ? null : _capa.text.trim(),
        'thumbnail_url': _miniatura.text.trim().isEmpty
            ? null
            : _miniatura.text.trim(),
        'duration_seconds': _duracaoSegundos(_duracao.text),
        'published_at': publicadoEm?.toUtc().toIso8601String(),
        'status': status,
        'display_order': int.tryParse(_ordem.text.trim()) ?? 0,
        'is_featured': _destaque,
        'required_plan_level': _nivelPlano,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final client = Supabase.instance.client;
      if (_editando) {
        await client
            .from('streaming_episodes')
            .update(dados)
            .eq('id', widget.episodio!['id']);
      } else {
        await client.from('streaming_episodes').insert(dados);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mapErroAdmin(e))));
    }
  }

  void _previsualizarVideo() {
    final id = _youtubeId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe uma URL válida do YouTube.')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => YoutubePreviewDialog(
        videoId: id,
        titulo: _titulo.text.trim().isEmpty
            ? 'Pré-visualização do episódio'
            : _titulo.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final temporadas = _temporadasDaSerie;
    final temTemporadas = temporadas.isNotEmpty;
    final temporadaSelecionada = temporadas.any(
      (item) => item['id']?.toString() == _seasonId,
    );
    final idVideo = _youtubeId;

    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.background(context),
        foregroundColor: ThemeColors.primaryText(context),
        title: Text(_editando ? 'Editar episódio' : 'Novo episódio'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            140,
          ),
          children: [
            const StreamingAdminSectionTitle(
              title: 'Organização',
              subtitle:
                  'O episódio pertence a uma temporada. A numeração deve ser única na temporada.',
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
              validator: (valor) => (valor == null || valor.isEmpty)
                  ? 'Selecione a série.'
                  : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('temporada-$_seriesId-$_seasonId'),
              initialValue: temporadaSelecionada ? _seasonId : null,
              decoration: adminInputDec(context, 'Temporada*'),
              items: temporadas
                  .map(
                    (temporada) => DropdownMenuItem<String>(
                      value: temporada['id']?.toString(),
                      child: Text(
                        'T${temporada['season_number'] ?? '?'}'
                        '${temporada['title'] != null ? ' • ${temporada['title']}' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: temTemporadas
                  ? (valor) => setState(() => _seasonId = valor ?? '')
                  : null,
              validator: (valor) => (valor == null || valor.isEmpty)
                  ? 'Selecione a temporada.'
                  : null,
            ),
            if (!temTemporadas)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Esta série ainda não tem temporadas. Crie uma temporada primeiro.',
                  style: TextStyle(
                    color: ThemeColors.error(context),
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _numero,
                    keyboardType: TextInputType.number,
                    decoration: adminInputDec(
                      context,
                      'Número do episódio*',
                      hint: 'Ex.: 1',
                    ),
                    validator: (valor) {
                      final numero = int.tryParse(valor?.trim() ?? '');
                      if (numero == null || numero <= 0) {
                        return 'Número inválido.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _ordem,
                    keyboardType: TextInputType.number,
                    decoration: adminInputDec(
                      context,
                      'Ordem de exibição',
                      hint: 'Menor aparece primeiro',
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _destaque,
              onChanged: (valor) => setState(() => _destaque = valor),
              title: const Text('Episódio em destaque'),
              subtitle: const Text(
                'Pode ser usado em seções editoriais futuras.',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _nivelPlano,
              decoration: adminInputDec(context, 'Acesso ao episódio').copyWith(
                helperText:
                    'O nível efetivo é o maior entre a série e o episódio. 0 = grátis.',
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Grátis / público')),
                DropdownMenuItem(
                  value: 1,
                  child: Text('Exclusivo — O Pest+ Básico ou superior'),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text('Exclusivo — O Pest+ Padrão ou superior'),
                ),
                DropdownMenuItem(
                  value: 3,
                  child: Text('Exclusivo — O Pest+ Premium'),
                ),
              ],
              onChanged: (valor) => setState(() => _nivelPlano = valor ?? 0),
            ),
            const Divider(height: 30),
            const StreamingAdminSectionTitle(title: 'Conteúdo'),
            TextFormField(
              controller: _titulo,
              textCapitalization: TextCapitalization.sentences,
              decoration: adminInputDec(context, 'Título do episódio*'),
              validator: (valor) => (valor == null || valor.trim().isEmpty)
                  ? 'Informe o título.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _sinopse,
              maxLines: 2,
              decoration: adminInputDec(context, 'Sinopse curta'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descricao,
              maxLines: 4,
              decoration: adminInputDec(context, 'Descrição completa'),
            ),
            const Divider(height: 30),
            const StreamingAdminSectionTitle(
              title: 'Vídeo do YouTube',
              subtitle:
                  'O vídeo é incorporado pelo player oficial. Não armazenamos cópias do vídeo.',
            ),
            TextFormField(
              controller: _youtube,
              keyboardType: TextInputType.url,
              decoration:
                  adminInputDec(
                    context,
                    'URL do vídeo*',
                    hint: 'https://www.youtube.com/watch?v=...',
                  ).copyWith(
                    errorText:
                        _youtube.text.trim().isNotEmpty && idVideo == null
                        ? 'URL de vídeo inválida.'
                        : null,
                    helperText:
                        'Aceita watch?v=, youtu.be, embed e shorts. O ID é validado automaticamente.',
                  ),
              onChanged: (valor) {
                setState(() => _youtubeId = YoutubeUrl.extractId(valor));
              },
              validator: (valor) {
                if (YoutubeUrl.extractId(valor) == null) {
                  return 'Informe uma URL válida do YouTube.';
                }
                return null;
              },
            ),
            if (idVideo != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 120,
                      height: 68,
                      child: Image.network(
                        YoutubeUrl.thumbnailUrl(idVideo),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: ThemeColors.surfaceVariant(context),
                          child: const Icon(Icons.play_circle_outline_rounded),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _previsualizarVideo,
                      icon: const Icon(
                        Icons.play_circle_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Pré-visualizar vídeo'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _duracao,
                    decoration: adminInputDec(
                      context,
                      'Duração',
                      hint: 'mm:ss ou segundos',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: adminInputDec(context, 'Status'),
                    items: const [
                      DropdownMenuItem(
                        value: 'rascunho',
                        child: Text('Rascunho'),
                      ),
                      DropdownMenuItem(
                        value: 'publicado',
                        child: Text('Publicado'),
                      ),
                      DropdownMenuItem(
                        value: 'agendado',
                        child: Text('Agendado'),
                      ),
                      DropdownMenuItem(
                        value: 'arquivado',
                        child: Text('Arquivado'),
                      ),
                    ],
                    onChanged: (valor) =>
                        setState(() => _status = valor ?? 'rascunho'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _publicacao,
              decoration:
                  adminInputDec(
                    context,
                    'Data de publicação',
                    hint: 'dd/mm/aaaa hh:mm',
                  ).copyWith(
                    helperText:
                        'Se a data estiver no futuro ao publicar, o episódio ficará agendado.',
                  ),
            ),
            const Divider(height: 30),
            const StreamingAdminSectionTitle(
              title: 'Capas do episódio',
              subtitle:
                  'Proporção recomendada: 16:9. Sem imagem própria, o app usa a miniatura do YouTube.',
            ),
            StreamingImageField(
              label: 'Capa do episódio',
              hint: 'Opcional. Usada como imagem principal do episódio.',
              value: _capa.text,
              folder: 'episodes',
              aspectRatio: 16 / 9,
              icon: Icons.image_outlined,
              onChanged: (url) => setState(() => _capa.text = url),
            ),
            StreamingImageField(
              label: 'Miniatura',
              hint: 'Opcional. Formato 16:9.',
              value: _miniatura.text,
              folder: 'episodes',
              aspectRatio: 16 / 9,
              icon: Icons.image_outlined,
              onChanged: (url) => setState(() => _miniatura.text = url),
            ),
            if (idVideo != null && _miniatura.text.trim().isEmpty) ...[
              Text(
                'Miniatura automática do YouTube',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ThemeColors.secondaryText(context),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  YoutubeUrl.thumbnailUrl(idVideo),
                  width: double.infinity,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 100,
                    color: ThemeColors.surfaceVariant(context),
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _salvando ? null : () => _salvar(),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(_editando ? 'Salvar alterações' : 'Salvar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _salvando ? null : () => _salvar(publicar: true),
                  icon: _salvando
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.public_rounded, size: 18),
                  label: const Text('Publicar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
