// v3.0.79: AttachDocumentScreen — Đính kèm tài liệu (ảnh/file/PDF) vào EMR BN
// v3.0.81: Thêm nút "Lưu ký" - ký tay → embed vào PDF → push signed EMR
//   (workflow giống Scan phiếu - chữ ký overlay góc dưới phải PDF + tên user)
// Workflow:
//   ┌──────────────────────────────┐
//   │ Loại văn bản ▼ (default 20)  │
//   │ Tên văn bản ___________      │
//   │ Nhóm văn bản ▼ (optional)   │
//   ├──────────────────────────────┤
//   │ [📷 Chụp ảnh] [📁 Tệp] [...] │
//   │ Ảnh preview (nếu có)         │
//   ├──────────────────────────────┤
//   │ [Lưu] [Lưu ký ✍️] [Hủy]      │
//   └──────────────────────────────┘
//
// Yêu cầu: HIS Pro auth token, VPN, mã điều trị.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:signature/signature.dart';
import 'package:his_mobile/data/api/attach_document_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/local/scanned_forms_service.dart';

/// v3.0.79: 20 loại văn bản phổ biến nhất (lấy từ note2 dropdown list)
/// Có thể được thay thế bằng API fetchDocumentTypes() nếu user cần list đầy đủ
class EmrDocType {
  final int id;
  final String code;
  final String name;
  const EmrDocType({required this.id, required this.code, required this.name});

  static const all = <EmrDocType>[
    EmrDocType(id: 2, code: '02', name: 'Phiếu khám vào viện'),
    EmrDocType(id: 3, code: '03', name: 'Đơn thuốc'),
    EmrDocType(id: 4, code: '04', name: 'Chứng nhận PTTT'),
    EmrDocType(id: 5, code: '05', name: 'Sơ kết 15 ngày điều trị'),
    EmrDocType(id: 7, code: '07', name: 'Tờ điều trị'),
    EmrDocType(id: 8, code: '08', name: 'Phiếu chăm sóc'),
    EmrDocType(id: 9, code: '09', name: 'Phiếu truyền dịch'),
    EmrDocType(id: 10, code: '10', name: 'Phiếu theo dõi'),
    EmrDocType(id: 11, code: '11', name: 'Phiếu phản ứng thuốc'),
    EmrDocType(id: 12, code: '12', name: 'Phiếu trích lục bệnh án'),
    EmrDocType(id: 15, code: '15', name: 'Giấy xác nhận cấp cứu'),
    EmrDocType(id: 16, code: '16', name: 'Biên bản khám'),
    EmrDocType(id: 17, code: '17', name: 'Biên bản hội chẩn'),
    EmrDocType(id: 20, code: '20', name: 'Phiếu khác'),
    EmrDocType(id: 21, code: '21', name: 'Phiếu chỉ định'),
    EmrDocType(id: 22, code: '22', name: 'Phiếu kết quả'),
    EmrDocType(id: 25, code: '25', name: 'Giấy ra viện'),
    EmrDocType(id: 26, code: '26', name: 'Giấy hẹn khám'),
    EmrDocType(id: 27, code: '27', name: 'Giấy chuyển viện'),
    EmrDocType(id: 30, code: '30', name: 'Vỏ bệnh án hội chẩn'),
  ];
}

class AttachDocumentScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  const AttachDocumentScreen({super.key, required this.patient});

  @override
  State<AttachDocumentScreen> createState() => _AttachDocumentScreenState();
}

