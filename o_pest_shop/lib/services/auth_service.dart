import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import 'supabase_service.dart';

class AuthService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response;
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String nome,
  }) async {
    AuthResponse response;
    try {
      response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'nome': nome, 'full_name': nome},
      );
    } catch (e) {
      debugPrint('████ Erro signUp Supabase: $e');
      rethrow;
    }

    if (response.user != null) {
      // Se não tiver sessão (ex: email confirmation ativado), faz auto-login
      if (response.session == null) {
        try {
          final loginResp = await _client.auth.signInWithPassword(
            email: email,
            password: password,
          );
          debugPrint('████ Auto-login sessão: ${loginResp.session?.accessToken != null}');
        } catch (e) {
          debugPrint('████ Erro auto-login após signUp: $e');
        }
      } else {
        debugPrint('████ Já tem sessão após signUp');
      }

      debugPrint('████ Tentando criar perfil para user: ${response.user!.id}');
      try {
        final upsertResult = await _client.from('perfis').upsert({
          'id': response.user!.id,
          'nome': nome,
          'email': email,
          'perfil': 'cliente',
        }).select();
        debugPrint('████ Perfil criado com sucesso: $upsertResult');
      } catch (e) {
        debugPrint('████ Erro ao criar perfil: $e');
        // Tenta via insert simples como fallback
        try {
          await _client.from('perfis').insert({
            'id': response.user!.id,
            'nome': nome,
            'email': email,
            'perfil': 'cliente',
          });
          debugPrint('████ Perfil criado via insert fallback');
        } catch (e2) {
          debugPrint('████ Erro também no insert fallback: $e2');
        }
      }
    }

    return response;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  Future<UserProfile?> getProfile(String userId) async {
    final response = await _client
        .from('perfis')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    return UserProfile.fromJson(response);
  }

  Future<void> updateProfile(UserProfile profile) async {
    await _client.from('perfis').upsert(profile.toJson());
  }
}
