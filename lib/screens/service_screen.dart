import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import 'mileage_sheet.dart';
import 'ui.dart' show daysOf, fmtKm, fmtDate;

/// Валюта для стоимости работ (поменяйте на свою)
const _kCurrency = '₽';

/// Интервал ТО в км
const _kServiceInterval = 15000;

class _P {
  static const bg = Color(0xFF0B0B0D);
  static const card = Color(0xFF161619);
  static const card2 = Color(0xFF1F1F24);
  static const line = Color(0xFF2B2B31);
  static const text = Color(0xFFF4F4F5);
  static const muted = Color(0xFF8B8B94);
  static const accent = Color(0xFFF5A300);
  static const onAccent = Color(0xFF111111);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
}

Color _dc(int? d) {
  if (d == null) return _P.muted;
  if (d <= 7) return _P.red;
  if (d <= 30) return _P.accent;
  return _P.green;
}

String _dshort(int? d) {
  if (d == null) return '—';
  if (d < 0) return '−${-d} дн.';
  if (d == 0) return 'сегодня';
  return '$d дн.';
}

String _dtag(int? d) {
  if (d == null) return 'НЕТ ДАННЫХ';
  if (d < 0) return 'ПРОСРОЧЕНО';
  if (d <= 7) return 'СРОЧНО';
  if (d <= 30) return 'ИСТЕКАЕТ';
  return 'АКТИВЕН';
}

String _today() {
  final n = DateTime.now();
  String t(int x) => x.toString().padLeft(2, '0');
  return '${t(n.day)}.${t(n.month)}.${n.year}';
}

