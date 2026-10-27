import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mechanic_app/screens/vehicle_form_sheet.dart';
import 'date_input.dart';
import 'doc_renew_sheet.dart';
import '../services/api.dart';
import 'ui.dart' show daysOf, fmtKm, fmtDate, toast, kSoonDays, kUrgentDays, PlateBadge, unitOf, showPartActions, deletePartFlow, C, AppTheme;

class _P {
  static Color get bg => C.bg;
  static Color get card => C.card;
  static Color get card2 => C.card2;
  static Color get line => C.line;
  static Color get text => C.text;
  static Color get muted => C.muted;
  static Color get ink => C.text; // в тёмной теме светлый
  static const accent = Color(0xFFE08A00);
  static const onAccent = Color(0xFFFFFFFF);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
}

/// Узел, который реально установлен на машине (по записям из /parts).
class _Node {
  final int typeId;
  final String title;
  final IconData icon;
  final int normKm; // норматив замены
  final int warn1; // жёлтый порог (осталось км)
  final int warn2; // красный порог (осталось км)
  final int lastKm; // пробег машины при последней установке
  final String installedAt; // YYYY-MM-DD
  _Node(this.typeId, this.title, this.icon, this.normKm, this.warn1,
      this.warn2, this.lastKm, this.installedAt);

  bool reset(int mileage) => mileage < lastKm; // пробег сбросился

  int left(int mileage) => normKm - max(mileage - lastKm, 0);

  double value(int mileage) => reset(mileage)
      ? 0.0
      : (left(mileage) / normKm).clamp(0.0, 1.0).toDouble();
  /// 0 — в норме, 1 — скоро замена, 2 — требует замены.
  /// Пороги те же, что на сайте и в «Требует внимания».
  int level(int mileage) {
    if (reset(mileage)) return 2;
    final l = left(mileage);
    final w1 = max(warn1, warn2);
    if (w1 == 0 && warn2 == 0) {
      // пороги не заданы — считаем по процентам
      final v = value(mileage);
      return v <= 0.2 ? 2 : (v <= 0.5 ? 1 : 0);
    }
    if (l <= warn2) return 2;
    if (l <= w1) return 1;
    return 0;
  }
}

bool _truthy(dynamic v) => v == true || v == 1 || v == 'true';
int _int(dynamic v) => ((v as num?) ?? 0).round();

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('масл')) return Icons.oil_barrel_outlined;
  if (n.contains('колодк') || n.contains('диск')) return Icons.album_outlined;
  if (n.contains('свеч')) return Icons.bolt_rounded;
  if (n.contains('жидк')) return Icons.water_drop_outlined;
  if (n.contains('фильтр')) return Icons.filter_alt_outlined;
  return Icons.settings_outlined;
}

Color _lc(int level) =>
    level == 2 ? _P.red : (level == 1 ? _P.accent : _P.green);

String _status(int level) =>
    level == 2 ? 'ТРЕБУЕТ ЗАМЕНЫ' : (level == 1 ? 'СКОРО ЗАМЕНА' : 'В НОРМЕ');

Color _dc(int? d) {
  if (d == null) return _P.muted;
  if (d <= kUrgentDays) return _P.red;
  if (d <= kSoonDays) return _P.accent;
  return _P.green;
}

String _dshort(int? d) {
  if (d == null) return '—';
  if (d < 0) return '${-d} дн.';
  if (d == 0) return 'сегодня';
  return '$d дн.';
}

