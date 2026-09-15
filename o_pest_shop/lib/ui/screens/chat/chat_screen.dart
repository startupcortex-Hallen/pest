import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final int unidadeId;
  final String unidadeNome;
  final String? unidadeFotoUrl;

  const ChatScreen({
    super.key,
    required this.unidadeId,
    required this.unidadeNome,
    this.unidadeFotoUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _service = ChatService();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _mensagens = [];
  List<Map<String, dynamic>> _pedidos = [];
  int? _conversaId;
  bool _loading = true;
  bool _enviando = false;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _realtimeChannel?.unsubscribe();
    try { Supabase.instance.client.removeChannel(_realtimeChannel!); } catch (_) {}
    super.dispose();
  }

  Future<void> _iniciar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) { if (mounted) context.go('/login'); return; }
    try {
      _conversaId = await _service.buscarOuCriarConversa(userId, widget.unidadeId);
      _mensagens = await _service.fetchMensagens(_conversaId!);
      _pedidos = await _service.fetchPedidos(userId, widget.unidadeId);
      _escutarMensagens();
    } catch (e) { debugPrint('Erro chat: $e'); }
    if (mounted) setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollParaBaixo());
  }

  void _escutarMensagens() {
    if (_conversaId == null) return;
    _realtimeChannel = _service.listenMensagens(_conversaId!, (novaMsg) {
      if (!mounted) return;
      if (_mensagens.any((m) => m['id'] == novaMsg['id'])) return;
      _buscarPerfilERefresh(novaMsg);
    });
  }

  Future<void> _buscarPerfilERefresh(Map<String, dynamic> msg) async {
    try {
      final perfil = await Supabase.instance.client
          .from('perfis').select('nome, avatar_url, funcao')
          .eq('id', msg['remetente_id']).maybeSingle();
      if (perfil != null) msg['perfis'] = perfil;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _mensagens.add(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollParaBaixo());
  }

  void _scrollParaBaixo() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _enviar() async {
    final texto = _msgCtrl.text.trim();
    if (texto.isEmpty || _conversaId == null || _enviando) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    setState(() => _enviando = true);
    try {
      await _service.enviarMensagem(_conversaId!, userId, texto);
      _msgCtrl.clear();
      _mensagens = await _service.fetchMensagens(_conversaId!);
      if (mounted) setState(() {});
      _scrollParaBaixo();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao enviar mensagem. Tente novamente.')),
      );
    }
    if (mounted) setState(() => _enviando = false);
  }

  bool _isHoje(String createdAt) {
    if (createdAt.length < 10) return false;
    final data = createdAt.substring(0, 10);
    final hoje = DateTime.now().toIso8601String().substring(0, 10);
    return data == hoje;
  }

  bool _isMesmaData(String a, String b) {
    if (a.length < 10 || b.length < 10) return false;
    return a.substring(0, 10) == b.substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.id;
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(4, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFE50914),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Suporte ao Cliente',
                                style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.w700, color: Colors.white)),
                            Text('Agente online agora',
                                style: TextStyle(fontSize: context.sp(12), color: Colors.white70)),
                          ],
                        ),
                      ),
                      Icon(Icons.info_outline_rounded, color: Colors.white70, size: context.sp(22)),
                    ],
                  ),
                ],
              ),
            ),
            // Order card
            if (_pedidos.isNotEmpty) ..._pedidos.take(1).map((p) => _buildPedidoCard(p)).toList(),
            // Messages
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _mensagens.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: _mensagens.length,
                          itemBuilder: (_, i) => _buildBalaoComData(_mensagens, i, userId),
                        ),
            ),
            // Input
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalaoComData(List<Map<String, dynamic>> msgs, int i, String? userId) {
    final m = msgs[i];
    final anterior = i > 0 ? msgs[i - 1] : null;
    final dataAtual = m['created_at'] as String? ?? '';
    final dataAnterior = anterior?['created_at'] as String? ?? '';

    return Column(
      children: [
        if (i == 0 || !_isMesmaData(dataAtual, dataAnterior))
          _buildDataDivider(dataAtual),
        _buildBalao(m, userId),
      ],
    );
  }

  Widget _buildDataDivider(String createdAt) {
    final hoje = _isHoje(createdAt);
    final data = createdAt.length >= 10 ? createdAt.substring(0, 10) : '';
    final label = hoje ? 'HOJE' : data;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFC6C6C6))),
      ),
    );
  }

  Widget _buildPedidoCard(Map<String, dynamic> pedido) {
    final itens = pedido['pedido_itens'] as List? ?? [];
    final primeiroItem = itens.isNotEmpty ? itens.first as Map<String, dynamic>? : null;
    final produto = primeiroItem?['produtos'] as Map?;
    final produtoNome = produto?['nome'] as String? ?? '';
    final produtoImg = produto?['url_imagem'] as List?;
    final imgUrl = (produtoImg is List && produtoImg.isNotEmpty) ? produtoImg.first as String? : null;
    final status = pedido['status'] as String? ?? '';
    final pedidoId = pedido['id'] as int? ?? 0;

    Color statusColor;
    switch (status.toLowerCase()) {
      case 'entregue': statusColor = const Color(0xFF00A650); break;
      case 'pago': statusColor = const Color(0xFFE50914); break;
      case 'pendente': statusColor = const Color(0xFFFFAD01); break;
      default: statusColor = const Color(0xFFC6C6C6);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: imgUrl != null
              ? Image.network(imgUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.shopping_bag_rounded, color: const Color(0xFF9C9C9C)))
              : Icon(Icons.shopping_bag_rounded, color: const Color(0xFF9C9C9C)),
        ),
        title: Text(produtoNome.isNotEmpty ? produtoNome : 'Pedido #$pedidoId',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFEDEDED)),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Text('Pedido #$pedidoId',
                style: const TextStyle(fontSize: 12, color: Color(0xFFC6C6C6))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(status.toUpperCase(),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF9C9C9C)),
        onTap: () {},
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE50914).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_rounded, color: Color(0xFFE50914), size: 36),
            ),
            const SizedBox(height: 20),
            const Text('Ol\u00e1! \u{1F44B}',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Fale com a equipe desta unidade.',
                style: TextStyle(fontSize: 14, color: Color(0xFFC6C6C6))),
            const SizedBox(height: 4),
            const Text('Envie uma mensagem para iniciar o atendimento.',
                style: TextStyle(fontSize: 13, color: Color(0xFF9C9C9C))),
          ],
        ),
      ),
    );
  }

  Widget _buildBalao(Map<String, dynamic> m, String? userId) {
    final texto = m['texto'] as String? ?? '';
    final createdAt = m['created_at'] as String? ?? '';
    final hora = createdAt.length >= 16 ? createdAt.substring(11, 16) : '';
    final isMe = m['remetente_id'] == userId;
    final perfil = m['perfis'] as Map?;
    final nomeRemetente = perfil?['nome'] as String? ?? '';
    final avatarUrl = perfil?['avatar_url'] as String?;
    final funcao = perfil?['funcao'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Nome e função do agente (só para mensagens do atendente)
          if (!isMe && nomeRemetente.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(nomeRemetente,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE50914))),
                  if (funcao != null && funcao.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(funcao == 'admin' ? 'Admin' : 'Atendente',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF9C9C9C))),
                  ],
                ],
              ),
            ),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFEBEBEB),
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(nomeRemetente.isNotEmpty ? nomeRemetente[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFC6C6C6)))
                        : null,
                  ),
                ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFFE50914) : const Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isMe ? const Radius.circular(4) : null,
                      bottomLeft: !isMe ? const Radius.circular(4) : null,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(texto,
                          style: TextStyle(
                            fontSize: 14,
                            color: isMe ? Colors.white : const Color(0xFFEDEDED),
                            height: 1.4,
                          )),
                    ],
                  ),
                ),
              ),
              if (isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFEBEBEB),
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(nomeRemetente.isNotEmpty ? nomeRemetente[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFC6C6C6)))
                        : null,
                  ),
                ),
            ],
          ),
          // Horário
          Padding(
            padding: EdgeInsets.only(top: 2, left: isMe ? 0 : 44, right: isMe ? 44 : 0),
            child: Text(hora, style: const TextStyle(fontSize: 10, color: Color(0xFF9C9C9C))),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Color(0xFF2C2C2C))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _enviar(),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Escreva sua mensagem...',
                    hintStyle: TextStyle(color: Color(0xFF9C9C9C), fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: _msgCtrl.text.trim().isEmpty
                    ? const Color(0xFF9C9C9C)
                    : const Color(0xFFE50914),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                onPressed: _msgCtrl.text.trim().isEmpty ? null : _enviar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
