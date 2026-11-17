class YoutubeUrl {
  YoutubeUrl._();

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isValidId(String? id) =>
      id != null && id.isNotEmpty && _idPattern.hasMatch(id);

  /// Extrai o ID de vídeo de URLs comuns do YouTube e também aceita o ID puro.
  /// Retorna null para qualquer entrada que não seja um vídeo válido.
  static String? extractId(String? input) {
    if (input == null) return null;
    final text = input.trim();
    if (text.isEmpty) return null;

    if (isValidId(text)) return text;

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();

    String? candidate;

    if (host == 'youtu.be') {
      if (segments.isNotEmpty) candidate = segments.first;
    } else if (host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com' ||
        host == 'youtube-nocookie.com') {
      final queryId = uri.queryParameters['v'];
      if (queryId != null && queryId.isNotEmpty) {
        candidate = queryId;
      } else if (segments.length >= 2) {
        const rotas = {'embed', 'shorts', 'live', 'v'};
        if (rotas.contains(segments[0])) candidate = segments[1];
      }
    }

    return isValidId(candidate) ? candidate : null;
  }

  static String? normalizedUrl(String? input) {
    final id = extractId(input);
    return id == null ? null : 'https://www.youtube.com/watch?v=$id';
  }

  static String watchUrl(String videoId) =>
      'https://www.youtube.com/watch?v=$videoId';

  static String thumbnailUrl(String videoId, {String quality = 'hqdefault'}) =>
      'https://img.youtube.com/vi/$videoId/$quality.jpg';
}
