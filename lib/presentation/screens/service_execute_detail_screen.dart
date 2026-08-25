// ServiceExecuteDetailScreen v3.1.05 - MÃ n hÃ¬nh thá»±c hiá»‡n dá»‹ch vá»¥ (Xá»­ lÃ½ yÃªu cáº§u khÃ¡m/cls/pttt)
// Workflow giá»‘ng HIS Desktop "Xá»­ lÃ½ yÃªu cáº§u khÃ¡m/cls/pttt (PhÃ²ng TT Khoa Cáº¥p Cá»©u)":
// - Top: ThÃ´ng tin BN (mÃ£, tÃªn, nÄƒm sinh, giá»›i tÃ­nh, khoa, ICD, ngÃ y y lá»‡nh)
// - Center: Form "PHIáº¾U ÄIá»†N TIM" / "PHIáº¾U KHÃM" / etc. vá»›i:
//   + Dá»‹ch vá»¥ yÃªu cáº§u (list, multi-select)
//   + HÃ¬nh áº£nh: GÃ³p káº¿t quáº£ + LÆ°u áº£nh + ÄÃ­nh kÃ¨m áº£nh (3 tab)
//   + Thá»i gian: Báº¯t Ä‘áº§u + Káº¿t thÃºc + Giá» GPBL
//   + Káº¿t quáº£ (multiline) + Káº¿t luáº­n + Ghi chÃº
//   + KÃ­p thá»±c hiá»‡n: 5 vá»‹ trÃ­ (PTV chÃ­nh + PTV phá»¥ 1+2 + GÃ¢y mÃª chÃ­nh + GÃ¢y mÃª phá»¥ 1)
//   + NÃºt "HoÃ n thÃ nh" â†’ call FinishWithTime â†’ EMR push (optional)
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/services/form_draft_service.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';
import 'package:his_mobile/presentation/widgets/user_picker_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:his_mobile/core/security/credentials.dart';
import 'package:intl/intl.dart' as intl;

class ServiceExecuteDetailScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final List<Map<String, dynamic>>? serviceReqs; // danh sÃ¡ch dá»‹ch vá»¥ cá»§a BN (optional, máº·c Ä‘á»‹nh 1)
  final int? executeRoomId;
  final int? executeDepartmentId;
  const ServiceExecuteDetailScreen({
    super.key,
    required this.patient,
    this.serviceReqs,
    this.executeRoomId,
    this.executeDepartmentId,
  });

  @override
  State<ServiceExecuteDetailScreen> createState() => _ServiceExecuteDetailScreenState();
}

class _ServiceExecuteDetailScreenState extends State<ServiceExecuteDetailScreen> with SingleTickerProviderStateMixin {
  final HisApiService _api = HisApiService();
  late TabController _tabCtrl;

  // Controllers
  final _ketQuaCtrl = TextEditingController(text: '');
  final _ketLuanCtrl = TextEditingController();
  final _ghiChuCtrl = TextEditingController();
  final _moTaCtrl = TextEditingController();
  final _phuongPhapCtrl = TextEditingController();
  final _bsChinhCtrl = TextEditingController();
  final _ptvPhu1Ctrl = TextEditingController();
  final _ptvPhu2Ctrl = TextEditingController();
  final _gayMeChinhCtrl = TextEditingController();
  final _gayMePhuCtrl = TextEditingController();
  final _ddCtrl = TextEditingController();

  DateTime _startTime = DateTime.now();
  DateTime _endTime = DateTime.now().add(const Duration(minutes: 15));
  DateTime? _gpblTime;
  final List<File> _images = []; // áº£nh Ä‘Ã­nh kÃ¨m
  final List<int> _selectedServiceIds = []; // id cÃ¡c dá»‹ch vá»¥ Ä‘Æ°á»£c chá»n Ä‘á»ƒ thá»±c hiá»‡n
  bool _saving = false;
  String _debug = '';

