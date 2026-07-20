import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/data/services/phieu_save_service.dart';

/// Form chung cho các thao tác với BN
/// Cho phép nhập liệu và submit (mock hoặc thật)
class OperationFormScreen extends StatefulWidget {
  final String title;
  final String icon;
  final Color color;
  final Map<String, dynamic> patient;
  final Map<String, List<OpFormField>> fields;

  const OperationFormScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.patient,
    required this.fields,
  });

  @override
  State<OperationFormScreen> createState() => _OperationFormScreenState();
}

class OpFormField {
  final String key;
  final String label;
  final String hint;
  final String type; // 'text', 'number', 'multiline', 'dropdown'
  final List<String>? options;
  final bool required;
  final String? defaultValue;

  const OpFormField({
    required this.key,
    required this.label,
    this.hint = '',
    this.type = 'text',
    this.options,
    this.required = false,
    this.defaultValue,
  });
}

class _OperationFormScreenState extends State<OperationFormScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String?> _errors = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields.values.expand((l) => l)) {
      _ctrls[f.key] = TextEditingController(text: f.defaultValue ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    bool ok = true;
    setState(() {
      _errors.clear();
      for (final f in widget.fields.values.expand((l) => l)) {
        if (f.required && (_ctrls[f.key]?.text.trim().isEmpty ?? true)) {
          _errors[f.key] = 'Vui lòng nhập ${f.label}';
          ok = false;
        }
      }
    });
    return ok;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    // Simulate save
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Đã lưu thành công!'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.pop(context);
    });
  }

  /// v3.0.58: Lưu local + đẩy EMR (Lưu ký hoặc Ký CA) - giống clinical_note
  Future<void> _saveAndPushEmr({required bool useVnptSignature}) async {
    if (!_validate()) return;
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{};
      for (final entry in _formData.entries) {
        data[entry.key] = entry.value;
      }
      final result = await PhieuSaveService.instance.save(
        mode: PhieuSaveMode.signed,
        input: PhieuSaveInput(
          patient: widget.patient,
          formName: widget.title,
          formData: data,
          useVnptSignature: useVnptSignature,
        ),
        saveLocalHook: (input) async => true, // v3.0.58: operation_form chỉ push EMR
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.displayMessage),
        backgroundColor: result.success && result.emrPushed ? Colors.green.shade700 : Colors.orange.shade700,
        duration: const Duration(seconds: 5),
      ));
      if (result.success) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.patient['TDL_PATIENT_UNSIGNED_NAME'] ?? widget.patient['TDL_PATIENT_NAME'] ?? widget.patient['tdl_patient_name'] ?? 'BN';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: widget.color,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Text(widget.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Patient context
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                      if ((widget.patient['treatment_code'] ?? widget.patient['SERVICE_REQ_CODE']) != null)
                        Text('ĐT: ${widget.patient['treatment_code'] ?? widget.patient['SERVICE_REQ_CODE']}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Form fields theo từng section
          ...widget.fields.entries.map((section) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (section.key.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(
                      section.key.toUpperCase(),
                      style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ),
                ...section.value.map((f) => _buildField(f)),
              ],
            );
          }),

          const SizedBox(height: 24),

          // Save button
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('HỦY'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'ĐANG LƯU...' : 'LƯU'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // v3.0.58: Nút Lưu ký
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _saving ? null : () => _saveAndPushEmr(useVnptSignature: false),
                  icon: const Icon(Icons.draw, size: 14),
                  label: const Text('Lưu ký', style: TextStyle(fontSize: 11)),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 4),
              // v3.0.58: Nút Ký CA
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _saveAndPushEmr(useVnptSignature: true),
                  icon: const Icon(Icons.verified_user, size: 14),
                  label: const Text('Ký CA', style: TextStyle(fontSize: 11)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField(OpFormField f) {
    final ctrl = _ctrls[f.key]!;
    Widget input;
    switch (f.type) {
      case 'multiline':
        input = TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: f.hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.all(10),
            errorText: _errors[f.key],
          ),
        );
        break;
      case 'number':
        input = TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: f.hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            errorText: _errors[f.key],
          ),
        );
        break;
      case 'dropdown':
        input = DropdownButtonFormField<String>(
          value: ctrl.text.isNotEmpty ? ctrl.text : null,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            errorText: _errors[f.key],
          ),
          items: (f.options ?? []).map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) {
            if (v != null) ctrl.text = v;
          },
        );
        break;
      default:
        input = TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: f.hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            errorText: _errors[f.key],
          ),
        );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(f.label, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600)),
              if (f.required)
                const Text(' *', style: TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          input,
        ],
      ),
    );
  }
}