String formatarDuracaoSegundos(int? segundos) {
  if (segundos == null || segundos <= 0) return '';
  final duracao = Duration(seconds: segundos);
  if (duracao.inHours > 0) {
    final minutos = duracao.inMinutes.remainder(60);
    return '${duracao.inHours}h ${minutos.toString().padLeft(2, '0')}min';
  }
  return '${duracao.inMinutes}min';
}

String formatarTempoReproducao(double segundos) {
  final total = segundos.round().clamp(0, 359999);
  final duracao = Duration(seconds: total);
  if (duracao.inHours > 0) {
    return '${duracao.inHours}:'
        '${duracao.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${duracao.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }
  return '${duracao.inMinutes}:'
      '${duracao.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

String formatarDataStreaming(DateTime? data) {
  if (data == null) return '';
  final local = data.toLocal();
  String p(int valor) => valor.toString().padLeft(2, '0');
  return '${p(local.day)}/${p(local.month)}/${local.year}';
}

String formatarDataHoraStreaming(DateTime? data) {
  if (data == null) return '';
  final local = data.toLocal();
  String p(int valor) => valor.toString().padLeft(2, '0');
  return '${p(local.day)}/${p(local.month)}/${local.year} '
      '${p(local.hour)}:${p(local.minute)}';
}

String formatarPercentual(double valor) {
  if (valor.isNaN || valor.isInfinite) return '0%';
  return '${(valor.clamp(0, 1) * 100).round()}%';
}

String tempoRelativoStreaming(DateTime? data) {
  if (data == null) return '';
  final diff = DateTime.now().difference(data.toLocal());
  if (diff.inSeconds < 60) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays < 7) return 'há ${diff.inDays} dias';
  if (diff.inDays < 30) return 'há ${(diff.inDays / 7).floor()} semanas';
  if (diff.inDays < 365) return 'há ${(diff.inDays / 30).floor()} meses';
  return 'há ${(diff.inDays / 365).floor()} anos';
}
