import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/modules/auth/presentation/screens/splash_screen.dart';
import 'package:his_mobile/modules/auth/presentation/screens/login_screen.dart';
import 'package:his_mobile/presentation/screens/home_screen.dart';
import 'package:his_mobile/presentation/screens/main_screen.dart';
import 'package:his_mobile/presentation/screens/settings_screen.dart';
import 'package:his_mobile/presentation/screens/reports_screen.dart';
import 'package:his_mobile/presentation/screens/patients_screen.dart';
import 'package:his_mobile/presentation/screens/patient_detail_screen.dart';
import 'package:his_mobile/presentation/screens/tien_ich_screen.dart';
import 'package:his_mobile/presentation/screens/treatment_records_screen.dart';
import 'package:his_mobile/modules/cpa/presentation/screens/emergency_screen.dart';

import 'package:his_mobile/core/security/credentials.dart';
/// HIS Pro Mobile - Application Router
class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScreen(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/ho-so-dieu-tri',
            pageBuilder: (context, state) => const NoTransitionPage(child: TreatmentRecordsScreen()),
          ),
          GoRoute(
            path: '/patients',
            pageBuilder: (context, state) => const NoTransitionPage(child: PatientsScreen()),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => const NoTransitionPage(child: ReportsScreen()),
          ),
          GoRoute(
            path: '/tien-ich',
            pageBuilder: (context, state) => const NoTransitionPage(child: TienIchScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/emergency',
        builder: (context, state) => const EmergencyScreen(),
      ),
      GoRoute(
        path: '/patient-detail',
        builder: (context, state) {
          final extra = state.extra;
          Map<String, dynamic> patient = <String, dynamic>{};
          Map<String, dynamic> department = <String, dynamic>{};
          String username = Credentials.defaultNemkLogin;
          if (extra is Map<String, dynamic>) {
            patient = (extra['patient'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            department = (extra['department'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            username = (extra['username'] as String?) ?? Credentials.defaultNemkLogin;
          }
          return PatientDetailScreen(
            patient: patient,
            department: department,
            username: username,
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Page not found: ${state.uri}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('Ve trang chu'),
            ),
          ],
        ),
      ),
    ),
  );
}

extension NavigationExtension on BuildContext {
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
