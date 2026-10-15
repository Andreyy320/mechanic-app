import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'mileage_sheet.dart';
import '../services/api.dart';
import 'ui.dart' show daysOf, fmtKm, fmtDate;

class _P {
  static const bg = Color(0xFFF6F7FA);
  static const card = Color(0xFFFFFFFF);
  static const card2 = Color(0xFFF1F3F7);
  static const line = Color(0xFFE5E7EB);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const accent = Color(0xFFE08A00);
  static const onAccent = Color(0xFFFFFFFF);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
}

class _Node {
  final int typeId;
  final String title;
  final String category;
  final IconData icon;
  final int intervalKm;
  final int? lastKm; // null = замену ещё не фиксировали
  _Node(this.typeId, this.title, this.category, this.icon, this.intervalKm,
      this.lastKm);

  int? left(int mileage) =>
      lastKm == null ? null : intervalKm - (mileage - lastKm!);
  double? value(int mileage) {
    final l = left(mileage);
    return l == null ? null : (l / intervalKm).clamp(0.0, 1.0).toDouble();
  }
}

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('масл')) return Icons.oil_barrel_outlined;
  if (n.contains('колодк') || n.contains('диск')) return Icons.album_outlined;
  if (n.contains('свеч')) return Icons.bolt_rounded;
  if (n.contains('жидк')) return Icons.water_drop_outlined;
  return Icons.settings_outlined;
}

Color _rc(double v) => v > 0.5 ? _P.green : (v > 0.2 ? _P.accent : _P.red);

