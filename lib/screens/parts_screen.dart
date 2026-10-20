import 'dart:math' show max, min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import 'ui.dart' show fmtKm, fmtDate, PlateBadge;
import 'vehicleDetail_screen.dart' show InstallSheet;

/// Вкладка «Узлы» — рабочий список «что менять».
/// • по умолчанию показаны только узлы «К замене»; «Скоро» и «Все» — фильтрами;
/// • два вида: «По машинам» (у какой машины что менять)
///   и «По запчастям» (какой запчасти сколько нужно — удобно для закупки);
/// • компактные строки, тап по строке — форма «Заменить».
/// Пороги те же, что в карточке машины и в гараже.

class _P {
  static const bg = Color(0xFFF6F7FA);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE5E7EB);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const accent = Color(0xFFE08A00);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
}

enum _Filter { red, soon, all }

int _n(dynamic v) =>
    v is num ? v.round() : (num.tryParse('$v')?.round() ?? 0);

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

String _tag(int level) =>
    level == 2 ? 'ЗАМЕНИТЬ' : (level == 1 ? 'СКОРО' : 'В НОРМЕ');

/// Один узел, установленный на конкретной машине
class _Item {
  final dynamic vehicle;
  final int typeId;
  final String name;
  final int norm; // норматив замены, км
  final int warn1; // жёлтый порог (осталось км)
  final int warn2; // красный порог (осталось км)
  final int lastKm; // пробег машины при установке
  final String installedAt; // YYYY-MM-DD
  _Item(this.vehicle, this.typeId, this.name, this.norm, this.warn1,
      this.warn2, this.lastKm, this.installedAt);

  int get mileage => _n(vehicle['mileage']);
  int get left => norm - max(mileage - lastKm, 0);
  double get value => (left / norm).clamp(0.0, 1.0).toDouble();

  /// 0 — в норме, 1 — скоро замена, 2 — требует замены
  int get level {
    final l = left;
    final w1 = max(warn1, warn2);
    if (w1 == 0 && warn2 == 0) {
      final v = value;
      return v <= 0.2 ? 2 : (v <= 0.5 ? 1 : 0);
    }
    if (l <= warn2) return 2;
    if (l <= w1) return 1;
    return 0;
  }
}

/// Группа строк: одна машина или одна запчасть
class _Group {
  final List<_Item> items;
  _Group(this.items);
  int get red => items.where((i) => i.level == 2).length;
  int get soon => items.where((i) => i.level == 1).length;
  int get worst => red > 0 ? 2 : (soon > 0 ? 1 : 0);
  double get minValue => items.map((i) => i.value).reduce(min);
}

class PartsScreen extends StatefulWidget {
  const PartsScreen({super.key});
  @override
  State<PartsScreen> createState() => _PartsScreenState();
}

class _PartsScreenState extends State<PartsScreen> {
  List<_Item> _items = [];
  bool _loading = true;
  String? _err;
  String _query = '';
  _Filter _filter = _Filter.red;
  bool _byCar = true;
  final Set<String> _open = {}; // какие карточки раскрыты