/// Запись истории обслуживания.
/// TODO: заменить на данные с сервера.
class _Rec {
  final String title;
  final int km;
  final String date;
  final String desc;
  final int cost;
  const _Rec(this.title, this.km, this.date, this.desc, this.cost);
}

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});
  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  late Future<List<dynamic>> _future = Api.vehicles();
  int _index = 0;
  final Map<dynamic, List<_Rec>> _history = {};

  Future<void> _reload() async {
    setState(() => _future = Api.vehicles());
    try {
      await _future;
    } catch (_) {}
  }

  void _soon() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Раздел в разработке')),
  );

  List<_Rec> _historyFor(dynamic v) {
    return _history.putIfAbsent(v['id'], () {
      final m = ((v['mileage'] as num?) ?? 0).round();
      final last = (m ~/ _kServiceInterval) * _kServiceInterval;
      return [
        _Rec('Малое ТО (ТО-${last ~/ _kServiceInterval})', last,
            '12.03.2026', 'Замена масла, масляного и салонного фильтров.',
            12400),
        _Rec('Замена задних тормозных колодок', last - 4200, '02.12.2025',
            'Колодки задней оси, проверка дисков.', 9800),
      ];
    });
  }

  Future<void> _addRecord(dynamic v) async {
    final rec = await showModalBottomSheet<_Rec>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddRecordSheet(
          mileage: ((v['mileage'] as num?) ?? 0).round()),
    );
    if (rec != null) {
      // TODO: отправить на сервер
      setState(() => _historyFor(v).insert(0, rec));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snap) {
        Widget body;
        List<dynamic> all = [];
        if (snap.connectionState != ConnectionState.done) {
          body = const Center(
              child: CircularProgressIndicator(color: _P.accent));
        } else if (snap.hasError) {
          body = _error();
        } else {
          all = snap.data ?? [];
          if (all.isEmpty) {
            body = const Center(
                child: Text('Машин пока нет',
                    style: TextStyle(color: _P.muted, fontSize: 15)));
          } else {
            if (_index >= all.length) _index = 0;
            body = _content(all[_index]);
          }
        }

        final v = all.isEmpty ? null : all[_index];
        return Scaffold(
          backgroundColor: _P.bg,
          appBar: AppBar(
            backgroundColor: _P.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            toolbarHeight: 68,
            titleSpacing: 16,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ТО И СТРАХОВКА',
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: _P.accent)),
                Text(v == null ? 'Обслуживание' : '${v['model']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: _P.text)),
              ],
            ),
            actions: [
              if (v != null)
                GestureDetector(
                  onTap: all.length > 1 ? () => _pickVehicle(all) : null,
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text('${v['plate']}',
                            style: const TextStyle(
                                fontSize: 13,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111111))),
                        if (all.length > 1)
                          const Icon(Icons.expand_more_rounded,
                              size: 18, color: Color(0xFF111111)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }

  Future<void> _pickVehicle(List<dynamic> all) async {
    final i = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            for (var k = 0; k < all.length; k++)
              ListTile(
                onTap: () => Navigator.pop(context, k),
                leading: const Icon(Icons.directions_car_rounded,
                    color: _P.accent),
                title: Text('${all[k]['model']}',
                    style: const TextStyle(
                        color: _P.text, fontWeight: FontWeight.w700)),
                subtitle: Text('${all[k]['plate']}',
                    style: const TextStyle(color: _P.muted)),
                trailing: k == _index
                    ? const Icon(Icons.check_rounded, color: _P.accent)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (i != null) setState(() => _index = i);
  }

  // ───────── содержимое ─────────

  Widget _content(dynamic v) {
    final m = ((v['mileage'] as num?) ?? 0).round();
    final last = (m ~/ _kServiceInterval) * _kServiceInterval;
    final next = last + _kServiceInterval;
    final left = next - m;
    final toNum = next ~/ _kServiceInterval;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: _P.accent,
            backgroundColor: _P.card2,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                _stats(v, m, left),
                const SizedBox(height: 20),
                _docsSection(v),
                const SizedBox(height: 20),
                _nextService(toNum, next, left),
                const SizedBox(height: 20),
                _historySection(v),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _addRecord(v),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
              label: const Text('ДОБАВИТЬ ЗАПИСЬ О ТО / ПОЛИС'),
              style: FilledButton.styleFrom(
                backgroundColor: _P.accent,
                foregroundColor: _P.onAccent,
                textStyle: const TextStyle(
                    fontSize: 13.5,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w800),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String t, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(t,
              style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: _P.muted)),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );

  // ───────── плитки сверху ─────────

  Widget _stats(dynamic v, int m, int left) {
    final c = left <= 1000 ? _P.red : (left <= 3000 ? _P.accent : _P.green);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _P.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _P.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ТЕКУЩИЙ ПРОБЕГ',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                        color: _P.muted)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${fmtKm(m)} км',
                      style: const TextStyle(
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: _P.text)),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final km = await showMileageSheet(context, v);
                    if (km != null) _reload();
                  },
                  child: const Text('ОБНОВИТЬ ›',
                      style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w800,
                          color: _P.accent)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ДО СЛЕДУЮЩЕГО ТО',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                        color: _P.muted)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${fmtKm(left)} км',
                      style: TextStyle(
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: c)),
                ),
                const SizedBox(height: 8),
                Text('интервал ${fmtKm(_kServiceInterval)} км',
                    style: const TextStyle(fontSize: 11.5, color: _P.muted)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ───────── полисы и документы ─────────

  Widget _docsSection(dynamic v) {
    final ins = daysOf(v['insurance_days']);
    final insp = daysOf(v['inspection_days']);
    final active = [ins, insp].where((d) => d != null && d >= 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(
          'ПОЛИСЫ И ДОКУМЕНТЫ',
          trailing: Text('$active АКТИВНЫХ',
              style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  color: _P.green)),
        ),
        _docCard(Icons.shield_outlined, 'Страховка', v['insurance_from'],
            v['insurance_to'], ins),
        const SizedBox(height: 10),
        _docCard(Icons.fact_check_outlined, 'Техосмотр', v['inspection_from'],
            v['inspection_to'], insp),
      ],
    );
  }

  Widget _docCard(
      IconData icon, String label, dynamic from, dynamic to, int? days) {
    final c = _dc(days);
    final fromD = DateTime.tryParse('$from');
    final toD = DateTime.tryParse('$to');
    var total = 365;
    if (fromD != null && toD != null) {
      final t = toD.difference(fromD).inDays;
      if (t > 0) total = t;
    }
    final value = days == null ? 0.0 : (days / total).clamp(0.0, 1.0);
    final period = to == null
        ? 'Нет данных'
        : (from != null && '$from'.isNotEmpty && '$from' != 'null'
        ? '${fmtDate(from)} — ${fmtDate(to)}'
        : 'до ${fmtDate(to)}');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: (days != null && days <= 30) ? c.withOpacity(0.5) : _P.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: c, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _P.text)),
                    const SizedBox(height: 2),
                    Text(period,
                        style:
                        const TextStyle(fontSize: 12.5, color: _P.muted)),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_dtag(days),
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w800,
                        color: c)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: c.withOpacity(0.16),
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
          const SizedBox(height: 8),
          Text('Осталось: ${_dshort(days)}',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: _soon,
                    style: FilledButton.styleFrom(
                      backgroundColor: _P.accent,
                      foregroundColor: _P.onAccent,
                      textStyle: const TextStyle(
                          fontSize: 12.5,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w800),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('ПРОДЛИТЬ'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _soon,
                  icon: const Icon(Icons.description_outlined, size: 17),
                  label: const Text('ДОКУМЕНТ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _P.text,
                    side: const BorderSide(color: _P.line),
                    textStyle: const TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────── ближайшее ТО ─────────

  Widget _nextService(int toNum, int next, int left) {
    final c = left <= 1000 ? _P.red : (left <= 3000 ? _P.accent : _P.green);
    // TODO: список работ и запчастей — с сервера
    const works = [
      'Замена моторного масла и масляного фильтра',
      'Замена салонного фильтра',
      'Диагностика подвески и тормозной системы',
      'Проверка уровней технических жидкостей',
    ];
    const parts = [
      ('Масло 5W-30 (5 л)', 'НА СКЛАДЕ', _P.green),
      ('Комплект фильтров', 'НУЖНО КУПИТЬ', _P.accent),
      ('Свечи зажигания', 'НЕ НУЖНО', _P.muted),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('БЛИЖАЙШЕЕ ТО'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _P.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.withOpacity(0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('ТО-$toNum',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: c)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('на ${fmtKm(next)} км',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _P.text)),
                        const SizedBox(height: 2),
                        Text('осталось ${fmtKm(left)} км',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: c)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('РЕКОМЕНДУЕМЫЕ РАБОТЫ',
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w800,
                      color: _P.muted)),
              const SizedBox(height: 8),
              for (final w in works)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_rounded,
                            size: 16, color: _P.accent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(w,
                            style: const TextStyle(
                                fontSize: 13.5, color: _P.text)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text('ПОДГОТОВКА К ОБСЛУЖИВАНИЮ',
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w800,
                      color: _P.muted)),
              const SizedBox(height: 8),
              for (final p in parts)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _P.card2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(p.$1,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: _P.text)),
                      ),
                      Text(p.$2,
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w800,
                              color: p.$3)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _soon,
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text('ЗАПИСАТЬСЯ В СЕРВИС ПАРТНЁРА'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _P.text,
                    side: const BorderSide(color: _P.line),
                    textStyle: const TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────── история ─────────

  Widget _historySection(dynamic v) {
    final list = _historyFor(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('ИСТОРИЯ ОБСЛУЖИВАНИЯ'),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: Text('Записей пока нет',
                    style: TextStyle(color: _P.muted))),
          ),
        for (final r in list)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _P.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _P.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(r.title,
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: _P.text)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: _P.card2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${fmtKm(r.km)} км',
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _P.text)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(r.date,
                    style: const TextStyle(fontSize: 12, color: _P.muted)),
                if (r.desc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(r.desc,
                      style: const TextStyle(
                          fontSize: 13, height: 1.35, color: _P.muted)),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Чек: ${fmtKm(r.cost)} $_kCurrency',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _P.text)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _soon,
                      child: const Text('ЗАКАЗ-НАРЯД ›',
                          style: TextStyle(
                              fontSize: 11.5,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w800,
                              color: _P.accent)),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _error() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: _P.muted),
            const SizedBox(height: 14),
            const Text('Не удалось загрузить данные',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _P.text)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _reload,
              style: FilledButton.styleFrom(
                backgroundColor: _P.accent,
                foregroundColor: _P.onAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Окно добавления записи о ТО
class _AddRecordSheet extends StatefulWidget {
  final int mileage;
  const _AddRecordSheet({required this.mileage});
  @override
  State<_AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends State<_AddRecordSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late final _km = TextEditingController(text: '${widget.mileage}');
  final _cost = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _km.dispose();
    _cost.dispose();
    super.dispose();
  }

  InputDecoration _d(String hint, {String? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _P.muted),
    suffixText: suffix,
    suffixStyle: const TextStyle(color: _P.muted),
    filled: true,
    fillColor: _P.card2,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );

  void _save() {
    final t = _title.text.trim();
    final km = int.tryParse(_km.text.trim());
    if (t.isEmpty || km == null) {
      setState(() => _error = 'Укажите название и пробег');
      return;
    }
    Navigator.pop(
      context,
      _Rec(t, km, _today(), _desc.text.trim(),
          int.tryParse(_cost.text.trim()) ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Запись о ТО',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _P.text)),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              style: const TextStyle(color: _P.text),
              cursorColor: _P.accent,
              decoration: _d('Что сделали (например, Малое ТО)'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _km,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: _P.text),
                    cursorColor: _P.accent,
                    decoration: _d('Пробег', suffix: 'км'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _cost,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: _P.text),
                    cursorColor: _P.accent,
                    decoration: _d('Стоимость', suffix: _kCurrency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              maxLines: 3,
              style: const TextStyle(color: _P.text),
              cursorColor: _P.accent,
              decoration: _d('Описание работ'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    style: const TextStyle(
                        color: _P.red, fontWeight: FontWeight.w500)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _P.accent,
                  foregroundColor: _P.onAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('СОХРАНИТЬ',
                    style: TextStyle(
                        fontSize: 14,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}