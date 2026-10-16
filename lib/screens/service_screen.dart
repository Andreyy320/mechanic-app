import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import 'ui.dart' show daysOf, fmtDate;

/// Вкладка «ТО и доки». Логика та же, что в разделах сайта
/// «Техосмотр», «Автострахование» и «История авто»:
///  • по каждому виду берётся действующий документ (с самой поздней датой окончания);
///  • цвет срока: просрочено — красный, осталось 30 дней и меньше — жёлтый, иначе зелёный;
///  • нет документа — красный «нет данных»;
///  • «Продлить» создаёт новую запись, срок по умолчанию: техосмотр +6 мес., страховка +12 мес., минус один день.

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

const _typeNames = {
  'inspection': 'Техосмотр',
  'insurance': 'Страховка',
  'other': 'Другое',
};

class _Lbl {
  final String from, to;
  final int months;
  const _Lbl(this.from, this.to, this.months);
}

const _labels = {
  'inspection': _Lbl('Дата ТО', 'Следующий ТО', 6),
  'insurance': _Lbl('Начало страховки', 'Конец страховки', 12),
};

// ───────── утилиты ─────────

String _two(int x) => x.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _ru(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

DateTime? _parse(dynamic s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('$s');
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

String _fmtDT(dynamic s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}:\d{2})').firstMatch('$s');
  return m == null ? '—' : '${m[3]}.${m[2]}.${m[1]} ${m[4]}';
}

/// Дата через N месяцев минус один день (18.08.2026 + 6 мес. = 17.02.2027)
DateTime _plusMonths(DateTime d, int months) {
  final tm = (d.month - 1) + months;
  final ty = d.year + tm ~/ 12;
  final tmm = tm % 12;
  final lastDay = DateTime(ty, tmm + 2, 0).day;
  final dd = min(d.day, lastDay);
  return DateTime(ty, tmm + 1, dd - 1);
}

DateTime _defaultEnd(String type, DateTime d) =>
    _plusMonths(d, _labels[type]?.months ?? 12);

int? _dl(dynamic d) => daysOf(d['days_left']);

/// 2 — просрочено, 1 — осталось 30 дней и меньше, 0 — в порядке, null — нет данных
int? _lvl(int? d) {
  if (d == null) return null;
  if (d < 0) return 2;
  if (d <= 30) return 1;
  return 0;
}

Color _lcol(int? lv) => lv == 2
    ? _P.red
    : lv == 1
    ? _P.accent
    : lv == 0
    ? _P.green
    : _P.muted;

String _statusText(int? d) {
  if (d == null) return 'нет данных';
  if (d < 0) return 'просрочено ${-d} дн.';
  if (d == 0) return 'истекает сегодня';
  return 'осталось $d дн.';
}

String _docName(dynamic d) {
  if (d['doc_type'] == 'other') {
    final t = '${d['title'] ?? ''}'.trim();
    return t.isEmpty ? 'Другое' : t;
  }
  return _typeNames['${d['doc_type']}'] ?? '${d['doc_type']}';
}

String _key(dynamic d) =>
    d['doc_type'] == 'other' ? 'other:${d['title'] ?? ''}' : '${d['doc_type']}';

