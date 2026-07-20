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
    // v2.81.0: Bỏ tab 'Bệnh nhân' (index 1) - index 0..3 cho Trang chủ/Báo cáo/Tiện ích/Cài đặt
    // v2.94.0: Đóng mọi dialog/sheet đang mở trước khi chuyển tab
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
    // Đóng tất cả dialogs/sheets đang hiển thị
    // (Navigator.popUntil chỉ pop routes, cần thêm cách đóng dialogs)
    if (Navigator.of(context).canPop()) {
      // Pop hết dialogs
      while (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
    setState(() => _currentIndex = index);
    switch (index) {
      case 0:
        // v2.94.0: Trang chủ - KHÔNG reset khoa, dùng khoa đã chọn trước đó
        context.go('/home');
        break;
      case 1:
        context.go('/reports');
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
            icon: Icon(Icons.assessment_outlined),
            selectedIcon: Icon(Icons.assessment),
            label: 'Báo cáo',
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
