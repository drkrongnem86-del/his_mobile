// v3.0.85: YTeSoListScreen - Generic list screen cho các chức năng Y tế số
//
// Hiển thị danh sách đẹp từ API Y Tế Số:
//   - Header: tên chức năng + mô tả + số record
//   - List: mỗi item là 1 record, với field extractor
//   - Empty state: không có dữ liệu
//   - Error state: lỗi mạng / API
//   - Pull to refresh
//   - Tap item: mở detail JSON
//
// Dùng cho: Y lệnh, Điều dưỡng, Vấn đề, Phiếu bàn giao, Tài liệu BN, ...

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:his_mobile/data/api/y_te_so_extended_service.dart';

/// Định nghĩa cách hiển thị 1 record
class YTeSoListField {
  final String label;
  final dynamic Function(dynamic) getValue;
  final TextStyle? style;
  const YTeSoListField(this.label, this.getValue, {this.style});
}

class YTeSoListScreen extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  /// Hàm gọi API
  final Future<YTeSoApiResult> Function() fetchData;

  /// Extractor: từ response -> List các record
  final List<dynamic> Function(YTeSoApiResult) extractRecords;

  /// Hiển thị mỗi record - list các field
  final List<YTeSoListField> Function(dynamic record) recordFields;

  /// Optional: tiêu đề chính của record (line 1, bold)
  final String Function(dynamic record)? recordTitle;

  /// Optional: subtitle (line 2, gray)
  final String Function(dynamic record)? recordSubtitle;

  const YTeSoListScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.fetchData,
    required this.extractRecords,
    required this.recordFields,
    this.recordTitle,
    this.recordSubtitle,
  });

  @override
  State<YTeSoListScreen> createState() => _YTeSoListScreenState();
}

class _YTeSoListScreenState extends State<YTeSoListScreen> {
  final _ext = YTeSoExtendedService.instance;
  bool _loading = true;
  String? _error;
  List<dynamic> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.fetchData();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success) {
        _records = widget.extractRecords(r);
        _error = null;
      } else {
        _error = r.message;
        _records = [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.description,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
        backgroundColor: widget.color,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: _loading ? null : () => _load(force: true),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Chưa có dữ liệu ${widget.title.toLowerCase()}',
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return Column(
      children: [
        Container(
          color: widget.color.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: widget.color),
              const SizedBox(width: 6),
              Text(
                '${_records.length} bản ghi',
                style: TextStyle(
                    fontSize: 12,
                    color: widget.color,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _showJsonRaw,
                icon: const Icon(Icons.code, size: 14),
                label: const Text('JSON'),
                style: TextButton.styleFrom(
                  foregroundColor: widget.color,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(force: true),
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _records.length,
              itemBuilder: (ctx, i) => _RecordCard(
                record: _records[i],
                color: widget.color,
                title: widget.recordTitle?.call(_records[i]),
                subtitle: widget.recordSubtitle?.call(_records[i]),
                fields: widget.recordFields(_records[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showJsonRaw() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('JSON: ${widget.title}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(_records),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: const JsonEncoder.withIndent('  ').convert(_records)));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã copy JSON')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng')),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final dynamic record;
  final Color color;
  final String? title;
  final String? subtitle;
  final List<YTeSoListField> fields;
  const _RecordCard({
    required this.record,
    required this.color,
    required this.fields,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null && title!.isNotEmpty)
                Text(title!,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold))
              else
                Text('Record',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 6),
                ...fields.map((f) {
                  final v = f.getValue(record);
                  if (v == null || v.toString().isEmpty || v.toString() == 'null')
                    return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                            fontFamily: f.style?.fontFamily),
                        children: [
                          TextSpan(
                              text: '${f.label}: ',
                              style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500)),
                          TextSpan(text: v.toString(), style: f.style),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title ?? 'Chi tiết'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(record),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: const JsonEncoder.withIndent('  ').convert(record)));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã copy JSON')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng')),
        ],
      ),
    );
  }
}
