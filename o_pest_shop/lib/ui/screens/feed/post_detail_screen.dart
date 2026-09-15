import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/feed_comment.dart';
import '../../../models/feed_post.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/feed_provider.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/helpers/time_ago.dart';
import '../../../services/feed_service.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
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
    final supabase = Supabase.instance.client;

    try {
      final postJson = await supabase
          .from('posts_feed')
          .select()
          .eq('id', widget.postId)
          .maybeSingle();

      if (postJson != null) {
        _post = FeedPost.fromJson(postJson as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Erro ao buscar post: $e');
    }

    if (_post != null && _userId != null) {
      try {
        final likesData = await supabase
            .from('post_likes')
            .select('user_id')
            .eq('post_id', widget.postId);

        if (likesData is List) {
          final likeCount = likesData.length;
          final likedByMe = likesData.any((like) {
            if (like is Map) return like['user_id'] == _userId;
            return like == _userId;
          });
          _post = FeedPost(
            id: _post!.id,
            userId: _post!.userId,
            autorNome: _post!.autorNome,
            autorImagem: _post!.autorImagem,
            titulo: _post!.titulo,
            descricao: _post!.descricao,
            urlImagem: _post!.urlImagem,
            urlYoutube: _post!.urlYoutube,
            categoria: _post!.categoria,
            likeCount: likeCount,
            commentCount: _post!.commentCount,
            likedByMe: likedByMe,
            createdAt: _post!.createdAt,
          );
        }
      } catch (e) {
        debugPrint('Erro ao buscar likes: $e');
      }
    }

    try {
      _comments = await _feedService.fetchComments(widget.postId);
    } catch (e) {
      debugPrint('Erro ao buscar comentários: $e');
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
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(context),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_post == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(context),
        body: const Center(child: Text('Post não encontrado')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: _buildBody(),
          ),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    try {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildMediaSection(),
          _buildInfoSection(),
          _buildDescriptionSection(),
          _buildLikesSection(),
          _buildAuthorSection(),
          _buildCommentsSection(),
          const SizedBox(height: 80),
        ],
      );
    } catch (e) {
      debugPrint('Erro renderizar post: $e');
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.hint, size: 48),
            const SizedBox(height: 16),
            Text(
              'Não foi possível carregar este post',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.secondaryText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(8, 8, AppSpacing.md, 8),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.primaryText),
                onPressed: () => context.pop(),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.share_rounded,
                        color: AppColors.primaryText),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.favorite_border_rounded,
                      color: (_post?.likedByMe ?? false)
                          ? AppColors.error
                          : AppColors.primaryText,
                    ),
                    onPressed: () {
                      if (_post != null) {
                        context
                            .read<FeedProvider>()
                            .toggleLike(_post!.id);
                      }
                    },
                  ),
                  const Icon(Icons.bookmark_border_rounded,
                      color: AppColors.primaryText),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSection() {
    final p = _post;
    if (p == null) return const SizedBox.shrink();
    final yt = p.urlYoutube;
    if (yt != null && yt.isNotEmpty) {
      return _buildYoutubePlayer(yt);
    }
    final img = p.urlImagem;
    if (img != null && img.isNotEmpty) {
      return _buildImage(img);
    }
    return _buildCategoryHeader(p);
  }

  Widget _buildCategoryHeader(FeedPost p) {
    IconData icon;
    switch (p.categoria.toLowerCase()) {
      case 'avisos':
        icon = Icons.campaign_rounded;
        break;
      case 'eventos':
        icon = Icons.event_rounded;
        break;
      case 'comunicado':
      case 'comunicados':
        icon = Icons.campaign_rounded;
        break;
      case 'novidade':
      case 'novidades':
        icon = Icons.new_releases_rounded;
        break;
      default:
        icon = Icons.article_rounded;
    }
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.8), AppColors.primary.withValues(alpha: 0.3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 64),
            const SizedBox(height: AppSpacing.md),
            Text(
              p.categoria.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String url) {
    return Container(
      height: 320,
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Hero(
        tag: 'post_${_post!.id}',
        child: CachedNetworkImage(
          imageUrl: url,
          width: double.infinity,
          height: 320,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(
            height: 320,
            color: AppColors.surfaceVariant,
            child: const Center(child: Icon(Icons.image_outlined, color: AppColors.hint, size: 64)),
          ),
          placeholder: (_, __) => Container(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildYoutubePlayer(String url) {
    final videoId = YoutubePlayerController.convertUrlToId(url);
    if (videoId == null) return const SizedBox.shrink();
    _ytController?.close();
    _ytController = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: false,
      ),
    );
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: YoutubePlayer(controller: _ytController!),
    );
  }

  Widget _buildInfoSection() {
    final p = _post!;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${p.categoria}  •  ${tempoLeitura(p.descricao)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.secondaryText)),
              const Icon(Icons.verified_rounded, color: AppColors.info, size: 16),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(p.titulo,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 3),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              CircleAvatar(
                radius: context.w(12).clamp(10.0, 16.0),
                backgroundColor: AppColors.surfaceVariant,
                child: Text(p.autorNome.isNotEmpty ? p.autorNome[0].toUpperCase() : 'U',
                    style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Por ${p.autorNome}  •  ${timeAgo(p.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.secondaryText)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    final p = _post;
    if (p == null) return const SizedBox.shrink();
    final desc = p.descricao;
    if (desc == null || desc.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(desc,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.primaryText, height: 1.6)),
          const SizedBox(height: AppSpacing.sm),
          Text('Compartilhe este post e ajude mais pessoas a ficarem informadas.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText)),
        ],
      ),
    );
  }

  Widget _buildLikesSection() {
    final p = _post;
    if (p == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: InkWell(
        onTap: _mostrarCurtidas,
        child: Row(
          children: [
            Icon(Icons.favorite_rounded, color: AppColors.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${p.likeCount} curtidas',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: AppColors.hint, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorSection() {
    final p = _post!;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sobre o Autor',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              CircleAvatar(
                radius: context.w(24).clamp(18.0, 32.0),
                backgroundColor: AppColors.surfaceVariant,
                child: Text(p.autorNome.isNotEmpty ? p.autorNome[0].toUpperCase() : 'U',
                    style: TextStyle(fontSize: context.sp(14), color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: context.w(AppSpacing.md)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.autorNome,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(p.categoria == 'vagas' ? 'Recrutador' : 'Colaborador',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.secondaryText)),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStat('Curtidas', '${p.likeCount}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.secondaryText, fontSize: 11)),
      ],
    );
  }

  Widget _buildCommentsSection() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Comentários (${_comments.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.md),
          if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Nenhum comentário ainda. Seja o primeiro!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText)),
              ),
            )
          else
            ..._comments.map((c) => _buildCommentTile(c)),
        ],
      ),
    );
  }

  Widget _buildCommentTile(FeedComment c) {
    final isOwner = c.userId == _userId;
    final podeExcluir = isOwner || (_userId != null && (context.read<AuthProvider>().user?.funcao == 'admin' || context.read<AuthProvider>().user?.funcao == 'atendente'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: context.w(16).clamp(12.0, 20.0),
            backgroundColor: AppColors.surfaceVariant,
            child: Text(c.autorNome.isNotEmpty ? c.autorNome[0].toUpperCase() : 'U',
                style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(c.autorNome, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (podeExcluir)
                      GestureDetector(
                        onTap: () => _deleteComment(c.id, c.userId),
                        child: const Icon(Icons.delete_outline_rounded, color: AppColors.hint, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(c.texto, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarCurtidas() async {
    final supabase = Supabase.instance.client;
    final likes = await supabase
      .from('post_likes')
      .select('user_id, perfis(id, nome, avatar_url)')
      .eq('post_id', widget.postId);

    if (!mounted || likes == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Curtidas (${(likes as List).length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          ...likes.map((like) {
            final perfil = like['perfis'] as Map?;
            final nome = perfil?['nome'] as String? ?? 'Usuário';
            return ListTile(
              leading: CircleAvatar(child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : 'U')),
              title: Text(nome),
            );
          }),
        ],
      ),
    );
  }

  void _deleteComment(String commentId, String commentUserId) async {
    final uid = _userId;
    final funcao = context.read<AuthProvider>().user?.funcao;
    final podeExcluir = uid == commentUserId || funcao == 'admin' || funcao == 'atendente';
    if (!podeExcluir) return;

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
      await _feedService.deleteComment(commentId);
      _comments = await _feedService.fetchComments(widget.postId);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Erro ao deletar comentário: $e');
    }
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: AppColors.divider)),
      ),
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
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AppColors.primary),
              onPressed: _sendComment,
            ),
          ],
        ),
      ),
    );
  }
}