  // v3.1.05: Tabs hÃ¬nh áº£nh
  int _imageTab = 0; // 0=GÃ³p káº¿t quáº£, 1=LÆ°u áº£nh, 2=ÄÃ­nh kÃ¨m áº£nh

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadCurrentUser();
    // Pre-select all serviceReqs
    if (widget.serviceReqs != null) {
      for (final s in widget.serviceReqs!) {
        final id = s['ID'] ?? s['id'];
        if (id != null) _selectedServiceIds.add(int.tryParse(id.toString()) ?? 0);
      }
    } else {
      // Single serviceReq case
      final id = widget.patient['ID'] ?? widget.patient['id'];
      if (id != null) _selectedServiceIds.add(int.tryParse(id.toString()) ?? 0);
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      // Máº·c Ä‘á»‹nh = tÃªn Ä‘Äƒng nháº­p hiá»‡n táº¡i (tá»« SharedPreferences)
      // ignore: deprecated_member_use
      // final username = await ...;
      // For now: dÃ¹ng tÃªn tá»« patient context
      _bsChinhCtrl.text = Credentials.defaultNemkLogin;
    } catch (_) {
      _bsChinhCtrl.text = Credentials.defaultNemkLogin;
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _ketQuaCtrl.dispose();
    _ketLuanCtrl.dispose();
    _ghiChuCtrl.dispose();
    _moTaCtrl.dispose();
    _phuongPhapCtrl.dispose();
    _bsChinhCtrl.dispose();
    _ptvPhu1Ctrl.dispose();
    _ptvPhu2Ctrl.dispose();
    _gayMeChinhCtrl.dispose();
    _gayMePhuCtrl.dispose();
    _ddCtrl.dispose();
    super.dispose();
  }

  String _g(String k1, [String? k2]) =>
      (widget.patient[k1] ?? widget.patient[k2 ?? ''] ?? '').toString();

  String get _patientName => fixVietnameseMojibake(PatientNameHelper.getName(widget.patient));
  String get _patientCode => _g('TDL_PATIENT_CODE', 'tdl_patient_code');
  String get _treatmentCode => _g('TDL_TREATMENT_CODE', 'treatment_code');
  String get _serviceReqCode => _g('SERVICE_REQ_CODE', 'service_req_code');
  String get _serviceName => _g('SERVICE_NAME', 'service_name');
  String get _icdName => _g('ICD_NAME', 'icd_name');
  String get _icdCode => _g('ICD_CODE', 'icd_code');
  String get _bedName => _g('BED_NAME', 'bed_name');
  String get _sttName => _g('SERVICE_REQ_STT_NAME', 'service_req_stt_name');
  String get _deptName => _g('REQUEST_DEPARTMENT_NAME', 'request_department_name');
  String get _instructionTime => _g('INTRUCTION_TIME', 'intruction_time');
  String get _note => _g('NOTE', 'note');
  int get _priority => int.tryParse(_g('PRIORITY', 'priority')) ?? 0;
  int get _numOrder => int.tryParse(_g('NUM_ORDER', 'num_order')) ?? 0;

