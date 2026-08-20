// DepartmentPatientsScreen v2.98.0
// - Sửa mojibake: "ngĂ y" → "ngày", "phĂ²ng" → "phòng", "rá»™ng" → "rộng"
// - ĐỔI Autocomplete → TextField filter LOCAL (như workspace cũ) - đơn giản hơn
// - Tự cập nhật tên khoa + chips Hôm nay/7/30/90 ngày khi load
// v2.40.2: Xem BN của 1 khoa với TYPE-AHEAD SEARCH
// v2.96.0: Thêm API selector (←/→)
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:his_mobile/presentation/widgets/patient_actions_sheet.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/core/services/his_config_service.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:go_router/go_router.dart';

// v2.96.0: Enum API source (đồng bộ với Home screen)
enum DeptPatientApiSource {
  public,    // Data public 8080 (mặc định)
  dataRoom,  // Data 3000 buồng
  dataDept,  // Data 3000 toàn khoa (v3.0.60: thêm)
  hisPro,    // HIS Pro 1408
}

/// v3.0.60: Phân quyền hiển thị API source
/// - User `nemk` (admin) → thấy 4 options: dataRoom + dataDept + hisPro + public
/// - User khác → chỉ thấy 2 options: hisPro + public
List<DeptPatientApiSource> _visibleDeptPatientApiSources() {
  final username = _getCurrentUsernameStatic();
  if (username.toLowerCase().trim() == 'nemk') {
    return DeptPatientApiSource.values.toList();
  }
  return [DeptPatientApiSource.hisPro, DeptPatientApiSource.public];
}

/// Helper static - lấy username hiện tại
String _getCurrentUsernameStatic() {
  try {
    return ThongkeAuthService().currentUsername ?? '';
  } catch (_) {
    return '';
  }
}

class DepartmentPatientsScreen extends StatefulWidget {
  final int departmentId;        // e.g., 22 = HSCC
  final String departmentName;    // e.g., "Khoa Cấp Cứu"
  final String? departmentCode;   // e.g., "HSCC"

  const DepartmentPatientsScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
    this.departmentCode,
  });

  @override
  State<DepartmentPatientsScreen> createState() => _DepartmentPatientsScreenState();
}

class _DepartmentPatientsScreenState extends State<DepartmentPatientsScreen> {
  final _searchCtrl = TextEditingController();
  final _thongke = ThongkeAuthService.instance;
  final _data = DataService.instance;
  final _scrollCtrl = ScrollController();

  bool _loading = false;
  bool _loaded = false;
  String? _error;
  List<Map<String, dynamic>> _patients = [];
  String? _selectedRoom; // v2.75.6: filter phòng
  List<Map<String, dynamic>> _suggestions = [];  // type-ahead results
  String _query = '';
  Timer? _debounce;

  // Filter state
  String _dateFilterType = '30days';

  /// v3.0.85: chỉ giữ date filter + search. Bỏ treatment type, type name, room.
  /// Filter giống "Hồ sơ điều trị" (Treatment History) - đơn giản, chỉ theo ngày.
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _dateTo = DateTime.now();
  /// v3.0.86: Bỏ date filter, thay bằng status filter (Tất cả / Đang điều trị / Đã xuất viện)
  String _statusFilter = 'all';
  bool _showSuggestions = false;