// ───────── экран ─────────

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});
  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  List<dynamic> _cars = [];
  List<dynamic> _docs = [];
  int _index = 0;
  bool _loading = true;
  String? _err;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false, bool withCars = true}) async {
    final my = ++_req;
    if (!silent) {
      setState(() {
        _loading = true;
        _err = null;
      });
    }
    try {
      if (withCars) {
        final cars = await Api.vehicles();
        if (my != _req) return;
        _cars = cars;
        if (_index >= cars.length) _index = 0;
      }
      final docs = _cars.isEmpty
          ? <dynamic>[]
          : await Api.vehicleDocuments(_cars[_index]['id']);
      if (my != _req) return;
      _docs = docs;
      _err = null;
    } on ApiException catch (e) {
      if (my == _req) _err = e.message;
    } catch (_) {
      if (my == _req) _err = 'Нет связи с сервером';
    }
    if (mounted && my == _req) setState(() => _loading = false);
  }

  /// Действующий документ по каждому виду (для «Другое» — по названию)
  Map<String, dynamic> _current() {
    final best = <String, dynamic>{};
    for (final d in _docs) {
      final k = _key(d);
      final b = best[k];
      if (b == null) {
        best[k] = d;
      } else {
        final c = '${d['date_to']}'.compareTo('${b['date_to']}');
        if (c > 0 ||
            (c == 0 && ((d['id'] as num?) ?? 0) > ((b['id'] as num?) ?? 0))) {
          best[k] = d;
        }
      }
    }
    return best;
  }

  Future<void> _openForm({String? type, dynamic doc, bool renew = false}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DocSheet(
        vehicle: _cars[_index],
        doc: doc,
        fixedType: type,
        renew: renew,
      ),
    );
    if (ok == true) {
      await _load(silent: true, withCars: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(renew
                ? 'Срок продлён, создана новая запись'
                : 'Данные сохранены')));
      }
    }
  }

  Future<void> _rowActions(dynamic d) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: _P.text),
                title: const Text('Изменить',
                    style: TextStyle(
                        color: _P.text, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: _P.red),
                title: const Text('Удалить',
                    style: TextStyle(
                        color: _P.red, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (act == 'edit') {
      await _openForm(doc: d);
    } else if (act == 'delete') {
      await _confirmDelete(d);
    }
  }

  Future<void> _confirmDelete(dynamic d) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Подтверждение удаления'),
        content: Text(
            'Удалить запись «${_docName(d)}» (до ${fmtDate(d['date_to'])})?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить',
                  style: TextStyle(color: _P.red))),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await Api.deleteDocument((d['id'] as num).toInt());
      await _load(silent: true, withCars: false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Запись удалена')));
      }
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

  Future<void> _pickVehicle() async {
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
            for (var k = 0; k < _cars.length; k++)
              ListTile(
                onTap: () => Navigator.pop(context, k),
                leading: const Icon(Icons.directions_car_rounded,
                    color: _P.accent),
                title: Text('${_cars[k]['model']}',
                    style: const TextStyle(
                        color: _P.text, fontWeight: FontWeight.w700)),
                subtitle: Text('${_cars[k]['plate']}',
                    style: const TextStyle(color: _P.muted)),
                trailing: k == _index
                    ? const Icon(Icons.check_rounded, color: _P.accent)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (i != null && i != _index) {
      _index = i;
      await _load(withCars: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _cars.isEmpty ? null : _cars[_index];
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ТЕХОСМОТР И СТРАХОВКА',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: _P.accent)),
            Text(v == null ? 'Документы' : '${v['model']}',
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
              onTap: _cars.length > 1 ? _pickVehicle : null,
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _P.text),
                ),
                child: Row(
                  children: [
                    Text('${v['plate']}',
                        style: const TextStyle(
                            fontSize: 13,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800,
                            color: _P.text)),
                    if (_cars.length > 1)
                      const Icon(Icons.expand_more_rounded,
                          size: 18, color: _P.text),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _P.accent));
    }
    if (_err != null) return _error();
    if (_cars.isEmpty) {
      return const Center(
          child: Text('Машин пока нет',
              style: TextStyle(color: _P.muted, fontSize: 15)));
    }

    final cur = _current();
    final others = cur.entries
        .where((e) => e.key.startsWith('other:'))
        .map((e) => e.value)
        .toList();
    final hist = [..._docs]..sort((a, b) =>
        '${b['date_from'] ?? b['date_to']}'
            .compareTo('${a['date_from'] ?? a['date_to']}'));

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: _P.accent,
            backgroundColor: _P.card,
            onRefresh: () => _load(silent: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                _label('ДЕЙСТВУЮЩИЕ ДОКУМЕНТЫ'),
                _docCard('inspection', cur['inspection']),
                const SizedBox(height: 10),
                _docCard('insurance', cur['insurance']),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _label('ПРОЧИЕ ДОКУМЕНТЫ'),
                  for (final d in others) ...[
                    _otherCard(d),
                    const SizedBox(height: 10),
                  ],
                ],
                const SizedBox(height: 20),
                _label('ИСТОРИЯ · ${hist.length}'),
                if (hist.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                        child: Text('По этой машине пока нет записей',
                            style: TextStyle(color: _P.muted))),
                  ),
                for (final d in hist)
                  _histRow(d, identical(cur[_key(d)], d)),
              ],
            ),
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
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                label: const Text('ДОБАВИТЬ ДОКУМЕНТ'),
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
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(t,
        style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: _P.muted)),
  );

  // ───────── карточка действующего документа ─────────

  Widget _docCard(String type, dynamic d) {
    final L = _labels[type]!;
    final icon = type == 'insurance'
        ? Icons.shield_outlined
        : Icons.fact_check_outlined;
    final name = _typeNames[type]!;
    final days = d == null ? null : _dl(d);
    final lv = d == null ? 2 : _lvl(days); // нет документа — красный, как на сайте
    final c = _lcol(lv);

    final fromD = d == null ? null : _parse(d['date_from']);
    final toD = d == null ? null : _parse(d['date_to']);
    var total = 365;
    if (fromD != null && toD != null) {
      final t = toD.difference(fromD).inDays;
      if (t > 0) total = t;
    }
    final value = days == null ? 0.0 : (days / total).clamp(0.0, 1.0);
    final warn = lv == 1 || lv == 2; // дату окончания красим, только если срок на исходе

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: warn ? c.withOpacity(0.5) : _P.line),
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
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: c, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _P.text)),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusText(days).toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w800,
                        color: c)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _kv(L.from,
                    d == null || fromD == null ? '—' : _ru(fromD), _P.text),
              ),
              Expanded(
                child: _kv(L.to,
                    d == null || toD == null ? 'нет' : _ru(toD),
                    warn ? c : _P.text),
              ),
            ],
          ),
          if (d != null) ...[
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
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _openForm(type: type, renew: d != null),
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
              child: Text(d == null ? 'ДОБАВИТЬ' : 'ПРОДЛИТЬ'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, Color vc) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k,
          style: const TextStyle(
              fontSize: 11.5, color: _P.muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(v,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: vc)),
    ],
  );

  /// Прочий документ: название, срок и статус
  Widget _otherCard(dynamic d) {
    final days = _dl(d);
    final lv = _lvl(days);
    final c = _lcol(lv);
    return Material(
      color: _P.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: (lv == 1 || lv == 2) ? c.withOpacity(0.5) : _P.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _rowActions(d),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.description_outlined, color: c, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_docName(d),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _P.text)),
                    const SizedBox(height: 2),
                    Text('до ${fmtDate(d['date_to'])}',
                        style:
                        const TextStyle(fontSize: 12.5, color: _P.muted)),
                  ],
                ),
              ),
              Text(_statusText(days),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c)),
            ],
          ),
        ),
      ),
    );
  }

  // ───────── история ─────────

  Widget _histRow(dynamic d, bool current) {
    final from = d['date_from'];
    final lv = current ? _lvl(_dl(d)) : null;
    final warn = lv == 1 || lv == 2;
    final base = current ? _P.text : _P.muted;
    final period = from == null || '$from'.isEmpty || '$from' == 'null'
        ? 'до ${fmtDate(d['date_to'])}'
        : '${fmtDate(from)} — ${fmtDate(d['date_to'])}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _P.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _P.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _rowActions(d),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_docName(d),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: base)),
                    ),
                    if (!current)
                      const Text('АРХИВ',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.7,
                              fontWeight: FontWeight.w800,
                              color: _P.muted))
                    else if (warn)
                      Text(_statusText(_dl(d)).toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w800,
                              color: _lcol(lv))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(period,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: warn ? _lcol(lv) : base)),
                const SizedBox(height: 2),
                Text(
                    'Оформлено ${_fmtDT(d['created_at'])}',
                    style: const TextStyle(fontSize: 11.5, color: _P.muted)),
              ],
            ),
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

