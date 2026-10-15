import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mechanic_app/screens/vehicleDetail_screen.dart';
import '../services/api.dart';
import 'mileage_sheet.dart';
import 'ui.dart' show daysOf, fmtKm, fmtDate;

/// ───── Палитра экрана (светлая тема, меняйте цвета здесь) ─────
class _P {
  static const bg = Color(0xFFF6F7FA);
  static const card = Color(0xFFFFFFFF);
  static const card2 = Color(0xFFF1F3F7);
  static const line = Color(0xFFE5E7EB);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const accent = Color(0xFFE08A00); // чуть темнее, чтобы читалось на белом
  static const onAccent = Color(0xFFFFFFFF);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
}

enum _Filter { all, overdue, soon }

int? _minDays(dynamic v) {
  final a = daysOf(v['insurance_days']);
  final b = daysOf(v['inspection_days']);
  if (a == null) return b;
  if (b == null) return a;
  return a < b ? a : b;
}

bool _isOverdue(dynamic v) => (_minDays(v) ?? 1) < 0;
bool _isSoon(dynamic v) {
  final m = _minDays(v);
  return m != null && m >= 0 && m <= 30;
}

Color _sc(int? d) {
  if (d == null) return _P.muted;
  if (d <= 7) return _P.red;
  if (d <= 30) return _P.accent;
  return _P.green;
}

String _tag(int? d) {
  if (d == null) return 'НЕТ ДАННЫХ';
  if (d < 0) return 'ПРОСРОЧЕНО';
  if (d <= 7) return 'СРОЧНО';
  if (d <= 30) return 'СКОРО';
  return 'В НОРМЕ';
}

