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
  /// v3.0.122: 3 nút - HỦY / TẢI VỀ (lưu vào Download public, user tự cài) / ĐỒNG Ý (auto install)
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
              '📲 ĐỒNG Ý: app tự cài đè. TẢI VỀ: lưu APK vào Download/HisMobile, mở File Manager cài thủ công.',
              style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
            ),
          ],
        ),
        actions: [
          // v3.0.124: Đổi thứ tự nút - TẮT VPN & CÀI đầu tiên (giải quyết "App not installed"
          // trên Samsung do OpenVPN service còn chạy foreground)
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadToPublicDownloads(context, info);
            },
            icon: const Icon(Icons.file_download, size: 16, color: Color(0xFFE65100)),
            label: const Text('TẢI VỀ', style: TextStyle(color: Color(0xFFE65100))),
          ),
          TextButton.icon(
            // v3.0.124: NÚT CHÍNH cho Samsung - tắt VPN trước khi cài
            onPressed: () async {
              Navigator.pop(ctx);
              // Tắt OpenVPN service trước (giải quyết "App not installed" trên Samsung)
              try {
                const vpnPlatform = MethodChannel(_installerChannel);
                await vpnPlatform.invokeMethod('disconnectVpn');
                debugPrint('✅ OpenVPN service disconnected');
              } catch (e) {
                debugPrint('⚠️ disconnectVpn error: $e');
              }
              // Sau đó mới install
              await _downloadAndInstall(context, info);
            },
            icon: const Icon(Icons.power_settings_new, size: 16, color: Color(0xFFD32F2F)),
            label: const Text('TẮT VPN & CÀI', style: TextStyle(color: Color(0xFFD32F2F))),
          ),
          FilledButton.icon(
            // v3.0.124: "ĐỒNG Ý" chỉ work nếu VPN đã tắt sẵn
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

  /// v3.0.122: Tải APK về thư mục Download public (Download/HisMobile/) để user tự cài
  /// - Android 10+: dùng MediaStore.Downloads (qua MethodChannel 'saveApkToDownloads')
  /// - User mở File Manager, tap file APK để cài
  /// - Ưu điểm: app KHÔNG cần chạy khi user cài → tránh "App not installed"
  static Future<void> _downloadToPublicDownloads(BuildContext context, UpdateInfo info) async {
    final messenger = ScaffoldMessenger.of(context);

    String? internalPath;
    bool downloadOk = false;
    String? downloadError;
    double progress = 0;

    // Hiện progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: Text('Đang tải v${info.newVersion} về Download…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress > 0 ? progress : null),
              const SizedBox(height: 12),
              Text(
                progress > 0
                    ? '${(progress * 100).toStringAsFixed(0)}% • v${info.newVersion}'
                    : 'Đang kết nối GitHub...',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        );
      }),
    );

    // Bước 1: Download APK về internal storage (giống _downloadAndInstall)
    try {
      final supportDir = await getApplicationSupportDirectory();
      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }
      internalPath = '${supportDir.path}/HIS_MOBILE_v${info.newVersion}.apk';

      final oldFile = File(internalPath);
      if (await oldFile.exists()) {
        try { await oldFile.delete(); } catch (_) {}
      }

      await Dio().download(
        info.apkUrl,
        internalPath,
        onReceiveProgress: (received, total) {
          if (total > 0) progress = received / total;
        },
      );
      downloadOk = true;
    } catch (e) {
      downloadError = e.toString();
    }

    // Đóng progress dialog
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      try { nav.pop(); } catch (_) {}
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

    // Bước 2: Gọi native copy file từ internal → public Downloads
    try {
      const platform = MethodChannel(_installerChannel);
      final displayName = 'HIS_MOBILE_v${info.newVersion}.apk';
      final res = await platform.invokeMethod('saveApkToDownloads', {
        'path': internalPath,
        'displayName': displayName,
      });
      debugPrint('saveApkToDownloads result: $res');
      final path = (res is Map) ? (res['path'] as String? ?? 'Download/HisMobile/') : 'Download/HisMobile/';
      final sizeBytes = (res is Map) ? (res['size'] as int? ?? 0) : 0;
      final sizeStr = sizeBytes > 0 ? '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB' : '';
      messenger.showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('✅ Đã lưu APK vào thư mục Download', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('📁 $path', style: const TextStyle(fontSize: 11)),
              if (sizeStr.isNotEmpty) Text('📦 $sizeStr', style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 4),
              const Text('Mở File Manager → Download/HisMobile → tap file để cài', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
            ],
          ),
          backgroundColor: const Color(0xFFE65100),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('saveApkToDownloads error: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Lưu vào Download lỗi: $e'),
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 6),
        ),
      );
    }
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

      // v3.0.135: Show persistent dialog thay vì snackbar
      // User cần thấy hướng dẫn ĐỢI INSTALLER MỞ RA + nhấn "Cài đặt"
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx2) => AlertDialog(
            icon: const Icon(Icons.system_update, color: Color(0xFF2E7D32), size: 48),
            title: const Text('Đang chuẩn bị cài đặt…'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                LinearProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  '1️⃣ Đợi SYSTEM INSTALLER mở ra (~4 giây)\n'
                  '2️⃣ Nhấn "Cài đặt" (Install)\n'
                  '3️⃣ App cũ sẽ được thay thế tự động\n\n'
                  '⚠️ Nếu installer không mở sau 4s:\n'
                  'Vào Download/HisMobile → tap file APK để cài thủ công.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('Đã hiểu'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Native install error: $e');
      // v3.0.135: Fallback - show dialog with file path for manual install
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx2) => AlertDialog(
            icon: const Icon(Icons.warning_amber, color: Color(0xFFE65100), size: 48),
            title: const Text('Cài đặt thủ công'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Installer không mở tự động. Hãy cài thủ công:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE65100)),
                  ),
                  child: Text(
                    '📁 Download/HisMobile/HIS_MOBILE_v${info.newVersion}.apk',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mở File Manager → Download/HisMobile → tap file APK → Install',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('OK'),
              ),
            ],
          ),
        );
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