class _AttachDocumentScreenState extends State<AttachDocumentScreen> {
  final _svc = AttachDocumentService.instance;
  final _nameCtrl = TextEditingController();
  // v3.0.81: SignatureController cho "Lưu ký"
  final _signatureCtrl = SignatureController(
    penStrokeWidth: 2.5,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  EmrDocType _docType = EmrDocType.all.firstWhere(
    (e) => e.code == '20',
    orElse: () => EmrDocType.all.last,
  );
  String? _docGroup; // optional
  String? _filePath;
  String? _fileName;
  int? _fileSize;
  bool _saving = false;
  String? _error;
  // v3.0.81: đã có chữ ký chưa (cho nút Lưu ký)
  String? _signaturePath;

  String get _signerName {
    final session = HisProApiService.instance.session;
    return session?.userName ?? session?.loginName ?? 'Khoa Cấp Cứu';
  }

  String get _patientCode {
    final p = widget.patient;
    return (p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? p['PATIENT_CODE'] ?? '').toString();
  }

  String get _patientName {
    final p = widget.patient;
    return (p['TDL_PATIENT_NAME'] ?? p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_name'] ?? '').toString();
  }

  String get _treatmentCode {
    final p = widget.patient;
    return (p['TDL_TREATMENT_CODE'] ?? p['tdl_treatment_code'] ?? p['TREATMENT_CODE'] ?? '').toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _signatureCtrl.dispose();
    super.dispose();
  }

  /// v3.0.81: Capture signature từ user (giống Scan phiếu)
  /// Returns path file PNG, hoặc null nếu user huỷ
  Future<String?> _captureSignature() async {
    _signatureCtrl.clear();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.draw, color: Color(0xFF6A1B9A), size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ký tên: $_signerName',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  height: 200,
                  child: Signature(
                    controller: _signatureCtrl,
                    backgroundColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Huỷ'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _signatureCtrl.clear(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Xóa'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          if (_signatureCtrl.isNotEmpty) Navigator.pop(ctx, true);
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Xong'),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
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
    final sigPath = p.join(dir, 'attach_sig_${DateTime.now().millisecondsSinceEpoch}.png');
    final f = File(sigPath);
    await f.writeAsBytes(bytes);
    return sigPath;
  }

  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? f = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (f == null) return;
      final size = await File(f.path).length();
      setState(() {
        _filePath = f.path;
        _fileName = f.name;
        _fileSize = size;
        if (_nameCtrl.text.isEmpty) {
          _nameCtrl.text = f.name.split('.').first;
        }
      });
    } catch (e) {
      _snack('Lỗi camera: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? f = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (f == null) return;
      final size = await File(f.path).length();
      setState(() {
        _filePath = f.path;
        _fileName = f.name;
        _fileSize = size;
        if (_nameCtrl.text.isEmpty) {
          _nameCtrl.text = f.name.split('.').first;
        }
      });
    } catch (e) {
      _snack('Lỗi thư viện: $e');
    }
  }

  void _removeFile() {
    setState(() {
      _filePath = null;
      _fileName = null;
      _fileSize = null;
    });
  }

  Future<void> _save({String? signaturePath}) async {
    if (_treatmentCode.isEmpty) {
      _snack('BN chưa có mã điều trị - không thể đính kèm');
      return;
    }
    if (_filePath == null) {
      _snack('Vui lòng chụp ảnh hoặc chọn file trước');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Vui lòng nhập tên văn bản');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await _svc.attachFile(
      treatmentCode: _treatmentCode,
      documentTypeId: _docType.id,
      documentName: _nameCtrl.text.trim(),
      filePath: _filePath!,
      signaturePath: signaturePath,  // v3.0.81: null nếu "Lưu", có path nếu "Lưu ký"
      documentGroupCode: _docGroup,
      signerName: _signerName,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.success) {
      final tag = r.isSigned ? '✅ Đã ký + đính kèm' : '✅ Đã đính kèm';
      _snack('$tag "${_nameCtrl.text}"');
      // Trở về màn hình trước (Xem bệnh án) - flag = true để refresh
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = r.error ?? 'Lỗi không rõ');
    }
  }

  /// v3.0.81: "Lưu ký" - capture signature trước, rồi gọi _save với signaturePath
  Future<void> _saveWithSignature() async {
    if (_filePath == null) {
      _snack('Vui lòng chụp ảnh hoặc chọn file trước');
      return;
    }
    // Bước 1: Lấy chữ ký (hoặc dùng lại nếu đã có)
    String? sigPath = _signaturePath;
    if (sigPath == null || !await File(sigPath).exists()) {
      sigPath = await _captureSignature();
      if (sigPath == null) {
        // User huỷ ký → dừng
        return;
      }
      if (mounted) {
        setState(() => _signaturePath = sigPath);
      }
    }
    // Bước 2: Lưu với chữ ký
    await _save(signaturePath: sigPath);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  String _fmtSize(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đính kèm tài liệu'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Hướng dẫn',
            onPressed: () => _showHelp(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPatientHeader(),
          if (_error != null) _buildErrorBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === Loại văn bản ===
                  _sectionLabel('Loại văn bản', Icons.category),
                  DropdownButtonFormField<EmrDocType>(
                    value: _docType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: EmrDocType.all.map((e) {
                      return DropdownMenuItem(
                        value: e,
                        child: Text('${e.code} - ${e.name}', style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _docType = v ?? _docType),
                  ),
                  const SizedBox(height: 12),

                  // === Tên văn bản ===
                  _sectionLabel('Tên văn bản', Icons.title),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'VD: test, X-quang ngực, Giấy chuyển viện...',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // === Nhóm văn bản (optional) ===
                  _sectionLabel('Nhóm văn bản (tuỳ chọn)', Icons.folder),
                  DropdownButtonFormField<String?>(
                    value: _docGroup,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('-- Không chọn --')),
                      DropdownMenuItem(value: '01', child: Text('01 - Sinh hóa')),
                      DropdownMenuItem(value: '02', child: Text('02 - Miễn dịch')),
                      DropdownMenuItem(value: '03', child: Text('03 - Vi sinh')),
                      DropdownMenuItem(value: '04', child: Text('04 - Huyết học')),
                      DropdownMenuItem(value: '05', child: Text('05 - Xquang')),
                      DropdownMenuItem(value: '06', child: Text('06 - Cắt lớp vi tính')),
                      DropdownMenuItem(value: '07', child: Text('07 - Điện tim')),
                      DropdownMenuItem(value: '10', child: Text('10 - Siêu âm')),
                      DropdownMenuItem(value: '11', child: Text('11 - Nội soi')),
                    ],
                    onChanged: (v) => setState(() => _docGroup = v),
                  ),
                  const SizedBox(height: 18),

                  // === File picker ===
                  _sectionLabel('Tệp đính kèm', Icons.attach_file),
                  if (_filePath == null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _bigPickerButton(
                            icon: Icons.camera_alt,
                            color1: const Color(0xFFD32F2F),
                            color2: const Color(0xFFB71C1C),
                            label: 'Chụp ảnh',
                            onTap: _pickFromCamera,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _bigPickerButton(
                            icon: Icons.photo_library,
                            color1: const Color(0xFF1976D2),
                            color2: const Color(0xFF0D47A1),
                            label: 'Từ thư viện',
                            onTap: _pickFromGallery,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    _filePreviewCard(),
                  ],
                  const SizedBox(height: 24),

                  // v3.0.81: 3 nút - Lưu (unsigned) + Lưu ký (signed) + Hủy
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Hủy'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : () => _save(),
                          icon: _saving
                              ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.cloud_upload, size: 18),
                          label: Text(_saving ? 'Đang lưu...' : 'Lưu', style: const TextStyle(fontSize: 13)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6A1B9A),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _saveWithSignature,
                          icon: const Icon(Icons.draw, size: 18),
                          label: const Text('Lưu ký', style: TextStyle(fontSize: 13)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_signaturePath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 14, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 4),
                          Text(
                            'Đã có chữ ký: ${_signaturePath!.split('/').last}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _saving ? null : () async {
                              // Ký lại
                              final newPath = await _captureSignature();
                              if (newPath != null && mounted) {
                                setState(() => _signaturePath = newPath);
                              }
                            },
                            icon: const Icon(Icons.refresh, size: 14),
                            label: const Text('Ký lại', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFEDE7F6), Color(0xFFD1C4E9)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _patientName.isEmpty ? 'BN' : _patientName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4A148C)),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Mã BN: ${_patientCode.isEmpty ? '—' : _patientCode}'
            '${_treatmentCode.isNotEmpty ? '  •  Mã ĐT: $_treatmentCode' : ''}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6A1B9A)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    final err = _error ?? '';
    // Rút gọn thông báo lỗi dài (Dio verbose, validateStatus 500, ...)
    String short = err;
    if (err.length > 200) short = '${err.substring(0, 200)}...';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: const Color(0xFFFFCDD2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              short,
              style: const TextStyle(color: Color(0xFFC62828), fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 4),
            const Text(
              '💡 Kiểm tra: (1) VPN BV (172.16.9.6) đã bật, (2) HIS Pro token còn hạn (Cài đặt → EMR Sync), (3) BN có đang mở ĐT trên HIS desktop không.',
              style: TextStyle(color: Color(0xFFB71C1C), fontSize: 10, height: 1.4, fontStyle: FontStyle.italic),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionLabel(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 14, color: const Color(0xFF6A1B9A)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6A1B9A))),
      ]),
    );
  }

