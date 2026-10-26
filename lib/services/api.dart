import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'dart:io' show SocketException;

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}

class Api {
  // потом замени на https://твой-домен/api
  static const baseUrl = 'http://194.156.66.100:5001/api';
  static const _timeout = Duration(seconds: 20);
  static const _storage = FlutterSecureStorage();

  static String? token;
  static String? name;
  static String? role;
  static void Function()? onUnauthorized; // вызывается при 401
  static void Function()? onNetError; // вызывается при сетевой ошибке
  static String? _pushToken;

  static Future<void> registerPush(String t) async {
    _pushToken = t;
    try {
      await _send('POST', '/notify/register', {'token': t});
    } catch (e) {
      debugPrint('registerPush: $e');
    }
  }


  static Future<void> loadSaved() async {
    token = await _storage.read(key: 'token');
    name = await _storage.read(key: 'name');
    role = await _storage.read(key: 'role');
  }

  static Future<void> logout({bool notifyServer = true}) async {
    stopEvents();
    final pt = _pushToken;
    _pushToken = null;
    if (notifyServer && pt != null && token != null) {
      try {
        await _send('POST', '/notify/unregister', {'token': pt});
      } catch (_) {}
    }
    token = name = role = null;
    _lastResult = null;
    _lastSync = null;
    _inflight = null;
    _ver = null;
    await _storage.deleteAll();
  }

