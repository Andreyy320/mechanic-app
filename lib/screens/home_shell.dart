import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mechanic_app/screens/parts_screen.dart';
import 'vehicles_screen.dart';
import 'service_screen.dart';
import 'profile_screen.dart';
import 'ui.dart';
import 'dart:async';
import '../services/api.dart';
import '../services/push.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _i = 0;
  Timer? _timer;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Api.autoSyncMileage(); // при открытии приложения
    Push.openTab.addListener(_onPushTab); // тап по уведомлению открывает нужную вкладку
    Push.init();
    _timer = Timer.periodic(
        const Duration(minutes: 10), (_) => Api.autoSyncMileage());
    Api.checkVersion(); // один раз запомнить текущую версию
    Api.startEvents();  // дальше сервер сам сообщает об изменениях


  }

  void _onPushTab() {
    final i = Push.openTab.value;
    if (i == null) return;
    Push.openTab.value = null;
    if (mounted) setState(() => _i = i);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      Api.autoSyncMileage(); // вернулся в приложение
      Push.resync(); // держим токен на сервере свежим
      Api.checkVersion();
      Api.startEvents();
    }
  }

  @override
  void dispose() {
    Push.openTab.removeListener(_onPushTab);
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  /// У каждой вкладки свой Navigator: экраны, открытые внутри вкладки
  /// (например, карточка машины), показываются НАД контентом,
  /// а нижняя панель остаётся на месте.
  final _keys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  Widget _tab(int i, Widget root) => Navigator(
    key: _keys[i],
    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
  );

  void _onTap(int i) {
    if (i == _i) {
      // повторное нажатие на активную вкладку — вернуться к её корню
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _i = i);
    }
  }

  void _onBack(bool didPop) {
    if (didPop) return;
    final nav = _keys[_i].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else if (_i != 0) {
      setState(() => _i = 0);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: _onBack,
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      body: IndexedStack(
        index: _i,
        children: [
          _tab(0, const VehiclesScreen()),
          _tab(1, const PartsScreen()),
          _tab(2, const ServiceScreen()),
          _tab(3, const ProfileScreen()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.directions_car_outlined),
              selectedIcon: Icon(Icons.directions_car_rounded),
              label: 'Гараж'),
          NavigationDestination(
              icon: Icon(Icons.build_outlined),
              selectedIcon: Icon(Icons.build_rounded),
              label: 'Узлы'),
          NavigationDestination(
              icon: Icon(Icons.description_outlined),
              selectedIcon: Icon(Icons.description_rounded),
              label: 'ТО и доки'),
          NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Профиль'),
        ],
      ),
    );
  }
}

class _Soon extends StatelessWidget {
  final String title;
  final String text;
  const _Soon(this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(title,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: kText)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction_rounded, size: 44, color: kMuted),
              const SizedBox(height: 14),
              const Text('Скоро',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: kText)),
              const SizedBox(height: 6),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kMuted)),
            ],
          ),
        ),
      ),
    );
  }
}