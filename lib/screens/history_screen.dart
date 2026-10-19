import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import 'ui.dart' show fmtKm, fmtDate;

class _P {
  static const bg = Color(0xFFF6F7FA);
  static const card = Color(0xFFFFFFFF);
  static const card2 = Color(0xFFF1F3F7);
  static const line = Color(0xFFE5E7EB);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const accent = Color(0xFFE08A00);
  static const green = Color(0xFF16A34A);
  static const blue = Color(0xFF475569);
}

int _n(dynamic v) => v is num ? v.round() : (num.tryParse('$v')?.round() ?? 0);

OutlineInputBorder _b(Color c, [double w = 1]) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(14),
  borderSide: BorderSide(color: c, width: w),
);

Widget _plate(String p, {double fs = 12.5}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(7),
    border: Border.all(color: _P.text),
  ),
  child: Text(p,
      style: TextStyle(
          fontSize: fs,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
          color: _P.text)),
);

// ───────────────────────── список машин ─────────────────────────

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _cars = [];
  bool _loading = true;
  String? _err;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _err = null; });
    try {
      _cars = await Api.vehicles();
      _err = null;
    } on ApiException catch (e) {
      _err = e.message;
    } catch (_) {
      _err = 'Нет связи с сервером';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        backgroundColor: _P.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _P.text,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text('История авто',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: _P.text)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _P.accent));
    }
    if (_err != null) {
      return Center(
          child: TextButton(onPressed: _load, child: Text('$_err · Повторить')));
    }
    final q = _query.trim().toLowerCase();
    final list = _cars
        .where((v) =>
    q.isEmpty ||
        '${v['plate']} ${v['model']}'.toLowerCase().contains(q))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            cursorColor: _P.accent,
            style: const TextStyle(color: _P.text),
            decoration: InputDecoration(
              hintText: 'Поиск по номеру или модели',
              hintStyle: const TextStyle(color: _P.muted),
              prefixIcon: const Icon(Icons.search_rounded, color: _P.muted),
              filled: true,
              fillColor: _P.card,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: _b(_P.line),
              enabledBorder: _b(_P.line),
              focusedBorder: _b(_P.accent, 1.4),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: _P.accent,
            onRefresh: () => _load(silent: true),
            child: list.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text(
                        _cars.isEmpty
                            ? 'Машин пока нет'
                            : 'Ничего не найдено',
                        style: const TextStyle(
                            color: _P.muted, fontSize: 15)),
                  ),
                ),
              ],
            )
                : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _carTile(list[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _carTile(dynamic v) {
    return Material(
      color: _P.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _P.line),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VehicleHistoryScreen(vehicle: v))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _P.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
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
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: _P.text)),
                    const SizedBox(height: 2),
                    Text('${fmtKm(v['mileage'])} км',
                        style:
                        const TextStyle(fontSize: 12.5, color: _P.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _plate('${v['plate']}'),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: _P.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────── история одной машины ─────────────────────

enum _Kind { part, inspection, insurance, other }

class _Ev {
  final _Kind kind;
  final String date; // YYYY-MM-DD
  final String title, sub;
  final int? typeId; // для запчастей: id типа запчасти
  _Ev(this.kind, this.date, this.title, this.sub, {this.typeId});
}

const _months = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
];

String _monthOf(String d) {
  final p = d.split('-');
  if (p.length != 3) return 'Без даты';
  final m = int.tryParse(p[1]) ?? 0;
  if (m < 1 || m > 12) return 'Без даты';
  return '${_months[m - 1]} ${p[0]}';
}

Color _color(_Kind k) {
  switch (k) {
    case _Kind.part:
      return _P.accent;
    case _Kind.inspection:
      return _P.green;
    case _Kind.insurance:
      return _P.blue;
    case _Kind.other:
      return _P.muted;
  }
}

IconData _icon(_Kind k) {
  switch (k) {
    case _Kind.part:
      return Icons.build_rounded;
    case _Kind.inspection:
      return Icons.fact_check_outlined;
    case _Kind.insurance:
      return Icons.shield_outlined;
    case _Kind.other:
      return Icons.description_outlined;
  }
}

class VehicleHistoryScreen extends StatefulWidget {
  final dynamic vehicle;
  const VehicleHistoryScreen({super.key, required this.vehicle});
  @override
  State<VehicleHistoryScreen> createState() => _VehicleHistoryScreenState();
}

class _VehicleHistoryScreenState extends State<VehicleHistoryScreen> {
  List<_Ev> _all = [];
  bool _loading = true;
  List<dynamic> _parts = []; // установки запчастей этой машины
  String? _err;
  _Kind? _filter; // null — все

  int get _id => _n(widget.vehicle['id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _err = null; });
    try {
      final res = await Future.wait([Api.parts(), Api.vehicleDocuments(_id)]);
      final ev = <_Ev>[];
      _parts = res[0].where((p) => _n(p['vehicle_id']) == _id).toList();

      // по каждой запчасти оставляем только последнюю установку
      final latest = <int, dynamic>{};
      final count = <int, int>{};
      for (final p in _parts) {
        final tid = _n(p['part_type_id']);
        count[tid] = (count[tid] ?? 0) + 1;
        final cur = latest[tid];
        if (cur == null) {
          latest[tid] = p;
          continue;
        }
        final c = '${p['installed_at']}'.compareTo('${cur['installed_at']}');
        if (c > 0 || (c == 0 && _n(p['id']) > _n(cur['id']))) latest[tid] = p;
      }
      for (final p in latest.values) {
        final tid = _n(p['part_type_id']);
        final n = count[tid] ?? 1;
        ev.add(_Ev(
          _Kind.part,
          '${p['installed_at']}',
          '${p['part_name']}',
          'Пробег при установке: ${fmtKm(p['mileage_at'])} км'
              '${n > 1 ? ' · замен: $n' : ''}',
          typeId: tid,
        ));
      }
      for (final d in res[1]) {
        final t = '${d['doc_type']}';
        final kind = t == 'insurance'
            ? _Kind.insurance
            : (t == 'inspection' ? _Kind.inspection : _Kind.other);
        final from = d['date_from'];
        final created = '${d['created_at'] ?? ''}';
        final date = (from != null && '$from'.isNotEmpty)
            ? '$from'
            : (created.length >= 10 ? created.substring(0, 10) : '');
        final title = kind == _Kind.insurance
            ? 'Страховка'
            : (kind == _Kind.inspection
            ? 'Техосмотр'
            : ((d['title'] ?? 'Документ') as Object).toString());
        final sub = (from != null && '$from'.isNotEmpty)
            ? 'с ${fmtDate(from)} по ${fmtDate(d['date_to'])}'
            : 'до ${fmtDate(d['date_to'])}';
        ev.add(_Ev(kind, date, title, sub));
      }
      ev.sort((a, b) => b.date.compareTo(a.date));
      _all = ev;
      _err = null;
    } on ApiException catch (e) {
      _err = e.message;
    } catch (_) {
      _err = 'Нет связи с сервером';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        backgroundColor: _P.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _P.text,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleSpacing: 0,
        title: Text('${v['model']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
        actions: [
          Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _plate('${v['plate']}', fs: 13),
              )),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _P.accent));
    }
    if (_err != null) {
      return Center(
          child: TextButton(onPressed: _load, child: Text('$_err · Повторить')));
    }

    int cnt(_Kind k) => _all.where((e) => e.kind == k).length;
    final list =
    _all.where((e) => _filter == null || e.kind == _filter).toList();

    final rows = <Object>[];
    String? last;
    for (final e in list) {
      final m = _monthOf(e.date);
      if (m != last) {
        rows.add(m);
        last = m;
      }
      rows.add(e);
    }

    return Column(
      children: [
        SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _chip('Все', _all.length, null, _P.text),
                _chip('Запчасти', cnt(_Kind.part), _Kind.part, _P.accent),
                _chip('ТО', cnt(_Kind.inspection), _Kind.inspection,
                    _P.green),
                _chip('Страховка', cnt(_Kind.insurance), _Kind.insurance,
                    _P.blue),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: RefreshIndicator(
            color: _P.accent,
            onRefresh: () => _load(silent: true),
            child: rows.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                      child: Text('Записей пока нет',
                          style: TextStyle(
                              color: _P.muted, fontSize: 15))),
                ),
              ],
            )
                : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                if (r is String) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
                    child: Text(r.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: _P.muted)),
                  );
                }
                return _card(r as _Ev);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, int n, _Kind? k, Color c) {
    final sel = _filter == k;
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: k == _Kind.insurance ? 0 : 8),
        child: GestureDetector(
          onTap: () => setState(() => _filter = k),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? c.withOpacity(0.1) : _P.card,
              borderRadius: BorderRadius.circular(12),
              border:
              Border.all(color: sel ? c : _P.line, width: sel ? 1.5 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$n',
                    style: TextStyle(
                        fontSize: 18,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: sel ? c : _P.text)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _P.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(_Ev e) {
    final c = _color(e.kind);
    final tappable = e.kind == _Kind.part;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _P.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _P.line),
        ),
        child: InkWell(
          onTap: tappable ? () => _showPart(e) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon(e.kind), color: c, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _P.text)),
                      const SizedBox(height: 3),
                      Text(e.sub,
                          style: const TextStyle(
                              fontSize: 12.5, color: _P.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fmtDate(e.date),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c)),
                    if (tappable) ...[
                      const SizedBox(height: 4),
                      const Text('ИСТОРИЯ ›',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w800,
                              color: _P.accent)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// История одной запчасти на этой машине: все замены и сколько каждая прослужила
  void _showPart(_Ev e) {
    final list = _parts.where((p) => _n(p['part_type_id']) == e.typeId).toList()
      ..sort((a, b) {
        var c = '${b['installed_at']}'.compareTo('${a['installed_at']}');
        if (c == 0) c = _n(b['mileage_at']).compareTo(_n(a['mileage_at']));
        return c != 0 ? c : _n(b['id']).compareTo(_n(a['id']));
      });
    if (list.isEmpty) return;
    final cur = _n(widget.vehicle['mileage']);
    final norm = _n(list.first['norm_km']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints:
        BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(e.title,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _P.text)),
                const SizedBox(height: 4),
                Text(
                    'Замен: ${list.length}'
                        '${norm > 0 ? ' · норматив ${fmtKm(norm)} км' : ''}',
                    style: const TextStyle(fontSize: 13, color: _P.muted)),
                const SizedBox(height: 14),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _P.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _P.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, thickness: 1, color: _P.line),
                      itemBuilder: (_, i) {
                        final p = list[i];
                        final at = _n(p['mileage_at']);
                        final isCurrent = i == 0;
                        final end = isCurrent ? cur : _n(list[i - 1]['mileage_at']);
                        final used = end - at;
                        final ok = used >= 0;
                        final over = isCurrent && norm > 0 && used > norm;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(fmtDate(p['installed_at']),
                                        style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w800,
                                            color: _P.text)),
                                    const SizedBox(height: 2),
                                    Text('на ${fmtKm(at)} км',
                                        style: const TextStyle(
                                            fontSize: 12.5, color: _P.muted)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(ok ? '${fmtKm(used)} км' : '—',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: over
                                              ? const Color(0xFFDC2626)
                                              : _P.text)),
                                  const SizedBox(height: 3),
                                  if (isCurrent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _P.card2,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('СЕЙЧАС',
                                          style: TextStyle(
                                              fontSize: 9.5,
                                              letterSpacing: 0.6,
                                              fontWeight: FontWeight.w800,
                                              color: _P.text)),
                                    )
                                  else
                                    const Text('ПРОСЛУЖИЛА',
                                        style: TextStyle(
                                            fontSize: 9.5,
                                            letterSpacing: 0.6,
                                            fontWeight: FontWeight.w800,
                                            color: _P.muted)),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}