  Widget _bigPickerButton({
    required IconData icon,
    required Color color1,
    required Color color2,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color1, color2]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _filePreviewCard() {
    final isImage = (_fileName ?? '').toLowerCase().matchAsPrefix('') != null &&
        ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp']
            .any((e) => (_fileName ?? '').toLowerCase().endsWith(e));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (isImage && _filePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(_filePath!),
                  width: 60, height: 60, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60),
                ),
              )
            else
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.description, size: 32, color: Color(0xFF6A1B9A)),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fileName ?? '(no name)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_fileSize != null)
                    Text(_fmtSize(_fileSize), style: const TextStyle(fontSize: 11, color: Color(0xFF616161))),
                  if (_filePath != null)
                    Text(
                      _filePath!.length > 50 ? '...${_filePath!.substring(_filePath!.length - 50)}' : _filePath!,
                      style: const TextStyle(fontSize: 9, color: Color(0xFF9E9E9E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Color(0xFFD32F2F)),
              onPressed: _removeFile,
              tooltip: 'Bỏ file này',
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hướng dẫn Đính kèm'),
        content: const SingleChildScrollView(
          child: Text(
            '📎 Đính kèm tài liệu vào EMR bệnh nhân\n\n'
            '1. Chọn "Loại văn bản" (mặc định 20 = Phiếu khác cho tài liệu tự do)\n'
            '2. Nhập "Tên văn bản" (sẽ hiển thị trong Xem bệnh án)\n'
            '3. (Tuỳ chọn) Chọn "Nhóm văn bản" nếu là XQ/CT/Siêu âm...\n'
            '4. Nhấn "Chụp ảnh" hoặc "Từ thư viện" để chọn file\n'
            '5. Nhấn "Lưu lên EMR" → file được đẩy lên HIS Pro EMR\n\n'
            '⚠️ Yêu cầu:\n'
            '• Có HIS Pro auth token (Cài đặt → EMR Sync)\n'
            '• Bật VPN BV nội bộ (172.16.9.6:1417)\n'
            '• BN phải có mã điều trị (TREATMENT_CODE)\n\n'
            '🔒 Lưu ý: Sau khi đính kèm, vào Xem bệnh án → nhấn "Tìm lại" để thấy file mới.',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }
}
