import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import 'login_screen.dart';
import 'history_screen.dart';
import 'ui.dart' show C, AppTheme;

class _P {
  static Color get bg => C.bg;
  static Color get card => C.card;
  static Color get card2 => C.card2;
  static Color get line => C.line;
  static Color get text => C.text;
  static Color get muted => C.muted;
  static const accent = Color(0xFFE08A00);
  static const red = Color(0xFFDC2626);
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  Future<void> _changeLogin() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _LoginChangeSheet(),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Логин изменён')));
    }
  }

  Future<void> _changePassword() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _PasswordSheet(),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Пароль изменён')));
    }
  }

  Future<void> _logout() async {
    final yes = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _LogoutSheet(),
    );
    if (yes != true) return;
    await Api.logout();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (Api.name?.trim().isNotEmpty ?? false)
        ? Api.name!.trim()
        : 'Пользователь';

    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        backgroundColor: _P.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 68,
        titleSpacing: 16,
        systemOverlayStyle: AppTheme.dark.value
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: AppTheme.dark,
            builder: (_, d, __) => IconButton(
              icon: Icon(
                  d ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: _P.text),
              onPressed: AppTheme.toggle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        title: Text('Профиль',
            style: TextStyle(
                fontSize: 22,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: _P.text)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // карточка человека
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _P.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _P.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _P.accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: _P.accent.withOpacity(0.45)),
                  ),
                  child: Text(name[0].toUpperCase(),
                      style: TextStyle(

                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _P.accent)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(

                              fontSize: 20,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              color: _P.text)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // действия
          Material(
            color: _P.card,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
color: _P.line),
            ),
            child: Column(
              children: [
                _tile(Icons.history_rounded, 'История авто', () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                }),
                Divider(
height: 1, thickness: 1, color: _P.line),
                _tile(Icons.person_outline_rounded, 'Сменить логин', _changeLogin),
                Divider(
height: 1, thickness: 1, color: _P.line),
                _tile(Icons.lock_outline_rounded, 'Сменить пароль',
                    _changePassword),
                Divider(
height: 1, thickness: 1, color: _P.line),
                _tile(Icons.logout_rounded, 'Выйти', _logout,
                    chevron: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap,
      {Color? color, bool chevron = true}) {
    final col = color ?? _P.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: col == _P.red ? _P.red.withOpacity(0.1) : _P.card2,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: col, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: col)),
            ),
            if (chevron) Icon(Icons.chevron_right_rounded, color: _P.muted),
          ],
        ),
      ),
    );
  }
}

/// Подтверждение выхода.
class _LogoutSheet extends StatelessWidget {
  const _LogoutSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _P.accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
Icons.logout_rounded,
                    color: _P.accent, size: 26),
              ),
            ),
            const SizedBox(height: 16),
            Text(
'Выйти из аккаунта?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
            const SizedBox(height: 6),
            Text(
'Чтобы войти снова, понадобятся логин и пароль.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: _P.muted)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: _P.muted,
                        backgroundColor: _P.card2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
'Отмена',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: _P.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
'Выйти',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
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

/// Форма «Сменить пароль»: текущий, новый, повтор нового.
class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet();
  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _cur = TextEditingController();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cur.dispose();
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_cur.text.isEmpty || _p1.text.isEmpty || _p2.text.isEmpty) {
      setState(() => _error = 'Заполните все поля');
      return;
    }
    if (_p1.text != _p2.text) {
      setState(() => _error = 'Новые пароли не совпадают');
      return;
    }
    if (_p1.text.length < 3) {
      setState(() => _error = 'Пароль должен быть не короче 3 символов');
      return;
    }
    if (_p1.text == _cur.text) {
      setState(() => _error = 'Новый пароль совпадает со старым');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.changePassword(_cur.text, _p1.text);
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

  Widget _field(TextEditingController c, {Widget? suffix}) => TextField(
    controller: c,
    obscureText: !_show,
    autocorrect: false,
    enableSuggestions: false,
    style: TextStyle(

        fontSize: 15, fontWeight: FontWeight.w600, color: _P.text),
    cursorColor: _P.accent,
    decoration: InputDecoration(
      filled: true,
      fillColor: _P.card2,
      suffixIcon: suffix,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );

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
            Text(
'Сменить пароль',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
            _label('Текущий пароль'),
            _field(
              _cur,
              suffix: IconButton(
                icon: Icon(
                    _show
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _P.muted),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
            _label('Новый пароль'),
            _field(_p1),
            _label('Повторите новый пароль'),
            _field(_p2),
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
                          : Text(
'Сохранить',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
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
                    child: Text(
'Отмена',
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
/// Форма «Сменить логин»: новый логин + текущий пароль для подтверждения.
class _LoginChangeSheet extends StatefulWidget {
  const _LoginChangeSheet();
  @override
  State<_LoginChangeSheet> createState() => _LoginChangeSheetState();
}

class _LoginChangeSheetState extends State<_LoginChangeSheet> {
  final _login = TextEditingController();
  final _pass = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = _login.text.trim();
    if (l.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Заполните все поля');
      return;
    }
    if (l.length < 4) {
      setState(() => _error = 'Логин должен быть не короче 4 символов');
      return;
    }
    if (l.contains(RegExp(r'\s'))) {
      setState(() => _error = 'В логине не должно быть пробелов');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.changeLogin(_pass.text, l);
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

  InputDecoration _dec({Widget? suffix}) => InputDecoration(
    filled: true,
    fillColor: _P.card2,
    suffixIcon: suffix,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );

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
            Text(
'Сменить логин',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _P.text)),
            _label('Новый логин'),
            TextField(
              controller: _login,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(

                  fontSize: 15, fontWeight: FontWeight.w600, color: _P.text),
              cursorColor: _P.accent,
              decoration: _dec(),
            ),
            _label('Текущий пароль (для подтверждения)'),
            TextField(
              controller: _pass,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _save(),
              style: TextStyle(

                  fontSize: 15, fontWeight: FontWeight.w600, color: _P.text),
              cursorColor: _P.accent,
              decoration: _dec(
                suffix: IconButton(
                  icon: Icon(
                      _show
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: _P.muted),
                  onPressed: () => setState(() => _show = !_show),
                ),
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
                          : Text(
'Сохранить',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
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
                    child: Text(
'Отмена',
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