import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mechanic_app/screens/vehicleDetail_screen.dart';
import '../services/api.dart';
import 'vehicle_form_sheet.dart';
import 'ui.dart' show daysOf, fmtKm, fmtDate, toast, kSoonDays, kUrgentDays;

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

// ───────── износ запчастей по машине ─────────

/// Сколько отслеживаемых узлов на машине и сколько из них красных / жёлтых
class _Wear {
  final int total, red, yellow;
  const _Wear(this.total, this.red, this.yellow);

  /// 0 — в норме, 1 — скоро замена, 2 — пора менять
  int get level => red > 0 ? 2 : (yellow > 0 ? 1 : 0);
}

int _n(dynamic v) =>
    v is num ? v.round() : (num.tryParse('$v')?.round() ?? 0);

/// Считаем так же, как сайт и «Требует внимания»: по каждой запчасти берём
/// последнюю установку; красный — осталось ≤ порога 2, жёлтый — ≤ порога 1.
Map<int, _Wear> _calcWear(List<dynamic> parts, List<dynamic> cars) {
  final mileage = {for (final c in cars) _n(c['id']): _n(c['mileage'])};
  final latest = <String, dynamic>{};
  for (final p in parts) {
    final k = '${p['vehicle_id']}:${p['part_type_id']}';
    final c = latest[k];
    if (c == null) {
      latest[k] = p;
      continue;
    }
    final cmp = '${p['installed_at']}'.compareTo('${c['installed_at']}');
    if (cmp > 0 || (cmp == 0 && _n(p['id']) > _n(c['id']))) latest[k] = p;
  }
  final total = <int, int>{}, red = <int, int>{}, yellow = <int, int>{};
  for (final p in latest.values) {
    final t = p['track'];
    final untracked = t != null && !(t == true || t == 1 || t == 'true');
    final norm = _n(p['norm_km']);
    if (untracked || norm <= 0) continue;

    final vid = _n(p['vehicle_id']);
    final w2 = _n(p['warn2_km']);
    final w1 = max(_n(p['warn1_km']), w2);
    final used = max((mileage[vid] ?? 0) - _n(p['mileage_at']), 0);
    final left = norm - used;

    // та же логика уровней, что в карточке машины
    int lvl;
    if (w1 == 0 && w2 == 0) {
      final v = left / norm;
      lvl = v <= 0.2 ? 2 : (v <= 0.5 ? 1 : 0);
    } else {
      lvl = left <= w2 ? 2 : (left <= w1 ? 1 : 0);
    }

    total[vid] = (total[vid] ?? 0) + 1;
    if (lvl == 2) {
      red[vid] = (red[vid] ?? 0) + 1;
    } else if (lvl == 1) {
      yellow[vid] = (yellow[vid] ?? 0) + 1;
    }
  }
  return {
    for (final id in total.keys)
      id: _Wear(total[id]!, red[id] ?? 0, yellow[id] ?? 0)
  };
}
// ───────── сроки документов ─────────

int? _minDays(dynamic v) {
  final a = daysOf(v['insurance_days']);
  final b = daysOf(v['inspection_days']);
  if (a == null) return b;
  if (b == null) return a;
  return a < b ? a : b;
}



Color _sc(int? d) {
  if (d == null) return _P.muted;
  if (d <= kUrgentDays) return _P.red;
  if (d <= kSoonDays) return _P.accent;
  return _P.green;
}

String _tag(int? d) {
  if (d == null) return 'НЕТ ДАННЫХ';
  if (d < 0) return 'ПРОСРОЧЕНО';
  if (d <= kUrgentDays) return 'СРОЧНО';
  if (d <= kSoonDays) return 'СКОРО';
  return 'В НОРМЕ';
}

String _short(int? d) {
  if (d == null) return '—';
  if (d < 0) return '−${-d} дн.';
  if (d == 0) return 'сегодня';
  return '$d дн.';
}

String _ago(dynamic s) {
  final d = DateTime.tryParse('$s')?.toLocal();
  if (d == null) return '';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'только что';
  if (m < 60) return '$m мин назад';
  if (m < 1440) return '${m ~/ 60} ч назад';
  return '${m ~/ 1440} дн. назад';
}
class VehiclesScreen extends StatefulWidget {

