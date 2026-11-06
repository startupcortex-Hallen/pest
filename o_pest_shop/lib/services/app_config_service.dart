import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AppConfig {
  final bool checkoutAtivo;
  final bool pagamentosAtivo;
  final bool freteAtivo;
  final bool pixOnly;
  final bool manutencao;
  final String? mensagemManutencao;

  const AppConfig({
    this.checkoutAtivo = true,
    this.pagamentosAtivo = true,
    this.freteAtivo = true,
    this.pixOnly = false,
    this.manutencao = false,
    this.mensagemManutencao,
  });

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    bool flag(String chave, String campo, {bool padrao = true}) {
      final item = map[chave];
      if (item is! Map) return padrao;
      final valor = item[campo];
      return valor is bool ? valor : padrao;
    }

    String? mensagem() {
      final item = map['manutencao'];
      if (item is! Map) return null;
      final valor = item['mensagem'];
      return valor is String && valor.trim().isNotEmpty ? valor.trim() : null;
    }

    return AppConfig(
      checkoutAtivo: flag('checkout', 'ativo'),
      pagamentosAtivo: flag('pagamentos', 'ativo'),
      freteAtivo: flag('frete', 'ativo'),
      pixOnly: flag('pagamentos', 'pix_only', padrao: false),
      manutencao: flag('manutencao', 'ativo', padrao: false),
      mensagemManutencao: mensagem(),
    );
  }

  Map<String, dynamic> toMap() => {
        'checkoutAtivo': checkoutAtivo,
        'pagamentosAtivo': pagamentosAtivo,
        'freteAtivo': freteAtivo,
        'pixOnly': pixOnly,
        'manutencao': manutencao,
        'mensagemManutencao': mensagemManutencao,
      };

  factory AppConfig.fromCache(Map<String, dynamic> map) {
    bool b(String k, bool padrao) => map[k] is bool ? map[k] as bool : padrao;
    return AppConfig(
      checkoutAtivo: b('checkoutAtivo', true),
      pagamentosAtivo: b('pagamentosAtivo', true),
      freteAtivo: b('freteAtivo', true),
      pixOnly: b('pixOnly', false),
      manutencao: b('manutencao', false),
      mensagemManutencao: map['mensagemManutencao'] as String?,
    );
  }
}

class AppConfigService {
  static const _cacheKey = 'opest_app_config_v1';
  static const _cacheTsKey = 'opest_app_config_v1_ts';
  static const Duration _ttl = Duration(minutes: 1);

  final SupabaseClient _client = SupabaseService.instance.client;

  Future<AppConfig> load() async {
    final cached = await _lerCache();
    if (cached != null) return cached;

    try {
      final rows = await _client
          .from('app_config_publica')
          .select('chave,valor');
      final mapa = <String, dynamic>{};
      if (rows is List) {
        for (final row in rows) {
          if (row is Map && row['chave'] is String) {
            mapa[row['chave'] as String] = row['valor'];
          }
        }
      }
      final config = AppConfig.fromMap(mapa);
      await _salvarCache(config);
      return config;
    } catch (_) {
      return const AppConfig();
    }
  }

  Future<AppConfig?> _lerCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final ts = DateTime.tryParse(prefs.getString(_cacheTsKey) ?? '');
      if (raw == null || ts == null) return null;
      if (DateTime.now().difference(ts) > _ttl) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return AppConfig.fromCache(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> _salvarCache(AppConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(config.toMap()));
      await prefs.setString(_cacheTsKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }
}
