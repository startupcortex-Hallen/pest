import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/helpers/theme_colors.dart';
import '../../../core/helpers/youtube_url.dart';
import '../../../core/theme/app_spacing.dart';
import '../streaming/widgets/youtube_preview_dialog.dart';
import 'admin_utils.dart';
import 'streaming_admin_widgets.dart';

class StreamingSeriesFormScreen extends StatefulWidget {
  final Map<String, dynamic>? serie;

  const StreamingSeriesFormScreen({super.key, this.serie});

  @override
  State<StreamingSeriesFormScreen> createState() =>
      _StreamingSeriesFormScreenState();
}

class _StreamingSeriesFormScreenState extends State<StreamingSeriesFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _slug;
  late final TextEditingController _descricao;
  late final TextEditingController _sinopse;
  late final TextEditingController _categoria;
  late final TextEditingController _classificacao;
  late final TextEditingController _ano;
  late final TextEditingController _ordem;
  late final TextEditingController _elenco;
  late final TextEditingController _trailer;
  late String _capa;
  late String _banner;
  late String _status;
  late bool _destaque;
  late int _nivelPlano;
  String? _trailerId;
  bool _salvando = false;

  bool get _editando => widget.serie != null;

  @override
  void initState() {
    super.initState();
    final s = widget.serie;
    _titulo = TextEditingController(text: s?['title']?.toString() ?? '');
    _slug = TextEditingController(text: s?['slug']?.toString() ?? '');
    _descricao = TextEditingController(
      text: s?['description']?.toString() ?? '',
    );
    _sinopse = TextEditingController(text: s?['synopsis']?.toString() ?? '');
    _categoria = TextEditingController(text: s?['category']?.toString() ?? '');
    _classificacao = TextEditingController(
      text: s?['age_rating']?.toString() ?? '',
    );
    _ano = TextEditingController(text: s?['release_year']?.toString() ?? '');
    _ordem = TextEditingController(
      text: s?['display_order']?.toString() ?? '0',
    );
    _elenco = TextEditingController(text: s?['cast_members']?.toString() ?? '');
    _trailer = TextEditingController(text: s?['trailer_url']?.toString() ?? '');
    _capa = s?['cover_url']?.toString() ?? '';
    _banner = s?['banner_url']?.toString() ?? '';
    _status = s?['status']?.toString() ?? 'rascunho';
    _destaque = s?['is_featured'] == true;
    _nivelPlano = (s?['required_plan_level'] as num?)?.toInt() ?? 0;
    _trailerId = YoutubeUrl.extractId(
      s?['trailer_youtube_id']?.toString() ?? _trailer.text,
    );
  }

  @override
  void dispose() {
    _titulo.dispose();
    _slug.dispose();
    _descricao.dispose();
    _sinopse.dispose();
    _categoria.dispose();
    _classificacao.dispose();
    _ano.dispose();
    _ordem.dispose();
    _elenco.dispose();
    _trailer.dispose();
    super.dispose();
  }

  String? _textoOuNull(TextEditingController controller) {
    final texto = controller.text.trim();
    return texto.isEmpty ? null : texto;
  }

  String _gerarSlug(String texto) {
    const acentos = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    var resultado = texto.toLowerCase();
    acentos.forEach((origem, destino) {
      resultado = resultado.replaceAll(origem, destino);
    });
    resultado = resultado
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (resultado.isEmpty) {
      resultado = 'serie-${DateTime.now().millisecondsSinceEpoch}';
    }
    return resultado;
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    if (!_formKey.currentState!.validate()) return;

    final slugTexto = _slug.text.trim().isEmpty
        ? _gerarSlug(_titulo.text)
        : _slug.text.trim();
    final trailerId = YoutubeUrl.extractId(_trailer.text);

    setState(() => _salvando = true);
    try {
      final dados = <String, dynamic>{
        'title': _titulo.text.trim(),
        'slug': slugTexto,
        'description': _textoOuNull(_descricao),
        'synopsis': _textoOuNull(_sinopse),
        'category': _textoOuNull(_categoria),
        'age_rating': _textoOuNull(_classificacao),
        'release_year': int.tryParse(_ano.text.trim()),
        'display_order': int.tryParse(_ordem.text.trim()) ?? 0,
        'cast_members': _textoOuNull(_elenco),
        'cover_url': _capa.trim().isEmpty ? null : _capa.trim(),
        'banner_url': _banner.trim().isEmpty ? null : _banner.trim(),
        'status': _status,
        'is_featured': _destaque,
        'required_plan_level': _nivelPlano,
        'trailer_youtube_id': trailerId,
        'trailer_url': YoutubeUrl.normalizedUrl(_trailer.text),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final client = Supabase.instance.client;
      if (_editando) {
        await client
            .from('streaming_series')
            .update(dados)
            .eq('id', widget.serie!['id']);
      } else {
        await client.from('streaming_series').insert(dados);
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

  void _previsualizarTrailer() {
    final id = _trailerId;
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
        titulo: 'Trailer — ${_titulo.text.trim()}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idTrailerValido = _trailerId;

    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.background(context),
        foregroundColor: ThemeColors.primaryText(context),
        title: Text(_editando ? 'Editar série' : 'Nova série'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            120,
          ),
          children: [
            const StreamingAdminSectionTitle(
              title: 'Informações principais',
              subtitle:
                  'Tudo o que aparece na aba Séries e na página da produção.',
            ),
            TextFormField(
              controller: _titulo,
              textCapitalization: TextCapitalization.words,
              decoration: adminInputDec(context, 'Título da série*'),
              validator: (valor) => (valor == null || valor.trim().isEmpty)
                  ? 'Informe o título.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _slug,
              decoration:
                  adminInputDec(
                    context,
                    'Slug (URL amigável)',
                    hint: 'de-dentro-da-favela',
                  ).copyWith(
                    helperText: _editando
                        ? 'O slug não muda automaticamente ao editar.'
                        : 'Deixe vazio para gerar a partir do título.',
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _categoria,
                    textCapitalization: TextCapitalization.words,
                    decoration: adminInputDec(context, 'Categoria'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _classificacao,
                    decoration: adminInputDec(
                      context,
                      'Classificação',
                      hint: 'Ex.: 16',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ano,
                    keyboardType: TextInputType.number,
                    decoration: adminInputDec(context, 'Ano de início'),
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
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: adminInputDec(context, 'Status'),
              items: const [
                DropdownMenuItem(value: 'rascunho', child: Text('Rascunho')),
                DropdownMenuItem(value: 'publicado', child: Text('Publicado')),
                DropdownMenuItem(value: 'arquivado', child: Text('Arquivado')),
              ],
              onChanged: (valor) =>
                  setState(() => _status = valor ?? 'rascunho'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _destaque,
              onChanged: (valor) => setState(() => _destaque = valor),
              title: const Text('Série em destaque'),
              subtitle: const Text(
                'Aparece na seção "Séries em destaque" do catálogo.',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _nivelPlano,
              decoration: adminInputDec(context, 'Acesso ao conteúdo').copyWith(
                helperText:
                    '0 = grátis. 1/2/3 = exige assinatura com nível igual ou superior.',
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
            const StreamingAdminSectionTitle(
              title: 'Descrição',
              subtitle:
                  'A sinopse curta aparece nos cards; a descrição na página da série.',
            ),
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
            const SizedBox(height: 10),
            TextFormField(
              controller: _elenco,
              maxLines: 2,
              decoration: adminInputDec(
                context,
                'Elenco / participantes',
                hint: 'Separe os nomes por vírgula',
              ),
            ),
            const Divider(height: 30),
            const StreamingAdminSectionTitle(
              title: 'Trailer',
              subtitle:
                  'Cole a URL de um vídeo do YouTube que permita incorporação.',
            ),
            TextFormField(
              controller: _trailer,
              keyboardType: TextInputType.url,
              decoration:
                  adminInputDec(
                    context,
                    'URL do trailer (YouTube)',
                    hint: 'https://www.youtube.com/watch?v=...',
                  ).copyWith(
                    errorText:
                        _trailer.text.trim().isNotEmpty &&
                            idTrailerValido == null
                        ? 'URL de vídeo inválida.'
                        : null,
                    helperText:
                        'Formatos aceitos: watch?v=, youtu.be, embed, shorts.',
                  ),
              onChanged: (valor) {
                setState(() {
                  _trailerId = YoutubeUrl.extractId(valor);
                });
              },
            ),
            if (idTrailerValido != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _previsualizarTrailer,
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('Pré-visualizar trailer'),
              ),
            ],
            const Divider(height: 30),
            const StreamingAdminSectionTitle(
              title: 'Imagens',
              subtitle:
                  'Capa vertical 2:3 e banner horizontal 16:9. As imagens não são esticadas.',
            ),
            StreamingImageField(
              label: 'Capa da série',
              hint: 'Proporção recomendada: 2:3 (vertical).',
              value: _capa,
              folder: 'series',
              aspectRatio: 2 / 3,
              icon: Icons.movie_outlined,
              onChanged: (url) => setState(() => _capa = url),
            ),
            StreamingImageField(
              label: 'Banner horizontal',
              hint: 'Proporção recomendada: 16:9 ou mais larga.',
              value: _banner,
              folder: 'banners',
              aspectRatio: 16 / 9,
              icon: Icons.panorama_horizontal_outlined,
              onChanged: (url) => setState(() => _banner = url),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ElevatedButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'Salvando...' : 'Salvar série'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ),
    );
  }
}
