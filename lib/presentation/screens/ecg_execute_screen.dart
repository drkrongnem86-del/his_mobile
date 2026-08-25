// ECG Execute Screen v3.1.00 - Form thá»±c hiá»‡n ECG táº¡i phÃ²ng thá»­ thuáº­t HSCC
// v3.1.00: NEW - workflow thá»±c hiá»‡n ECG tá»« PhÃ²ng thá»­ thuáº­t
// - Header: thÃ´ng tin BN + yÃªu cáº§u dá»‹ch vá»¥
// - Form: thá»i gian báº¯t Ä‘áº§u/káº¿t thÃºc, káº¿t quáº£ ECG (required), káº¿t luáº­n, kÃ­p
// - Save + auto-finish: call api/HisServiceReq/FinishWithTime
// - Save draft: FormDraftService (backup local)
// - Return true â†’ caller (ProcedureRoom) auto-refresh + BN chuyá»ƒn sang "ÄÃ£ thá»±c hiá»‡n"
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
import 'package:his_mobile/presentation/widgets/user_picker_dialog.dart';  // v3.0.171: shared user picker
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:his_mobile/core/security/credentials.dart';
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
  final _ketQuaCtrl = TextEditingController(text: 'NHá»ŠP XOANG Äá»€U');
  final _ketLuanCtrl = TextEditingController();
  final _ghiChuCtrl = TextEditingController();
  // v3.0.171: 6 kÃ­p thá»±c hiá»‡n (sync vá»›i PhÃ²ng thá»§ thuáº­t HSCC)
  final _bsChinhCtrl = TextEditingController();
  final _ptvPhu1Ctrl = TextEditingController();
  final _ptvPhu2Ctrl = TextEditingController();
  final _gayMeChinhCtrl = TextEditingController();
  final _gayMePhuCtrl = TextEditingController();
  final _ddCtrl = TextEditingController();

  DateTime _startTime = DateTime.now();
  DateTime _endTime = DateTime.now().add(const Duration(minutes: 15));
  final List<File> _images = [];
  bool _saving = false;
  String _debug = '';

  // v3.0.163: Machine selection (MÃ¡y táº¡o Oxy di Ä‘á»™ng, MÃ¡y Ä‘iá»‡n tim 03 kÃªnh,...)
  Map<String, dynamic>? _selectedMachine;
  List<Map<String, dynamic>> _availableMachines = [];
  bool _loadingMachines = false;

  // v3.0.168: User list cho PTV/TTV chÃ­nh (BS, Ä‘iá»u dÆ°á»¡ng)
  // Hiá»ƒn thá»‹ tÃªn Ä‘áº§y Ä‘á»§ (USERNAME) nhÆ° HIS Desktop
  List<Map<String, dynamic>> _userList = [];
  String? _selectedBsChinhLogin;   // LOGINNAME BS chÃ­nh (báº¯t buá»™c)
  String? _selectedPtvPhu1Login;   // LOGINNAME PTV phá»¥ 1 (optional)
  String? _selectedPtvPhu2Login;   // LOGINNAME PTV phá»¥ 2 (optional)
  String? _selectedGayMeChinhLogin; // LOGINNAME GÃ¢y mÃª chÃ­nh (optional)
  String? _selectedGayMePhuLogin;  // LOGINNAME GÃ¢y mÃª phá»¥ (optional)
  String? _selectedDdLogin;        // LOGINNAME Äiá»u dÆ°á»¡ng (optional)
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    // v3.0.164: Auto-load token tá»« SharedPreferences (sync vá»›i procedure room)
    _loadHisProToken();
    _loadMachines();
    // v3.0.168: Load user list cho PTV/TTV chÃ­nh
    _loadUsers();
  }

  /// v3.0.168: Load danh sÃ¡ch users tá»« AcsUser (port 1401)
  /// - Filter: IS_ACTIVE=1, sáº¯p xáº¿p theo USERNAME
  /// - Hiá»ƒn thá»‹ tÃªn Ä‘áº§y Ä‘á»§ (USERNAME) trong dropdown
  /// - LÆ°u LOGINNAME Ä‘á»ƒ gá»­i cho backend
  /// - v3.0.169: Cache 2 giá» (SharedPreferences) - trÃ¡nh gá»i API má»—i láº§n má»Ÿ ECG
  static const String _kAcsUserCacheKey = 'acs_user_list_cache';
  static const String _kAcsUserCacheTimeKey = 'acs_user_list_cache_time';
  static const Duration _kAcsUserCacheTTL = Duration(hours: 2);

  Future<void> _loadUsers() async {
    if (_userList.isNotEmpty) return; // Ä‘Ã£ load
    setState(() => _loadingUsers = true);
    try {
      // v3.0.169: Thá»­ cache trÆ°á»›c (< 2h)
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

      // Cache miss hoáº·c stale â†’ gá»i API
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

          // v3.0.169: LÆ°u cache
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

  /// v3.0.168: Láº¥y USERNAME (tÃªn Ä‘áº§y Ä‘á»§) tá»« LOGINNAME
  String _getFullName(String? loginName) {
    if (loginName == null || loginName.isEmpty) return '';
    final found = _userList.firstWhere(
      (u) => (u['LOGINNAME'] ?? '').toString() == loginName,
      orElse: () => <String, dynamic>{},
    );
    if (found.isEmpty) return loginName; // fallback
    return (found['USERNAME'] ?? loginName).toString();
  }

  /// v3.0.171: Build 1 row trong KÃ­p thá»±c hiá»‡n (sync vá»›i PhÃ²ng thá»§ thuáº­t HSCC)
  /// - Hiá»ƒn thá»‹ "FullName (LOGINNAME)" hoáº·c "-- Chá»n --"
  /// - Tap icon search â†’ má»Ÿ UserPickerDialog vá»›i search filter
  /// - Required: hiá»ƒn thá»‹ * báº¯t buá»™c
  Widget _buildKipField({
    required String label,
    required IconData icon,
    required String? loginName,
    required TextEditingController displayCtrl,
    required ValueChanged<String?> onChanged,
    bool required = false,
  }) {
    final hasValue = loginName != null && loginName.isNotEmpty;
    final displayText = hasValue ? displayCtrl.text : '-- Chá»n --';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              labelStyle: const TextStyle(fontSize: 11),
              prefixIcon: Icon(icon, size: 18),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 12,
                color: hasValue ? Colors.black87 : Colors.black38,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.person_search, size: 20, color: Color(0xFF6A1B9A)),
          tooltip: 'Chá»n tá»« HIS Pro (cÃ³ search)',
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => UserPickerDialog(
                api: _api,
                departmentId: 22, // HSCC
                title: 'Chá»n $label',
                defaultLoginName: loginName,
                onSelected: (r) {
                  setState(() {
                    onChanged(r.loginName);
                    displayCtrl.text = '${r.fullName} (${r.loginName})';
                  });
                },
              ),
            );
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  /// v3.0.165: Auto-load HIS Pro token tá»« TokenSyncService khi má»Ÿ screen
  /// - Náº¿u TokenSyncService Ä‘Ã£ cÃ³ token â†’ dÃ¹ng luÃ´n
  /// - Náº¿u chÆ°a cÃ³ â†’ load tá»« storage hoáº·c auto-fetch
  Future<void> _loadHisProToken() async {
    if (TokenSyncService.instance.hasToken) {
      // ÄÃ£ cÃ³ tá»« trÆ°á»›c - dÃ¹ng luÃ´n
      _api.setAuthToken(TokenSyncService.instance.currentToken!);
      if (kDebugMode) debugPrint('ECG: using cached token');
      return;
    }
    // ChÆ°a cÃ³ â†’ load tá»« storage (silent - khÃ´ng hiá»‡n loading)
    await TokenSyncService.instance.loadFromStorage();
    if (TokenSyncService.instance.hasToken) {
      _api.setAuthToken(TokenSyncService.instance.currentToken!);
      if (kDebugMode) debugPrint('ECG: loaded token from storage');
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // v3.0.168: LÆ°u LOGINNAME (key 'hispro_user') thay vÃ¬ hiá»ƒn thá»‹ USERNAME
      // Dropdown sáº½ dÃ¹ng LOGINNAME Ä‘á»ƒ tÃ¬m vÃ  hiá»ƒn thá»‹ tÃªn Ä‘áº§y Ä‘á»§
      final loginname = prefs.getString('hispro_user') ?? prefs.getString('username') ?? Credentials.defaultNemkLogin;
      if (mounted) {
        setState(() {
          // Hiá»ƒn thá»‹ LOGINNAME ban Ä‘áº§u (sáº½ tá»± Ä‘á»™ng map sang tÃªn Ä‘áº§y Ä‘á»§ khi user list load)
          _selectedBsChinhLogin = loginname;
          _bsChinhCtrl.text = loginname; // backup náº¿u dropdown fail
        });
      }
    } catch (_) {
      _selectedBsChinhLogin = Credentials.defaultNemkLogin;
      _bsChinhCtrl.text = Credentials.defaultNemkLogin;
    }
  }

  /// v3.0.163: Load danh sÃ¡ch mÃ¡y phÃ¹ há»£p vá»›i service Ä‘ang thá»±c hiá»‡n
  /// Æ¯u tiÃªn mÃ¡y tá»« HIS_SERVICE_MACHINE (mapping), fallback GetAll
  Future<void> _loadMachines() async {
    setState(() => _loadingMachines = true);
    try {
      final serviceId = widget.serviceReq['SERVICE_ID'] ?? widget.serviceReq['service_id'];
      List<Map<String, dynamic>> machineList = [];

      if (serviceId != null) {
        // Láº¥y mÃ¡y tá»« HIS_SERVICE_MACHINE (mapping vá»›i service)
        final r1 = await _api.getMachinesForService(int.tryParse(serviceId.toString()) ?? 0, limit: 50);
        if (r1.success && r1.data is Map) {
          final data = r1.data as Map;
          if (data['Data'] is List) {
            final mappings = (data['Data'] as List).where((m) => m['MACHINE_ID'] != null).toList();
            if (mappings.isNotEmpty) {
              // Láº¥y chi tiáº¿t tá»«ng mÃ¡y
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

      // Fallback: náº¿u khÃ´ng cÃ³ mapping, láº¥y táº¥t cáº£ mÃ¡y cÃ³ "Ä‘iá»‡n tim" hoáº·c "ECG"
      if (machineList.isEmpty) {
        final r3 = await _api.getAllMachines(limit: 200);
        if (r3.success && r3.data is Map) {
          final allData = r3.data as Map;
          if (allData['Data'] is List) {
            final allMachines = (allData['Data'] as List).cast<Map<String, dynamic>>();
            machineList = allMachines.where((m) {
              final name = m['MACHINE_NAME']?.toString().toLowerCase() ?? '';
              return name.contains('Ä‘iá»‡n tim') ||
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
          // Auto-select MÃ¡y táº¡o Oxy di Ä‘á»™ng (ID=29) náº¿u cÃ³
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
          _debug = 'âš ï¸ Lá»—i load mÃ¡y: $e';
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
    _ptvPhu1Ctrl.dispose();
    _ptvPhu2Ctrl.dispose();
    _gayMeChinhCtrl.dispose();
    _gayMePhuCtrl.dispose();
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

  /// LÆ°u + auto-finish service req
  Future<bool> _saveAndFinish() async {
    if (!_formKey.currentState!.validate()) return false;
    if (_ketQuaCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('âš ï¸ Vui lÃ²ng nháº­p káº¿t quáº£ ECG')),
      );
      return false;
    }
    if ((_selectedBsChinhLogin ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('âš ï¸ Vui lÃ²ng chá»n BÃ¡c sÄ© chÃ­nh / PTV chÃ­nh')),
      );
      return false;
    }

    setState(() {
      _saving = true;
      _debug = 'â³ Äang lÆ°u ECG...';
    });

    try {
      // 1. LÆ°u local (FormDraftService) - backup
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
          _debug = 'âŒ Lá»—i: KhÃ´ng tÃ¬m tháº¥y ServiceReq ID';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('âŒ Lá»—i: KhÃ´ng tÃ¬m tháº¥y ServiceReq ID'), backgroundColor: Colors.red),
          );
        }
        return false;
      }

      setState(() => _debug = 'â³ Äang Ä‘Ã¡nh dáº¥u hoÃ n thÃ nh (FinishWithTime)...');

      // v3.0.168: LÆ°u mÃ¡y + kÃ­p thá»±c hiá»‡n (MACHINE_ID, EXECUTE_LOGINNAME, EXECUTE_USERNAME,...)
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
        setState(() => _debug = 'â³ Äang lÆ°u mÃ¡y "$machineName"...');
      }
      // v3.0.171: Ghi 6 kÃ­p thá»±c hiá»‡n (sync vá»›i PhÃ²ng thá»§ thuáº­t HSCC)
      void addKip(String? login, String fullNameKey, String loginNameKey) {
        if ((login ?? '').isNotEmpty) {
          updateData[loginNameKey] = login;
          updateData[fullNameKey] = _getFullName(login);
        }
      }
      addKip(_selectedBsChinhLogin, 'EXECUTE_USERNAME', 'EXECUTE_LOGINNAME');
      addKip(_selectedPtvPhu1Login, 'PTV_PHU_1_USERNAME', 'PTV_PHU_1_LOGINNAME');
      addKip(_selectedPtvPhu2Login, 'PTV_PHU_2_USERNAME', 'PTV_PHU_2_LOGINNAME');
      addKip(_selectedGayMeChinhLogin, 'GAY_ME_CHINH_USERNAME', 'GAY_ME_CHINH_LOGINNAME');
      addKip(_selectedGayMePhuLogin, 'GAY_ME_PHU_USERNAME', 'GAY_ME_PHU_LOGINNAME');
      addKip(_selectedDdLogin, 'NURSE_USERNAME', 'NURSE_LOGINNAME');
      if (updateData.length > 1) {
        await _api.updateServiceReq(updateData);
      }

      final finishResult = await _api.finishServiceReqWithTime(
        serviceReqId: int.tryParse(serviceReqId.toString()) ?? 0,
        startTime: _startTime,
        endTime: _endTime,
        resultNote: '${_ketQuaCtrl.text}${_ketLuanCtrl.text.isNotEmpty ? '\n\nKáº¿t luáº­n: ${_ketLuanCtrl.text}' : ''}${_ghiChuCtrl.text.isNotEmpty ? '\n\nGhi chÃº: ${_ghiChuCtrl.text}' : ''}',
      );

      if (!mounted) return false;

      if (finishResult.success) {
        setState(() {
          _saving = false;
          _debug = 'âœ… HoÃ n thÃ nh! ServiceReq #${serviceReqId} â†’ status=3 (HoÃ n thÃ nh)';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âœ… ÄÃ£ hoÃ n thÃ nh ECG${_images.isNotEmpty ? " + ${_images.length} áº£nh" : ""}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        // Tráº£ vá» true Ä‘á»ƒ caller (ProcedureRoom) reload
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context, true);
        });
        return true;
      } else {
        setState(() {
          _saving = false;
          _debug = 'âŒ Lá»—i finish: ${finishResult.message}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âŒ Lá»—i: ${finishResult.message}'),
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
        _debug = 'âŒ Exception: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('âŒ Lá»—i: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  String _calculateAge() {
    final dobStr = _g('TDL_PATIENT_DOB', 'tdl_patient_dob');
    if (dobStr.isEmpty) return 'â€”';
    try {
      final dob = int.parse(dobStr);
      final dobDate = DateTime(dob ~/ 10000, (dob ~/ 100) % 100, dob % 100);
      final now = DateTime.now();
      var age = now.year - dobDate.year;
      if (now.month < dobDate.month || (now.month == dobDate.month && now.day < dobDate.day)) {
        age--;
      }
      return '$age tuá»•i';
    } catch (_) {
      return 'â€”';
    }
  }

  String _formatDob() {
    final dobStr = _g('TDL_PATIENT_DOB', 'tdl_patient_dob');
    if (dobStr.isEmpty) return 'â€”';
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
          SnackBar(content: Text('Lá»—i chá»n áº£nh: $e'), backgroundColor: Colors.red),
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
        title: const Text('Thá»±c hiá»‡n ECG', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          // v3.0.165: NÃšT Tá»° Láº¤Y TOKEN (multi-source) - Æ°u tiÃªn hÆ¡n paste
          IconButton(
            icon: const Icon(Icons.cloud_sync, size: 18),
            tooltip: 'Tá»± láº¥y token tá»± Ä‘á»™ng',
            onPressed: _autoFetchToken,
          ),
          // v3.0.164: NÃºt dÃ¡n token HIS Pro (sync vá»›i procedure room + treatment history)
          IconButton(
            icon: const Icon(Icons.vpn_key, size: 18),
            tooltip: 'DÃ¡n token HIS Pro',
            onPressed: _showPasteTokenDialog,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'HÆ°á»›ng dáº«n',
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
                // Thá»i gian
                _buildSectionTitle('â± THá»œI GIAN THá»°C HIá»†N', const Color(0xFFD32F2F)),
                Row(children: [
                  Expanded(child: _buildDateTimeField('Báº¯t Ä‘áº§u', _startTime, () => _pickDateTime(isStart: true))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDateTimeField('Káº¿t thÃºc', _endTime, () => _pickDateTime(isStart: false))),
                ]),
                const SizedBox(height: 12),

                // v3.0.163: Chá»n mÃ¡y thá»±c hiá»‡n
                _buildSectionTitle('ðŸ–¥ï¸ MÃY THá»°C HIá»†N (báº¯t buá»™c)', const Color(0xFF7B1FA2)),
                if (_loadingMachines)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Äang táº£i danh sÃ¡ch mÃ¡y...', style: TextStyle(fontSize: 11, color: Colors.black54)),
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
                          'KhÃ´ng load Ä‘Æ°á»£c danh sÃ¡ch mÃ¡y. Báº¥m HoÃ n thÃ nh sáº½ lÆ°u khÃ´ng kÃ¨m mÃ¡y.',
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
                      hintText: 'Chá»n mÃ¡y',
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
                    validator: (v) => v == null ? 'Vui lÃ²ng chá»n mÃ¡y' : null,
                  ),
                const SizedBox(height: 12),

                // Káº¿t quáº£
                _buildSectionTitle('ðŸ“‹ Káº¾T QUáº¢ ECG (báº¯t buá»™c)', const Color(0xFF1976D2)),
                TextFormField(
                  controller: _ketQuaCtrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: 'VD: NHá»ŠP XOANG Äá»€U Táº¦N Sá» 82 Láº¦N / PHÃšT\nTrá»¥c Ä‘iá»‡n tim: bÃ¬nh thÆ°á»ng\nKhÃ´ng tháº¥y dáº¥u hiá»‡u nhá»“i mÃ¡u cÆ¡ tim cáº¥p...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lÃ²ng nháº­p káº¿t quáº£ ECG' : null,
                ),
                const SizedBox(height: 8),

                // Káº¿t luáº­n
                _buildSectionTitle('ðŸ” Káº¾T LUáº¬N', const Color(0xFF388E3C)),
                TextFormField(
                  controller: _ketLuanCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Káº¿t luáº­n cá»§a bÃ¡c sÄ© (khÃ´ng báº¯t buá»™c)',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),

                // Ghi chÃº
                _buildSectionTitle('ðŸ“ GHI CHÃš', const Color(0xFF616161)),
                TextFormField(
                  controller: _ghiChuCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Ghi chÃº thÃªm (khÃ´ng báº¯t buá»™c)',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // HÃ¬nh áº£nh Ä‘Ã­nh kÃ¨m
                _buildSectionTitle('ðŸ“· HÃŒNH áº¢NH ÄÃNH KÃˆM (${_images.length})', const Color(0xFF7B1FA2)),
                _buildImagePicker(),
                const SizedBox(height: 12),

                // KÃ­p thá»±c hiá»‡n (v3.0.171: sync vá»›i PhÃ²ng thá»§ thuáº­t HSCC - 6 vá»‹ trÃ­)
                _buildSectionTitle('ðŸ‘¥ KÃP THá»°C HIá»†N', const Color(0xFFE65100)),
                if (_loadingUsers && _userList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Äang táº£i DS user tá»« server...', style: TextStyle(fontSize: 10, color: Colors.black54)),
                    ]),
                  )
                else ...[
                  // v3.0.171: 6 kÃ­p thá»±c hiá»‡n - Ä‘á»“ng bá»™ vá»›i PhÃ²ng thá»§ thuáº­t HSCC
                  _buildKipField(
                    label: 'BS / PTV chÃ­nh',
                    icon: Icons.medical_services,
                    loginName: _selectedBsChinhLogin,
                    displayCtrl: _bsChinhCtrl,
                    onChanged: (v) => _selectedBsChinhLogin = v,
                    required: true,
                  ),
                  _buildKipField(
                    label: 'PTV phá»¥ 1',
                    icon: Icons.medical_services_outlined,
                    loginName: _selectedPtvPhu1Login,
                    displayCtrl: _ptvPhu1Ctrl,
                    onChanged: (v) => _selectedPtvPhu1Login = v,
                  ),
                  _buildKipField(
                    label: 'PTV phá»¥ 2',
                    icon: Icons.medical_services_outlined,
                    loginName: _selectedPtvPhu2Login,
                    displayCtrl: _ptvPhu2Ctrl,
                    onChanged: (v) => _selectedPtvPhu2Login = v,
                  ),
                  _buildKipField(
                    label: 'GÃ¢y mÃª chÃ­nh',
                    icon: Icons.healing,
                    loginName: _selectedGayMeChinhLogin,
                    displayCtrl: _gayMeChinhCtrl,
                    onChanged: (v) => _selectedGayMeChinhLogin = v,
                  ),
                  _buildKipField(
                    label: 'GÃ¢y mÃª phá»¥ 1',
                    icon: Icons.healing_outlined,
                    loginName: _selectedGayMePhuLogin,
                    displayCtrl: _gayMePhuCtrl,
                    onChanged: (v) => _selectedGayMePhuLogin = v,
                  ),
                  _buildKipField(
                    label: 'Äiá»u dÆ°á»¡ng',
                    icon: Icons.health_and_safety,
                    loginName: _selectedDdLogin,
                    displayCtrl: _ddCtrl,
                    onChanged: (v) => _selectedDdLogin = v,
                  ),
                ],
                const SizedBox(height: 12),

                // Debug
                if (_debug.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _debug.startsWith('âœ…')
                          ? const Color(0xFFE8F5E9)
                          : _debug.startsWith('âŒ')
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
                    child: Text('MÃ£ BN: $_patientCode', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                if (_treatmentCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                    child: Text('ÄT: $_treatmentCode', style: const TextStyle(color: Colors.white, fontSize: 10)),
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
                _serviceName.isNotEmpty ? _serviceName : 'Ghi Ä‘iá»‡n tim cáº¥p cá»©u táº¡i giÆ°á»ng',
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
            label: const Text('Chá»¥p áº£nh', style: TextStyle(fontSize: 12)),
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
            label: const Text('ThÆ° viá»‡n', style: TextStyle(fontSize: 12)),
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
              label: const Text('Há»§y', style: TextStyle(fontSize: 12)),
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
                _saving ? 'Äang lÆ°u...' : 'HoÃ n thÃ nh & Káº¿t thÃºc',
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

  /// v3.0.165: Tá»° Láº¤Y TOKEN tá»± Ä‘á»™ng (multi-source)
  /// - Proxy â†’ Login API â†’ Renew API â†’ Hardcoded fallback
  /// - Apply cho cáº£ HisApiService + HisProApiService + broadcast
  Future<void> _autoFetchToken() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Expanded(child: Text('ðŸ”„ Äang tá»± láº¥y token...', style: TextStyle(fontSize: 12))),
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
              Expanded(child: Text('âœ… Token má»›i tá»«: ${event.source}')),
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
              Expanded(child: Text('âŒ KhÃ´ng láº¥y Ä‘Æ°á»£c token: ${event.message ?? "khÃ´ng rÃµ"}')),
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
          SnackBar(content: Text('âŒ Lá»—i: $e'), backgroundColor: const Color(0xFFD32F2F)),
        );
      }
    }
  }

  /// v3.0.164: Dialog dÃ¡n token HIS Pro (sync vá»›i procedure room + treatment history)
  /// - 1 paste â†’ lÆ°u vÃ o SharedPreferences â†’ táº¥t cáº£ API HIS Pro dÃ¹ng token má»›i
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
          Text('DÃ¡n token HIS Pro', style: TextStyle(fontSize: 14)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Token HIS Pro xoay vÃ²ng má»—i session. Khi app bÃ¡o lá»—i:', style: TextStyle(fontSize: 11)),
              const SizedBox(height: 6),
              const Text('1. Má»Ÿ HIS Desktop â†’ file log', style: TextStyle(fontSize: 11)),
              const Text('2. TÃ¬m dÃ²ng: dti:"...|...|TOKEN|..."', style: TextStyle(fontSize: 11)),
              const Text('3. Copy pháº§n TOKEN (64 kÃ½ tá»± hex)', style: TextStyle(fontSize: 11)),
              const Text('4. Paste vÃ o Ä‘Ã¢y â†’ LÆ°u', style: TextStyle(fontSize: 11, color: Color(0xFF6A1B9A), fontWeight: FontWeight.w600)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Há»§y')),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 14),
            label: const Text('LÆ°u'),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );
    if (saved != null && saved.isNotEmpty) {
      // v3.0.165: DÃ¹ng TokenSyncService - 1 dÃ²ng Ã¡p dá»¥ng cho táº¥t cáº£ services + broadcast
      await TokenSyncService.instance.setManualToken(saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('ÄÃ£ lÆ°u token: ${saved.substring(0, 8)}â€¦${saved.substring(saved.length - 4)} (Ã¡p dá»¥ng má»i nÆ¡i)')),
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
        title: const Text('HÆ°á»›ng dáº«n thá»±c hiá»‡n ECG'),
        content: const SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('1. Chá»n thá»i gian báº¯t Ä‘áº§u vÃ  káº¿t thÃºc', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('2. Nháº­p káº¿t quáº£ Ä‘iá»‡n tim (báº¯t buá»™c)', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('3. Nháº­p káº¿t luáº­n (náº¿u cÃ³)', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('4. ÄÃ­nh kÃ¨m áº£nh ECG (náº¿u cÃ³)', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('5. Nháº­p tÃªn BÃ¡c sÄ© chÃ­nh (báº¯t buá»™c)', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('6. Nháº¥n "HoÃ n thÃ nh & Káº¿t thÃºc"', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('LÆ°u Ã½: Sau khi lÆ°u, BN sáº½ tá»± Ä‘á»™ng chuyá»ƒn sang tráº¡ng thÃ¡i "ÄÃ£ thá»±c hiá»‡n" trong PhÃ²ng thá»­ thuáº­t. Äá»ƒ Ä‘áº©y EMR, dÃ¹ng menu "ÄÃ­nh kÃ¨m tÃ i liá»‡u" trong thao tÃ¡c BN.', style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ÄÃ³ng')),
        ],
      ),
    );
  }
}
