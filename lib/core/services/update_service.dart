// UpdateService v3.0.93 - Tự động kiểm tra cập nhật từ GitHub
//
// Workflow:
//   1. App mở → gọi UpdateService.checkUpdate()
//   2. GET https://raw.githubusercontent.com/drkrongnem86-del/his_mobile/main/version.json
//   3. So sánh version với app hiện tại
//   4. Nếu mới hơn → hiện dialog "Có bản cập nhật mới"
//   5. User bấm "Đồng ý" → tải APK → mở installer
//
// File version.json ở GitHub root:
//   {
//     "version": "3.0.94",
//     "apk_url": "https://github.com/drkrongnem86-del/his_mobile/releases/download/v3.0.94/his_mobile_v3.0.94_arm64.apk",
//     "message": "Fix bug + cải tiến"
//   }
//
// Lưu ý:
//   - APK phải ký bằng cùng keystore (release key, không phải debug)
//   - Không đưa GitHub Token vào app (chỉ đọc public file)
//   - User phải tự bấm "Cài đặt" khi Android hiện prompt (không thể tự cài)

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  // GitHub repo (đã có sẵn)
  static const String githubOwner = 'drkrongnem86-del';
  static const String githubRepo = 'his_mobile';
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/$githubOwner/$githubRepo/main/version.json';

  /// Kiểm tra có bản cập nhật mới không
  /// Returns: null nếu không có update, hoặc UpdateInfo
  static Future<UpdateInfo?> checkUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version; // vd: "3.0.93"
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

  /// So sánh version "a.b.c" với "x.y.z" - a > x hoặc b > y hoặc c > z
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
              '⚠️ Sau khi tải, Android sẽ hiện popup hỏi "Cài đặt" - bạn cần bấm Cài đặt để hoàn tất.',
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

  /// Tải APK + mở installer
  static Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    try {
      final dir = await getTemporaryDirectory();
      final apkPath = '${dir.path}/HIS_MOBILE_v${info.newVersion}.apk';
      // Nếu file đã có (down trước đó) → xóa
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
                      progress > 0 ? '${(progress * 100).toStringAsFixed(0)}%' : 'Đang tải...',
                      style: const TextStyle(fontSize: 13),
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
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Đóng progress dialog
      // Mở installer
      final result = await OpenFilex.open(
        apkPath,
        type: 'application/vnd.android.package-archive',
      );
      debugPrint('OpenFilex result: ${result.type} - ${result.message}');
      if (!context.mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Tải xong nhưng không mở được installer: ${result.message}'),
            backgroundColor: const Color(0xFFEF6C00),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('UpdateService download error: $e');
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Đóng progress dialog nếu còn
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Không tải được bản cập nhật: $e'),
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 4),
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
