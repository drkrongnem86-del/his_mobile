// Procedure Room Screen - Phòng thử thuật Khoa Cấp Cứu
// v3.1.08: Cải thiện refresh + detect BN mới
// - Auto-refresh 30s (trước 60s) - để bắt BN mới nhanh hơn
// - Refresh khi user quay lại app (didChangeAppLifecycleState = resumed)
// - Detect BN mới → SnackBar "Có X BN mới"
// - 3 API options với icon đám mây + auto-fallback
// - 5 tabs dịch vụ + SLDV counter
// - Tap BN → mở ServiceExecuteDetailScreen
// v3.1.09: GỘP API selector - dùng global AppApiSourceNotifier (đồng bộ với HomeScreen top pill)
// - Khi embedded = true → ẨN 3 chips, đọc từ AppApiSourceNotifier, auto-reload khi đổi
// - Khi standalone (mở từ Tiện ích) → GIỮ 3 chips local
// v3.1.10: XÓA info bar "☁ API: API 2" (BS phản hồi nằm chồng ô search)
// v3.1.11: PHỤC HỒI info bar gọn + ẨN top pill to ở HomeScreen (khi ở Phòng thử thuật)
// - Procedure room (embedded) → HIỆN info bar gọn "☁ API: API 2 • Data 3000" + menu chọn
// - HomeScreen (khi _isCurrentDeptProcedureRoom) → ẨN top pill to
// v3.1.12: NÚT DÁN TOKEN HIS PRO (paste token từ log khi token cũ hết hạn)
// - Token active xoay vòng mỗi session → user dán token mới từ log
// - Save vào SharedPreferences + gọi HisApiService.setAuthToken ngay
// - Trường hợp lỗi 3 API: thường do token HIS Pro hết hạn, dán token mới sẽ work
// v3.1.13: TRA CỨU NHANH BN theo mã điều trị (dùng khi cả 3 API đều chết)
// - Gọi Data 3000 `/v1/medical-record/document-types?treatmentCode=...` (works qua internet!)
// - User nhập mã điều trị (15 số) từ HIS Desktop → xem BN + danh sách phiếu EMR
// - Cũng extract được service_req_code từ HIS_CODE field của mỗi phiếu
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/api_source_notifier.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/presentation/screens/ecg_execute_screen.dart';
import 'package:his_mobile/presentation/screens/service_execute_detail_screen.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v3.1.07: API source cho procedure room - tất cả đều dùng icon đám mây ☁
/// v3.1.09: GIỮ enum này cho STANDALONE mode (mở từ Tiện ích - không có parent)
///   Khi embedded = true, dùng AppApiSource (global) thay vì enum này
enum ProcedureApiSource {
  hisPro,   // ☁ HIS Pro (LAN/VPN, port 1429) - mặc định, data thật nhất
  dataApi,  // ☁ Data 3000 (Storage API)
  public,   // ☁ Public (Internet 113.163.187.3:8080)
}

extension ProcedureApiSourceX on ProcedureApiSource {
  String get label {
    switch (this) {
      case ProcedureApiSource.hisPro: return 'HIS Pro';
      case ProcedureApiSource.dataApi: return 'Data 3000';
      case ProcedureApiSource.public: return 'Public';
    }
  }
  IconData get icon => Icons.cloud_outlined;  // tất cả đều dùng icon đám mây
  Color get color {
    switch (this) {
      case ProcedureApiSource.hisPro: return const Color(0xFF6A1B9A);
      case ProcedureApiSource.dataApi: return const Color(0xFF00838F);
      case ProcedureApiSource.public: return const Color(0xFF0277BD);
    }
  }
  String get sublabel {
    switch (this) {
      case ProcedureApiSource.hisPro: return 'LAN/VPN';
      case ProcedureApiSource.dataApi: return 'Data 3000';
      case ProcedureApiSource.public: return 'Internet';
    }
  }

  /// v3.1.09: Map sang AppApiSource (cho sync với global notifier)
  AppApiSource get asAppSource {
    switch (this) {
      case ProcedureApiSource.hisPro:  return AppApiSource.hisPro;
      case ProcedureApiSource.dataApi: return AppApiSource.dataRoom;
      case ProcedureApiSource.public:  return AppApiSource.public;
    }
  }

  /// v3.1.09: Map từ AppApiSource (khi đọc từ global notifier)
  static ProcedureApiSource fromAppSource(AppApiSource s) {
    switch (s) {
      case AppApiSource.dataRoom: return ProcedureApiSource.dataApi;
      case AppApiSource.dataDept: return ProcedureApiSource.dataApi;
      case AppApiSource.hisPro:   return ProcedureApiSource.hisPro;
      case AppApiSource.public:   return ProcedureApiSource.public;
    }
  }
}

class ProcedureRoomScreen extends StatefulWidget {
  final int? executeRoomId;
  final int? executeDepartmentId;
  // v3.1.02: true = render trong HomeScreen (ẩn AppBar/UserHeader), false = full screen
  final bool embedded;
  // v3.1.02: Callback khi tap BN (dùng cho embedded - mở actions sheet riêng)
  final void Function(Map<String, dynamic> patient, Map<String, dynamic> serviceReq)? onPatientTap;
  // v3.1.09: true = dùng global AppApiSourceNotifier (đồng bộ với HomeScreen top pill, ẩn 3 chips)
  //          false = dùng local ProcedureApiSource + hiện 3 chips
  //          mặc định = embedded (true nếu embedded, false nếu standalone)
  final bool? useGlobalApiSource;

  const ProcedureRoomScreen({
    super.key,
    this.executeRoomId,
    this.executeDepartmentId,
    this.embedded = false,
    this.onPatientTap,
    this.useGlobalApiSource,
  });

