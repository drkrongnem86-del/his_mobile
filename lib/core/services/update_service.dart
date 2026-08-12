// UpdateService v3.0.97 - Tự động kiểm tra cập nhật từ GitHub
//
// Workflow:
//   1. App mở → gọi UpdateService.checkUpdate()
//   2. GET https://raw.githubusercontent.com/drkrongnem86-del/his_mobile/main/version.json
//   3. So sánh version với app hiện tại
//   4. Nếu mới hơn → hiện dialog "Có bản cập nhật mới"
//   5. User bấm "Đồng ý" → tải APK → save vào Downloads → mở installer
//
// File version.json ở GitHub root:
//   {
//     "version": "3.0.96",
//     "apk_url": "https://github.com/drkrongnem86-del/his_mobile/releases/download/v3.0.96/his_mobile_v3.0.96_arm64.apk",
//     "message": "Mô tả thay đổi"
//   }
//
// v3.0.97: Fix black screen - save APK vào Downloads + dùng FileProvider + dùng platform intent

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String githubOwner = 'drkrongnem86-del';
  static const String githubRepo = 'his_mobile';
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/$githubOwner/$githubRepo/main/version.json';

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
              '⚠️ APK sẽ được tải về thư mục Downloads. Sau đó Android sẽ mở installer - bấm "Cài đặt" để hoàn tất.',
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

  /// Tải APK về Downloads rồi mở installer
  /// v3.0.97: Save vào Downloads/HisMobile/ (user dễ thấy) + log progress
  static Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    String? apkPath;
    bool downloadOk = false;
    String? downloadError;

    // Bước 1: Tải APK
    try {
      // Lưu vào Downloads/HisMobile/ (external storage - user dễ thấy)
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        // Android: dùng /storage/emulated/0/Download/HisMobile/
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          // ext = /storage/emulated/0/Android/data/<pkg>/files
          // Lên 1 cấp để tới /storage/emulated/0/
          final parent = ext.parent.parent.parent;
          downloadsDir = Directory('${parent.path}/Download/HisMobile');
        }
      }
      downloadsDir ??= await getApplicationDocumentsDirectory();

      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      apkPath = '${downloadsDir.path}/HIS_MOBILE_v${info.newVersion}.apk';

      // Xóa file cũ nếu có
      final oldFile = File(apkPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }

      double progress = 0;
      // Hiện dialog progress
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (ctx, setSt) {
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
                    const SizedBox(height: 4),
                    Text(
                      '📁 $apkPath',
                      style: const TextStyle(fontSize: 9, color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      await Dio().download(
        info.apkUrl,
        apkPath,
        onReceiveProgress: (received, total) {
          if (total > 0) progress = received / total;
        },
      );
      downloadOk = true;
      debugPrint('✅ APK downloaded: $apkPath (${await File(apkPath).length()} bytes)');
    } catch (e) {
      downloadError = e.toString();
      debugPrint('❌ UpdateService download error: $e');
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // Đóng progress dialog

    if (!downloadOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Tải APK lỗi: $downloadError'),
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // Bước 2: Mở installer
    _openInstaller(context, apkPath!, info.newVersion);
  }

  /// Mở Android installer để cài APK
  /// v3.0.97: Dùng cả open_filex + intent fallback
  static Future<void> _openInstaller(BuildContext context, String apkPath, String version) async {
    // Verify file tồn tại
    final file = File(apkPath);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ File APK không tồn tại: $apkPath'),
            backgroundColor: const Color(0xFFC62828),
          ),
        );
      }
      return;
    }

    final sizeKB = (await file.length()) ~/ 1024;
    debugPrint('📦 APK file: $apkPath ($sizeKB KB)');

    // Thử open_filex trước (phổ biến nhất)
    try {
      final result = await OpenFilex.open(
        apkPath,
        type: 'application/vnd.android.package-archive',
      );
      debugPrint('OpenFilex result: ${result.type} - ${result.message}');
      if (result.type == ResultType.done) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📲 Đang mở installer - bấm "Cài đặt" khi Android hỏi'),
              backgroundColor: Color(0xFF2E7D32),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('OpenFilex failed: $e');
    }

    // Fallback: dùng url_launcher với file:// URI
    try {
      final uri = Uri.file(apkPath);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📲 Đã mở installer bằng app khác'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('launchUrl failed: $e');
    }

    // Fallback cuối: dùng ACTION_INSTALL_PACKAGE intent qua platform channel
    try {
      const platform = MethodChannel('his_mobile/installer');
      await platform.invokeMethod('installApk', {'path': apkPath});
    } catch (e) {
      debugPrint('Platform channel failed: $e');
    }

    // Tất cả fail → báo user mở file manager
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning, color: Color(0xFFEF6C00)),
            SizedBox(width: 8),
            Text('Mở installer thủ công'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Đã tải APK nhưng không mở được installer tự động.'),
              const SizedBox(height: 8),
              const Text('Mở thủ công:'),
              const SizedBox(height: 4),
              Text(
                '1. Mở app "Files" / "My Files" trên điện thoại\n'
                '2. Vào Downloads/HisMobile/\n'
                '3. Bấm vào file HIS_MOBILE_v$version.apk\n'
                '4. Bấm "Cài đặt"',
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '📁 $apkPath\n($sizeKB KB)',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFE65100)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: apkPath));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('📋 Đã copy path vào clipboard')),
                );
              },
              child: const Text('Copy path'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
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
