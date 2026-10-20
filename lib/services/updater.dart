import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../screens/ui.dart';
import 'api.dart';

class Updater {
  static bool _showing = false;

  /// Сервер отдаёт только последнюю версию и один URL,
  /// поэтому качается всегда одна последняя сборка.
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

      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      if (latest <= current) return;
      if (!context.mounted) return;

      _showing = true;
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.55),
        builder: (_) => _UpdateDialog(url: url),
      );
      _showing = false;
    } catch (_) {
      _showing = false;
    }
  }

  /// Только для проверки дизайна: скачивание имитируется.
  static Future<void> preview(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => const _UpdateDialog(url: '', simulate: true),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String url;
  final bool simulate;
  const _UpdateDialog({required this.url, this.simulate = false});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  bool _installing = false;
  int _percent = 0;
  String? _error;
  Timer? _fake;

  @override
  void dispose() {
    _fake?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _busy = true;
      _installing = false;
      _percent = 0;
      _error = null;
    });
    if (widget.simulate) {
      _fake = Timer.periodic(const Duration(milliseconds: 60), (t) {
        if (!mounted) return t.cancel();
        setState(() => _percent += 2);
        if (_percent >= 100) {
          t.cancel();
          setState(() {
            _busy = false;
            _installing = true;
          });
        }
      });
      return;
    }
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
            _installing = true;
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

  Widget _icon() {
    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kPrimary.withOpacity(0.08),
            ),
          ),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kPrimary.withOpacity(0.14),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFB02E), kPrimary],
              ),
              boxShadow: [
                BoxShadow(
                  color: kPrimary.withOpacity(0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.system_update_rounded,
                color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _bottom() {
    if (_busy) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_percent%',
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: kPrimary)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _percent / 100,
              minHeight: 10,
              backgroundColor: kPrimary.withOpacity(0.12),
              valueColor: const AlwaysStoppedAnimation(kPrimary),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Скачиваем обновление…',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: kMuted)),
        ],
      );
    }
    if (_installing) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text('Открываю установщик…',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: kMuted)),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: _start,
        style: FilledButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text('ОБНОВИТЬ',
            style: TextStyle(
                fontSize: 15, letterSpacing: 0.6, fontWeight: FontWeight.w800)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.9, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (_, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: v, child: child),
        ),
        child: Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _icon()),
                const SizedBox(height: 20),
                const Text('Доступно обновление',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 23,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: kText)),
                const SizedBox(height: 8),
                const Text('Установите новую версию,\nчтобы продолжить работу',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: kMuted)),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: kRed, fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 24),
                _bottom(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}