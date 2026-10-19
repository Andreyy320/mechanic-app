import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'services/api.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/ui.dart';

final navKey = GlobalKey<NavigatorState>();

/// Эталонная ширина интерфейса (логических пикселей). Вид приложения на любом
/// экране — как на экране с такой шириной. Больше число — всё мельче, меньше — крупнее.
const double kDesignWidth = 400;

/// Вызывается, когда пуш приходит при закрытом или свёрнутом приложении.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage m) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // только вертикальная ориентация: вёрстка везде одинаковая
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_bgHandler);
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
      // Интерфейс всегда строится на эталонной ширине kDesignWidth и затем
      // пропорционально растягивается на экран. Поэтому «Размер экрана»,
      // «Размер шрифта» и ширина телефона больше не меняют вид приложения.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final s = mq.size.width / kDesignWidth; // во сколько раз растянуть
        final h = mq.size.height / s; // высота в эталонных единицах
        return MediaQuery(
          data: mq.copyWith(
            size: Size(kDesignWidth, h),
            padding: mq.padding / s,
            viewPadding: mq.viewPadding / s,
            viewInsets: mq.viewInsets / s,
            systemGestureInsets: mq.systemGestureInsets / s,
            textScaler: TextScaler.noScaling,
            boldText: false,
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: kDesignWidth,
              maxWidth: kDesignWidth,
              minHeight: h,
              maxHeight: h,
              child: Transform.scale(
                scale: s,
                alignment: Alignment.topLeft,
                child: child!,
              ),
            ),
          ),
        );
      },
      // русский язык: календарь, кнопки «Отмена / OK», названия месяцев
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Api.token == null ? const LoginScreen() : const HomeShell(),
    );
  }
}