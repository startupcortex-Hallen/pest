import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'core/constants/auth_notifier.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Detecta se o app foi aberto por um link de recuperação de senha
  // (o redirect do e-mail volta com "?recuperar=1" na URL).
  if (Uri.base.queryParameters['recuperar'] == '1') {
    PasswordRecoveryFlag.pending = true;
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0A0A0A),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  FlutterError.onError = (details) {
    debugPrint('████ FLUTTER ERROR: ${details.exception}');
    debugPrint('████ STACK: ${details.stack}');
    FlutterError.dumpErrorToConsole(details);
  };
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  try {
    await SupabaseService.instance.initialize();
  } catch (e) {
    debugPrint('Erro ao inicializar Supabase: $e');
  }
  runApp(const App());
}
