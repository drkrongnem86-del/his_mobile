// ECG Execute Screen v3.1.00 - Form thực hiện ECG tại phòng thử thuật HSCC
// v3.1.00: NEW - workflow thực hiện ECG từ Phòng thử thuật
// - Header: thông tin BN + yêu cầu dịch vụ
// - Form: thời gian bắt đầu/kết thúc, kết quả ECG (required), kết luận, kíp
// - Save + auto-finish: call api/HisServiceReq/FinishWithTime
// - Save draft: FormDraftService (backup local)
// - Return true → caller (ProcedureRoom) auto-refresh + BN chuyển sang "Đã thực hiện"
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/services/form_draft_service.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

class ECGExecuteScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> serviceReq;
  const ECGExecuteScreen({super.key, required this.patient, required this.serviceReq});

  @override
  State<ECGExecuteScreen> createState() => _ECGExecuteScreenState();
}

class _ECGExecuteScreenState extends State<ECGExecuteScreen> {
  final _formKey = GlobalKey<FormState>();
  final HisApiService _api = HisApiService();

  // Controllers
  final _ketQuaCtrl = TextEditingController(text: 'NHỊP XOANG ĐỀU');
  final _ketLuanCtrl = TextEditingController();
  final _ghiChuCtrl = TextEditingController();
  final _bsChinhCtrl = TextEditingController();
  final _ddCtrl = TextEditingController();