  @override
  void initState() {
    super.initState();
    _load();
    // что-то изменили на другой вкладке — список обновится сам
    Api.docsChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    Api.docsChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _err = null;
      });
    }
    try {
      final res = await Future.wait([Api.vehicles(), Api.parts()]);
      final cars = {for (final c in res[0]) _n(c['id']): c};

      // по каждой паре «машина + запчасть» берём последнюю установку
      final latest = <String, dynamic>{};
      for (final p in res[1]) {
        final k = '${p['vehicle_id']}:${p['part_type_id']}';
        final cur = latest[k];
        if (cur == null) {
          latest[k] = p;
          continue;
        }
        final c = '${p['installed_at']}'.compareTo('${cur['installed_at']}');
        if (c > 0 || (c == 0 && _n(p['id']) > _n(cur['id']))) latest[k] = p;
      }

      final items = <_Item>[];
      for (final p in latest.values) {
        // /parts может не отдавать track — пропускаем, только если он явно выключен
        final t = p['track'];
        final untracked = t != null && !(t == true || t == 1 || t == 'true');
        final norm = _n(p['norm_km']);
        if (untracked || norm <= 0) continue;
        final car = cars[_n(p['vehicle_id'])];
        if (car == null) continue;
        items.add(_Item(
          car,
          _n(p['part_type_id']),
          '${p['part_name']}',
          norm,
          _n(p['warn1_km']),
          _n(p['warn2_km']),
          _n(p['mileage_at']),
          '${p['installed_at']}',
        ));
      }

      _items = items;
      _err = null;
    } on ApiException catch (e) {
      _err = e.message;
    } catch (_) {
      _err = 'Нет связи с сервером';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _replace(_Item it) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => InstallSheet(
        vehicle: Map<String, dynamic>.from(it.vehicle),
        mileage: it.mileage,
        types: const [],
        fixedTypeId: it.typeId,
        fixedName: it.name,
      ),
    );
    if (ok == true && mounted) {
      Api.docsChanged.value++; // обновит эту вкладку и гараж
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Установка сохранена')));
    }
  }

  List<_Group> _groups(List<_Item> list) {
    final m = <int, List<_Item>>{};
    for (final i in list) {
      (m[_byCar ? _n(i.vehicle['id']) : i.typeId] ??= []).add(i);
    }
    final gs = m.values.map((l) {
      l.sort((a, b) {
        final c = b.level.compareTo(a.level);
        return c != 0 ? c : a.value.compareTo(b.value);
      });
      return _Group(l);
    }).toList();
    gs.sort((a, b) {
      final c = b.worst.compareTo(a.worst);
      return c != 0 ? c : a.minValue.compareTo(b.minValue);
    });
    return gs;
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
        titleSpacing: 16,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text('Ресурс запчастей',
            style: TextStyle(
                fontSize: 22,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: _P.text)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _P.accent));
    }
    if (_err != null) return _error();

    final red = _items.where((i) => i.level == 2).length;
    final soon = _items.where((i) => i.level == 1).length;
    final q = _query.trim().toLowerCase();

    final filtered = _items.where((i) {
      if (_filter == _Filter.red && i.level != 2) return false;
      if (_filter == _Filter.soon && i.level != 1) return false;
      if (q.isEmpty) return true;
      return '${i.vehicle['plate']} ${i.vehicle['model']} ${i.name}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final groups = _groups(filtered);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            children: [
              Row(
                children: [
                  _chip('К замене', red, _Filter.red, _P.red),
                  const SizedBox(width: 8),
                  _chip('Скоро', soon, _Filter.soon, _P.accent),
                  const SizedBox(width: 8),
                  _chip('Все', _items.length, _Filter.all, _P.text),
                ],
              ),
              const SizedBox(height: 10),
              _search(),
              const SizedBox(height: 10),
              _seg(),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: _P.accent,
            backgroundColor: _P.card,
            onRefresh: () => _load(silent: true),
            child: groups.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [_empty()],
            )
                : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
              itemCount: groups.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Text(
                        '${_byCar ? 'МАШИНЫ' : 'ЗАПЧАСТИ'} · ${groups.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: _P.muted)),
                  );
                }
                return _groupCard(groups[i - 1]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    final allGood = _items.isNotEmpty && _query.trim().isEmpty;
    final good = allGood && _filter != _Filter.all;
    final icon = good
        ? Icons.check_circle_outline_rounded
        : Icons.build_outlined;
    final title = _items.isEmpty
        ? 'Пока нет установленных запчастей'
        : good
        ? (_filter == _Filter.red
        ? 'Нет узлов к замене'
        : 'Ничего не горит')
        : 'Ничего не найдено';
    final sub = _items.isEmpty
        ? 'Добавьте установку в карточке машины'
        : good
        ? 'Всё в порядке'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
      child: Column(
        children: [
          Icon(icon, size: 44, color: good ? _P.green : _P.muted),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _P.text)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: _P.muted)),
          ],
        ],
      ),
    );
  }

  // ───────── верх: фильтры, поиск, переключатель вида ─────────

  Widget _chip(String label, int n, _Filter f, Color c) {
    final sel = _filter == f;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? c.withOpacity(0.1) : _P.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? c : _P.line, width: sel ? 1.5 : 1),
          ),
          child: Column(
            children: [
              Text('$n',
                  style: TextStyle(
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: n == 0 && f != _Filter.all ? _P.muted : c)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _P.muted)),
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
        hintText: 'Запчасть, номер или модель',
        hintStyle: const TextStyle(color: _P.muted),
        prefixIcon: const Icon(Icons.search_rounded, color: _P.muted),
        filled: true,
        fillColor: _P.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: b(_P.line),
        enabledBorder: b(_P.line),
        focusedBorder: b(_P.accent, 1.4),
      ),
    );
  }

  Widget _seg() {
    Widget b(String t, IconData i, bool sel, VoidCallback f) => Expanded(
      child: GestureDetector(
        onTap: f,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: sel ? _P.card : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: sel ? Border.all(color: _P.line) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(i, size: 16, color: sel ? _P.text : _P.muted),
              const SizedBox(width: 6),
              Text(t,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: sel ? _P.text : _P.muted)),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE9ECF2),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          b('По машинам', Icons.directions_car_outlined, _byCar,
                  () => setState(() => _byCar = true)),
          b('По запчастям', Icons.build_outlined, !_byCar,
                  () => setState(() => _byCar = false)),
        ],
      ),
    );
  }

  // ───────── группа: машина или запчасть ─────────

  Widget _plate(String p, {double fs = 12}) => PlateBadge(p, fs: fs);

  Widget _count(int n, Color c) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text('$n',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: c)),
      ],
    ),
  );

  Widget _groupCard(_Group g) {
    final first = g.items.first;
    final c = _lc(g.worst);
    // ключ с префиксом, чтобы «машина 1» и «запчасть 1» не путались
    final key = _byCar ? 'c${_n(first.vehicle['id'])}' : 't${first.typeId}';
    // при поиске карточки раскрываются сами, чтобы сразу было видно найденное
    final open = _open.contains(key) || _query.trim().isNotEmpty;

    return Material(
      color: _P.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: g.red > 0 ? c.withOpacity(0.45) : _P.line),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (!_open.remove(key)) _open.add(key);
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  if (_byCar)
                    _plate('${first.vehicle['plate']}', fs: 13)
                  else
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _P.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_iconFor(first.name),
                          color: _P.accent, size: 19),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_byCar ? '${first.vehicle['model']}' : first.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: _P.text)),
                        Text(
                            _byCar
                                ? 'узлов: ${g.items.length}'
                                : 'машин: ${g.items.length}',
                            style: const TextStyle(
                                fontSize: 11.5, color: _P.muted)),
                      ],
                    ),
                  ),
                  if (g.red > 0) _count(g.red, _P.red),
                  if (g.soon > 0) _count(g.soon, _P.accent),
                  if (g.red == 0 && g.soon == 0)
                    const Icon(Icons.check_circle_rounded,
                        size: 20, color: _P.green),
                  const SizedBox(width: 4),
                  Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _P.muted),
                ],
              ),
            ),
          ),
          if (open)
            for (final it in g.items) ...[
              const Divider(height: 1, thickness: 1, color: _P.line),
              _row(it),
            ],
        ],
      ),
    );
  }
  // ───────── компактная строка узла ─────────

  Widget _row(_Item it) {
    final c = _lc(it.level);
    final left = it.left;

    return InkWell(
      onTap: () => _replace(it),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            if (_byCar)
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(it.name), color: c, size: 19),
              )
            else
              _plate('${it.vehicle['plate']}', fs: 11.5),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_byCar ? it.name : '${it.vehicle['model']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _P.text)),
                  const SizedBox(height: 2),
                  Text(
                      left >= 0
                          ? 'Осталось ${fmtKm(left)} км · с ${fmtDate(it.installedAt)}'
                          : 'Перепробег ${fmtKm(-left)} км · с ${fmtDate(it.installedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: _P.muted)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: it.value,
                      minHeight: 4,
                      backgroundColor: c.withOpacity(0.16),
                      valueColor: AlwaysStoppedAnimation(c),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${(it.value * 100).round()}%',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c)),
                const SizedBox(height: 2),
                Text(_tag(it.level),
                    style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w800,
                        color: c)),
              ],
            ),
          ],
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
            Text(_err ?? 'Не удалось загрузить данные',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _P.text)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: _P.accent,
                foregroundColor: Colors.white,
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