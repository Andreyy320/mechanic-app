import 'package:flutter/material.dart';

const kPrimary = Color(0xFF2563EB);
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
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: kPrimary.withOpacity(0.12),
    labelTextStyle: MaterialStateProperty.all(
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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

/// "2027-03-12" -> "12.03.2027"
String fmtDate(dynamic s) {
  if (s == null) return '';
  final p = '$s'.split('-');
  if (p.length != 3) return '$s';
  return '${p[2]}.${p[1]}.${p[0]}';
}

Color statusColor(int? d) {
  if (d == null) return kMuted;
  if (d <= 7) return kRed;
  if (d <= 30) return kAmber;
  return kGreen;
}

String daysText(int? d) {
  if (d == null) return 'нет';
  if (d < 0) return 'просрочено ${-d} дн.';
  if (d == 0) return 'сегодня';
  return '$d дн.';
}

/// Нужно ли обратить внимание на машину (документ истёк или истекает в ближайшие 30 дней)
bool needsAttention(dynamic v) {
  final a = daysOf(v['insurance_days']);
  final b = daysOf(v['inspection_days']);
  return (a != null && a <= 30) || (b != null && b <= 30);
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