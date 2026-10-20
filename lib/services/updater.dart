import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'api.dart';

class Updater {
  static bool _showing = false;

  static Future<void> check(BuildContext context) async {
    if (_showing) return;
    try {
      final r = await http
          .get(Uri.parse('${Api.baseUrl}/app-version'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final data = jsonDecode(r.body);
      final latest = (data['version'] as num).toInt();
      final url = data['url'] as String;
      final notes = (data['notes'] ?? '') as String;

      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      if (latest <= current) return;
      if (!context.mounted) return;

      _showing = true;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(url: url, notes: notes),
      );
      _showing = false;
    } catch (_) {
      _showing = false;
    }
  }
}

class _UpdateDialog extends StatefulWidget {
  final String url, notes;
  const _UpdateDialog({required this.url, required this.notes});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  int _percent = 0;
  String? _error;

  void _start() {
    setState(() {
      _busy = true;
      _error = null;
    });
    OtaUpdate()
        .execute(widget.url, destinationFilename: 'mechanic.apk')
        .listen((e) {
      if (!mounted) return;
      setState(() {
        switch (e.status) {
          case OtaStatus.DOWNLOADING:
            _percent = int.tryParse(e.value ?? '') ?? _percent;
            break;
          case OtaStatus.INSTALLING:
            _busy = false;
            break;
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            _busy = false;
            _error =
            'Разрешите установку из этого приложения в настройках и нажмите «Обновить» ещё раз.';
            break;
          default:
            _busy = false;
            _error = 'Не удалось скачать. Попробуйте ещё раз.';
        }
      });
    }, onError: (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Не удалось скачать. Попробуйте ещё раз.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Доступно обновление'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.notes.isNotEmpty) Text(widget.notes),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _percent / 100),
              const SizedBox(height: 6),
              Text('Скачивание: $_percent%'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: [
          if (!_busy)
            TextButton(onPressed: _start, child: const Text('Обновить')),
        ],
      ),
    );
  }
}