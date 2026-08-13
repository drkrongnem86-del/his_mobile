import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/app_version_service.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/core/services/department_service.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
// v3.0.77: Bỏ import his_pro_api_service + his_pro_service (đã bỏ dialog login HIS Pro)
// import 'package:his_mobile/data/api/his_pro_api_service.dart';
// import 'package:his_mobile/data/api/his_pro_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/services/emr_push_api_source.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/data/patient_dataset.dart';
import 'package:his_mobile/presentation/widgets/patient_actions_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/presentation/widgets/patient_card.dart';
import 'package:his_mobile/presentation/widgets/patient_search_field.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';
import 'package:his_mobile/presentation/widgets/dept_picker_dialog.dart';
import 'package:his_mobile/presentation/screens/connection_check_screen.dart';
import 'package:his_mobile/presentation/screens/settings_screen.dart';
import 'package:his_mobile/presentation/screens/vpn_benh_vien_screen.dart';
import 'package:his_mobile/core/services/vpn_benh_vien_service.dart';
import 'package:his_mobile/presentation/screens/patients_screen.dart';
import 'package:his_mobile/presentation/screens/reports_screen.dart';
import 'package:his_mobile/presentation/screens/qr_scanner_screen.dart';
import 'package:his_mobile/presentation/screens/department_patients_screen.dart';
import 'package:his_mobile/presentation/screens/tien_ich_screen.dart';
import 'package:his_mobile/presentation/screens/y_te_so_home_screen.dart';
import 'package:his_mobile/presentation/screens/phong_tt_kcc_screen.dart';
import 'package:his_mobile/presentation/widgets/marquee_banner.dart';

/// Nguồn dữ liệu BN hiển thị - "Thật" (từ Data/HIS Pro API) vs "Từ app code" (PatientSeed).
enum PatientDataSource {
  seed,           // Cũ: chỉ có 6 BN mẫu từ HIS Pro logs
  thongke,        // BN thật từ Data API (real) — giữ enum value để không break model
  emptyThongke,   // API OK nhưng khoa này trống
  appCode,        // BN sinh ra từ PatientSeed trong app code (>= 28 BN / khoa)
  hisProLive,     // BN thật từ HIS Pro backend qua VPN (login + GetLView)
}

/// v2.91.0: Chọn nguồn API để lấy BN (user chọn trên AppBar)
/// - dataRoom: API 2 - `getPatientsInRooms` (Data 3000 `/v1/patient/benh-nhan-buong-benh`) - MẶC ĐỊNH
/// - dataDept: API fallback - `getPatientsByDepartment` (Data 3000 `/v1/patient/benh-nhan-khoa`)
/// - hisPro: API 1 - `api/HisTreatment/GetView` (HIS Pro 1408) - qua VPN
/// - public: API public - `113.163.187.3:8080` (Data public không cần auth)
enum PatientApiSource {
  dataRoom,   // API 2 - buồng bệnh (mặc định)
  dataDept,   // API fallback - toàn khoa
  hisPro,     // API 1 - HIS Pro qua VPN
  public,     // API public không auth
}

/// v3.0.74: Chỉ hiển thị 2 API: HIS Pro qua VPN + Public
/// (Bỏ Data 3000 buồng bệnh + toàn khoa)
List<PatientApiSource> _visiblePatientApiSources() {
  return [PatientApiSource.hisPro, PatientApiSource.public];
}

/// v3.0.75: Bộ lọc thời gian (theo mẫu HIS Pro desktop)
/// Thay thế "Loại ĐT" trên HomeScreen bằng chip chọn khoảng thời gian.
enum TrDateFilter {
  today,   // Trong ngày
  week,    // Trong tuần
  month,   // Trong tháng
  year,    // Trong năm
  custom,  // Khoảng ngày tự chọn
}

String _trDateLabel(TrDateFilter f) {
  switch (f) {
    case TrDateFilter.today:  return 'Hôm nay';
    case TrDateFilter.week:   return 'Tuần';
    case TrDateFilter.month:  return 'Tháng';
    case TrDateFilter.year:   return 'Năm';
    case TrDateFilter.custom: return 'Tùy chọn';
  }
}

