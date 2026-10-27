import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/net.dart';

/// Основной цвет приложения: тот же, что на экранах (гараж, ТО и доки, узлы).
const kPrimary = Color(0xFFE08A00);
const kText = Color(0xFF111827);
const kMuted = Color(0xFF6B7280);
const kBg = Color(0xFFF6F7FA);
const kLine = Color(0xFFE5E7EB);
const kGreen = Color(0xFF16A34A);
const kAmber = Color(0xFFD97706);
const kRed = Color(0xFFDC2626);

/// Единая тема приложения. Подключается в main.dart: theme: buildTheme()
ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: kBg,
  colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, surface: Colors.white),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: kText,
    contentTextStyle: const TextStyle(
        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: kPrimary.withOpacity(0.14),
    iconTheme: MaterialStateProperty.resolveWith<IconThemeData?>(
          (s) => IconThemeData(
        color: s.contains(MaterialState.selected) ? kPrimary : kMuted,
      ),
    ),
    labelTextStyle: MaterialStateProperty.resolveWith<TextStyle?>(
          (s) => TextStyle(
        fontSize: 12,
        fontWeight: s.contains(MaterialState.selected)
            ? FontWeight.w700
            : FontWeight.w600,
        color: s.contains(MaterialState.selected) ? kText : kMuted,
      ),
    ),
  ),
);

int? daysOf(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.round();
  return int.tryParse('$v');
}

/// 12345 -> "12 345"
String fmtKm(dynamic m) {
  final n = m is num ? m.round() : (int.tryParse('$m') ?? 0);
  return n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ' ',
  );
}
/// Единица пробега машины или записи: 'миль' или 'км'
String unitOf(dynamic v) =>
    (v is Map && v['mileage_unit'] == 'mi') ? 'миль' : 'км';

/// "2027-03-12" -> "12.03.2027"
String fmtDate(dynamic s) {
  if (s == null) return '';
  final p = '$s'.split('-');
  if (p.length != 3) return '$s';
  return '${p[2]}.${p[1]}.${p[0]}';
}

/// За сколько дней до окончания документ становится жёлтым («скоро») и красным («срочно»)
const int kSoonDays = 7;
const int kUrgentDays = 0;  // красный: только сегодня (0) или просрочено

Color statusColor(int? d) {
  if (d == null) return kMuted;
  if (d <= kUrgentDays) return kRed;
  if (d <= kSoonDays) return kAmber;
  return kGreen;
}

String daysText(int? d) {
  if (d == null) return 'нет';
  if (d < 0) return 'просрочено ${-d} дн.';
  if (d == 0) return 'сегодня';
  return '$d дн.';
}

/// Нужно ли обратить внимание на машину (документ истёк или истекает в ближайшие kSoonDays дней)
bool needsAttention(dynamic v) {
  final a = daysOf(v['insurance_days']);
  final b = daysOf(v['inspection_days']);
  return (a != null && a <= kSoonDays) || (b != null && b <= kSoonDays);
}

class StatusPill extends StatelessWidget {
  final String label;
  final int? days;
  const StatusPill({super.key, required this.label, required this.days});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(days);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label · ${daysText(days)}',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c),
          ),
        ],
      ),
    );
  }
}

/// Цвет полоски ресурса: чем меньше осталось, тем краснее
Color resourceColor(double v) => v > 0.5 ? kGreen : (v > 0.2 ? kAmber : kRed);

/// Карточка узла с полоской ресурса (value: сколько осталось, 0..1)
class ResourceBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  const ResourceBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = resourceColor(value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: kText)),
              ),
              Text('${(value * 100).round()}%',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: c)),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12.5, color: kMuted)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: c.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
        ],
      ),
    );
  }
}

/// Красивое уведомление снизу. error: true — красное.
void toast(BuildContext context, String text, {bool error = false}) {
  final c = error ? kRed : kGreen;
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    backgroundColor: Colors.white,
    elevation: 6,
    duration: const Duration(milliseconds: 2500),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: c.withOpacity(0.4)),
    ),
    content: Row(
      children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: c, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
        ),
      ],
    ),
  ));
}
/// Номерной знак: белая плашка с двойной рамкой, как на настоящем номере
class PlateBadge extends StatelessWidget {
  final String plate;
  final double fs;
  const PlateBadge(this.plate, {super.key, this.fs = 13});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kText, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: fs * 0.7, vertical: fs * 0.25),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: kText.withOpacity(0.25), width: 0.8),
        ),
        child: Text(
          plate.toUpperCase(),
          style: TextStyle(
            fontSize: fs,
            height: 1.1,
            letterSpacing: fs * 0.12,
            fontWeight: FontWeight.w800,
            color: kText,
          ),
        ),
      ),
    );
  }
}

/// Красная плашка сверху, пока нет соединения. Сама исчезает, когда сеть вернулась.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Net.online,
      builder: (_, on, __) => AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: on
            ? const SizedBox(width: double.infinity)
            : Material(
          color: kRed,
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: Net.check,
              child: const Padding(
                padding:
                EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'Нет соединения. Данные могут быть устаревшими',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                    Text('Повторить',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Меню по долгому нажатию на узел: 'replace' | 'delete' | null
Future<String?> showPartActions(BuildContext context, String name) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: kText)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.build_rounded, color: kPrimary),
              title: const Text('Зафиксировать замену',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'replace'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: kRed),
              title: const Text('Удалить установку',
                  style: TextStyle(fontWeight: FontWeight.w600, color: kRed)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Подтверждение и снятие узла с машины (POST /parts/remove).
/// Узел пропадает из «Узлов», история замен остаётся в «Истории».
/// Возвращает true, если снято. Списки обновятся сами через Api.docsChanged.
Future<bool> deletePartFlow(
    BuildContext context, int vehicleId, int partTypeId, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) => _DeletePartDialog(name: name),
  );
  if (ok != true) return false;
  try {
    await Api.removePart(vehicleId, partTypeId);
    Api.docsChanged.value++;
    if (context.mounted) toast(context, 'Установка удалена');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) toast(context, 'Нет связи с сервером', error: true);
  }
  return false;
}

/// Окно подтверждения удаления установки
class _DeletePartDialog extends StatelessWidget {
  final String name;
  const _DeletePartDialog({required this.name});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: kRed, size: 24),
            ),
            const SizedBox(height: 16),
            const Text('Удалить установку?',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: kText)),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                      text: name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: kText)),
                  const TextSpan(
                      text:
                      ' пропадёт из списка узлов этой машины. История замен сохранится.'),
                ],
              ),
              style:
              const TextStyle(fontSize: 14, height: 1.4, color: kMuted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: kText,
                        backgroundColor: kBg,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Отмена',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: kRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Удалить',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}