/// Форма документа: вид, название (для «Другое»), дата начала, дата окончания.
/// При добавлении и продлении дата окончания подставляется сама (как на сайте).
class _DocSheet extends StatefulWidget {
  final dynamic vehicle;
  final dynamic doc; // null — новая запись
  final String? fixedType; // вид уже выбран (продлить / добавить в карточке)
  final bool renew;
  const _DocSheet({
    required this.vehicle,
    this.doc,
    this.fixedType,
    this.renew = false,
  });
  @override
  State<_DocSheet> createState() => _DocSheetState();
}

class _DocSheetState extends State<_DocSheet> {
  late String _type =
      '${widget.doc?['doc_type'] ?? widget.fixedType ?? 'inspection'}';
  late final _title =
  TextEditingController(text: '${widget.doc?['title'] ?? ''}');
  DateTime? _from, _to;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.doc != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _from = _parse(widget.doc['date_from']);
      _to = _parse(widget.doc['date_to']);
    } else {
      final n = DateTime.now();
      _from = DateTime(n.year, n.month, n.day);
      _to = _defaultEnd(_type, _from!);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _setType(String t) {
    setState(() {
      _type = t;
      if (!_editing && _from != null) _to = _defaultEnd(t, _from!);
    });
  }

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 15),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (!_editing) _to = _defaultEnd(_type, d);
      } else {
        _to = d;
      }
    });
  }

  Future<void> _save() async {
    if (_type == 'other' && _title.text.trim().isEmpty) {
      setState(() => _error = 'Укажите название документа');
      return;
    }
    if (_to == null) {
      setState(() => _error = 'Укажите дату окончания');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      'doc_type': _type,
      'title': _type == 'other' ? _title.text.trim() : '',
      'date_from': _from == null ? '' : _iso(_from!),
      'date_to': _iso(_to!),
    };
    try {
      if (_editing) {
        await Api.updateDocument((widget.doc['id'] as num).toInt(), body);
      } else {
        await Api.addDocument((widget.vehicle['id'] as num).toInt(), body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Нет связи с сервером');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _lbl(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 14),
    child: Text(t,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _P.muted)),
  );

  Widget _field(String text, {IconData? icon, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
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
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _P.text)),
              ),
              if (icon != null) Icon(icon, size: 20, color: _P.muted),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final L = _labels[_type];
    final title = widget.renew
        ? 'Продлить: ${v['plate']}'
        : (_editing ? 'Редактировать: Документ' : 'Добавить: Документ');

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
            _lbl('Машина'),
            _field('${v['plate']} ${v['model']}'),
            if (widget.fixedType == null) ...[
              _lbl('Вид документа'),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in _typeNames.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _type == e.key,
                      onSelected: (_) => _setType(e.key),
                      selectedColor: _P.accent.withOpacity(0.15),
                      backgroundColor: _P.card2,
                      side: BorderSide(
                          color: _type == e.key ? _P.accent : _P.line),
                      labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _type == e.key ? _P.accent : _P.text),
                    ),
                ],
              ),
            ],
            if (_type == 'other') ...[
              _lbl('Название'),
              TextField(
                controller: _title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _P.text),
                cursorColor: _P.accent,
                decoration: InputDecoration(
                  hintText: 'Например, Зелёная карта',
                  filled: true,
                  fillColor: _P.card2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
            _lbl(L?.from ?? 'Начало'),
            _field(_from == null ? 'Не указана' : _ru(_from!),
                icon: Icons.calendar_today_outlined, onTap: () => _pick(true)),
            _lbl(L?.to ?? 'Окончание'),
            _field(_to == null ? 'Выберите дату' : _ru(_to!),
                icon: Icons.calendar_today_outlined, onTap: () => _pick(false)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(
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
                        foregroundColor: _P.onAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _busy
                          ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                          : const Text('СОХРАНИТЬ',
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
                    child: const Text('Отмена',
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