// Generic ClinicalNoteScreen - form nhập liệu + danh sách notes cũ của BN.
// Dùng cho mọi loại clinical note: sinh hiệu, đơn thuốc, tờ điều trị, CLS, bàn giao, phiếu chăm sóc, dịch truyền, thủ thuật, khám bệnh.
// Data lưu local qua ClinicalNotesService → hiển thị lịch sử.
import 'package:flutter/material.dart';
import 'package:his_mobile/data/local/clinical_notes_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/services/phieu_save_service.dart';
import 'package:his_mobile/presentation/widgets/patient_header.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

/// Định nghĩa 1 field trong form
class NoteField {
  final String key;          // key lưu trong data map
  final String label;
  final String? hint;
  final String type;         // 'text' | 'multiline' | 'number' | 'dropdown' | 'checklist' | 'time'
  final List<String>? options; // dropdown options
  final bool required;
  final String? unit;        // vd 'mmHg', 'lần/phút'
  final int? maxLines;
  final IconData? icon;
  final Color? color;

  const NoteField({
    required this.key,
    required this.label,
    this.hint,
    this.type = 'text',
    this.options,
    this.required = false,
    this.unit,
    this.maxLines,
    this.icon,
    this.color,
  });
}

class ClinicalNoteScreen extends StatefulWidget {
  final ClinicalNoteType type;
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;
  final List<NoteField> fields;

  const ClinicalNoteScreen({
    super.key,
    required this.type,
    required this.patient,
    required this.department,
    required this.fields,
  });

  @override
  State<ClinicalNoteScreen> createState() => _ClinicalNoteScreenState();
}

