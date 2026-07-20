// ScanPhieuScreen v3.0.22
// - Sửa mojibake toàn file
// - Sửa flow Lưu/Lưu ký theo app Y tế số:
//   + Lưu (local): chỉ lưu LOCAL trên điện thoại, KHÔNG push EMR
//   + Lưu ký: capture chữ ký + push EMR thật qua HIS Pro 1417 (qua VPN)
// - Tên phiếu nhập tự do, mặc định "Phiếu khác" (ID=20) nếu chưa chọn
// - BN test: 000002124358 - app tự fetch tên qua HIS Pro nếu có token
// v3.0.22: Refactor - dùng PhieuSaveService thống nhất (1 entry point, 1 error handling)

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:path/path.dart' as p;
import 'package:his_mobile/data/local/scanned_forms_service.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/data/api/emr_push_service.dart';
import 'package:his_mobile/data/services/phieu_save_service.dart';

class ScanPhieuScreen extends StatefulWidget {
  final String treatmentCode;
  final String patientName;
  final String? signedBy;

  const ScanPhieuScreen({
    super.key,
    required this.treatmentCode,
    required this.patientName,
    this.signedBy,
  });

  @override
  State<ScanPhieuScreen> createState() => _ScanPhieuScreenState();
}

/// v3.0.0: Chế độ save cho Scan phiếu
enum ScanSaveMode {
  local,      // chỉ lưu local
  unsigned,   // lưu + đẩy EMR (chưa ký)
  signed,     // lưu + ký + đẩy EMR
}

class _ScanPhieuScreenState extends State<ScanPhieuScreen> {
  final _formNameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _signatureCtrl = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  File? _imageFile;
  File? _signatureFile;  // v2.64.0: lưu signature file
  EmrDocTypeInfo? _selectedDocType;
  bool _saving = false;
  String? _error;
  List<EmrDocTypeInfo> _docTypes = [];
  bool _loadingTypes = true;

  @override
  void initState() {
    super.initState();
    _loadDocTypes();
  }

