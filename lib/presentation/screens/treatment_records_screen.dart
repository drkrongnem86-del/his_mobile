// treatment_records_screen.dart v3.0.64
// Hồ sơ điều trị - Xem danh sách BN theo khoa (multi-dept) với bộ lọc ngày
// v3.0.64: Tạo mới - theo yêu cầu BS Nểm

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/core/services/department_service.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:his_mobile/presentation/widgets/patient_actions_sheet.dart';

/// v3.0.64: Bộ lọc thời gian (theo mẫu HIS Pro desktop)
enum TrDateFilter {
  today,     // Trong ngày
  week,      // Trong tuần
  month,     // Trong tháng
  year,      // Trong năm
  custom,    // Khoảng ngày tự chọn
}

String _trDateLabel(TrDateFilter f) {
  switch (f) {
    case TrDateFilter.today: return 'Hôm nay';
    case TrDateFilter.week: return 'Tuần';
    case TrDateFilter.month: return 'Tháng';
    case TrDateFilter.year: return 'Năm';
    case TrDateFilter.custom: return 'Tùy chọn';
  }
}

class TreatmentRecordsScreen extends StatefulWidget {
  const TreatmentRecordsScreen({super.key});

  @override
  State<TreatmentRecordsScreen> createState() => _TreatmentRecordsScreenState();
}

class _TreatmentRecordsScreenState extends State<TreatmentRecordsScreen> {
  final _thongke = ThongkeAuthService.instance;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _loading = false;
  bool _loaded = false;
  String? _error;
  List<Map<String, dynamic>> _patients = [];

  // === Filter state ===
  TrDateFilter _dateFilter = TrDateFilter.today;
  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();

  // v3.0.64: Multi-department selection
  Set<int> _selectedDeptIds = {};       // department IDs đã chọn
  Set<String> _selectedDeptCodes = {};  // department codes đã chọn
  List<Map<String, dynamic>> _departments = [];

  // Search
  String _query = '';
  bool _showSuggestions = false;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyDefaultDateFilter();
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

  List<Map<String, dynamic>> get _allDepts {
    if (DepartmentService.instance.departments.isNotEmpty) {
      return DepartmentService.instance.departments;
    }
    return _departments;
  }

  void _loadDepartments() {
    // Dùng DepartmentService nếu có, không thì fallback rỗng
    if (DepartmentService.instance.departments.isNotEmpty) {
      setState(() {});
    }
    // Nếu chưa load, vẫn cho phép chọn sau
  }

  void _applyDefaultDateFilter() {
    final today = DateTime.now();
    setState(() {
      _dateFrom = today;
      _dateTo = today;
    });
  }

  void _onDateFilterChanged(TrDateFilter f) {
    final today = DateTime.now();
    DateTime from;
    DateTime to = today;
    switch (f) {
      case TrDateFilter.today:
        from = DateTime(today.year, today.month, today.day);
        to = DateTime(today.year, today.month, today.day, 23, 59, 59);
        break;
      case TrDateFilter.week:
        from = today.subtract(const Duration(days: 7));
        break;
      case TrDateFilter.month:
        from = DateTime(today.year, today.month, 1);
        break;
      case TrDateFilter.year:
        from = DateTime(today.year, 1, 1);
        break;
      case TrDateFilter.custom:
        from = _dateFrom;
        to = _dateTo;
        break;
    }
    setState(() {
      _dateFilter = f;
      _dateFrom = from;
      _dateTo = to;
    });
    if (f != TrDateFilter.custom) {
      _load();
    }
  }

