import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/endereco.dart';
import 'supabase_service.dart';

/// CRUD de endereços de entrega do usuário (tabela enderecos_usuario).
class EnderecoService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<List<Endereco>> fetch(String userId) async {
    final response = await _client
        .from('enderecos_usuario')
        .select()
        .eq('user_id', userId)
        .order('principal', ascending: false)
        .order('id', ascending: false);

    return response.map((json) => Endereco.fromJson(json)).toList();
  }

  Future<void> adicionar(
    String userId, {
    required String apelido,
    required String cep,
    required String rua,
    required String numero,
    String complemento = '',
    required String bairro,
    required String cidade,
    required String uf,
    bool principal = false,
  }) async {
    if (principal) await _limparPrincipal(userId);
    await _client.from('enderecos_usuario').insert({
      'user_id': userId,
      'apelido': apelido,
      'cep': cep,
      'rua': rua,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'principal': principal,
    });
  }

  Future<void> atualizar(
    String userId,
    int id, {
    required String apelido,
    required String cep,
    required String rua,
    required String numero,
    String complemento = '',
    required String bairro,
    required String cidade,
    required String uf,
    bool principal = false,
  }) async {
    if (principal) await _limparPrincipal(userId, excetoId: id);
    await _client.from('enderecos_usuario').update({
      'apelido': apelido,
      'cep': cep,
      'rua': rua,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'principal': principal,
    }).eq('id', id);
  }

  Future<void> excluir(int id) async {
    await _client.from('enderecos_usuario').delete().eq('id', id);
  }

  Future<void> definirPrincipal(String userId, int id) async {
    await _limparPrincipal(userId);
    await _client
        .from('enderecos_usuario')
        .update({'principal': true}).eq('id', id);
  }

  Future<void> _limparPrincipal(String userId, {int? excetoId}) async {
    var query = _client
        .from('enderecos_usuario')
        .update({'principal': false}).eq('user_id', userId);
    if (excetoId != null) query = query.neq('id', excetoId);
    await query;
  }
}
