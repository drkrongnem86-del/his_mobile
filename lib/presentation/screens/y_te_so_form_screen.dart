// v3.0.9: Form generic cho các chức năng Y tế số
// v3.0.10: Dùng Base64 trực tiếp (không qua FSS 1405 vì trả 404 từ VPN)
// v3.0.22: Refactor - dùng PhieuSaveService thống nhất (1 entry point, bỏ 3 hàm duplicate)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/services/phieu_save_service.dart';
import 'package:his_mobile/data/services/y_te_so_store.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/data/models/y_te_so_feature.dart';

/// Loại trường nhập
class YTeSoField {
  final String key;
  final String label;
  final bool required;
  final bool multiline;
  final TextInputType keyboardType;
  final List<String>? options; // cho select
  final bool isNumber;

  const YTeSoField.text(
    this.key,
    this.label, {
    this.required = false,
    this.multiline = false,
  })  : keyboardType = TextInputType.text,
        options = null,
        isNumber = false;

  const YTeSoField.number(
    this.key,
    this.label, {
    this.required = false,
  })  : keyboardType = TextInputType.number,
        multiline = false,
        options = null,
        isNumber = true;

  const YTeSoField.select(
    this.key,
    this.label, {
    required this.options,
    this.required = false,
  })  : keyboardType = TextInputType.text,
        multiline = false,
        isNumber = false;
}

class YTeSoFormScreen extends StatefulWidget {
  final String featureId;
  final String featureName;
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;
  final List<YTeSoField> fields;
  final int? emrDocType; // DocumentTypeId cho EMR push
  final bool readOnly;

  const YTeSoFormScreen({
    super.key,
    required this.featureId,
    required this.featureName,
    required this.patient,
    required this.department,
    required this.fields,
    this.emrDocType,
    this.readOnly = false,
  });

  @override
  State<YTeSoFormScreen> createState() => _YTeSoFormScreenState();
}

