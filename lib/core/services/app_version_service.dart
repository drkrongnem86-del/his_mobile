// AppVersionService v2.66.0 - Lấy version app động từ package_info_plus
// Hiển thị ở Settings - số phiên bản + build number

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionService {
  static final AppVersionService instance = AppVersionService._();
  AppVersionService._();

  String _version = '...';
  String _buildNumber = '...';
  String _packageName = 'com.drnem.his_mobile';
  String _appName = 'HIS MOBILE';
  bool _loaded = false;

  Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
      _packageName = info.packageName;
      _appName = info.appName;
      _loaded = true;
      debugPrint('📦 App version: $_version+$_buildNumber ($_packageName)');
    } catch (e) {
      debugPrint('Load PackageInfo error: $e');
      _version = '2.66.0';
      _buildNumber = '0';
    }
  }

  String get version => _version;
  String get buildNumber => _buildNumber;
  String get packageName => _packageName;
  String get appName => _appName;
  String get displayVersion => '$_version+$_buildNumber';
  String get displayFull => '$_appName v$_version (build $_buildNumber)';
  bool get loaded => _loaded;
}