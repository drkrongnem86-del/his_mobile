// BenhAnCuScreen v2.37.1 - Bệnh án cũ (lịch sử điều trị)
// Tìm tất cả treatment_code của 1 patient_code qua Data API
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/presentation/widgets/local_patient_search_field.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class BenhAnCuScreen extends StatefulWidget {
  /// patientCode: mã BN (MABN/TDL_PATIENT_CODE) để tra cứu
  final String? patientCode;
  const BenhAnCuScreen({super.key, this.patientCode});

  @override
  State<BenhAnCuScreen> createState() => _BenhAnCuScreenState();
}

class _BenhAnCuScreenState extends State<BenhAnCuScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _treatments = [];
  List<Map<String, dynamic>> _filteredTreatments = [];  // v2.98.6: Filter LOCAL
  bool _loading = false;
  String? _error;

  /// v2.98.6: Filter LOCAL trên list _treatments (giống DepartmentPatientsScreen v2.98.0)
  void _applyLocalFilter() {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filteredTreatments = _treatments;
      return;
    }
    _filteredTreatments = _treatments.where((t) {
      return (t['TDL_PATIENT_NAME'] ?? t['tdl_patient_name'] ?? t['TEN_BENH_NHAN'] ?? '').toString().toLowerCase().contains(q) ||
          (t['TDL_TREATMENT_CODE'] ?? t['treatment_code'] ?? t['MADT'] ?? '').toString().toLowerCase().contains(q) ||
          (t['TDL_PATIENT_CODE'] ?? t['patient_code'] ?? t['MABN'] ?? '').toString().toLowerCase().contains(q) ||
          (t['ICD_NAME'] ?? t['icd_name'] ?? t['CHAN_DOAN'] ?? '').toString().toLowerCase().contains(q) ||
          (t['ICD_CODE'] ?? t['icd_code'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    // v2.98.6: Listener filter LOCAL khi user gõ
    _ctrl.addListener(_onLocalFilterChanged);
    if (widget.patientCode != null && widget.patientCode!.isNotEmpty) {
      _ctrl.text = widget.patientCode!;
      _search();
    }
  }

  /// v2.98.6: Filter LOCAL khi user gõ (setState rebuild list)
  void _onLocalFilterChanged() {
    if (mounted) {
      setState(() {
        _applyLocalFilter();
      });
    }
  }

  Future<void> _search() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) {
      _snack('Nhập mã BN hoặc mã ĐT');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _treatments = [];
    });
    try {
      final dio = Dio(BaseOptions(baseUrl: DataService.instance.baseUrl, connectTimeout: const Duration(seconds: 15)));
      final r = await dio.post('/v1/patient/lich-su-dieu-tri', data: {
        'patientCode': code,
        'length': 50,
      });
      if (r.statusCode == 200) {
        final list = r.data is List ? r.data : (r.data is Map ? (r.data['Data'] as List? ?? []) : []);
        setState(() {
          _treatments = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _applyLocalFilter();  // v2.98.6: Filter LOCAL sau khi load
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'API trả HTTP ${r.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Lỗi: ${e.toString().split("\n").first}\n\n(Gợi ý: kiểm tra endpoint /v1/patient/lich-su-dieu-tri có tồn tại)';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    // v2.98.6: Remove listener
    _ctrl.removeListener(_onLocalFilterChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF5D4037),
        foregroundColor: Colors.white,
        title: const Text('Bệnh án cũ', style: TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(compact: true),
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFFFF3E0),
            child: Column(
              children: [
                LocalPatientSearchField(
                  hintText: 'Tìm BN (gõ để lọc, bấm dòng để tra cứu)...',
                  onPatientTap: (p) {
                    _ctrl.text = (p['TDL_PATIENT_CODE'] ?? p['patient_code'] ?? p['MABN'] ?? '').toString();
                    _search();
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ctrl,
                   onSubmitted: (_) => _search(),
                   // v2.98.6: filter LOCAL ngay khi gõ (không cần Enter)
                   onChanged: (_) => _onLocalFilterChanged(),
                  decoration: InputDecoration(
                    labelText: 'Hoặc nhập trực tiếp mã BN/ĐT',
                    prefixIcon: const Icon(Icons.history),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _search,
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tra cứu tất cả đợt điều trị trước của BN theo mã',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline, size: 48, color: Colors.black45),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                : _filteredTreatments.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.black26),
                            SizedBox(height: 12),
                            Text('Nhập mã để tra bệnh án cũ', style: TextStyle(color: Colors.black45)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _filteredTreatments.length,
                        itemBuilder: (ctx, i) => _buildTreatmentCard(_filteredTreatments[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreatmentCard(Map<String, dynamic> t) {
    String _g(String k1, [String? k2, String? k3]) =>
        (t[k1] ?? t[k2 ?? ''] ?? t[k3 ?? ''] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF5D4037).withOpacity(0.15),
          child: const Icon(Icons.local_hospital, color: Color(0xFF5D4037)),
        ),
        title: Text(_g('TREATMENT_CODE', 'treatment_code', 'MADT'), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_g('IN_TIME', 'IN_DATE').isNotEmpty)
              Text('Vào viện: ${_g('IN_TIME', 'IN_DATE')}'),
            if (_g('OUT_TIME', 'OUT_DATE').isNotEmpty)
              Text('Ra viện: ${_g('OUT_TIME', 'OUT_DATE')}'),
            if (_g('DEPARTMENT_NAME', 'TEN_KHOA').isNotEmpty)
              Text('Khoa: ${_g('DEPARTMENT_NAME', 'TEN_KHOA')}'),
            if (_g('ICD_NAME', 'CHAN_DOAN').isNotEmpty)
              Text('ICD: ${_g('ICD_NAME', 'CHAN_DOAN')}', style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}