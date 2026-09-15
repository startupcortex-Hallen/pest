import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
