import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  static Future<void> loadSaved() async {
    token = await _storage.read(key: 'token');
    name = await _storage.read(key: 'name');
    role = await _storage.read(key: 'role');
  }

  static Future<void> logout() async {
    token = name = role = null;
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
      body: jsonEncode({'login': login, 'password': password}),
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

  static Future<dynamic> _send(String method, String path,
      [Object? body]) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final r = await http.Response.fromStream(await req.send().timeout(_timeout));
    final data = _decode(r.body);
    if (r.statusCode == 401) {
      await logout();
      onUnauthorized?.call();
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

  // ───────── профиль ─────────

  static Future<dynamic> me() => _send('GET', '/me');

  static Future<void> changePassword(String current, String password) =>
      _send('POST', '/me/password', {'current': current, 'password': password});

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

  // ───────── документы (страховка, техосмотр, прочее) ─────────

  /// doc_type: insurance | inspection | other
  /// Поля: id, doc_type, title, number, note, date_from, date_to, days_left
  static Future<List<dynamic>> vehicleDocuments(int vehicleId) =>
      _list('/vehicles/$vehicleId/documents');

  /// Все документы одного вида по всем машинам (type: insurance | inspection)
  static Future<List<dynamic>> documents(String type) =>
      _list('/documents?type=$type');

  /// body: doc_type, date_to (YYYY-MM-DD, обязательно), date_from, number, title, note
  /// «Продлить» = добавить новый документ с новыми датами.
  static Future<dynamic> addDocument(int vehicleId, Map<String, dynamic> body) =>
      _send('POST', '/vehicles/$vehicleId/documents', body);

  static Future<void> updateDocument(int id, Map<String, dynamic> body) =>
      _send('PUT', '/documents/$id', body);

  static Future<void> deleteDocument(int id) =>
      _send('DELETE', '/documents/$id');

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