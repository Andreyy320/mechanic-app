import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';

class _P {
  static const card = Color(0xFFFFFFFF);
  static const card2 = Color(0xFFF1F3F7);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const accent = Color(0xFFE08A00);
  static const red = Color(0xFFDC2626);
}

/// Форма машины: гос. номер, марка, цвет, пробег, описание.
/// vehicle == null — «Добавить» (машина записывается на того, кто вошёл),
/// иначе — «Редактировать». Возвращает true, если данные сохранены.
Future<bool?> showVehicleForm(BuildContext context, {dynamic vehicle}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _P.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _VehicleFormSheet(vehicle: vehicle),
  );
}

final _letter = RegExp(r'\p{L}', unicode: true);
final _digit = RegExp(r'\d');

/// Номер вводится «как есть», формат определяется сам:
///   вторая цифра  → «Т 774 МЕ»  (буква, 3 цифры, 2 буквы)
///   вторая буква  → «АВС 123»  (3 буквы, 3 цифры)
/// Заглавные буквы и пробелы ставятся автоматически.
class _PlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final buf = <String>[];
    String? kinds; // 'LDDDLL' или 'LLLDDD'
    for (final ch in newValue.text.toUpperCase().split('')) {
      final isL = _letter.hasMatch(ch), isD = _digit.hasMatch(ch);
      if (!isL && !isD) continue; // пробелы и прочее пропускаем
      if (buf.isEmpty) {
        if (isL) buf.add(ch); // номер начинается с буквы
        continue;
      }
      if (kinds == null) kinds = isD ? 'LDDDLL' : 'LLLDDD';
      if (buf.length >= kinds.length) break;
      if (kinds[buf.length] == 'L' ? isL : isD) buf.add(ch);
    }
    final b = StringBuffer();
    for (var i = 0; i < buf.length; i++) {
      final spaceBefore = kinds == 'LDDDLL' ? (i == 1 || i == 4) : i == 3;
      if (i > 0 && spaceBefore) b.write(' ');
      b.write(buf[i]);
    }
    final t = b.toString();
    return TextEditingValue(
        text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// Подходит ли номер под один из двух шаблонов (иначе — «нестандартный»)
bool _isStandard(String p) =>
    RegExp(r'^\p{L} \d{3} \p{L}{2}$', unicode: true).hasMatch(p) ||
        RegExp(r'^\p{L}{3} \d{3}$', unicode: true).hasMatch(p);

class _VehicleFormSheet extends StatefulWidget {
  final dynamic vehicle;
  const _VehicleFormSheet({this.vehicle});
  @override
  State<_VehicleFormSheet> createState() => _VehicleFormSheetState();
}

class _VehicleFormSheetState extends State<_VehicleFormSheet> {
  late final _plate = TextEditingController(text: _s('plate'));
  late final _model = TextEditingController(text: _s('model'));
  late final _color = TextEditingController(text: _s('color'));
  late final _km = TextEditingController(
      text: _editing ? '${(widget.vehicle['mileage'] as num?)?.round() ?? ''}' : '');
  late final _desc = TextEditingController(text: _s('description'));
  // нестандартный номер: свободный ввод без шаблона
  late bool _free = _editing && !_isStandard(_s('plate').trim());
  bool _busy = false;
  String? _error;

  bool get _editing => widget.vehicle != null;

  String _s(String k) {
    final v = widget.vehicle?[k];
    return v == null ? '' : '$v';
  }

  @override
  void dispose() {
    _plate.dispose();
    _model.dispose();
    _color.dispose();
    _km.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _toggleFree() {
    setState(() {
      _free = !_free;
      _plate.clear();
    });
  }

  Future<bool> _confirmLower(int now, int cur) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _P.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Пробег уменьшится'),
        content: Text(
            'Новый пробег $now км меньше текущего $cur км. Это нормально только при исправлении ошибки. Сохранить?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _save() async {
    final plate = _plate.text.trim();
    final model = _model.text.trim();
    if (plate.isEmpty) {
      setState(() => _error = 'Укажите гос. номер');
      return;
    }
    // обычный номер должен быть введён полностью: 6 символов
    if (!_free && plate.replaceAll(' ', '').length != 6) {
      setState(() => _error = 'Введите номер полностью');
      return;
    }
    if (model.isEmpty) {
      setState(() => _error = 'Укажите марку');
      return;
    }
    final kmText = _km.text.trim();
    final km = kmText.isEmpty ? null : int.tryParse(kmText);
    if (kmText.isNotEmpty && km == null) {
      setState(() => _error = 'Пробег должен быть числом');
      return;
    }

    // как на сайте: пробег меньше текущего — только после подтверждения
    var force = false;
    if (_editing && km != null) {
      final cur = ((widget.vehicle['mileage'] as num?) ?? 0).round();
      if (km < cur) {
        if (!await _confirmLower(km, cur)) return;
        force = true;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'plate': plate,
      'model': model,
      'color': _color.text.trim(),
      'description': _desc.text.trim(),
      if (km != null) 'mileage': km,
      if (force) 'force': true,
    };
    try {
      if (_editing) {
        await Api.updateVehicle((widget.vehicle['id'] as num).toInt(), body);
      } else {
        await Api.createVehicle(body);
      }
      Api.docsChanged.value++; // обновит список на вкладке «ТО и доки»
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // например «Машина с таким гос. номером уже есть»
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
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _P.muted)),
  );

  Widget _input(TextEditingController c,
      {TextInputType? type,
        int lines = 1,
        String? suffix,
        List<TextInputFormatter>? formatters,
        TextCapitalization cap = TextCapitalization.none}) {
    return TextField(
      controller: c,
      keyboardType: type,
      maxLines: lines,
      minLines: lines,
      inputFormatters: formatters,
      textCapitalization: cap,
      style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w600, color: _P.text),
      cursorColor: _P.accent,
      decoration: InputDecoration(
        suffixText: suffix,
        filled: true,
        fillColor: _P.card2,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Поле в виде номерного знака
  Widget _plateField() {
    return Column(
      children: [
        Container(
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _P.text, width: 2),
          ),
          child: TextField(
            key: ValueKey(_free), // при смене режима поле строится заново
            controller: _plate,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: _free
                ? [
              TextInputFormatter.withFunction(
                      (o, n) => n.copyWith(text: n.text.toUpperCase()))
            ]
                : [_PlateFormatter()],
            cursorColor: _P.accent,
            style: const TextStyle(
                fontSize: 28,
                letterSpacing: 3,
                fontWeight: FontWeight.w800,
                color: _P.text),
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              hintText: _free ? 'НОМЕР' : 'Т 774 МЕ',
              hintStyle: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD1D5DB)),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _toggleFree,
            style: TextButton.styleFrom(
              foregroundColor: _P.muted,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            child: Text(_free ? 'Обычный номер' : 'Нестандартный номер'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_editing ? 'Редактировать: Машина' : 'Добавить: Машина',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
            _label('Гос. номер'),
            _plateField(),
            _label('Марка'),
            _input(_model, cap: TextCapitalization.words),
            _label('Цвет'),
            _input(_color, cap: TextCapitalization.sentences),
            _label('Пробег, км'),
            _input(_km,
                type: TextInputType.number,
                suffix: 'км',
                formatters: [FilteringTextInputFormatter.digitsOnly]),
            _label('Описание'),
            _input(_desc, lines: 3, cap: TextCapitalization.sentences),
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