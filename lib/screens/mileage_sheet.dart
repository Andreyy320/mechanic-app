import 'package:flutter/material.dart';
import '../services/api.dart';
import 'ui.dart';

/// Открывает окно ввода пробега. Возвращает новый пробег (int) или null.
Future<int?> showMileageSheet(BuildContext context, dynamic vehicle) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _MileageSheet(vehicle: vehicle),
  );
}

class _MileageSheet extends StatefulWidget {
  final dynamic vehicle;
  const _MileageSheet({required this.vehicle});
  @override
  State<_MileageSheet> createState() => _MileageSheetState();
}

class _MileageSheetState extends State<_MileageSheet> {
  late final _c = TextEditingController(
      text: '${(widget.vehicle['mileage'] as num?)?.round() ?? ''}');
  bool _busy = false;
  bool _force = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final km = int.tryParse(_c.text.trim());
    if (km == null || km < 0) {
      setState(() => _error = 'Введите пробег числом');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.updateMileage(widget.vehicle['id'], km, force: _force);
      if (mounted) Navigator.of(context).pop(km);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Нет связи с сервером');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Обновить пробег',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: kText)),
          const SizedBox(height: 4),
          Text('${widget.vehicle['plate']} · ${widget.vehicle['model']}',
              style: const TextStyle(fontSize: 14, color: kMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
                suffixText: unitOf(widget.vehicle),
              filled: true,
              fillColor: kBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _force,
            onChanged: (v) => setState(() => _force = v),
            title: const Text('Разрешить уменьшение пробега',
                style: TextStyle(fontSize: 14)),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: TextStyle(
                      color: Colors.red.shade700, fontWeight: FontWeight.w500)),
            ),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
                  : const Text('Сохранить',
                  style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

