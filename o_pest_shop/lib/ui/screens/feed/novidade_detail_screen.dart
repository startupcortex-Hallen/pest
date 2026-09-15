import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../models/feed_comment.dart';
import '../../../models/feed_post.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/feed_service.dart';

class NovidadeDetailScreen extends StatefulWidget {
  final String postId;
  const NovidadeDetailScreen({super.key, required this.postId});

  @override
  State<NovidadeDetailScreen> createState() => _NovidadeDetailScreenState();
}

class _NovidadeDetailScreenState extends State<NovidadeDetailScreen> {
  final _feedService = FeedService();
  FeedPost? _post;
  List<FeedComment> _comments = [];
  bool _loading = true;
  bool _enviando = false;
  final _commentCtrl = TextEditingController();
  YoutubePlayerController? _ytController;

  String? get _userId => context.read<AuthProvider>().user?.id;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _ytController?.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      final postJson = await supabase.from('posts_feed').select().eq('id', widget.postId).maybeSingle();
      if (postJson != null) {
        _post = FeedPost.fromJson(postJson as Map<String, dynamic>);
        if (_post!.urlYoutube != null && _post!.urlYoutube!.isNotEmpty) {
          final videoId = YoutubePlayerController.convertUrlToId(_post!.urlYoutube!);
          if (videoId != null) {
            _ytController = YoutubePlayerController.fromVideoId(
              videoId: videoId, autoPlay: false,
              params: const YoutubePlayerParams(showControls: true, showFullscreenButton: false),
            );
          }
        }
      }
      _comments = await _feedService.fetchComments(widget.postId);
    } catch (e) {
      debugPrint('Erro novidade detail: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendComment() async {
    final texto = _commentCtrl.text.trim();
    if (texto.isEmpty || _userId == null || _enviando) return;
    setState(() => _enviando = true);
    try {
      final jaComentou = await _feedService.checkJaComentou(widget.postId, _userId!);
      if (jaComentou) { _commentCtrl.clear(); if (mounted) _mostrarDialogJaComentou(); return; }
      await _feedService.addComment(widget.postId, _userId!, texto);
      _commentCtrl.clear();
      _comments = await _feedService.fetchComments(widget.postId);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Erro ao enviar comentário: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar seu comentário. Tente novamente.')),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Novidade'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
              ? const Center(child: Text('Novidade não encontrada'))
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          if (_ytController != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: YoutubePlayer(controller: _ytController!),
                            )
                          else if (_post!.urlImagem != null && _post!.urlImagem!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: Hero(
                                tag: 'post_${_post!.id}',
                                child: CachedNetworkImage(imageUrl: _post!.urlImagem!, height: 200, width: double.infinity, fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                                    placeholder: (_, __) => Container(color: Colors.white)),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.md),
                          Text(_post!.titulo, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: AppSpacing.sm),
                          if (_post!.descricao != null && _post!.descricao!.isNotEmpty)
                            Text(_post!.descricao!, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.primaryText, height: 1.6)),
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(),
                          const SizedBox(height: AppSpacing.sm),
                          Text('Comentários (${_comments.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: AppSpacing.sm),
                          if (_comments.isEmpty)
                            const Text('Nenhum comentário ainda.', style: TextStyle(color: AppColors.secondaryText))
                          else
                            ..._comments.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(radius: context.w(14).clamp(10, 18), backgroundColor: AppColors.surfaceVariant,
                                    child: Text(c.autorNome.isNotEmpty ? c.autorNome[0].toUpperCase() : 'U',
                                        style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold))),
                                  SizedBox(width: context.w(10)),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(c.autorNome, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600))),
                                          _buildCommentDelete(c),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(c.texto, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText)),
                                    ],
                                  )),
                                ],
                              ),
                            )),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      decoration: BoxDecoration(color: AppColors.surface, border: const Border(top: BorderSide(color: AppColors.divider))),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _commentCtrl,
                                decoration: InputDecoration(
                                  hintText: 'Digite seu comentário...',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  filled: true, fillColor: AppColors.surfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.primary), onPressed: _sendComment),
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
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: AppColors.error))),
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
      child: Icon(Icons.delete_outline_rounded, color: AppColors.hint, size: 18),
    );
  }
}
