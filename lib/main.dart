import 'package:flutter/material.dart';
import 'services/api.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/ui.dart';

final navKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadSaved();
  Api.onUnauthorized = () {
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
    );
  };
  runApp(const MechanicApp());
}

class MechanicApp extends StatelessWidget {
  const MechanicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Механик',
      theme: buildTheme(),
      home: Api.token == null ? const LoginScreen() : const HomeShell(),
    );
  }
}