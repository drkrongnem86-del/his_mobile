import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/presentation/screens/patient_detail_screen.dart';
import 'package:his_mobile/presentation/widgets/patient_search_field.dart';

/// Màn hình danh sách bệnh nhân theo phòng
class PatientListByRoomScreen extends StatefulWidget {
  final Map<String, dynamic> room;
  const PatientListByRoomScreen({super.key, required this.room});

  @override
  State<PatientListByRoomScreen> createState() => _PatientListByRoomScreenState();
}

class _PatientListByRoomScreenState extends State<PatientListByRoomScreen> {
  final HisApiService _api = HisApiService.instance;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _allPatients = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final roomId = widget.room['ROOM_ID'] ?? widget.room['ID'];
      final roomName = widget.room['ROOM_NAME']?.toString() ?? widget.room['DEPARTMENT_NAME']?.toString() ?? 'Phòng';

      print('📡 Loading BN cho phòng $roomId ($roomName)');

      final result = await _api.getServiceRequests(
        executeRoomId: (roomId is int) ? roomId : 36, // v3.0.105: PKCC = 36
        limit: 100,
      );

      if (mounted) {
        setState(() {
          if (result.success && result.data is Map) {
            final data = result.data as Map;
            if (data['Success'] == true && data['Data'] is List) {
              _allPatients = List<Map<String, dynamic>>.from(data['Data']);
              _patients = _allPatients;
              print('   ✅ Loaded ${_patients.length} BN thật');
            } else {
              _error = 'Không có dữ liệu';
            }
          } else {
            _error = result.message ?? 'Lỗi kết nối';
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomName = widget.room['ROOM_NAME']?.toString() ?? 'Phòng';
    final deptName = widget.room['DEPARTMENT_NAME']?.toString() ?? '';
    final roomCode = widget.room['ROOM_CODE']?.toString() ?? '';
    final roomId = widget.room['ROOM_ID'] ?? widget.room['ID'];

    // Lọc BN theo query (gõ 1 chữ hiện gợi ý)
    List<Map<String, dynamic>> filteredPatients = _patients;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredPatients = _patients.where((p) {
        final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['VIR_PATIENT_NAME'] ?? '').toString().toLowerCase();
        final code = (p['TDL_PATIENT_CODE'] ?? '').toString().toLowerCase();
        final tcode = (p['TDL_TREATMENT_CODE'] ?? '').toString().toLowerCase();
        final hein = (p['TDL_HEIN_CARD_NUMBER'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q) || tcode.contains(q) || hein.contains(q);
      }).toList();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.safePop(),
          tooltip: 'Quay lại',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(roomCode.isEmpty ? roomName : roomCode,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            if (deptName.isNotEmpty)
              Text(deptName,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: Column(
        children: [
          // Header với số lượng BN
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.indigo[700],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TỔNG SỐ BỆNH NHÂN',
                          style: TextStyle(color: Colors.white70, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text('${_patients.length} ca',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      if (roomId != null)
                        Text('ID phòng: $roomId', style: const TextStyle(color: Colors.white60, fontSize: 10)),
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
                  Expanded(
                    child: Text('⚠️ $_error',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 11)),
                  ),
                ],
              ),
            ),

          // v2.38.1: Ô tìm kiếm BN có gợi ý (dùng PatientSearchField)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: PatientSearchField(
              hintText: 'Tìm BN trong phòng (gõ 1 chữ hiện gợi ý)',
              onChanged: (q) {
                setState(() => _searchQuery = q);
              },
              onPatientTap: (p) {
                // Mở chi tiết BN khi bấm gợi ý
                final username = ThongkeAuthService().currentUsername ?? '';
                final deptMap = {
                  'id': widget.room['DEPARTMENT_ID'] ?? 0,
                  'code': widget.room['DEPARTMENT_CODE'] ?? '',
                  'name': widget.room['DEPARTMENT_NAME'] ?? '',
                  'icon': '🏥',
                };
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PatientDetailScreen(
                      patient: p,
                      department: deptMap,
                      username: username,
                    ),
                  ),
                );
              },
            ),
          ),

          // Loading
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )

          // Empty
          else if (_patients.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('Chưa có bệnh nhân',
                        style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Phòng này hiện không có BN cấp cứu',
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
            )

          // Patient list
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filteredPatients.length,
                  itemBuilder: (context, i) => _buildPatientCard(filteredPatients[i], i),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> p, int index) {
    final name = p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['VIR_PATIENT_NAME'] ?? 'N/A';
    final code = p['TDL_PATIENT_CODE'] ?? p['PATIENT_CODE'] ?? '';
    final gender = p['TDL_PATIENT_GENDER_NAME'] ?? '';
    final dob = p['TDL_PATIENT_DOB'];
    final age = _age(dob);
    final stt = p['SERVICE_REQ_STT_ID'] ?? 1;
    final sttName = stt == 1 ? 'CHỜ KHÁM' : stt == 2 ? 'ĐANG KHÁM' : 'HOÀN THÀNH';
    final sttColor = stt == 1 ? Colors.red.shade600 : stt == 2 ? Colors.orange.shade600 : Colors.green.shade600;
    final heinCard = p['TDL_HEIN_CARD_NUMBER']?.toString();
    final treatmentCode = p['TDL_TREATMENT_CODE']?.toString() ?? '';
    final serviceCode = p['SERVICE_REQ_CODE']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: sttColor.withOpacity(0.12), shape: BoxShape.circle),
                  child: Icon(gender.contains('Nữ') ? Icons.female : Icons.male, color: sttColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('$code • ${gender} • ${age}Y',
                          style: const TextStyle(color: Colors.black87, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: sttColor, borderRadius: BorderRadius.circular(8)),
                  child: Text(sttName,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (heinCard != null && heinCard.isNotEmpty)
                    _infoRow('BHYT', heinCard),
                  if (treatmentCode.isNotEmpty)
                    _infoRow('Mã ĐT', treatmentCode),
                  if (serviceCode.isNotEmpty)
                    _infoRow('Mã YL', serviceCode),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final username = ThongkeAuthService().currentUsername ?? '';
                    final deptMap = {
                      'id': widget.room['DEPARTMENT_ID'] ?? 0,
                      'code': widget.room['DEPARTMENT_CODE'] ?? '',
                      'name': widget.room['DEPARTMENT_NAME'] ?? '',
                      'icon': '🏥',
                    };
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PatientDetailScreen(
                          patient: p,
                          department: deptMap,
                          username: username,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.medical_services, size: 16),
                  label: const Text('Phiếu của BN', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    side: const BorderSide(color: Colors.indigo),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text('$label:', style: const TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  int _age(dynamic dob) {
    if (dob == null) return 0;
    try {
      final y = int.parse(dob.toString().substring(0, 4));
      if (y < 1900 || y > 2100) return 0;
      return DateTime.now().year - y;
    } catch (_) { return 0; }
  }
}
