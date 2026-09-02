import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/patient_dataset.dart';
import 'package:his_mobile/presentation/widgets/patient_actions_sheet.dart';
import 'package:his_mobile/presentation/widgets/patient_card.dart';

/// Màn hình Bệnh nhân - hiển thị tất cả BN từ Thongke server
/// Tìm kiếm tiếng Việt với tên/mã/khoa
class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final HisApiService _api = HisApiService.instance;
  final ThongkeAuthService _thongke = ThongkeAuthService();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  bool _loading = true;
  String? _error;
  String? _debugInfo;
  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _selectedPatient;
  String _searchQuery = '';
  String? _selectedRoom; // v2.75.6: filter phòng

  @override
  void initState() {
    super.initState();
    _load();
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// v2.37.0: Tính gợi ý BN theo tên/Mã ĐT - càng gõ càng chính xác
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
    // Lấy tất cả BN hiện có + seed
    final all = <Map<String, dynamic>>[..._patients];
    // Bổ sung seed nếu patients list rỗng
    if (all.isEmpty) {
      for (final d in ['HSCC', 'CCS', 'DTYC', 'DVNTK', 'DVTMCT', 'HSTC', 'NTK', 'NTTN', 'KM', 'NGCT', 'NGTH', 'KN', 'NTM', 'KNTH', 'KPS', 'KTNT', 'PTGMHS', 'KRHM', 'KTMH', 'KTN', 'KYHCT', 'KKB', 'KUB', 'KSNK', 'HSCCL', 'CCSVL', 'DTCCLuu']) {
        all.addAll(PatientSeed.getByDepartment(d));
      }
    }
    // Filter và ranking theo độ khớp
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
      if (score > 0) {
        scored.add({...p, '_score': score});
      }
    }
    scored.sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));
    setState(() {
      _suggestions = scored.take(15).toList();
      _showSuggestions = true;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _debugInfo = null;
    });

    try {
      // 1. Hiển thị data seed NGAY (UX nhanh)
      final seed = PatientSeed.search(_searchQuery);
      setState(() {
        _patients = seed;
        _loading = false;
      });

      // 2. Gọi Thongke API với cookies (CookieManager tự gửi)
      final apiList = await _thongke.fetchPatients(
        treatmentCode: _searchQuery.isNotEmpty ? _searchQuery : null,
        length: 500,
      );

      if (apiList != null) {
        // Filter theo search query (diacritic-insensitive)
        var filtered = apiList;
        if (_searchQuery.isNotEmpty) {
          filtered = apiList.where((p) {
            final fields = [
              p['tdl_patient_name']?.toString() ?? '',
              p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME']?.toString() ?? '',
              p['tdl_patient_code']?.toString() ?? '',
              p['TDL_PATIENT_CODE']?.toString() ?? '',
              p['tdl_hein_card_number']?.toString() ?? '',
              p['treatment_code']?.toString() ?? '',
              p['TDL_TREATMENT_CODE']?.toString() ?? '',
              p['tdl_patient_phone']?.toString() ?? '',
              p['department_name']?.toString() ?? '',
              p['department_code']?.toString() ?? '',
            ];
            return fields.any((f) => matchesVietnamese(f, _searchQuery));
          }).toList();
        }
        // Merge với seed (thêm BN seed chưa có trong API)
        final apiCodes = filtered.map((p) => p['treatment_code']).toSet();
        for (final p in seed) {
          final code = p['treatment_code'];
          if (code != null && !apiCodes.contains(code)) {
            filtered.add(p);
          }
        }
        if (!mounted) return;
        setState(() {
          _patients = filtered;
          _debugInfo = '🌐 Thongke: ${apiList.length} BN từ server (filter còn ${filtered.length})';
        });
      } else {
        if (!mounted) return;
        setState(() {
          _patients = seed;
          _debugInfo = '📋 Dùng ${seed.length} BN từ app (PatientSeed)';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _patients = PatientSeed.search(_searchQuery);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          // v2.75.6: Filter theo phòng sau khi load xong
          if (_selectedRoom != null && _selectedRoom!.isNotEmpty) {
            _patients = _patients.where((p) {
              final room = (p['EXECUTE_ROOM_NAME'] ?? p['BED_ROOM_NAME'] ?? p['room_name'] ?? '').toString();
              return room == _selectedRoom;
            }).toList();
          }
        });
      }
    }
  }

  void _onSearch(String value) {
    setState(() => _searchQuery = value.trim());
    _updateSuggestions(value);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_searchQuery == value.trim() && mounted) {
        _load();
      }
    });
  }

  /// Mở BN được chọn từ gợi ý
  void _pickSuggestion(Map<String, dynamic> p) {
    _searchCtrl.text = (p['tdl_patient_name'] ?? p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['TEN_BENH_NHAN'] ?? '').toString();
    _searchCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _searchCtrl.text.length));
    setState(() {
      _searchQuery = (p['treatment_code'] ?? p['TDL_TREATMENT_CODE'] ?? p['tdl_patient_code'] ?? '').toString();
      _showSuggestions = false;
    });
    _load();
  }

  void _openActions(Map<String, dynamic> patient) {
    setState(() => _selectedPatient = patient);
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
        patient: patient,
        department: {'name': 'Bệnh nhân', 'code': '', 'icon': '👤'},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: 'Quay lại Trang chủ',
          onPressed: () {
            // ShellRoute: dùng go_router để tránh đen màn hình
            if (Navigator.canPop(context)) {
              context.safePop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Sổ bệnh nhân', style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart, color: Colors.white),
            tooltip: 'Thống kê',
            onPressed: () {
              if (mounted) context.go('/reports');
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Làm mới',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                style: const TextStyle(color: Colors.black, fontSize: 14),
                cursorColor: Colors.indigo,
                decoration: InputDecoration(
                  hintText: 'Tìm bệnh nhân (gõ 1 chữ hiện gợi ý)',
                  hintStyle: const TextStyle(color: Colors.black45, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Colors.indigo, size: 20),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black54, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearch('');
                          },
                        ),
                      // v2.75.0: Nút "Tìm" rõ ràng
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: TextButton(
                          onPressed: () {
                            if (_searchQuery.isNotEmpty) {
                              _updateSuggestions(_searchQuery);
                            }
                          },
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Tìm',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: const Color(0xFFE3F2FD),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.indigo, width: 1.5),
                  ),
                ),
                onChanged: _onSearch,
              ),
            ),
            // v2.75.6: Chips phòng ngang (giống HomeScreen)
            _buildRoomChips(),
            // v2.37.0: Gợi ý dropdown
            if (_showSuggestions && _suggestions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.indigo.shade200),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final p = _suggestions[i];
                    final name = (p['tdl_patient_name'] ?? p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['TEN_BENH_NHAN'] ?? 'BN').toString();
                    final tcode = (p['treatment_code'] ?? p['TDL_TREATMENT_CODE'] ?? p['MADT'] ?? '').toString();
                    final pcode = (p['patient_code'] ?? p['TDL_PATIENT_CODE'] ?? p['MABN'] ?? '').toString();
                    return ListTile(
                      dense: true,
                      leading: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.indigo,
                        child: Icon(Icons.person, color: Colors.white, size: 14),
                      ),
                      title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      subtitle: Text([
                        if (tcode.isNotEmpty) 'ĐT: $tcode',
                        if (pcode.isNotEmpty) 'BN: $pcode',
                      ].where((s) => s.isNotEmpty).join(' • '), style: const TextStyle(fontSize: 11)),
                      onTap: () => _pickSuggestion(p),
                    );
                  },
                ),
              ),

            // Count + selected patient
            if (_patients.isNotEmpty || _selectedPatient != null)
              Container(
                color: const Color(0xFFE3F2FD),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.people, size: 14, color: Colors.indigo),
                    const SizedBox(width: 4),
                    Text(
                      '${_patients.length} bệnh nhân',
                      style: const TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    if (_selectedPatient != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(4)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '● ${capitalizeVietnameseName((_selectedPatient!['TDL_PATIENT_UNSIGNED_NAME'] ?? _selectedPatient!['TDL_PATIENT_NAME'] ?? _selectedPatient!['tdl_patient_name'] ?? 'BN').toString())}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => setState(() => _selectedPatient = null),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // BN list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _patients.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                            itemCount: _patients.length,
                            itemBuilder: (context, i) {
                              final p = _patients[i];
                              final isSelected = _selectedPatient != null &&
                                  _selectedPatient!['treatment_code'] == p['treatment_code'];
                              return PatientCard(
                                patient: p,
                                isSelected: isSelected,
                                onActions: () => _openActions(p),
                                onSelectedChanged: (sel) {
                                  setState(() {
                                    _selectedPatient = sel ? p : null;
                                  });
                                },
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Không tìm thấy "${_searchQuery}"'
                  : 'Chưa có bệnh nhân',
              style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Đợi tải từ server hoặc bấm Thử lại',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 11),
            ),
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
                        Text('DEBUG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_debugInfo!, style: const TextStyle(fontSize: 10, color: Colors.black87, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
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

  /// v2.75.6: Filter chips phòng nằm ngang (giống HomeScreen)
  Widget _buildRoomChips() {
    final rooms = <String>{};
    for (final p in _patients) {
      final room = (p['EXECUTE_ROOM_NAME'] ?? p['BED_ROOM_NAME'] ?? p['room_name'] ?? '').toString();
      if (room.isNotEmpty) rooms.add(room);
    }
    final roomList = rooms.toList()..sort();
    if (roomList.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFFF5F5F5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _roomChip(label: 'Tất cả', value: null, isSelected: _selectedRoom == null),
            for (final r in roomList) _roomChip(label: r, value: r, isSelected: _selectedRoom == r),
          ],
        ),
      ),
    );
  }

  Widget _roomChip({required String label, required String? value, required bool isSelected}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () {
          setState(() => _selectedRoom = value);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1976D2) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xFF1976D2) : Colors.black26,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}