  DateTime _startTime = DateTime.now();
  DateTime _endTime = DateTime.now().add(const Duration(minutes: 15));
  final List<File> _images = [];
  bool _saving = false;
  String _debug = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('hispro_user') ?? prefs.getString('username') ?? 'nemk';
      if (mounted) {
        setState(() {
          _bsChinhCtrl.text = username;
        });
      }
    } catch (_) {
      _bsChinhCtrl.text = 'nemk';
    }
  }

  @override
  void dispose() {
    _ketQuaCtrl.dispose();
    _ketLuanCtrl.dispose();
    _ghiChuCtrl.dispose();
    _bsChinhCtrl.dispose();
    _ddCtrl.dispose();
    super.dispose();
  }

  String _g(String k1, [String? k2]) {
    final v = widget.patient[k1] ??
        widget.patient[k2 ?? ''] ??
        widget.serviceReq[k1] ??
        widget.serviceReq[k2 ?? ''] ??
        '';
    return v?.toString() ?? '';
  }

  String get _patientName => fixVietnameseMojibake(PatientNameHelper.getName(widget.patient));
  String get _patientCode => _g('TDL_PATIENT_CODE', 'tdl_patient_code');
  String get _treatmentCode => _g('TDL_TREATMENT_CODE', 'treatment_code');
  String get _serviceReqCode => _g('SERVICE_REQ_CODE', 'service_req_code');
  String get _serviceName => _g('SERVICE_NAME', 'service_name');

  /// Lưu + auto-finish service req
  Future<bool> _saveAndFinish() async {
    if (!_formKey.currentState!.validate()) return false;
    if (_ketQuaCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vui lòng nhập kết quả ECG')),
      );
      return false;
    }
    if (_bsChinhCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vui lòng nhập tên Bác sĩ chính')),
      );
      return false;
    }

    setState(() {
      _saving = true;
      _debug = '⏳ Đang lưu ECG...';
    });

    try {
      // 1. Lưu local (FormDraftService) - backup
      final formData = <String, dynamic>{
        'form': 'ECG',
        'patient_code': _patientCode,
        'treatment_code': _treatmentCode,
        'service_req_code': _serviceReqCode,
        'service_name': _serviceName,
        'start_time': _startTime.toIso8601String(),
        'end_time': _endTime.toIso8601String(),
        'ket_qua': _ketQuaCtrl.text,
        'ket_luan': _ketLuanCtrl.text,
        'ghi_chu': _ghiChuCtrl.text,
        'bs_chinh': _bsChinhCtrl.text,
        'dd': _ddCtrl.text,
        'images_count': _images.length,
        'created_at': DateTime.now().toIso8601String(),
      };
      try {
        await FormDraftService.instance.saveDraft(
          'ECG',
          _patientCode.isNotEmpty ? _patientCode : _serviceReqCode,
          formData,
          <String, List<dynamic>>{'images': _images.map((f) => f.path).toList()},
        );
        if (kDebugMode) debugPrint('ECG form draft saved: ECG_$_patientCode');
      } catch (e) {
        debugPrint('FormDraftService save error: $e');
      }

      // 2. Call finishServiceReqWithTime API
      final serviceReqId = widget.serviceReq['ID'] ?? widget.serviceReq['id'];
      if (serviceReqId == null) {
        setState(() {
          _saving = false;
          _debug = '❌ Lỗi: Không tìm thấy ServiceReq ID';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Lỗi: Không tìm thấy ServiceReq ID'), backgroundColor: Colors.red),
          );
        }
        return false;
      }

      setState(() => _debug = '⏳ Đang đánh dấu hoàn thành (FinishWithTime)...');

      final finishResult = await _api.finishServiceReqWithTime(
        serviceReqId: int.tryParse(serviceReqId.toString()) ?? 0,
        startTime: _startTime,
        endTime: _endTime,
        resultNote: '${_ketQuaCtrl.text}${_ketLuanCtrl.text.isNotEmpty ? '\n\nKết luận: ${_ketLuanCtrl.text}' : ''}${_ghiChuCtrl.text.isNotEmpty ? '\n\nGhi chú: ${_ghiChuCtrl.text}' : ''}',
      );

      if (!mounted) return false;

      if (finishResult.success) {
        setState(() {
          _saving = false;
          _debug = '✅ Hoàn thành! ServiceReq #${serviceReqId} → status=3 (Hoàn thành)';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã hoàn thành ECG${_images.isNotEmpty ? " + ${_images.length} ảnh" : ""}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        // Trả về true để caller (ProcedureRoom) reload
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context, true);
        });
        return true;
      } else {
        setState(() {
          _saving = false;
          _debug = '❌ Lỗi finish: ${finishResult.message}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi: ${finishResult.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _debug = '❌ Exception: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  String _calculateAge() {
    final dobStr = _g('TDL_PATIENT_DOB', 'tdl_patient_dob');
    if (dobStr.isEmpty) return '—';
    try {
      final dob = int.parse(dobStr);
      final dobDate = DateTime(dob ~/ 10000, (dob ~/ 100) % 100, dob % 100);
      final now = DateTime.now();
      var age = now.year - dobDate.year;
      if (now.month < dobDate.month || (now.month == dobDate.month && now.day < dobDate.day)) {
        age--;
      }
      return '$age tuổi';
    } catch (_) {
      return '—';
    }
  }

  String _formatDob() {
    final dobStr = _g('TDL_PATIENT_DOB', 'tdl_patient_dob');
    if (dobStr.isEmpty) return '—';
    try {
      final dob = int.parse(dobStr);
      return '${dob % 100}/${(dob ~/ 100) % 100}/${dob ~/ 10000}';
    } catch (_) {
      return dobStr;
    }
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final init = isStart ? _startTime : _endTime;
    final date = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(hours: 1)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (time == null) return;
    final newDt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startTime = newDt;
        if (_endTime.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 15));
        }
      } else {
        _endTime = newDt;
      }
    });
  }

  Future<void> _pickImage({required ImageSource source}) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _images.add(File(picked.path)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chọn ảnh: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeImage(int idx) {
    setState(() => _images.removeAt(idx));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        title: const Text('Thực hiện ECG', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Hướng dẫn',
            onPressed: _showHelp,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(children: [
          // ===== USER HEADER =====
          UserHeader.fromAuth(compact: true),

          // ===== PATIENT & SERVICE INFO =====
          _buildPatientHeader(),

          // ===== FORM =====
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Thời gian
                _buildSectionTitle('⏱ THỜI GIAN THỰC HIỆN', const Color(0xFFD32F2F)),
                Row(children: [
                  Expanded(child: _buildDateTimeField('Bắt đầu', _startTime, () => _pickDateTime(isStart: true))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDateTimeField('Kết thúc', _endTime, () => _pickDateTime(isStart: false))),
                ]),
                const SizedBox(height: 12),

                // Kết quả
                _buildSectionTitle('📋 KẾT QUẢ ECG (bắt buộc)', const Color(0xFF1976D2)),
                TextFormField(
                  controller: _ketQuaCtrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: 'VD: NHỊP XOANG ĐỀU TẦN SỐ 82 LẦN / PHÚT\nTrục điện tim: bình thường\nKhông thấy dấu hiệu nhồi máu cơ tim cấp...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập kết quả ECG' : null,
                ),
                const SizedBox(height: 8),

                // Kết luận
                _buildSectionTitle('🔍 KẾT LUẬN', const Color(0xFF388E3C)),
                TextFormField(
                  controller: _ketLuanCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Kết luận của bác sĩ (không bắt buộc)',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),

                // Ghi chú
                _buildSectionTitle('📝 GHI CHÚ', const Color(0xFF616161)),
                TextFormField(
                  controller: _ghiChuCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Ghi chú thêm (không bắt buộc)',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Hình ảnh đính kèm
                _buildSectionTitle('📷 HÌNH ẢNH ĐÍNH KÈM (${_images.length})', const Color(0xFF7B1FA2)),
                _buildImagePicker(),
                const SizedBox(height: 12),

                // Kíp thực hiện
                _buildSectionTitle('👥 KÍP THỰC HIỆN', const Color(0xFFE65100)),
                TextFormField(
                  controller: _bsChinhCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bác sĩ chính *',
                    prefixIcon: Icon(Icons.medical_services, size: 18),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ddCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Điều dưỡng (không bắt buộc)',
                    prefixIcon: Icon(Icons.health_and_safety, size: 18),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Debug
                if (_debug.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _debug.startsWith('✅')
                          ? const Color(0xFFE8F5E9)
                          : _debug.startsWith('❌')
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_debug, style: const TextStyle(fontSize: 10)),
                  ),
              ]),
            ),
          ),

          // ===== ACTION BUTTONS =====
          _buildActionButtons(),
        ]),
      ),
    );
  }

  Widget _buildPatientHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white24,
            child: Text(
              _patientName.isNotEmpty ? _patientName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _patientName,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Wrap(spacing: 6, runSpacing: 2, children: [
                if (_patientCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                    child: Text('Mã BN: $_patientCode', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                if (_treatmentCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                    child: Text('ĐT: $_treatmentCode', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                if (_serviceReqCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                    child: Text('YC: $_serviceReqCode', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            const Icon(Icons.flash_on, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _serviceName.isNotEmpty ? _serviceName : 'Ghi điện tim cấp cứu tại giường',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }

  Widget _buildDateTimeField(String label, DateTime dt, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.access_time, size: 14, color: Color(0xFFD32F2F)),
            const SizedBox(width: 4),
            Text(
              intl.DateFormat('HH:mm').format(dt),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            Text(
              intl.DateFormat('dd/MM').format(dt),
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildImagePicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickImage(source: ImageSource.camera),
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('Chụp ảnh', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickImage(source: ImageSource.gallery),
            icon: const Icon(Icons.photo_library, size: 16),
            label: const Text('Thư viện', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ]),
      if (_images.isNotEmpty) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length,
            itemBuilder: (ctx, i) => Stack(children: [
              Container(
                margin: const EdgeInsets.only(right: 6),
                width: 80, height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  image: DecorationImage(
                    image: FileImage(_images[i]),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                right: 2, top: 2,
                child: GestureDetector(
                  onTap: () => _removeImage(i),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 12),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Hủy', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveAndFinish,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.flash_on, size: 16),
              label: Text(
                _saving ? 'Đang lưu...' : 'Hoàn thành & Kết thúc',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hướng dẫn thực hiện ECG'),
        content: const SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('1. Chọn thời gian bắt đầu và kết thúc', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('2. Nhập kết quả điện tim (bắt buộc)', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('3. Nhập kết luận (nếu có)', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('4. Đính kèm ảnh ECG (nếu có)', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('5. Nhập tên Bác sĩ chính (bắt buộc)', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('6. Nhấn "Hoàn thành & Kết thúc"', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Lưu ý: Sau khi lưu, BN sẽ tự động chuyển sang trạng thái "Đã thực hiện" trong Phòng thử thuật. Để đẩy EMR, dùng menu "Đính kèm tài liệu" trong thao tác BN.', style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }
}
