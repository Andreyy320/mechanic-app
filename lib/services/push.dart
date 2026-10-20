import 'dart:ui' show Color;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api.dart';

/// Пуш-уведомления: разрешение, токен, показ при открытом приложении, тап по уведомлению.
class Push {
  static bool _listening = false; // слушатели вешаются один раз
  static String? _token;

  /// Какую вкладку открыть после тапа по уведомлению (1 — «Узлы», 2 — «ТО и доки»).
  /// HomeShell слушает это значение и сбрасывает его в null.
  static final openTab = ValueNotifier<int?>(null);

  static final _local = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'main3',
    'Уведомления',
    description: 'Сроки техосмотра и страховки, износ запчастей',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('notif'),
  );

  /// Вызывать после входа. Токен отправляется серверу при КАЖДОМ вызове
  /// (после выхода и входа под другим логином он должен привязаться к новому человеку).
  static Future<void> init() async {
    try {
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      if (!_listening) {
        _listening = true;
        await _initLocal();
        await m.setForegroundNotificationPresentationOptions(
            alert: true, badge: true, sound: true);
        FirebaseMessaging.onMessage.listen(_showForeground);
        FirebaseMessaging.onMessageOpenedApp.listen(_open);
        m.onTokenRefresh.listen((t) {
          _token = t;
          Api.registerPush(t);
        });
        final first = await m.getInitialMessage(); // приложение открыто тапом по пушу
        if (first != null) _open(first);
      }
      _token = await m.getToken();
      if (kDebugMode) debugPrint('FCM token: $_token');
      if (_token != null) await Api.registerPush(_token!);
    } catch (e) {
      debugPrint('Push init: $e');
    }
  }

  /// Повторно отдать токен серверу (например, когда вернулись в приложение).
  static Future<void> resync() async {
    if (Api.token == null) return;
    if (_token == null) {
      await init(); // токен ещё не получен (например, не было сети при запуске) — пробуем снова
      return;
    }
    await Api.registerPush(_token!);
  }

  static Future<void> _initLocal() async {
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
      onDidReceiveNotificationResponse: (r) => _openScreen(r.payload),
    );
    await _local
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// На Android FCM сам не рисует уведомление, пока приложение открыто — рисуем сами.
  /// (На iOS это делает setForegroundNotificationPresentationOptions.)
  static void _showForeground(RemoteMessage m) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final n = m.notification;
    final title = n?.title ?? m.data['title'];
    final body = n?.body ?? m.data['body'];
    if (title == null && body == null) return;
    _local.show(
      id: m.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: const Color(0xFFE08A00),
          styleInformation: BigTextStyleInformation(body ?? ''),
        ),
      ),
      payload: m.data['screen'],
    );
  }
  static void _open(RemoteMessage m) => _openScreen(m.data['screen']);

  static void _openScreen(String? screen) {
    final i = screen == 'parts' ? 1 : (screen == 'service' ? 2 : null);
    if (i != null) openTab.value = i;
  }
}