  // v2.96.0: API source
  // v2.98.2: Default = API 1 (HIS Pro) theo yêu cầu BS
  DeptPatientApiSource _apiSource = DeptPatientApiSource.hisPro;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    // v2.98.0: Tự refresh tên khoa (nếu DepartmentService đã load) - đảm bảo tên có dấu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});  // Trigger rebuild với departmentName mới nhất
        _load();  // Auto-load BN lần đầu
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text;
    setState(() {
      _query = q;
      _showSuggestions = q.trim().isNotEmpty;
    });
    // Debounce type-ahead: 300ms
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (q.trim().length >= 1) {
        _doTypeAheadSearch(q.trim());
      } else {
        setState(() => _suggestions = []);
      }
    });
  }

  Future<void> _doTypeAheadSearch(String keyword) async {
    try {
      final list = await _thongke.searchPatientsPublic(
        keyword: keyword,
        from: _dateFrom,
        to: _dateTo,
        length: 30,
      );
      // Filter to this dept (fuzzy match by dept name)
      final deptLower = widget.departmentName.toLowerCase();
      final filtered = list.where((p) {
        final d = (p['DEPARTMENT_NAME'] ?? '').toString().toLowerCase();
        return d.contains(deptLower.split(' ').last) ||
            deptLower.contains(d) ||
            d == deptLower ||
            widget.departmentCode == 'HSCC' && d.contains('cấp cứu') && !d.contains('lưu') ||
            widget.departmentCode == 'CCS' && d.contains('phụ sản') ||
            widget.departmentCode == 'NTK' && d.contains('thần kinh');
      }).toList();
      if (!mounted) return;
      setState(() {
        _suggestions = filtered.isEmpty ? list : filtered;
      });
    } catch (e) {
      debugPrint('typeahead error: $e');
    }
  }

  void _selectSuggestion(Map<String, dynamic> p) {
    setState(() {
      _searchCtrl.text = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['tdl_patient_name'] ?? '').toString();
      _showSuggestions = false;
    });
    _doSearch();
  }

  Future<void> _doSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      _load();
      return;
    }
    setState(() {
      _loading = true;
      _showSuggestions = false;
    });
    try {
      final list = await _thongke.searchPatientsPublic(
        keyword: q,
        from: _dateFrom,
        to: _dateTo,
        length: 100,
      );
      // Filter to this dept
      final deptLower = widget.departmentName.toLowerCase();
      final filtered = list.where((p) {
        final d = (p['DEPARTMENT_NAME'] ?? '').toString().toLowerCase();
        return d.contains(deptLower.split(' ').last) ||
            deptLower.contains(d) ||
            d == deptLower ||
            widget.departmentCode == 'HSCC' && d.contains('cấp cứu') && !d.contains('lưu') ||
            widget.departmentCode == 'CCS' && d.contains('phụ sản');
      }).toList();
      if (!mounted) return;
      setState(() {
        _patients = filtered.isEmpty ? list : filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _showSuggestions = false;
    });
    try {
      List<Map<String, dynamic>>? list;
      // v2.96.0: Chọn API source
      switch (_apiSource) {
        case DeptPatientApiSource.public:
          list = await _thongke.fetchPatientsPublic(
            departmentCatalogId: widget.departmentId,
            from: _dateFrom,
            to: _dateTo,
            filterType: 'date_in',
            length: 500,
          );
          break;
        case DeptPatientApiSource.dataRoom:
          // v2.96.0: Data 3000 - getPatientsInRooms (cần BED_ROOM_IDs)
          // Lấy buồng theo khoa trước
          final rooms = await _data.getRoomsByDepartment(widget.departmentId.toString());
          final bedRoomIds = rooms.map((r) => r.id).toList();
          if (bedRoomIds.isNotEmpty) {
            final ps = await _data.getPatientsInRooms(bedRoomIds);
            list = ps.map((p) => _dataPatientToMap(p)).toList();
          } else {
            list = [];
          }
          break;
        case DeptPatientApiSource.hisPro:
          // v2.96.0: HIS Pro 1408
          final apiList = await _thongke.fetchPatients(
            department: widget.departmentCode,
            length: 500,
          );
          list = apiList;
          break;
        case DeptPatientApiSource.dataDept:
          // v3.0.60: Data 3000 - getPatientsByDepartment
          final ps = await _data.getPatientsByDepartment(widget.departmentId);
          list = ps.map((p) => _dataPatientToMap(p)).toList();
          break;
      }
      if (!mounted) return;
      setState(() {
        _patients = list ?? [];
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loaded = true;
      });
    }
  }

  // v2.96.0: Convert DataPatient to Map
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
      'BED_NAME': p.bedName,
      'HEIN_CARD_NUMBER': p.heinCardNumber,
      'DEPARTMENT_CODE': p.departmentCode,
      'MABUONGBENH': p.roomCode,
    };
  }

  // v2.96.0: Set API source
  void _setApiSource(DeptPatientApiSource src) {
    setState(() => _apiSource = src);
    _load();
  }

  void _onDateFilterChanged(String value) {
    setState(() {
      _dateFilterType = value;
      final today = DateTime.now();
      switch (value) {
        case 'today':
          _dateFrom = today;
          _dateTo = today;
          break;
        case '7days':
          _dateFrom = today.subtract(const Duration(days: 7));
          _dateTo = today;
          break;
        case '30days':
          _dateFrom = today.subtract(const Duration(days: 30));
          _dateTo = today;
          break;
        case '90days':
          _dateFrom = today.subtract(const Duration(days: 90));
          _dateTo = today;
          break;
      }
    });
    _load();
  }

  String _fmtDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        // v2.58.0: Explicit back button với WillPopScope để chắc chắn back work
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Quay lại danh sách khoa',
          onPressed: () {
            if (Navigator.canPop(context)) {
              context.safePop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.departmentName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            Text(
              'ID: ${widget.departmentId}'
              '${widget.departmentCode != null ? ' • ${widget.departmentCode}' : ''}'
              ' • ${_patients.length} BN'
              '${_suggestions.isNotEmpty ? ' • ${_suggestions.length} gợi ý' : ''}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: GestureDetector(
        // v2.40.2: Vuốt sang trái trên body -> refresh (mở rá»™ng search)
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -300 && _showSuggestions) {
            setState(() => _showSuggestions = false);
            FocusScope.of(context).unfocus();
          }
        },
        child: Column(
          children: [
            // v2.96.0: API selector (←/→) - đặt trên cùng
            _buildApiSelector(),
            // v3.0.89: Time filter chips - bỏ Trạng thái filter
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // v3.0.87: Time filter chips (giống Hồ sơ điều trị)
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 13, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 4),
                      const Text('Thời gian:',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _dateChip('today', 'Hôm nay'),
                              const SizedBox(width: 4),
                              _dateChip('7days', '7 ngày'),
                              const SizedBox(width: 4),
                              _dateChip('30days', '30 ngày'),
                              const SizedBox(width: 4),
                              _dateChip('90days', '90 ngày'),
                            ],
                          ),
                        ),
                      ),
                      if (_loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // v2.42.0: BN thật từ Data cell - hiển thị tên khoa + số BN
                  Row(
                    children: [
                      const Icon(Icons.cloud_done, size: 14, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'BN thật từ Data: ${widget.departmentName} (${_patients.length} BN)',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _fmtDate(_dateFrom) + ' → ' + _fmtDate(_dateTo),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // v2.98.0: Search bar - TextField filter LOCAL đơn giản (như workspace cũ)
            // BỎ Autocomplete - filter trực tiếp trên list đã load (không popup gợi ý)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Gõ tên / mã ĐT / mã BN để lọc...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
              ),
            ),
            // v3.0.85: Bỏ filter TREATMENT_TYPE_NAME + room - giống Hồ sơ điều trị
            // (chỉ giữ date filter + search)
            // Suggestions (type-ahead)
            if (_showSuggestions && _suggestions.isNotEmpty)
              Container(
                color: Colors.white,
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: _suggestions.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == _suggestions.length) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() => _showSuggestions = false);
                            _doSearch();
                          },
                          icon: const Icon(Icons.search, size: 16),
                          label: Text('Tìm tất cả "${_query}"'),
                        ),
                      );
                    }
                    return _buildSuggestionTile(_suggestions[i]);
                  },
                ),
              ),
            // Patient list
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionTile(Map<String, dynamic> p) {
    final name = fixVietnameseMojibake(
      (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['tdl_patient_name'] ?? 'BN').toString());
    final code = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString();
    final dob = (p['TDL_PATIENT_DOB'] ?? '').toString();
    final dept = fixVietnameseMojibake((p['DEPARTMENT_NAME'] ?? '').toString());

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0xFF2E7D32),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(
        '$code • $dept',
        style: const TextStyle(fontSize: 11),
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      trailing: dob.isNotEmpty
          ? Text(dob.substring(0, dob.length > 10 ? 10 : dob.length), style: const TextStyle(fontSize: 10, color: Colors.black54))
          : null,
      onTap: () => _selectSuggestion(p),
    );
  }

  Widget _dateChip(String value, String label) {
    final selected = _dateFilterType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _onDateFilterChanged(value),
      selectedColor: const Color(0xFF2E7D32),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 11,
      ),
    );
  }

  /// v3.0.86: Status chip (Tất cả / Đang ĐT / Đã xuất viện)
  Widget _statusChip(String value, String label, IconData icon) {
    final selected = _statusFilter == value;
    return ChoiceChip(
      avatar: Icon(icon,
          size: 14,
          color: selected ? Colors.white : const Color(0xFF1976D2)),
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _statusFilter = value);
      },
      selectedColor: const Color(0xFF1976D2),
      backgroundColor: Colors.grey[100],
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        fontSize: 11,
      ),
    );
  }

  // v2.96.0: API selector với ←/→ - đặt trên cùng
  Widget _buildApiSelector() {
    final currentIdx = DeptPatientApiSource.values.indexOf(_apiSource);
    return Container(
      color: const Color(0xFFE8EAF6),  // nền xanh nhạt indigo
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          const Icon(Icons.cloud_outlined, size: 16, color: Colors.indigo),
          const SizedBox(width: 6),
          const Text('API:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo)),
          // ←
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20, color: Colors.indigo),
            tooltip: 'API trước',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              final prevIdx = (currentIdx - 1) < 0
                  ? DeptPatientApiSource.values.length - 1
                  : currentIdx - 1;
              _setApiSource(DeptPatientApiSource.values[prevIdx]);
            },
          ),
          // Tên API hiện tại
          Expanded(
            child: GestureDetector(
              onTap: () => _showApiMenu(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _apiSourceColor(_apiSource),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    _apiSourceLabel(_apiSource),
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
          // →
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20, color: Colors.indigo),
            tooltip: 'API sau',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              final nextIdx = (currentIdx + 1) >= DeptPatientApiSource.values.length
                  ? 0
                  : currentIdx + 1;
              _setApiSource(DeptPatientApiSource.values[nextIdx]);
            },
          ),
        ],
      ),
    );
  }

  // v2.96.0: Helper - label API ngắn
  static String _apiSourceLabel(DeptPatientApiSource src) {
    switch (src) {
      case DeptPatientApiSource.dataRoom: return '🌐 API 2';
      case DeptPatientApiSource.dataDept: return '🌐 API';  // v3.0.60
      case DeptPatientApiSource.hisPro: return '🏥 API 1';
      case DeptPatientApiSource.public: return '🌍 Public';
    }
  }

  // v2.96.0: Helper - màu API
  static Color _apiSourceColor(DeptPatientApiSource src) {
    switch (src) {
      case DeptPatientApiSource.dataRoom: return Colors.teal.shade700;
      case DeptPatientApiSource.dataDept: return Colors.cyan.shade700;  // v3.0.60
      case DeptPatientApiSource.hisPro: return Colors.indigo.shade700;
      case DeptPatientApiSource.public: return Colors.orange.shade700;
    }
  }

  // v2.96.0: Menu chọn API (khi tap tên API)
  // v3.0.60: Phân quyền - chỉ user `nemk` thấy 4 options
  void _showApiMenu() {
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
            ..._visibleDeptPatientApiSources().map((src) {
              final isSel = _apiSource == src;
              String label;
              String url;
              switch (src) {
                case DeptPatientApiSource.dataRoom:
                  label = 'API 2 - Data 3000 (buồng bệnh)';
                  url = 'POST /v1/patient/benh-nhan-buong-benh';
                  break;
                case DeptPatientApiSource.dataDept:
                  label = 'API - Data 3000 (toàn khoa)';
                  url = 'POST /v1/patient/benh-nhan-khoa';
                  break;
                case DeptPatientApiSource.hisPro:
                  label = 'API 1 - HIS Pro 1408 (qua VPN)';
                  url = 'POST /api/HisTreatment/GetView?param=BASE64';
                  break;
                case DeptPatientApiSource.public:
                  label = 'API Public - 113.163.187.3:8080';
                  url = 'GET /emr/index (Data public)';
                  break;
              }
              return ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _apiSourceColor(src).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.cloud, color: _apiSourceColor(src), size: 20),
                ),
                title: Text(label),
                subtitle: Text(url, style: const TextStyle(fontSize: 10)),
                trailing: isSel ? Icon(Icons.check_circle, color: _apiSourceColor(src)) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _setApiSource(src);
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _patients.isEmpty && _suggestions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _patients.isEmpty && _suggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }
    if (_patients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _query.isEmpty
                    ? 'Khoa không có BN trong khoảng ${_fmtDate(_dateFrom)} → ${_fmtDate(_dateTo)}'
                    : 'Không tìm thấy "$_query"',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              if (_query.isEmpty) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _onDateFilterChanged('90days'),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: const Text('Mở rộng 90 ngày'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // v2.75.6: Filter theo phòng nếu có chọn
        itemCount: _filteredPatients().length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, i) => _buildPatientCard(_filteredPatients()[i]),
      ),
    );
  }

  /// v3.0.86: Filter LOCAL đơn giản - search + status
  /// v3.0.89: Sort ca mới nhất lên đầu (IN_TIME desc)
  List<Map<String, dynamic>> _filteredPatients() {
    var list = _patients;
    // v3.0.86: Status filter (Tất cả / Đang ĐT / Đã xuất viện) - giữ logic nhưng ẩn UI
    if (_statusFilter != 'all') {
      list = list.where((p) {
        final outTime = (p['out_time'] ?? p['OUT_TIME'] ?? '').toString().trim();
        final isOut = outTime.isNotEmpty && outTime != '-' && outTime != 'null';
        if (_statusFilter == 'in') return !isOut;
        if (_statusFilter == 'out') return isOut;
        return true;
      }).toList();
    }
    // v2.98.0: Filter LOCAL theo search query (giống workspace cũ)
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((p) {
        final name = (p['TDL_PATIENT_NAME'] ?? p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_name'] ?? '').toString().toLowerCase();
        final code = (p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? '').toString().toLowerCase();
        final reqCode = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q) || reqCode.contains(q);
      }).toList();
    }
    // v3.0.89: Sort ca mới nhất lên đầu (IN_TIME desc)
    list = List<Map<String, dynamic>>.from(list);
    list.sort((a, b) {
      final aIn = (a['IN_TIME'] ?? a['in_time'] ?? '').toString();
      final bIn = (b['IN_TIME'] ?? b['in_time'] ?? '').toString();
      return bIn.compareTo(aIn); // desc: larger (newer) first
    });
    return list;
  }

  /// v3.0.85: Bỏ các filter cũ (_buildTreatmentTypeChips, _buildRoomChips, ...)
  /// Chỉ giữ date filter + search (giống Hồ sơ điều trị)
  Widget _buildPatientCard(Map<String, dynamic> p) {
    final name = fixVietnameseMojibake(
      (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['tdl_patient_name'] ?? 'BN').toString());
    final code = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString();
    final patientCode = (p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? '').toString();
    final dob = (p['TDL_PATIENT_DOB'] ?? '').toString();
    final phone = (p['TDL_PATIENT_PHONE'] ?? p['phone'] ?? '').toString();
    final type = (p['TREATMENT_TYPE_NAME'] ?? '').toString();
    final ptType = (p['PATIENT_TYPE_NAME'] ?? '').toString();
    final isBHYT = ptType.contains('BHYT');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        // v2.64.0: 1 tap = mở thao tác (giống app Y tế số)
        onTap: () {
          HapticFeedback.lightImpact();
          _openPatientActions(p);
        },
        onLongPress: () {
          // Long-press → mở chi tiết (data dump) để debug/xem raw data
          HapticFeedback.mediumImpact();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            useSafeArea: true,
            barrierColor: Colors.black.withOpacity(0.25),
            clipBehavior: Clip.antiAlias,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
            builder: (ctx) => _buildDetailSheet(p),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (type.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(type, style: TextStyle(color: Colors.blue.shade800, fontSize: 10)),
                    ),
                  if (isBHYT) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('BHYT', style: TextStyle(color: Colors.green.shade800, fontSize: 10)),
                    ),
                  ],
                  // v2.42.0: Icon thao tac nhanh
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _openPatientActions(p),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Bấm 1 lần → Thao tác • Giữ để xem chi tiết',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  if (code.isNotEmpty)
                    Text('Mã ĐT: $code',
                        style: const TextStyle(fontSize: 11, color: Colors.black87)),
                  if (patientCode.isNotEmpty)
                    Text('Mã BN: $patientCode',
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  if (dob.isNotEmpty)
                    Text('NS: $dob',
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  if (phone.isNotEmpty)
                    Text('SĐT: $phone',
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// v2.42.0 + v2.56.0: Mở PatientActionsSheet cho 1 BN - dùng showModalBottomSheet thay MaterialPage
  /// (tránh mĂ n hình xám, fix dark barrier)
  void _openPatientActions(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withOpacity(0.25),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PatientActionsSheet(
        patient: p,
        department: {
          'id': widget.departmentId,
          'code': widget.departmentCode ?? '',
          'name': widget.departmentName,
        },
      ),
    );
  }

  Widget _buildDetailSheet(Map<String, dynamic> p) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Text('Chi tiết BN',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                children: p.entries.map((e) {
                  final v = e.value?.toString() ?? 'null';
                  final vFixed = fixVietnameseMojibake(v);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        SelectableText(
                          vFixed,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
