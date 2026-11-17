import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'admin_utils.dart';
import 'streaming_admin_widgets.dart';

class StreamingSeasonFormScreen extends StatefulWidget {
  final Map<String, dynamic>? temporada;
  final List<Map<String, dynamic>> series;
  final String? seriesInicialId;

  const StreamingSeasonFormScreen({
    super.key,
    this.temporada,
    required this.series,
    this.seriesInicialId,
  });

  @override
  State<StreamingSeasonFormScreen> createState() =>
      _StreamingSeasonFormScreenState();
}

class _StreamingSeasonFormScreenState extends State<StreamingSeasonFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numero;
  late final TextEditingController _titulo;
  late final TextEditingController _descricao;
  late final TextEditingController _dataLancamento;
  late final TextEditingController _ordem;
  late String _seriesId;
  late String _status;
  late String _capa;
  bool _salvando = false;

  bool get _editando => widget.temporada != null;

  @override
  void initState() {
    super.initState();
    final t = widget.temporada;
    _numero = TextEditingController(
      text: t?['season_number']?.toString() ?? '1',
    );
    _titulo = TextEditingController(text: t?['title']?.toString() ?? '');
    _descricao = TextEditingController(
      text: t?['description']?.toString() ?? '',
    );
    _dataLancamento = TextEditingController(
      text: _dataTexto(t?['release_date']),
    );
    _ordem = TextEditingController(
      text: t?['display_order']?.toString() ?? '9999',
    );
    _status = t?['status']?.toString() ?? 'rascunho';
    _capa = t?['cover_url']?.toString() ?? '';
    _seriesId =
        t?['series_id']?.toString() ??
        widget.seriesInicialId ??
        (widget.series.isNotEmpty
            ? widget.series.first['id']?.toString() ?? ''
            : '');
  }

  String _dataTexto(dynamic valor) {
    if (valor == null) return '';
    final data = DateTime.tryParse(valor.toString());
    if (data == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(data.day)}/${p(data.month)}/${data.year}';
  }

  String? _dataIso(String texto) {
    final limpo = texto.trim();
    if (limpo.isEmpty) return null;
    final partes = limpo.split('/');
    if (partes.length == 3) {
      final dia = int.tryParse(partes[0]);
      final mes = int.tryParse(partes[1]);
      final ano = int.tryParse(partes[2]);
      if (dia != null && mes != null && ano != null) {
        final data = DateTime.utc(ano, mes, dia);
        return data.toIso8601String().split('T').first;
      }
    }
    final data = DateTime.tryParse(limpo);
    if (data == null) return null;
    return data.toIso8601String().split('T').first;
  }

  @override
  void dispose() {
    _numero.dispose();
    _titulo.dispose();
    _descricao.dispose();
    _dataLancamento.dispose();
    _ordem.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    if (!_formKey.currentState!.validate()) return;
    if (_seriesId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione a série da temporada.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final dados = <String, dynamic>{
        'series_id': _seriesId,
        'season_number': int.tryParse(_numero.text.trim()) ?? 1,
        'title': _titulo.text.trim().isEmpty ? null : _titulo.text.trim(),
        'description': _descricao.text.trim().isEmpty
            ? null
            : _descricao.text.trim(),
        'release_date': _dataIso(_dataLancamento.text),
        'display_order': int.tryParse(_ordem.text.trim()) ?? 0,
        'status': _status,
        'cover_url': _capa.trim().isEmpty ? null : _capa.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final client = Supabase.instance.client;
      if (_editando) {
        await client
            .from('streaming_seasons')
            .update(dados)
            .eq('id', widget.temporada!['id']);
      } else {
        await client.from('streaming_seasons').insert(dados);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      appBar: AppBar(
        backgroundColor: ThemeColors.background(context),
        foregroundColor: ThemeColors.primaryText(context),
        title: Text(_editando ? 'Editar temporada' : 'Nova temporada'),
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
              title: 'Dados da temporada',
              subtitle:
                  'A temporada pertence a uma série e organiza os episódios.',
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
              onChanged: (valor) => setState(() => _seriesId = valor ?? ''),
              validator: (valor) => (valor == null || valor.isEmpty)
                  ? 'Selecione a série.'
                  : null,
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
                      'Número da temporada*',
                      hint: 'Ex.: 1',
                    ),
                    validator: (valor) {
                      final numero = int.tryParse(valor?.trim() ?? '');
                      if (numero == null || numero <= 0) {
                        return 'Informe um número válido.';
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
            const SizedBox(height: 10),
            TextFormField(
              controller: _titulo,
              textCapitalization: TextCapitalization.sentences,
              decoration: adminInputDec(
                context,
                'Título da temporada',
                hint: 'Ex.: 1ª temporada',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descricao,
              maxLines: 3,
              decoration: adminInputDec(context, 'Descrição'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dataLancamento,
                    decoration: adminInputDec(
                      context,
                      'Data de lançamento',
                      hint: 'dd/mm/aaaa',
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
            const Divider(height: 30),
            const StreamingAdminSectionTitle(
              title: 'Capa da temporada',
              subtitle: 'Proporção recomendada: 2:3 (vertical).',
            ),
            StreamingImageField(
              label: 'Imagem da temporada',
              hint: 'Opcional. Sem capa, o app usa a imagem da série.',
              value: _capa,
              folder: 'seasons',
              aspectRatio: 2 / 3,
              icon: Icons.video_library_outlined,
              onChanged: (url) => setState(() => _capa = url),
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
            label: Text(_salvando ? 'Salvando...' : 'Salvar temporada'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ),
    );
  }
}