  Future<void> _pickCustomDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF00796B),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (range != null) {
      setState(() {
        _dateFilter = TrDateFilter.custom;
        _dateFrom = range.start;
        _dateTo = range.end;
      });
      _load();
    }
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text;
    setState(() {
      _query = q;
      _showSuggestions = q.trim().isNotEmpty;
    });
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (q.trim().isNotEmpty) {
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
      if (!mounted) return;
      setState(() => _suggestions = (list ?? []).take(30).toList());
    } catch (e) {
      debugPrint('typeahead error: $e');
    }
  }

  void _selectSuggestion(Map<String, dynamic> p) {
    _searchCtrl.text = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['tdl_patient_name'] ?? '').toString();
    setState(() {
      _query = _searchCtrl.text;
      _showSuggestions = false;
    });
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;

    // Nếu chưa chọn khoa nào → thông báo
    if (_selectedDeptIds.isEmpty && _selectedDeptCodes.isEmpty) {
      setState(() => _error = 'Vui lòng chọn ít nhất 1 khoa để xem danh sách.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _showSuggestions = false;
    });

    try {
      // v3.0.72: CHỈ dùng API Public - bỏ Data 3000 và HIS Pro VPN
      final futures = <Future<List<Map<String, dynamic>>?>>[];
      for (final id in _selectedDeptIds) {
        futures.add(_thongke.fetchPatientsPublic(
          departmentCatalogId: id,
          from: _dateFrom,
          to: _dateTo,
          filterType: 'date_in',
          length: 300,
        ));
      }
      final results = await Future.wait(futures);
      final allPatients = <Map<String, dynamic>>[];
      for (final r in results) {
        if (r != null) allPatients.addAll(r);
      }

      // Sắp xếp: mới nhất trước (theo IN_TIME)
      allPatients.sort((a, b) {
        final ta = _getInTime(a) ?? DateTime(1900);
        final tb = _getInTime(b) ?? DateTime(1900);
        return tb.compareTo(ta);
      });

      if (!mounted) return;
      setState(() {
        _patients = allPatients;
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

  DateTime? _getInTime(Map<String, dynamic> p) {
    try {
      final v = p['IN_TIME'] ?? p['in_time'] ?? p['TDL_IN_TIME'] ?? p['tdl_in_time'] ?? '';
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v.toString().substring(0, 19));
      }
    } catch (_) {}
    return DateTime(2000);
  }

  void _onDeptTap() async {
    // Mở bottom sheet chọn khoa đa chọn
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DeptMultiPicker(
        initialSelected: _selectedDeptIds,
        departments: _allDepts,
      ),
    );
    if (result != null) {
      setState(() {
        _selectedDeptIds = result;
        // Build dept codes từ ids
        _selectedDeptCodes = {};
        for (final d in _allDepts) {
          if (result.contains(d['id'] as int)) {
            final code = d['code']?.toString();
            if (code != null) _selectedDeptCodes.add(code);
          }
        }
      });
      _load();
    }
  }

  String _fmtDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
  }

  List<Map<String, dynamic>> _filteredPatients() {
    var list = _patients;
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((p) {
        final name = (p['TDL_PATIENT_NAME'] ?? p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_name'] ?? '').toString().toLowerCase();
        final code = (p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? '').toString().toLowerCase();
        final reqCode = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q) || reqCode.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00796B),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Quay lại',
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
            const Text('Hồ sơ điều trị', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${_selectedDeptIds.length} khoa • ${_patients.length} BN',
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
      body: Column(
        children: [
          // === Date Filter Chips ===
          _buildDateFilterBar(),

          // === Department Picker Button ===
          _buildDeptPickerBar(),

          // === Search bar ===
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Gõ tên / mã BN / mã ĐT để lọc...',
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
            ),
          ),

          // === Suggestions overlay ===
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
                          _load();
                        },
                        icon: const Icon(Icons.search, size: 16),
                        label: Text('Tìm tất cả "$_query"'),
                      ),
                    );
                  }
                  return _buildSuggestionTile(_suggestions[i]);
                },
              ),
            ),

          // === Patient List ===
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildDateFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Color(0xFF00796B)),
              const SizedBox(width: 6),
              const Text('Thời gian:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: TrDateFilter.values.map((f) {
                      final selected = _dateFilter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(_trDateLabel(f), style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.black87)),
                          selected: selected,
                          onSelected: (_) {
                            if (f == TrDateFilter.custom) {
                              _pickCustomDateRange();
                            } else {
                              _onDateFilterChanged(f);
                            }
                          },
                          selectedColor: const Color(0xFF00796B),
                          backgroundColor: Colors.grey.shade100,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.date_range, size: 12, color: Colors.black38),
              const SizedBox(width: 4),
              Text(
                '${_fmtDate(_dateFrom)} → ${_fmtDate(_dateTo)}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              ),
              const Spacer(),
              Text(
                'Lọc: ${_dateFilter == TrDateFilter.custom ? "Tùy chọn" : _trDateLabel(_dateFilter)}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF00796B), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeptPickerBar() {
    final depts = _allDepts.where((d) => _selectedDeptIds.contains(d['id'] as int)).toList();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_hospital, size: 14, color: Color(0xFF00796B)),
              const SizedBox(width: 6),
              Text(
                'Khoa: ${_selectedDeptIds.isEmpty ? "Chưa chọn" : "${_selectedDeptIds.length} khoa"}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: _selectedDeptIds.isEmpty ? Colors.red : const Color(0xFF00796B)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _onDeptTap,
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Chọn khoa', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00796B),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (depts.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: depts.map((d) {
                  final name = d['name']?.toString() ?? '';
                  final icon = d['icon']?.toString() ?? '🏥';
                  return Padding(
                    padding: const EdgeInsets.only(right: 6, top: 4),
                    child: Chip(
                      avatar: Text(icon, style: const TextStyle(fontSize: 12)),
                      label: Text(name, style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      deleteIconColor: Colors.black54,
                      onDeleted: () {
                        final id = d['id'] as int;
                        setState(() {
                          _selectedDeptIds.remove(id);
                          final code = d['code']?.toString();
                          if (code != null) _selectedDeptCodes.remove(code);
                        });
                      },
                      backgroundColor: const Color(0xFFE0F2F1),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _patients.isEmpty && _suggestions.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00796B)));
    }
    if (_error != null && _patients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: Colors.orange.shade400),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange.shade800, fontSize: 13)),
              const SizedBox(height: 12),
              if (_selectedDeptIds.isEmpty)
                FilledButton.icon(
                  onPressed: _onDeptTap,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00796B)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Chọn khoa'),
                )
              else
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
                    ? 'Không có BN trong khoảng ${_fmtDate(_dateFrom)} → ${_fmtDate(_dateTo)}'
                    : 'Không tìm thấy "$_query"',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredPatients();
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF00796B),
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, i) => _buildPatientCard(filtered[i]),
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> p) {
    final name = capitalizeVietnameseName(PatientNameHelper.getName(p));
    final code = (p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? '').toString();
    final reqCode = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString();
    final dob = (p['TDL_PATIENT_DOB'] ?? p['tdl_patient_dob'] ?? '').toString();
    final gender = (p['TDL_PATIENT_GENDER_NAME'] ?? p['gender_name'] ?? '').toString();
    final icd = (p['ICD_NAME'] ?? p['icd_name'] ?? '').toString();
    final dept = fixVietnameseMojibake((p['TDL_REQUEST_DEPARTMENT_NAME'] ?? p['DEPARTMENT_NAME'] ?? p['department_name'] ?? '').toString());
    final addr = (p['PATIENT_ADDRESS'] ?? p['address'] ?? '').toString();
    final treatmentType = (p['TREATMENT_TYPE_NAME'] ?? p['treatment_type_name'] ?? '').toString();
    final HeinCard = (p['HEIN_CARD_NUMBER'] ?? p['hein_card_number'] ?? '').toString();

    String? inTime;
    try {
      final v = p['IN_TIME'] ?? p['in_time'] ?? p['TDL_IN_TIME'] ?? '';
      if (v.toString().isNotEmpty) {
        final dt = DateTime.tryParse(v.toString().length > 19 ? v.toString().substring(0, 19) : v.toString());
        if (dt != null) {
          inTime = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${_fmtDate(dt)}';
        }
      }
    } catch (_) {}

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.lightImpact();
          _showPatientActions(p);
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Name + Dept
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF00796B),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        if (dept.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.local_hospital, size: 10, color: Color(0xFF00796B)),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  dept,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF00796B), fontWeight: FontWeight.w600),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Gender + DOB
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (gender.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: gender == 'Nam' ? Colors.blue.shade50 : Colors.pink.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(gender, style: TextStyle(fontSize: 10, color: gender == 'Nam' ? Colors.blue.shade700 : Colors.pink.shade700, fontWeight: FontWeight.w600)),
                        ),
                      if (dob.isNotEmpty)
                        Text(
                          dob.length >= 4 ? dob.substring(0, 4) : dob,
                          style: const TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Row 2: Codes + ICD
              Row(
                children: [
                  if (reqCode.isNotEmpty)
                    _infoTag('Mã ĐT', reqCode, Colors.indigo),
                  if (code.isNotEmpty)
                    _infoTag('Mã BN', code, Colors.grey.shade700),
                  if (treatmentType.isNotEmpty)
                    _infoTag('HĐT', treatmentType, Colors.teal.shade700),
                  const Spacer(),
                  if (inTime != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time, size: 10, color: Colors.black38),
                        const SizedBox(width: 2),
                        Text(inTime, style: const TextStyle(fontSize: 9, color: Colors.black54)),
                      ],
                    ),
                ],
              ),

              // Row 3: ICD + BHYT
              if (icd.isNotEmpty || HeinCard.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      if (icd.isNotEmpty)
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.medical_information, size: 10, color: Colors.red),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  icd,
                                  style: const TextStyle(fontSize: 10, color: Colors.red),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (HeinCard.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.badge, size: 10, color: Colors.blue),
                            const SizedBox(width: 2),
                            Text(
                              HeinCard,
                              style: const TextStyle(fontSize: 9, color: Colors.blue),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

              // Row 4: Address
              if (addr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, size: 10, color: Colors.black38),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          addr,
                          style: const TextStyle(fontSize: 9, color: Colors.black45),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTag(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8))),
          Text(value, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showPatientActions(Map<String, dynamic> patient) {
    final dept = _allDepts.isNotEmpty ? (_allDepts.firstWhere(
      (d) => d['id'] == patient['DEPARTMENT_ID'] || d['code'] == patient['DEPARTMENT_CODE'],
      orElse: () => {'id': 0, 'name': 'Khoa', 'code': ''},
    )) : {'id': 0, 'name': 'Khoa', 'code': ''};

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => PatientActionsSheet(
        patient: patient,
        department: dept,
      ),
    );
  }

  Widget _buildSuggestionTile(Map<String, dynamic> p) {
    final name = fixVietnameseMojibake(
      (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['tdl_patient_name'] ?? 'BN').toString());
    final code = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString();
    final dept = fixVietnameseMojibake((p['DEPARTMENT_NAME'] ?? '').toString());
    final dob = (p['TDL_PATIENT_DOB'] ?? '').toString();

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: const Color(0xFF00796B),
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      title: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      subtitle: Text('$code • $dept', style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: dob.isNotEmpty ? Text(dob.substring(0, dob.length > 10 ? 10 : dob.length), style: const TextStyle(fontSize: 9, color: Colors.black54)) : null,
      onTap: () => _selectSuggestion(p),
    );
  }
}