  @override
  State<ProcedureRoomScreen> createState() => _ProcedureRoomScreenState();
}

class _ProcedureRoomScreenState extends State<ProcedureRoomScreen> with WidgetsBindingObserver {
  final HisApiService _api = HisApiService();
  final HisProApiService _hisPro = HisProApiService.instance;

  // v3.1.09: Khi embedded mặc định dùng global notifier (ẩn 3 chips, đồng bộ với HomeScreen top pill)
  //          Khi standalone (mở từ Tiện ích) dùng local ProcedureApiSource + hiện 3 chips
  late final bool _useGlobal;
  // v3.1.07: API source selector (3 lựa chọn với icon đám mây ☁) - chỉ dùng khi standalone
  ProcedureApiSource _apiSource = ProcedureApiSource.hisPro;
  // Trạng thái API: null = chưa test, true = connected, false = error
  final Map<ProcedureApiSource, bool?> _apiStatus = {
    ProcedureApiSource.hisPro: null,
    ProcedureApiSource.dataApi: null,
    ProcedureApiSource.public: null,
  };

  // v3.1.05: Tab loại dịch vụ (giống HIS Desktop "Dịch vụ chỉ định")
  // 0=Tất cả, 1=Khám, 2=CĐHA, 3=Thủ thuật, 4=Vật tư
  int _serviceTypeTab = 0;

  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _allPatients = [];
  bool _loading = true;
  String? _error;
  String _debugInfo = '';
  DateTime? _lastSynced;
  Timer? _autoRefreshTimer;
  // v3.1.08: Track danh sách BN cũ để detect BN mới
  Set<String> _previousPatientKeys = {};
  // DEBUG: count để chỉ log 3 patient đầu tiên
  int _debugLogCount = 0;

  @override
  void initState() {
    super.initState();
    // v3.1.09: Mặc định dùng global khi embedded, local khi standalone
    _useGlobal = widget.useGlobalApiSource ?? widget.embedded;
    if (_useGlobal) {
      // Lấy giá trị hiện tại từ global notifier (vd đã set = API 2 ở HomeScreen)
      _apiSource = ProcedureApiSourceX.fromAppSource(AppApiSourceNotifier.instance.value);
      // Listen cho thay đổi (khi user đổi API ở HomeScreen top pill)
      AppApiSourceNotifier.instance.notifier.addListener(_onGlobalApiSourceChanged);
    }
    WidgetsBinding.instance.addObserver(this);
    _loadPatients();
    // v3.1.08: Auto-refresh 30s (nhanh hơn 60s) - bắt BN mới
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadPatients(silent: true));
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    if (_useGlobal) {
      AppApiSourceNotifier.instance.notifier.removeListener(_onGlobalApiSourceChanged);
    }
    _searchCtrl.dispose();
    _searchFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// v3.1.09: Khi global notifier đổi (user bấm ←/→ ở HomeScreen top pill)
  void _onGlobalApiSourceChanged() {
    if (!mounted) return;
    final newSrc = ProcedureApiSourceX.fromAppSource(AppApiSourceNotifier.instance.value);
    if (newSrc != _apiSource) {
      debugPrint('ProcedureRoom: global API changed ${_apiSource.label} → ${newSrc.label}');
      setState(() {
        _apiSource = newSrc;
        _loading = true;
      });
      _loadPatients();
    }
  }