String _short(int? d) {
  if (d == null) return '—';
  if (d < 0) return '−${-d} дн.';
  if (d == 0) return 'сегодня';
  return '$d дн.';
}

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});
  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  late Future<List<dynamic>> _future = Api.vehicles();
  String _query = '';
  _Filter _filter = _Filter.all;

  Future<void> _reload() async {
    setState(() => _future = Api.vehicles());
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _updateMileage(dynamic v) async {
    final km = await showMileageSheet(context, v);
    if (km != null) _reload();
  }

  Future<void> _open(dynamic v) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VehicleDetailScreen(vehicle: v)),
    );
    if (mounted) _reload();
  }

  void _soonMsg() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Раздел в разработке')),
  );

  @override
  Widget build(BuildContext context) {
    final initial = (Api.name?.trim().isNotEmpty ?? false)
        ? Api.name!.trim()[0].toUpperCase()
        : 'M';
    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        backgroundColor: _P.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 68,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _P.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _P.accent.withOpacity(0.4)),
              ),
              child: const Icon(Icons.directions_car_rounded,
                  color: _P.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ГАРАЖ МЕХАНИКА',
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: _P.accent)),
                Text(Api.name ?? 'Гараж',
                    style: const TextStyle(
                        fontSize: 22,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: _P.text)),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _P.card,
              shape: BoxShape.circle,
              border: Border.all(color: _P.accent.withOpacity(0.6)),
            ),
            child: Text(initial,
                style: const TextStyle(
                    color: _P.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: _P.accent));
          }
          if (snap.hasError) return _error();

          final all = snap.data ?? [];
          final overdue = all.where(_isOverdue).length;
          final soon = all.where(_isSoon).length;
          final q = _query.trim().toLowerCase();

          final list = all.where((v) {
            if (_filter == _Filter.overdue && !_isOverdue(v)) return false;
            if (_filter == _Filter.soon && !_isSoon(v)) return false;
            if (q.isEmpty) return true;
            return '${v['plate']} ${v['model']}'.toLowerCase().contains(q);
          }).toList()
            ..sort((a, b) =>
                (_minDays(a) ?? 99999).compareTo(_minDays(b) ?? 99999));

          final top = <Widget>[
            Row(
              children: [
                _stat(Icons.directions_car_rounded, 'В ГАРАЖЕ', all.length,
                    'активных авто', _P.accent, _Filter.all),
                const SizedBox(width: 10),
                _stat(Icons.error_outline_rounded, 'ПРОСРОЧЕНО', overdue,
                    'документы', overdue > 0 ? _P.red : _P.muted,
                    _Filter.overdue),
                const SizedBox(width: 10),
                _stat(Icons.schedule_rounded, 'СКОРО', soon, 'до 30 дней',
                    soon > 0 ? _P.accent : _P.muted, _Filter.soon),
              ],
            ),
            const SizedBox(height: 14),
            _search(),
            const SizedBox(height: 18),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 50, bottom: 30),
                child: Center(
                  child: Text(
                    all.isEmpty ? 'Машин пока нет' : 'Ничего не найдено',
                    style: const TextStyle(color: _P.muted, fontSize: 15),
                  ),
                ),
              )
            else ...[
              _hero(list.first),
              if (list.length > 1) ...[
                const SizedBox(height: 22),
                _label('ВСЕ АВТОМОБИЛИ · ${list.length - 1}'),
              ],
            ],
          ];
          final rest = list.length > 1 ? list.skip(1).toList() : <dynamic>[];
          final footer = <Widget>[
            const SizedBox(height: 10),
            _addButton(),
            const SizedBox(height: 12),
            _noteTile(),
          ];

          return RefreshIndicator(
            color: _P.accent,
            backgroundColor: _P.card,
            onRefresh: _reload,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: top.length + rest.length + footer.length,
              itemBuilder: (_, i) {
                if (i < top.length) return top[i];
                final j = i - top.length;
                if (j < rest.length) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _compact(rest[j]),
                  );
                }
                return footer[j - rest.length];
              },
            ),
          );
        },
      ),
    );
  }

  // ───────── верхние плитки ─────────

  Widget _stat(IconData icon, String label, int n, String caption, Color c,
      _Filter f) {
    final selected = _filter == f && f != _Filter.all;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = selected ? _Filter.all : f),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? c.withOpacity(0.08) : _P.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? c : _P.line, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: c),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w800,
                            color: _P.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('$n',
                  style: TextStyle(
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: c)),
              const SizedBox(height: 4),
              Text(caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _P.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _search() {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(color: _P.text),
      cursorColor: _P.accent,
      decoration: InputDecoration(
        hintText: 'Поиск по номеру или модели',
        hintStyle: const TextStyle(color: _P.muted),
        prefixIcon: const Icon(Icons.search_rounded, color: _P.muted),
        filled: true,
        fillColor: _P.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: b(_P.line),
        enabledBorder: b(_P.line),
        focusedBorder: b(_P.accent, 1.4),
      ),
    );
  }

  Widget _label(String t, {Color color = _P.muted}) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(t,
        style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: color)),
  );

  // ───────── главная карточка ─────────

  Widget _hero(dynamic v) {
    final m = _minDays(v);
    final attention = m != null && m <= 30;
    return Material(
      color: _P.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
            color: attention ? _sc(m).withOpacity(0.45) : _P.line),
      ),
      child: InkWell(
        onTap: () => _open(v),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: attention ? _sc(m) : _P.accent,
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(attention ? 'ТРЕБУЕТ ВНИМАНИЯ' : 'ОСНОВНОЙ АВТОМОБИЛЬ',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: attention ? _sc(m) : _P.accent)),
                ],
              ),
            ),
            // «обложка» вместо фото
            Container(
              height: 132,
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF7E6), Color(0xFFFFE6B3)],
                ),
                border: Border.all(color: _P.accent.withOpacity(0.25)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 8,
                    top: 14,
                    child: Icon(Icons.directions_car_filled_rounded,
                        size: 100, color: _P.accent.withOpacity(0.18)),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: const Color(0xFF111827)),
                      ),
                      child: Text('${v['plate']}',
                          style: const TextStyle(
                              fontSize: 13,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827))),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Text('${v['model']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: _P.text)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ПРОБЕГ НА ОДОМЕТРЕ',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 0.9,
                                    fontWeight: FontWeight.w800,
                                    color: _P.muted)),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('${fmtKm(v['mileage'])} км',
                                  style: const TextStyle(
                                      fontSize: 34,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800,
                                      color: _P.text)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => _updateMileage(v),
                        icon: const Icon(Icons.sync_rounded, size: 17),
                        label: const Text('ОБНОВИТЬ'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _P.text,
                          backgroundColor: _P.card2,
                          side: const BorderSide(color: _P.line),
                          textStyle: const TextStyle(
                              fontSize: 12.5,
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w800),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _docBox(Icons.shield_outlined, 'Страховка',
                      v['insurance_from'], v['insurance_to'],
                      daysOf(v['insurance_days'])),
                  _docBox(Icons.fact_check_outlined, 'Техосмотр',
                      v['inspection_from'], v['inspection_to'],
                      daysOf(v['inspection_days'])),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _soonMsg,
                            icon: const Icon(Icons.monitor_heart_outlined,
                                size: 18),
                            label: const Text('ДИАГНОСТИКА'),
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
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: () => _open(v),
                            icon: const Icon(Icons.menu_book_rounded, size: 18),
                            label: const Text('ЖУРНАЛ ТО'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _P.accent,
                              foregroundColor: _P.onAccent,
                              textStyle: const TextStyle(
                                  fontSize: 12.5,
                                  letterSpacing: 0.4,
                                  fontWeight: FontWeight.w800),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Блок документа: слева название и срок, справа дни и статус
  Widget _docBox(
      IconData icon, String label, dynamic from, dynamic to, int? days) {
    final c = _sc(days);
    final fromD = DateTime.tryParse('$from');
    final toD = DateTime.tryParse('$to');
    var total = 365;
    if (fromD != null && toD != null) {
      final t = toD.difference(fromD).inDays;
      if (t > 0) total = t;
    }
    final value = days == null ? 0.0 : (days / total).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: c, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _P.text)),
                    const SizedBox(height: 2),
                    Text(
                      to == null ? 'Нет данных' : 'до ${fmtDate(to)}',
                      style: const TextStyle(fontSize: 12.5, color: _P.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_short(days),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c)),
                  const SizedBox(height: 3),
                  Text(_tag(days),
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w800,
                          color: c)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: c.withOpacity(0.16),
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
        ],
      ),
    );
  }

  // ───────── обычная карточка ─────────

  Widget _chip(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: c.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      ],
    ),
  );

  Widget _compact(dynamic v) {
    final ins = daysOf(v['insurance_days']);
    final insp = daysOf(v['inspection_days']);
    return Material(
      color: _P.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _P.line),
      ),
      child: InkWell(
        onTap: () => _open(v),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _P.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.directions_car_rounded,
                        color: _P.accent, size: 23),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${v['model']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: _P.text)),
                        const SizedBox(height: 2),
                        Text('${v['plate']}',
                            style: const TextStyle(
                                fontSize: 13.5,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w600,
                                color: _P.muted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _P.muted),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip('Страховка · ${_short(ins)}', _sc(ins)),
                  _chip('Техосмотр · ${_short(insp)}', _sc(insp)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: _P.card2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ПРОБЕГ',
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.9,
                                  fontWeight: FontWeight.w800,
                                  color: _P.muted)),
                          Text('${fmtKm(v['mileage'])} км',
                              style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: _P.text)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _updateMileage(v),
                      icon: const Icon(Icons.sync_rounded, size: 16),
                      label: const Text('ОБНОВИТЬ'),
                      style: TextButton.styleFrom(
                        foregroundColor: _P.accent,
                        textStyle: const TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.4,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────── низ экрана ─────────

  Widget _addButton() {
    return Material(
      color: _P.accent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _soonMsg,
        child: const SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  color: _P.onAccent, size: 22),
              SizedBox(width: 8),
              Text('ДОБАВИТЬ АВТОМОБИЛЬ В ГАРАЖ',
                  style: TextStyle(
                      fontSize: 13.5,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w800,
                      color: _P.onAccent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteTile() {
    return Material(
      color: _P.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _P.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _soonMsg,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, color: _P.accent, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text('Быстрая заметка механика',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: _P.text)),
              ),
              Text('ЗАПИСАТЬ ›',
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w800,
                      color: _P.accent)),
            ],
          ),
        ),
      ),
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
            const Text('Не удалось загрузить список',
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