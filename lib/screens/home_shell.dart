import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'vehicles_screen.dart';
import 'service_screen.dart';
import 'profile_screen.dart';
import 'ui.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

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
          _tab(1, const _Soon('Узлы', 'Ресурс узлов и замены появятся здесь')),
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