import 'package:flutter/services.dart';

const _mask = '__.__.____';
/// Частичная проверка: «_» допустимы, но уже введённые цифры
/// не должны давать день > 31, месяц > 12 или нули (00).
bool _valid(List<String> c) {
  bool d(String s) => s != '_';
  // день
  if (d(c[0]) && !'0123'.contains(c[0])) return false;
  if (c[0] == '3' && d(c[1]) && !'01'.contains(c[1])) return false;
  if (c[0] == '0' && c[1] == '0') return false;
  // месяц
  if (d(c[3]) && !'01'.contains(c[3])) return false;
  if (c[3] == '1' && d(c[4]) && !'012'.contains(c[4])) return false;
  if (c[3] == '0' && c[4] == '0') return false;
  // год: 1xxx или 2xxx
  if (d(c[6]) && !'12'.contains(c[6])) return false;
  return true;
}
/// Ввод даты по маске ДД.ММ.ГГГГ: цифры вписываются поверх «_»,
/// удаление заменяет цифру на «_» и ничего не сдвигает, курсор остаётся на месте.
class DateMaskFormatter extends TextInputFormatter {
  static bool _dot(int i) => i == 2 || i == 5;
  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final oldOk = oldValue.text.length == 10;
    final chars = (oldOk ? oldValue.text : _mask).split('');
    final nl = newValue.text.length;
    final cur = newValue.selection.baseOffset.clamp(0, nl);
    var cursor = cur;

    if (oldOk && nl < 10) {
      // удаление
      final removed = 10 - nl;
      final start = cur;
      final end = (start + removed).clamp(0, 10);
      var cleared = false;
      for (var i = start; i < end; i++) {
        if (!_dot(i)) {
          chars[i] = '_';
          cleared = true;
        }
      }
      cursor = start;
      if (!cleared && start > 0) {
        // стёрли только точку — чистим цифру перед ней
        var j = start - 1;
        if (_dot(j)) j--;
        if (j >= 0) {
          chars[j] = '_';
          cursor = j;
        }
      }
    } else if (nl > (oldOk ? 10 : 0)) {
      // ввод или вставка: цифры ложатся поверх маски
      final k = nl - (oldOk ? 10 : 0);
      final start = (cur - k).clamp(0, nl);
      final inserted = newValue.text.substring(start, cur);
      var p = start;
      for (final ch in inserted.split('')) {
        if (!_isDigit(ch)) continue;
        while (p < 10 && _dot(p)) p++;
        if (p >= 10) break;
        chars[p] = ch;
        p++;
      }
      cursor = p;
      while (cursor < 10 && _dot(cursor)) cursor++;
    } else if (oldOk && nl == 10) {
      // заменили выделенный символ
      for (var i = 0; i < 10; i++) {
        if (_dot(i)) continue;
        final ch = newValue.text[i];
        chars[i] = _isDigit(ch) ? ch : '_';
      }
    }

    if (!_valid(chars)) return oldValue; // недопустимая цифра не вводится

    return TextEditingValue(
      text: chars.join(),
      selection: TextSelection.collapsed(offset: cursor.clamp(0, 10)),
    );
  }
}