  const VehiclesScreen({super.key});
  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  Map<int, _Wear> _wear = {};
  late Future<List<dynamic>> _future = _fetch();
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    // что-то изменили на другой вкладке или в карточке машины — список обновится сам
    Api.docsChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    Api.docsChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _reload();
  }

  /// Машины + износ запчастей. Если запчасти не загрузились — список всё равно покажется.
  Future<List<dynamic>> _fetch() async {
    final cars = await Api.vehicles();
    try {
      _wear = _calcWear(await Api.parts(), cars);
    } catch (_) {
      _wear = {};
    }
    return cars;
  }

  Future<void> _reload() async {
    final f = _fetch();
    setState(() {
      _future = f;
    });
    try {
      await f;
    } catch (_) {}
  }
  bool _syncBusy = false;

  Future<void> _updateMileage(dynamic v) async {
    if (_syncBusy) return;
    _syncBusy = true;
    final r = await Api.autoSyncMileage(force: true); // список обновится сам
    _syncBusy = false;
    if (!mounted) return;
    String msg;
    if (r == null) {
      toast(context, 'Не удалось обновить пробег', error: true);
    } else if (r is Map &&
        (r['not_found'] as List?)?.contains(v['plate']) == true) {
      toast(context, 'Для этой машины нет данных о пробеге', error: true);
    } else {
      toast(context, 'Пробег обновлён');
    }
  }


  Future<void> _open(dynamic v) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VehicleDetailScreen(vehicle: v)),
    );
    if (mounted) _reload();
  }

  Future<void> _addVehicle() async {
    final ok = await showVehicleForm(context);
    if (ok == true) {
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Машина добавлена')));
      }
    }
  }
  /// Просрочено: документ истёк ИЛИ запчасть в красной зоне
  bool _isOverdue(dynamic v) {
    final docs = (_minDays(v) ?? 1) < 0;
    final parts = (_wear[_n(v['id'])]?.level ?? 0) == 2;
    return docs || parts;
  }

  /// Скоро: ничего не просрочено, но документ истекает скоро ИЛИ запчасть в жёлтой зоне
  bool _isSoon(dynamic v) {
    if (_isOverdue(v)) return false;
    final m = _minDays(v);
    final docs = m != null && m >= 0 && m <= kSoonDays;
    final parts = (_wear[_n(v['id'])]?.level ?? 0) == 1;
    return docs || parts;
  }
  /// Для сортировки: чем меньше, тем срочнее (документы и износ)
  int _urgency(dynamic v) {
    var d = _minDays(v) ?? 99999;
    final w = _wear[_n(v['id'])];
    if (w != null) {
      if (w.level == 2 && d > 0) d = 0;
      if (w.level == 1 && d > kSoonDays) d = kSoonDays;
    }
    return d;
  }
  /// Ближайший срок сверху; при равенстве — у кого больше красных запчастей, затем по номеру
  int _cmp(dynamic a, dynamic b) {
    final c = _urgency(a).compareTo(_urgency(b));
    if (c != 0) return c;
    final ra = _wear[_n(a['id'])]?.red ?? 0;
    final rb = _wear[_n(b['id'])]?.red ?? 0;
    if (ra != rb) return rb.compareTo(ra);
    return '${a['plate']}'.compareTo('${b['plate']}');
  }
  @override
  Widget build(BuildContext context) {
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
                const Text('УЧЕТ АВТОПАРКА',
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: _P.accent)),
                Text(Api.name ?? 'Машины',
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
          GestureDetector(
            onTap: _addVehicle,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: _P.accent,
                shape: BoxShape.circle,
              ),
              child:
              const Icon(Icons.add_rounded, color: _P.onAccent, size: 24),
            ),
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
            ..sort(_cmp);

          final top = <Widget>[
            Row(
              children: [
                _stat(Icons.directions_car_rounded, 'ВСЕГО', all.length,
                    'активных авто', _P.accent, _Filter.all),
                const SizedBox(width: 10),
                _stat(Icons.error_outline_rounded, 'ПРОСРОЧЕНО', overdue,
                    'документы и узлы', overdue > 0 ? _P.red : _P.muted,
                    _Filter.overdue),
                const SizedBox(width: 10),
                _stat(Icons.schedule_rounded, 'СКОРО', soon, 'до $kSoonDays дн.',
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
            else
              _label('ВСЕ АВТОМОБИЛИ · ${list.length}'),
          ];

          return RefreshIndicator(
            color: _P.accent,
            backgroundColor: _P.card,
            onRefresh: () async {
              final r = await Api.autoSyncMileage(force: true);
              await _reload();
              if (mounted && r is Map) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Пробег обновлён: ${r['updated'] ?? 0} авто')),
                );
              }
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: top.length + list.length,
              itemBuilder: (_, i) {
                if (i < top.length) return top[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _card(list[i - top.length]),
                );
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: c),
                    const SizedBox(width: 5),
                    Text(label,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w800,
                            color: _P.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('$n',
                  style: TextStyle(
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: c)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(caption,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, color: _P.muted)),
              ),
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

  // ───────── карточка машины ─────────

  Widget _card(dynamic v) {
    final m = _minDays(v);
    final w = _wear[_n(v['id'])];
    final wl = w?.level ?? 0;
    // требует внимания: горят документы или износ запчастей
    final attention = (m != null && m <= kSoonDays) || wl > 0;
    final ac = ((m != null && m <= kUrgentDays) || wl == 2) ? _P.red : _P.accent;
    final mark = attention ? ac : _P.green;

    return Material(
      color: _P.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: attention ? ac.withOpacity(0.45) : _P.line),
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
                    decoration:
                    BoxDecoration(color: mark, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(attention ? 'ТРЕБУЕТ ВНИМАНИЯ' : 'В НОРМЕ',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: mark)),
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
                            if (v['mileage_synced_at'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('Обновлено: ${_ago(v['mileage_synced_at'])}',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: _P.muted)),
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
                  if (w != null && w.total > 0) _wearBox(w),
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

  /// Блок износа: одной строкой — в норме / скоро / пора менять
  Widget _wearBox(_Wear? w) {
    final has = w != null && w.total > 0;
    final lv = w?.level ?? 0;
    final c = !has
        ? _P.muted
        : (lv == 2 ? _P.red : (lv == 1 ? _P.accent : _P.green));
    final tag = !has
        ? 'НЕТ ДАННЫХ'
        : (lv == 2 ? 'ПОРА МЕНЯТЬ' : (lv == 1 ? 'СКОРО' : 'В НОРМЕ'));
    String sub;
    if (!has) {
      sub = 'Запчасти не установлены';
    } else if (lv == 0) {
      sub = 'Все узлы в порядке';
    } else {
      final parts = <String>[
        if (w.red > 0) 'К замене: ${w.red}',
        if (w.yellow > 0) 'Скоро: ${w.yellow}',
      ];
      sub = parts.join(' · ');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.build_outlined, color: c, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Износ запчастей',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _P.text)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(fontSize: 12.5, color: _P.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(tag,
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w800,
                  color: c)),
        ],
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