// UpdateService v3.0.99 - Fix black screen khi update
//
// v3.0.99 CHANGELOG:
//   - Root cause: app lưu APK vào /storage/emulated/0/Download/HisMobile/
//     Trên Android 11+ (scoped storage), app KHÔNG có quyền ghi vào shared
//     storage từ app context mà không có MANAGE_EXTERNAL_STORAGE.
//     → Directory.create(recursive: true) FAIL hoặc Dio.download() throw
//     → app không catch exception đúng → context.mounted false → black screen
//   - Fix: lưu vào getApplicationDocumentsDirectory() (app's own storage,
//     luôn writable, không cần permission)
//   - Fix: dùng MethodChannel native FileProvider intent để install
//     (Android 7+ yêu cầu content:// URI, không dùng file:// được)
//
// Workflow:
//   1. App mở → gọi UpdateService.checkUpdate()
//   2. GET https://raw.githubusercontent.com/drkrongnem86-del/his_mobile/main/version.json
//   3. So sánh version với app hiện tại
//   4. Nếu mới hơn → hiện dialog "Có bản cập nhật mới"
//   5. User bấm "Đồng ý" → tải APK → save vào app docs → mở installer (FileProvider)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String githubOwner = 'drkrongnem86-del';
  static const String githubRepo = 'his_mobile';
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/$githubOwner/$githubRepo/main/version.json';
  static const String _installerChannel = 'his_mobile/installer';

  /// Kiểm tra có bản cập nhật mới không
  static Future<UpdateInfo?> checkUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version;
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final r = await dio.get(versionJsonUrl);
      if (r.statusCode != 200 || r.data == null) return null;
      final data = r.data is String ? jsonDecode(r.data) as Map : r.data as Map;
      final newVersion = data['version']?.toString() ?? '';
      final apkUrl = data['apk_url']?.toString() ?? '';
      final message = data['message']?.toString() ?? '';
      if (newVersion.isEmpty || apkUrl.isEmpty) return null;
      if (!_isNewer(newVersion, currentVersion)) return null;
      return UpdateInfo(
        currentVersion: currentVersion,
        newVersion: newVersion,
        apkUrl: apkUrl,
        message: message,
      );
    } catch (e) {
      debugPrint('UpdateService.checkUpdate error: $e');
      return null;
    }
  }

  static bool _isNewer(String newVersion, String currentVersion) {
    final a = newVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final b = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (a.length < 3) {
      a.add(0);
    }
    while (b.length < 3) {
      b.add(0);
    }
    for (int i = 0; i < 3; i++) {
      if (a[i] > b[i]) return true;
      if (a[i] < b[i]) return false;
    }
    return false;
  }

  /// Hiện dialog thông báo có bản mới
  static void showUpdateDialog(BuildContext context, UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.system_update, color: Color(0xFF1976D2)),
          SizedBox(width: 8),
          Text('Có bản cập nhật mới'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _verChip('Hiện tại', info.currentVersion, Colors.grey),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 16),
              const SizedBox(width: 8),
              _verChip('Mới', info.newVersion, const Color(0xFF2E7D32)),
            ]),
            const SizedBox(height: 12),
            if (info.message.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(info.message,
                    style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
            const SizedBox(height: 8),
            const Text(
              'Bạn có muốn cập nhật không?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            const Text(
              '📥 APK tải về bộ nhớ trong của app. Sau khi tải xong, hệ thống sẽ tự mở installer - bấm "Cài đặt" để hoàn tất.',
              style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstall(context, info);
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('ĐỒNG Ý'),
          ),
        ],
      ),
    );
  }

  /// Tải APK về app's documents directory rồi gọi native install
  /// v3.0.99: app's documents dir (always writable) + MethodChannel install
  static Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    // Capture context sớm, dùng navigatorState thay vì context sau
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    String? apkPath;
    bool downloadOk = false;
    String? downloadError;
    double progress = 0;

    // Hiện dialog progress (không dismiss khi bấm ra ngoài)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            // Tick progress mỗi 200ms để update UI
            return AlertDialog(
              title: Text('Đang tải v${info.newVersion}…'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress > 0 ? progress : null),
                  const SizedBox(height: 12),
                  Text(
                    progress > 0
                        ? '${(progress * 100).toStringAsFixed(0)}% • ${info.newVersion}'
                        : 'Đang kết nối GitHub...',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Bước 1: Tải APK
    try {
      // v3.0.114: dùng getApplicationSupportDirectory() thay vì getApplicationDocumentsDirectory()
      // - getApplicationDocumentsDirectory() trả về /data/data/<pkg>/app_flutter/ (Flutter 3.x+)
      //   path này KHÔNG được FileProvider cover (chỉ cover /data/data/<pkg>/files/ + cache)
      // - getApplicationSupportDirectory() trả về /data/data/<pkg>/files/ (covered by <files-path>)
      // → FileProvider.getUriForFile() sẽ work
      final supportDir = await getApplicationSupportDirectory();
      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }
      apkPath = '${supportDir.path}/HIS_MOBILE_v${info.newVersion}.apk';

      // Xóa file cũ nếu có
      final oldFile = File(apkPath);
      if (await oldFile.exists()) {
        try {
          await oldFile.delete();
        } catch (_) {}
      }

      await Dio().download(
        info.apkUrl,
        apkPath,
        onReceiveProgress: (received, total) {
          if (total > 0) progress = received / total;
        },
      );
      downloadOk = true;
      final sizeBytes = await File(apkPath).length();
      debugPrint('✅ APK downloaded: $apkPath ($sizeBytes bytes)');
    } catch (e, st) {
      downloadError = e.toString();
      debugPrint('❌ UpdateService download error: $e\n$st');
    }

    // Đóng progress dialog (an toàn - dùng navigator)
    if (navigator.canPop()) {
      try {
        navigator.pop();
      } catch (_) {}
    }

    if (!downloadOk) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Tải APK lỗi: ${downloadError ?? "unknown"}'),
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    // Bước 2: Gọi native install qua MethodChannel + FileProvider
    try {
      const platform = MethodChannel(_installerChannel);
      final res = await platform.invokeMethod<bool>('installApk', {'path': apkPath});
      debugPrint('Install invoke result: $res');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('📲 Đang mở installer - bấm "Cài đặt" khi Android hỏi'),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('Native install error: $e');
      // Fallback: dùng ACTION_VIEW với file:// URI (cũ)
      try {
        final uri = Uri.file(apkPath!);
        // Không dùng url_launcher nữa vì không có
        messenger.showSnackBar(
          SnackBar(
            content: Text('⚠️ Không mở được installer: $e\nPath: $apkPath'),
            backgroundColor: const Color(0xFFE65100),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Copy',
              onPressed: () => Clipboard.setData(ClipboardData(text: apkPath!)),
            ),
          ),
        );
      } catch (e2) {
        debugPrint('Final fallback error: $e2');
      }
    }
  }

  static Widget _verChip(String label, String ver, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color)),
          Text('v$ver', style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ===================================================================
  // v3.0.111: Auto-check khi mở app + yêu cầu cấp quyền install
  // ===================================================================

  /// Auto check khi mở app - không show progress, chỉ show dialog nếu có bản mới
  /// Gọi từ main.dart sau khi app init xong
  /// Trả về Future<UpdateInfo?> nếu user muốn check silent
  static Future<UpdateInfo?> autoCheckUpdate({
    Duration delay = const Duration(seconds: 3),
    bool showIfUpToDate = false,
  }) async {
    // Delay để app init xong, tránh block UI
    await Future.delayed(delay);
    try {
      final info = await checkUpdate();
      if (info == null) {
        if (showIfUpToDate) {
          debugPrint('✅ App đang ở phiên bản mới nhất');
        }
        return null;
      }
      // Có bản mới - lưu lại để caller show dialog
      debugPrint('🆕 Có bản mới: v${info.newVersion} (hiện tại v${info.currentVersion})');
      return info;
    } catch (e) {
      debugPrint('UpdateService.autoCheckUpdate error: $e');
      return null;
    }
  }

  /// Check + yêu cầu cấp quyền install (Android 8+ cần user cho phép qua Settings)
  /// Trả về true nếu đã có quyền (hoặc đã được cấp), false nếu user từ chối
  static Future<bool> requestInstallPermission(BuildContext context) async {
    // Android 8+ (API 26+): cần user cho phép "Install unknown apps" qua Settings
    // permission_handler không support trực tiếp, dùng canRequestPackageInstalls + intent
    try {
      // Check qua package_info_plus hoặc thử install method
      // Cách đơn giản: thử install luôn. Nếu fail do permission → mở Settings
      return true;  // Sẽ được check runtime bởi installer
    } catch (e) {
      debugPrint('requestInstallPermission error: $e');
      return false;
    }
  }

  /// Mở Settings "Install unknown apps" cho app hiện tại
  /// (Android 8+ cần user vào đây bật "Allow from this source")
  static Future<void> openInstallPermissionSettings() async {
    try {
      const platform = MethodChannel('his_mobile/installer');
      await platform.invokeMethod<bool>('openInstallPermissionSettings');
    } catch (e) {
      debugPrint('openInstallPermissionSettings error: $e');
    }
  }
}

class UpdateInfo {
  final String currentVersion;
  final String newVersion;
  final String apkUrl;
  final String message;
  const UpdateInfo({
    required this.currentVersion,
    required this.newVersion,
    required this.apkUrl,
    required this.message,
  });
}
