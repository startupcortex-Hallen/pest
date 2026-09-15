String timeAgo(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  final date = DateTime.tryParse(dateStr);
  if (date == null) return '';
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inSeconds < 60) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays < 7) return 'há ${diff.inDays} dias';
  if (diff.inDays < 30) return 'há ${(diff.inDays / 7).floor()} semanas';
  if (diff.inDays < 365) return 'há ${(diff.inDays / 30).floor()} meses';
  return 'há ${(diff.inDays / 365).floor()} anos';
}

String tempoLeitura(String? texto) {
  if (texto == null || texto.isEmpty) return '1 min';
  final palavras = texto.split(RegExp(r'\s+')).length;
  final minutos = (palavras / 200).ceil();
  return '$minutos min';
}
