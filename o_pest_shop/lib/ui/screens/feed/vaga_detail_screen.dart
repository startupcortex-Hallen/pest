import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/feed_comment.dart';
import '../../../models/feed_post.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/feed_service.dart';
import '../../../core/helpers/time_ago.dart';
import '../../widgets/animated_card_entry.dart';

class VagaDetailScreen extends StatefulWidget {
  final String postId;
  const VagaDetailScreen({super.key, required this.postId});

  @override
  State<VagaDetailScreen> createState() => _VagaDetailScreenState();
}

class _VagaDetailScreenState extends State<VagaDetailScreen> {
  final _feedService = FeedService();
  FeedPost? _post;
  bool _loading = true;
  bool _jaCandidatou = false;
  String? _curriculoUrl;
  List<FeedComment> _comments = [];
  bool _enviando = false;
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  double _bannerHeight = 240;
  YoutubePlayerController? _ytController;

  String? get _userId => context.read<AuthProvider>().user?.id;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final offset = _scrollCtrl.offset;
      setState(() => _bannerHeight = (240 - offset).clamp(0.0, 240.0).toDouble());
    });
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    _ytController?.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final supabase = Supabase.instance.client;
      final postJson = await supabase
          .from('posts_feed')
          .select()
          .eq('id', widget.postId)
          .maybeSingle();

      if (postJson != null) {
        _post = FeedPost.fromJson(postJson as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Erro vaga detail: $e');
    }

    if (_userId != null && _post != null) {
      try {
        _jaCandidatou = await _feedService.checkCandidatura(widget.postId, _userId!);
        if (_jaCandidatou) {
          final resp = await Supabase.instance.client
              .from('candidaturas')
              .select('url_curriculo')
              .eq('vaga_id', widget.postId)
              .eq('user_id', _userId!)
              .maybeSingle();
          if (resp != null) _curriculoUrl = resp['url_curriculo'] as String?;
        }
        } catch (e) {
          debugPrint('Erro: $e');
        }
    }

    try {
      _comments = await _feedService.fetchComments(widget.postId);
    } catch (e) {
      debugPrint('Erro: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendComment() async {
    final texto = _commentCtrl.text.trim();
    if (texto.isEmpty || _userId == null) return;
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      // Verifica se já comentou
      final jaComentou = await _feedService.checkJaComentou(widget.postId, _userId!);
      if (jaComentou) {
        _commentCtrl.clear();
        if (mounted) _mostrarDialogJaComentou();
        return;
      }
      await _feedService.addComment(widget.postId, _userId!, texto);
      _commentCtrl.clear();
      _comments = await _feedService.fetchComments(widget.postId);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Erro: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível enviar seu comentário. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _mostrarDialogJaComentou() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: const Color(0xFFFFAD01).withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.info_outline_rounded, color: Color(0xFFFFAD01), size: 28),
          ),
          const SizedBox(height: 16),
          const Text('Você já comentou nesta publicação',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Para evitar spam, você só pode comentar uma vez por publicação.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFFC6C6C6))),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white),
              child: const Text('Entendi'),
            ),
          ),
        ]),
      ),
    );
  }

  void _abrirFormulario() async {
    if (_jaCandidatou) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded, color: ThemeColors.success(ctx), size: 56),
            const SizedBox(height: 16),
            const Text('Você já se candidatou para essa vaga', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Aguarde o processo seletivo.', textAlign: TextAlign.center, style: TextStyle(color: ThemeColors.secondaryText(ctx))),
            if (_curriculoUrl != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(_curriculoUrl!);
                  if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri);
                },
                icon: const Icon(Icons.download_rounded), label: const Text('Baixar currículo enviado'),
              ),
            ],
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    final nomeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final telefoneCtrl = TextEditingController();
    final phoneMask = MaskTextInputFormatter(mask: '## # #####-####', filter: {"#": RegExp(r'[0-9]')});
    PlatformFile? pdfSelecionado;
    bool enviando = false;

    // Auto-preenche nome do perfil do usuario
    if (_userId != null) {
      try {
        final perfil = await Supabase.instance.client
            .from('perfis')
            .select('nome, email')
            .eq('id', _userId!)
            .maybeSingle();
        if (perfil != null) {
          nomeCtrl.text = perfil['nome'] as String? ?? '';
          emailCtrl.text = perfil['email'] as String? ?? '';
        }
      } catch (e) {
        debugPrint('Erro: $e');
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Candidate-se', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: nomeCtrl, decoration: InputDecoration(labelText: 'Nome completo', border: OutlineInputBorder(), filled: true, fillColor: ThemeColors.surfaceVariant(context))),
            const SizedBox(height: 8),
            TextField(controller: emailCtrl, decoration: InputDecoration(labelText: 'E-mail', border: OutlineInputBorder(), filled: true, fillColor: ThemeColors.surfaceVariant(context))),
            const SizedBox(height: 8),
            TextField(controller: telefoneCtrl, decoration: InputDecoration(labelText: 'Telefone (opcional)', border: OutlineInputBorder(), filled: true, fillColor: ThemeColors.surfaceVariant(context)),
              keyboardType: TextInputType.phone, inputFormatters: [phoneMask]),
            const SizedBox(height: 16),
            const Text('Currículo (PDF)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
                if (r != null && r.files.isNotEmpty) setSheetState(() => pdfSelecionado = r.files.first);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  border: Border.all(color: pdfSelecionado != null ? ThemeColors.primary(context) : ThemeColors.outline(context)),
                  borderRadius: BorderRadius.circular(12),
                  color: pdfSelecionado != null ? ThemeColors.primary(context).withValues(alpha: 0.05) : ThemeColors.surfaceVariant(context),
                ),
                child: Column(children: [
                  Icon(pdfSelecionado != null ? Icons.description_rounded : Icons.upload_file_rounded, color: pdfSelecionado != null ? ThemeColors.primary(context) : ThemeColors.hint(context), size: 36),
                  const SizedBox(height: 8),
                  Text(pdfSelecionado != null ? pdfSelecionado!.name : 'Selecionar PDF', style: TextStyle(color: pdfSelecionado != null ? ThemeColors.primary(context) : ThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 50, child: ElevatedButton.icon(
              onPressed: enviando ? null : () async {
                if (nomeCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || pdfSelecionado == null) return;
                setSheetState(() => enviando = true);
                try {
                  String? urlCurriculo;
                  final Uint8List? conteudo = pdfSelecionado!.bytes;
                  if (conteudo != null) {
                    final fileName = 'curriculo_${_userId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
                    await Supabase.instance.client.storage.from('Curriculos').uploadBinary(fileName, conteudo, fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true));
                    urlCurriculo = Supabase.instance.client.storage.from('Curriculos').getPublicUrl(fileName);
                  }
                  await _feedService.submitCandidatura({'vaga_id': widget.postId, 'user_id': _userId, 'nome': nomeCtrl.text.trim(), 'email': emailCtrl.text.trim(), 'telefone': telefoneCtrl.text.trim(), 'url_curriculo': urlCurriculo});
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() => _jaCandidatou = true);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Candidatura enviada com sucesso!')));
                } catch (e) {
                  setSheetState(() => enviando = false);
                  if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: ThemeColors.error(context)));
                }
              },
              icon: enviando ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: ThemeColors.onPrimary(context))) : const Icon(Icons.send_rounded),
              label: Text(enviando ? 'Enviando...' : 'Enviar Candidatura'),
              style: ElevatedButton.styleFrom(backgroundColor: ThemeColors.primary(context), foregroundColor: ThemeColors.onPrimary(context), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            )),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(backgroundColor: ThemeColors.background(context), appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop())), body: const Center(child: CircularProgressIndicator()));
    if (_post == null) return Scaffold(backgroundColor: ThemeColors.background(context), appBar: AppBar(backgroundColor: ThemeColors.surface(context), leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop())), body: const Center(child: Text('Vaga não encontrada')));

    final p = _post!;

    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: Column(
                children: [
                  // Banner
                  SizedBox(
                    height: _bannerHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (p.urlYoutube != null && p.urlYoutube!.isNotEmpty)
                          _buildBannerYoutube(p.urlYoutube!)
                        else if (p.urlImagem != null && p.urlImagem!.isNotEmpty)
                          Hero(
                            tag: 'post_${p.id}',
                            child: CachedNetworkImage(imageUrl: p.urlImagem!, fit: BoxFit.cover, errorWidget: (_, __, ___) => _defaultBanner(), placeholder: (_, __) => Container(color: Colors.white)),
                          )
                        else
                          _defaultBanner(),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x99000000)]),
                          ),
                        ),
                        Positioned(top: MediaQuery.of(context).padding.top + 8, left: 16,
                          child: Container(
                            decoration: BoxDecoration(color: ThemeColors.surface(context).withValues(alpha: 0.8), shape: BoxShape.circle),
                            child: IconButton(icon: Icon(Icons.arrow_back_rounded, color: ThemeColors.primaryText(context)), onPressed: () => context.pop()),
                          ),
                        ),
                        Positioned(top: MediaQuery.of(context).padding.top + 8, right: 16,
                          child: Container(
                            decoration: BoxDecoration(color: ThemeColors.surface(context).withValues(alpha: 0.8), shape: BoxShape.circle),
                            child: IconButton(icon: Icon(Icons.share_rounded, color: ThemeColors.primaryText(context)), onPressed: () {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Card conteudo (sobreposto ao banner via transform —
                  // margin negativa é proibida no Container)
                  Container(
                    transform: Matrix4.translationValues(0, -24, 0),
                    decoration: BoxDecoration(
                      color: ThemeColors.surface(context),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.titulo, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              AnimatedCardEntry(
                                index: 0,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                                  _buildTag(Icons.location_on_rounded, _post!.categoria),
                                  _buildTag(Icons.schedule_rounded, 'Período Integral'),
                                  _buildTag(Icons.payments_rounded, 'A combinar'),
                                  _buildTag(Icons.work_outline_rounded, 'Vaga'),
                                ]),
                              ),
                            ),
                          ],
                          ),
                        ),
                        if (p.descricao != null && p.descricao!.isNotEmpty) ...[
                          const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg), child: Divider(height: 32)),
                          AnimatedCardEntry(
                            index: 1,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Sobre a vaga', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text(p.descricao!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ThemeColors.secondaryText(context), height: 1.6)),
                                ],
                              ),
                            ),
                          ),
                        ],
                        // Autor
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                          child: Row(
                            children: [
                              CircleAvatar(radius: context.w(20).clamp(16.0, 26.0), backgroundColor: ThemeColors.primary(context).withValues(alpha: 0.1),
                                child: Text(p.autorNome.isNotEmpty ? p.autorNome[0].toUpperCase() : 'E',
                                    style: TextStyle(color: ThemeColors.onPrimary(context), fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.autorNome, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  Text(timeAgo(_post!.createdAt), style: TextStyle(color: ThemeColors.hint(context), fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg), child: Divider(height: 32)),
                        // Comentários
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Comentários e Dúvidas (${_comments.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox.shrink(),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_comments.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: ThemeColors.surfaceVariant(context), borderRadius: BorderRadius.circular(12)),
                                  child: Text('Nenhum comentário ainda.', style: TextStyle(color: ThemeColors.secondaryText(context))),
                                )
                              else
                                ...(_comments.take(3).toList().asMap().entries.map((entry) {
                                  final ci = entry.key;
                                  final c = entry.value;
                                  return AnimatedCardEntry(
                                    index: ci + 2,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(radius: context.w(14).clamp(10.0, 18.0), backgroundColor: ThemeColors.surfaceVariant(context),
                                            child: Text(c.autorNome.isNotEmpty ? c.autorNome[0].toUpperCase() : 'U',
                                                style: TextStyle(fontSize: 10, color: ThemeColors.primary(context), fontWeight: FontWeight.bold))),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(c.autorNome, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                                                    const Spacer(),
                                                    _buildCommentDelete(c),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Text(c.texto, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ThemeColors.secondaryText(context))),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                })),
                              const SizedBox(height: 8),
                              // Input de comentário dentro do scroll
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: ThemeColors.outline(context)),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _commentCtrl,
                                        decoration: const InputDecoration(
                                          hintText: 'Digite seu comentário...',
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        ),
                                        textCapitalization: TextCapitalization.sentences,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.send_rounded, color: ThemeColors.primary(context)),
                                      onPressed: _sendComment,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 100),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom bar fixo
          Container(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            decoration: BoxDecoration(color: ThemeColors.surface(context), border: Border(top: BorderSide(color: ThemeColors.outline(context)))),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeColors.outline(context))),
                    child: IconButton(icon: Icon(Icons.favorite_border_rounded, color: ThemeColors.primaryText(context)), onPressed: () {}),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _abrirFormulario,
                        icon: const Icon(Icons.send_rounded),
                        label: Text(_jaCandidatou ? 'Candidatura Enviada' : 'Candidatar-se Agora', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        style: ElevatedButton.styleFrom(backgroundColor: ThemeColors.primary(context), foregroundColor: ThemeColors.onPrimary(context), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentDelete(FeedComment c) {
    final uid = _userId;
    final funcao = context.read<AuthProvider>().user?.funcao;
    final podeExcluir = uid == c.userId || funcao == 'admin' || funcao == 'atendente';
    if (!podeExcluir) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Excluir comentário'),
            content: const Text('Tem certeza?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: ThemeColors.error(ctx)))),
            ],
          ),
        );
        if (confirm != true) return;
        try {
          await _feedService.deleteComment(c.id);
          _comments = await _feedService.fetchComments(widget.postId);
          if (mounted) setState(() {});
        } catch (e) {
          debugPrint('Erro: $e');
        }
      },
      child: Icon(Icons.delete_outline_rounded, color: ThemeColors.hint(context), size: 18),
    );
  }

  Widget _buildTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: ThemeColors.primary(context).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: ThemeColors.primary(context)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, color: ThemeColors.primary(context), fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _defaultBanner() {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [ThemeColors.primary(context).withValues(alpha: 0.6), ThemeColors.primary(context).withValues(alpha: 0.2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: const Center(child: Icon(Icons.work_rounded, color: Colors.white, size: 80)),
    );
  }

  Widget _buildBannerYoutube(String url) {
    final videoId = YoutubePlayerController.convertUrlToId(url);
    if (videoId == null) return _defaultBanner();
    _ytController?.close();
    _ytController = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: false,
      ),
    );
    return YoutubePlayer(controller: _ytController!);
  }
}
