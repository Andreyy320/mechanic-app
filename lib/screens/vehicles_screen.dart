import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mechanic_app/screens/vehicleDetail_screen.dart';
import '../services/api.dart';
import 'vehicle_form_sheet.dart';
import 'ui.dart' show daysOf, fmtKm, fmtDate, toast, kSoonDays, kUrgentDays, PlateBadge, unitOf, C, AppTheme,kResetTol;

class _P {
  static Color get bg => C.bg;
  static Color get card => C.card;
  static Color get card2 => C.card2;
  static Color get line => C.line;
  static Color get text => C.text;
  static Color get muted => C.muted;
  static const accent = Color(0xFFE08A00);
  static const onAccent = Color(0xFFFFFFFF);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
}

enum _Filter { all, overdue, soon }

// ───────── износ запчастей по машине ─────────

class _Wear {
  final int total, red, yellow, reset; // reset: узлы со сброшенным пробегом (они входят и в red)
  final double avg; // средний остаток ресурса узлов, 0..1
  const _Wear(this.total, this.red, this.yellow, this.reset, this.avg);
  /// 0 — в норме, 1 — скоро замена, 2 — пора менять
  int get level => red > 0 ? 2 : (yellow > 0 ? 1 : 0);
}

int _n(dynamic v) =>
    v is num ? v.round() : (num.tryParse('$v')?.round() ?? 0);

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
  final total = <int, int>{}, red = <int, int>{}, yellow = <int, int>{}, resetN = <int, int>{};
  final sum = <int, double>{};
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
    final reset = _n(p['mileage_at']) - (mileage[vid] ?? 0) > kResetTol;
    int lvl;
    if (reset) {
      lvl = 2;
    } else if (w1 == 0 && w2 == 0) {
      final v = left / norm;
      lvl = v <= 0.2 ? 2 : (v <= 0.5 ? 1 : 0);
    } else {
      lvl = left <= w2 ? 2 : (left <= w1 ? 1 : 0);
    }

    total[vid] = (total[vid] ?? 0) + 1;
    sum[vid] = (sum[vid] ?? 0) + (reset ? 0.0 : (left / norm).clamp(0.0, 1.0).toDouble());
    if (lvl == 2) {
      red[vid] = (red[vid] ?? 0) + 1;
      if (reset) resetN[vid] = (resetN[vid] ?? 0) + 1;
    } else if (lvl == 1) {
      yellow[vid] = (yellow[vid] ?? 0) + 1;
    }
  }
  return {
    for (final id in total.keys)
      id: _Wear(total[id]!, red[id] ?? 0, yellow[id] ?? 0, resetN[id] ?? 0,
          sum[id]! / total[id]!)
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
  if (d < 0) return '${-d} дн.';
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
    final m = _minDays(v);
    final docs = m != null && m <= kUrgentDays;
    final parts = (_wear[_n(v['id'])]?.level ?? 0) == 2;
    return docs || parts;
  }

  /// Скоро: ничего не просрочено, но документ истекает скоро ИЛИ запчасть в жёлтой зоне
  bool _isSoon(dynamic v) {
    if (_isOverdue(v)) return false;
    final m = _minDays(v);
    final docs = m != null && m > kUrgentDays && m <= kSoonDays;
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
        systemOverlayStyle: AppTheme.dark.value
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
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
              child: Icon(
Icons.directions_car_rounded,
                  color: _P.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Text(Api.name ?? 'Машины',
                style: TextStyle(

                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: _P.text)),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _addVehicle,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _P.accent,
                shape: BoxShape.circle,
              ),
              child:
              Icon(
Icons.add_rounded, color: _P.onAccent, size: 24),
            ),
          ),

        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return Center(

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
                    style: TextStyle(
color: _P.muted, fontSize: 15),
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
                        style: TextStyle(

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
                    style: TextStyle(
fontSize: 11, color: _P.muted)),
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
      style: TextStyle(
color: _P.text),
      cursorColor: _P.accent,
      decoration: InputDecoration(
        hintText: 'Поиск по номеру или модели',
        hintStyle: TextStyle(
color: _P.muted),
        prefixIcon: Icon(
Icons.search_rounded, color: _P.muted),
        filled: true,
        fillColor: _P.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: b(_P.line),
        enabledBorder: b(_P.line),
        focusedBorder: b(_P.accent, 1.4),
      ),
    );
  }

  Widget _label(String t, {Color? color}) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(t,
        style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: color ?? _P.muted)),
  );

  // ───────── карточка машины ─────────

  Widget _card(dynamic v) {
    final m = _minDays(v);
    final w = _wear[_n(v['id'])];
    final wl = w?.level ?? 0;
    final insD = daysOf(v['insurance_days']);
    final inspD = daysOf(v['inspection_days']);
    final attention = (m != null && m <= kSoonDays) || wl > 0;
    final urgent = (m != null && m <= kUrgentDays) || wl == 2;
    final ac = urgent ? _P.red : _P.accent;
    final mark = attention ? ac : _P.green;
    final color = '${v['color'] ?? ''}'.trim();
    final hasWear = w != null && w.total > 0;
    // кольцо и подпись под ним — только по узлам (как в карточке машины)
    final ringC = !hasWear
        ? _P.muted
        : (wl == 2 ? _P.red : (wl == 1 ? _P.accent : _P.green));
    final ringWord = !hasWear
        ? ''
        : (wl == 2 ? 'ЗАМЕНА' : (wl == 1 ? 'СКОРО' : 'В НОРМЕ'));
    String docAlert(String name, String expired, int? d) {
      if (d == null || d > kSoonDays) return '';
      if (d < 0) return '$name $expired на ${-d} дн.';
      if (d == 0) return '$name истекает сегодня';
      return '$name: осталось $d дн.';
    }

    final alerts = <String>[
      docAlert('Страховка', 'просрочена', insD),
      docAlert('Техосмотр', 'просрочен', inspD),
      if (w != null && w.reset > 0) 'Пробег сбросился, введите установки: ${w.reset}',
      if (w != null && w.red - w.reset > 0) 'К замене узлов: ${w.red - w.reset}',
      if (w != null && w.yellow > 0) 'Скоро замена узлов: ${w.yellow}',
    ].where((s) => s.isNotEmpty).toList();

    return Material(
      color: _P.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: attention ? ac.withOpacity(0.45) : _P.line),
      ),
      child: InkWell(
        onTap: () => _open(v),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // слева: статус, модель, цвет и номер; справа по центру: кольцо
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                  color: mark, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 7),
                            Text(attention ? 'ТРЕБУЕТ ВНИМАНИЯ' : 'В НОРМЕ',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 1.0,
                                    fontWeight: FontWeight.w800,
                                    color: mark)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('${v['model']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(

                                fontSize: 24,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                color: _P.text)),
                        if (color.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(color,
                              style: TextStyle(

                                  fontSize: 13, color: _P.muted)),
                        ],
                        const SizedBox(height: 16),
                        PlateBadge('${v['plate']}', fs: 24),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 76,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: CircularProgressIndicator(
                                    value: hasWear ? w.avg : 0.0,
                                    strokeWidth: 6,
                                    backgroundColor: ringC.withOpacity(0.16),
                                    valueColor: AlwaysStoppedAnimation(ringC),
                                  ),
                                ),
                                hasWear
                                    ? Text('${(w.avg * 100).round()}%',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: ringC))
                                    : Text('нет\nузлов',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        height: 1.2,
                                        fontWeight: FontWeight.w700,
                                        color: ringC)),
                              ],
                            ),
                          ),
                          if (ringWord.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(ringWord,
                                  maxLines: 1,
                                  style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 0.4,
                                      fontWeight: FontWeight.w800,
                                      color: ringC)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // красная плашка с причиной
              if (alerts.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ac.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ac.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: ac, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(alerts.join('\n'),
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                color: ac)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              // пробег, страховка, техосмотр
              // пробег, страховка, техосмотр: одна полоса с тонкими линиями
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: _P.line),
                  ),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _miniStat(
                        Icons.speed_rounded,
                        'ПРОБЕГ',
                        '${fmtKm(v['mileage'])} ${unitOf(v)}',
                        _P.text,
                        v['mileage_synced_at'] != null
                            ? _ago(v['mileage_synced_at'])
                            : null,
                      ),
                      Container(
                          width: 1,
                          color: _P.line,
                          margin: const EdgeInsets.symmetric(horizontal: 10)),
                      _miniStat(
                        Icons.shield_outlined,
                        'СТРАХОВКА',
                        _short(insD),
                        _sc(insD),
                        v['insurance_to'] == null
                            ? 'нет данных'
                            : 'до ${fmtDate(v['insurance_to'])}',
                      ),
                      Container(
                          width: 1,
                          color: _P.line,
                          margin: const EdgeInsets.symmetric(horizontal: 10)),
                      _miniStat(
                        Icons.fact_check_outlined,
                        'ТЕХОСМОТР',
                        _short(inspD),
                        _sc(inspD),
                        v['inspection_to'] == null
                            ? 'нет данных'
                            : 'до ${fmtDate(v['inspection_to'])}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // кнопки
              // кнопка: на всю ширину (карточка целиком открывает машину)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _updateMileage(v),
                  icon: Icon(
Icons.sync_rounded, size: 18),
                  label: Text(
'ОБНОВИТЬ ПРОБЕГ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _P.accent,
                    foregroundColor: _P.onAccent,
                    textStyle: TextStyle(

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
      ),
    );
  }

  /// Маленький блок: иконка + подпись, значение, мелкая строка под ним
  Widget _miniStat(
      IconData icon, String label, String value, Color c, String? sub) {
    return Expanded(
      child: Container(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: _P.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(label,
                        maxLines: 1,
                        style: TextStyle(

                            fontSize: 9.5,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w800,
                            color: _P.muted)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c)),
            ),
            if (sub != null) ...[
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(sub,
                    maxLines: 1,
                    style: TextStyle(
fontSize: 10.5, color: _P.muted)),
              ),
            ],
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
                        style: TextStyle(

                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _P.text)),
                    const SizedBox(height: 2),
                    Text(
                      to == null ? 'Нет данных' : 'до ${fmtDate(to)}',
                      style: TextStyle(
fontSize: 12.5, color: _P.muted),
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
                Text(
'Износ запчастей',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _P.text)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
fontSize: 12.5, color: _P.muted)),
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
            Icon(
Icons.cloud_off_rounded, size: 44, color: _P.muted),
            const SizedBox(height: 14),
            Text(
'Не удалось загрузить список',
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
              child: Text(
'Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}