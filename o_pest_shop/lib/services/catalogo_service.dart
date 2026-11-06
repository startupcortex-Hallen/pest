import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Snapshot público usado pela home. Não contém custo, PIX, repasse ou
/// qualquer dado de usuário. O checkout sempre revalida preço/estoque.
class CatalogoSnapshot {
  final List<Map<String, dynamic>> categorias;
  final List<Map<String, dynamic>> produtos;
  final List<Map<String, dynamic>> promocoes;
  final List<Map<String, dynamic>> banners;
  final List<Map<String, dynamic>> unidades;
  final DateTime? geradoEm;

  const CatalogoSnapshot({
    required this.categorias,
    required this.produtos,
    required this.promocoes,
    required this.banners,
    required this.unidades,
    this.geradoEm,
  });

  Map<String, dynamic> toJson() => {
        'versao': geradoEm?.toIso8601String(),
        'categorias': categorias,
        'produtos': produtos,
        'promocoes': promocoes,
        'banners': banners,
        'unidades': unidades,
      };

  factory CatalogoSnapshot.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> lista(String chave) {
      final raw = json[chave];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }

    return CatalogoSnapshot(
      categorias: lista('categorias'),
      produtos: lista('produtos'),
      promocoes: lista('promocoes'),
      banners: lista('banners'),
      unidades: lista('unidades'),
      geradoEm: DateTime.tryParse(json['versao'] as String? ?? ''),
    );
  }
}

class CatalogoService {
  static const _cacheKey = 'opest_catalogo_publico_v1';
  static const _cacheTsKey = 'opest_catalogo_publico_v1_ts';
  static const Duration ttl = Duration(minutes: 5);
  static const Duration validadeMaxima = Duration(hours: 24);

  static const String _caminhoCatalogo = 'data/catalogo.json';
  static const String _caminhoProdutos = 'data/produtos.json';
  static const Duration _timeoutEstatico = Duration(seconds: 8);
  static const Duration _produtosTtl = Duration(minutes: 10);

  static List<Map<String, dynamic>>? _produtosLocal;
  static DateTime? _produtosLocalEm;

  SupabaseClient get _client => SupabaseService.instance.client;

  Uri? _urlEstatica(String caminho) {
    const base = String.fromEnvironment('OPEST_CATALOGO_BASE');
    if (base.isNotEmpty) {
      final normalizada = base.endsWith('/') ? base : '$base/';
      return Uri.parse(normalizada).resolve(caminho);
    }
    if (!kIsWeb) return null;
    return Uri.base.resolve(caminho);
  }

  Future<CatalogoSnapshot?> lerCache({bool permitirExpirado = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;

      final ts = DateTime.tryParse(prefs.getString(_cacheTsKey) ?? '');
      if (ts == null) return null;
      final idade = DateTime.now().difference(ts);
      if (idade > validadeMaxima) return null;
      if (!permitirExpirado && idade > ttl) return null;

      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return CatalogoSnapshot.fromJson(
        Map<String, dynamic>.from(json),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> salvarCache(Map<String, dynamic> json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(json));
      await prefs.setString(_cacheTsKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Cache é opcional; nunca deve quebrar a home.
    }
  }

  Future<Map<String, dynamic>?> buscarEstatico() async {
    final uri = _urlEstatica(_caminhoCatalogo);
    if (uri == null) return null;
    try {
      final resposta = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeoutEstatico);
      if (resposta.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(resposta.bodyBytes));
      if (json is! Map) return null;
      return Map<String, dynamic>.from(json);
    } catch (_) {
      return null;
    }
  }

  /// Lista completa de produtos ativos publicada junto com o site.
  /// No Android/Web sem arquivo estático o retorno é vazio e o app usa o
  /// PostgREST como fallback.
  Future<List<Map<String, dynamic>>> carregarProdutosLocais({
    bool force = false,
  }) async {
    final agora = DateTime.now();
    final cache = _produtosLocal;
    if (!force &&
        cache != null &&
        _produtosLocalEm != null &&
        agora.difference(_produtosLocalEm!) < _produtosTtl) {
      return cache;
    }

    final uri = _urlEstatica(_caminhoProdutos);
    if (uri == null) return cache ?? const [];

    try {
      final resposta = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeoutEstatico);
      if (resposta.statusCode != 200) return cache ?? const [];

      final json = jsonDecode(utf8.decode(resposta.bodyBytes));
      final raw = json is Map ? json['produtos'] : null;
      if (raw is! List) return cache ?? const [];

      final produtos = raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
      if (produtos.isEmpty) return cache ?? const [];

      final ordenados = [...produtos]..sort((a, b) {
          final idA = (a['id'] as num?)?.toInt() ?? 0;
          final idB = (b['id'] as num?)?.toInt() ?? 0;
          return idA.compareTo(idB);
        });
      _produtosLocal = ordenados;
      _produtosLocalEm = agora;
      return ordenados;
    } catch (_) {
      return cache ?? const [];
    }
  }

  Future<List<Map<String, dynamic>>> buscarBannersFallback() async {
    try {
      final r = await _client
          .from('banners')
          .select('id,titulo,imagem_url,link_url,ordem,data_inicio,data_fim')
          .eq('ativo', true)
          .order('ordem', ascending: true)
          .limit(10);
      if (r is! List) return const [];
      final agora = DateTime.now();
      return r
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((b) {
            final ini = DateTime.tryParse(b['data_inicio'] as String? ?? '');
            final fim = DateTime.tryParse(b['data_fim'] as String? ?? '');
            return (ini == null || !ini.isAfter(agora)) &&
                (fim == null || !fim.isBefore(agora));
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> buscarRemoto() async {
    final estatico = await buscarEstatico();
    if (estatico != null) {
      await salvarCache(estatico);
      return estatico;
    }

    try {
      final resposta = await _client.functions.invoke('catalogo-publico');
      final data = resposta.data;
      if (data is Map) {
        final mapa = Map<String, dynamic>.from(data);
        await salvarCache(mapa);
        return mapa;
      }
    } catch (_) {
      // Função ainda não publicada/sem rede: a home usa o fallback REST.
    }
    return null;
  }
}