String _status(double v) {
  if (v <= 0.2) return 'ТРЕБУЕТ ЗАМЕНЫ';
  if (v <= 0.5) return 'СКОРО ЗАМЕНА';
  return 'В НОРМЕ';
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

class VehicleDetailScreen extends StatefulWidget {
  final dynamic vehicle;
  const VehicleDetailScreen({super.key, required this.vehicle});
  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  late final Map<String, dynamic> _v = Map<String, dynamic>.from(widget.vehicle);
  List<_Node> _nodes = [];
  bool _loading = true;
  String? _err;
  String _cat = 'Все';
  _Node? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final res = await Future.wait([Api.partTypes(), Api.parts()]);
      final types = res[0];
      final mine = res[1].where((p) => p['vehicle_id'] == _v['id']).toList();

      final nodes = <_Node>[];
      for (final t in types) {
        if (t['track'] == false || t['track'] == 0) continue;
        final inst = mine.where((p) => p['part_type_id'] == t['id']).toList()
          ..sort((a, b) => ((b['mileage_at'] as num?) ?? 0)
              .compareTo((a['mileage_at'] as num?) ?? 0));
        nodes.add(_Node(
          t['id'],
          '${t['name']}',
          '${t['category'] ?? 'Узлы'}',
          _iconFor('${t['name']}'),
          (t['norm_km'] as num).round(),
          inst.isEmpty ? null : (inst.first['mileage_at'] as num).round(),
        ));
      }
      if (mounted) setState(() => _nodes = nodes);
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (_) {
      if (mounted) setState(() => _err = 'Нет связи с сервером');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _mileage => ((_v['mileage'] as num?) ?? 0).round();

  Future<void> _updateMileage() async {
    final km = await showMileageSheet(context, _v);
    if (km != null) setState(() => _v['mileage'] = km);
  }

  List<String> get _cats {
    final s = <String>[];
    for (final n in _nodes) {
      if (!s.contains(n.category)) s.add(n.category);
    }
    return ['Все', ...s];
  }

  int _count(String c) =>
      c == 'Все' ? _nodes.length : _nodes.where((n) => n.category == c).length;

  Future<void> _reset() async {
    if (_nodes.isEmpty) return;
    final m = _mileage;
    final sorted = [..._nodes]
      ..sort((a, b) => (a.value(m) ?? 2).compareTo(b.value(m) ?? 2));
    final node = _selected ?? sorted.first;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('ЗАФИКСИРОВАТЬ ЗАМЕНУ',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: _P.accent)),
            const SizedBox(height: 8),
            Text(node.title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _P.text)),
            const SizedBox(height: 6),
            Text(
                'Ресурс будет сброшен до 100% на пробеге ${fmtKm(m)} км.',
                style: const TextStyle(fontSize: 14, color: _P.muted)),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _P.accent,
                  foregroundColor: _P.onAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('ПОДТВЕРДИТЬ',
                    style: TextStyle(
                        fontSize: 14,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
              const Text('Отмена', style: TextStyle(color: _P.muted)),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        await Api.addPart(
          vehicleId: _v['id'],
          partTypeId: node.typeId,
          installedAt: DateTime.now().toIso8601String().substring(0, 10),
          mileageAt: m,
        );
        _selected = null;
        await _load();
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Нет связи с сервером')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final m = _mileage;
    final list = _nodes
        .where((n) => _cat == 'Все' || n.category == _cat)
        .toList()
      ..sort((a, b) => (a.value(m) ?? 2).compareTo(b.value(m) ?? 2));

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
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: _P.text),
            ),
            child: Text('${v['plate']}',
                style: const TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                    color: _P.text)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                child: CircularProgressIndicator(color: _P.accent))
                : _err != null
                ? Center(
                child: TextButton(
                    onPressed: _load,
                    child: Text('$_err · Повторить')))
                : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                _summary(m),
                const SizedBox(height: 12),
                _docs(v),
                const SizedBox(height: 16),
                _filters(),
                const SizedBox(height: 14),
                for (final n in list) ...[
                  _nodeCard(n, m),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      size: 22),
                  label: const Text('ЗАФИКСИРОВАТЬ ЗАМЕНУ / СБРОС'),
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
          ),
        ],
      ),
    );
  }

  // ───────── верхняя карточка: кольцо + пробег ─────────

  Widget _summary(int m) {
    final known = _nodes.where((n) => n.value(m) != null).toList();
    final avg = known.isEmpty
        ? 0.0
        : known.map((n) => n.value(m)!).reduce((a, b) => a + b) /
        known.length;
    final critical = known.where((n) => n.value(m)! <= 0.2).length;
    final c = _rc(avg);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _P.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: CircularProgressIndicator(
                        value: avg,
                        strokeWidth: 8,
                        backgroundColor: c.withOpacity(0.16),
                        valueColor: AlwaysStoppedAnimation(c),
                      ),
                    ),
                    Text('${(avg * 100).round()}%',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: c)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ресурс узлов',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _P.text)),
                    const SizedBox(height: 3),
                    Text('Агрегат по ${known.length} узлам',
                        style:
                        const TextStyle(fontSize: 12.5, color: _P.muted)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (critical > 0 ? _P.red : _P.green)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        critical > 0
                            ? '$critical ИЗ ${known.length} ТРЕБУЮТ ВНИМАНИЯ'
                            : 'ВСЁ В НОРМЕ',
                        style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w800,
                            color: critical > 0 ? _P.red : _P.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                      Text('${fmtKm(m)} км',
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: _P.text)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _updateMileage,
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
    );
  }

  // ───────── страховка / техосмотр (компактно) ─────────

  Widget _docs(Map<String, dynamic> v) {
    return Row(
      children: [
        Expanded(
            child: _docTile(Icons.shield_outlined, 'Страховка',
                v['insurance_to'], daysOf(v['insurance_days']))),
        const SizedBox(width: 10),
        Expanded(
            child: _docTile(Icons.fact_check_outlined, 'Техосмотр',
                v['inspection_to'], daysOf(v['inspection_days']))),
      ],
    );
  }

  Widget _docTile(IconData icon, String label, dynamic to, int? days) {
    final c = _dc(days);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _P.text)),
                const SizedBox(height: 2),
                Text(to == null ? 'Нет данных' : 'до ${fmtDate(to)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: _P.muted)),
              ],
            ),
          ),
          Text(_dshort(days),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }

  // ───────── фильтры ─────────

  Widget _filters() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _cats[i];
          final sel = c == _cat;
          return GestureDetector(
            onTap: () => setState(() => _cat = c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? _P.accent : _P.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? _P.accent : _P.line),
              ),
              child: Text(
                c == 'Все' ? 'Все узлы (${_count(c)})' : '$c (${_count(c)})',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: sel ? _P.onAccent : _P.text),
              ),
            ),
          );
        },
      ),
    );
  }

  // ───────── карточка узла ─────────

  Widget _nodeCard(_Node n, int m) {
    final left = n.left(m);
    final value = n.value(m) ?? 0.0;
    final c = left == null ? _P.muted : _rc(value);
    final critical = left != null && value <= 0.2;
    final sel = identical(_selected, n);

    return Material(
      color: _P.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: sel
                ? _P.accent
                : (critical ? c.withOpacity(0.45) : _P.line),
            width: sel ? 1.6 : 1),
      ),
      child: InkWell(
        onTap: () => setState(() => _selected = sel ? null : n),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(n.icon, color: c, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: _P.text)),
                  ),
                  const SizedBox(width: 8),
                  Text(left == null ? '—' : '${(value * 100).round()}%',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: c)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: c.withOpacity(0.16),
                  valueColor: AlwaysStoppedAnimation(c),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      left == null
                          ? 'Замена не фиксировалась'
                          : left >= 0
                          ? 'Осталось ${fmtKm(left)} км из ${fmtKm(n.intervalKm)}'
                          : 'Перепробег ${fmtKm(-left)} км · интервал ${fmtKm(n.intervalKm)}',
                      style: const TextStyle(fontSize: 12, color: _P.muted),
                    ),
                  ),
                  Text(left == null ? 'НЕТ ДАННЫХ' : _status(value),
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w800,
                          color: c)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}