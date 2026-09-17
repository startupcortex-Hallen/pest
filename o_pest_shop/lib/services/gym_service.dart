import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class GymService {
  final SupabaseClient _client = SupabaseService.instance.client;

  // AULAS
  Future<List<Map<String, dynamic>>> fetchAulas(int unidadeId) async {
    final r = await _client.from('aulas').select().eq('unidade_id', unidadeId).order('dia_semana').order('horario');
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<bool> checkInscricao(int aulaId, String userId, String data) async {
    final r = await _client.from('aulas_inscricao').select('id').eq('aula_id', aulaId).eq('user_id', userId).eq('data_aula', data).maybeSingle();
    return r != null;
  }

  Future<void> inscreverAula(int aulaId, String userId, String data) async {
    await _client.from('aulas_inscricao').insert({'aula_id': aulaId, 'user_id': userId, 'data_aula': data});
    final atual = await _client.from('aulas').select('vagas_ocupadas').eq('id', aulaId).maybeSingle();
    final vagas = (atual?['vagas_ocupadas'] as num?)?.toInt() ?? 0;
    await _client.from('aulas').update({'vagas_ocupadas': vagas + 1}).eq('id', aulaId);
  }

  // PERSONAL
  Future<List<Map<String, dynamic>>> fetchPersonais(int unidadeId) async {
    final r = await _client.from('perfis').select('id, nome, avatar_url').eq('funcao', 'personal').eq('unidade_id', unidadeId);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> agendarPersonal(Map<String, dynamic> data) async {
    await _client.from('personal_sessoes').insert(data);
  }

  Future<List<Map<String, dynamic>>> fetchMinhasSessoes(String userId) async {
    final r = await _client.from('personal_sessoes').select('*, perfis!personal_id(nome, avatar_url)').eq('aluno_id', userId).order('data_hora', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  // AVALIAÇÃO
  Future<List<Map<String, dynamic>>> fetchAvaliacoes(String userId) async {
    final r = await _client.from('avaliacoes').select().eq('user_id', userId).order('data_avaliacao', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> salvarAvaliacao(Map<String, dynamic> data) async {
    await _client.from('avaliacoes').insert(data);
  }

  // PROGRESSO FOTOS
  Future<List<Map<String, dynamic>>> fetchProgressoFotos(String userId) async {
    final r = await _client.from('progresso_fotos').select().eq('user_id', userId).order('data', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  // CHAT
  Future<List<Map<String, dynamic>>> fetchConversas(String userId) async {
    final r = await _client.from('conversas').select('*, perfis!profissional_id(nome, avatar_url)').or('usuario_id.eq.$userId,profissional_id.eq.$userId').order('updated_at', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchMensagens(int conversaId) async {
    final r = await _client.from('mensagens').select('*, perfis!remetente_id(nome)').eq('conversa_id', conversaId).order('created_at');
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> enviarMensagem(int conversaId, String userId, String texto) async {
    await _client.from('mensagens').insert({'conversa_id': conversaId, 'remetente_id': userId, 'texto': texto});
    await _client.from('conversas').update({'ultima_mensagem': texto, 'updated_at': DateTime.now().toIso8601String()}).eq('id', conversaId);
  }

  Future<int> criarConversa(String usuarioId, String profissionalId) async {
    final r = await _client.from('conversas').insert({'usuario_id': usuarioId, 'profissional_id': profissionalId}).select('id').single();
    return r['id'] as int;
  }

  // DESAFIOS
  Future<List<Map<String, dynamic>>> fetchDesafios(int unidadeId) async {
    final r = await _client.from('desafios').select('*, desafios_participantes(user_id, progresso)').eq('unidade_id', unidadeId).eq('ativo', true);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> participarDesafio(int desafioId, String userId) async {
    await _client.from('desafios_participantes').insert({'desafio_id': desafioId, 'user_id': userId});
  }

  Future<void> atualizarProgresso(int desafioId, String userId, int progresso) async {
    await _client.from('desafios_participantes').update({'progresso': progresso}).eq('desafio_id', desafioId).eq('user_id', userId);
  }

  // INDICAÇÃO
  Future<Map<String, dynamic>?> fetchIndicacao(String userId) async {
    final r = await _client.from('indicacoes').select('*, perfis!indicado_id(nome)').eq('usuario_id', userId).maybeSingle();
    if (r == null) return null;
    return r as Map<String, dynamic>;
  }

  Future<void> criarIndicacao(String userId, String indicadoId, String codigo) async {
    await _client.from('indicacoes').insert({'usuario_id': userId, 'indicado_id': indicadoId, 'codigo_indicacao': codigo, 'pontos_ganhos': 50});
    final perfil = await _client.from('perfis').select('pontos').eq('id', userId).maybeSingle();
    final pontos = (perfil?['pontos'] as num?)?.toInt() ?? 0;
    await _client.from('perfis').update({'pontos': pontos + 50}).eq('id', userId);
  }

  // DASHBOARD
  Future<Map<String, dynamic>> fetchDashboard(int unidadeId) async {
    final alunos = await _client.from('perfis').select('id').eq('unidade_id', unidadeId);
    final aulasHoje = await _client.from('aulas_inscricao').select('id').eq('data_aula', DateTime.now().toIso8601String().split('T')[0]);
    final receita = await _client.from('pedidos').select('total').eq('unidade_id', unidadeId).eq('status', 'pago');
    final totalReceita = (receita as List).fold<double>(0, (s, i) => s + ((i['total'] as num?)?.toDouble() ?? 0));
    return {'alunos': (alunos as List).length, 'aulas_hoje': (aulasHoje as List).length, 'receita_mes': totalReceita};
  }
}
