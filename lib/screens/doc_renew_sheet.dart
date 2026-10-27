import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mechanic_app/screens/ui.dart' show C;
import '../services/api.dart';
import 'date_input.dart';

class _P {
  static Color get card => C.card;
  static Color get card2 => C.card2;
  static Color get line => C.line;
  static Color get text => C.text;
  static Color get muted => C.muted;
  static const accent = Color(0xFFE08A00);
  static const red = Color(0xFFDC2626);
}

const _names = {'inspection': 'Техосмотр', 'insurance': 'Страховка'};
const _fromLbl = {'inspection': 'Дата ТО', 'insurance': 'Начало страховки'};
const _toLbl = {'inspection': 'Следующий ТО', 'insurance': 'Конец страховки'};
const _defMonths = {'inspection': 6, 'insurance': 12};

String _two(int x) => x.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _ru(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

/// «15.03.2026» -> DateTime, либо null, если дата неполная или несуществующая
DateTime? _parse(String s) {
  final p = s.trim().split('.');
  if (p.length != 3 || p[2].length != 4) return null;
  final d = int.tryParse(p[0]), m = int.tryParse(p[1]), y = int.tryParse(p[2]);
  if (d == null || m == null || y == null) return null;
  final r = DateTime(y, m, d);
  // 31.02 превращается в март — считаем такую дату неверной
  if (r.year != y || r.month != m || r.day != d) return null;
  return r;
}

/// Дата через N месяцев минус один день (как на сайте)
DateTime _plusMonths(DateTime d, int months) {
  final tm = (d.month - 1) + months;
  final ty = d.year + tm ~/ 12;
  final tmm = tm % 12;
  final lastDay = DateTime(ty, tmm + 2, 0).day;
  return DateTime(ty, tmm + 1, min(d.day, lastDay) - 1);
}


/// Форма продления / добавления страховки или техосмотра.
/// type: 'insurance' | 'inspection'. Возвращает true, если запись сохранена.
Future<bool?> showRenewSheet(
    BuildContext context, {
      required dynamic vehicle,
      required String type,
      String? currentTo, // текущая дата окончания (YYYY-MM-DD), если есть
    }) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _P.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        _RenewSheet(vehicle: vehicle, type: type, currentTo: currentTo),
  );
}

class _RenewSheet extends StatefulWidget {
  final dynamic vehicle;
  final String type;
  final String? currentTo;
  const _RenewSheet(
      {required this.vehicle, required this.type, this.currentTo});
  @override
  State<_RenewSheet> createState() => _RenewSheetState();
}

class _RenewSheetState extends State<_RenewSheet> {
  late final TextEditingController _fromC;
  late final TextEditingController _toC;
  late int _months; // выбранная длительность (0 — своя дата окончания)
  bool _busy = false;
  String? _error;

  bool get _hasCurrent =>
      widget.currentTo != null &&
          widget.currentTo!.isNotEmpty &&
          widget.currentTo != 'null';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    final from = DateTime(n.year, n.month, n.day);
    _months = _defMonths[widget.type] ?? 12;
    _fromC = TextEditingController(text: _ru(from));
    _toC = TextEditingController(text: _ru(_plusMonths(from, _months)));
    _fromC.addListener(_onFromChanged);
  }

  @override
  void dispose() {
    _fromC.dispose();
    _toC.dispose();
    super.dispose();
  }

  /// Изменили дату начала — дата окончания пересчитывается (если выбран срок)
  void _onFromChanged() {
    if (_months == 0) return;
    final f = _parse(_fromC.text);
    if (f == null) return;
    _toC.text = _ru(_plusMonths(f, _months));
  }

  Future<void> _pick(TextEditingController c, {required bool isFrom}) async {
    final now = DateTime.now();
    final init = _parse(c.text) ?? DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 15),
      helpText: isFrom ? 'Дата начала' : 'Дата окончания',
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
      if (!isFrom) _months = 0; // дату окончания выбрали руками
      c.text = _ru(d);
    });
  }

  Future<void> _save() async {
    final from = _parse(_fromC.text);
    final to = _parse(_toC.text);
    if (from == null) {
      setState(() => _error = 'Дата начала введена неверно (например, 15.03.2026)');
      return;
    }
    if (to == null) {
      setState(() => _error = 'Дата окончания введена неверно (например, 14.03.2027)');
      return;
    }
    if (to.isBefore(from)) {
      setState(() => _error = 'Дата окончания раньше даты начала');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.addDocument((widget.vehicle['id'] as num).toInt(), {
        'doc_type': widget.type,
        'title': '',
        'date_from': _iso(from),
        'date_to': _iso(to),
      });
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
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _P.muted)),
  );

  Widget _readOnly(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    decoration: BoxDecoration(
      color: _P.card2,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(text,
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: _P.text)),
  );

  /// Поле даты: можно вписать цифрами (точки сами) или нажать на календарь
  Widget _dateField(TextEditingController c,
      {required bool isFrom, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [DateMaskFormatter()],
      onChanged: (v) {
        if (_error != null) setState(() => _error = null);
        onChanged?.call(v);
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
          fontSize: 16, fontWeight: FontWeight.w600, color: _P.muted),
        filled: true,
        fillColor: _P.card2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _P.accent, width: 1.5),
        ),
        suffixIcon: IconButton(
          tooltip: 'Выбрать в календаре',
          icon: const Icon(Icons.calendar_month_rounded, color: _P.accent),
          onPressed: () => _pick(c, isFrom: isFrom),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final name = _names[widget.type] ?? widget.type;
    final cur = _hasCurrent ? DateTime.tryParse(widget.currentTo!) : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_hasCurrent ? 'Продлить: $name' : 'Добавить: $name',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
            if (cur != null) ...[
              const SizedBox(height: 4),
              Text('Сейчас действует до ${_ru(cur)}',
                  style: TextStyle(fontSize: 13, color: _P.muted)),
            ],
            _lbl('Машина'),
            _readOnly('${v['plate']} ${v['model']}'),
            _lbl(_fromLbl[widget.type] ?? 'Начало'),
            _dateField(_fromC, isFrom: true),
            _lbl(_toLbl[widget.type] ?? 'Окончание'),
            _dateField(
              _toC,
              isFrom: false,
              // вписали дату окончания руками — срок больше не пересчитывается
              onChanged: (_) {
                if (_months != 0) setState(() => _months = 0);
              },
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
                          : Text(_hasCurrent ? 'ПРОДЛИТЬ' : 'СОХРАНИТЬ',
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