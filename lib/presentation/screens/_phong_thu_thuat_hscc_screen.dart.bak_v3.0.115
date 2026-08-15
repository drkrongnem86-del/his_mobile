// PhongThuThuatHsccScreen v3.0.110 - "Phòng thủ thuật HSCC"
// v3.0.110: Thêm Y Tế Số 3000 + sửa HIS Pro filter theo HIS Desktop thật
//   - 3 nguồn API: ☁ Public 8080 / 🏥 HIS Pro 1408 / 📊 Y Tế Số 3000
//   - HIS Pro: filter EXECUTE_ROOM_ID=36 + status [1,2,3] (giống HIS Desktop → 78 BN)
//   - Y Tế Số: filter BED_ROOM_ID (mặc định 39 - anh chỉnh trong app nếu sai)
//   - Public: filter dept_catalog=22 (luôn chạy, ~19 BN)
//
// v3.0.109: Thay thế PhongTTKccScreen (PTTT_KCC cũ) theo yêu cầu BS Nem
//   - Lấy layout API selector từ HomeScreen Khoa Cấp Cứu
//   - Card BN + bottom sheet 2 tab: Thông tin / ECG - giữ nguyên từ bản cũ

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:his_mobile/core/services/phong_tt_api_sources.dart';
import 'package:his_mobile/data/api/y_te_so_service.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// Màn hình Phòng thủ thuật HSCC (REQUEST_ROOM_ID = 39)
class PhongThuThuatHsccScreen extends StatefulWidget {
  final int requestRoomId;
  final String roomName;
  final int deptCatalogId;

  const PhongThuThuatHsccScreen({
    super.key,
    this.requestRoomId = 39,    // PTTT_KCC
    this.roomName = 'Phòng thủ thuật HSCC',
    this.deptCatalogId = 22,     // HSCC - Khoa Cấp Cứu
  });

  @override
  State<PhongThuThuatHsccScreen> createState() => _PhongThuThuatHsccScreenState();
}

class _PhongThuThuatHsccScreenState extends State<PhongThuThuatHsccScreen> {
  static const _kApiSourcePref = 'phong_thu_thuat_hscc_api_source';
  static const _kBedRoomIdPref = 'phong_thu_thuat_hscc_bed_room_id';
  static const _kExecuteRoomIdPref = 'phong_thu_thuat_hscc_execute_room_id';
  PhongTTApiSource _selectedSource = PhongTTApiSource.public8080;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _allPatients = [];
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  String? _apiSourceLabel;
  DateTime? _lastSynced;
  String? _lastApiUrl;
  int _bedRoomId = 39;        // v3.0.110: BED_ROOM_ID cho Y Tế Số (mặc định 39 = PTTT_KCC)
  int _executeRoomId = 36;    // v3.0.110: EXECUTE_ROOM_ID cho HIS Pro (HIS Desktop dùng 36)

  @override
  void initState() {
    super.initState();
    _loadSavedSource();
  }

