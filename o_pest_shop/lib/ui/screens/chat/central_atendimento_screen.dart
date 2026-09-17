import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/chat_service.dart';

class CentralAtendimentoScreen extends StatefulWidget {
  const CentralAtendimentoScreen({super.key});

  @override
  State<CentralAtendimentoScreen> createState() => _CentralAtendimentoScreenState();
}

class _CentralAtendimentoScreenState extends State<CentralAtendimentoScreen> {
  final _service = ChatService();
  List<Map<String, dynamic>> _conversas = [];
  bool _loading = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    try { Supabase.instance.client.removeChannel(_realtimeChannel!); } catch (_) {}
    super.dispose();
  }

  Future<void> _carregar() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      _conversas = await _service.fetchConversasAtendente(userId);
      _escutarNovas();
    } catch (e) {
      debugPrint('Erro central: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _escutarNovas() {
    _realtimeChannel = _service.listenNovasMensagens((novaMsg) {
      if (!mounted) return;
      _carregar(); // recarrega a lista para atualizar últimas mensagens
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: const Color(0xFFEDEDED)),
          onPressed: () => context.pop(),
        ),
        title: const Text('Central de Atendimento',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFEDEDED))),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversas.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: _conversas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _buildConversaItem(_conversas[i]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE50914).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFE50914), size: 36),
          ),
          const SizedBox(height: 20),
          const Text('Nenhum atendimento',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('As conversas dos clientes aparecerão aqui.',
              style: TextStyle(fontSize: 14, color: Color(0xFFC6C6C6))),
        ],
      ),
    );
  }

  Widget _buildConversaItem(Map<String, dynamic> conv) {
    final perfil = conv['perfis'] as Map?;
    final unidade = conv['unidades'] as Map?;
    final nomeBruto = (perfil?['nome'] as String?)?.trim() ?? '';
    final nomeCliente = nomeBruto.isEmpty ? 'Cliente' : nomeBruto;
    final avatarUrl = perfil?['avatar_url'] as String?;
    final ultimaMsg = conv['ultima_mensagem'] as String? ?? '';
    final updatedAt = conv['updated_at'] as String? ?? conv['created_at'] as String? ?? '';
    final hora = updatedAt.length >= 16 ? updatedAt.substring(11, 16) : '';
    final unidadeNome = unidade?['nome'] as String? ?? '';
    final conversaId = (conv['id'] as num?)?.toInt();
    if (conversaId == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFFEBEBEB),
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? Text(nomeCliente[0].toUpperCase(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFC6C6C6)))
              : null,
        ),
        title: Text(nomeCliente,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFFEDEDED))),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ultimaMsg.isNotEmpty ? ultimaMsg : 'Clique para iniciar atendimento',
                style: TextStyle(fontSize: 13, color: ultimaMsg.isNotEmpty ? const Color(0xFFC6C6C6) : const Color(0xFF9C9C9C)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(unidadeNome.isNotEmpty ? unidadeNome : 'Loja',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9C9C9C))),
          ],
        ),
        trailing: Text(hora, style: const TextStyle(fontSize: 11, color: Color(0xFF9C9C9C))),
        onTap: () => context.push('/chat/$conversaId/${Uri.encodeComponent(nomeCliente)}'),
      ),
    );
  }
}
