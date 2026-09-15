import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/helpers/time_ago.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/produto.dart';
import '../../../models/feed_post.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/chat_service.dart';
import '../../widgets/feed_card.dart';
import '../../widgets/featured_card.dart';
import '../../widgets/animated_card_entry.dart';
import '../product/product_detail_screen.dart';

class UnidadeScreen extends StatefulWidget {
  final int unidadeId;
  const UnidadeScreen({super.key, required this.unidadeId});

  @override
  State<UnidadeScreen> createState() => _UnidadeScreenState();
}

class _UnidadeScreenState extends State<UnidadeScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _unidade;
  List<Produto> _produtos = [];
  List<FeedPost> _posts = [];
  bool _loading = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _load();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final supabase = Supabase.instance.client;
    try {
      final uni = await supabase.from('unidades').select().eq('id', widget.unidadeId).maybeSingle();
      if (uni != null) {
        _unidade = uni as Map<String, dynamic>;
      }

      final prods = await supabase.from('produtos').select('*, categorias(nome), marcas(nome), unidades(nome)').eq('unidade_id', widget.unidadeId).order('id');
      if (prods is List) _produtos = prods.map((j) => Produto.fromJson(j as Map<String, dynamic>)).toList();

      final posts = await supabase.from('posts_feed').select('*, post_likes(user_id), unidades(nome)').eq('unidade_id', widget.unidadeId).order('created_at', ascending: false);
      if (posts is List) _posts = posts.map((j) => FeedPost.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Erro ao carregar unidade: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic> _extrairHorarios() {
    final horarios = <String, dynamic>{};
    if (_unidade == null) return horarios;
    for (final dia in ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom']) {
      final chave = 'horario_$dia';
      if (_unidade![chave] != null) horarios[dia] = _unidade![chave];
    }
    return horarios;
  }

  String _horarioHoje() {
    final dias = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'];
    final hoje = dias[DateTime.now().weekday % 7];
    return _extrairHorarios()[hoje] as String? ?? 'Fechado';
  }

  bool _estaAberto() {
    final horaStr = _horarioHoje();
    if (horaStr == 'Fechado') return false;
    final partes = horaStr.split('-');
    if (partes.length != 2) return false;
    try {
      final agora = DateTime.now();
      final abertura = partes[0].split(':').map(int.parse).toList();
      final fechamento = partes[1].split(':').map(int.parse).toList();
      final agoraMin = agora.hour * 60 + agora.minute;
      final aberturaMin = abertura[0] * 60 + abertura[1];
      final fechamentoMin = fechamento[0] * 60 + fechamento[1];
      return agoraMin >= aberturaMin && agoraMin <= fechamentoMin;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _unidade;
    return Scaffold(
      backgroundColor: ThemeColors.background(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : u == null
              ? const Center(child: Text('Loja não encontrada'))
              : _buildBody(u),
    );
  }

  Widget _buildBody(Map<String, dynamic> u) {
    final nome = u['nome'] as String? ?? '';
    final fotoUrl = u['foto_url'] as String?;
    final bairro = u['bairro'] as String?;
    final endereco = u['endereco'] as String?;
    final cidade = u['cidade'] as String?;
    final logoUrl = u['logo_url'] as String?;
    final aberto = _estaAberto();
    final horarioHoje = _horarioHoje();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Image
          SizedBox(
            height: context.h(320).clamp(260.0, 400.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: fotoUrl ?? '',
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _heroPlaceholder(nome),
                  placeholder: (_, __) => _heroPlaceholder(nome),
                ),
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: const Alignment(0, 0.35),
                    ),
                  ),
                ),
                // Top buttons (SafeArea aligned)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _circleButton(Icons.arrow_back_rounded, () => context.pop()),
                        Row(
                          children: [
                            _circleButton(Icons.share_rounded, () {}),
                            SizedBox(width: context.w(AppSpacing.sm)),
                            _circleButton(Icons.favorite_border_rounded, () {}),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Info card (white, overlapped)
          Transform.translate(
            offset: Offset(0, -context.h(20)),
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
              padding: EdgeInsets.all(context.w(AppSpacing.lg)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.rLg(context)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE50914).withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome + Logo
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nome,
                                style: TextStyle(
                                  fontSize: context.sp(20).clamp(18.0, 24.0),
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFEDEDED),
                                )),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.location_on_rounded, size: context.sp(16), color: const Color(0xFFE50914)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${endereco ?? ''}${bairro != null ? ' - $bairro' : ''}${cidade != null ? ', $cidade' : ''}',
                                    style: TextStyle(fontSize: context.sp(13), color: const Color(0xFFE50914)),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBEBEB),
                          borderRadius: BorderRadius.circular(AppRadius.rMd(context)),
                          border: Border.all(color: const Color(0xFF2C2C2C)),
                        ),
                        child: logoUrl != null && logoUrl.isNotEmpty
                            ? Image.network(logoUrl, fit: BoxFit.contain, width: 40, height: 40)
                            : Image.asset('assets/logo.jpg', fit: BoxFit.contain, width: 40, height: 40),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  // Stats
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statItem('${_produtos.length}', 'Produtos'),
                      // Status Aberto/Fechado dinâmico com animação
                      GestureDetector(
                        onTap: () {},
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: aberto ? const Color(0xFF00A650).withValues(alpha: 0.1) : const Color(0xFFF23D4F).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: aberto ? _pulseAnimation.value : 1.0,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: aberto ? const Color(0xFF00A650) : const Color(0xFFF23D4F),
                                            boxShadow: aberto
                                                ? [BoxShadow(
                                                    color: const Color(0xFF00A650).withValues(alpha: 0.6),
                                                    blurRadius: 6,
                                                    spreadRadius: 1,
                                                  )]
                                                : null,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    aberto ? 'Aberto agora' : 'Fechado',
                                    style: TextStyle(
                                      fontSize: context.sp(11),
                                      fontWeight: FontWeight.w600,
                                      color: aberto ? const Color(0xFF00A650) : const Color(0xFFF23D4F),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(aberto ? horarioHoje : 'Consulte horários',
                                style: TextStyle(fontSize: context.sp(10), color: const Color(0xFF9C9C9C))),
                          ],
                        ),
                      ),
                      _statItem('${_posts.length}', 'Novidades'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Info badges
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _infoBadge(Icons.access_time_rounded, aberto ? 'Aberto: $horarioHoje' : 'Fechado hoje'),
                  const SizedBox(width: 8),
                  _infoBadge(Icons.directions_car_rounded, endereco ?? ''),
                  if (aberto) ...[
                    const SizedBox(width: 8),
                    _infoBadge(Icons.verified_rounded, 'Loja parceira ativa'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Botão Falar com a Unidade
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
            child: SizedBox(
              width: double.infinity,
              height: context.h(50).clamp(44.0, 56.0),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final userId = context.read<AuthProvider>().user?.id;
                  if (userId == null) {
                    context.go('/login');
                    return;
                  }
                  // Verifica se o usuário é da equipe da unidade
                  final chatService = ChatService();
                  final ehEquipe = await chatService.usuarioEquipeDaUnidade(userId, widget.unidadeId);
                  if (!mounted) return;
                  if (ehEquipe) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Você faz parte da equipe desta unidade.'),
                        duration: const Duration(seconds: 3),
                        action: SnackBarAction(
                          label: 'Central',
                          onPressed: () => context.push('/central-atendimento'),
                        ),
                      ),
                    );
                    return;
                  }
                  if (!mounted) return;
                  context.push('/chat/${widget.unidadeId}/${Uri.encodeComponent(nome)}');
                },
                icon: const Icon(Icons.chat_rounded, size: 20),
                label: const Text('Falar com a Unidade', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Sobre a unidade (Container branco)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(context.w(AppSpacing.lg)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.rLg(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sobre a loja',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(
                    nome.isNotEmpty
                        ? 'Bem-vindo à $nome. A loja parceira oficial no bairro $bairro. Produtos originais, promoções e a cultura do O Pest.'
                        : 'Loja parceira com produtos originais e ofertas da comunidade.',
                    style: TextStyle(fontSize: context.sp(14), color: const Color(0xFFC6C6C6), height: 1.6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Produtos Disponíveis
          if (_produtos.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Produtos Disponíveis',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: context.h(220).clamp(170.0, 280.0),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(left: context.w(AppSpacing.md)),
                itemCount: _produtos.length,
                separatorBuilder: (_, __) => SizedBox(width: context.w(AppSpacing.md)),
                itemBuilder: (context, index) {
                  return AnimatedCardEntry(
                    index: index,
                    child: FeaturedCard(
                      produto: _produtos[index],
                      onTap: () => ProductDetailScreen.push(
                        context,
                        _produtos[index].id,
                        imageUrl: _produtos[index].urlImagem.isNotEmpty
                            ? _produtos[index].urlImagem.first
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          // Localização
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.md)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Localização',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.sm),
                GestureDetector(
                  onTap: () => _abrirMapa(endereco, bairro, cidade, u['latitude'], u['longitude']),
                  child: Container(
                    height: context.h(180).clamp(140.0, 220.0),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.rLg(context)),
                      border: Border.all(color: const Color(0xFF2C2C2C)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildMap(u['latitude'], u['longitude'], endereco, bairro, cidade),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _abrirMapa(endereco, bairro, cidade, u['latitude'], u['longitude']),
                  child: Text(
                    '${endereco ?? ''}${bairro != null ? ', $bairro' : ''}${cidade != null ? ' - $cidade' : ''}',
                    style: TextStyle(fontSize: context.sp(13), color: const Color(0xFFE50914), decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _heroPlaceholder(String nome) {
    return Container(
      color: ThemeColors.primary(context),
      child: Center(
        child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : 'A',
            style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)],
      ),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFFEDEDED), size: context.sp(22)),
        onPressed: onTap,
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.w700, color: const Color(0xFFEDEDED))),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: context.sp(11), color: const Color(0xFFC6C6C6))),
      ],
    );
  }

  Widget _infoBadge(IconData icon, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.sm), vertical: context.h(6)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C2C2C)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: context.sp(16), color: const Color(0xFFE50914)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: context.sp(12), color: const Color(0xFFC6C6C6))),
        ],
      ),
    );
  }

  Widget _buildMap(dynamic lat, dynamic lng, String? endereco, String? bairro, String? cidade) {
    final hasCoords = lat != null && lng != null;
    if (!hasCoords) {
      return Container(
        color: const Color(0xFF1F1F1F),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_rounded, size: 48, color: const Color(0xFF9C9C9C)),
              const SizedBox(height: 8),
              Text(endereco ?? '',
                  style: TextStyle(fontSize: context.sp(13), color: const Color(0xFF9C9C9C)),
                  textAlign: TextAlign.center),
              if (bairro != null) ...[
                const SizedBox(height: 4),
                Text('$bairro, ${cidade ?? ''}',
                    style: TextStyle(fontSize: context.sp(12), color: const Color(0xFF9C9C9C))),
              ],
            ],
          ),
        ),
      );
    }

    final latNum = double.tryParse(lat.toString()) ?? -12.1528;
    final lngNum = double.tryParse(lng.toString()) ?? -44.9932;

    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(latNum, lngNum),
        initialZoom: 16.0,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.opest.shop',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(latNum, lngNum),
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on_rounded, color: Color(0xFFE50914), size: 40),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _abrirMapa(String? endereco, String? bairro, String? cidade, dynamic lat, dynamic lng) async {
    final hasCoords = lat != null && lng != null;
    final Uri uri;
    if (hasCoords) {
      final latNum = double.tryParse(lat.toString()) ?? -12.1528;
      final lngNum = double.tryParse(lng.toString()) ?? -44.9932;
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$latNum,$lngNum');
    } else {
      final address = '${endereco ?? ''}${bairro != null ? ', $bairro' : ''}${cidade != null ? ', $cidade' : ''}';
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