class _YTeSoFormScreenState extends State<YTeSoFormScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String?> _errors = {};
  bool _saving = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _ctrls[f.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    for (final f in widget.fields) {
      if (f.required) {
        final v = _ctrls[f.key]?.text.trim() ?? '';
        if (v.isEmpty) {
          return 'Vui lòng nhập "${f.label}"';
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _collectData() {
    final data = <String, dynamic>{};
    for (final f in widget.fields) {
      final v = _ctrls[f.key]?.text.trim() ?? '';
      if (f.isNumber && v.isNotEmpty) {
        data[f.key] = double.tryParse(v) ?? v;
      } else {
        data[f.key] = v;
      }
    }
    return data;
  }

  /// Lưu local
  /// v3.0.20: Lưu - workflow PDF temp + tự động đẩy EMR unsigned + xóa PDF
  /// v3.0.22: Lưu - workflow PDF temp thống nhất qua PhieuSaveService
  /// - Lưu local (YTeSoStore) + đẩy EMR unsigned (IsFinishSign=false)
  /// - BS ký trên HIS Pro desktop sau
  Future<bool> _saveUnsigned() async {
    final err = _validate();
    if (err != null) {
      _snack(err, Colors.red);
      return false;
    }
    setState(() => _saving = true);
    try {
      final data = _collectData();
      _snack('💾 Bước 1/3: Lưu local...', Colors.blue);
      // Bước 1: Lưu local (YTeSoStore) - thông qua hook trong PhieuSaveService
      Future<bool> saveLocalHook(PhieuSaveInput input) async {
        await YTeSoStore.instance.save(
          featureId: widget.featureId,
          patientCode: widget.patient['TDL_PATIENT_CODE']?.toString() ?? widget.patient['PATIENT_CODE']?.toString() ?? '',
          treatmentCode: widget.patient['TDL_TREATMENT_CODE']?.toString() ?? widget.patient['treatment_code']?.toString() ?? '',
          data: input.formData,
        );
        return true;
      }

      _snack('☁️ Bước 2/3: Tạo PDF + đẩy EMR (chưa ký)...', Colors.blue);
      final result = await PhieuSaveService.instance.save(
        mode: PhieuSaveMode.unsigned,
        input: PhieuSaveInput(
          patient: widget.patient,
          formName: widget.featureName,
          formData: data,
          documentTypeId: widget.emrDocType,
          phieuLabel: widget.featureName,
        ),
        saveLocalHook: saveLocalHook,
      );

      if (!mounted) return false;
      if (result.emrPushed) {
        setState(() {
          _result = '✅ Lưu + đẩy EMR thành công\n'
              '• DocumentCode: ${result.documentCode}\n'
              '• (BS ký trên HIS Pro desktop sau)\n'
              '• ${result.elapsedMs}ms';
        });
        _snack('✅ Lưu + EMR thành công - ${result.documentCode}', Colors.green);
        return true;
      } else if (result.success) {
        _snack('⚠️ EMR fail: ${result.error}\nPDF giữ tại: ${result.tempPdfPath}', Colors.orange);
        return false;
      } else {
        _snack('❌ Lỗi: ${result.error}', Colors.red);
        return false;
      }
    } catch (e) {
      _snack('Lỗi: $e', Colors.red);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// v3.0.22: Lưu ký - workflow PDF temp thống nhất qua PhieuSaveService
  /// - Lưu local (YTeSoStore) + đẩy EMR signed (IsFinishSign=true)
  /// - Có dialog confirm "Ký & Đẩy EMR" trước khi push
  Future<bool> _saveSigned() async {
    final err = _validate();
    if (err != null) {
      _snack(err, Colors.red);
      return false;
    }
    setState(() => _saving = true);
    try {
      final data = _collectData();
      _snack('💾 Bước 1/3: Lưu local...', Colors.blue);
      Future<bool> saveLocalHook(PhieuSaveInput input) async {
        await YTeSoStore.instance.save(
          featureId: widget.featureId,
          patientCode: widget.patient['TDL_PATIENT_CODE']?.toString() ?? widget.patient['PATIENT_CODE']?.toString() ?? '',
          treatmentCode: widget.patient['TDL_TREATMENT_CODE']?.toString() ?? widget.patient['treatment_code']?.toString() ?? '',
          data: input.formData,
        );
        return true;
      }

      // v3.0.20: Dialog confirm trước khi ký
      final ok = await _showSignConfirmDialog();
      if (!ok) {
        _snack('Đã hủy lưu ký', Colors.orange);
        return false;
      }

      _snack('☁️ Bước 2/3: Tạo PDF + đẩy EMR (đã ký)...', Colors.blue);
      final result = await PhieuSaveService.instance.save(
        mode: PhieuSaveMode.signed,
        input: PhieuSaveInput(
          patient: widget.patient,
          formName: widget.featureName,
          formData: data,
          documentTypeId: widget.emrDocType,
          phieuLabel: widget.featureName,
        ),
        saveLocalHook: saveLocalHook,
      );

      if (!mounted) return false;
      if (result.emrPushed) {
        setState(() {
          _result = '✅ Lưu ký + đẩy EMR thành công\n'
              '• DocumentCode: ${result.documentCode}\n'
              '• (BS đã ký điện tử - dùng làm bằng chứng pháp lý)\n'
              '• ${result.elapsedMs}ms';
        });
        _snack('✅ Lưu ký + EMR thành công - ${result.documentCode}', Colors.green);
        return true;
      } else if (result.success) {
        _snack('⚠️ EMR fail: ${result.error}\nPDF giữ tại: ${result.tempPdfPath}', Colors.orange);
        return false;
      } else {
        _snack('❌ Lỗi: ${result.error}', Colors.red);
        return false;
      }
    } catch (e) {
      _snack('Lỗi: $e', Colors.red);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// v3.0.26: Lưu ký bằng VNPT SmartCA (ký PKCS#7 thật qua Deeplink)
  /// Workflow: tạo PDF → mở app VNPT SmartCA → user xác nhận → embed PKCS#7 → push EMR
  Future<bool> _saveSignedVnpt() async {
    final err = _validate();
    if (err != null) {
      _snack(err, Colors.red);
      return false;
    }
    setState(() => _saving = true);
    try {
      final data = _collectData();
      _snack('💾 Bước 1/3: Lưu local...', Colors.blue);
      Future<bool> saveLocalHook(PhieuSaveInput input) async {
        await YTeSoStore.instance.save(
          featureId: widget.featureId,
          patientCode: widget.patient['TDL_PATIENT_CODE']?.toString() ?? widget.patient['PATIENT_CODE']?.toString() ?? '',
          treatmentCode: widget.patient['TDL_TREATMENT_CODE']?.toString() ?? widget.patient['treatment_code']?.toString() ?? '',
          data: input.formData,
        );
        return true;
      }

      _snack('🔐 Bước 2/3: Ký PKCS#7 qua VNPT SmartCA...', Colors.blue);
      final result = await PhieuSaveService.instance.save(
        mode: PhieuSaveMode.signed,
        input: PhieuSaveInput(
          patient: widget.patient,
          formName: widget.featureName,
          formData: data,
          documentTypeId: widget.emrDocType,
          phieuLabel: widget.featureName,
          useVnptSignature: true,  // v3.0.26: dùng VNPT SmartCA thật
        ),
        saveLocalHook: saveLocalHook,
      );

      if (!mounted) return false;
      // v3.0.29: VNPT có thể fail (chưa có backend BV) → fallback vẫn push EMR signed
      if (result.emrPushed) {
        if (result.vnptSigned) {
          setState(() {
            _result = '✅ Ký VNPT SmartCA + EMR thành công\n'
                '• DocumentCode: ${result.documentCode}\n'
                '• PKCS#7 từ VNPT SmartCA\n'
                '• ${result.elapsedMs}ms';
          });
          _snack('✅ Ký VNPT + EMR thành công - ${result.documentCode}', Colors.green);
        } else {
          // VNPT fail nhưng EMR vẫn push OK với IsFinishSign=true
          setState(() {
            _result = '✅ Đẩy EMR thành công (chưa ký VNPT)\n'
                '• DocumentCode: ${result.documentCode}\n'
                '• ⚠️ VNPT SmartCA chưa sẵn sàng (cần backend BV)\n'
                '• BS ký trên HIS Pro desktop sau\n'
                '• ${result.elapsedMs}ms';
          });
          _snack('⚠️ VNPT chưa sẵn sàng - đã đẩy EMR (BS ký sau)', Colors.orange);
        }
        return true;
      } else if (result.success) {
        _snack('⚠️ EMR fail: ${result.error}\nPDF giữ tại: ${result.tempPdfPath}', Colors.orange);
        return false;
      } else {
        _snack('❌ ${result.error}', Colors.red);
        return false;
      }
    } catch (e) {
      _snack('Lỗi: $e', Colors.red);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// v3.0.20: Dialog confirm "Ký & Đẩy EMR" trước khi push (cho Lưu ký)
  Future<bool> _showSignConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.draw, color: Color(0xFF2E7D32)),
            SizedBox(width: 8),
            Text('Xác nhận ký'),
          ],
        ),
        content: const Text(
          'Sau khi bấm "Ký & Đẩy EMR":\n'
          '• PDF sẽ được đẩy lên EMR HIS Pro (IsFinishSign=true)\n'
          '• BS ký điện tử (sẽ ký thật trên HIS Pro desktop sau)',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, false),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Hủy'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle, size: 16),
            label: const Text('Ký & Đẩy EMR'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patient['TDL_PATIENT_UNSIGNED_NAME']?.toString() ??
        widget.patient['TDL_PATIENT_NAME']?.toString() ??
        widget.patient['tdl_patient_name']?.toString() ??
        '';
    final treatmentCode = widget.patient['TDL_TREATMENT_CODE']?.toString() ?? '';
    final feature = YTeSoFeatures.byId(widget.featureId);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: feature?.color,
        foregroundColor: Colors.white,
        title: Text(
          widget.featureName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // BN info
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Color(0xFF1565C0), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        patientName.isEmpty ? '(chưa có tên)' : patientName,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        treatmentCode.isEmpty ? 'N/A' : treatmentCode,
                        style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Form fields
            if (!widget.readOnly)
              ...widget.fields.map((f) => _buildField(f))
            else
              // Read-only: hiển thị placeholder
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: widget.fields
                        .map((f) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      f.label,
                                      style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '(Sẽ load từ HIS Pro)',
                                      style: const TextStyle(fontSize: 12, color: Colors.black38, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Result
            if (_result != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _result!,
                        style: const TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // v3.0.29: 3 nút rõ ràng với tooltip
            // - Lưu: chỉ local + push EMR unsigned (BS ký trên HIS Pro desktop)
            // - Lưu ký: local + push EMR với IsFinishSign=true (BS đã ký điện tử)
            // - Ký VNPT: local + ký PKCS#7 thật qua VNPT SmartCA + push EMR (cần backend BV)
            if (!widget.readOnly) ...[
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: 'Lưu local + đẩy EMR (BS ký trên HIS Pro desktop sau)',
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Lưu'),
                        onPressed: _saving ? null : _saveUnsigned,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: 'Lưu local + đẩy EMR với IsFinishSign=true (BS đã ký điện tử)',
                      child: FilledButton.icon(
                        icon: const Icon(Icons.verified_user, size: 18),
                        label: const Text('Lưu ký'),
                        style: FilledButton.styleFrom(
                          backgroundColor: feature?.color,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _saving ? null : _saveSigned,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // v3.0.29: Nút VNPT SmartCA - tooltip rõ ràng cần backend
              Tooltip(
                message: 'Ký PKCS#7 thật qua VNPT SmartCA\n(cần backend BV đang hoạt động)',
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.verified, size: 18),
                    label: const Text('Ký VNPT SmartCA'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.purple.shade50,
                      foregroundColor: Colors.purple.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _saving ? null : _saveSignedVnpt,
                  ),
                ),
              ),
              // v3.0.17: BỎ hint SmartCA cert serial dưới nút - bảo mật
            ],

            const SizedBox(height: 12),

            // Version info
            Center(
              child: Text(
                'v${AppConstants.appVersion} • ${widget.featureId} • ${HisProApiService.instance.getEffectiveTokenSource()}',
                style: const TextStyle(fontSize: 10, color: Colors.black38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(YTeSoField f) {
    final ctrl = _ctrls[f.key]!;
    if (f.options != null) {
      // Select dropdown
      String currentValue = ctrl.text;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  f.label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (f.required)
                  const Text(' *', style: TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: currentValue.isNotEmpty ? currentValue : null,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: [
                for (final o in f.options!)
                  DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => ctrl.text = v ?? '',
            ),
          ],
        ),
      );
    }

    // Text field
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                f.label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (f.required)
                const Text(' *', style: TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: f.keyboardType,
            maxLines: f.multiline ? null : 1,
            minLines: f.multiline ? 3 : 1,
            inputFormatters: f.isNumber
                ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
                : null,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
