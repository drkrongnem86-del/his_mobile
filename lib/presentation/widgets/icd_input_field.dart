// IcdInputField v2.98.5
// Widget nhập ICD-10 chung cho tất cả các mục ICD trong Lập phiếu
// - 2 ô input: Mã ICD (in đỏ) + Tên bệnh
// - Nút "Mở web tra cứu" → mở Icd10WebViewScreen (Firebase hosting)
// - User gõ mã → auto-fill từ webview (bấm "Dùng" trong webview)
// - Có chế độ multi-select (cho icdSuggest) với nút "+ Thêm ICD"
//
// Áp dụng cho:
//   - PhieuFieldType.icd (đơn giản - 1 mã)
//   - PhieuFieldType.icdSuggest (multi-select - nhiều mã)
//   - PhieuFieldType.icdText (kèm text mô tả)
//   - PhieuKhamScreen (chẩn đoán chính)
import 'package:flutter/material.dart';
import 'package:his_mobile/presentation/screens/icd10_webview_screen.dart';

class IcdInputField extends StatefulWidget {
  /// Key để lưu giá trị (vd: 'CHAN_DOAN', 'CHAN_DOAN_SO_BO'...)
  final String fieldKey;

  /// Label hiển thị
  final String label;

  /// Required field
  final bool required;

  /// Cho phép chọn nhiều ICD (cho icdSuggest)
  final bool multiSelect;

  /// Initial values
  final List<IcdValue> initialValues;

  /// Callback khi giá trị thay đổi
  final ValueChanged<List<IcdValue>>? onChanged;

  /// Hint text cho mã
  final String? codeHint;

  /// Hint text cho tên
  final String? nameHint;

  const IcdInputField({
    super.key,
    required this.fieldKey,
    required this.label,
    this.required = false,
    this.multiSelect = false,
    this.initialValues = const [],
    this.onChanged,
    this.codeHint,
    this.nameHint,
  });

  @override
  State<IcdInputField> createState() => _IcdInputFieldState();
}

class IcdValue {
  final String code;
  final String name;

  const IcdValue({required this.code, required this.name});

  Map<String, String> toJson() => {'code': code, 'name': name};

  factory IcdValue.fromJson(Map<String, String> json) =>
      IcdValue(code: json['code'] ?? '', name: json['name'] ?? '');

  /// Parse từ string "I10 - Tăng huyết áp" hoặc "I10" hoặc "Tăng huyết áp"
  static IcdValue? tryParse(String s) {
    if (s.trim().isEmpty) return null;
    final t = s.trim();
    final idx = t.indexOf(' - ');
    if (idx > 0) {
      return IcdValue(code: t.substring(0, idx).trim(), name: t.substring(idx + 3).trim());
    }
    // Nếu chỉ có 1 phần, đoán là mã nếu bắt đầu bằng chữ cái + số
    final codeRegex = RegExp(r'^[A-Z]\d{1,3}(\.[A-Z0-9]+)?$');
    if (codeRegex.hasMatch(t)) {
      return IcdValue(code: t, name: '');
    }
    return IcdValue(code: '', name: t);
  }

  String get displayText {
    if (code.isEmpty && name.isEmpty) return '';
    if (code.isEmpty) return name;
    if (name.isEmpty) return code;
    return '$code - $name';
  }

  @override
  String toString() => displayText;
}

class _IcdInputFieldState extends State<IcdInputField> {
  late List<_IcdRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialValues
        .map((v) => _IcdRow(code: v.code, name: v.name))
        .toList();
    if (_rows.isEmpty && !widget.multiSelect) {
      // Đơn giản (1 mã): luôn có 1 row trống
      _rows.add(_IcdRow.empty());
    }
  }

  void _notifyChange() {
    final values = _rows
        .where((r) => r.code.trim().isNotEmpty || r.name.trim().isNotEmpty)
        .map((r) => IcdValue(code: r.codeCtrl.text.trim(), name: r.nameCtrl.text.trim()))
        .toList();
    widget.onChanged?.call(values);
  }

  Future<void> _openWebTraCuu(int rowIdx) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => Icd10WebViewScreen(allowReturnCode: true),
      ),
    );
    if (code != null && code.isNotEmpty) {
      setState(() {
        _rows[rowIdx].codeCtrl.text = code;
      });
      _notifyChange();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã điền mã: $code (gõ tên bệnh nếu cần)'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _addRow() {
    setState(() {
      _rows.add(_IcdRow.empty());
    });
  }

  void _removeRow(int idx) {
    if (_rows.length == 1 && !widget.multiSelect) {
      // Không cho xóa row cuối nếu single-select
      _rows[0].codeCtrl.clear();
      _rows[0].nameCtrl.clear();
    } else {
      setState(() {
        _rows.removeAt(idx);
      });
    }
    _notifyChange();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.medical_services, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Text(
                  widget.label + (widget.required ? ' *' : ''),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (widget.multiSelect)
                  Text(
                    '${_rows.length} mã',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          // List các row ICD
          for (int i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildRow(i),
            ),
          // Nút thêm (chỉ cho multi-select)
          if (widget.multiSelect)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF455A64)),
                label: const Text('Thêm ICD', style: TextStyle(fontSize: 12, color: Color(0xFF455A64))),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(int idx) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Mã ICD (in đỏ, nhỏ - 2 phần)
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _rows[idx].codeCtrl,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Mã ICD',
                    hintText: widget.codeHint ?? 'VD: I10, J18, R50',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => _notifyChange(),
                ),
              ),
              const SizedBox(width: 6),
              // Tên bệnh
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _rows[idx].nameCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Tên bệnh',
                    hintText: widget.nameHint ?? 'VD: Tăng huyết áp',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  onChanged: (_) => _notifyChange(),
                ),
              ),
              // Nút xóa (chỉ cho multi-select, hoặc nếu có nhiều row)
              if (widget.multiSelect && _rows.length > 1)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                  onPressed: () => _removeRow(idx),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Nút mở web tra cứu
          Row(
            children: [
              const Icon(Icons.info_outline, size: 13, color: Colors.indigo),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Gõ mã ICD hoặc bấm nút bên để tra cứu trực tuyến',
                  style: TextStyle(color: Colors.indigo.shade700, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openWebTraCuu(idx),
                icon: const Icon(Icons.open_in_browser, size: 13),
                label: const Text('Mở web tra cứu', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 28),
                  side: const BorderSide(color: Color(0xFF455A64)),
                  foregroundColor: const Color(0xFF455A64),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IcdRow {
  final TextEditingController codeCtrl;
  final TextEditingController nameCtrl;

  _IcdRow({String code = '', String name = ''})
      : codeCtrl = TextEditingController(text: code),
        nameCtrl = TextEditingController(text: name);

  factory _IcdRow.empty() => _IcdRow();

  String get code => codeCtrl.text;
  String get name => nameCtrl.text;

  void dispose() {
    codeCtrl.dispose();
    nameCtrl.dispose();
  }
}
