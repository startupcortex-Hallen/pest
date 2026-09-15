import 'package:flutter/foundation.dart';
import '../models/feed_post.dart';
import '../services/auth_service.dart';
import '../services/feed_service.dart';

class FeedProvider extends ChangeNotifier {
  final FeedService _feedService;
  final AuthService _authService;

  FeedProvider(this._feedService, this._authService);

  List<FeedPost> _posts = [];
  List<String> _categorias = [];
  List<FeedPost> _filtered = [];
  String? _selectedCategoria;
  bool _loading = false;

  List<FeedPost> get feed => _selectedCategoria == null ? _posts : _filtered;
  List<String> get categorias => _categorias;
  String? get selectedCategoria => _selectedCategoria;
  bool get loading => _loading;
  String? get userId => _authService.currentUser?.id;

  Future<void> loadFeed() async {
    _loading = true;
    notifyListeners();

    try {
      _posts = await _feedService.fetchPosts(currentUserId: userId);
    } catch (e) {
      debugPrint('████████ ERRO FECTH POSTS: $e');
      _posts = [];
    }

    try {
      _categorias = await _feedService.fetchCategorias();
    } catch (e) {
      debugPrint('████████ ERRO FECTH CATEGORIAS: $e');
    }

    _aplicarFiltro();
    _loading = false;
    notifyListeners();
  }

  void selectCategoria(String? categoria) {
    _selectedCategoria = categoria;
    _aplicarFiltro();
    notifyListeners();
  }

  void _aplicarFiltro() {
    if (_selectedCategoria == null) {
      _filtered = [];
      return;
    }
    _filtered = _posts
        .where((p) => p.categoria.toLowerCase() == _selectedCategoria!.toLowerCase())
        .toList();
  }

  Future<void> toggleLike(String postId) async {
    final uid = userId;
    if (uid == null) return;

    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;

    final post = _posts[idx];
    if (post.likedByMe) {
      await _feedService.unlikePost(postId, uid);
    } else {
      await _feedService.likePost(postId, uid);
    }

    _posts[idx] = FeedPost(
      id: post.id,
      userId: post.userId,
      autorNome: post.autorNome,
      autorImagem: post.autorImagem,
      titulo: post.titulo,
      descricao: post.descricao,
      urlImagem: post.urlImagem,
      urlYoutube: post.urlYoutube,
      categoria: post.categoria,
      likeCount: post.likeCount + (post.likedByMe ? -1 : 1),
      commentCount: post.commentCount,
      likedByMe: !post.likedByMe,
      createdAt: post.createdAt,
    );
    _aplicarFiltro();
    notifyListeners();
  }
}