  Future<void> _loadSavedSource() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kApiSourcePref);
      if (saved != null) {
        _selectedSource = PhongTTApiSource.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => PhongTTApiSource.public8080,
        );
      }
      _bedRoomId = prefs.getInt(_kBedRoomIdPref) ?? 39;
      _executeRoomId = prefs.getInt(_kExecuteRoomIdPref) ?? 36;
    } catch (_) {}
    if (mounted) setState(() {});
    _loadData();
  }

  Future<void> _saveSource(PhongTTApiSource s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kApiSourcePref, s.name);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      debugPrint('🔍 [PTTT_HSCC] load from ${_selectedSource.label} (bed=$_bedRoomId, exe=$_executeRoomId)');
      final res = await PhongTTApiService.instance.loadPatients(
        source: _selectedSource,
        executeRoomId: _executeRoomId,
        bedRoomId: _bedRoomId,
        deptCatalogId: widget.deptCatalogId,
      );

      debugPrint('🔍 [PTTT_HSCC] result: success=${res.success} count=${res.patients.length} msg=${res.message}');
      if (res.patients.isNotEmpty) {
        debugPrint('🔍 [PTTT_HSCC] first BN: ${res.patients.first}');
      }
      await _dumpResponseToFile(res);

      if (mounted) {
        setState(() {
          _allPatients = res.patients;
          _apiSourceLabel = res.success
              ? '${_selectedSource.label} → ${res.patients.length} BN'
              : '❌ ${_selectedSource.shortLabel}: ${res.message}';
          _lastApiUrl = res.apiUrl;
          _lastSynced = res.loadedAt;
          _error = res.success ? null : res.message;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('🔍 [PTTT_HSCC] EXCEPTION: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _changeSource(PhongTTApiSource newSource) async {
    if (newSource == _selectedSource) return;
    setState(() {
      _selectedSource = newSource;
      _allPatients = [];
      _apiSourceLabel = '⏳ Đang chuyển sang ${newSource.label}...';
    });
    await _saveSource(newSource);
    await _loadData();
  }

  // Bottom sheet chỉnh Room ID
  Future<void> _showRoomIdEditor() async {
    final bedCtrl = TextEditingController(text: _bedRoomId.toString());
    final exeCtrl = TextEditingController(text: _executeRoomId.toString());
    final result = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.tune, size: 20, color: Color(0xFFB71C1C)),
                  SizedBox(width: 8),
                  Text('Cấu hình Room ID', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bedCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'BED_ROOM_ID (Y Tế Số 3000)',
                  hintText: '39',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: exeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'EXECUTE_ROOM_ID (HIS Pro 1408)',
                  hintText: '36',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text('💡 HIS Desktop filter: EXECUTE_ROOM_ID=36, status 1,2,3 → 78 BN',
                style: TextStyle(color: Colors.black45, fontSize: 11)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Hủy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final bed = int.tryParse(bedCtrl.text) ?? _bedRoomId;
                        final exe = int.tryParse(exeCtrl.text) ?? _executeRoomId;
                        Navigator.pop(ctx, {'bed': bed, 'exe': exe});
                      },
                      child: const Text('Lưu & Tải lại'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _bedRoomId = result['bed']!;
        _executeRoomId = result['exe']!;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kBedRoomIdPref, _bedRoomId);
        await prefs.setInt(_kExecuteRoomIdPref, _executeRoomId);
      } catch (_) {}
      _loadData();
    }
  }

  // ============== API selector (giống HomeScreen) ==============
  void _prevSource() {
    final idx = PhongTTApiSource.values.indexOf(_selectedSource);
    final prev = idx == 0 ? PhongTTApiSource.values.length - 1 : idx - 1;
    _changeSource(PhongTTApiSource.values[prev]);
  }

  void _nextSource() {
    final idx = PhongTTApiSource.values.indexOf(_selectedSource);
    final next = idx == PhongTTApiSource.values.length - 1 ? 0 : idx + 1;
    _changeSource(PhongTTApiSource.values[next]);
  }

  String _sourceLabel(PhongTTApiSource src) {
    switch (src) {
      case PhongTTApiSource.public8080: return '☁ Public';
      case PhongTTApiSource.hisPro1408: return '🏥 HIS Pro 1408';
      case PhongTTApiSource.yTeSo3000:  return '📊 Y Tế Số 3000';
    }
  }

  IconData _sourceIcon(PhongTTApiSource src) {
    switch (src) {
      case PhongTTApiSource.public8080: return Icons.cloud;
      case PhongTTApiSource.hisPro1408: return Icons.local_hospital;
      case PhongTTApiSource.yTeSo3000:  return Icons.storage;
    }
  }

  Color _sourceColor(PhongTTApiSource src) {
    switch (src) {
      case PhongTTApiSource.public8080: return Colors.orange.shade700;
      case PhongTTApiSource.hisPro1408: return Colors.indigo.shade700;
      case PhongTTApiSource.yTeSo3000:  return Colors.teal.shade700;
    }
  }

  String _sourceUrl(PhongTTApiSource src) {
    switch (src) {
      case PhongTTApiSource.public8080: return 'GET emr-checker-list :8080';
      case PhongTTApiSource.hisPro1408: return 'GetLView :1408 (roomId=$_executeRoomId)';
      case PhongTTApiSource.yTeSo3000:  return 'POST benh-nhan-buong-benh (bed=$_bedRoomId)';
    }
  }

  // Bottom sheet chọn API
  void _showApiMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.cloud, size: 20, color: Color(0xFFB71C1C)),
                SizedBox(width: 8),
                Text('Chọn nguồn API', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Lấy danh sách BN trong Phòng thủ thuật HSCC:',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 12),
            ...PhongTTApiSource.values.map((src) {
              final isSel = src == _selectedSource;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFFFFEBEE) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSel ? const Color(0xFFB71C1C) : Colors.grey.shade300,
                    width: isSel ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  onTap: () {
                    Navigator.pop(ctx);
                    _changeSource(src);
                  },
                  leading: Container(
                    width: 36, height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSel ? _sourceColor(src) : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(_sourceIcon(src),
                      color: isSel ? Colors.white : Colors.black54, size: 18),
                  ),
                  title: Text(_sourceLabel(src), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_sourceUrl(src), style: const TextStyle(fontSize: 11)),
                  trailing: isSel ? const Icon(Icons.check_circle, color: Color(0xFFB71C1C)) : null,
                ),
              );
            }),
            const Divider(height: 16),
            ListTile(
              leading: const Icon(Icons.tune, color: Color(0xFFB71C1C)),
              title: const Text('Cấu hình Room ID', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('BED_ROOM_ID=$_bedRoomId, EXECUTE_ROOM_ID=$_executeRoomId',
                style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                _showRoomIdEditor();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Dump response ra file
  Future<void> _dumpResponseToFile(PhongTTResult res) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/last_pttt_hscc_response.json');
      final buf = StringBuffer();
      buf.writeln('=== PTTT_HSCC DEBUG DUMP v3.0.109 ===');
      buf.writeln('Time: ${DateTime.now().toIso8601String()}');
      buf.writeln('Source: ${_selectedSource.name}');
      buf.writeln('URL: ${res.apiUrl}');
      buf.writeln('Success: ${res.success}');
      buf.writeln('Message: ${res.message ?? ""}');
      buf.writeln('Count: ${res.patients.length}');
      if (res.patients.isNotEmpty) {
        buf.writeln('--- First 2 BNs ---');
        for (var i = 0; i < (res.patients.length < 2 ? res.patients.length : 2); i++) {
          buf.writeln('--- BN ${i + 1} ---');
          try {
            buf.writeln(const JsonEncoder.withIndent('  ').convert(res.patients[i]));
          } catch (e) {
            buf.writeln(res.patients[i].toString());
          }
        }
      }
      await f.writeAsString(buf.toString(), flush: true);
    } catch (e) {
      debugPrint('🔍 [PTTT_HSCC] dump error: $e');
    }
  }

  // Helper lấy tên BN
  Map<String, String> _pickPatientName(Map<String, dynamic> p) {
    final candidates = <String>[
      'TDL_PATIENT_NAME',
      'TDL_PATIENT_UNSIGNED_NAME',
      'VIR_PATIENT_NAME',
      'PATIENT_NAME',
      'tdl_patient_name',
      'patientName',
    ];
    for (final k in candidates) {
      final v = p[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return {'name': v.toString().trim(), 'source': k};
      }
    }
    return {'name': 'N/A', 'source': '(no name field)'};
  }

  int _age(dynamic dob) {
    if (dob == null) return 0;
    try {
      final s = dob.toString();
      // Support yyyy-MM-dd, yyyyMMddHHmmss, yyyyMMdd
      int y;
      if (s.length >= 4) {
        y = int.parse(s.substring(0, 4));
        if (y < 1900 || y > 2100) return 0;
        return DateTime.now().year - y;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatInTime(String t) {
    try {
      final dt = DateTime.parse(t);
      return '${_two(dt.hour)}:${_two(dt.minute)} ${_two(dt.day)}/${_two(dt.month)}/${dt.year}';
    } catch (_) {
      return t;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter BN theo search
    final q = _searchQuery.toLowerCase().trim();
    final filtered = q.isEmpty
        ? _allPatients
        : _allPatients.where((p) {
            final name = _pickPatientName(p)['name']!.toLowerCase();
            final code = (p['TDL_PATIENT_CODE'] ?? '').toString().toLowerCase();
            final tcode = (p['TDL_TREATMENT_CODE'] ?? '').toString().toLowerCase();
            return name.contains(q) || code.contains(q) || tcode.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.safePop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.medical_services, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.roomName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('EXECUTE_ROOM_ID: $_executeRoomId  •  HIS Desktop filter',
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'Tải lại'),
        ],
      ),
      body: Column(
        children: [
          // Dòng chọn API (giống HomeScreen) - đặt trên ô search
          Container(
            color: const Color(0xFFE8EAF6),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.cloud, size: 16, color: Color(0xFF3949AB)),
                const SizedBox(width: 6),
                const Text('API:', style: TextStyle(fontSize: 12, color: Color(0xFF3949AB), fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _prevSource,
                  tooltip: 'API trước',
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showApiMenu(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: _sourceColor(_selectedSource).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _sourceColor(_selectedSource), width: 1),
                      ),
                      child: Center(
                        child: Text(
                          _sourceLabel(_selectedSource),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _sourceColor(_selectedSource),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _nextSource,
                  tooltip: 'API sau',
                ),
              ],
            ),
          ),

          // Header gradient với số BN
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BỆNH NHÂN TRONG PHÒNG',
                          style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('${filtered.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          Text('/ ${_allPatients.length} ca',
                              style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                      if (_apiSourceLabel != null && _apiSourceLabel!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(_apiSourceLabel!,
                            style: const TextStyle(color: Colors.white60, fontSize: 10),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      if (_lastSynced != null) ...[
                        const SizedBox(height: 2),
                        Text('🕐 ${_two(_lastSynced!.hour)}:${_two(_lastSynced!.minute)}:${_two(_lastSynced!.second)} ${_two(_lastSynced!.day)}/${_two(_lastSynced!.month)}',
                            style: const TextStyle(color: Colors.white60, fontSize: 10)),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.people, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),

          // Error banner
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('⚠️ $_error', style: TextStyle(color: Colors.red.shade700, fontSize: 11))),
                ],
              ),
            ),

          // Search box
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '🔍 Lọc tên BN / mã BN / mã điều trị...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox, size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text('Chưa có bệnh nhân',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(q.isEmpty
                                ? 'Phòng này hiện không có BN'
                                : 'Không tìm thấy BN phù hợp với "$q"',
                                style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) => _buildPatientCard(filtered[i], i),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> p, int index) {
    final name = _pickPatientName(p)['name']!;
    final code = (p['TDL_PATIENT_CODE'] ?? p['PATIENT_CODE'] ?? '').toString();
    final dob = p['TDL_PATIENT_DOB'];
    final age = _age(dob);
    final isBHYT = p['IS_BHYT'] == true;
    final sttColor = isBHYT ? Colors.blue.shade600 : Colors.purple.shade600;
    final heinCard = (p['TDL_HEIN_CARD_NUMBER'] ?? '').toString();
    final treatmentCode = (p['TDL_TREATMENT_CODE'] ?? '').toString();
    final patientTypeName = (p['PATIENT_TYPE_NAME'] ?? '').toString();
    final treatmentTypeName = (p['TREATMENT_TYPE_NAME'] ?? '').toString();
    final inTime = (p['IN_TIME'] ?? '').toString();
    final deptName = (p['DEPARTMENT_NAME'] ?? p['LAST_DEPARTMENT_RAW'] ?? '').toString();
    final address = (p['TDL_PATIENT_ADDRESS'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: sttColor.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showPatientSheet(p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: sttColor, borderRadius: BorderRadius.circular(6)),
                    child: Text('${index + 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Icon(isBHYT ? Icons.verified_user : Icons.person_outline, color: sttColor, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (patientTypeName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: sttColor, borderRadius: BorderRadius.circular(8)),
                      child: Text(patientTypeName,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('$code  •  ${dob ?? ''}  •  ${age}Y',
                  style: const TextStyle(color: Colors.black87, fontSize: 12)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    if (treatmentCode.isNotEmpty) _apiRow('Mã ĐT', treatmentCode, Icons.medical_information),
                    if (heinCard.isNotEmpty) _apiRow('BHYT', heinCard, Icons.credit_card),
                    if (treatmentTypeName.isNotEmpty) _apiRow('Loại ĐT', treatmentTypeName, Icons.local_hospital),
                    if (deptName.isNotEmpty) _apiRow('Khoa', deptName, Icons.business),
                    if (inTime.isNotEmpty) _apiRow('Giờ vào', _formatInTime(inTime), Icons.access_time),
                    if (address.isNotEmpty) _apiRow('Địa chỉ', address, Icons.place),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _apiRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 11, color: const Color(0xFFB71C1C)),
          const SizedBox(width: 4),
          SizedBox(
            width: 50,
            child: Text('$label:',
                style: const TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _showPatientSheet(Map<String, dynamic> p) async {
    final name = _pickPatientName(p)['name']!;
    final code = (p['TDL_PATIENT_CODE'] ?? '').toString();
    final treatmentCode = (p['TDL_TREATMENT_CODE'] ?? '').toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  decoration: const BoxDecoration(
                    color: Color(0xFFB71C1C),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('Mã BN: $code', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                if (treatmentCode.isNotEmpty)
                                  Text('Mã ĐT: $treatmentCode', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const TabBar(
                        indicatorColor: Colors.white,
                        indicatorWeight: 2,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white60,
                        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        tabs: [
                          Tab(icon: Icon(Icons.person, size: 16), text: 'Thông tin'),
                          Tab(icon: Icon(Icons.monitor_heart, size: 16), text: 'Điện tim'),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _infoTab(p),
                      _ecgTab(treatmentCode, name),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTab(Map<String, dynamic> p) {
    final name = _pickPatientName(p)['name']!;
    final inTime = (p['IN_TIME'] ?? '').toString();
    final outTime = (p['OUT_TIME'] ?? '').toString();
    final fields = <MapEntry<String, String>>[
      MapEntry('Mã BN', (p['TDL_PATIENT_CODE'] ?? '').toString()),
      MapEntry('Tên BN', name),
      MapEntry('Năm sinh', (p['TDL_PATIENT_DOB'] ?? '').toString()),
      MapEntry('Tuổi', _age(p['TDL_PATIENT_DOB']).toString()),
      MapEntry('BHYT', (p['TDL_HEIN_CARD_NUMBER'] ?? '').toString()),
      MapEntry('Mã điều trị', (p['TDL_TREATMENT_CODE'] ?? '').toString()),
      MapEntry('Loại ĐT', (p['TREATMENT_TYPE_NAME'] ?? '').toString()),
      MapEntry('Đối tượng', (p['PATIENT_TYPE_NAME'] ?? '').toString()),
      MapEntry('Khoa', (p['DEPARTMENT_NAME'] ?? p['LAST_DEPARTMENT_RAW'] ?? '').toString()),
      MapEntry('Địa chỉ', (p['TDL_PATIENT_ADDRESS'] ?? '').toString()),
      MapEntry('SĐT', (p['TDL_PATIENT_PHONE'] ?? '').toString()),
      MapEntry('SDT người nhà', (p['TDL_PATIENT_RELATIVE_MOBILE'] ?? '').toString()),
      MapEntry('Giờ vào', inTime.isNotEmpty ? _formatInTime(inTime) : ''),
      MapEntry('Giờ ra', outTime.isNotEmpty ? _formatInTime(outTime) : ''),
      MapEntry('Nguồn', (p['_DATA_SOURCE'] ?? '').toString()),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: fields.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final f = fields[i];
        if (f.value.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(f.key,
                    style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
              Expanded(
                child: Text(f.value,
                    style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ecgTab(String treatmentCode, String patientName) {
    if (treatmentCode.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: Colors.black26, size: 64),
              SizedBox(height: 12),
              Text('BN chưa có mã điều trị', style: TextStyle(color: Colors.black54, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return _EcgViewer(treatmentCode: treatmentCode, patientName: patientName);
  }
}

/// Widget load và hiển thị file PDF điện tim từ YTeSo API
class _EcgViewer extends StatefulWidget {
  final String treatmentCode;
  final String patientName;
  const _EcgViewer({required this.treatmentCode, required this.patientName});

  @override
  State<_EcgViewer> createState() => _EcgViewerState();
}

class _EcgViewerState extends State<_EcgViewer> {
  final YTeSoService _yTeSo = YTeSoService.instance;
  bool _loading = true;
  String? _error;
  List<YTeSoDocument> _docs = [];
  String? _loadedDocPath;
  YTeSoDocument? _loadedDoc;
  final PdfViewerController _pdfCtrl = PdfViewerController();

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  @override
  void dispose() {
    _pdfCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocs() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _yTeSo.listDocuments(treatmentCode: widget.treatmentCode);
      if (res.success && res.groups != null) {
        final all = <YTeSoDocument>[];
        for (final g in res.groups!) {
          final isEcgType = g.id == 160 ||
              g.typeCode == '65' ||
              g.typeName.toLowerCase().contains('điện tim');
          for (final item in g.items) {
            if (isEcgType || item.name.toLowerCase().contains('điện tim')) {
              all.add(item);
            }
          }
        }
        _docs = all;
      } else {
        _error = res.message ?? 'Lỗi tải danh sách';
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPdf(YTeSoDocument doc) async {
    setState(() { _loading = true; _error = null; _loadedDocPath = null; });
    try {
      final res = await _yTeSo.downloadDocument(
        documentId: doc.id,
        treatmentCode: widget.treatmentCode,
      );
      if (!res.success || res.filePath == null) {
        _error = res.message ?? 'Không tải được file';
        return;
      }
      if (mounted) {
        setState(() {
          _loadedDocPath = res.filePath;
          _loadedDoc = doc;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade300, size: 64),
              const SizedBox(height: 12),
              Text('Lỗi: $_error', style: const TextStyle(color: Colors.black54, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadDocs,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_loadedDocPath != null) {
      return Column(
        children: [
          Container(
            color: const Color(0xFFFFF3E0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Color(0xFFD32F2F), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loadedDoc?.name ?? 'Điện tim',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() {
                    _loadedDocPath = null;
                    _loadedDoc = null;
                  }),
                  tooltip: 'Đóng',
                ),
              ],
            ),
          ),
          Expanded(
            child: SfPdfViewer.file(
              File(_loadedDocPath!),
              controller: _pdfCtrl,
              canShowScrollHead: false,
              canShowScrollStatus: true,
            ),
          ),
        ],
      );
    }
    if (_docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monitor_heart, color: Colors.grey.shade300, size: 80),
              const SizedBox(height: 12),
              const Text('Chưa có phiếu điện tim',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Mã ĐT: ${widget.treatmentCode}',
                  style: const TextStyle(color: Colors.black54, fontSize: 11)),
              const SizedBox(height: 8),
              const Text('(Phiếu điện tim phải được đẩy lên EMR trước)',
                  style: TextStyle(color: Colors.black45, fontSize: 11), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (ctx, i) {
        final d = _docs[i];
        return Card(
          color: const Color(0xFFFFF3E0),
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.monitor_heart, color: Color(0xFFD32F2F), size: 20),
            ),
            title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.signer.isNotEmpty) Text('👨‍⚕️ ${d.signer}', style: const TextStyle(fontSize: 11)),
                if (d.documentTime.isNotEmpty) Text('🕐 ${_formatDocTime(d.documentTime)}', style: const TextStyle(fontSize: 11)),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () => _loadPdf(d),
          ),
        );
      },
    );
  }

  String _formatDocTime(String t) {
    if (t.length < 12) return t;
    try {
      return '${t.substring(6, 8)}/${t.substring(4, 6)}/${t.substring(0, 4)} ${t.substring(8, 10)}:${t.substring(10, 12)}';
    } catch (_) {
      return t;
    }
  }
}
