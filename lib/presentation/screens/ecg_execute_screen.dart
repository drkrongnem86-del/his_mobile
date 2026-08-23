// ECG Execute Screen v3.1.00 - Form thực hiện ECG tại phòng thử thuật HSCC
// v3.1.00: NEW - workflow thực hiện ECG từ Phòng thử thuật
// - Header: thông tin BN + yêu cầu dịch vụ
// - Form: thời gian bắt đầu/kết thúc, kết quả ECG (required), kết luận, kíp
// - Save + auto-finish: call api/HisServiceReq/FinishWithTime
// - Save draft: FormDraftService (backup local)
// - Return true → caller (ProcedureRoom) auto-refresh + BN chuyển sang "Đã thực hiện"
import 'dart:async';
import 'dart:convert';  // v3.0.169: jsonDecode/jsonEncode cho AcsUser cache
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';  // v3.0.164: sync token EMR push
import 'package:his_mobile/data/services/auto_token_service.dart';  // v3.0.164: sync token
import 'package:his_mobile/data/services/token_sync_service.dart';  // v3.0.165: token hub
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

  // v3.0.163: Machine selection (Máy tạo Oxy di động, Máy điện tim 03 kênh,...)
  Map<String, dynamic>? _selectedMachine;
  List<Map<String, dynamic>> _availableMachines = [];
  bool _loadingMachines = false;

  // v3.0.168: User list cho PTV/TTV chính (BS, điều dưỡng)
  // Hiển thị tên đầy đủ (USERNAME) như HIS Desktop
  List<Map<String, dynamic>> _userList = [];
  String? _selectedBsChinhLogin;  // LOGINNAME của BS chính (dùng cho backend)
  String? _selectedDdLogin;        // LOGINNAME của điều dưỡng
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    // v3.0.164: Auto-load token từ SharedPreferences (sync với procedure room)
    _loadHisProToken();
    _loadMachines();
    // v3.0.168: Load user list cho PTV/TTV chính
    _loadUsers();
  }

  /// v3.0.168: Load danh sách users từ AcsUser (port 1401)
  /// - Filter: IS_ACTIVE=1, sắp xếp theo USERNAME
  /// - Hiển thị tên đầy đủ (USERNAME) trong dropdown
  /// - Lưu LOGINNAME để gửi cho backend
  /// - v3.0.169: Cache 2 giờ (SharedPreferences) - tránh gọi API mỗi lần mở ECG
  static const String _kAcsUserCacheKey = 'acs_user_list_cache';
  static const String _kAcsUserCacheTimeKey = 'acs_user_list_cache_time';
  static const Duration _kAcsUserCacheTTL = Duration(hours: 2);

  Future<void> _loadUsers() async {
    if (_userList.isNotEmpty) return; // đã load
    setState(() => _loadingUsers = true);
    try {
      // v3.0.169: Thử cache trước (< 2h)
      final prefs = await SharedPreferences.getInstance();
      final cacheTimeMs = prefs.getInt(_kAcsUserCacheTimeKey);
      final cacheJson = prefs.getString(_kAcsUserCacheKey);
      if (cacheJson != null && cacheTimeMs != null) {
        final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(cacheTimeMs));
        if (age < _kAcsUserCacheTTL) {
          final cached = jsonDecode(cacheJson) as List;
          _userList = cached.cast<Map<String, dynamic>>();
          debugPrint('ECG: loaded ${_userList.length} users from cache (age: ${age.inMinutes}min)');
          if (mounted) setState(() => _loadingUsers = false);
          return;
        }
      }

      // Cache miss hoặc stale → gọi API
      final r = await _api.getAcsUsers(limit: 200);
      if (r.success && r.data is Map) {
        final data = r.data as Map;
        final raw = data['Data'];
        if (raw is List) {
          _userList = raw.cast<Map<String, dynamic>>().where((u) {
            final username = (u['USERNAME'] ?? '').toString().trim();
            final loginname = (u['LOGINNAME'] ?? '').toString().trim();
            return username.isNotEmpty && loginname.isNotEmpty;
          }).toList();
          debugPrint('ECG: loaded ${_userList.length} users from API');

          // v3.0.169: Lưu cache
          await prefs.setString(_kAcsUserCacheKey, jsonEncode(_userList));
          await prefs.setInt(_kAcsUserCacheTimeKey, DateTime.now().millisecondsSinceEpoch);

          if (mounted) setState(() {});
        }
      } else {
        debugPrint('ECG: getAcsUsers failed: ${r.message}');
      }
    } catch (e) {
      debugPrint('ECG: _loadUsers error: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  /// v3.0.168: Lấy USERNAME (tên đầy đủ) từ LOGINNAME
  String _getFullName(String? loginName) {
    if (loginName == null || loginName.isEmpty) return '';
    final found = _userList.firstWhere(
      (u) => (u['LOGINNAME'] ?? '').toString() == loginName,
      orElse: () => <String, dynamic>{},
    );
    if (found.isEmpty) return loginName; // fallback
    return (found['USERNAME'] ?? loginName).toString();
  }

  /// v3.0.165: Auto-load HIS Pro token từ TokenSyncService khi mở screen
  /// - Nếu TokenSyncService đã có token → dùng luôn
  /// - Nếu chưa có → load từ storage hoặc auto-fetch
  Future<void> _loadHisProToken() async {
    if (TokenSyncService.instance.hasToken) {
      // Đã có từ trước - dùng luôn
      _api.setAuthToken(TokenSyncService.instance.currentToken!);
      if (kDebugMode) debugPrint('ECG: using cached token');
      return;
    }
    // Chưa có → load từ storage (silent - không hiện loading)
    await TokenSyncService.instance.loadFromStorage();
    if (TokenSyncService.instance.hasToken) {
      _api.setAuthToken(TokenSyncService.instance.currentToken!);
      if (kDebugMode) debugPrint('ECG: loaded token from storage');
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // v3.0.168: Lưu LOGINNAME (key 'hispro_user') thay vì hiển thị USERNAME
      // Dropdown sẽ dùng LOGINNAME để tìm và hiển thị tên đầy đủ
      final loginname = prefs.getString('hispro_user') ?? prefs.getString('username') ?? 'nemk';
      if (mounted) {
        setState(() {
          // Hiển thị LOGINNAME ban đầu (sẽ tự động map sang tên đầy đủ khi user list load)
          _selectedBsChinhLogin = loginname;
          _bsChinhCtrl.text = loginname; // backup nếu dropdown fail
        });
      }
    } catch (_) {
      _selectedBsChinhLogin = 'nemk';
      _bsChinhCtrl.text = 'nemk';
    }
  }

  /// v3.0.163: Load danh sách máy phù hợp với service đang thực hiện
  /// Ưu tiên máy từ HIS_SERVICE_MACHINE (mapping), fallback GetAll
  Future<void> _loadMachines() async {
    setState(() => _loadingMachines = true);
    try {
      final serviceId = widget.serviceReq['SERVICE_ID'] ?? widget.serviceReq['service_id'];
      List<Map<String, dynamic>> machineList = [];

      if (serviceId != null) {
        // Lấy máy từ HIS_SERVICE_MACHINE (mapping với service)
        final r1 = await _api.getMachinesForService(int.tryParse(serviceId.toString()) ?? 0, limit: 50);
        if (r1.success && r1.data is Map) {
          final data = r1.data as Map;
          if (data['Data'] is List) {
            final mappings = (data['Data'] as List).where((m) => m['MACHINE_ID'] != null).toList();
            if (mappings.isNotEmpty) {
              // Lấy chi tiết từng máy
              final r2 = await _api.getAllMachines(limit: 200);
              if (r2.success && r2.data is Map) {
                final allData = r2.data as Map;
                if (allData['Data'] is List) {
                  final allMachines = (allData['Data'] as List).cast<Map<String, dynamic>>();
                  for (final mapping in mappings) {
                    final machineId = mapping['MACHINE_ID'];
                    final found = allMachines.firstWhere(
                      (m) => m['ID'] == machineId,
                      orElse: () => <String, dynamic>{},
                    );
                    if (found.isNotEmpty) machineList.add(found);
                  }
                }
              }
            }
          }
        }
      }

      // Fallback: nếu không có mapping, lấy tất cả máy có "điện tim" hoặc "ECG"
      if (machineList.isEmpty) {
        final r3 = await _api.getAllMachines(limit: 200);
        if (r3.success && r3.data is Map) {
          final allData = r3.data as Map;
          if (allData['Data'] is List) {
            final allMachines = (allData['Data'] as List).cast<Map<String, dynamic>>();
            machineList = allMachines.where((m) {
              final name = m['MACHINE_NAME']?.toString().toLowerCase() ?? '';
              return name.contains('điện tim') ||
                  name.contains('ecg') ||
                  name.contains('oxy') ||
                  name.contains('monitor');
            }).toList();
            if (machineList.isEmpty) machineList = allMachines;
          }
        }
      }

      if (mounted) {
        setState(() {
          _availableMachines = machineList;
          // Auto-select Máy tạo Oxy di động (ID=29) nếu có
          _selectedMachine = machineList.firstWhere(
            (m) => m['MACHINE_NAME']?.toString().contains('Oxy') == true,
            orElse: () => machineList.isNotEmpty ? machineList.first : <String, dynamic>{},
          );
          if (_selectedMachine?.isEmpty ?? true) _selectedMachine = null;
          _loadingMachines = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMachines = false;
          _debug = '⚠️ Lỗi load máy: $e';
        });
      }
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
    if ((_selectedBsChinhLogin ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vui lòng chọn Bác sĩ chính / PTV chính')),
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

      // v3.0.168: Lưu máy + kíp thực hiện (MACHINE_ID, EXECUTE_LOGINNAME, EXECUTE_USERNAME,...)
      final updateData = <String, dynamic>{
        'ID': int.tryParse(serviceReqId.toString()) ?? 0,
      };
      if (_selectedMachine != null) {
        final machineId = _selectedMachine!['ID'];
        final machineName = _selectedMachine!['MACHINE_NAME']?.toString() ?? '';
        updateData['MACHINE_ID'] = machineId;
        updateData['MACHINE_IDS'] = machineId.toString();
        updateData['MACHINE_NAME'] = machineName;
        updateData['MACHINE_NAMES'] = machineName;
        setState(() => _debug = '⏳ Đang lưu máy "$machineName"...');
      }
      // v3.0.168: Ghi kíp thực hiện (BS chính, điều dưỡng)
      if ((_selectedBsChinhLogin ?? '').isNotEmpty) {
        updateData['EXECUTE_LOGINNAME'] = _selectedBsChinhLogin;
        updateData['EXECUTE_USERNAME'] = _getFullName(_selectedBsChinhLogin);
      }
      if ((_selectedDdLogin ?? '').isNotEmpty) {
        updateData['NURSE_LOGINNAME'] = _selectedDdLogin;
        updateData['NURSE_USERNAME'] = _getFullName(_selectedDdLogin);
      }
      if (updateData.length > 1) {
        await _api.updateServiceReq(updateData);
      }

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
          // v3.0.165: NÚT TỰ LẤY TOKEN (multi-source) - ưu tiên hơn paste
          IconButton(
            icon: const Icon(Icons.cloud_sync, size: 18),
            tooltip: 'Tự lấy token tự động',
            onPressed: _autoFetchToken,
          ),
          // v3.0.164: Nút dán token HIS Pro (sync với procedure room + treatment history)
          IconButton(
            icon: const Icon(Icons.vpn_key, size: 18),
            tooltip: 'Dán token HIS Pro',
            onPressed: _showPasteTokenDialog,
          ),
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

                // v3.0.163: Chọn máy thực hiện
                _buildSectionTitle('🖥️ MÁY THỰC HIỆN (bắt buộc)', const Color(0xFF7B1FA2)),
                if (_loadingMachines)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Đang tải danh sách máy...', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    ]),
                  )
                else if (_availableMachines.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFFB74D)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.warning_amber, color: Color(0xFFE65100), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Không load được danh sách máy. Bấm Hoàn thành sẽ lưu không kèm máy.',
                          style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
                        ),
                      ),
                    ]),
                  )
                else
                  DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: _selectedMachine,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.medical_services, color: Color(0xFF7B1FA2)),
                      hintText: 'Chọn máy',
                    ),
                    items: _availableMachines.map((m) {
                      return DropdownMenuItem<Map<String, dynamic>>(
                        value: m,
                        child: Text(
                          '${m['MACHINE_NAME'] ?? 'N/A'} (${m['MACHINE_CODE'] ?? ''})',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (m) {
                      setState(() => _selectedMachine = m);
                    },
                    validator: (v) => v == null ? 'Vui lòng chọn máy' : null,
                  ),
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
                // v3.0.168: Dropdown Bác sĩ chính/PTV chính - hiển thị tên đầy đủ từ server
                if (_loadingUsers && _userList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Đang tải DS user từ server...', style: TextStyle(fontSize: 10, color: Colors.black54)),
                    ]),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _userList.any((u) => (u['LOGINNAME'] ?? '') == _selectedBsChinhLogin) ? _selectedBsChinhLogin : null,
                    decoration: const InputDecoration(
                      labelText: 'Bác sĩ chính / PTV chính *',
                      prefixIcon: Icon(Icons.medical_services, size: 18),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                    ),
                    items: _userList.map<DropdownMenuItem<String>>((u) {
                      final login = (u['LOGINNAME'] ?? '').toString();
                      final name = (u['USERNAME'] ?? login).toString();
                      return DropdownMenuItem<String>(
                        value: login,
                        child: Text(
                          '$name ($login)',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedBsChinhLogin = v;
                        // Sync backup text controller
                        _bsChinhCtrl.text = v ?? '';
                      });
                    },
                    validator: (v) => (v == null || v.isEmpty) ? 'Bắt buộc' : null,
                  ),
                const SizedBox(height: 8),
                // v3.0.168: Dropdown Điều dưỡng - optional
                if (_userList.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    value: _userList.any((u) => (u['LOGINNAME'] ?? '') == _selectedDdLogin) ? _selectedDdLogin : null,
                    decoration: const InputDecoration(
                      labelText: 'Điều dưỡng (không bắt buộc)',
                      prefixIcon: Icon(Icons.health_and_safety, size: 18),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('-- Không chọn --', style: TextStyle(fontSize: 12, color: Colors.black45)),
                      ),
                      ..._userList.map<DropdownMenuItem<String?>>((u) {
                        final login = (u['LOGINNAME'] ?? '').toString();
                        final name = (u['USERNAME'] ?? login).toString();
                        return DropdownMenuItem<String?>(
                          value: login,
                          child: Text(
                            '$name ($login)',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedDdLogin = v;
                        _ddCtrl.text = v ?? '';
                      });
                    },
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

  /// v3.0.165: TỰ LẤY TOKEN tự động (multi-source)
  /// - Proxy → Login API → Renew API → Hardcoded fallback
  /// - Apply cho cả HisApiService + HisProApiService + broadcast
  Future<void> _autoFetchToken() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Expanded(child: Text('🔄 Đang tự lấy token...', style: TextStyle(fontSize: 12))),
          ]),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 30),
        ),
      );
    }
    try {
      final event = await TokenSyncService.instance.autoFetchToken(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      if (event.token != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('✅ Token mới từ: ${event.source}')),
            ]),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.error, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('❌ Không lấy được token: ${event.message ?? "không rõ"}')),
            ]),
            backgroundColor: const Color(0xFFD32F2F),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: const Color(0xFFD32F2F)),
        );
      }
    }
  }

  /// v3.0.164: Dialog dán token HIS Pro (sync với procedure room + treatment history)
  /// - 1 paste → lưu vào SharedPreferences → tất cả API HIS Pro dùng token mới
  Future<void> _showPasteTokenDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentToken = prefs.getString('his_pro_token_override') ?? '';
    final controller = TextEditingController(text: currentToken);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.vpn_key, color: Color(0xFF6A1B9A)),
          SizedBox(width: 8),
          Text('Dán token HIS Pro', style: TextStyle(fontSize: 14)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Token HIS Pro xoay vòng mỗi session. Khi app báo lỗi:', style: TextStyle(fontSize: 11)),
              const SizedBox(height: 6),
              const Text('1. Mở HIS Desktop → file log', style: TextStyle(fontSize: 11)),
              const Text('2. Tìm dòng: dti:"...|...|TOKEN|..."', style: TextStyle(fontSize: 11)),
              const Text('3. Copy phần TOKEN (64 ký tự hex)', style: TextStyle(fontSize: 11)),
              const Text('4. Paste vào đây → Lưu', style: TextStyle(fontSize: 11, color: Color(0xFF6A1B9A), fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 2,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '805953ca1e7f5a67e86a21108b0b921f336041a2829214364d49ab83c724c575',
                  hintStyle: TextStyle(fontSize: 9, color: Colors.black38, fontFamily: 'monospace'),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 14),
            label: const Text('Lưu'),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );
    if (saved != null && saved.isNotEmpty) {
      // v3.0.165: Dùng TokenSyncService - 1 dòng áp dụng cho tất cả services + broadcast
      await TokenSyncService.instance.setManualToken(saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Đã lưu token: ${saved.substring(0, 8)}…${saved.substring(saved.length - 4)} (áp dụng mọi nơi)')),
            ]),
            backgroundColor: const Color(0xFF388E3C),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