class _ClinicalNoteScreenState extends State<ClinicalNoteScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String?> _dropdownValues = {};
  final Map<String, List<bool>> _checklistValues = {};
  final _noteCtrl = TextEditingController();
  final _notesService = ClinicalNotesService.instance;
  final _auth = ThongkeAuthService();

  bool _saving = false;
  List<ClinicalNote> _history = [];
  bool _loadingHistory = true;

  String _g(String k1, [String? k2, String? k3]) =>
      (widget.patient[k1] ?? widget.patient[k2 ?? ''] ?? widget.patient[k3 ?? ''] ?? '').toString();

  String get _patientCode {
    final c = _g('TDL_TREATMENT_CODE', 'treatment_code');
    if (c.isNotEmpty) return c;
    return _g('TDL_PATIENT_CODE', 'tdl_patient_code');
  }

  String get _patientName => _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME');

  String get _createdBy => _auth.currentUsername ?? 'admin';

  @override
  void initState() {
    super.initState();
    // Init controllers
    for (final f in widget.fields) {
      _ctrls[f.key] = TextEditingController();
      if (f.type == 'dropdown') {
        _dropdownValues[f.key] = null;
      }
      if (f.type == 'checklist' && f.options != null) {
        _checklistValues[f.key] = List.filled(f.options!.length, false);
      }
    }
    _loadHistory();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final list = await _notesService.getNotesForPatientAndType(_createdBy, _patientCode, widget.type);
    if (!mounted) return;
    setState(() {
      _history = list;
      _loadingHistory = false;
    });
  }

  Future<void> _save() async {
    // Validate required fields
    for (final f in widget.fields) {
      if (f.required) {
        if (f.type == 'dropdown' && (_dropdownValues[f.key] == null || _dropdownValues[f.key]!.isEmpty)) {
          _showError('${f.label} chưa chọn');
          return;
        }
        if (f.type != 'dropdown' && f.type != 'checklist' && (_ctrls[f.key]?.text.trim().isEmpty ?? true)) {
          _showError('${f.label} chưa nhập');
          return;
        }
        if (f.type == 'checklist' && (f.options == null || !_checklistValues[f.key]!.contains(true))) {
          _showError('${f.label} chưa chọn mục nào');
          return;
        }
      }
    }

    setState(() => _saving = true);

    final data = <String, dynamic>{};
    for (final f in widget.fields) {
      if (f.type == 'dropdown') {
        data[f.key] = _dropdownValues[f.key] ?? '';
      } else if (f.type == 'checklist' && f.options != null) {
        final checked = <String>[];
        for (int i = 0; i < f.options!.length; i++) {
          if (_checklistValues[f.key]?[i] == true) {
            checked.add(f.options![i]);
          }
        }
        data[f.key] = checked;
      } else {
        data[f.key] = _ctrls[f.key]?.text.trim() ?? '';
      }
    }

    final now = DateTime.now();
    final note = ClinicalNote(
      id: '${widget.type.key}_${now.millisecondsSinceEpoch}',
      type: widget.type,
      patientCode: _patientCode,
      patientName: _patientName,
      departmentCode: widget.department['code']?.toString() ?? '',
      departmentName: widget.department['name']?.toString() ?? '',
      data: data,
      note: _noteCtrl.text.trim(),
      createdBy: _createdBy,
      createdAt: now,
    );

    try {
      await _notesService.addNote(_createdBy, note);
      // Reset form
      for (final c in _ctrls.values) c.clear();
      for (final k in _dropdownValues.keys) {
        _dropdownValues[k] = null;
      }
      for (final k in _checklistValues.keys) {
        if (_checklistValues[k] != null) {
          for (int i = 0; i < _checklistValues[k]!.length; i++) {
            _checklistValues[k]![i] = false;
          }
        }
      }
      _noteCtrl.clear();
      await _loadHistory();
      if (!mounted) return;
      // Lưu thành công — snackbar có icon lớn + action xem
      final newCount = _history.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 80),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '✅ ĐÃ LƯU PHIẾU',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  Text(
                    '${widget.type.label} - BN $_patientName (tổng $newCount)',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      _showError('Lỗi lưu: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// v3.0.58: Lưu local + đẩy EMR (Lưu ký hoặc Ký CA)
  /// - useVnptSignature=true → Ký CA qua PhieuSaveService
  /// - useVnptSignature=false → Lưu ký (signature tay) qua PhieuSaveService
  /// Workflow:
  ///   1. Gọi _save() để lưu local + validate
  ///   2. Build data từ _ctrls (giống _save)
  ///   3. Gọi PhieuSaveService.save() với mode=signed, useVnptSignature
  ///   4. Show kết quả
  Future<void> _saveAndPushEmr({required bool useVnptSignature}) async {
    // Bước 1: Lưu local trước (validate + lưu)
    await _save();
    if (!mounted || _saving) return; // _save có thể đã set _saving=true chưa kịp reset
    // Đợi _save xong (poll _saving)
    while (_saving) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    if (!mounted) return;

    // Bước 2: Build data
    final data = <String, dynamic>{};
    for (final f in widget.fields) {
      if (f.type == 'dropdown') {
        data[f.key] = _dropdownValues[f.key] ?? '';
      } else if (f.type == 'checklist' && f.options != null) {
        final checked = <String>[];
        for (int i = 0; i < f.options!.length; i++) {
          if (_checklistValues[f.key]?[i] == true) checked.add(f.options![i]);
        }
        data[f.key] = checked;
      } else {
        data[f.key] = _ctrls[f.key]?.text.trim() ?? '';
      }
    }

    // Bước 3: Gọi PhieuSaveService
    try {
      setState(() => _saving = true);
      final result = await PhieuSaveService.instance.save(
        mode: PhieuSaveMode.signed,
        input: PhieuSaveInput(
          patient: widget.patient,
          formName: widget.type.label,
          formData: data,
          useVnptSignature: useVnptSignature,
          workingDeptName: widget.department['name']?.toString(),
          roomTypeCode: widget.type.key.toUpperCase().substring(0, 2),
        ),
        saveLocalHook: (input) async {
          // Đã lưu local trong _save() rồi → trả true
          return true;
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.displayMessage),
        backgroundColor: result.success && result.emrPushed ? Colors.green.shade700 : Colors.orange.shade700,
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      _showError('Lỗi đẩy EMR: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('⚠️ $m'),
      backgroundColor: Colors.red.shade700,
    ));
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
  }

  void _confirmDelete(ClinicalNote n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá phiếu này?'),
        content: Text('Phiếu lúc ${_formatTime(n.createdAt)} sẽ bị xoá vĩnh viễn.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _notesService.deleteNote(_createdBy, n.id);
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xoá')));
      }
    }
  }

  /// Render giá trị data theo field để hiển thị trong history
  Widget _renderHistoryValue(NoteField f, dynamic v) {
    if (v == null || (v is String && v.isEmpty)) return const SizedBox.shrink();
    String label = '${f.label}: ';
    Widget valueWidget;
    if (v is List) {
      if (v.isEmpty) return const SizedBox.shrink();
      valueWidget = Wrap(
        spacing: 4, runSpacing: 4,
        children: v.map<Widget>((item) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
          child: Text(item.toString(), style: const TextStyle(fontSize: 11, color: Colors.indigo)),
        )).toList(),
      );
    } else {
      final str = v.toString();
      if (f.unit != null && f.unit!.isNotEmpty && !str.contains(f.unit!)) {
        valueWidget = Text('$str ${f.unit}', style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600));
      } else {
        valueWidget = Text(str, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(widget.type.colorValue);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Text(widget.type.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.type.label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(department: widget.department['name']?.toString()),
          PatientHeader(patient: widget.patient, department: widget.department, accent: accent),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                // Form nhập liệu
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                            child: Icon(Icons.edit_note, color: accent, size: 18),
                          ),
                          const SizedBox(width: 8),
                          const Text('NHẬP PHIẾU MỚI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ],
                      ),
                      const Divider(height: 16),
                      // Render fields
                      ...widget.fields.map((f) => _buildField(f, accent)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteCtrl,
                        minLines: 2,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.black, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Ghi chú thêm (tuỳ chọn)',
                          labelStyle: const TextStyle(color: Colors.indigo, fontSize: 12),
                          hintText: 'VD: theo dõi sát SA 30 phút / lần...',
                          hintStyle: const TextStyle(color: Colors.black38, fontSize: 12),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // v3.0.58: 3 nút save - [Lưu] [Lưu ký] [Ký CA] theo mẫu Bàn giao BN
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.save_outlined, size: 16),
                              label: const Text('Lưu', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                side: BorderSide(color: Colors.grey.shade400),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _saving ? null : () => _saveAndPushEmr(useVnptSignature: false),
                              icon: const Icon(Icons.draw, size: 16),
                              label: const Text('Lưu ký', style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _saving ? null : () => _saveAndPushEmr(useVnptSignature: true),
                              icon: const Icon(Icons.verified_user, size: 16),
                              label: const Text('Ký CA', style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // History
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.history, color: Colors.indigo, size: 18),
                          ),
                          const SizedBox(width: 8),
                          Text('LỊCH SỬ (${_history.length} phiếu)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const Spacer(),
                          if (_history.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Xoá tất cả?'),
                                    content: Text('Sẽ xoá ${_history.length} phiếu ${widget.type.label.toLowerCase()} của BN $_patientName'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () async {
                                          for (final n in _history) {
                                            await _notesService.deleteNote(_createdBy, n.id);
                                          }
                                          if (mounted) Navigator.pop(context);
                                          await _loadHistory();
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xoá tất cả')));
                                          }
                                        },
                                        child: const Text('Xoá hết'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              icon: const Icon(Icons.delete_sweep, size: 16),
                              label: const Text('Xoá hết'),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                            ),
                        ],
                      ),
                      const Divider(height: 16),
                      if (_loadingHistory)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (_history.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.inbox_outlined, size: 36, color: Colors.black26),
                                SizedBox(height: 8),
                                Text('Chưa có phiếu nào', style: TextStyle(color: Colors.black54, fontSize: 13)),
                                SizedBox(height: 4),
                                Text('Tạo phiếu mới ở trên để bắt đầu', style: TextStyle(color: Colors.black45, fontSize: 11)),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._history.asMap().entries.map((entry) {
                          final i = entry.key;
                          final n = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
                            decoration: BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                                      child: Text('#${_history.length - i}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _formatTime(n.createdAt),
                                        style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Text(n.createdBy, style: const TextStyle(color: Colors.indigo, fontSize: 10)),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      iconSize: 16,
                                      icon: const Icon(Icons.close, color: Colors.black45, size: 16),
                                      tooltip: 'Xoá',
                                      onPressed: () => _confirmDelete(n),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ...widget.fields
                                    .map((f) => _renderHistoryValue(f, n.data[f.key]))
                                    .where((w) => w is! SizedBox),
                                if (n.note.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6)),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.sticky_note_2, size: 12, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(n.note, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black87))),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(NoteField f, Color accent) {
    Widget field;
    switch (f.type) {
      case 'multiline':
        field = TextField(
          controller: _ctrls[f.key],
          minLines: 2,
          maxLines: f.maxLines ?? 4,
          style: const TextStyle(color: Colors.black, fontSize: 13),
          decoration: _dec(f, accent),
        );
        break;
      case 'number':
        field = TextField(
          controller: _ctrls[f.key],
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: _dec(f, accent),
        );
        break;
      case 'dropdown':
        field = DropdownButtonFormField<String>(
          initialValue: _dropdownValues[f.key],
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: _dec(f, accent),
          items: (f.options ?? [])
              .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (v) => setState(() => _dropdownValues[f.key] = v),
        );
        break;
      case 'checklist':
        final options = f.options ?? [];
        field = Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade50,
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (f.icon != null) Icon(f.icon, size: 14, color: f.color ?? Colors.indigo),
                  const SizedBox(width: 4),
                  Text(f.label, style: TextStyle(color: f.color ?? Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
                  if (f.required)
                    const Text(' *', style: TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6, runSpacing: 4,
                children: List.generate(options.length, (i) {
                  final checked = _checklistValues[f.key]?[i] ?? false;
                  return FilterChip(
                    label: Text(options[i], style: TextStyle(fontSize: 11, color: checked ? Colors.white : Colors.black87)),
                    selected: checked,
                    onSelected: (v) => setState(() {
                      final list = _checklistValues[f.key];
                      if (list != null && i < list.length) list[i] = v;
                    }),
                    selectedColor: f.color ?? Colors.indigo,
                    backgroundColor: Colors.white,
                    checkmarkColor: Colors.white,
                    side: BorderSide(color: checked ? (f.color ?? Colors.indigo) : Colors.grey.shade400),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }),
              ),
            ],
          ),
        );
        break;
      default: // text
        field = TextField(
          controller: _ctrls[f.key],
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: _dec(f, accent),
        );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: field,
    );
  }

  InputDecoration _dec(NoteField f, Color accent) {
    return InputDecoration(
      labelText: (f.label) + (f.required ? ' *' : ''),
      labelStyle: TextStyle(color: f.color ?? accent, fontSize: 12, fontWeight: FontWeight.w600),
      hintText: f.hint,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 12),
      prefixIcon: f.icon != null ? Icon(f.icon, size: 18, color: f.color ?? accent) : null,
      suffixText: f.unit,
      suffixStyle: const TextStyle(color: Colors.black54, fontSize: 12),
      filled: true,
      fillColor: Colors.grey.shade50,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accent, width: 1.5)),
    );
  }
}
