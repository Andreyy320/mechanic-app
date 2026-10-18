import 'dart:math' show min;
import 'package:flutter/material.dart';
import '../services/api.dart';

class _P {
  static const card = Color(0xFFFFFFFF);
  static const card2 = Color(0xFFF1F3F7);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const accent = Color(0xFFE08A00);
  static const red = Color(0xFFDC2626);
}

const _names = {'inspection': 'Техосмотр', 'insurance': 'Страховка'};
const _fromLbl = {'inspection': 'Дата ТО', 'insurance': 'Начало страховки'};
const _toLbl = {'inspection': 'Следующий ТО', 'insurance': 'Конец страховки'};
const _months = {'inspection': 6, 'insurance': 12};

String _two(int x) => x.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _ru(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

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
  late DateTime _from;
  late DateTime _to;
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
    _from = DateTime(n.year, n.month, n.day);
    _to = _plusMonths(_from, _months[widget.type] ?? 12);
  }

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 15),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        _to = _plusMonths(d, _months[widget.type] ?? 12);
      } else {
        _to = d;
      }
    });
  }

  Future<void> _save() async {
    if (_to.isBefore(_from)) {
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
        'date_from': _iso(_from),
        'date_to': _iso(_to),
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
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
            if (cur != null) ...[
              const SizedBox(height: 4),
              Text('Сейчас действует до ${_ru(cur)}',
                  style: const TextStyle(fontSize: 13, color: _P.muted)),
            ],
            _lbl('Машина'),
            _field('${v['plate']} ${v['model']}'),
            _lbl(_fromLbl[widget.type] ?? 'Начало'),
            _field(_ru(_from),
                icon: Icons.calendar_today_outlined, onTap: () => _pick(true)),
            _lbl(_toLbl[widget.type] ?? 'Окончание'),
            _field(_ru(_to),
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
                          style: const TextStyle(
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