  Future<void> _loadDocTypes() async {
    try {
      final types = await EmrPushService.instance.getDocumentTypes();
      if (!mounted) return;
      setState(() {
        _docTypes = types;
        _loadingTypes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingTypes = false);
    }
  }

  @override
  void dispose() {
    _formNameCtrl.dispose();
    _noteCtrl.dispose();
    _signatureCtrl.dispose();
    super.dispose();
  }

  /// v2.64.0: Capture signature dialog (giống PhieuKhamScreen)
  /// Returns path file signature, hoặc null nếu user hủy
  Future<String?> _captureSignature() async {
    _signatureCtrl.clear();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ký tên: ${widget.signedBy ?? DataService.instance.user?.userName ?? 'user'}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  height: 220,
                  child: Signature(
                    controller: _signatureCtrl,
                    backgroundColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.close),
                        label: const Text('Huỷ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _signatureCtrl.clear(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Xóa'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          if (_signatureCtrl.isNotEmpty) {
                            Navigator.pop(ctx, true);
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Xong'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != true || _signatureCtrl.isEmpty) return null;
    final bytes = await _signatureCtrl.toPngBytes();
    if (bytes == null) return null;
    final dir = await ScannedFormsService.instance.getImageDir();
    final sigPath = p.join(dir, 'scan_sig_${DateTime.now().millisecondsSinceEpoch}.png');
    final f = File(sigPath);
    await f.writeAsBytes(bytes);
    return sigPath;
  }

  Future<void> _pickImage({required ImageSource source}) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (picked == null) return;
      setState(() {
        _imageFile = File(picked.path);
      });
    } catch (e) {
      setState(() => _error = 'Lỗi chụp/chọn ảnh: $e');
    }
  }

  void _showImagePickerSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Chụp ảnh từ Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(source: ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Chọn từ Thư viện'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(source: ImageSource.gallery);
              },
            ),
            if (_imageFile != null)
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.orange),
                title: const Text('Chụp/Chọn lại'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(source: ImageSource.camera);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// v2.63.0: SearchablePicker 38 loại (37 EMR + Phiếu khác ID=20)
  void _showDocTypePickerSheet() {
    if (_docTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa load được danh sách loại phiếu')),
      );
      return;
    }
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final query = searchCtrl.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? _docTypes
                : _docTypes.where((t) =>
                    t.name.toLowerCase().contains(query) ||
                    t.code.toLowerCase().contains(query) ||
                    t.id.toString().contains(query)).toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              expand: false,
              builder: (ctx, scrollCtrl) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 40, height: 4,
                              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.assignment, color: Colors.indigo, size: 22),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Chọn loại phiếu (${_docTypes.length} loại từ HIS Pro)',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Text('${filtered.length}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: searchCtrl,
                              onChanged: (_) => setSheetState(() {}),
                              decoration: InputDecoration(
                                isDense: true,
                                prefixIcon: const Icon(Icons.search, size: 18),
                                hintText: 'Tìm theo tên / mã / ID...',
                                hintStyle: const TextStyle(fontSize: 13),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                          itemBuilder: (ctx, i) {
                            final t = filtered[i];
                            final isSelected = _selectedDocType?.id == t.id;
                            return ListTile(
                              dense: true,
                              leading: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.indigo.shade100 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(
                                    t.code,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.indigo.shade900 : Colors.grey.shade700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              title: Text(
                                t.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                                ),
                              ),
                              subtitle: Text('ID: ${t.id} | ${t.code}',
                                  style: const TextStyle(fontSize: 10, color: Colors.black45)),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: Colors.indigo, size: 20)
                                  : null,
                              onTap: () {
                                setState(() {
                                  _selectedDocType = t;
                                  if (_formNameCtrl.text.trim().isEmpty) {
                                    _formNameCtrl.text = t.name;
                                  }
                                });
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _validate() async {
    if (_imageFile == null) {
      setState(() => _error = 'Vui lòng chụp/chọn ảnh phiếu');
      return false;
    }
    // v2.98.3: BỎ check _selectedDocType - cho phép lưu với tên tự do
    // Mặc định lấy ID=20 (Phiếu khác) nếu chưa chọn
    if (_selectedDocType == null) {
      // Tạo 1 "phiếu tự do" ảo với ID=20
      _selectedDocType = EmrDocTypeInfo(
        id: 20,
        code: 'OT',
        name: _formNameCtrl.text.trim().isNotEmpty ? _formNameCtrl.text.trim() : 'Phiếu khác',
        numOrder: 20,
      );
    }
    if (_formNameCtrl.text.trim().isEmpty) {
      _formNameCtrl.text = _selectedDocType!.name;
    }
    setState(() => _error = null);
    return true;
  }

  /// v3.0.46: 3 chế độ - Lưu / Lưu ký / Ký VNPT SmartCA (theo mẫu Bàn giao BN)
  /// - [ScanSaveMode.local]: lưu local + đẩy EMR unsigned
  /// - [ScanSaveMode.signed]: lưu local + ký tay + đẩy EMR signed
  /// - [useVnptSignature]=true: lưu local + ký PKCS#7 qua VNPT SmartCA + đẩy EMR signed
  /// Refactor: dùng PhieuSaveService thống nhất (1 entry point, 1 error handling)
  Future<void> _save({required ScanSaveMode mode, bool useVnptSignature = false}) async {
    if (_saving) return;
    if (!await _validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Bước 1 - Lưu ảnh gốc local (cho ScannedForm)
      _snack('💾 Bước 1/4: Lưu ảnh local...', Colors.blue);
      final dir = await ScannedFormsService.instance.getImageDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final id = '$ts-${Random().nextInt(99999)}';
      final ext = p.extension(_imageFile!.path).isEmpty ? '.jpg' : p.extension(_imageFile!.path);
      final imgPath = p.join(dir, 'scan_$id$ext');
      await _imageFile!.copy(imgPath);

      // Bước 2 - Nếu Lưu ký, capture signature trước
      _snack(mode == ScanSaveMode.signed ? '✍️ Bước 2/4: Ký tay...' : '☁️ Bước 2/4: Đẩy EMR (chưa ký)...', Colors.blue);
      String? signaturePath;
      if (mode == ScanSaveMode.signed) {
        final sigPath = await _captureSignature();
        if (sigPath == null) {
          // User huỷ ký → dừng
          _snack('Đã hủy ký', Colors.orange);
          return;
        }
        signaturePath = sigPath;
      }

      // Bước 3 - Gọi PhieuSaveService thống nhất (convert ảnh → PDF → push EMR)
      _snack(useVnptSignature ? '🔐 Bước 3/4: Ký PKCS#7 qua VNPT SmartCA...' : '☁️ Bước 3/4: Tạo PDF + đẩy EMR...', Colors.blue);
      final result = await PhieuSaveService.instance.save(
        mode: mode == ScanSaveMode.signed ? PhieuSaveMode.signed : PhieuSaveMode.unsigned,
        input: PhieuSaveInput(
          useVnptSignature: useVnptSignature,
          patient: {
            'TDL_TREATMENT_CODE': widget.treatmentCode,
            'TDL_PATIENT_CODE': '',
            'TDL_PATIENT_UNSIGNED_NAME': widget.patientName,
          },
          formName: _formNameCtrl.text.trim(),
          formData: {'ghi_chu': _noteCtrl.text.trim()},
          imagePath: _imageFile!.path,
          signaturePath: signaturePath,
          documentTypeId: _selectedDocType!.id,
          phieuLabel: _selectedDocType!.name,
          departmentCode: 'HSCC',
          roomCode: 'PKCC',
          workingDeptName: 'Cấp Cứu Lưu',
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        ),
      );

      // Bước 4 - Lưu ScannedForm + auto-back
      _snack('💾 Bước 4/4: Lưu ScannedForm...', Colors.blue);
      final form = ScannedForm(
        id: id,
        treatmentCode: widget.treatmentCode,
        patientName: widget.patientName,
        formName: _formNameCtrl.text.trim(),
        imagePath: imgPath,
        signaturePath: signaturePath,
        signedBy: widget.signedBy ?? DataService.instance.user?.userName ?? 'user',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        uploaded: result.emrPushed,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      await ScannedFormsService.instance.save(form);

      HapticFeedback.mediumImpact();
      if (!mounted) return;

      // Hiển thị kết quả
      if (result.emrPushed) {
        final actionLabel = useVnptSignature ? 'Ký VNPT' : (mode == ScanSaveMode.signed ? 'Lưu ký' : 'Lưu');
        _snack('✅ $actionLabel + EMR thành công\nDocumentCode: ${result.documentCode}', Colors.green);
      } else if (result.success) {
        _snack('⚠️ Đã lưu local. EMR fail: ${result.error}\nPDF giữ tại: ${result.tempPdfPath}', Colors.orange);
      } else {
        _snack('❌ Lỗi: ${result.error}', Colors.red);
        return;
      }

      // Auto-back to "Phiếu đã lưu" sau 2s
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Lỗi lưu: $e';
      });
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Scan phiếu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Patient info
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.patientName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('Mã ĐT: ${widget.treatmentCode}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Loại phiếu (picker 38 loại)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _selectedDocType != null ? Colors.indigo.shade300 : Colors.grey.shade300,
                  width: _selectedDocType != null ? 1.5 : 1,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment, size: 18, color: Colors.indigo),
                      const SizedBox(width: 6),
                      const Text('Loại phiếu',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
                      const Spacer(),
                      if (_loadingTypes)
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                      else
                        Text('${_docTypes.length} loại',
                            style: const TextStyle(fontSize: 10, color: Colors.black45)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: _loadingTypes ? null : _showDocTypePickerSheet,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          if (_selectedDocType != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(_selectedDocType!.code,
                                  style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade900,
                                  )),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_selectedDocType!.name,
                                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text('ID: ${_selectedDocType!.id}',
                                style: const TextStyle(fontSize: 10, color: Colors.black45)),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() => _selectedDocType = null),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32),
                            ),
                          ] else
                            const Expanded(
                              child: Text('Bấm để chọn loại phiếu (38 loại)...',
                                  style: TextStyle(fontSize: 13, color: Colors.black54)),
                            ),
                          const Icon(Icons.arrow_drop_down, color: Colors.black45),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Form name
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.edit_note, size: 18, color: Colors.indigo),
                      SizedBox(width: 6),
                      Text('Tên phiếu (tùy chỉnh)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _formNameCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _selectedDocType != null ? 'Mặc định: ${_selectedDocType!.name}' : 'Chọn loại phiếu trước',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Image
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _imageFile == null ? Colors.grey.shade300 : Colors.green.shade400,
                  width: _imageFile == null ? 1 : 2,
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.image,
                          size: 18,
                          color: _imageFile == null ? Colors.grey : Colors.green.shade700),
                      const SizedBox(width: 6),
                      const Text('Hình ảnh phiếu',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
                      const Spacer(),
                      if (_imageFile != null)
                        TextButton.icon(
                          onPressed: _showImagePickerSheet,
                          icon: const Icon(Icons.edit, size: 14),
                          label: const Text('Sửa', style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  AspectRatio(
                    aspectRatio: 3 / 4,
                    child: _imageFile == null
                        ? InkWell(
                            onTap: _showImagePickerSheet,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, size: 48, color: Colors.grey.shade500),
                                  const SizedBox(height: 8),
                                  Text('Bấm để chụp ảnh hoặc chọn từ thư viện',
                                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _showImagePickerSheet,
                                    icon: const Icon(Icons.camera_alt, size: 16),
                                    label: const Text('Chụp/Chọn ảnh'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF1565C0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(_imageFile!, fit: BoxFit.contain),
                                Positioned(
                                  top: 8, right: 8,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                      onPressed: () => setState(() => _imageFile = null),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Note
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.note, size: 18, color: Colors.indigo),
                      SizedBox(width: 6),
                      Text('Ghi chú (tùy chọn)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Ghi chú thêm...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // v2.64.0: Signature preview (nếu Đã ký)
            if (_signatureFile != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.draw, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'đã ký (sẽ lưu kèm phiếu)',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.green.shade900),
                      ),
                    ),
                    SizedBox(
                      height: 36, width: 72,
                      child: Image.file(_signatureFile!, fit: BoxFit.contain),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.red),
                      onPressed: () async {
                        final reSig = await _captureSignature();
                        if (reSig != null) {
                          setState(() => _signatureFile = File(reSig));
                        }
                      },
                    ),
                  ],
                ),
              ),
            if (_signatureFile != null) const SizedBox(height: 12),

            // Error
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ],
                ),
              ),
            if (_error != null) const SizedBox(height: 12),

            // v3.0.46: 3 nút - [Lưu] [Lưu ký] [Ký VNPT SmartCA] theo mẫu Bàn giao BN
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(mode: ScanSaveMode.local),
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Lưu', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
                      foregroundColor: const Color(0xFF1565C0),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () async {
                      // Lưu ký: nếu chưa vẽ → mở dialog vẽ
                      if (_signatureFile == null) {
                        final sigPath = await _captureSignature();
                        if (sigPath == null) return;
                        setState(() => _signatureFile = File(sigPath));
                      }
                      await _save(mode: ScanSaveMode.signed);
                    },
                    icon: const Icon(Icons.draw, size: 16),
                    label: const Text('Lưu ký', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // v3.0.46: Nút Ký VNPT SmartCA - ký PKCS#7 thật qua app VNPT
            SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.verified, size: 16),
                  label: const Text('Ký VNPT SmartCA', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purple.shade50,
                    foregroundColor: Colors.purple.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: _saving ? null : () async {
                    // Ký VNPT: capture signature trước (nếu chưa có)
                    if (_signatureFile == null) {
                      final sigPath = await _captureSignature();
                      if (sigPath == null) return;
                      setState(() => _signatureFile = File(sigPath));
                    }
                    await _save(mode: ScanSaveMode.signed, useVnptSignature: true);
                  },
                ),
              ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 20),

            // Info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '3 nút (theo mẫu Bàn giao BN):\n'
                      '• "Lưu" = chỉ lưu local, BS ký trên HIS Pro desktop sau\n'
                      '• "Lưu ký" = ký tay trong app + đẩy EMR thật qua HIS Pro 1417\n'
                      '• "Ký VNPT SmartCA" = ký PKCS#7 thật qua app VNPT (cần backend BV)',
                      style: TextStyle(color: Colors.blue.shade900, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