/// Tính khoảng (from, to) tương ứng với TrDateFilter.
/// - today: 00:00 → 23:59 hôm nay
/// - week: 7 ngày gần nhất → hôm nay
/// - month: ngày 1 đầu tháng → hôm nay
/// - year: ngày 1/1 → hôm nay
/// - custom: giữ nguyên (đã set qua date range picker)
({DateTime from, DateTime to}) _trDateRange(TrDateFilter f, DateTime customFrom, DateTime customTo) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (f) {
    case TrDateFilter.today:
      return (
        from: today,
        to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    case TrDateFilter.week:
      return (
        from: today.subtract(const Duration(days: 6)),
        to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    case TrDateFilter.month:
      return (
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    case TrDateFilter.year:
      return (
        from: DateTime(now.year, 1, 1),
        to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    case TrDateFilter.custom:
      return (from: customFrom, to: customTo);
  }
}

/// Helper static - lấy username hiện tại (dùng cho phân quyền)
String _getCurrentUsernameStatic() {
  try {
    return ThongkeAuthService().currentUsername ?? '';
  } catch (_) {
    return '';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HisApiService _api = HisApiService();
  final ThongkeAuthService _thongkeAuth = ThongkeAuthService();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  int _currentDeptIndex = 0;  // v2.94.0: Sẽ load từ SharedPreferences trong initState
  final GlobalKey<_DepartmentPatientPageState> _departmentKey =
      GlobalKey<_DepartmentPatientPageState>();

  // v3.0.36: API push EMR đang chọn
  EmrPushApiSource _emrApiSource = EmrPushApiSource.public;
  bool _isEmrApiAdmin = false;

  // v2.94.0: Lưu/đọc khoa đã chọn
  static const _kDeptIndexKey = 'home_current_dept_index';

  // v3.0.75: Bộ lọc thời gian (HIS Pro style) - thay thế "Loại ĐT"
  TrDateFilter _trDateFilter = TrDateFilter.today;
  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  static const _kTrDateFilterKey = 'home_tr_date_filter';
  static const _kDateFromKey = 'home_date_from';
  static const _kDateToKey = 'home_date_to';

  Future<void> _loadDeptIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt(_kDeptIndexKey) ?? 0;
      if (idx >= 0 && idx < _departments.length) {
        if (mounted) {
          setState(() => _currentDeptIndex = idx);
        }
      }
    } catch (_) {}
  }

  /// v3.0.75: Load TrDateFilter + custom range
  Future<void> _loadTrDateFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt(_kTrDateFilterKey) ?? TrDateFilter.today.index;
      if (idx >= 0 && idx < TrDateFilter.values.length) {
        _trDateFilter = TrDateFilter.values[idx];
      }
      final fromMs = prefs.getInt(_kDateFromKey);
      final toMs = prefs.getInt(_kDateToKey);
      if (fromMs != null) _dateFrom = DateTime.fromMillisecondsSinceEpoch(fromMs);
      if (toMs != null) _dateTo = DateTime.fromMillisecondsSinceEpoch(toMs);
      // Nếu không phải custom, tính lại range theo filter hiện tại
      if (_trDateFilter != TrDateFilter.custom) {
        final r = _trDateRange(_trDateFilter, _dateFrom, _dateTo);
        _dateFrom = r.from;
        _dateTo = r.to;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveTrDateFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTrDateFilterKey, _trDateFilter.index);
      await prefs.setInt(_kDateFromKey, _dateFrom.millisecondsSinceEpoch);
      await prefs.setInt(_kDateToKey, _dateTo.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// v3.0.75: User chọn chip thời gian → cập nhật + reload
  void _onTrDateFilterChanged(TrDateFilter f) async {
    if (f == TrDateFilter.custom) {
      // Mở date range picker
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF303F9F),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        ),
      );
      if (range == null) return;
      setState(() {
        _trDateFilter = TrDateFilter.custom;
        _dateFrom = range.start;
        _dateTo = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
      });
    } else {
      final r = _trDateRange(f, _dateFrom, _dateTo);
      setState(() {
        _trDateFilter = f;
        _dateFrom = r.from;
        _dateTo = r.to;
      });
    }
    await _saveTrDateFilter();
    // Báo DepartmentPatientPage load lại với date range mới
    _departmentKey.currentState?.setDateRange(_dateFrom, _dateTo);
  }

  Future<void> _saveDeptIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kDeptIndexKey, _currentDeptIndex);
    } catch (_) {}
  }

  // v2.66.0: Helper - lấy list khoa từ DepartmentService (ưu tiên API) hoặc AppConstants
  List<Map<String, dynamic>> get _departments {
    // v2.79.0: Fix infinite recursion - fallback AppConstants khi DepartmentService rỗng
    List<Map<String, dynamic>> base;
    if (DepartmentService.instance.departments.isNotEmpty) {
      base = DepartmentService.instance.departments;
    } else {
      base = List<Map<String, dynamic>>.from(AppConstants.departments);
    }
    // v3.0.101: Luôn append Phòng đặc biệt (Phòng TT KCC) vào cuối
    // Tránh DepartmentService API không có entry này
    for (final d in AppConstants.departments) {
      if (d['isPhong'] == true && !base.any((e) => e['code'] == d['code'])) {
        base = [...base, d];
      }
    }
    return base;
  }
  String _searchQuery = '';
  // v2.85.0: Search query riêng cho mỗi khoa - không bị reset khi chuyển khoa
  final Map<int, String> _searchByDept = {};
  int? _lastDeptIndex;  // v2.85.0: nhớ khoa cuối cùng đã chọn
  Map<String, dynamic>? _selectedPatient;
  String _username = 'BS. Nểm';

  // v2.75.0: Drawer "CHỌN KHOA" collapse/expand + search khoa
  bool _deptDrawerExpanded = false;
  String _deptDrawerSearch = '';
  final TextEditingController _deptSearchCtrl = TextEditingController();

  // v2.75.5: Room filter chips - lọc BN theo phòng
  String? _selectedRoom; // null = tất cả

  // v2.64.0: Tab trạng thái BN (0=Chưa tiếp nhận, 1=Đang điều trị, 2=Đã điều trị)
  int _statusTab = 1;  // Mặc định: Đang điều trị

  @override
  void initState() {
    super.initState();
    _loadDeptIndex();  // v2.94.0: Load khoa đã chọn từ SharedPreferences
    _loadTrDateFilter();  // v3.0.75: Load TrDateFilter (HIS Pro style)
    _loadUsername();
    _loadEmrApiSource();  // v3.0.36: Load API push EMR đã chọn
    _loadTreatmentTypeFilter();  // v3.0.42: Load filter TREATMENT_TYPE_NAME
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus && _showSuggestions) {
        setState(() => _showSuggestions = false);
      }
    });
    // v3.0.77: Bỏ HIS Pro auto-bootstrap (đã bỏ dialog login thủ công)
    // - HIS Pro dùng bearer token auto-load từ splash screen
    // - Không cần bootstrap thêm ở home
  }

  /// v3.0.36: Load API push EMR + check role admin
  Future<void> _loadEmrApiSource() async {
    final selector = EmrApiSelectorService.instance;
    _isEmrApiAdmin = selector.isAdmin();
    final src = await selector.getSelected();
    if (!mounted) return;
    setState(() {
      _emrApiSource = src;
    });
  }

  /// v3.0.36: User chọn API push EMR (chỉ admin mới thấy options)
  Future<void> _setEmrApiSource(EmrPushApiSource src) async {
    if (src != EmrPushApiSource.public && !_isEmrApiAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chỉ user `nemk` mới được chọn API khác'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final ok = await EmrApiSelectorService.instance.setSelected(src);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _emrApiSource = src;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Đã chuyển sang ${src.label}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// v3.0.36: Màu badge cho API push
  Color _emrApiColor(EmrPushApiSource src) {
    switch (src) {
      case EmrPushApiSource.public: return Colors.lightBlue.shade700;
      case EmrPushApiSource.hisPro: return Colors.indigo.shade700;
      case EmrPushApiSource.mockLocal: return Colors.deepPurple.shade700;
    }
  }

  /// v3.0.36: Icon cho API push
  IconData _emrApiIcon(EmrPushApiSource src) {
    switch (src) {
      case EmrPushApiSource.public: return Icons.public;
      case EmrPushApiSource.hisPro: return Icons.local_hospital;
      case EmrPushApiSource.mockLocal: return Icons.cloud;
    }
  }

  Future<void> _loadUsername() async {
    // Ưu tiên: Data (singleton) - user login thật ở đây
    await DataService.instance.loadSession();
    final dataUser = DataService.instance.user;
    if (dataUser != null && (dataUser.userName.isNotEmpty)) {
      if (!mounted) return;
      setState(() {
        _username = 'BS. ${dataUser.userName}';
      });
      return;
    }
    // Fallback: ThongkeAuthService (HIS Pro VPN)
    var name = _thongkeAuth.currentUsername;
    if (name == null) {
      final ok = await _thongkeAuth.restoreSession();
      if (ok) name = _thongkeAuth.currentUsername;
    }
    if (!mounted) return;
    setState(() {
      _username = (name != null && name.isNotEmpty) ? 'BS. $name' : 'BS. Nểm';
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _deptSearchCtrl.dispose();
    super.dispose();
  }

  /// v2.37.1: Tính gợi ý BN từ _patients hiện tại (bỏ PatientSeed)
  void _updateSuggestions(String q) {
    q = q.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    final lower = q.toLowerCase();
    final noDiacritics = removeDiacritics(lower);
    // v3.0.76: BỎ PatientSeed - chỉ tìm trong BN đang hiển thị ở DepartmentPatientPage
    final all = <Map<String, dynamic>>[
      ...(_departmentKey.currentState?._patients ?? <Map<String, dynamic>>[]),
    ];
    final scored = <Map<String, dynamic>>[];
    for (final p in all) {
      final name = PatientNameHelper.getName(p);
      final code = (p['treatment_code'] ?? p['TDL_TREATMENT_CODE'] ?? p['MADT'] ?? '').toString();
      final pcode = (p['patient_code'] ?? p['TDL_PATIENT_CODE'] ?? p['MABN'] ?? '').toString();
      final nameLow = removeDiacritics(name.toLowerCase());
      int score = 0;
      if (nameLow == noDiacritics) score = 100;
      else if (nameLow.startsWith(noDiacritics)) score = 80;
      else if (nameLow.contains(noDiacritics)) score = 60;
      if (code == q) score = score > 95 ? score : 95;
      else if (code.startsWith(q)) score = score > 70 ? score : 70;
      else if (code.contains(q)) score = score > 50 ? score : 50;
      if (pcode == q) score = score > 90 ? score : 90;
      else if (pcode.startsWith(q)) score = score > 65 ? score : 65;
      if (score > 0) scored.add({...p, '_score': score});
    }
    scored.sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));
    setState(() {
      _suggestions = scored.take(10).toList();
      _showSuggestions = true;
    });
  }

  void _onDeptChanged(int index) {
    setState(() => _currentDeptIndex = index);
    _saveDeptIndex();  // v2.94.0: Lưu khoa đã chọn
  }

  /// Banner BN đang thao tác
  Widget _buildPatientBanner() {
    if (_selectedPatient == null) return const SizedBox.shrink();
    final p = _selectedPatient!;
    String _g(String k1, [String? k2, String? k3]) =>
        (p[k1] ?? p[k2 ?? ''] ?? p[k3 ?? ''] ?? '').toString();
    final name = capitalizeVietnameseName(PatientNameHelper.getName(p));
    final code = _g('MA_BENH_NHAN', 'TDL_PATIENT_CODE', 'MA_BN');
    final reqCode = _g('MA_DIEU_TRI', 'TDL_TREATMENT_CODE', 'SERVICE_REQ_CODE');
    final icd = _g('ICD_BENH_NHAN_FULL', 'ICD_NAME', 'CHAN_DOAN');
    final khoa = _g('KHOA_DIEU_TRI', 'TDL_REQUEST_DEPARTMENT_NAME', 'TEN_KHOA');

    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.medical_services, size: 12, color: Colors.amber),
                    SizedBox(width: 3),
                    Text(
                      'ĐANG THAO TÁC:',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                if (code.isNotEmpty || reqCode.isNotEmpty)
                  Text(
                    [if (code.isNotEmpty) 'Mã BN: $code', if (reqCode.isNotEmpty) 'ĐT: $reqCode'].join(' | '),
                    style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                if (icd.isNotEmpty)
                  Text(
                    'ICD: $icd',
                    style: const TextStyle(color: Colors.black54, fontSize: 10, fontStyle: FontStyle.italic),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                if (khoa.isNotEmpty)
                  Text(
                    'Khoa: $khoa',
                    style: const TextStyle(color: Colors.indigo, fontSize: 10, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black54, size: 20),
            tooltip: 'Bỏ chọn',
            onPressed: () => setState(() => _selectedPatient = null),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final dataIsOnline = DataService.instance.isAuthenticated;
    final currentDept = _departments[_currentDeptIndex];
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: const BoxDecoration(color: Color(0xFF303F9F)),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_username,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        // v2.82.0: Hiển thị tên khoa hiện tại thay vì hardcode 'Khoa Cấp Cứu Lưu'
                        Text(
                          currentDept['name']?.toString() ?? 'Bác sĩ',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.fiber_manual_record,
                                color: dataIsOnline ? Colors.greenAccent : Colors.amberAccent,
                                size: 10),
                            const SizedBox(width: 4),
                            Text(
                              dataIsOnline ? 'Data: Online' : 'Data: Offline',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // === 3 MỤC CHÍNH ===
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 4),

                  // v2.73.0: HÀNG 1 - "Chọn khoa" - danh sách khoa nhanh
                  _buildDrawerDeptList(),

                  const Divider(height: 16),

                  // v2.81.0: Bỏ mục 'Bệnh nhân' trong Drawer (giống bottom nav)
                  _drawerItem(
                    icon: Icons.bar_chart,
                    color: Colors.green,
                    title: 'Báo cáo',
                    subtitle: 'Thống kê khám, thuốc, XN...',
                    onTap: () {
                      context.safePopDelayed();
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (mounted) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
                        }
                      });
                    },
                  ),

                  const Divider(height: 24),

                  // v3.0.19: BỎ menu "Y tế số" - đã gộp vào "Thao tác bệnh nhân" ở bottom sheet
                  _drawerItem(
                    icon: Icons.refresh,
                    color: Colors.blue,
                    title: 'Làm mới dữ liệu',
                    subtitle: 'Tải lại DS BN khoa hiện tại',
                    onTap: () {
                      context.safePop();
                      setState(() {});
                    },
                  ),

                  const SizedBox(height: 16),

                  Center(
                    child: Text(
                      '${AppVersionService.instance.displayVersion} | Dr. Nểm CCĐK',
                      style: TextStyle(color: Colors.black45, fontSize: 10),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// v2.75.0: Drawer "CHỌN KHOA" - 1 ô collapse/expand + search khoa
  /// - Mặc định: thu gọn, chỉ hiện khoa hiện tại
  /// - Bấm header: sổ xuống → search box + list khoa (filter theo gõ)
  /// - Chọn khoa → đồng bộ BN list ở cả Drawer + Bottom nav
  Widget _buildDrawerDeptList() {
    final currentDept = _departments[_currentDeptIndex];
    final currentName = currentDept['name']?.toString() ?? 'Chưa chọn khoa';
    final currentCode = currentDept['code']?.toString() ?? '';
    final currentIcon = currentDept['icon'] as String? ?? '🏥';

    // Filter khoa theo search
    final filtered = _deptDrawerSearch.isEmpty
        ? _departments.asMap().entries.toList()
        : _departments.asMap().entries.where((entry) {
            final d = entry.value;
            final q = _deptDrawerSearch.toLowerCase();
            return (d['name']?.toString() ?? '').toLowerCase().contains(q) ||
                (d['code']?.toString() ?? '').toLowerCase().contains(q) ||
                d['id'].toString().contains(q);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // === 1 Ô THU GỌN / SỔ XUỐNG ===
        InkWell(
          onTap: () {
            setState(() {
              _deptDrawerExpanded = !_deptDrawerExpanded;
              if (_deptDrawerExpanded) {
                _deptDrawerSearch = '';
                _deptSearchCtrl.clear();
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF303F9F).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF303F9F).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Text(currentIcon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CHỌN KHOA',
                        style: TextStyle(
                          color: Color(0xFF303F9F),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentName,
                        style: const TextStyle(
                          color: Color(0xFF303F9F),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (currentCode.isNotEmpty)
                        Text(
                          '$currentCode • ${_departments.length} khoa',
                          style: const TextStyle(color: Colors.black54, fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Nút thu gọn / sổ xuống
                Icon(
                  _deptDrawerExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: const Color(0xFF303F9F),
                  size: 24,
                ),
              ],
            ),
          ),
        ),

        // === PHẦN MỞ RỘNG (search + list) ===
        if (_deptDrawerExpanded) ...[
          // Search box
          Container(
            margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black26, width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.black45, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _deptSearchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Tìm khoa (tên, mã, ID)...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) {
                      setState(() => _deptDrawerSearch = v);
                    },
                  ),
                ),
                if (_deptDrawerSearch.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16, color: Colors.black45),
                    onPressed: () {
                      setState(() {
                        _deptDrawerSearch = '';
                        _deptSearchCtrl.clear();
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          // Nút "Tìm khoa" mở full dialog search
          InkWell(
            onTap: () async {
              Navigator.pop(context);
              await Future.delayed(const Duration(milliseconds: 150));
              if (!mounted) return;
              final picked = await DeptPickerDialog.show(context, _currentDeptIndex);
              if (picked != null) {
                _pickDept(picked);
              }
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: const [
                  Icon(Icons.manage_search, color: Color(0xFF303F9F), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Tìm khoa (đầy đủ)...',
                    style: TextStyle(
                      color: Color(0xFF303F9F),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // List khoa (filtered, scrollable)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Không tìm thấy khoa phù hợp',
                      style: TextStyle(color: Colors.black45, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) {
                      final entry = filtered[idx];
                      final i = entry.key;
                      final d = entry.value;
                      final isCurrent = i == _currentDeptIndex;
                      return InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          Future.delayed(const Duration(milliseconds: 150), () {
                            if (!mounted) return;
                            _pickDept(i);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isCurrent ? const Color(0xFF303F9F).withValues(alpha: 0.1) : null,
                            border: Border(
                              left: BorderSide(
                                color: isCurrent ? const Color(0xFF303F9F) : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                d['icon'] as String? ?? '🏥',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d['name']?.toString() ?? '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                        color: isCurrent ? const Color(0xFF303F9F) : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${d['code']} • ID ${d['id']}',
                                      style: const TextStyle(fontSize: 9, color: Colors.black45),
                                    ),
                                  ],
                                ),
                              ),
                              if (isCurrent)
                                const Icon(Icons.check_circle, color: Color(0xFF303F9F), size: 14),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  /// v2.68.0: Hạng 1 trong Drawer - "Đang xem khoa" (giống app v0.3.5 team BS)
  /// Hiển thị khoa hiện tại + bấm để đổi khoa
  Widget _drawerDeptItem(Map<String, dynamic> currentDept) {
    final name = currentDept['name']?.toString() ?? '';
    final code = currentDept['code']?.toString() ?? '';
    final id = currentDept['id']?.toString() ?? '';
    return InkWell(
      onTap: () async {
        // Mở picker đổi khoa (đóng drawer trước)
        Navigator.pop(context);
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        final picked = await DeptPickerDialog.show(context, _currentDeptIndex);
        if (picked != null) {
          _pickDept(picked);
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF303F9F).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF303F9F).withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF303F9F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_hospital, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Đang xem khoa',
                    style: TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: const TextStyle(color: Color(0xFF303F9F), fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$code • ID $id • ${_departments.length} khoa',
                    style: const TextStyle(color: Colors.black54, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF303F9F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.swap_vert, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: Colors.black45, size: 20),
      onTap: onTap,
    );
  }

  void _pickDept(int i) {
    // v3.0.103: Special index 99001 = Phòng TT Khoa Cấp Cứu (từ card nổi bật ở dialog)
    if (i == 99001) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PhongTTKccScreen()),
      );
      return;
    }
    if (i == _currentDeptIndex) return;
    // v3.0.101: Check "Phòng" đặc biệt từ AppConstants (dialog dùng list này)
    // Tránh index lệch khi DepartmentService load từ API (số entry khác 53)
    if (i >= 0 && i < AppConstants.departments.length) {
      final d = AppConstants.departments[i];
      if (d['isPhong'] == true) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PhongTTKccScreen()),
        );
        return;
      }
    }
    final d = _departments[i];
    setState(() {
      _currentDeptIndex = i;
      _selectedRoom = null; // v2.75.5: reset room filter khi đổi khoa
    });
    _saveDeptIndex();  // v2.94.0: Lưu khoa đã chọn
    _thongkeAuth.setCurrentDepartment(
      d['code']?.toString(),
      d['name']?.toString(),
    );
    // v2.75.0: Sync BN list ở cả Drawer + Bottom nav - reload khoa mới
    _departmentKey.currentState?._load();
  }

  // v2.78.0: Dialog search giống 22222.apk
  // Bấm icon search trên AppBar → mở dialog → gõ tên → filter
  void _showSearchDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.search, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Tìm bệnh nhân', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Tên / Mã BN / SĐT',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            setState(() => _searchQuery = v.trim());
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _searchQuery = '');
              Navigator.pop(ctx);
            },
            child: const Text('Xóa lọc'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Tìm'),
            onPressed: () {
              setState(() => _searchQuery = ctrl.text.trim());
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _openActions(Map<String, dynamic> patient) {
    // v3.0.75: BỎ "always on top" - KHÔNG set _selectedPatient làm AppBar/banner "ghim" BN
    // Trước đó: setState(() => _selectedPatient = patient) → AppBar + banner vàng hiển thị BN
    //             kể cả khi user đã đóng sheet / chuyển sang màn khác
    // Sau: clear state → về trang chủ bình thường; BN chỉ hiện trong sheet
    setState(() => _selectedPatient = null);
    final dept = _departments[_currentDeptIndex];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      // v3.0.63: BỎ HOÀN TOÀN barrier (Colors.transparent) để home KHÔNG bị xám
      // BS yêu cầu: "khi thao tác BN, trang chủ vẫn hiện rõ không bị xám"
      // Drop shadow trên sheet đã đủ phân biệt với nền
      barrierColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      // v3.0.58: maxHeight 70% để home peek 30% (BS muốn "trang chủ luôn nổi")
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
      ),
      builder: (_) => PatientActionsSheet(
        patient: patient,
        department: dept,
      ),
    ).whenComplete(() {
      // v3.0.75: Khi đóng sheet → chắc chắn clear (phòng case set trước đó)
      if (mounted) setState(() => _selectedPatient = null);
    });
  }

  void _openConnectionCheck() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConnectionCheckScreen()),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('Thoát ứng dụng', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Bạn có chắc muốn đóng ứng dụng?\n\n'
          'Ứng dụng sẽ thoát hoàn toàn khỏi điện thoại.',
          style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close, color: Colors.black54, size: 20),
            label: const Text('HỦY', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              side: const BorderSide(color: Colors.black26, width: 1),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              SystemNavigator.pop();
            },
            icon: const Icon(Icons.power_settings_new, color: Colors.white, size: 20),
            label: const Text('THOÁT NGAY', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/login');
            },
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dept = _departments[_currentDeptIndex];
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 24),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        // v2.68.0: Title = tên khoa đang xem + click để đổi
        title: InkWell(
          onTap: () async {
            final picked = await DeptPickerDialog.show(context, _currentDeptIndex);
            if (picked != null) _pickDept(picked);
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_hospital, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    dept['name']?.toString() ?? 'Chọn khoa',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.white, size: 22),
                if (_selectedPatient != null) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: InkWell(
                      onTap: () => setState(() => _selectedPatient = null),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(4)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                '● ${capitalizeVietnameseName((_selectedPatient!['TDL_PATIENT_UNSIGNED_NAME'] ?? _selectedPatient!['TDL_PATIENT_NAME'] ?? _selectedPatient!['tdl_patient_name'] ?? 'BN').toString())}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.close, color: Colors.white, size: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          // v3.0.74: VPN Bệnh viện status indicator
          _VpnStatusIndicator(),
          // v2.94.0: BỎ nút search IconButton trên AppBar (không tắc dụng, search đã có ở dưới)
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
            tooltip: 'Quét QR BN',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.wifi_find, color: Colors.white),
            tooltip: 'Kiểm tra VPN',
            onPressed: _openConnectionCheck,
          ),
          // v3.0.44: BỎ AppBar API selector (đã fix mặc định HIS Pro 1417, không cần chọn)
          // _buildEmrApiSelector(), // BỎ

        ],
      ),
      // v2.64.0: KHÔNG có bottom nav
      body: Column(
        children: [
          // ===== USER HEADER - tên user đăng nhập cố định trên nền =====
          UserHeader.fromAuth(
            department: dept['name']?.toString(),
          ),

          // v3.0.19: BỎ banner Bearer + thay bằng marquee quảng cáo tự chạy
          // v3.0.42: Version tự động từ AppVersionService (đọc từ package_info_plus)
          MarqueeBanner(
            messages: [
              '🏥 HIS Mobile v${AppVersionService.instance.version}+${AppVersionService.instance.buildNumber} - Ứng dụng quản lý EMR Bệnh viện Ninh Thuận',
              '⚡ 20 chức năng Y tế số - Lưu ký SmartCA VNPT trực tiếp lên EMR',
              '📱 Tạo phiếu khám, phiếu chăm sóc, bàn giao ca, đẩy thẳng lên EMR',
              '🏥 Khoa Cấp Cứu Lưu - BVĐK Ninh Thuận',
              '⚡ 2 nút Lưu - Lưu ký - workflow chuẩn từ app Y tế số (Bộ Y tế)',
              '📋 Quản lý bệnh nhân: 81 khoa phòng, 33k CLS, 32k thuốc, 174 ICD-10',
              '🔍 Tra cứu nhanh: BHYT, ICD-10, danh sách tiêm chủng, y lệnh',
              '💾 Lưu offline + đẩy EMR khi có mạng',
            ],
            backgroundColor: const Color(0xFF00838F),
            textColor: Colors.white,
          ),

          // Banner tên BN đang thao tác
          if (_selectedPatient != null) _buildPatientBanner(),

          // v2.81.0: BỎ _buildStatusTabs + _buildRoomChips
          // Thay bằng search bar thật (TextField + diacritic-insensitive filter)
          // Hiển thị ngay trên BN list

          // v2.96.0: API selector TRÊN, search bar DƯỚI
          // v2.92.0: SegmentedButton chọn API - to, nổi bật, dễ thấy
          _buildApiSelector(),

          // v2.81.0: Search bar thật - filter trực tiếp tên BN
          _buildSearchBar(),

          Expanded(
            child: DepartmentPatientPage(
              key: _departmentKey,
              department: _departments[_currentDeptIndex],
              searchQuery: _searchQuery,
              // v2.81.0: Bỏ roomFilter
              roomFilter: null,
              // v3.0.42: Filter TREATMENT_TYPE_NAME
              treatmentTypeFilter: _treatmentTypeFilter,
              // v3.0.75: Date range từ TrDateFilter (HIS Pro style)
              dateFrom: _dateFrom,
              dateTo: _dateTo,
              selectedPatientId: _selectedPatient?['ID'] as int?,
              onPatientTap: _openActions,
              onPatientSelect: (p) => setState(() => _selectedPatient = p),
            ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  // v3.0.42: Filter TREATMENT_TYPE_NAME (lưu theo state)
  // v3.0.57: Đổi sang dynamic - dùng TREATMENT_TYPE_NAME field thật từ HIS Pro
  // (vd: "Nội trú" / "Khám" / "Ngoại trú") thay vì trạng thái khám
  String _treatmentTypeFilter = 'all';
  static const _kTreatmentTypeFilterKey = 'home_treatment_type_filter';

  Future<void> _loadTreatmentTypeFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kTreatmentTypeFilterKey) ?? 'all';
      if (mounted) setState(() => _treatmentTypeFilter = v);
    } catch (_) {}
  }

  Future<void> _setTreatmentTypeFilter(String v) async {
    setState(() => _treatmentTypeFilter = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTreatmentTypeFilterKey, v);
    } catch (_) {}
  }

  /// v3.0.57: Lấy unique TREATMENT_TYPE_NAME từ DepartmentPatientPage qua GlobalKey
  /// - _patients ở trong _DepartmentPatientPageState, không phải _HomeScreenState
  /// - Dùng GlobalKey để access patients list
  /// - Fallback: nếu chưa load xong thì dùng 3 giá trị mặc định
  List<String> _getUniqueTreatmentTypeNames() {
    final set = <String>{};
    final patients = _departmentKey.currentState?._patients ?? [];
    for (final p in patients) {
      final t = (p['TREATMENT_TYPE_NAME'] ?? p['treatment_type_name'] ?? '').toString().trim();
      if (t.isNotEmpty && t != '-') set.add(t);
    }
    final list = set.toList()..sort();
    return list;
  }

  // v3.0.75: Search bar + dòng TrDateFilter (HIS Pro style: Hôm nay/Tuần/Tháng/Năm/Tùy chọn)
  // v3.0.74 trở về trước: dùng "Loại ĐT" - bỏ theo yêu cầu BS
  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dòng 1: Search TextField
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Tìm tên / mã BN / mã ĐT (lọc trong khoa hiện tại)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.indigo, width: 2),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.black54),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
            onChanged: (q) => setState(() => _searchQuery = q),
          ),
          // Dòng 2: v3.0.75 Bộ lọc thời gian (HIS Pro style: Hôm nay/Tuần/Tháng/Năm/Tùy chọn)
          SizedBox(
            height: 36,
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Color(0xFF303F9F)),
                const SizedBox(width: 4),
                const Text('Thời gian:', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in TrDateFilter.values)
                        _trDateFilterChip(f),
                    ],
                  ),
                ),
                // Hiển thị range ngắn gọn bên phải
                Text(
                  '${_fmtShortDate(_dateFrom)}→${_fmtShortDate(_dateTo)}',
                  style: const TextStyle(fontSize: 9, color: Colors.black45, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtShortDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}';
  }

  /// v3.0.75: Chip TrDateFilter
  Widget _trDateFilterChip(TrDateFilter f) {
    final selected = _trDateFilter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(_trDateLabel(f), style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.black87)),
        selected: selected,
        onSelected: (_) => _onTrDateFilterChanged(f),
        selectedColor: const Color(0xFF303F9F),
        backgroundColor: Colors.grey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// v3.0.42: Chip filter loại điều trị (legacy - giữ cho code cũ nếu còn tham chiếu)
  Widget _filterChip(String value, String label) {
    final selected = _treatmentTypeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.black87)),
        selected: selected,
        onSelected: (_) => _setTreatmentTypeFilter(value),
        selectedColor: Colors.indigo.shade700,
        backgroundColor: Colors.grey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // v3.0.6: Banner nho nhỏ ở đầu HomeScreen cho BS thấy app đang dùng Bearer
  // hardcode từ app Y tế số thật v0.3.3 (verified 2026-07-14 work với mọi endpoint).
  // Nếu banner KHÔNG hiện → app chưa phải v3.0.6, cần cài đè lên bản cũ.


  Widget _endpointRow(String name, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$name:',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              url,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }


  int _countData(dynamic data) {
    if (data is Map && data['Data'] is List) return (data['Data'] as List).length;
    if (data is List) return data.length;
    return 0;
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // v3.0.42: Selector cho API push EMR trên AppBar (←/→ 2 options: HIS Pro 1408 + Public 8080)
  // User thường thấy 2 options. User `nemk` thấy thêm 1 option Mock.
  Widget _buildEmrApiSelector() {
    final visible = EmrApiSelectorService.instance.visibleSources();
    final currentIdx = visible.indexOf(_emrApiSource);
    final safeIdx = currentIdx < 0 ? 0 : currentIdx;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 18),
            tooltip: 'API push trước',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              if (visible.isEmpty) return;
              final prevIdx = (safeIdx - 1) < 0 ? visible.length - 1 : safeIdx - 1;
              _setEmrApiSource(visible[prevIdx]);
            },
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 56),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _emrApiShortLabel(_emrApiSource),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white, size: 18),
            tooltip: 'API push sau',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              if (visible.isEmpty) return;
              final nextIdx = (safeIdx + 1) >= visible.length ? 0 : safeIdx + 1;
              _setEmrApiSource(visible[nextIdx]);
            },
          ),
        ],
      ),
    );
  }

  /// v3.0.42: Label ngắn cho API push EMR (hiển thị trên AppBar)
  String _emrApiShortLabel(EmrPushApiSource src) {
    switch (src) {
      case EmrPushApiSource.hisPro: return '🏥 HIS';
      case EmrPushApiSource.public: return '🌍 8080';
      case EmrPushApiSource.mockLocal: return '🧪 Mock';
    }
  }

  // v2.92.0: SegmentedButton chọn API - to, nổi bật, dễ thấy
  // v2.93.0: Thêm ←/→ nút chuyển qua lại giữa các API
  Widget _buildApiSelector() {
    // Lấy API source hiện tại từ DepartmentPatientPage (nếu có)
    final currentSrc = _departmentKey.currentState?._apiSource ?? PatientApiSource.dataRoom;
    final currentIdx = PatientApiSource.values.indexOf(currentSrc);
    return Container(
      color: const Color(0xFFE8EAF6),  // nền xanh nhạt indigo
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Icon(Icons.cloud_outlined, size: 16, color: Colors.indigo),
          ),
          const Text('API:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo)),
          // v2.93.0: Nút ←  (trước)
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20, color: Colors.indigo),
            tooltip: 'API trước',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              final prevIdx = (currentIdx - 1) < 0
                  ? PatientApiSource.values.length - 1
                  : currentIdx - 1;
              _departmentKey.currentState?._setApiSource(PatientApiSource.values[prevIdx]);
              setState(() {});
            },
          ),
          // Tên API hiện tại
          Expanded(
            child: GestureDetector(
              onTap: () {
                // Tap để mở menu chọn
                _showApiMenu(context, currentSrc);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _apiSourceColor(currentSrc),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    _apiSourceLabelShort(currentSrc),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // v2.93.0: Nút →  (sau)
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20, color: Colors.indigo),
            tooltip: 'API sau',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              final nextIdx = (currentIdx + 1) >= PatientApiSource.values.length
                  ? 0
                  : currentIdx + 1;
              _departmentKey.currentState?._setApiSource(PatientApiSource.values[nextIdx]);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // v2.93.0: Menu chọn API (khi tap vào tên API hiện tại)
  void _showApiMenu(BuildContext context, PatientApiSource current) {
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
              child: const Text('Chọn nguồn API lấy BN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ..._visiblePatientApiSources().map((src) {
              final isSel = current == src;
              return ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _apiSourceColor(src).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.cloud, color: _apiSourceColor(src), size: 20),
                ),
                title: Text(_apiSourceLabelForHome(src)),
                subtitle: Text(_apiSourceUrl(src), style: const TextStyle(fontSize: 10)),
                trailing: isSel ? Icon(Icons.check_circle, color: _apiSourceColor(src)) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _departmentKey.currentState?._setApiSource(src);
                  setState(() {});
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // v2.93.0: Label đầy đủ cho menu
  static String _apiSourceLabelForHome(PatientApiSource src) {
    switch (src) {
      case PatientApiSource.dataRoom: return 'API 2 - Data 3000 (buồng bệnh)';
      case PatientApiSource.dataDept: return 'API - Data 3000 (toàn khoa)';
      case PatientApiSource.hisPro: return 'API 1 - HIS Pro 1408 (qua VPN)';
      case PatientApiSource.public: return 'API Public - 113.163.187.3:8080';
    }
  }

  // v2.93.0: URL hiển thị trong menu
  static String _apiSourceUrl(PatientApiSource src) {
    switch (src) {
      case PatientApiSource.dataRoom: return 'POST /v1/patient/benh-nhan-buong-benh';
      case PatientApiSource.dataDept: return 'POST /v1/patient/benh-nhan-khoa';
      case PatientApiSource.hisPro: return 'POST /api/HisTreatment/GetView?param=BASE64';
      case PatientApiSource.public: return 'GET /emr/index (Data public)';
    }
  }

  // v2.92.0: Helper - label ngắn cho SegmentedButton
  static String _apiSourceLabelShort(PatientApiSource src) {
    switch (src) {
      case PatientApiSource.dataRoom: return '🌐 API 2';
      case PatientApiSource.dataDept: return '📋 Data';
      case PatientApiSource.hisPro: return '🏥 API 1';
      case PatientApiSource.public: return '🌍 Public';
    }
  }

  // v2.92.0: Helper - màu cho SegmentedButton
  static Color _apiSourceColor(PatientApiSource src) {
    switch (src) {
      case PatientApiSource.dataRoom: return Colors.teal.shade700;
      case PatientApiSource.dataDept: return Colors.green.shade700;
      case PatientApiSource.hisPro: return Colors.indigo.shade700;
      case PatientApiSource.public: return Colors.orange.shade700;
    }
  }

  // ===== v2.64.0: 3 tab trạng thái =====

  /// v2.75.8: Đếm BN theo trạng thái - fix đúng logic, KHÔNG miss BN
  /// 0 = Chưa tiếp nhận (BN không có bất kỳ field status nào)
  /// 1 = Đang điều trị (BN có is_pause='0' HOẶC có sttId HOẶC có out_time trong 24h)
  /// 2 = Đã điều trị (BN có out_time > 24h trước)
  Map<int, int> _countByStatus() {
    // Lấy _patients từ _DepartmentPatientPageState qua key
    final patients = _departmentKey.currentState?._patients ?? <Map<String, dynamic>>[];
    final counts = {0: 0, 1: 0, 2: 0};
    for (final p in patients) {
      final outTime = (p['out_time']?.toString() ?? '').trim();
      final sttId = p['service_req_stt_id'] ?? p['SERVICE_REQ_STT_ID'];
      final isPause = (p['is_pause']?.toString() ?? '').trim();
      DateTime? outDt;
      if (outTime.isNotEmpty && outTime != '-' && outTime != 'null') {
        try {
          if (outTime.contains('/')) {
            final parts = outTime.split(' ');
            final date = parts[0].split('/');
            final time = parts.length > 1 ? parts[1].split(':') : ['0','0'];
            outDt = DateTime(int.parse(date[2]), int.parse(date[1]), int.parse(date[0]),
                int.parse(time[0]), int.parse(time[1]));
          } else {
            outDt = DateTime.tryParse(outTime);
          }
        } catch (_) { outDt = null; }
      }
      final hasOutTime = outDt != null;
      final recentlyDischarged = hasOutTime
          ? DateTime.now().difference(outDt!) < const Duration(hours: 24)
          : false;
      // v2.75.8: Logic mới - an toàn, không miss BN
      if (hasOutTime && !recentlyDischarged) {
        // Có out_time trong 24h → vừa ra viện → "Đang điều trị" (BN vẫn còn trong khoa)
        counts[1] = (counts[1] ?? 0) + 1;
      } else if (hasOutTime) {
        // Có out_time > 24h → "Đã điều trị"
        counts[2] = (counts[2] ?? 0) + 1;
      } else if (isPause.isNotEmpty || sttId != null) {
        // Có is_pause HOẶC sttId → BN có status rõ ràng → "Đang điều trị"
        counts[1] = (counts[1] ?? 0) + 1;
      } else {
        // Không có bất kỳ field nào → "Chưa tiếp nhận"
        counts[0] = (counts[0] ?? 0) + 1;
      }
    }
    return counts;
  }

  // v2.81.0: BỎ _buildStatusTabs, _buildRoomChips, _buildFilterBar, _buildSmartSearchBar
  // Thay bằng _buildSearchBar() đơn giản (TextField ở dưới AppBar)
  // Không còn tabs trạng thái, không còn chips phòng

  // ignore: unused_element
  Widget _buildStatusTabs() => const SizedBox.shrink();
  // ignore: unused_element
  Widget _statusTabBtn(int tab, String label, int count, Color activeColor) => const SizedBox.shrink();
  // ignore: unused_element
  Widget _buildRoomChips() => const SizedBox.shrink();
  // ignore: unused_element
  Widget _roomChip({required String label, required String? value, required bool isSelected}) => const SizedBox.shrink();
  // ignore: unused_element
  Widget _buildFilterBar() => const SizedBox.shrink();
  // ignore: unused_element
  Widget _buildSmartSearchBar() => const SizedBox.shrink();
  /// v2.74.0: Tính gợi ý BN thật (có reqCode, name match) - max 8 items
  List<Map<String, dynamic>> _computeSearchSuggestions() {
    if (_searchQuery.trim().isEmpty) return [];
    final patients = _departmentKey.currentState?._patients ?? <Map<String, dynamic>>[];
    final query = _searchQuery.trim();
    final matches = <Map<String, dynamic>>[];
    for (final p in patients) {
      final reqCode = (p['treatment_code'] ?? p['TDL_TREATMENT_CODE'] ?? '').toString();
      // v2.74.0: chỉ BN thật (có reqCode)
      if (reqCode.isEmpty) continue;
      final name = capitalizeVietnameseName(PatientNameHelper.getName(p));
      final code = (p['tdl_patient_code'] ?? p['TDL_PATIENT_CODE'] ?? '').toString();
      // Match theo tên HOẶC mã
      if (matchesVietnamese(name, query) || matchesVietnamese(code, query)) {
        matches.add({
          'name': name,
          'code': code,
          'reqCode': reqCode,
        });
        if (matches.length >= 8) break;  // max 8 suggestions
      }
    }
    return matches;
  }
}

/// 1 Page BN cho 1 khoa - load API + filter search
class DepartmentPatientPage extends StatefulWidget {
  final Map<String, dynamic> department;
  final String searchQuery;
  final String? roomFilter; // v2.75.5: lọc theo phòng
  // v3.0.42: Filter TREATMENT_TYPE_NAME ('all' / 'noitru' / 'kham' / 'ngoaitru')
  final String treatmentTypeFilter;
  // v3.0.75: Date range từ TrDateFilter (HIS Pro style)
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final Function(Map<String, dynamic>) onPatientTap;
  final ValueChanged<Map<String, dynamic>?> onPatientSelect;
  final int? selectedPatientId;

  const DepartmentPatientPage({
    super.key,
    required this.department,
    required this.searchQuery,
    required this.onPatientTap,
    required this.onPatientSelect,
    this.roomFilter,
    this.treatmentTypeFilter = 'all',
    this.dateFrom,
    this.dateTo,
    this.selectedPatientId,
  });

  @override
  State<DepartmentPatientPage> createState() => _DepartmentPatientPageState();
}

class _DepartmentPatientPageState extends State<DepartmentPatientPage>
    with AutomaticKeepAliveClientMixin {
  final HisApiService _api = HisApiService();
  final ThongkeAuthService _thongke = ThongkeAuthService();
  final DataService _data = DataService.instance;

  bool _loading = false;  // v2.39.0: manual load, khong auto khi vao page
  bool _loaded = false;   // v2.39.0: da load it nhat 1 lan chua
  bool _apiJustChanged = false;  // v2.98.1: Hiện banner "Vuốt sang trái" khi user chuyển API
  String? _error;
  String? _debugInfo;
  List<Map<String, dynamic>> _patients = [];
  PatientDataSource _dataSource = PatientDataSource.emptyThongke;
  DateTime? _lastSynced;

  // v2.91.0: Chọn nguồn API (user chọn trên AppBar)
  // v3.0.74: Default = Public API (ưu tiên load nhanh khi vào app)
  PatientApiSource _apiSource = PatientApiSource.public;
  String _apiSourceLabel = 'Public';

  // v2.64.0: Tab trạng thái BN (0=Chưa tiếp nhận, 1=Đang điều trị, 2=Đã điều trị)
  int _statusTab = 1;  // Mặc định: Đang điều trị

  // v2.39.0: Filter bar state (giong web EMR-checker)
  String _dateFilterType = 'today';  // today, 7days, 30days, custom
  String _dateField = 'in';          // 'in' (Ngay vao) hoac 'out' (Ngay ra)
  // v3.0.75: Nhận date range từ parent (HomeScreen) - mặc định "hôm nay"
  late DateTime _dateFrom = widget.dateFrom ?? _todayStart();
  late DateTime _dateTo = widget.dateTo ?? _todayEnd();

  static DateTime _todayStart() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }
  static DateTime _todayEnd() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 23, 59, 59);
  }

  /// v3.0.75: Public method - HomeScreen gọi khi user đổi TrDateFilter
  void setDateRange(DateTime from, DateTime to) {
    if (!mounted) return;
    setState(() {
      _dateFrom = from;
      _dateTo = to;
    });
    _load();
  }

  // v2.75.0: ER-specific (Khoa Cap Cuu + Phu san) - department_id mapping
  // HSCC = 22 (Khoa Cap Cuu), KCC_CS2 = 203 (Khoa Cap Cuu Co So 2)
  // CCS = 23 (Phu san cap cuu), NTK = 30 (Noi than kinh)
  // HSCCL = 68 (Khoa Cap Cuu Luu), DTCCLuu = 71, DTCCLUUCS2 = 223
  // Boolean to mark ER department (for ER-optimized defaults)
  static const Set<int> _erDeptIds = {22, 23, 68, 71, 203, 223};
  bool get _isErDept {
    final id = widget.department['id'] as int?;
    return id != null && _erDeptIds.contains(id);
  }

  /// v2.44.0: Toggle giua Khoa Cap Cuu (HSCC=22) va Co So 2 (KCC_CS2=203)
  void _toggleErFacility() {
    final curId = widget.department['id'] as int?;
    int newId;
    if (curId == 22 || curId == 71) {
      newId = 203;  // CS2
    } else if (curId == 203 || curId == 223) {
      newId = 22;  // Main
    } else {
      return;
    }
    // Navigate to the other facility
    final otherDept = (DepartmentService.instance.departments.isNotEmpty
            ? DepartmentService.instance.departments
            : AppConstants.departments)
        .firstWhere(
      (d) => d['id'] == newId,
      orElse: () => widget.department,
    );
    if (otherDept['id'] == widget.department['id']) return;
    HapticFeedback.mediumImpact();
    // Recreate this widget with new department
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DepartmentPatientPage(
          key: ValueKey('dept-$newId'),
          department: Map<String, dynamic>.from(otherDept),
          searchQuery: widget.searchQuery,
          selectedPatientId: null,
          onPatientTap: widget.onPatientTap,
          onPatientSelect: widget.onPatientSelect,
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // v2.91.0: Load _apiSource preference (mặc định API 2 nếu chưa set)
    _loadApiSourcePreference();
    // v3.0.76: BỎ PatientSeed ở frame đầu - hiển thị empty state
    // Hiện loading spinner + banner "đang tải BN thật từ API"
    setState(() {
      _patients = [];
      _dataSource = PatientDataSource.emptyThongke;
      _loaded = false;
      _loading = true;
      _debugInfo = '⏳ Đang tải BN từ API...';
    });
    debugPrint('===== _DepartmentPatientPage initState: empty start for ${widget.department['code']}');
    // Sau đó gọi _load() để lấy BN thật từ API
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // v2.91.0: Load + save _apiSource preference
  // v3.0.77: Default = Public API (khi chưa set lần nào)
  // - Public nhanh, không cần auth, dùng được khi chưa có VPN
  // - User vẫn có thể chuyển sang HIS Pro qua menu API
  void _loadApiSourcePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt('patient_api_source') ?? PatientApiSource.public.index;
      if (idx >= 0 && idx < PatientApiSource.values.length) {
        _apiSource = PatientApiSource.values[idx];
        _apiSourceLabel = _apiSourceLabelFor(_apiSource);
      }
    } catch (_) {}
  }

  void _setApiSource(PatientApiSource src) async {
    setState(() {
      _apiSource = src;
      _apiSourceLabel = _apiSourceLabelFor(src);
      _apiJustChanged = true;  // v2.98.1: Hiện banner nhắc mở full list
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('patient_api_source', src.index);
    } catch (_) {}
    // Reload data với API mới
    _load();
  }

  String _apiSourceLabelFor(PatientApiSource src) {
    switch (src) {
      case PatientApiSource.dataRoom: return 'API 2 (Data 3000 - buồng)';
      case PatientApiSource.dataDept: return 'API Data (khoa)';
      case PatientApiSource.hisPro: return 'API 1 (HIS Pro 1408)';
      case PatientApiSource.public: return 'API Public (8080)';
    }
  }

  /// v2.93.0: Sort BN theo in_time desc (mới nhập viện gần nhất lên đầu)
  /// Hỗ trợ format: "dd/MM/yyyy HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"
  static List<Map<String, dynamic>> _sortPatientsByInTime(List<Map<String, dynamic>> list) {
    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final aTime = _parseInTime(a['IN_TIME'] ?? a['in_time'] ?? a['IN_TIME_VS']);
      final bTime = _parseInTime(b['IN_TIME'] ?? b['in_time'] ?? b['IN_TIME_VS']);
      // Null = xuống cuối
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      // Desc: mới nhất lên đầu
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  /// v2.93.0: Parse IN_TIME từ nhiều format
  static DateTime? _parseInTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null' || s == '-') return null;
    try {
      if (s.contains('/')) {
        // dd/MM/yyyy HH:mm
        final parts = s.split(' ');
        final date = parts[0].split('/');
        final time = parts.length > 1 ? parts[1].split(':') : ['0', '0'];
        if (date.length < 3) return null;
        return DateTime(
          int.parse(date[2]),
          int.parse(date[1]),
          int.parse(date[0]),
          time.length > 0 ? int.parse(time[0]) : 0,
          time.length > 1 ? int.parse(time[1]) : 0,
        );
      } else if (s.contains('-')) {
        return DateTime.tryParse(s);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// v2.91.0: Badge text hiển thị trên banner (gọn)
  String _apiSourceBadge(PatientApiSource src) {
    switch (src) {
      case PatientApiSource.dataRoom: return 'API 2';
      case PatientApiSource.dataDept: return 'Data';
      case PatientApiSource.hisPro: return 'API 1';
      case PatientApiSource.public: return 'Public';
    }
  }

  /// v2.91.0: Màu badge nguồn API
  Color _apiSourceColor(PatientApiSource src) {
    switch (src) {
      case PatientApiSource.dataRoom: return Colors.teal.shade700;
      case PatientApiSource.dataDept: return Colors.green.shade700;
      case PatientApiSource.hisPro: return Colors.indigo.shade700;
      case PatientApiSource.public: return Colors.orange.shade700;
    }
  }

  @override
  void didUpdateWidget(covariant DepartmentPatientPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v2.40.0: Auto-load khi đổi khoa - HSCC/CCS se hien BN ngay khi user chon
    if (oldWidget.department['id'] != widget.department['id']) {
      _load();
    }
    // v3.0.75: Khi parent đổi TrDateFilter → dateFrom/dateTo thay đổi → reload
    final oldFrom = oldWidget.dateFrom;
    final oldTo = oldWidget.dateTo;
    final newFrom = widget.dateFrom;
    final newTo = widget.dateTo;
    if ((oldFrom == null && newFrom != null) ||
        (oldTo == null && newTo != null) ||
        (oldFrom != null && newFrom != null && oldFrom != newFrom) ||
        (oldTo != null && newTo != null && oldTo != newTo)) {
      setDateRange(newFrom ?? _dateFrom, newTo ?? _dateTo);
    }
    // Search query thay doi -> filter LOCAL (khong goi API)
    // (gõ phím search phải filter LOCAL, không gọi API → tránh crash + chậm)
  }

  /// v2.36.1: API /v1/patient/buong-benh chỉ trả buồng nội trú (DT_xxx).
  /// Phòng khám ngoại trú (PKxxx) KHÔNG có → phải hardcode BED_ROOM_IDs cho từng khoa.
  /// Source: ảnh BS gửi 2026-07-07 "giao diện cấp cứu.jpg" (HIS Pro PKCC có nhiều BN).
  /// Lưu ý: đây là BED_ROOM_IDs (ID field trong response), không phải ROOM_ID.
  /// v2.38.5: BED_ROOM_IDs thật cho từng khoa (Data API trả BN theo BED_ROOM_ID)
  /// Test 2026-07-08 với Data API (113.163.187.3:3000) scan IDs 1-5000:
  /// - Data API **KHÔNG có BN PK cấp cứu (HSCC, CCS)** — chỉ nội trú + PK các khoa khác
  /// - ID 39 trong Data API = NTK (NOT HSCC như HIS Pro log ban đầu)
  /// - HSCC chỉ có 1 buồng DT_CC (BED_ROOM_ID=28) — nội trú, thường 0 BN
  /// - PK cấp cứu HSCC/CCS CHỈ CÓ qua HIS Pro LAN (qua OpenVPN BV, port 1429)
  /// Nguồn: HIS Pro logs (D:\Soft\HISPRO_THAT\Logs\LogSystem.txt) + test Data API
  List<int> _getExtraBedRoomIds(int? deptId) {
    if (deptId == null) return [];
    // v2.38.5: BỎ tất cả hardcode [375, 376, 39] - test thực tế Data API KHÔNG có HSCC PK
    // HSCC/CCS PK cấp cứu → user phải bật VPN + bấm "ĐB HIS" thủ công
    return const [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _debugInfo = null;
    });

    // v2.38.3: try/catch toàn bộ _load() tránh crash app nếu HIS Pro/Data exception
    try {
      await _loadImpl();
    } catch (e, st) {
      debugPrint('_load crash: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Lỗi tải BN: ${e.toString().split("\n").first}';
        _debugInfo = 'Có lỗi xảy ra. Kéo xuống để thử lại.';
      });
    }
  }

  Future<void> _loadImpl() async {
    debugPrint('===== _loadImpl START: deptCode=${widget.department['code']} deptId=${widget.department['id']} isAuth=${_data.isAuthenticated} =====');
    try {
      final deptCode = widget.department['code'] as String?;
      final deptId = widget.department['id'] as int?;

      // v2.54.0: PHÒNG KHÁM CẤP CỨU (HSCC=22, CCS=23, DTCCLuu=71, KCC_CS2=203, DTCCLUUCS2=223)
      // Data path 8080 CÓ BN thật qua department_catalog param (verified 215 BN HSCC 2026-07-09).
      // DataService (port 3000) KHÔNG có BN PK cấp cứu → skip thẳng xuống line 1241 fetchPatientsPublic.
      final isPKCapCuu = deptId != null &&
          _erDeptIds.contains(deptId);

      // v3.0.74: Ưu tiên Public API khi vào app (không cần auth)
      // - Nếu chưa auth → thử Public API trước, fallback PatientSeed nếu fail
      // - Nếu đã auth → thử DataService (theo _apiSource), fallback Public/HIS Pro
      if (!_data.isAuthenticated) {
        // v3.0.74: Thử Public API trước (không cần Data auth)
        try {
          const Duration apiTimeout = Duration(seconds: 5);
          final pubList = await _thongke.fetchPatientsPublic(
            departmentCatalogId: deptId,
            from: _dateFrom,
            to: _dateTo,
            filterType: _dateField,
            length: 500,
          ).timeout(apiTimeout, onTimeout: () => null);

          if (!mounted) return;
          if (pubList != null && pubList.isNotEmpty) {
            setState(() {
              _patients = _sortPatientsByInTime(pubList);
              _dataSource = PatientDataSource.thongke;
              _loading = false;
              _loaded = true;
              _lastSynced = DateTime.now();
              _autoLoadIcd();
              _debugInfo = '☁ API Public (113.163.187.3:8080) khoa=$deptCode → ${pubList.length} BN';
            });
            return;
          }
        } catch (e) {
          debugPrint('fetchPatientsPublic failed/timeout (not auth): $e → fallback PatientSeed');
        }
        // v3.0.76: Public fail → hiển thị empty state (KHÔNG dùng PatientSeed nữa)
        debugPrint('===== _loadImpl: not auth + public fail → empty state for $deptCode');
        if (!mounted) return;
        setState(() {
          _patients = [];
          _dataSource = PatientDataSource.emptyThongke;
          _loading = false;
          _loaded = true;
          _lastSynced = null;
          _error = '⚠️ Không tải được BN từ Public API. Bật VPN Bệnh viện hoặc kiểm tra kết nối mạng.';
          _debugInfo = '☁ Public API không khả dụng → nhấn nút 🔄 để thử lại.';
        });
        return;
      }

      // v2.35.10: Gọi API Data TRƯỚC (không show seed trước nữa - tránh banner "CHƯA ĐỒNG BỘ" sai)
      // Nếu authenticated → dùng DataService (BN thật theo khoa user chọn)
      // v2.54.0: BỎ DataService cho PK Cấp Cứu (vì nó không có) - thẳng xuống fetchPatientsPublic (8080)
      // v2.91.0: Honor _apiSource user chọn - skip các API khác nếu không phù hợp
      // v3.0.63: Wrap mỗi API call với timeout 5s + auto-fallback về HIS Pro primary
      const Duration apiTimeout = Duration(seconds: 5);
      if (_data.isAuthenticated && deptId != null && !isPKCapCuu &&
          (_apiSource == PatientApiSource.dataRoom || _apiSource == PatientApiSource.dataDept)) {
        try {
          // 1. Lấy buồng bệnh theo khoa đang chọn (timeout 5s)
          final rooms = await _data.getRoomsByDepartment(deptId.toString())
              .timeout(apiTimeout, onTimeout: () => <DataRoom>[]);
          // 2. Lấy danh sách BED_ROOM_ID từ rooms API
          // v2.35.13: BED_ROOM_IDs = r.id (ID field = 28), KHÔNG phải r.roomId (224)
          List<int> bedRoomIds = rooms.map((r) => r.id).toList();

          // v2.36.1: Thêm các buồng PK ngoại trú hardcoded (API không trả về)
          final extraRoomIds = _getExtraBedRoomIds(deptId);
          if (extraRoomIds.isNotEmpty) {
            bedRoomIds = [...bedRoomIds, ...extraRoomIds];
          }

          if (bedRoomIds.isNotEmpty && _apiSource == PatientApiSource.dataRoom) {
            // v2.91.0: API 2 - getPatientsInRooms (ưu tiên) với timeout 5s
            try {
              final patients = await _data.getPatientsInRooms(bedRoomIds)
                  .timeout(apiTimeout, onTimeout: () => <DataPatient>[]);
              if (patients.isNotEmpty) {
                if (!mounted) return;
                setState(() {
                  _patients = _sortPatientsByInTime(patients.map((p) => _dataPatientToMap(p)).toList());
                  _dataSource = PatientDataSource.thongke;
                  _loading = false;
                  _loaded = true;
                  _lastSynced = DateTime.now();
                  _debugInfo = '☁ API 2 (Data 3000 - buồng bệnh) khoa=$deptCode → ${patients.length} BN';
                });
                _autoLoadIcd();
                return;
              }
            } catch (e) {
              debugPrint('getPatientsInRooms failed/timeout: $e → fallback');
            }
          }
          // v2.91.0: API fallback - getPatientsByDepartment (toàn khoa) với timeout 5s
          if (_apiSource == PatientApiSource.dataRoom || _apiSource == PatientApiSource.dataDept) {
            try {
              final deptPatients = await _data.getPatientsByDepartment(deptId)
                  .timeout(apiTimeout, onTimeout: () => <DataPatient>[]);
              if (deptPatients.isNotEmpty) {
                if (!mounted) return;
                setState(() {
                  _patients = _sortPatientsByInTime(deptPatients.map((p) => _dataPatientToMap(p)).toList());
                  _dataSource = PatientDataSource.thongke;
                  _loading = false;
                  _loaded = true;
                  _lastSynced = DateTime.now();
                  _debugInfo = '☁ API Data (toàn khoa) khoa=$deptCode → ${deptPatients.length} BN';
                });
                return;
              }
            } catch (e) {
              debugPrint('getPatientsByDepartment failed/timeout: $e → fallback');
            }
          }
          // v3.0.76: BỎ fallback PatientSeed khi Data không trả BN → empty state
          if (!mounted) return;
          debugPrint('===== _loadImpl: data-empty → empty state for $deptCode');
          setState(() {
            _patients = [];
            _dataSource = PatientDataSource.emptyThongke;
            _loading = false;
            _loaded = true;
            _error = '⚠️ Khoa $deptCode: Data API không trả về BN. Bật VPN hoặc chọn khoa khác.';
            _debugInfo = '☁ Data 3000 trống → nhấn 🔄 để thử lại.';
          });
          return;
        } catch (e) {
          debugPrint('Data service error: $e');
          // v3.0.76: Lỗi Data → empty state (KHÔNG dùng PatientSeed)
          if (!mounted) return;
          setState(() {
            _patients = [];
            _dataSource = PatientDataSource.emptyThongke;
            _loading = false;
            _loaded = true;
            _error = '⚠️ Data API lỗi: ${e.toString().split("\n").first}. Bật VPN hoặc thử lại.';
            _debugInfo = '☁ Data lỗi → nhấn 🔄 để thử lại.';
          });
          return;
        }
      }

      // 3. v2.40.0: Thử Data PUBLIC API (113.163.187.3:8080) - HSCC/CCS filter WORKING
      // v3.0.63: Wrap timeout 5s + auto-fallback về HIS Pro
      if (_apiSource == PatientApiSource.public || _apiSource == PatientApiSource.hisPro) {
        try {
          final pubList = await _thongke.fetchPatientsPublic(
            departmentCatalogId: deptId,  // 22=HSCC, 23=CCS, 30=NTK, ...
            from: _dateFrom,
            to: _dateTo,
            filterType: _dateField,       // 'date_in' / 'date_out' / etc
            length: 500,
          ).timeout(apiTimeout, onTimeout: () => null);

          if (!mounted) return;
          if (pubList != null && pubList.isNotEmpty) {
            setState(() {
              _patients = _sortPatientsByInTime(pubList);
              _dataSource = PatientDataSource.thongke;
              _loading = false;
              _loaded = true;
              _lastSynced = DateTime.now();
              _autoLoadIcd();
              _debugInfo = '☁ API Public (113.163.187.3:8080) khoa=$deptCode → ${pubList.length} BN';
            });
            return;
          }
        } catch (e) {
          debugPrint('fetchPatientsPublic failed/timeout: $e → fallback HIS Pro');
        }
      }

      // 4. Fallback: Thongke HIS Pro VPN (chỉ work khi có VPN + token)
      // v3.0.63: Wrap timeout 5s + auto-fallback cuối cùng về HIS Pro primary
      if (_apiSource == PatientApiSource.hisPro || _apiSource == PatientApiSource.public) {
        try {
          final apiList = await _thongke.fetchPatients(
            department: deptCode,
            length: 500,
          ).timeout(apiTimeout, onTimeout: () => null);

          if (!mounted) return;
          if (apiList != null && apiList.isNotEmpty) {
            setState(() {
              _patients = _sortPatientsByInTime(apiList);
              _dataSource = PatientDataSource.thongke;
              _loading = false;
              _loaded = true;
              _autoLoadIcd();
              _lastSynced = DateTime.now();
              _debugInfo = '☁ API 1 (HIS Pro 1408 qua VPN) khoa=$deptCode → ${apiList.length} BN';
            });
            return;
          }
        } catch (e) {
          debugPrint('fetchPatients HIS Pro failed/timeout: $e → fallback PatientSeed');
        }
      }

      // 4. v3.0.76: API không trả về BN (offline / VPN fail / khoa trống) → empty state
      // KHÔNG dùng PatientSeed nữa - user thấy thật trạng hệ thống
      debugPrint('===== _loadImpl: end-of-fn → empty state for $deptCode');
      if (!mounted) return;
      setState(() {
        _patients = [];
        _dataSource = PatientDataSource.emptyThongke;
        _loading = false;
        _loaded = true;
        _error = '⚠️ API $_apiSourceLabel không khả dụng. Bật VPN Bệnh viện và thử lại.';
        _debugInfo = '☁ API trống → nhấn 🔄 để thử lại.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Convert DataPatient to Map format expected by widgets
  Map<String, dynamic> _dataPatientToMap(dynamic p) {
    return {
      'ID': p.treatmentId,
      'TDL_PATIENT_UNSIGNED_NAME': p.patientName,
      'TDL_PATIENT_NAME': p.patientName,
      'TDL_PATIENT_CODE': p.patientCode,
      'TDL_TREATMENT_CODE': p.treatmentCode,
      'TDL_PATIENT_GENDER_NAME': p.gender == 1 ? 'Nam' : (p.gender == 2 ? 'Nữ' : ''),
      'TDL_PATIENT_DOB': p.yearOfBirth != null ? '${p.yearOfBirth}00000000' : null,
      'ICD_CODE': p.icdCode,
      'ICD_NAME': p.icdName,
      'P': p.bedCode,
      'BED_NAME': p.bedName,
      'HEIN_CARD_NUMBER': p.heinCardNumber,
      'DEPARTMENT_CODE': p.departmentCode,
      'MABUONGBENH': p.roomCode,
      'MoiNhapVien': p.isNewAdmit ? 'Mới nhập viện' : '',
      'That': p.isReal ? 'Thật' : '',
    };
  }

  /// Public method để _HomeScreenState gọi khi HIS Pro sync xong
  void _updateFromHisPro(List<Map<String, dynamic>> patients, String deptName) {
    setState(() {
      _patients = patients;
      _dataSource = PatientDataSource.hisProLive;
      _lastSynced = DateTime.now();
      _debugInfo = '📡 HIS Pro khoa=$deptName → ${patients.length} BN | Token OK';
    });
    _autoLoadIcd();
  }

  /// v2.48.0: Tự động tải ICD/mặt bệnh cho tất cả BN đang hiện
  /// Gọi HIS Pro port 1408 với Bearer token đã lưu
  /// Update UI ngay khi ICD về - không block UI
  void _autoLoadIcd() {
    if (!mounted) return;
    final thongke = ThongkeAuthService.instance;
    if (!thongke.hasHisProToken) return;
    final codes = _patients
        .map((p) => (p['treatment_code'] ?? p['TDL_TREATMENT_CODE'] ?? '').toString())
        .where((c) => c.isNotEmpty)
        .toList();
    if (codes.isEmpty) return;
    debugPrint('🔄 Auto-loading ICD cho ${codes.length} BN...');
    unawaited(thongke.batchFetchIcd(codes).then((icdMap) {
      if (icdMap.isEmpty || !mounted) return;
      setState(() {
        for (var p in _patients) {
          final code = (p['treatment_code'] ?? p['TDL_TREATMENT_CODE'] ?? '').toString();
          if (icdMap.containsKey(code)) {
            final icd = icdMap[code]!;
            p['icd_code'] = icd['icd_code'] ?? '';
            p['icd_name'] = icd['icd_name'] ?? '';
            p['icd_text'] = icd['icd_text'] ?? '';
            p['icd_sub_codes'] = icd['icd_sub_codes'] ?? '';
          }
        }
      });
      debugPrint('✅ Loaded ICD cho ${icdMap.length}/${codes.length} BN');
    }));
  }

  /// v2.64.0: Lọc BN theo trạng thái
  /// v2.75.8: Filter BN theo trạng thái - logic an toàn
  /// 0 = Chưa tiếp nhận (BN không có bất kỳ field status nào)
  /// 1 = Đang điều trị (BN có is_pause='0' HOẶC có sttId HOẶC có out_time trong 24h)
  /// 2 = Đã điều trị (BN có out_time > 24h trước)
  List<Map<String, dynamic>> _filterByStatus(List<Map<String, dynamic>> list, int status) {
    final now = DateTime.now();
    return list.where((p) {
      final outTime = (p['out_time']?.toString() ?? '').trim();
      final sttId = p['service_req_stt_id'] ?? p['SERVICE_REQ_STT_ID'];
      final isPause = (p['is_pause']?.toString() ?? '').trim();

      // Parse out_time
      DateTime? outDt;
      if (outTime.isNotEmpty && outTime != '-' && outTime != 'null') {
        try {
          if (outTime.contains('/')) {
            final parts = outTime.split(' ');
            final date = parts[0].split('/');
            final time = parts.length > 1 ? parts[1].split(':') : ['0','0'];
            outDt = DateTime(
              int.parse(date[2]), int.parse(date[1]), int.parse(date[0]),
              int.parse(time[0]), int.parse(time[1]),
            );
          } else {
            outDt = DateTime.tryParse(outTime);
          }
        } catch (_) { outDt = null; }
      }

      final hasOutTime = outDt != null;
      final recentlyDischarged = hasOutTime
          ? now.difference(outDt!) < const Duration(hours: 24)
          : false;

      switch (status) {
        case 0: // Chưa tiếp nhận - BN không có bất kỳ field nào
          return !hasOutTime && isPause.isEmpty && sttId == null;
        case 1: // Đang điều trị
          if (hasOutTime && recentlyDischarged) return true; // ra viện trong 24h
          if (hasOutTime) return false; // ra viện > 24h → tab 2
          // Có is_pause HOẶC sttId → đang active
          final keep = isPause.isNotEmpty || sttId != null;
          debugPrint('===== _filterByStatus: outTime=$outTime isPause=$isPause sttId=$sttId → $keep');
          return keep;
        case 2: // Đã điều trị
          return hasOutTime && !recentlyDischarged;
        default:
          return true;
      }
    }).toList();
  }

  List<Map<String, dynamic>> _filterPatients() {
    var list = _patients;
    // v2.80.0: BỎ _filterByStatus - luôn hiển thị tất cả BN
    // (filter theo status phức tạp, dễ filter nhầm → BS mất BN)
    // Chỉ filter theo phòng + search + TREATMENT_TYPE_NAME
    if (widget.roomFilter != null && widget.roomFilter!.isNotEmpty) {
      list = list.where((p) {
        final room = (p['EXECUTE_ROOM_NAME'] ?? p['BED_ROOM_NAME'] ?? '').toString();
        return room == widget.roomFilter;
      }).toList();
    }
    // v3.0.57: Filter TREATMENT_TYPE_NAME (Hình thức ĐT) - dynamic từ data HIS Pro
    // - Trước đó dùng 'chuakham'/'dangkham' (trạng thái khám) - sai theo BS yêu cầu
    // - Fix: so sánh trực tiếp field TREATMENT_TYPE_NAME
    if (widget.treatmentTypeFilter != 'all') {
      list = list.where((p) {
        final ttn = (p['TREATMENT_TYPE_NAME'] ?? p['treatment_type_name'] ?? '').toString().trim();
        return ttn == widget.treatmentTypeFilter;
      }).toList();
    }
    // v2.98.2: Search filter LOCAL - giống DepartmentPatientsScreen (đơn giản + hiệu quả)
    // Tìm trên tên, mã BN, mã ĐT (toLowerCase contains)
    if (widget.searchQuery.isEmpty) return list;
    final q = widget.searchQuery.trim().toLowerCase();
    return list.where((p) {
      final name = (p['TDL_PATIENT_NAME'] ?? p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_name'] ?? '').toString().toLowerCase();
      final code = (p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? '').toString().toLowerCase();
      final reqCode = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || reqCode.contains(q);
    }).toList();
  }

  /// v2.68.0: Lọc BN theo 3 tab trạng thái (giống app v0.3.5 team BS)
  /// 0 = Chưa tiếp nhận (chưa có y lệnh khám)
  /// 1 = Đang điều trị (out_time null HOẶC out_time trong 24h)
  /// 2 = Đã điều trị (is_pause=1 + out_time > 24h trước)




  /// v2.44.0: Hiển thị thống kê BN BHYT / Viện phí cho khoa cấp cứu
  Widget _buildErPatientTypeStats() {
    if (_patients.isEmpty) return const SizedBox.shrink();
    int bhyt = 0, vp = 0;
    for (final p in _patients) {
      final t = (p['PATIENT_TYPE_NAME'] ?? '').toString();
      if (t.contains('BHYT')) bhyt++;
      else if (t.contains('Viện Phí') || t.contains('Yêu Cầu')) vp++;
    }
    final other = _patients.length - bhyt - vp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_hospital, size: 12, color: Colors.orange),
          const SizedBox(width: 4),
          const Text('Phân loại:', style: TextStyle(fontSize: 10, color: Colors.black54)),
          const SizedBox(width: 6),
          _countChip('BHYT', bhyt, Colors.green),
          const SizedBox(width: 4),
          _countChip('Viện phí', vp + other, Colors.orange),
          const Spacer(),
          Text('Tổng: ${_patients.length}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _countChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text('$label: $count',
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }


  String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.blue.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButton<String>(
            value: value,
            items: items,
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox(),
            isDense: true,
            style: const TextStyle(fontSize: 12, color: Colors.black),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
        _dateFilterType = 'custom';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // v2.74.0: Bỏ _buildFilterBar() (filter bar đã ở _HomeScreenState body)
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (!_loaded && !_loading) {
      // v2.40.0: Auto-load khoi phuc nen _loaded se true ngay sau initState
      // Fallback hint chi khi that su chua load
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty, size: 56, color: Colors.indigo.shade300),
              const SizedBox(height: 16),
              Text(
                'Đang tải dữ liệu...',
                style: TextStyle(color: Colors.indigo.shade700, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return Column(
        children: [
          _buildDataSourceBanner(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'Không tải được BN từ khoa',
                style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 11)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
              ),
            ],
          ),
        ),
      );
    }

    final deptId = widget.department['id'];
    if (deptId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.department['icon'] as String, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                widget.department['name'] as String,
                style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('Mã: ${widget.department['code']}',
                  style: const TextStyle(color: Colors.black54, fontSize: 11)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Khoa này chưa cấu hình ID trong app.\n'
                  'Cần lấy DEPARTMENT_ID thật từ HIS Pro\n'
                  'để hiển thị bệnh nhân.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black87, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filterPatients();

    if (filtered.isEmpty) {
      // v3.0.76: Empty state với nút Bật VPN + Thử lại (KHÔNG dùng PatientSeed)
      final showVpnButton = _dataSource == PatientDataSource.emptyThongke && !VpnBenhVienService.instance.isConnected;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                showVpnButton ? Icons.vpn_lock_outlined : Icons.people_outline,
                size: 56,
                color: showVpnButton ? Colors.orange.shade400 : Colors.black26,
              ),
              const SizedBox(height: 12),
              Text(
                widget.searchQuery.isNotEmpty
                    ? 'Không tìm thấy "${widget.searchQuery}"'
                    : (showVpnButton
                        ? 'Không có dữ liệu BN'
                        : 'Chưa có BN trong khoa này'),
                style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (showVpnButton) ...[
                const Text(
                  'Có thể API chưa trả BN vì chưa có VPN Bệnh viện.\n'
                  'Bấm nút bên dưới để bật VPN, hoặc chọn khoa khác.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const VpnBenhVienScreen()),
                        );
                      },
                      icon: const Icon(Icons.vpn_lock, size: 18),
                      label: const Text('Bật VPN Bệnh viện'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Thử lại'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const Text(
                  'Bấm mũi tên ▼ ở trên để chọn khoa khác.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 11),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Thử lại'),
                ),
              ],
              if (_debugInfo != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bug_report, color: Colors.orange, size: 14),
                          SizedBox(width: 4),
                          Text('DEBUG INFO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _debugInfo!,
                        style: const TextStyle(fontSize: 10, color: Colors.black87, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          _buildDataSourceBanner(),
          // v2.98.1: Banner nhắc vuốt sang trái mở full list + search LOCAL
          // - Hiện khi: list < 50 BN (mặc định) HOẶC vừa chuyển API source
          if ((_apiJustChanged || filtered.length < 50) && filtered.isNotEmpty)
            _buildSwipeHintBanner(deptId: widget.department['id'] as int?, deptName: widget.department['name']?.toString() ?? '', deptCode: widget.department['code']?.toString()),
          Expanded(
            child: GestureDetector(
              // v2.40.2: Vuốt sang trái trên toàn list -> mở DepartmentPatientsScreen
              onHorizontalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -300) {
                  _apiJustChanged = false;  // v2.98.1: clear flag khi user swipe
                  _openDepartmentPatientsFullList();
                }
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final p = filtered[i];
                  final isSelected = widget.selectedPatientId != null && widget.selectedPatientId == p['ID'];
                  return PatientCard(
                    patient: p,
                    isSelected: isSelected,
                    onActions: () => widget.onPatientTap(p),
                    onSelectedChanged: (sel) {
                      if (sel) {
                      widget.onPatientSelect(p);
                    } else if (widget.selectedPatientId == p['ID']) {
                      widget.onPatientSelect(null);
                    }
                  },
                );
              },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// v2.40.2: Banner nhắc vuốt sang trái + nút mở DepartmentPatientsScreen
  Widget _buildSwipeHintBanner({int? deptId, required String deptName, String? deptCode}) {
    if (deptId == null || deptId <= 0) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF3E0),
      child: InkWell(
        onTap: _openDepartmentPatientsFullList,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              const Icon(Icons.swipe_left, size: 14, color: Color(0xFFE65100)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Vuốt sang trái HOẶC bấm vào đây → mở danh sách BN đầy đủ + search',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.w500),
                ),
              ),
              const Icon(Icons.arrow_forward, size: 14, color: Color(0xFFE65100)),
            ],
          ),
        ),
      ),
    );
  }

  /// v2.40.2: Mở DepartmentPatientsScreen (full BN + smart search)
  void _openDepartmentPatientsFullList() {
    final deptId = widget.department['id'] as int?;
    final deptName = widget.department['name']?.toString() ?? '';
    final deptCode = widget.department['code']?.toString();
    if (deptId == null || deptId <= 0) return;
    HapticFeedback.mediumImpact();
    _apiJustChanged = false;  // v2.98.1: clear flag khi user mở full list
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DepartmentPatientsScreen(
          departmentId: deptId,
          departmentName: deptName,
          departmentCode: deptCode,
        ),
      ),
    );
  }

  /// v2.77.0: BỎ hoàn toàn banner cam - LUÔN dùng PatientSeed
  /// Giữ method stub để không lỗi compile, nhưng không ai gọi nữa
  Widget _buildPKCapCuuEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text('Không có BN', style: TextStyle(color: Colors.black54, fontSize: 14)),
      ),
    );
  }

  Widget _buildDataSourceBanner() {
    switch (_dataSource) {
      case PatientDataSource.hisProLive:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFFFF3E0), Color(0xFFFFCC80)]),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: const Color(0xFFE65100), borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.cloud_sync, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '📡 ${_patients.length} BN THẬT từ HIS Pro',
                      style: const TextStyle(color: Color(0xFFE65100), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (_lastSynced != null)
                      Text(
                        'Đồng bộ lúc ${_formatTime(_lastSynced!)} - cần bật VPN để đồng bộ',
                        style: const TextStyle(color: Colors.black54, fontSize: 9),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      case PatientDataSource.appCode:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)]),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.indigo.shade700, borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.code, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '📋 ${_patients.length} BN TỪ APP CODE (PatientSeed)',
                      style: TextStyle(color: Colors.indigo.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (_lastSynced != null)
                      Text(
                        'Đồng bộ lúc ${_formatTime(_lastSynced!)} - không cần internet để dùng',
                        style: const TextStyle(color: Colors.black54, fontSize: 9),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 18, color: Colors.indigo.shade700),
                onPressed: _load,
                tooltip: 'Tải lại',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        );
      case PatientDataSource.thongke:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)]),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.cloud_done, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '✅ ${_patients.length} BN THẬT',
                            style: TextStyle(color: Colors.green.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // v2.91.0: Badge nguồn API
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _apiSourceColor(_apiSource),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _apiSourceBadge(_apiSource),
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (_lastSynced != null)
                      Text(
                        'Đồng bộ lúc ${_formatTime(_lastSynced!)} - kéo xuống để cập nhật',
                        style: const TextStyle(color: Colors.black54, fontSize: 9),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 18, color: Colors.green.shade700),
                onPressed: _load,
                tooltip: 'Đồng bộ lại',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              // v2.91.0: Chọn nguồn API
              // v3.0.60: Phân quyền - chỉ user `nemk` mới thấy 4 options
              // User khác chỉ thấy hisPro + public
              PopupMenuButton<PatientApiSource>(
                icon: Icon(Icons.api, size: 18, color: Colors.green.shade700),
                tooltip: 'Chọn nguồn API lấy BN',
                onSelected: _setApiSource,
                itemBuilder: (ctx) => _visiblePatientApiSources().map((src) {
                  final isSel = _apiSource == src;
                  return PopupMenuItem<PatientApiSource>(
                    value: src,
                    child: Row(
                      children: [
                        Icon(isSel ? Icons.check_circle : Icons.cloud_outlined,
                          size: 14, color: isSel ? Colors.green : Colors.black54),
                        const SizedBox(width: 6),
                        Text(_apiSourceLabelFor(src),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            color: isSel ? Colors.green.shade700 : Colors.black,
                          )),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      case PatientDataSource.emptyThongke:
        return Container(
          color: const Color(0xFFFFF8E1),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Khoa không có BN trong khoảng thời gian đã chọn. Bấm "Thử lại" hoặc đổi khoa/ngày.',
                  style: const TextStyle(color: Colors.black87, fontSize: 11),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: Colors.black54),
                onPressed: _load,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tooltip: 'Tải lại',
              ),
            ],
          ),
        );
      case PatientDataSource.seed:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFFFF3E0), Color(0xFFFFF8E1)]),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.warning_amber, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '⚠️ CHƯA ĐỒNG BỘ — đang dùng ${_patients.length} BN mẫu',
                      style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _thongke.currentUsername != null
                          ? 'Phiên hết hạn, bấm [Đồng bộ] →'
                          : 'Vui lòng đăng nhập để xem BN thật',
                      style: const TextStyle(color: Colors.black87, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: _syncOrLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(_thongke.currentUsername != null ? Icons.refresh : Icons.login, size: 14),
                label: Text(
                  _thongke.currentUsername != null ? 'Đồng bộ' : 'Đăng nhập',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
    }
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}';
  }

  Future<void> _syncOrLogin() async {
    if (_thongke.currentUsername == null) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
      return;
    }
    await _thongke.initPersistence();
    setState(() => _loading = true);
    await _load();
  }
}


/// v3.0.74: Indicator trạng thái VPN Bệnh viện ở AppBar
class _VpnStatusIndicator extends StatefulWidget {
  @override
  State<_VpnStatusIndicator> createState() => _VpnStatusIndicatorState();
}

class _VpnStatusIndicatorState extends State<_VpnStatusIndicator> {
  @override
  void initState() {
    super.initState();
    VpnBenhVienService.instance.init();
    VpnBenhVienService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    VpnBenhVienService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vpn = VpnBenhVienService.instance;
    final isConnected = vpn.isConnected;
    final isConnecting = vpn.isConnecting;
    Color color = Colors.white60;
    IconData icon = Icons.vpn_lock;
    String tooltip = 'VPN BV: Chưa kết nối';
    if (isConnected) {
      color = Colors.greenAccent;
      icon = Icons.verified;
      tooltip = 'VPN BV: Đã kết nối';
    } else if (isConnecting) {
      color = Colors.orangeAccent;
      icon = Icons.sync;
      tooltip = 'VPN BV: Đang kết nối...';
    }
    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VpnBenhVienScreen()),
        );
      },
    );
  }
}
