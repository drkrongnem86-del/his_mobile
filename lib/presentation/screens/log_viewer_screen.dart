// v3.0.38: LogViewerScreen - Xem log upload + export IT
// - Hiển thị log hôm nay (human-readable)
// - Nút "Làm mới" - reload log
// - Nút "Chia sẻ" - share file log qua email/chat
// - Nút "Export JSON" - export file JSON cho IT
// - Stats: success/failed/retry count
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:his_mobile/data/services/upload_log_service.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  List<String> _lines = [];
  Map<String, int> _stats = {};
  String _logPath = '';
  String _jsonPath = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lines = await UploadLogService.instance.readToday();
      final stats = await UploadLogService.instance.getTodayStats();
      final logPath = await UploadLogService.instance.getLogFilePath();
      final jsonPath = await UploadLogService.instance.getJsonLogFilePath();
      if (!mounted) return;
      setState(() {
        _lines = lines.reversed.toList(); // Mới nhất lên đầu
        _stats = stats;
        _logPath = logPath;
        _jsonPath = jsonPath;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _shareLog() async {
    try {
      // v3.0.60: Nếu _logPath rỗng hoặc file chưa tồn tại → tạo file rỗng để share
      String filePath = _logPath;
      if (filePath.isEmpty) {
        filePath = await UploadLogService.instance.getLogFilePath();
        _logPath = filePath;
      }
      final file = File(filePath);
      if (!await file.exists()) {
        // v3.0.60: Tạo file rỗng nếu chưa có (để share_plus không lỗi)
        await file.create(recursive: true);
        await file.writeAsString('# HIS Mobile EMR Upload Log\n# File tạo: ${DateTime.now()}\n# Chưa có log nào - thử push 1 EMR trước.\n');
        _showSnack('📄 Tạo file log rỗng (chưa có log nào - push EMR trước sẽ có data)', isError: false);
      }
      // v3.0.58: Dùng share_plus để share file qua Zalo/Facebook/Email/GDrive
      try {
        final result = await Share.shareXFiles(
          [XFile(filePath, mimeType: 'text/plain', name: 'his_mobile_emr_log.txt')],
          text: 'HIS Mobile - EMR Upload Log (${DateTime.now().toString().substring(0, 19)})',
          subject: 'HIS Mobile EMR Upload Log',
        );
        if (result.status == ShareResultStatus.success) {
          _showSnack('✅ Đã share log thành công', isError: false);
          return;
        }
      } catch (e) {
        // Fallback: copy path vào clipboard
        await Clipboard.setData(ClipboardData(text: filePath));
        _showSnack('📋 Đã copy path vào clipboard (share_plus fail: $e)', isError: false);
        return;
      }
      // User hủy share
      await Clipboard.setData(ClipboardData(text: filePath));
      _showSnack('📋 Đã copy path vào clipboard: $filePath', isError: false);
    } catch (e) {
      _showSnack('Lỗi share: $e', isError: true);
    }
  }

  Future<void> _clearLog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.delete_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('Xóa toàn bộ log?'),
        ]),
        content: const Text(
          'Tất cả log upload EMR (request/response/retry/metric) sẽ bị xóa vĩnh viễn.\n\n'
          'Hành động này không thể hoàn tác. Nên export JSON trước nếu cần gửi IT.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa hết'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await UploadLogService.instance.clearAll();
    _showSnack(ok ? '🗑️ Đã xóa toàn bộ log' : '❌ Xóa log thất bại', isError: !ok);
    _load();
  }

  Future<void> _exportJson() async {
    try {
      final json = await UploadLogService.instance.exportTodayAsJson();
      // Lưu vào file Downloads để user dễ share
      try {
        final dir = await getApplicationDocumentsDirectory();
        final exportFile = File('${dir.path}/upload_export_${DateTime.now().millisecondsSinceEpoch}.json');
        await exportFile.writeAsString(json);
        await Clipboard.setData(ClipboardData(text: exportFile.path));
        _showSnack('✅ Đã export JSON: ${exportFile.path}', isError: false);
      } catch (e) {
        // Fallback: chỉ copy JSON vào clipboard
        await Clipboard.setData(ClipboardData(text: json));
        _showSnack('✅ Đã copy JSON vào clipboard (${json.length} chars)', isError: false);
      }
    } catch (e) {
      _showSnack('Lỗi export: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      duration: const Duration(seconds: 4),
    ));
  }

  Color _lineColor(String line) {
    if (line.contains(' | RESPONSE | ') && line.contains('Success=true')) return Colors.green.shade100;
    if (line.contains(' | RESPONSE | ') && line.contains('Success=false')) return Colors.red.shade100;
    if (line.contains(' | RETRY#')) return Colors.orange.shade100;
    if (line.contains(' | QUEUE | ')) return Colors.blue.shade100;
    if (line.contains(' | METRIC | ')) return Colors.purple.shade100;
    return Colors.transparent;
  }

  IconData _lineIcon(String line) {
    if (line.contains(' | REQUEST | ')) return Icons.upload;
    if (line.contains(' | RESPONSE | ') && line.contains('Success=true')) return Icons.check_circle;
    if (line.contains(' | RESPONSE | ') && line.contains('Success=false')) return Icons.error;
    if (line.contains(' | RETRY#')) return Icons.refresh;
    if (line.contains(' | QUEUE | ')) return Icons.queue;
    if (line.contains(' | METRIC | ')) return Icons.analytics;
    return Icons.info;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Upload EMR', style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _load,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'share') _shareLog();
              if (v == 'export') _exportJson();
              if (v == 'copy_path') {
                Clipboard.setData(ClipboardData(text: _logPath));
                _showSnack('📋 Đã copy: $_logPath');
              }
              if (v == 'clear') _clearLog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'share',
                child: Row(children: [Icon(Icons.share, size: 18), SizedBox(width: 8), Text('Chia sẻ log')]),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(children: [Icon(Icons.code, size: 18), SizedBox(width: 8), Text('Export JSON')]),
              ),
              const PopupMenuItem(
                value: 'copy_path',
                child: Row(children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('Copy path')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Xóa log', style: TextStyle(color: Colors.red))]),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats header
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statChip('Request', _stats['request'] ?? 0, Colors.blue),
                _statChip('Success', _stats['success'] ?? 0, Colors.green),
                _statChip('Failed', _stats['failed'] ?? 0, Colors.red),
                _statChip('Retry', _stats['retry'] ?? 0, Colors.orange),
              ],
            ),
          ),
          // Path info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.grey.shade50,
            child: Text(
              _logPath.isEmpty
                  ? '📁 (đang tải...)'
                  : '📁 $_logPath',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          // List log
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Lỗi: $_error', style: const TextStyle(color: Colors.red)))
                    : _lines.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.inbox, size: 64, color: Colors.black26),
                                const SizedBox(height: 12),
                                const Text('Chưa có log hôm nay',
                                    style: TextStyle(color: Colors.black45)),
                                const SizedBox(height: 8),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    'Push 1 EMR (Lưu ký) trước, log sẽ xuất hiện ở đây.\n'
                                    'Nếu cần gửi IT để debug, bấm ⋮ → Chia sẻ log.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black38, fontSize: 12, height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(4),
                            itemCount: _lines.length,
                            itemBuilder: (_, i) {
                              final line = _lines[i];
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 1),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _lineColor(line),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(_lineIcon(line), size: 14, color: Colors.black54),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        line,
                                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
