import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import 'doc_renew_sheet.dart';
import 'ui.dart' show daysOf, fmtDate;

/// Вкладка «ТО и доки»: все машины механика, по каждой — срок техосмотра
/// и страховки. Сверху те, у кого хуже всего. Тап по документу — продлить.
/// Цвета как на сайте: нет данных / просрочено — красный,
/// осталось 30 дней и меньше — жёлтый, иначе зелёный.

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

enum _Filter { all, overdue, soon }

/// 2 — просрочено или нет данных, 1 — осталось 30 дней и меньше, 0 — в порядке
int _lvl(int? d) {
  if (d == null || d < 0) return 2;
  if (d <= 30) return 1;
  return 0;
}

Color _col(int lv) => lv == 2 ? _P.red : (lv == 1 ? _P.accent : _P.green);

String _statusText(int? d) {
  if (d == null) return 'нет данных';
  if (d < 0) return 'просрочено ${-d} дн.';
  if (d == 0) return 'истекает сегодня';
  return 'осталось $d дн.';
}

int? _insDays(dynamic v) =>
    v['insurance_to'] == null ? null : daysOf(v['insurance_days']);
int? _inspDays(dynamic v) =>
    v['inspection_to'] == null ? null : daysOf(v['inspection_days']);

/// Сколько дней до ближайшего срока (нет данных — самое срочное)
int _urgency(dynamic v) {
  final a = _insDays(v), b = _inspDays(v);
  final x = a ?? -1000000, y = b ?? -1000000;
  return x < y ? x : y;
}

bool _isOverdue(dynamic v) => _lvl(_insDays(v)) == 2 || _lvl(_inspDays(v)) == 2;
bool _isSoon(dynamic v) =>
    !_isOverdue(v) && (_lvl(_insDays(v)) == 1 || _lvl(_inspDays(v)) == 1);

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});
  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  List<dynamic> _cars = [];
  bool _loading = true;
  String? _err;
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
    // продлили документ на карточке машины — список обновится сам
    Api.docsChanged.addListener(_onDocs);
  }

  @override
  void dispose() {
    Api.docsChanged.removeListener(_onDocs);
    super.dispose();
  }

  void _onDocs() {
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
      final cars = await Api.vehicles();
      _cars = cars;
      _err = null;
    } on ApiException catch (e) {
      _err = e.message;
    } catch (_) {
      _err = 'Нет связи с сервером';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _renew(dynamic v, String type) async {
    final to = v[type == 'insurance' ? 'insurance_to' : 'inspection_to'];
    final ok = await showRenewSheet(context,
        vehicle: v, type: type, currentTo: '${to ?? ''}');
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Срок продлён, создана новая запись')));
    }
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ТЕХОСМОТР И СТРАХОВКА',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: _P.accent)),
            Text('ТО и доки',
                style: TextStyle(
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: _P.text)),
          ],
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _P.accent));
    }
    if (_err != null) return _error();

    final overdue = _cars.where(_isOverdue).length;
    final soon = _cars.where(_isSoon).length;
    final q = _query.trim().toLowerCase();

    final list = _cars.where((v) {
      if (_filter == _Filter.overdue && !_isOverdue(v)) return false;
      if (_filter == _Filter.soon && !_isSoon(v)) return false;
      if (q.isEmpty) return true;
      return '${v['plate']} ${v['model']}'.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => _urgency(a).compareTo(_urgency(b)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            children: [
              Row(
                children: [
                  _chip('Все', _cars.length, _Filter.all, _P.text),
                  const SizedBox(width: 8),
                  _chip('Просрочено', overdue, _Filter.overdue, _P.red),
                  const SizedBox(width: 8),
                  _chip('Скоро', soon, _Filter.soon, _P.accent),
                ],
              ),
              const SizedBox(height: 10),
              _search(),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: _P.accent,
            backgroundColor: _P.card,
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
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _carCard(list[i]),
            ),
          ),
        ),
      ],
    );
  }

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
        hintText: 'Поиск по номеру или модели',
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

  // ───────── карточка машины ─────────

  Widget _carCard(dynamic v) {
    final worst = [_lvl(_insDays(v)), _lvl(_inspDays(v))]
        .reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: worst == 0 ? _P.line : _col(worst).withOpacity(0.45)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('${v['model']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: _P.text)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: _P.text),
                  ),
                  child: Text('${v['plate']}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                          color: _P.text)),
                ),
              ],
            ),
          ),
          _docTile(v, 'inspection', Icons.fact_check_outlined, 'Техосмотр',
              v['inspection_to'], _inspDays(v)),
          const SizedBox(height: 8),
          _docTile(v, 'insurance', Icons.shield_outlined, 'Страховка',
              v['insurance_to'], _insDays(v)),
        ],
      ),
    );
  }

  Widget _docTile(dynamic v, String type, IconData icon, String label,
      dynamic to, int? days) {
    final c = _col(_lvl(days));
    return Material(
      color: c.withOpacity(0.07),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
       borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.withOpacity(0.35)),
      ),
      child: InkWell(
        onTap: () => _renew(v, type),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
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
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: _P.text)),
                    const SizedBox(height: 2),
                    Text(to == null ? 'Нет данных' : 'до ${fmtDate(to)}',
                        style: const TextStyle(
                            fontSize: 12.5, color: _P.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_statusText(days),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: c)),
                  const SizedBox(height: 3),
                  Text(to == null ? 'ДОБАВИТЬ ›' : 'ПРОДЛИТЬ ›',
                      style: const TextStyle(
                          fontSize: 10.5,
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