String _two(int x) => x.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _ru(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

/// «15.03.2026» -> DateTime, либо null, если дата неполная или несуществующая
DateTime? _parseRu(String s) {
  final p = s.trim().split('.');
  if (p.length != 3 || p[2].length != 4) return null;
  final d = int.tryParse(p[0]), m = int.tryParse(p[1]), y = int.tryParse(p[2]);
  if (d == null || m == null || y == null) return null;
  final r = DateTime(y, m, d);
  if (r.year != y || r.month != m || r.day != d) return null;
  return r;
}


class VehicleDetailScreen extends StatefulWidget {
  final dynamic vehicle;
  const VehicleDetailScreen({super.key, required this.vehicle});
  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  late final Map<String, dynamic> _v = Map<String, dynamic>.from(widget.vehicle);
  List<_Node> _nodes = []; // только установленное на этой машине
  List<dynamic> _types = []; // справочник запчастей (для новой установки)
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
    Api.docsChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    Api.docsChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _refresh();
  }

  /// Тихо подтягивает свежие данные машины и узлов (без крутилки).
  Future<void> _refresh() async {
    try {
      final all = await Api.vehicles();
      final fresh =
      all.firstWhere((x) => x['id'] == _v['id'], orElse: () => null);
      if (fresh != null && mounted) {
        setState(() => _v.addAll(Map<String, dynamic>.from(fresh)));
      }
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _err = null;
      });
    }
    try {
      final res = await Future.wait([Api.partTypes(), Api.parts()]);
      final types = res[0];
      final mine = res[1].where((p) => p['vehicle_id'] == _v['id']);

      // по каждой запчасти берём последнюю установку на этой машине
      final latest = <int, dynamic>{};
      for (final p in mine) {
        final tid = _int(p['part_type_id']);
        final cur = latest[tid];
        if (cur == null) {
          latest[tid] = p;
          continue;
        }
        final c = '${p['installed_at']}'.compareTo('${cur['installed_at']}');
        if (c > 0 || (c == 0 && _int(p['id']) > _int(cur['id']))) {
          latest[tid] = p;
        }
      }

      final nodes = <_Node>[];
      for (final p in latest.values) {
        final norm = _int(p['norm_km']);
        if (norm <= 0) continue; // без норматива ресурс не посчитать
        nodes.add(_Node(
          _int(p['part_type_id']),
          '${p['part_name']}',
          _iconFor('${p['part_name']}'),
          norm,
          _int(p['warn1_km']),
          _int(p['warn2_km']),
          _int(p['mileage_at']),
          '${p['installed_at']}',
        ));
      }

      if (mounted) {

        setState(() {
          _nodes = nodes;

          final mi = _v['mileage_unit'] == 'mi';
          _types = types.where((t) {
            final norm = _int(mi ? t['norm_mi'] : t['norm_km']);
            return _truthy(t['track']) && norm > 0;
          }).toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (_) {
      if (mounted) setState(() => _err = 'Нет связи с сервером');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _mileage => ((_v['mileage'] as num?) ?? 0).round();

  Future<void> _renewDoc(String type) async {
    final ok = await showRenewSheet(
      context,
      vehicle: _v,
      type: type,
      currentTo:
      '${_v[type == 'insurance' ? 'insurance_to' : 'inspection_to'] ?? ''}',
    );
    if (ok != true) return;
    try {
      final all = await Api.vehicles();
      final fresh =
      all.firstWhere((x) => x['id'] == _v['id'], orElse: () => null);
      if (fresh != null && mounted) {
        setState(() => _v.addAll(Map<String, dynamic>.from(fresh)));
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Срок продлён, создана новая запись')));
    }
  }
  Future<void> _showActions() async {
    final act = await showModalBottomSheet<String>(
      context: context,

      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.edit_outlined, color: _P.text),
                title: Text('Изменить',
                    style: TextStyle(
                        color: _P.text, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading:
                Icon(Icons.delete_outline_rounded, color: _P.red),
                title: Text('Удалить',
                    style: TextStyle(
                        color: _P.red, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (act == 'edit') {
      await _editVehicle();
    } else if (act == 'delete') {
      await _deleteVehicle();
    }
  }


  Future<void> _editVehicle() async {
    final ok = await showVehicleForm(context, vehicle: _v);
    if (ok != true) return;
    try {
      final all = await Api.vehicles();
      final fresh =
      all.firstWhere((x) => x['id'] == _v['id'], orElse: () => null);
      if (fresh != null && mounted) {
        setState(() => _v.addAll(Map<String, dynamic>.from(fresh)));
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Данные сохранены')));
    }
  }

  Future<void> _deleteVehicle() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _P.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Подтверждение удаления'),
        content: Text('Удалить машину ${_v['plate']} вместе с её документами?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
              Text('Удалить', style: TextStyle(color: _P.red))),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await Api.deleteVehicle((_v['id'] as num).toInt());
      Api.docsChanged.value++; // обновит вкладку «ТО и доки»
      if (mounted) Navigator.of(context).pop(); // назад в гараж, он перезагрузится
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
  Future<void> _updateMileage() async {
    final r = await Api.autoSyncMileage(force: true);
    if (r == null) {
      if (mounted) toast(context, 'Не удалось обновить пробег', error: true);
      return;
    }
    try {
      final all = await Api.vehicles();
      final fresh =
      all.firstWhere((x) => x['id'] == _v['id'], orElse: () => null);
      if (fresh != null && mounted) {
        setState(() => _v.addAll(Map<String, dynamic>.from(fresh)));
      }
    } catch (_) {}
    if (mounted) toast(context, 'Пробег обновлён');
  }

  /// Долгое нажатие на узел: заменить или удалить установку
  Future<void> _nodeActions(_Node n) async {
    final act = await showPartActions(context, n.title);
    if (!mounted) return;
    if (act == 'replace') {
      _install(node: n);
    } else if (act == 'delete') {
      await deletePartFlow(context, _int(_v['id']), n.typeId, n.title);
      // список обновится сам через Api.docsChanged
    }
  }

  /// Форма «Добавить: Установка».
  /// node != null — замена конкретного узла (запчасть уже выбрана),
  /// node == null — новая установка с выбором запчасти.
  Future<void> _install({_Node? node}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,

      isScrollControlled: true,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => InstallSheet(
        vehicle: _v,
        mileage: _mileage,
        types: _types,
        fixedTypeId: node?.typeId,
        fixedName: node?.title,
      ),
    );
    if (ok == true) {
      await _load();
      Api.docsChanged.value++; // <- новая строка
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Установка сохранена')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final m = _mileage;
    final list = [..._nodes]..sort((a, b) {
      final c = b.level(m).compareTo(a.level(m));
      return c != 0 ? c : a.value(m).compareTo(b.value(m));
    });

    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        backgroundColor: _P.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _P.text,
        systemOverlayStyle: AppTheme.dark.value
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleSpacing: 0,
        title: Text('${v['model']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
        actions: [
          GestureDetector(
            onTap: _showActions,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 36,
              height: 32,
              decoration: BoxDecoration(
                color: _P.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _P.line),
              ),
              child: Icon(Icons.more_horiz_rounded,
                  size: 20, color: _P.text),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PlateBadge('${v['plate']}', fs: 13),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(
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
                if (list.isEmpty)
                  _empty()
                else
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
                  onPressed: _loading ? null : () => _install(),
                  icon: Icon(Icons.add_circle_outline_rounded, size: 22),
                  label: Text('ДОБАВИТЬ УСТАНОВКУ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _P.accent,
                    foregroundColor: _P.onAccent,
                    textStyle: TextStyle(
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

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _P.line),
      ),
      child: Column(
        children: [
          Icon(Icons.build_outlined, size: 36, color: _P.muted),
          SizedBox(height: 10),
          Text('Пока нет установленных запчастей',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _P.text)),
          SizedBox(height: 4),
          Text('Нажмите «Добавить установку», чтобы добавить первую',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: _P.muted)),
        ],
      ),
    );
  }

  // ───────── верхняя карточка: кольцо + пробег ─────────

  Widget _summary(int m) {
    final has = _nodes.isNotEmpty;
    final avg = !has
        ? 0.0
        : _nodes.map((n) => n.value(m)).reduce((a, b) => a + b) /
        _nodes.length;
    final worst = !has ? 0 : _nodes.map((n) => n.level(m)).reduce(max);
    final attention = _nodes.where((n) => n.level(m) >= 1).length;
    final c = has ? _lc(worst) : _P.muted;

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
                    Text(has ? '${(avg * 100).round()}%' : '—',
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
                    Text('Ресурс узлов',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _P.text)),
                    const SizedBox(height: 3),
                    Text(
                        has
                            ? 'Средний ресурс · узлов: ${_nodes.length}'
                            : 'Нет данных об установке',
                        style:
                        TextStyle(fontSize: 12.5, color: _P.muted)),
                    if (has) ...[
                      const SizedBox(height: 6),
                      Text(
                        attention > 0
                            ? '$attention ИЗ ${_nodes.length} ТРЕБУЮТ ВНИМАНИЯ'
                            : 'ВСЁ В НОРМЕ',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w800,
                            color: c),
                      ),
                    ],
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
                      Text('ПРОБЕГ',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.9,
                              fontWeight: FontWeight.w800,
                              color: _P.muted)),
                      Text('${fmtKm(m)} ${unitOf(_v)}',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: _P.text)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _updateMileage,
                  icon: Icon(Icons.sync_rounded, size: 16),
                  label: Text('ОБНОВИТЬ'),
                  style: TextButton.styleFrom(
                    foregroundColor: _P.accent,
                    textStyle: TextStyle(
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
                v['insurance_to'], daysOf(v['insurance_days']),
                    () => _renewDoc('insurance'))),
        const SizedBox(width: 10),
        Expanded(
            child: _docTile(Icons.fact_check_outlined, 'Техосмотр',
                v['inspection_to'], daysOf(v['inspection_days']),
                    () => _renewDoc('inspection'))),
      ],
    );
  }

  Widget _docTile(IconData icon, String label, dynamic to, int? days,
      VoidCallback onTap) {
    final c = _dc(days);
    return Material(
      color: c.withOpacity(0.07),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.withOpacity(0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: c, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _P.text)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(to == null ? 'Нет данных' : 'до ${fmtDate(to)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: _P.muted)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(_dshort(days),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: c)),
                  ),
                  const SizedBox(width: 4),
                  Text(to == null ? 'ДОБАВИТЬ ›' : 'ПРОДЛИТЬ ›',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w800,
                          color: _P.accent)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  // ───────── карточка узла (тап — форма замены) ─────────

  Widget _nodeCard(_Node n, int m) {
    final left = n.left(m);
    final value = n.value(m);
    final level = n.level(m);
    final c = _lc(level);
    final u = unitOf(_v);
    return Material(
      color: _P.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: level == 2 ? c.withOpacity(0.45) : _P.line),
      ),
      child: InkWell(
        onTap: () => _install(node: n),
        onLongPress: () => _nodeActions(n),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: _P.text)),
                        const SizedBox(height: 2),
                        Text(
                            'Установлено ${fmtDate(n.installedAt)} · ${fmtKm(n.lastKm)} $u',
                            style: TextStyle(
                                fontSize: 11.5, color: _P.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(n.reset(m) ? '—' : '${(value * 100).round()}%',
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
              Text(
                n.reset(m)
                    ? 'Пробег сбросился: введите установку заново'
                    : left >= 0
                    ? 'Осталось ${fmtKm(left)} $u из ${fmtKm(n.normKm)}'
                    : 'Перепробег ${fmtKm(-left)} $u · интервал ${fmtKm(n.normKm)}',
                style: TextStyle(fontSize: 12, color: _P.muted),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(n.reset(m) ? 'ПРОБЕГ СБРОСИЛСЯ' : _status(level),
                      style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w800,
                          color: c)),
                  const Spacer(),
                  Text('ЗАМЕНИТЬ ›',
                      style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w800,
                          color: _P.accent)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Форма «Добавить: Установка» (как на сайте):
/// машина, запчасть, дата установки, пробег машины при установке.
/// Форма «Добавить: Установка» (как на сайте):
/// машина, запчасть, дата установки, пробег машины при установке.
class InstallSheet extends StatefulWidget {
  final Map<String, dynamic> vehicle;
  final int mileage;
  final List<dynamic> types;
  final int? fixedTypeId; // запчасть уже выбрана (тап по узлу)
  final String? fixedName;
  const InstallSheet({
    required this.vehicle,
    required this.mileage,
    required this.types,
    this.fixedTypeId,
    this.fixedName,
  });
  @override
  State<InstallSheet> createState() => InstallSheetState();
}

class InstallSheetState extends State<InstallSheet> {
  late int? _typeId = widget.fixedTypeId;
  late final _dateC = TextEditingController(text: _ru(DateTime.now()));
  late final _km = TextEditingController(text: '${widget.mileage}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _dateC.dispose();
    _km.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var init = _parseRu(_dateC.text) ?? today;
    if (init.isAfter(today)) init = today;
    final d = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Дата установки',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: _P.accent,
            onPrimary: Colors.white,
            surface: _P.card,
            onSurface: _P.text,
            surfaceTint: Colors.transparent,
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: _P.card,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: _P.card,
            headerForegroundColor: _P.text,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: _P.accent),
          ),
        ),
        child: child!,
      ),
    );
    if (d == null) return;
    setState(() {
      _error = null;
      _dateC.text = _ru(d);
    });
  }

  OutlineInputBorder _border([Color? c]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: c == null
        ? BorderSide.none
        : BorderSide(color: c, width: 1.5),
  );

  /// Поле даты: можно вписать цифрами (точки сами) или нажать на календарь
  Widget _dateField() {
    return TextField(
      controller: _dateC,
      keyboardType: TextInputType.number,
      inputFormatters: [DateMaskFormatter()],
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      style: TextStyle(
          fontSize: 18,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
          color: _P.text),
      cursorColor: _P.accent,
      decoration: InputDecoration(
        hintText: 'ДД.ММ.ГГГГ',
        hintStyle: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFD1D5DB)),
        filled: true,
        fillColor: _P.card2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: _border(),
        enabledBorder: _border(),
        focusedBorder: _border(_P.accent),
        suffixIcon: IconButton(
          tooltip: 'Выбрать в календаре',
          icon: Icon(Icons.calendar_month_rounded, color: _P.accent),
          onPressed: _pickDate,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_typeId == null) {
      setState(() => _error = 'Выберите запчасть');
      return;
    }
    final date = _parseRu(_dateC.text);
    if (date == null) {
      setState(() => _error = 'Дата установки введена неверно (например, 15.03.2026)');
      return;
    }
    final now = DateTime.now();
    if (date.isAfter(DateTime(now.year, now.month, now.day))) {
      setState(() => _error = 'Дата установки не может быть в будущем');
      return;
    }
    final km = int.tryParse(_km.text.trim());
    if (km == null || km < 0) {
      setState(() => _error = 'Укажите пробег машины при установке');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.addPart(
        vehicleId: widget.vehicle['id'],
        partTypeId: _typeId!,
        installedAt: _iso(date),
        mileageAt: km,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Нет связи с сервером');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 14),
    child: Text(t,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _P.muted)),
  );

  Widget _readOnly(String text, {IconData? icon}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    decoration: BoxDecoration(
      color: _P.card2,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: _P.text)),
        ),
        if (icon != null) Icon(icon, size: 20, color: _P.muted),
      ],
    ),
  );

  /// Поиск запчасти: белое меню, чёрный текст, серая подсветка (без оранжевого)
  Widget _partPicker() {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: _P.ink,
          surface: _P.card,
          surfaceTint: Colors.transparent,
          surfaceContainer: _P.card,
          surfaceContainerHigh: _P.card,
          primaryContainer: _P.card2,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: _P.ink,
          selectionHandleColor: _P.ink,
          selectionColor: _P.ink.withOpacity(0.15),
        ),
        hoverColor: _P.card2,
        highlightColor: _P.card2,
        splashColor: _P.card2,
      ),
      child: LayoutBuilder(
        builder: (_, c) => DropdownMenu<int>(
          width: c.maxWidth,
          hintText: 'Начните ввод для поиска...',
          enableFilter: true,
          requestFocusOnTap: true,
          menuHeight: 260,
          textStyle: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: _P.text),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: _P.card2,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            border: _border(),
            enabledBorder: _border(),
            focusedBorder: _border(_P.accent),
          ),
          menuStyle: MenuStyle(
            backgroundColor: MaterialStatePropertyAll(_P.card),
            surfaceTintColor:
            const MaterialStatePropertyAll(Colors.transparent),
            elevation: const MaterialStatePropertyAll(4),
            shape: MaterialStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: _P.line),
            )),
          ),
          dropdownMenuEntries: [
            for (final t in widget.types)
              DropdownMenuEntry<int>(
                value: _int(t['id']),
                label: '${t['name']}',
                style: ButtonStyle(
                  backgroundColor: MaterialStatePropertyAll(_P.card),
                  foregroundColor: MaterialStatePropertyAll(_P.text),
                  textStyle: const MaterialStatePropertyAll(TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
                  overlayColor: MaterialStatePropertyAll(_P.card2),
                ),
              ),
          ],
          onSelected: (id) => setState(() => _typeId = id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Добавить: Установка',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
            _label('Машина'),
            _readOnly('${v['plate']} ${v['model']}'),
            _label('Запчасть'),
            if (widget.fixedTypeId != null)
              _readOnly(widget.fixedName ?? '')
            else
              _partPicker(),
            _label('Дата установки'),
            _dateField(),
            _label('Пробег машины при установке, ${unitOf(widget.vehicle)}'),
            TextField(
              controller: _km,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _save(),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: _P.text),
              cursorColor: _P.ink,
              decoration: InputDecoration(
                suffixText: unitOf(widget.vehicle),

                suffixStyle: TextStyle(color: _P.muted, fontWeight: FontWeight.w600),
                filled: true,
                fillColor: _P.card2,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                border: _border(),
                enabledBorder: _border(),
                focusedBorder: _border(_P.muted),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: TextStyle(
                        color: _P.red, fontWeight: FontWeight.w500)),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _P.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _busy
                          ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                          : Text('СОХРАНИТЬ',
                          style: TextStyle(
                              fontSize: 14,
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: _P.muted,
                      backgroundColor: _P.card2,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Отмена',
                        style: TextStyle(fontWeight: FontWeight.w700)),
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