/// v3.0.64: Bottom sheet đa chọn khoa
class _DeptMultiPicker extends StatefulWidget {
  final Set<int> initialSelected;
  final List<Map<String, dynamic>> departments;

  const _DeptMultiPicker({required this.initialSelected, required this.departments});

  @override
  State<_DeptMultiPicker> createState() => _DeptMultiPickerState();
}

class _DeptMultiPickerState extends State<_DeptMultiPicker> {
  late Set<int> _selected;
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_q.isEmpty) return widget.departments;
    final lower = _q.toLowerCase();
    return widget.departments.where((d) {
      final name = d['name']?.toString() ?? '';
      final code = d['code']?.toString() ?? '';
      return name.toLowerCase().contains(lower) || code.toLowerCase().contains(lower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.local_hospital, color: Color(0xFF00796B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Chọn khoa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('${_selected.length} khoa đã chọn', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, _selected),
                  child: const Text('XONG', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Tìm khoa...',
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),

          // Quick chips: Chọn tất cả / Bỏ tất cả
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                ActionChip(
                  label: const Text('Chọn tất cả', style: TextStyle(fontSize: 11)),
                  onPressed: () => setState(() => _selected = widget.departments.map((d) => d['id'] as int).toSet()),
                  backgroundColor: const Color(0xFFE0F2F1),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: const Text('Bỏ tất cả', style: TextStyle(fontSize: 11)),
                  onPressed: () => setState(() => _selected.clear()),
                  backgroundColor: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // List
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: _filtered.length,
              itemBuilder: (ctx, i) {
                final d = _filtered[i];
                final id = d['id'] as int;
                final name = d['name']?.toString() ?? '';
                final code = d['code']?.toString() ?? '';
                final icon = d['icon']?.toString() ?? '🏥';
                final isSelected = _selected.contains(id);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    });
                  },
                  activeColor: const Color(0xFF00796B),
                  title: Row(
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 13)),
                            Text('ID $id • $code', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  dense: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// === Helper: capitalize Vietnamese name ===
String capitalizeVietnameseName(String name) {
  if (name.isEmpty) return name;
  // Split by space, capitalize each part
  return name.trim().split(' ').map((part) {
    if (part.isEmpty) return part;
    return part[0].toUpperCase() + part.substring(1).toLowerCase();
  }).join(' ');
}