  /// v3.1.08: Khi user quay lại app (từ background), refresh ngay
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('ProcedureRoom: app resumed → refresh');
      _loadPatients(silent: true);
    }
  }

  /// v3.1.08: Detect BN mới (so sánh với danh sách cũ)
  void _detectNewPatients(List<Map<String, dynamic>> newList) {
    final newKeys = <String>{};
    for (final p in newList) {
      final key = '${p['ID'] ?? p['id']}_${p['SERVICE_REQ_STT_ID'] ?? p['service_req_stt_id']}';
      newKeys.add(key);
    }
    final added = newKeys.difference(_previousPatientKeys);
    if (_previousPatientKeys.isNotEmpty && added.isNotEmpty) {
      // Có BN mới
      debugPrint('ProcedureRoom: ${added.length} BN mới');
      // Hiển thị SnackBar (chỉ khi widget còn visible)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.notifications_active, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('🔔 Có ${added.length} yêu cầu mới trong phòng thử thuật!')),
            ]),
            backgroundColor: const Color(0xFF388E3C),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Xem',
              textColor: Colors.white,
              onPressed: () {
                // Reload list (cuộn lên đầu)
              },
            ),
          ),
        );
      }
    }
    _previousPatientKeys = newKeys;
  }

  /// v3.1.07: User chọn API thủ công (chỉ dùng ở standalone mode - có 3 chips)
  void _switchApi(ProcedureApiSource src) {
    if (_apiSource == src) {
      // Click lại → reload
      _loadPatients();
      return;
    }
    setState(() {
      _apiSource = src;
      _loading = true;
    });
    // v3.1.09: Sync global notifier (nếu user sau đó mở HomeScreen thì top pill cũng đổi theo)
    AppApiSourceNotifier.instance.value = src.asAppSource;
    _loadPatients();
  }

  Future<void> _loadPatients({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final roomId = widget.executeRoomId ?? AppConstants.ROOM_ID_KHAM_CAP_CUU;
    final deptId = widget.executeDepartmentId ?? AppConstants.DEPARTMENT_ID_CAP_CUU;

    // v3.1.07: Auto-fallback chain - thử HIS Pro trước, nếu lỗi thì thử các API khác
    final sources = <ProcedureApiSource>[
      _apiSource,
      // Fallback chain - nếu API hiện tại lỗi
      if (_apiSource != ProcedureApiSource.hisPro) ProcedureApiSource.hisPro,
      if (_apiSource != ProcedureApiSource.dataApi) ProcedureApiSource.dataApi,
      if (_apiSource != ProcedureApiSource.public) ProcedureApiSource.public,
    ];

    HisResult? result;
    ProcedureApiSource? usedSource;
    String? lastError;

    for (final src in sources) {
      try {
        if (!silent) setState(() => _debugInfo = '☁ Đang thử ${src.label}...');
        result = await _callApi(src, roomId, deptId, limit: 200);
        if (result.success) {
          usedSource = src;
          // Update API status
          _apiStatus[src] = true;
          // Test other APIs in background
          for (final other in ProcedureApiSource.values) {
            if (other != src && _apiStatus[other] == null) {
              _testApiStatus(other, roomId, deptId);
            }
          }
          break;
        } else {
          _apiStatus[src] = false;
          lastError = result.message ?? 'Lỗi không xác định';
          if (!silent) setState(() => _debugInfo = '⚠ ${src.label} lỗi: $lastError - đang thử API khác...');
        }
      } catch (e) {
        _apiStatus[src] = false;
        lastError = e.toString();
        if (!silent) setState(() => _debugInfo = '⚠ ${src.label} lỗi: $e - đang thử API khác...');
      }
    }

    if (!mounted) return;

    if (result == null || !result.success) {
      setState(() {
        _loading = false;
        _allPatients = [];
        _error = lastError ?? 'Tất cả API đều lỗi';
        // v3.1.12: Gợi ý user dán token HIS Pro khi tất cả fail
        _debugInfo = '❌ Tất cả API đều lỗi. Cuối: $lastError\n'
            '👉 Bấm nút 🔑 (key) để DÁN TOKEN HIS Pro mới từ log HIS Desktop\n'
            '   HOẶC chuyển sang WiFi BV (172.16.x.x) để truy cập HIS Pro LAN';
      });
      return;
    }

    List<Map<String, dynamic>> data = [];
    if (result.data is List) {
      data = List<Map<String, dynamic>>.from(result.data);
    } else if (result.data is Map && (result.data as Map)['Data'] is List) {
      data = List<Map<String, dynamic>>.from((result.data as Map)['Data']);
    }

    // v3.1.08: Detect BN mới (trước khi setState)
    if (mounted) {
      _detectNewPatients(data);
    }

    setState(() {
      _apiSource = usedSource!;
      _allPatients = data;
      _lastSynced = DateTime.now();
      _loading = false;
      _error = null;
      _debugInfo = '☁ ${usedSource.label} - Phòng TT HSCC (room $roomId): ${data.length} BN/yêu cầu';
    });
  }

  /// v3.1.07: Gọi API theo source
  Future<HisResult> _callApi(ProcedureApiSource src, int roomId, int deptId, {int limit = 200}) async {
    switch (src) {
      case ProcedureApiSource.hisPro:
        return await _api.getServiceRequestsByRoom(roomId, limit: limit)
            .timeout(const Duration(seconds: 8), onTimeout: () => HisResult(success: false, message: 'HIS Pro timeout'));
      case ProcedureApiSource.dataApi:
        return await _api.getServiceRequestsByRoomDataApi(roomId, limit: limit, departmentId: deptId)
            .timeout(const Duration(seconds: 8), onTimeout: () => HisResult(success: false, message: 'Data API timeout'));
      case ProcedureApiSource.public:
        return await _api.getServiceRequestsByRoomPublic(roomId, limit: limit, departmentCatalogId: deptId)
            .timeout(const Duration(seconds: 8), onTimeout: () => HisResult(success: false, message: 'Public API timeout'));
    }
  }

  /// v3.1.07: Test 1 API trong background (không block UI)
  Future<void> _testApiStatus(ProcedureApiSource src, int roomId, int deptId) async {
    try {
      final result = await _callApi(src, roomId, deptId, limit: 5);
      if (mounted) {
        setState(() {
          _apiStatus[src] = result.success;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _apiStatus[src] = false;
        });
      }
    }
  }

  /// v3.1.05: Bỏ bộ lọc Bệnh - filter theo search query + service type tab
  /// Sắp xếp ca mới nhất ở trên cùng (4-level sort giống HIS Desktop)
  List<Map<String, dynamic>> get _filteredPatients {
    var list = _allPatients;
    // Filter theo service type tab
    if (_serviceTypeTab > 0) {
      list = list.where((p) {
        final t = _toInt(p['SERVICE_REQ_TYPE_ID'] ?? p['service_req_type_id']);
        if (_serviceTypeTab == 1) return t == 1; // Khám
        if (_serviceTypeTab == 2) return t == 3; // CĐHA
        if (_serviceTypeTab == 3) return t == 4 || t == 5 || t == 9 || t == 10; // Thủ thuật
        if (_serviceTypeTab == 4) return t == 8; // Vật tư
        return true;
      }).toList();
    }
    // Filter theo search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) {
        final name = fixVietnameseMojibake(PatientNameHelper.getName(p)).toLowerCase();
        final code = (p['TDL_PATIENT_CODE'] ?? p['TDL_PATIENT_NAME'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q);
      }).toList();
    }
    // 4-level sort (HIS Desktop)
    list = _sortByInTimeDesc(list);
    return list;
  }

  /// v3.1.04: Sort BN giống HIS Desktop (4 fields theo thứ tự)
  /// 1. INTRUCTION_TIME DESC (ca mới nhất ở trên cùng)
  /// 2. SERVICE_REQ_STT_ID ASC (chưa thực hiện - stt 1 - ở trên, đã xong - stt 3 - ở dưới)
  /// 3. PRIORITY DESC (ưu tiên cao ở trên)
  /// 4. NUM_ORDER ASC (số thứ tự trong ngày nhỏ ở trên)
  List<Map<String, dynamic>> _sortByInTimeDesc(List<Map<String, dynamic>> list) {
    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      // 1. INTRUCTION_TIME DESC
      final aTime = _parsePatientTime(a);
      final bTime = _parsePatientTime(b);
      if (aTime == null && bTime != null) return 1;
      if (aTime != null && bTime == null) return -1;
      if (aTime != null && bTime != null && aTime != bTime) {
        return bTime.compareTo(aTime);
      }
      // 2. SERVICE_REQ_STT_ID ASC
      final aStt = _toInt(a['SERVICE_REQ_STT_ID'] ?? a['service_req_stt_id']);
      final bStt = _toInt(b['SERVICE_REQ_STT_ID'] ?? b['service_req_stt_id']);
      if (aStt != bStt) return aStt.compareTo(bStt);
      // 3. PRIORITY DESC
      final aPri = _toInt(a['PRIORITY'] ?? a['priority']);
      final bPri = _toInt(b['PRIORITY'] ?? b['priority']);
      if (aPri != bPri) return bPri.compareTo(aPri);
      // 4. NUM_ORDER ASC
      final aNum = _toInt(a['NUM_ORDER'] ?? a['num_order']);
      final bNum = _toInt(b['NUM_ORDER'] ?? b['num_order']);
      return aNum.compareTo(bNum);
    });
    return sorted;
  }

  /// Helper: parse int
  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  DateTime? _parsePatientTime(Map<String, dynamic> p) {
    // Ưu tiên 1: INTRUCTION_TIME (HIS Pro long)
    final instructionTime = p['INTRUCTION_TIME'] ?? p['intruction_time'];
    if (instructionTime != null) {
      final dt = _parseHisLong(instructionTime);
      if (dt != null) return dt;
    }
    // Ưu tiên 2: INTRUCTION_DATE (HIS Pro long - chỉ ngày)
    final instructionDate = p['INTRUCTION_DATE'] ?? p['intruction_date'];
    if (instructionDate != null) {
      final dt = _parseHisLong(instructionDate);
      if (dt != null) return dt;
    }
    // Ưu tiên 3: IN_TIME (Data API - string)
    final inTime = p['IN_TIME'] ?? p['in_time'] ?? p['IN_TIME_VS'];
    if (inTime != null) {
      final dt = _parseDataTimeString(inTime.toString());
      if (dt != null) return dt;
    }
    return null;
  }

  /// Parse HIS Pro long date (yyyyMMddHHmmss hoặc yyyyMMdd)
  DateTime? _parseHisLong(dynamic v) {
    if (v == null) return null;
    int? n;
    if (v is int) n = v;
    if (v is num) n = v.toInt();
    if (v is String) n = int.tryParse(v);
    if (n == null) return null;
    if (n < 19000101) return null; // Invalid
    // yyyyMMddHHmmss (14 digits)
    if (n >= 19000101000000) {
      final s = n.toString().padLeft(14, '0');
      return DateTime(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
        int.parse(s.substring(8, 10)),
        int.parse(s.substring(10, 12)),
        int.parse(s.substring(12, 14)),
      );
    }
    // yyyyMMdd (8 digits)
    if (n >= 19000101 && n < 99999999) {
      final s = n.toString().padLeft(8, '0');
      return DateTime(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
      );
    }
    return null;
  }

  /// Parse Data API time string (dd/MM/yyyy HH:mm hoặc yyyy-MM-dd HH:mm:ss)
  DateTime? _parseDataTimeString(String s) {
    s = s.trim();
    if (s.isEmpty || s == 'null' || s == '-') return null;
    try {
      if (s.contains('/')) {
        // dd/MM/yyyy HH:mm hoặc dd/MM/yyyy
        final parts = s.split(' ');
        final dateParts = parts[0].split('/');
        if (dateParts.length == 3) {
          final day = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final year = int.parse(dateParts[2]);
          if (parts.length > 1) {
            final timeParts = parts[1].split(':');
            return DateTime(
              year, month, day,
              int.parse(timeParts[0]),
              timeParts.length > 1 ? int.parse(timeParts[1]) : 0,
            );
          }
          return DateTime(year, month, day);
        }
      }
      if (s.contains('-')) {
        // yyyy-MM-dd HH:mm:ss hoặc yyyy-MM-dd
        final parts = s.split(' ');
        final dateParts = parts[0].split('-');
        if (dateParts.length == 3) {
          final year = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final day = int.parse(dateParts[2]);
          if (parts.length > 1) {
            final timeParts = parts[1].split(':');
            return DateTime(
              year, month, day,
              int.parse(timeParts[0]),
              timeParts.length > 1 ? int.parse(timeParts[1]) : 0,
            );
          }
          return DateTime(year, month, day);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openECGExecute(Map<String, dynamic> patient, Map<String, dynamic> serviceReq) async {
    if (widget.onPatientTap != null) {
      // Embedded mode: dùng callback (vd mở ProcedureRoomActionsSheet riêng)
      widget.onPatientTap!(patient, serviceReq);
      return;
    }
    // v3.1.05: Mở màn hình chi tiết dịch vụ (giống HIS Desktop "Xử lý yêu cầu")
    // Lấy TẤT CẢ serviceReq cùng TREATMENT_ID (1 BN có thể có nhiều DV: Khám + CĐHA + Thủ thuật)
    final allServiceReqs = await _fetchAllServiceReqsForPatient(patient);
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceExecuteDetailScreen(
          patient: patient,
          serviceReqs: allServiceReqs,
          executeRoomId: widget.executeRoomId,
          executeDepartmentId: widget.executeDepartmentId,
        ),
      ),
    );
    if (result == true) {
      // Hoàn thành → reload để cập nhật trạng thái
      _loadPatients(silent: true);
    }
  }

  /// v3.1.05: Lấy tất cả serviceReq của BN cùng TREATMENT_ID
  /// (1 BN có thể có nhiều DV: Khám, CĐHA, Thủ thuật cùng lúc - giống HIS Desktop "Dịch vụ chỉ định")
  Future<List<Map<String, dynamic>>> _fetchAllServiceReqsForPatient(Map<String, dynamic> patient) async {
    final treatmentId = patient['TREATMENT_ID'] ?? patient['treatment_id'] ?? patient['TDL_TREATMENT_ID'];
    if (treatmentId == null) return [patient];
    try {
      final res = await _api.getServiceRequestsByTreatment(treatmentId);
      if (res.success && res.data is List && (res.data as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(res.data);
      }
    } catch (e) {
      debugPrint('getServiceRequestsByTreatment error: $e');
    }
    return [patient];
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) {
      // v3.1.02: Embedded mode - không có Scaffold/AppBar (HomeScreen đã có)
      return Container(
        color: const Color(0xFFF5F7FA),
        child: body,
      );
    }
    // Full screen mode (mở từ Tiện ích)
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        title: const Text('Phòng thử thuật - HSCC',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadPatients(),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    return Column(children: [
      // ===== USER HEADER (chỉ hiện khi không embedded) =====
      if (!widget.embedded) UserHeader.fromAuth(compact: true),
      // ===== API SELECTOR =====
      // v3.1.11: BS phản hồi - muốn GIỮ info bar gọn trong procedure room (thay vì top pill to ở HomeScreen)
      //          Khi _useGlobal (embedded) → hiện info bar gọn "☁ API: API 2 • Data 3000" + menu chọn
      //          Khi standalone → hiện 3 chips đầy đủ
      if (_useGlobal) _buildApiInfoBar() else _buildApiSelector(),
      // ===== SEARCH BAR =====
      _buildSearchBar(),
      // ===== STATS + DEBUG INFO =====
      _buildStatsBar(),
      // ===== SERVICE TYPE TABS (Tất cả / Khám / CĐHA / Thủ thuật / Vật tư) =====
      _buildServiceTypeTabs(),
      // ===== PATIENT LIST =====
      Expanded(child: _buildList()),
      // ===== FOOTER: SLDV counter (giống HIS Desktop "SLDV đã xử lý: X/Y") =====
      if (!widget.embedded) _buildFooter(),
    ]);
  }

  /// v3.1.12: Info bar gọn cho procedure room (embedded mode)
  /// - Hiện 1 dòng nhỏ: "☁ API: API 2 • Data 3000"
  /// - Tap → mở menu chọn API (ghi vào global notifier)
  /// - Nút "Dán token" - paste token HIS Pro từ log khi cần
  /// - Nút "Tra cứu" - nhập mã điều trị/mã YC để xem chi tiết BN
  /// - Refresh button riêng
  /// - Thay thế top pill to đùng ở HomeScreen (khi _isCurrentDeptProcedureRoom = true)
  Widget _buildApiInfoBar() {
    final currentSrc = AppApiSourceNotifier.instance.value;
    return Container(
      color: currentSrc.color.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(children: [
        Icon(Icons.cloud_outlined, size: 14, color: currentSrc.color),
        const SizedBox(width: 4),
        Expanded(
          child: GestureDetector(
            onTap: _showApiMenu,
            child: Row(children: [
              Text('API:', style: TextStyle(fontSize: 10, color: currentSrc.color, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text(
                '${currentSrc.shortLabel} • ${currentSrc.subLabel}',
                style: TextStyle(fontSize: 10, color: currentSrc.color, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 12, color: Colors.black45),
            ]),
          ),
        ),
        // v3.1.13: Nút Tra cứu nhanh (lookup BN theo mã điều trị - dùng khi mọi API fail)
        IconButton(
          icon: const Icon(Icons.search, size: 16, color: Color(0xFF0277BD)),
          onPressed: _showQuickLookupDialog,
          tooltip: 'Tra cứu BN (nhập mã điều trị)',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        // v3.1.12: Nút Dán token HIS Pro (paste token từ log khi cần)
        IconButton(
          icon: const Icon(Icons.vpn_key, size: 14, color: Color(0xFF6A1B9A)),
          onPressed: _showPasteTokenDialog,
          tooltip: 'Dán token HIS Pro',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        IconButton(
          icon: Icon(Icons.refresh, size: 16, color: currentSrc.color),
          onPressed: () => _loadPatients(),
          tooltip: 'Tải lại',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  /// v3.1.13: Tra cứu nhanh BN theo mã điều trị (15 số)
  /// - Hoạt động qua Data 3000 `/v1/medical-record/document-types?treatmentCode=...` (chạy được từ internet)
  /// - Hiển thị: tên BN, năm sinh, giới tính, khoa hiện tại, danh sách phiếu EMR
  /// - Dùng khi cả 3 API (HIS Pro/Data/Public) đều chết
  Future<void> _showQuickLookupDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.search, color: Color(0xFF0277BD)),
          SizedBox(width: 8),
          Text('Tra cứu nhanh BN', style: TextStyle(fontSize: 14)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nhập mã điều trị (15 số) hoặc mã YC DV (15 số)',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 4),
              const Text(
                'Lấy từ HIS Desktop → cột "Mã điều trị" hoặc "Mã ĐT"',
                style: TextStyle(fontSize: 10, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '000002175050',
                  hintStyle: TextStyle(fontSize: 11, color: Colors.black38, fontFamily: 'monospace'),
                  isDense: true,
                  prefixIcon: Icon(Icons.qr_code, size: 18),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              const SizedBox(height: 8),
              const Text(
                '💡 Hoạt động qua Data 3000 internet (113.163.187.3:3000)',
                style: TextStyle(fontSize: 9, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.search, size: 14),
            label: const Text('Tra cứu'),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }
    final data = await DataService.instance.quickLookupByTreatmentCode(result);
    if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close loading
    if (!mounted) return;
    _showLookupResult(result, data);
  }

  /// v3.1.13: Hiển thị kết quả tra cứu
  void _showLookupResult(String code, Map<String, dynamic>? data) {
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Lỗi khi tra cứu'), backgroundColor: Color(0xFFD32F2F)),
      );
      return;
    }
    if (data['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${data['error']}'), backgroundColor: const Color(0xFFD32F2F)),
      );
      return;
    }
    final patient = data['patient'] as Map<String, dynamic>?;
    final docs = (data['documents'] as List?) ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.person, color: Color(0xFF0277BD)),
          const SizedBox(width: 8),
          Expanded(child: Text(
            patient?['patientName']?.toString() ?? 'Không rõ tên',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          )),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (patient != null) ...[
                  _row('Mã BN', patient['patientCode']?.toString() ?? '-'),
                  _row('Năm sinh', patient['dob']?.toString() ?? '-'),
                  _row('Giới tính', patient['genderName']?.toString() ?? '-'),
                  _row('Khoa hiện tại', '${patient['currentDepartmentCode']} - ${patient['currentDepartmentName']}'),
                  _row('Mã điều trị', data['treatmentCode']?.toString() ?? code),
                ] else
                  Text('Không tìm được thông tin BN\nMã điều trị: $code', style: const TextStyle(fontSize: 11)),
                const Divider(height: 16),
                Text('📋 Danh sách phiếu (${docs.length}):',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...docs.take(20).map((d) {
                  final m = d as Map<String, dynamic>;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: m['isSigned'] == true ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ${m['name']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        Text('   ${m['typeName']} | ${m['requester']} | ${m['createTime']}',
                            style: const TextStyle(fontSize: 9, color: Colors.black54)),
                        if ((m['serviceReqCode'] as String? ?? '').isNotEmpty)
                          Text('   YC: ${m['serviceReqCode']}', style: const TextStyle(fontSize: 9, color: Color(0xFF6A1B9A))),
                      ],
                    ),
                  );
                }),
                if (docs.length > 20)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('... và ${docs.length - 20} phiếu khác',
                        style: const TextStyle(fontSize: 10, color: Colors.black45)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Đóng'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 90,
          child: Text('$label:', style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  /// v3.1.12: Dialog dán token HIS Pro (khi token cũ hết hạn)
  /// - User mở HIS Desktop → mở file log → copy token từ "dti:...|...|TOKEN|..."
  /// - Paste vào dialog → Save → app sẽ dùng token mới
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
              const Text(
                'Token HIS Pro xoay vòng mỗi session. Khi app báo lỗi, hãy:',
                style: TextStyle(fontSize: 11),
              ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 14),
            label: const Text('Lưu'),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );
    if (saved != null && saved.isNotEmpty) {
      await prefs.setString('his_pro_token_override', saved);
      // Set ngay cho HisApiService (procedure room dùng cái này)
      _api.setAuthToken(saved);
      // Set cho HisProApiService (EMR push) - dùng setCustomBearer
      await _hisPro.setCustomBearer(saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Đã lưu token mới: ${saved.substring(0, 8)}…${saved.substring(saved.length - 4)}')),
            ]),
            backgroundColor: const Color(0xFF388E3C),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Tải lại',
              textColor: Colors.white,
              onPressed: () => _loadPatients(),
            ),
          ),
        );
        _loadPatients();
      }
    }
  }

  /// v3.1.11: Bottom sheet chọn API (ghi vào global notifier)
  void _showApiMenu() {
    final current = AppApiSourceNotifier.instance.value;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              child: const Text('Chọn nguồn API lấy BN phòng thử thuật',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ...AppApiSource.values.map((src) {
              final isSel = current == src;
              return ListTile(
                dense: true,
                leading: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: src.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.cloud_outlined, color: src.color, size: 18),
                ),
                title: Text(src.fullLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                subtitle: Text(src.url, style: const TextStyle(fontSize: 9)),
                trailing: isSel ? Icon(Icons.check_circle, color: src.color) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  AppApiSourceNotifier.instance.value = src;
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// v3.1.07: API selector với icon đám mây (3 nút ☁)
  /// - Tất cả 3 nút đều dùng Icons.cloud_outlined
  /// - Hiển thị trạng thái: ✓ xanh (connected) / ✗ đỏ (error) / ? xám (chưa test)
  /// - Tap để chuyển API thủ công + auto-fallback khi lỗi
  Widget _buildApiSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(children: [
        const Icon(Icons.cloud_outlined, size: 14, color: Color(0xFF303F9F)),
        const SizedBox(width: 4),
        const Text('API:', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Expanded(
          child: Row(children: [
            for (final src in ProcedureApiSource.values) ...[
              Expanded(child: _apiChip(src)),
              if (src != ProcedureApiSource.values.last) const SizedBox(width: 4),
            ],
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF6A1B9A)),
          onPressed: () => _loadPatients(),
          tooltip: 'Tải lại (thử auto-fallback)',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  /// v3.1.07: Chip API với icon đám mây + trạng thái
  Widget _apiChip(ProcedureApiSource src) {
    final selected = _apiSource == src;
    final status = _apiStatus[src];
    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (status) {
      case true:
        statusColor = const Color(0xFF388E3C);
        statusIcon = Icons.check_circle;
        statusText = 'OK';
        break;
      case false:
        statusColor = const Color(0xFFD32F2F);
        statusIcon = Icons.error;
        statusText = 'Lỗi';
        break;
      case null:
        statusColor = const Color(0xFF9E9E9E);
        statusIcon = Icons.help_outline;
        statusText = '...';
        break;
    }
    return InkWell(
      onTap: () => _switchApi(src),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? src.color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? src.color : const Color(0xFFE0E0E0),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon đám mây (chính)
            Icon(Icons.cloud_outlined, size: 14, color: selected ? src.color : const Color(0xFF9E9E9E)),
            const SizedBox(width: 2),
            // Mũi tên chỉ API đang dùng
            if (selected) Icon(Icons.chevron_right, size: 10, color: src.color) else const SizedBox(width: 10),
            const SizedBox(width: 2),
            // Label
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(src.label,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: selected ? src.color : Colors.black87),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  Row(children: [
                    Text('☁', style: TextStyle(fontSize: 8, color: selected ? src.color : const Color(0xFF9E9E9E))),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(src.sublabel,
                        style: TextStyle(fontSize: 8, color: selected ? src.color : Colors.black54),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            // Status icon
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(statusIcon, size: 10, color: statusColor),
            ),
          ],
        ),
      ),
    );
  }

  /// v3.1.05: Footer SLDV counter (giống HIS Desktop)
  Widget _buildFooter() {
    final sldvTotal = _allPatients.length;
    final sldvDone = _allPatients.where((p) {
      final stt = _toInt(p['SERVICE_REQ_STT_ID'] ?? p['service_req_stt_id']);
      return stt >= 3;
    }).length;
    return Container(
      color: const Color(0xFFF6F8FB),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        const Icon(Icons.medical_services, size: 12, color: Color(0xFF303F9F)),
        const SizedBox(width: 4),
        Text('SLDV đã xử lý: ', style: TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w600)),
        Text('$sldvDone/$sldvTotal', style: const TextStyle(fontSize: 12, color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
        const Spacer(),
        if (_lastSynced != null)
          Text('Cập nhật: ${_formatTime(_lastSynced!)}', style: const TextStyle(fontSize: 9, color: Colors.black45)),
      ]),
    );
  }

  /// v3.1.05: Tabs loại dịch vụ + counter SLDV (giống HIS Desktop "Dịch vụ chỉ định")
  /// Hiển thị: Tất cả (X/Y), Khám (X/Y), CĐHA (X/Y), Thủ thuật (X/Y), Vật tư (X/Y)
  Widget _buildServiceTypeTabs() {
    // Đếm SLDV theo từng loại
    int khamTotal = 0, khamDone = 0;
    int cdhaTotal = 0, cdhaDone = 0;
    int thuThuatTotal = 0, thuThuatDone = 0;
    int vatTuTotal = 0, vatTuDone = 0;

    for (final p in _allPatients) {
      // Mỗi BN có thể có nhiều serviceReq, nhưng v3.1.05 giả định 1 patient = 1 service type
      // (HIS Desktop list BN 1 lần, count SLDV qua các sub-tab)
      final t = _toInt(p['SERVICE_REQ_TYPE_ID'] ?? p['service_req_type_id']);
      final stt = _toInt(p['SERVICE_REQ_STT_ID'] ?? p['service_req_stt_id']);
      final isDone = stt >= 3; // stt 3,4,5,6 = hoàn thành
      if (t == 1) { khamTotal++; if (isDone) khamDone++; }
      else if (t == 3) { cdhaTotal++; if (isDone) cdhaDone++; }
      else if (t == 4 || t == 5 || t == 9 || t == 10) { thuThuatTotal++; if (isDone) thuThuatDone++; }
      else if (t == 8) { vatTuTotal++; if (isDone) vatTuDone++; }
    }
    final allTotal = _allPatients.length;
    final allDone = _allPatients.where((p) {
      final stt = _toInt(p['SERVICE_REQ_STT_ID'] ?? p['service_req_stt_id']);
      return stt >= 3;
    }).length;

    return Container(
      color: const Color(0xFFE8EAF6),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(children: [
        Expanded(child: _srvTypeTab(0, 'Tất cả', allDone, allTotal, const Color(0xFF303F9F), Icons.list_alt)),
        const SizedBox(width: 2),
        Expanded(child: _srvTypeTab(1, 'Khám', khamDone, khamTotal, const Color(0xFF00838F), Icons.medical_services)),
        const SizedBox(width: 2),
        Expanded(child: _srvTypeTab(2, 'CĐHA', cdhaDone, cdhaTotal, const Color(0xFF1976D2), Icons.image)),
        const SizedBox(width: 2),
        Expanded(child: _srvTypeTab(3, 'Thủ thuật', thuThuatDone, thuThuatTotal, const Color(0xFFD32F2F), Icons.healing)),
        const SizedBox(width: 2),
        Expanded(child: _srvTypeTab(4, 'Vật tư', vatTuDone, vatTuTotal, const Color(0xFF388E3C), Icons.medical_information)),
      ]),
    );
  }

  Widget _srvTypeTab(int idx, String label, int done, int total, Color color, IconData icon) {
    final selected = _serviceTypeTab == idx;
    return InkWell(
      onTap: () => setState(() => _serviceTypeTab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? color : const Color(0xFFE0E0E0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 11, color: selected ? Colors.white : color),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: selected ? Colors.white : color),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              '($done/$total)',
              style: TextStyle(fontSize: 9, color: selected ? Colors.white : Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  /// v3.1.06: Bỏ _buildApiSelector - chỉ dùng HIS Pro (giống HIS Desktop)

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        decoration: InputDecoration(
          hintText: 'Tìm theo tên, mã BN...',
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF6A1B9A)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
        ),
        onChanged: (q) => setState(() => _searchQuery = q),
      ),
    );
  }

  /// v3.1.02: Thanh thống kê - hiển thị: tổng BN, số chưa thực hiện, số đã thực hiện
  Widget _buildStatsBar() {
    final total = _allPatients.length;
    final chua = _allPatients.where((p) {
      final stt = p['SERVICE_REQ_STT_ID'] ?? p['service_req_stt_id'] ?? 1;
      return stt == 1 || stt == 2;
    }).length;
    final da = total - chua;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _miniStat('Tổng', total, const Color(0xFF1976D2)),
          _miniStat('Chưa TH', chua, const Color(0xFFD32F2F)),
          _miniStat('Đã TH', da, const Color(0xFF388E3C)),
          if (_debugInfo.isNotEmpty)
            Text(
              '• $_debugInfo${_lastSynced != null ? ' • ${_formatTime(_lastSynced!)}' : ''}',
              style: const TextStyle(fontSize: 9, color: Color(0xFF00695C)),
            ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label: $count', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Lỗi: $_error', style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadPatients,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    final list = _filteredPatients;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              _allPatients.isEmpty
                  ? 'Chưa có yêu cầu dịch vụ nào ở phòng thử thuật'
                  : 'Không có BN nào khớp từ khóa tìm kiếm',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadPatients(silent: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final p = list[i];
          return _buildPatientTile(p);
        },
      ),
    );
  }

  Widget _buildPatientTile(Map<String, dynamic> p) {
    // DEBUG: log field names từ API response để debug tên BN không hiện
    assert(() {
      if (_debugLogCount < 3) {
        _debugLogCount++;
        final keys = p.keys.where((k) => k.toLowerCase().contains('patient') || k.toLowerCase().contains('name') || k.toLowerCase().contains('hoten') || k.toLowerCase().contains('ten_')).toList();
        debugPrint('🔍 [ProcRoom] Patient #$_debugLogCount name fields: $keys');
        debugPrint('🔍 [ProcRoom] Raw: TDL_PATIENT_NAME=${p['TDL_PATIENT_NAME']} tdl_patient_name=${p['tdl_patient_name']} TEN_BENH_NHAN=${p['TEN_BENH_NHAN']} hotenbn=${p['hotenbn']}');
        debugPrint('🔍 [ProcRoom] Helper result: ${PatientNameHelper.getName(p)}');
      }
      return true;
    }());
    final name = fixVietnameseMojibake(PatientNameHelper.getName(p));
    final code = (p['TDL_PATIENT_CODE'] ?? p['TDL_PATIENT_NAME'] ?? '').toString();
    final serviceReqCode = (p['SERVICE_REQ_CODE'] ?? p['service_req_code'] ?? '').toString();
    final serviceName = (p['SERVICE_NAME'] ?? p['service_name'] ?? '—').toString();
    final stt = p['SERVICE_REQ_STT_ID'] ?? p['service_req_stt_id'] ?? 1;
    final sttName = (p['SERVICE_REQ_STT_NAME'] ?? p['service_req_stt_name'] ?? '').toString();
    final priority = p['PRIORITY'] ?? p['priority'] ?? 0;
    final icd = (p['ICD_NAME'] ?? p['icd_name'] ?? '').toString();
    final icdCode = (p['ICD_CODE'] ?? p['icd_code'] ?? '').toString();
    final bedName = (p['BED_NAME'] ?? p['bed_name'] ?? '').toString();
    final isChua = stt == 1 || stt == 2;
    // v3.1.03: Hiển thị thời gian tạo yêu cầu
    final inTime = _formatInTime(p);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 1,
      child: InkWell(
        onTap: () => _openECGExecute(p, p),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: isChua ? const Color(0xFFFFCDD2) : const Color(0xFFC8E6C9),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: isChua ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (priority == 2)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(3)),
                        child: const Text('Ưu tiên', style: TextStyle(fontSize: 9, color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                      ),
                    if (inTime.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(3)),
                        child: Text(inTime, style: const TextStyle(fontSize: 9, color: Color(0xFF0277BD), fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 1),
                  Row(children: [
                    if (code.isNotEmpty)
                      Text(code, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    if (bedName.isNotEmpty) ...[
                      const Text(' • ', style: TextStyle(fontSize: 10, color: Colors.black38)),
                      Text(bedName, style: const TextStyle(fontSize: 10, color: Color(0xFF303F9F), fontWeight: FontWeight.w600)),
                    ],
                    if (serviceReqCode.isNotEmpty) ...[
                      const Text(' • ', style: TextStyle(fontSize: 10, color: Colors.black38)),
                      Text(serviceReqCode, style: const TextStyle(fontSize: 10, color: Colors.black45)),
                    ],
                  ]),
                  if (icd.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        icdCode.isNotEmpty ? '$icdCode - $icd' : icd,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF6A1B9A), fontStyle: FontStyle.italic),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: isChua ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        sttName.isNotEmpty ? sttName : (isChua ? 'Chưa thực hiện' : 'Hoàn thành'),
                        style: TextStyle(
                          fontSize: 9,
                          color: isChua ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        serviceName,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF6A1B9A)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            if (isChua)
              ElevatedButton.icon(
                onPressed: () => _openECGExecute(p, p),
                icon: const Icon(Icons.flash_on, size: 12),
                label: const Text('ECG', style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            else
              const Icon(Icons.check_circle, color: Color(0xFF388E3C), size: 24),
          ]),
        ),
      ),
    );
  }

  /// v3.1.03: Format thời gian tạo yêu cầu thành HH:mm dd/MM
  String _formatInTime(Map<String, dynamic> p) {
    final dt = _parsePatientTime(p);
    if (dt == null) return '';
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    if (isToday) return '$h:$m';
    return '$h:$m ${dt.day}/${dt.month}';
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}';
  }
}