  Future<void> _pickDateTime({required bool isStart, required bool isGpbl}) async {
    DateTime init;
    if (isGpbl) {
      init = _gpblTime ?? DateTime.now();
    } else if (isStart) {
      init = _startTime;
    } else {
      init = _endTime;
    }
    final date = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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
      if (isGpbl) {
        _gpblTime = newDt;
      } else if (isStart) {
        _startTime = newDt;
        if (_endTime.isBefore(_startTime)) _endTime = _startTime.add(const Duration(minutes: 15));
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

  String _toHisLong(DateTime dt) {
    return (dt.year * 10000000000 + dt.month * 100000000 + dt.day * 1000000 + dt.hour * 100 + dt.minute).toString();
  }

  /// v3.1.05: LÆ°u + auto-finish táº¥t cáº£ dá»‹ch vá»¥ Ä‘Æ°á»£c chá»n
  Future<bool> _saveAndFinish() async {
    if (_ketQuaCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('âš ï¸ Vui lÃ²ng nháº­p káº¿t quáº£ trÆ°á»›c khi lÆ°u')),
      );
      return false;
    }
    if (_bsChinhCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('âš ï¸ Vui lÃ²ng nháº­p BÃ¡c sÄ© chÃ­nh')),
      );
      return false;
    }
    if (_selectedServiceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('âš ï¸ ChÆ°a chá»n dá»‹ch vá»¥ nÃ o')),
      );
      return false;
    }

    setState(() {
      _saving = true;
      _debug = 'â³ Äang xá»­ lÃ½ ${_selectedServiceIds.length} dá»‹ch vá»¥...';
    });

    try {
      // 1. LÆ°u local (FormDraftService) - backup
      final formData = {
        'form': 'SERVICE_EXECUTE',
        'patient_code': _patientCode,
        'treatment_code': _treatmentCode,
        'service_req_codes': _selectedServiceIds,
        'start_time': _startTime.toIso8601String(),
        'end_time': _endTime.toIso8601String(),
        'gpbl_time': _gpblTime?.toIso8601String(),
        'ket_qua': _ketQuaCtrl.text,
        'ket_luan': _ketLuanCtrl.text,
        'ghi_chu': _ghiChuCtrl.text,
        'mo_ta': _moTaCtrl.text,
        'phuong_phap': _phuongPhapCtrl.text,
        'bs_chinh': _bsChinhCtrl.text,
        'ptv_phu_1': _ptvPhu1Ctrl.text,
        'ptv_phu_2': _ptvPhu2Ctrl.text,
        'gay_me_chinh': _gayMeChinhCtrl.text,
        'gay_me_phu': _gayMePhuCtrl.text,
        'dd': _ddCtrl.text,
        'images_count': _images.length,
        'created_at': DateTime.now().toIso8601String(),
      };
      try {
        await FormDraftService.instance.saveDraft(
          'SERVICE_EXECUTE',
          _patientCode.isNotEmpty ? _patientCode : _treatmentCode,
          formData,
          <String, List<dynamic>>{'images': _images.map((f) => f.path).toList()},
        );
      } catch (e) {
        debugPrint('FormDraftService save error: $e');
      }

      // 2. Call finishServiceReqWithTime cho tá»«ng dá»‹ch vá»¥ Ä‘Æ°á»£c chá»n
      int successCount = 0;
      String lastError = '';
      for (final serviceReqId in _selectedServiceIds) {
        setState(() => _debug = 'â³ FinishWithTime $serviceReqId... ($successCount/${_selectedServiceIds.length} xong)');
        final result = await _api.finishServiceReqWithTime(
          serviceReqId: serviceReqId,
          startTime: _startTime,
          endTime: _endTime,
          resultNote: _buildResultNote(),
        );
        if (result.success) {
          successCount++;
        } else {
          lastError = result.message ?? 'Lá»—i khÃ´ng xÃ¡c Ä‘á»‹nh';
          debugPrint('finishServiceReq $serviceReqId failed: $lastError');
        }
      }

      if (!mounted) return false;

      if (successCount == _selectedServiceIds.length) {
        setState(() {
          _saving = false;
          _debug = 'âœ… HoÃ n thÃ nh $successCount dá»‹ch vá»¥';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âœ… ÄÃ£ hoÃ n thÃ nh $successCount dá»‹ch vá»¥${_images.isNotEmpty ? " + ${_images.length} áº£nh" : ""}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context, true);
        });
        return true;
      } else {
        setState(() {
          _saving = false;
          _debug = 'âš ï¸ $successCount/${_selectedServiceIds.length} xong. Lá»—i cuá»‘i: $lastError';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âš ï¸ $successCount/${_selectedServiceIds.length} OK. $lastError'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _debug = 'âŒ Lá»—i: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('âŒ Lá»—i: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  String _buildResultNote() {
    final parts = <String>[];
    if (_ketQuaCtrl.text.isNotEmpty) parts.add('Káº¿t quáº£: ${_ketQuaCtrl.text}');
    if (_moTaCtrl.text.isNotEmpty) parts.add('MÃ´ táº£: ${_moTaCtrl.text}');
    if (_phuongPhapCtrl.text.isNotEmpty) parts.add('PhÆ°Æ¡ng phÃ¡p: ${_phuongPhapCtrl.text}');
    if (_ketLuanCtrl.text.isNotEmpty) parts.add('\nKáº¿t luáº­n: ${_ketLuanCtrl.text}');
    if (_ghiChuCtrl.text.isNotEmpty) parts.add('\nGhi chÃº: ${_ghiChuCtrl.text}');
    if (_bsChinhCtrl.text.isNotEmpty) parts.add('\nBS: ${_bsChinhCtrl.text}');
    if (_ptvPhu1Ctrl.text.isNotEmpty) parts.add('PTV phá»¥ 1: ${_ptvPhu1Ctrl.text}');
    if (_ptvPhu2Ctrl.text.isNotEmpty) parts.add('PTV phá»¥ 2: ${_ptvPhu2Ctrl.text}');
    if (_gayMeChinhCtrl.text.isNotEmpty) parts.add('GM chÃ­nh: ${_gayMeChinhCtrl.text}');
    if (_ddCtrl.text.isNotEmpty) parts.add('ÄD: ${_ddCtrl.text}');
    return parts.join(' | ');
  }

  String _formatHisLong(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.length < 8) return s;
    try {
      final y = s.substring(0, 4);
      final mo = s.substring(4, 6);
      final d = s.substring(6, 8);
      if (s.length >= 12) {
        final h = s.substring(8, 10);
        final mi = s.substring(10, 12);
        return '$h:$mi $d/$mo/$y';
      }
      return '$d/$mo/$y';
    } catch (_) {
      return s;
    }
  }

  String _formatDob() {
    final dob = _g('TDL_PATIENT_DOB', 'tdl_patient_dob');
    if (dob.isEmpty) return '';
    try {
      final s = dob.length >= 8 ? dob.substring(0, 8) : dob;
      final y = s.substring(0, 4);
      final mo = s.substring(4, 6);
      final d = s.substring(6, 8);
      return '$d/$mo/$y';
    } catch (_) {
      return dob;
    }
  }

  String _formatDateTime(DateTime dt) {
    return intl.DateFormat('HH:mm dd/MM/yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        title: Text('Xá»­ lÃ½ yÃªu cáº§u - $_serviceName', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'LÆ°u + Káº¿t thÃºc',
            onPressed: _saving ? null : _saveAndFinish,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.amber,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.assignment_turned_in, size: 14), text: 'GÃ³p káº¿t quáº£'),
            Tab(icon: Icon(Icons.save_alt, size: 14), text: 'LÆ°u áº£nh'),
            Tab(icon: Icon(Icons.attach_file, size: 14), text: 'ÄÃ­nh kÃ¨m'),
          ],
        ),
      ),
      body: Column(children: [
        // ===== USER HEADER =====
        UserHeader.fromAuth(compact: true),
        // ===== PATIENT INFO BAR (giá»‘ng HIS Desktop "ThÃ´ng tin bá»‡nh nhÃ¢n") =====
        _buildPatientInfoBar(),
        // ===== 3 TABS CONTENT =====
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildResultTab(),
              _buildSaveImageTab(),
              _buildAttachTab(),
            ],
          ),
        ),
        // ===== DEBUG =====
        if (_debug.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            color: const Color(0xFFE0F2F1),
            child: Text(_debug, style: const TextStyle(fontSize: 10, color: Color(0xFF00695C))),
          ),
        // ===== ACTION BUTTONS =====
        _buildActionButtons(),
      ]),
    );
  }

  /// v3.1.05: Thanh thÃ´ng tin BN (compact - giá»‘ng HIS Desktop bÃªn pháº£i)
  Widget _buildPatientInfoBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
        ),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
          child: Center(child: Text(
            _patientName.isNotEmpty ? _patientName[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_patientName, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${_patientCode.isNotEmpty ? "MÃ£ BN: $_patientCode" : ""}${_treatmentCode.isNotEmpty ? " â€¢ ÄT: $_treatmentCode" : ""}',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              if (_icdName.isNotEmpty)
                Text(
                  'ICD: ${_icdCode.isNotEmpty ? "$_icdCode - " : ""}$_icdName',
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontStyle: FontStyle.italic),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (_priority == 2)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(4)),
            child: const Text('Æ¯U TIÃŠN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
      ]),
    );
  }

  /// v3.1.05: Tab "GÃ³p káº¿t quáº£" - Form thá»±c hiá»‡n (giá»‘ng HIS Desktop PHIáº¾U ÄIá»†N TIM)
  Widget _buildResultTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Dá»‹ch vá»¥ yÃªu cáº§u (checkboxes)
        if (widget.serviceReqs != null && widget.serviceReqs!.length > 1) ...[
          _sectionTitleWithIcon('Dá»ŠCH Vá»¤ YÃŠU Cáº¦U', Icons.assignment, const Color(0xFF303F9F)),
          ...widget.serviceReqs!.map((s) {
            final id = int.tryParse((s['ID'] ?? s['id'] ?? '0').toString()) ?? 0;
            final name = (s['SERVICE_NAME'] ?? s['service_name'] ?? '').toString();
            final code = (s['SERVICE_REQ_CODE'] ?? s['service_req_code'] ?? '').toString();
            final checked = _selectedServiceIds.contains(id);
            return CheckboxListTile(
              value: checked,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    if (!_selectedServiceIds.contains(id)) _selectedServiceIds.add(id);
                  } else {
                    _selectedServiceIds.remove(id);
                  }
                });
              },
              title: Text('$name', style: const TextStyle(fontSize: 12)),
              subtitle: Text(code, style: const TextStyle(fontSize: 10, color: Colors.black54)),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            );
          }),
          const SizedBox(height: 8),
        ],
        // Thá»i gian
        _sectionTitle('â± THá»œI GIAN', const Color(0xFF303F9F)),
        Row(children: [
          Expanded(child: _dateTimeField('Báº¯t Ä‘áº§u', _startTime, () => _pickDateTime(isStart: true, isGpbl: false))),
          const SizedBox(width: 6),
          Expanded(child: _dateTimeField('Káº¿t thÃºc', _endTime, () => _pickDateTime(isStart: false, isGpbl: false))),
        ]),
        const SizedBox(height: 6),
        _dateTimeField('Giá» GPBL (tráº£ káº¿t quáº£)', _gpblTime, () => _pickDateTime(isStart: false, isGpbl: true), isOptional: true),
        const SizedBox(height: 10),
        // Káº¿t quáº£
        _sectionTitle('ðŸ“‹ Káº¾T QUáº¢', const Color(0xFF1976D2)),
        TextField(
          controller: _ketQuaCtrl,
          minLines: 4, maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Nháº­p káº¿t quáº£ (báº¯t buá»™c) - VD: "NHá»ŠP XOANG Äá»€U Táº¦N Sá» 82 Láº¦N / PHÃšT"',
            border: OutlineInputBorder(), filled: true, fillColor: Colors.white, isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        // MÃ´ táº£ + PhÆ°Æ¡ng phÃ¡p
        _sectionTitle('ðŸ“ MÃ” Táº¢', const Color(0xFF616161)),
        TextField(
          controller: _moTaCtrl,
          minLines: 2, maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'MÃ´ táº£ chi tiáº¿t (khÃ´ng báº¯t buá»™c)',
            border: OutlineInputBorder(), filled: true, fillColor: Colors.white, isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        _sectionTitle('ðŸ”¬ PHÆ¯Æ NG PHÃP', const Color(0xFF00897B)),
        TextField(
          controller: _phuongPhapCtrl,
          minLines: 1, maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'PhÆ°Æ¡ng phÃ¡p thá»±c hiá»‡n (khÃ´ng báº¯t buá»™c)',
            border: OutlineInputBorder(), filled: true, fillColor: Colors.white, isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        // Káº¿t luáº­n
        _sectionTitle('ðŸ” Káº¾T LUáº¬N', const Color(0xFF388E3C)),
        TextField(
          controller: _ketLuanCtrl,
          minLines: 2, maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Káº¿t luáº­n cá»§a bÃ¡c sÄ© (khÃ´ng báº¯t buá»™c)',
            border: OutlineInputBorder(), filled: true, fillColor: Colors.white, isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        // Ghi chÃº
        _sectionTitle('ðŸ“‹ GHI CHÃš', const Color(0xFFE65100)),
        TextField(
          controller: _ghiChuCtrl,
          minLines: 1, maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Ghi chÃº thÃªm (khÃ´ng báº¯t buá»™c)',
            border: OutlineInputBorder(), filled: true, fillColor: Colors.white, isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        // KÃ­p thá»±c hiá»‡n (5 vá»‹ trÃ­ - giá»‘ng HIS Desktop)
        _sectionTitle('ðŸ‘¥ KÃP THá»°C HIá»†N', const Color(0xFFD32F2F)),
        _kipField('BS / PTV chÃ­nh *', Icons.medical_services, _bsChinhCtrl, required: true),
        _kipField('PTV phá»¥ 1', Icons.medical_services_outlined, _ptvPhu1Ctrl),
        _kipField('PTV phá»¥ 2', Icons.medical_services_outlined, _ptvPhu2Ctrl),
        _kipField('GÃ¢y mÃª chÃ­nh', Icons.healing, _gayMeChinhCtrl),
        _kipField('GÃ¢y mÃª phá»¥ 1', Icons.healing_outlined, _gayMePhuCtrl),
        _kipField('Äiá»u dÆ°á»¡ng', Icons.health_and_safety, _ddCtrl),
        const SizedBox(height: 12),
      ]),
    );
  }

  /// v3.1.05: Tab "LÆ°u áº£nh" - LÆ°u áº£nh káº¿t quáº£
  Widget _buildSaveImageTab() {
    return _buildImageTabContent(
      title: 'LÆ¯U áº¢NH Káº¾T QUáº¢',
      desc: 'LÆ°u áº£nh káº¿t quáº£ (Ä‘iá»‡n tim, X-quang, v.v.) vÃ o há»“ sÆ¡',
      color: const Color(0xFF00838F),
    );
  }

  /// v3.1.05: Tab "ÄÃ­nh kÃ¨m" - ÄÃ­nh kÃ¨m áº£nh
  Widget _buildAttachTab() {
    return _buildImageTabContent(
      title: 'ÄÃNH KÃˆM áº¢NH',
      desc: 'ÄÃ­nh kÃ¨m áº£nh vÃ o EMR bá»‡nh nhÃ¢n',
      color: const Color(0xFFAD1457),
    );
  }

  Widget _buildImageTabContent({required String title, required String desc, required Color color}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(desc, style: TextStyle(fontSize: 11, color: color))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _pickImage(source: ImageSource.camera),
              icon: const Icon(Icons.camera_alt, size: 16),
              label: const Text('Chá»¥p áº£nh', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
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
                foregroundColor: color, side: BorderSide(color: color),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.image, size: 14, color: Colors.black54),
          const SizedBox(width: 4),
          Text('${_images.length} áº£nh Ä‘Ã£ chá»n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        if (_images.isEmpty)
          Container(
            width: double.infinity, height: 150,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
            ),
            child: const Center(child: Text('ChÆ°a cÃ³ áº£nh. Chá»¥p hoáº·c chá»n tá»« thÆ° viá»‡n.', style: TextStyle(color: Colors.black45, fontSize: 12))),
          )
        else
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6,
            ),
            itemCount: _images.length,
            itemBuilder: (ctx, i) => Stack(children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  image: DecorationImage(image: FileImage(_images[i]), fit: BoxFit.cover),
                ),
              ),
              Positioned(
                right: 2, top: 2,
                child: GestureDetector(
                  onTap: () => _removeImage(i),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 12),
                  ),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(4)),
          child: const Row(children: [
            Icon(Icons.lightbulb_outline, size: 14, color: Color(0xFFE65100)),
            SizedBox(width: 6),
            Expanded(child: Text(
              'LÆ°u Ã½: Sau khi lÆ°u, dÃ¹ng menu "ÄÃ­nh kÃ¨m tÃ i liá»‡u" trong thao tÃ¡c BN Ä‘á»ƒ upload áº£nh lÃªn EMR.',
              style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }

  Widget _sectionTitleWithIcon(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Row(children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ]),
    );
  }

  Widget _dateTimeField(String label, DateTime? dt, VoidCallback onTap, {bool isOptional = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(children: [
          const Icon(Icons.access_time, size: 14, color: Color(0xFFD32F2F)),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 9, color: Colors.black54)),
                if (dt != null)
                  Text(_formatDateTime(dt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))
                else
                  Text(isOptional ? '(khÃ´ng báº¯t buá»™c)' : '(chÆ°a chá»n)', style: const TextStyle(fontSize: 11, color: Colors.black38, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _kipField(String label, IconData icon, TextEditingController ctrl, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontSize: 11),
              prefixIcon: Icon(icon, size: 16),
              border: const OutlineInputBorder(),
              filled: true, fillColor: Colors.white, isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.person_search, size: 20, color: Color(0xFF6A1B9A)),
          tooltip: 'Chá»n tá»« HIS Pro',
          onPressed: () => _pickUser(ctrl, label),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  /// v3.1.05: Picker user tá»« HIS Pro (api/HisExecuteRoleUser/Get)
  /// Hiá»ƒn thá»‹ danh sÃ¡ch BS/ÄD theo role Ä‘á»ƒ chá»n nhanh
  /// v3.0.174: DÃ¹ng shared UserPickerDialog (cÃ³ search filter á»Ÿ top) thay vÃ¬ _UserPickerDialog cÅ©
  Future<void> _pickUser(TextEditingController ctrl, String label) async {
    showDialog(
      context: context,
      builder: (ctx) => UserPickerDialog(
        api: _api,
        departmentId: widget.executeDepartmentId ?? 22, // HSCC default
        title: 'Chá»n $label',
        onSelected: (result) {
          setState(() {
            ctrl.text = '${result.fullName} (${result.loginName})';
          });
        },
      ),
    );
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
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
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
                _saving ? 'Äang xá»­ lÃ½...' : 'HoÃ n thÃ nh & Káº¿t thÃºc (${_selectedServiceIds.length})',
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
}