  /// Ответ сервера может быть не JSON (например, страница ошибки от nginx) —
  /// тогда вместо падения возвращаем null.
  static dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static Future<void> login(String login, String password) async {
    final r = await http
        .post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password, 'client': 'app'}),
    )
        .timeout(_timeout);
    final data = _decode(r.body);
    if (r.statusCode != 200 || data is! Map) {
      throw ApiException(
          (data is Map ? data['error'] : null) ?? 'Ошибка входа', r.statusCode);
    }
    token = data['token'];
    name = data['name'];
    role = data['role'];
    await _storage.write(key: 'token', value: token);
    await _storage.write(key: 'name', value: name);
    await _storage.write(key: 'role', value: role);
  }

  // ───────── сигналы об изменениях с сервера ─────────
  static http.Client? _sseClient;
  static bool _sseOn = false;

  static void startEvents() {
    if (_sseOn) return;
    _sseOn = true;
    _eventsLoop();
  }

  static void stopEvents() {
    _sseOn = false;
    _sseClient?.close();
    _sseClient = null;
  }

  static Future<void> _eventsLoop() async {
    var first = true;
    while (_sseOn) {
      final client = http.Client();
      _sseClient = client;
      try {
        if (token == null) {
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }
        final req = http.Request('GET', Uri.parse('$baseUrl/events'));
        req.headers['Authorization'] = 'Bearer $token';
        req.headers['Accept'] = 'text/event-stream';
        req.headers['X-Client'] = 'app';
        final resp = await client.send(req).timeout(_timeout);
        if (resp.statusCode == 401) {
          await logout(notifyServer: false);
          onUnauthorized?.call();
          break;
        }
        if (resp.statusCode != 200) throw Exception('events ${resp.statusCode}');
        var buf = '';
        // если 70 секунд тишины (даже пингов нет) — считаем связь мёртвой и переподключаемся
        await for (final chunk in resp.stream
            .transform(utf8.decoder)
            .timeout(const Duration(seconds: 70))) {
          buf += chunk;
          if (buf.length > 100000) buf = '';
          final parts = buf.split('\n\n');
          buf = parts.removeLast();
          for (final p in parts) {
            if (p.contains('data: hello')) {
              if (!first) docsChanged.value++; // после переподключения догоняем пропущенное
              first = false;
            } else if (p.contains('data: changed')) {
              docsChanged.value++;
            }
          }
        }
      } catch (e) {
        debugPrint('events: $e');
      } finally {
        client.close();
      }
      if (_sseOn) await Future.delayed(const Duration(seconds: 3));
    }
  }

  static Future<dynamic> _send(String method, String path,
      [Object? body]) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers['Content-Type'] = 'application/json';
    req.headers['X-Client'] = 'app';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final http.Response r;
    try {
      r = await http.Response.fromStream(await req.send().timeout(_timeout));
    } on SocketException {
      onNetError?.call();
      rethrow;
    } on TimeoutException {
      onNetError?.call();
      rethrow;
    } on http.ClientException {
      onNetError?.call();
      rethrow;
    }
    final data = _decode(r.body);
    if (r.statusCode == 401) {
      if (token != null) {
        await logout(notifyServer: false);
        onUnauthorized?.call();
      }
      throw ApiException('Войдите заново', 401);
    }
    if (r.statusCode >= 400) {
      throw ApiException(
          (data is Map ? data['error'] : null) ?? 'Ошибка сервера',
          r.statusCode);
    }
    return data;
  }

  static Future<List<dynamic>> _list(String path) async =>
      (await _send('GET', path)) as List<dynamic>;
  // ───────── пользователи (только админ) ─────────

  /// id, login, name, role, active — для выбора владельца новой машины
  static Future<List<dynamic>> users() => _list('/users');
  // ───────── профиль ─────────

  static Future<dynamic> me() => _send('GET', '/me');

  static Future<void> changeLogin(String currentPassword, String newLogin) async {
    final r = await _send('POST', '/me/login', {
      'current': currentPassword,
      'login': newLogin,
      'client': 'app',
    });
    // Если ваш бэкенд при смене логина возвращает новый токен (как при смене пароля)
    if (r is Map && r['token'] is String) {
      token = r['token'];
      await _storage.write(key: 'token', value: token);
    }
  }


  static Future<void> changePassword(String current, String password) async {
    final r = await _send('POST', '/me/password',
        {'current': current, 'password': password, 'client': 'app'});
    if (r is Map && r['token'] is String) {
      token = r['token'];
      await _storage.write(key: 'token', value: token);
    }
  }
  // ───────── машины ─────────

  /// Каждая машина: id, plate, model, color, mileage, description, owner_name,
  /// insurance_from/to/days, inspection_from/to/days
  static Future<List<dynamic>> vehicles() => _list('/vehicles');

  /// body: plate, model, color, mileage, description
  /// (админ дополнительно передаёт owner_id)
  static Future<dynamic> createVehicle(Map<String, dynamic> body) =>
      _send('POST', '/vehicles', body);

  static Future<dynamic> updateVehicle(int id, Map<String, dynamic> body) =>
      _send('PUT', '/vehicles/$id', body);

  static Future<void> deleteVehicle(int id) => _send('DELETE', '/vehicles/$id');

  static Future<void> updateMileage(int id, int km, {bool force = false}) =>
      _send('PUT', '/vehicles/$id/mileage', {'mileage': km, 'force': force});

  /// Кнопка «Пробег с GPS»: механик обновляет свои машины, админ все.
  /// Ответ: updated, unchanged, lower, not_found_count, changes[], ...
  static Future<dynamic> syncMileageGps() => _send('POST', '/mileage-sync');

  static dynamic _lastResult;
  static DateTime? _lastSync;
  static Future<dynamic>? _inflight;

  /// Синхронизация пробега с GPS. Автоматически — не чаще minGap.
  /// Если синхронизация уже идёт, просто ждём её результат.
  static Future<dynamic> autoSyncMileage({
    Duration minGap = const Duration(minutes: 5),
    bool force = false,
  }) {
    if (token == null) return Future.value(null);
    if (_inflight != null) return _inflight!;
    final now = DateTime.now();
    final gap = force ? const Duration(seconds: 30) : minGap;
    if (_lastSync != null && now.difference(_lastSync!) < gap) {
      return Future.value(force ? _lastResult : null);
    }
    _inflight = () async {
      try {
        final r = await syncMileageGps();
        _lastSync = DateTime.now();
        _lastResult = r;
        if (r is Map && ((r['updated'] as num?) ?? 0) > 0) docsChanged.value++;
        return r;
      } catch (_) {
        return null;
      } finally {
        _inflight = null;
      }
    }();
    return _inflight!;
  }
  // ───────── документы (страховка, техосмотр, прочее) ─────────

  /// doc_type: insurance | inspection | other
  /// Поля: id, doc_type, title, number, note, date_from, date_to, days_left
  static Future<List<dynamic>> vehicleDocuments(int vehicleId) =>
      _list('/vehicles/$vehicleId/documents');

  /// Все документы одного вида по всем машинам (type: insurance | inspection)
  static Future<List<dynamic>> documents(String type) =>
      _list('/documents?type=$type');

  static final docsChanged = ValueNotifier<int>(0);
  static Object? _ver;

  /// Спрашивает у сервера версию данных; если изменилась, обновляет все вкладки.
  static Future<void> checkVersion() async {
    if (token == null) return;
    try {
      final r = await _send('GET', '/version');
      final v = r is Map ? r['v'] : null;
      if (v == null) return;
      if (_ver != null && _ver != v) {
        debugPrint('version changed -> refresh');
        docsChanged.value++;
      }
      _ver = v;
    } catch (e) {
      debugPrint('checkVersion error: $e');
    }
  }
  static Future<dynamic> addDocument(
      int vehicleId, Map<String, dynamic> body) async {
    final r = await _send('POST', '/vehicles/$vehicleId/documents', body);
    docsChanged.value++;
    return r;
  }

  static Future<void> updateDocument(int id, Map<String, dynamic> body) async {
    await _send('PUT', '/documents/$id', body);
    docsChanged.value++;
  }

  static Future<void> deleteDocument(int id) async {
    await _send('DELETE', '/documents/$id');
    docsChanged.value++;
  }

  // ───────── «Требует внимания» ─────────

  /// Список с полем kind: 'doc' (просроченные/истекающие документы)
  /// или 'part' (запчасти на исходе, level: red | yellow)
  static Future<List<dynamic>> attention() => _list('/attention');

  // ───────── запчасти и износ (узлы) ─────────

  /// Справочник: id, name, norm_km, warn1_km, warn2_km, track
  static Future<List<dynamic>> partTypes() => _list('/part-types');

  /// Журнал установок по всем машинам пользователя: vehicle_id, part_type_id,
  /// part_name, norm_km, warn1_km, warn2_km, installed_at, mileage_at,
  /// current_mileage, fact_km, left_km
  static Future<List<dynamic>> parts() => _list('/parts');

  /// «Зафиксировать замену»: installedAt в формате YYYY-MM-DD
  static Future<dynamic> addPart({
    required int vehicleId,
    required int partTypeId,
    required String installedAt,
    required int mileageAt,
  }) =>
      _send('POST', '/parts', {
        'vehicle_id': vehicleId,
        'part_type_id': partTypeId,
        'installed_at': installedAt,
        'mileage_at': mileageAt,
      });

  static Future<void> updatePart(int id, Map<String, dynamic> body) =>
      _send('PUT', '/parts/$id', body);

  static Future<void> deletePart(int id) => _send('DELETE', '/parts/$id');

  // ───────── справочник кузовов ─────────

  static Future<List<dynamic>> bodyTypes() => _list('/body-types');
}