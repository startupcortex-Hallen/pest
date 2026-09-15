import 'package:flutter/material.dart';

/// Cores, rótulos e previsões dos status de pedido — compartilhado entre
/// cliente, admin/loja e entregador.
Color corStatusPedido(String status) {
  switch (status) {
    case 'pendente': return const Color(0xFFFFAD01);
    case 'pago': return const Color(0xFF0052FF);
    case 'em_preparo': return const Color(0xFF9747FF);
    case 'pronto_para_entrega': return const Color(0xFFFF8C00);
    case 'saiu_para_entrega': return const Color(0xFF0084FF);
    case 'entregue': return const Color(0xFF00A650);
    case 'cancelado': return const Color(0xFFF23D4F);
    default: return const Color(0xFF666666);
  }
}

String rotuloStatusPedido(String status) {
  switch (status) {
    case 'pendente': return 'Aguardando pagamento';
    case 'pago': return 'Pagamento aprovado';
    case 'em_preparo': return 'Em preparo';
    case 'pronto_para_entrega': return 'Pronto para entrega';
    case 'saiu_para_entrega': return 'Saiu para entrega';
    case 'entregue': return 'Entregue';
    case 'cancelado': return 'Cancelado';
    default: return status;
  }
}

String rotuloStatusCurto(String status) {
  switch (status) {
    case 'pendente': return 'Pendente';
    case 'pago': return 'Pago';
    case 'em_preparo': return 'Em preparo';
    case 'pronto_para_entrega': return 'Pronto p/ entrega';
    case 'saiu_para_entrega': return 'Saiu p/ entrega';
    case 'entregue': return 'Entregue';
    case 'cancelado': return 'Cancelado';
    default: return status;
  }
}

/// Previsão amigável: retirada/entrega baseada no prazo da unidade.
String previsaoTexto(Map<String, dynamic> unidade, String tipoEntrega) {
  final prazo = tipoEntrega == 'entrega'
      ? (unidade['prazo_entrega_min'] as int? ?? 120)
      : (unidade['prazo_retirada_min'] as int? ?? 60);
  final agora = DateTime.now();
  final prevista = agora.add(Duration(minutes: prazo));
  String p(int v) => v.toString().padLeft(2, '0');
  final dia = prevista.day == agora.day ? 'hoje' : 'amanhã';
  final hora = '${p(prevista.hour)}h${p(prevista.minute)}';
  if (tipoEntrega == 'entrega') {
    return 'Entrega prevista: $dia às $hora';
  }
  return 'Retirada disponível: $dia às $hora';
}

/// Etapas da timeline do pedido (padrão ML/Shopee).
const List<String> etapasTimeline = [
  'pendente',
  'pago',
  'em_preparo',
  'pronto_para_entrega',
  'saiu_para_entrega',
  'entregue',
];

int indiceEtapa(String? status) {
  final s = status ?? '';
  final idx = etapasTimeline.indexOf(s);
  return idx < 0 ? -1 : idx;
}

String formatarDataHora(String? iso) {
  final dt = DateTime.tryParse(iso ?? '')?.toLocal();
  if (dt == null) return '';
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(dt.day)}/${p(dt.month)}/${dt.year} às ${p(dt.hour)}:${p(dt.minute)}';
}
