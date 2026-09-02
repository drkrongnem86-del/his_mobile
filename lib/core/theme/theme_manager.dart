import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v2.37.1: ThemeManager - singleton đổi theme toàn app
class ThemeManager {
  ThemeManager._();
  static final ThemeManager instance = ThemeManager._();

  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

  ThemeMode get current => themeModeNotifier.value;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode') ?? 'system';
    themeModeNotifier.value = saved == 'light'
        ? ThemeMode.light
        : saved == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      mode == ThemeMode.light ? 'light' : mode == ThemeMode.dark ? 'dark' : 'system',
    );
  }
}