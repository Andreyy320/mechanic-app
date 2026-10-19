import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api.dart';

class Net {
  static final online = ValueNotifier<bool>(true);
  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static Timer? _retry;

  static void start() {
    Api.onNetError = () => _set(false);
    _sub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (r.contains(ConnectivityResult.none)) {
        _set(false);
      } else {
        check();
      }
    });
    check();
  }

  /// Есть ли сеть и отвечает ли сервер (любой HTTP-ответ, даже 401, = сервер жив)
  static Future<void> check() async {
    final r = await Connectivity().checkConnectivity();
    if (r.contains(ConnectivityResult.none)) {
      _set(false);
      return;
    }
    try {
      await http
          .get(Uri.parse('${Api.baseUrl}/version'))
          .timeout(const Duration(seconds: 5));
      _set(true);
    } catch (_) {
      _set(false);
    }
  }

  static void _set(bool v) {
    if (online.value == v) return;
    online.value = v;
    if (v) {
      _retry?.cancel();
      _retry = null;
      Api.docsChanged.value++; // сеть вернулась, обновить все вкладки
    } else {
      // пока офлайн, проверяем каждые 5 секунд
      _retry ??= Timer.periodic(const Duration(seconds: 5), (_) => check());
    }
  }
}