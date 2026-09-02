// MainScreen v3.0.75 - Bottom nav với 4 mục: Trang chủ / Hồ sơ / Tiện ích / Cài đặt
// v3.0.75: Bỏ "Báo cáo" khỏi narrow nav theo yêu cầu BS
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainScreen extends StatefulWidget {
  final Widget child;

  const MainScreen({super.key, required this.child});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  void _goTo(int index) {
    // Đóng mọi dialog/sheet đang mở trước khi chuyển tab
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
    if (Navigator.of(context).canPop()) {
      while (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
    setState(() => _currentIndex = index);
    switch (index) {
      case 0:
        // Trang chủ
        context.go('/home');
        break;
      case 1:
        // v3.0.74: Hồ sơ điều trị
        context.go('/ho-so-dieu-tri');
        break;
      case 2:
        context.go('/tien-ich');
        break;
      case 3:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _goTo,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Hồ sơ',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: 'Tiện ích',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}
