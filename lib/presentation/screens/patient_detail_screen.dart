// PatientDetailScreen v2.17 - xem chi tiết 1 BN từ HIS Pro
// - Tab 1: Hồ sơ BN (profile từ HIS Pro + data local)
// - Tab 2: Y lệnh CLS (đã làm + đang chờ)
// - Tab 3: ICD + chẩn đoán
// - Tab 4: Lịch sử phiếu (clinical notes đã ghi local)
//
// Auto-sync: khi mở, nếu có HIS Pro token thì tự pull
// detail + CLS history từ server (chỉ khi BN có marker _DATA_SOURCE='HIS_PRO_LIVE').
import 'package:flutter/material.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'package:his_mobile/data/api/his_pro_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/local/clinical_notes_service.dart';
import 'package:his_mobile/presentation/widgets/clinical_note_screen.dart';
import 'package:his_mobile/presentation/widgets/patient_header.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class PatientDetailScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;
  final String username;

  const PatientDetailScreen({
    super.key,
    required this.patient,
    required this.department,
    required this.username,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _hisPro = HisProService.instance;
  final _notes = ClinicalNotesService.instance;

  Map<String, dynamic>? _serverDetail;
  List<Map<String, dynamic>> _clsHistory = [];
  List<ClinicalNote> _localNotes = [];
  bool _loading = true;
  String _statusMsg = 'Đang tải...';

  String _g(String k1, [String? k2, String? k3]) =>
      (widget.patient[k1] ?? widget.patient[k2 ?? ''] ?? widget.patient[k3 ?? ''] ?? '').toString();

  String get _patientCode {
    final c = _g('TDL_TREATMENT_CODE', 'treatment_code');
    if (c.isNotEmpty) return c;
    return _g('TDL_PATIENT_CODE', 'tdl_patient_code');
  }

  String get _patientName => _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _statusMsg = 'Đang tải dữ liệu...';
    });

    // 1. Load local notes
    final notes = await _notes.getNotesForPatient(widget.username, _patientCode);

    // 2. Nếu đã login HIS Pro → pull detail + CLS history
    bool fromServer = false;
    if (_hisPro.isLoggedIn) {
      final d = await _hisPro.fetchPatientDetail(_patientCode);
      if (d.success && d.patients.isNotEmpty) {
        _serverDetail = d.patients.first;
        fromServer = true;
      }
      final cls = await _hisPro.fetchClsHistory(_patientCode);
      if (cls.success) {
        _clsHistory = cls.patients;
      }
    }

    if (!mounted) return;
    setState(() {
      _localNotes = notes;
      _loading = false;
      _statusMsg = fromServer ? '✓ Đã tải từ HIS Pro' : '⚠ Không thể tải từ HIS Pro (offline?)';
    });
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
  }

  /// Tab 1: Hồ sơ BN
  Widget _tabProfile() {
    final p = widget.patient;
    final dh = _serverDetail?['patient'] as Map?;
    final icon = p['TDL_PATIENT_GENDER_NAME'] == 'Nữ' ? Icons.female : Icons.male;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _serverDetail != null ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _serverDetail != null ? Colors.green.shade300 : Colors.amber.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _serverDetail != null ? Icons.cloud_done : Icons.cloud_off,
                  color: _serverDetail != null ? Colors.green : Colors.amber,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMsg,
                    style: TextStyle(
                      fontSize: 11,
                      color: _serverDetail != null ? Colors.green.shade900 : Colors.amber.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                  tooltip: 'Làm mới',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Avatar + name + basic
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.indigo.shade700,
                  child: Text(
                    _patientName.isNotEmpty ? _patientName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _patientName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.2),
                      ),
                      const SizedBox(height: 4),
                      Wrap(spacing: 4, runSpacing: 4, children: [
                        _badge(Colors.indigo, 'Mã BN: ${_g('TDL_PATIENT_CODE', 'tdl_patient_code')}'),
                        _badge(Colors.teal, 'ĐT: ${_g('TDL_TREATMENT_CODE', 'treatment_code')}'),
                      ]),
                    ],
                  ),
                ),
                Icon(icon, size: 32, color: Colors.indigo.shade700),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Info table - local + server merge
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 3, offset: const Offset(0, 1))],
            ),
            child: Column(
              children: [
                _infoRow('Ngày sinh', _showBest('TDL_PATIENT_DOB', 'DOB'), icon: Icons.cake, prefix: dh),
                _infoRow('Giới tính', _showBest('TDL_PATIENT_GENDER_NAME', 'GENDER'), icon: icon, prefix: dh),
                _infoRow('Số BHYT', _showBest('TDL_HEIN_CARD_NUMBER', 'HEIN_CARD'), icon: Icons.credit_card, prefix: dh),
                _infoRow('SĐT', _showBest('TDL_PATIENT_PHONE', 'PHONE'), icon: Icons.phone, prefix: dh),
                _infoRow('SĐT người nhà', _showBest('TDL_PATIENT_RELATIVE_MOBILE', 'RELATIVE_MOBILE'),
                    icon: Icons.phone_forwarded, prefix: dh),
                _infoRow('Địa chỉ', _showBest('TDL_PATIENT_ADDRESS', 'ADDRESS'), icon: Icons.home, prefix: dh, fullLine: true),
                _infoRow('Ngày vào viện', _showBest('IN_TIME', 'IN_DATE'),
                    icon: Icons.login, prefix: dh),
                _infoRow('Bác sĩ ĐT', _showBest('TDL_TREATMENT_DOCTOR_LOGINNAME', 'DOCTOR_NAME'),
                    icon: Icons.medical_services, prefix: dh),
                _infoRow('Khoa ĐT', _showBest('DEPARTMENT_NAME', 'EXECUTE_DEPARTMENT_NAME'),
                    icon: Icons.local_hospital, prefix: dh),
                _infoRow('ICD hiện tại', _showBest('ICD_NAME', 'ICD'), icon: Icons.healing, color: Colors.red, prefix: dh),
                _infoRow('Mã ICD', _showBest('ICD_CODE', 'ICD_CODE'), icon: Icons.code, prefix: dh),
                _infoRow('Loại ĐT', _showBest('TREATMENT_TYPE_NAME', 'TREATMENT_TYPE'),
                    icon: Icons.medical_information, prefix: dh),
                _infoRow('Loại BN', _showBest('PATIENT_TYPE_NAME', 'PATIENT_TYPE'),
                    icon: Icons.person, prefix: dh),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (dh != null && dh.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F7FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: Colors.teal, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Đã tải thêm từ HIS Pro server (MCH GetTreatment)',
                      style: TextStyle(fontSize: 11, color: const Color(0xFF00695C)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _showBest(String localKey, String serverKey) {
    // Ưu tiên local, fallback server
    final local = widget.patient[localKey];
    final server = _serverDetail?['patient']?[serverKey];
    if (local != null && local.toString().trim().isNotEmpty) return local.toString();
    if (server != null && server.toString().trim().isNotEmpty) return server.toString();
    return '—';
  }

  Widget _infoRow(String label, String value,
      {IconData? icon, Color? color, Map? prefix, bool fullLine = false}) {
    final hasServerValue = prefix != null && prefix.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F4FF))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) Icon(icon, size: 16, color: color ?? Colors.black45),
          if (icon != null) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: value == '—' ? Colors.black26 : Colors.black,
                    fontSize: fullLine ? 12 : 13,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                if (hasServerValue && widget.patient[_localKeyFor(label)] == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: const [
                        Icon(Icons.cloud_done, size: 9, color: Colors.teal),
                        SizedBox(width: 3),
                        Text('từ server', style: TextStyle(color: Colors.teal, fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _localKeyFor(String label) {
    switch (label) {
      case 'Ngày sinh': return 'TDL_PATIENT_DOB';
      case 'Giới tính': return 'TDL_PATIENT_GENDER_NAME';
      case 'Số BHYT': return 'TDL_HEIN_CARD_NUMBER';
      case 'SĐT': return 'TDL_PATIENT_PHONE';
      case 'SĐT người nhà': return 'TDL_PATIENT_RELATIVE_MOBILE';
      case 'Địa chỉ': return 'TDL_PATIENT_ADDRESS';
      case 'Ngày vào viện': return 'IN_TIME';
      case 'ICD hiện tại': return 'ICD_NAME';
      case 'Mã ICD': return 'ICD_CODE';
    }
    return '';
  }

  /// Tab 2: Y lệnh CLS đã/chưa thực hiện
  Widget _tabCls() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_clsHistory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science, size: 64, color: Colors.black26),
              const SizedBox(height: 12),
              const Text('Không có dữ liệu CLS', style: TextStyle(color: Colors.black87, fontSize: 14)),
              const SizedBox(height: 6),
              const Text(
                'Đảm bảo đã bật OpenVPN + đồng bộ từ HIS Pro',
                style: TextStyle(color: Colors.black54, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _clsHistory.length,
      itemBuilder: (ctx, i) {
        final s = _clsHistory[i];
        final type = s['SERVICE_REQ_TYPE_NAME']?.toString() ?? '';
        final code = s['SERVICE_REQ_CODE']?.toString() ?? '';
        final stt = s['SERVICE_REQ_STT_NAME']?.toString() ?? '';
        final instrTime = s['INTRUCTION_TIME']?.toString() ?? '';
        final exeRoom = s['EXECUTE_ROOM_NAME']?.toString() ?? '';
        final note = s['NOTE']?.toString() ?? '';
        final isDone = stt.contains('Đã') || stt.contains('Hoàn');
        final icd = s['ICD_NAME']?.toString() ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDone ? Colors.green.shade200 : Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDone ? Colors.green.shade700 : Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(type.isNotEmpty ? type : 'CLS',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(code.isNotEmpty ? code : '—',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDone ? Colors.green.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isDone ? Colors.green.shade300 : Colors.amber.shade300,
                      ),
                    ),
                    child: Text(
                      stt,
                      style: TextStyle(
                        color: isDone ? Colors.green.shade900 : Colors.amber.shade900,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (instrTime.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 12, color: Colors.black54),
                    const SizedBox(width: 4),
                    Text('Y lệnh: $instrTime', style: const TextStyle(color: Colors.black87, fontSize: 11)),
                  ],
                ),
              if (exeRoom.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.room_preferences, size: 12, color: Colors.black54),
                    const SizedBox(width: 4),
                    Text('Phòng: $exeRoom', style: const TextStyle(color: Colors.black87, fontSize: 11)),
                  ],
                ),
              if (icd.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('📋 $icd', style: const TextStyle(color: Colors.red, fontSize: 11)),
                ),
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('💬 $note', style: const TextStyle(color: Colors.black87, fontSize: 10, fontStyle: FontStyle.italic)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Tab 3: ICD + chẩn đoán
  Widget _tabIcd() {
    final icdFromServer = (_serverDetail?['icd'] as List?) ?? [];
    final icdFromLocal = <String, int>{};
    for (final n in _localNotes) {
      for (final v in n.data.values) {
        final s = v.toString().trim();
        if (RegExp(r'^[A-Z]\d{2}(\.\d{1,2})?$').hasMatch(s)) {
          icdFromLocal[s] = (icdFromLocal[s] ?? 0) + 1;
        }
      }
    }
    final allIcdCodes = <String>{};
    for (final m in icdFromServer) {
      final code = (m as Map)['ICD_CODE'] ?? (m)['CODE'] ?? '';
      if (code.toString().isNotEmpty) allIcdCodes.add(code.toString());
    }
    allIcdCodes.addAll(icdFromLocal.keys);

    if (allIcdCodes.isEmpty) {
      return const Center(child: Text('Chưa có ICD code nào'));
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: allIcdCodes.map((code) {
        final fromServer = icdFromServer.firstWhere(
          (e) => (e['ICD_CODE'] ?? e['CODE'] ?? '').toString() == code,
          orElse: () => null,
        );
        final localCount = icdFromLocal[code] ?? 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: Text(code, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (fromServer != null && fromServer['ICD_NAME'] != null)
                      Text(fromServer['ICD_NAME'].toString(),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    if (localCount > 0)
                      Row(
                        children: [
                          const Icon(Icons.history, size: 10, color: Colors.indigo),
                          const SizedBox(width: 3),
                          Text('Đã ghi trong $localCount phiếu local',
                              style: const TextStyle(color: Colors.indigo, fontSize: 10, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (fromServer != null)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: Colors.teal.shade300)),
                            child: const Text('HIS Pro',
                                style: TextStyle(color: Color(0xFF00695C), fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        if (localCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: Colors.indigo.shade300)),
                            child: const Text('App',
                                style: TextStyle(color: Colors.indigo, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Tab 4: Phiếu local đã ghi
  Widget _tabNotes() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_localNotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_add, size: 56, color: Colors.black26),
            const SizedBox(height: 8),
            const Text('Chưa ghi phiếu nào cho BN này',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _localNotes.length,
      itemBuilder: (ctx, i) {
        final n = _localNotes[i];
        final accent = Color(n.type.colorValue);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withOpacity(0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClinicalNoteScreen(
                type: n.type, patient: widget.patient, department: widget.department,
                fields: const [],
              ))).then((_) => _load()),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                      child: Text(n.type.icon, style: const TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.type.label, style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
                          Text(_formatTime(n.createdAt), style: const TextStyle(color: Colors.black54, fontSize: 10)),
                          if (n.note.isNotEmpty)
                            Text('📝 ${n.note}',
                                style: const TextStyle(color: Colors.black87, fontSize: 10, fontStyle: FontStyle.italic),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.black26),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _badge(Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  /// Check note có thể sync lên HIS Pro hay không
  bool _canSyncNote(ClinicalNote note) {
    const syncable = ['vitals', 'paraclinical', 'infusion', 'care_sheet', 'prescription'];
    return syncable.contains(note.type.key);
  }

  Future<void> _syncAllNotes() async {
    if (!_hisPro.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần đăng nhập HIS Pro trước (bấm 🔄 ở banner)')),
      );
      return;
    }

    final syncable = _localNotes.where(_canSyncNote).toList();
    if (syncable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có phiếu nào sync được')),
      );
      return;
    }

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(strokeWidth: 3),
              SizedBox(width: 16),
              Text('Đang đồng bộ phiếu lên HIS Pro...'),
            ],
          ),
        ),
      ),
    );

    int success = 0;
    int fail = 0;
    final errors = <String>[];
    for (final n in syncable) {
      final res = await _hisPro.syncNoteToHisPro(
        treatmentCode: _patientCode,
        data: n.data,
        noteType: n.type.key,
      );
      if (res.success) {
        success++;
      } else {
        fail++;
        errors.add('${n.type.label}: ${res.message}');
      }
    }

    if (!mounted) return;
    Navigator.pop(context); // close progress

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(fail == 0 ? Icons.check_circle : Icons.warning_amber, color: fail == 0 ? Colors.green : Colors.orange, size: 22),
            const SizedBox(width: 6),
            Text('Đồng bộ ${success + fail} phiếu', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (success > 0)
                Row(children: [
                  const Icon(Icons.check, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text('Thành công: $success phiếu', style: const TextStyle(color: Colors.green, fontSize: 13)),
                ]),
              if (fail > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    const Icon(Icons.close, color: Colors.red, size: 16),
                    const SizedBox(width: 4),
                    Text('Thất bại: $fail phiếu', style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ]),
                ),
              const SizedBox(height: 8),
              if (errors.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: errors.take(5).map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $e', style: const TextStyle(fontSize: 11)),
                    )).toList(),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Lưu ý: HIS Pro endpoint có thể khác phiên bản. Lỗi thường do schema chưa khớp — sửa theo doc API.',
                style: TextStyle(fontSize: 10, color: Colors.black54, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Chi tiết BN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          if (_localNotes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Đồng bộ phiếu local lên HIS Pro',
              onPressed: _syncAllNotes,
            ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Làm mới', onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Hồ sơ'),
            Tab(text: 'CLS'),
            Tab(text: 'ICD'),
            Tab(text: 'Phiếu local'),
          ],
        ),
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(department: widget.department['name']?.toString()),
          PatientHeader(patient: widget.patient, department: widget.department, accent: const Color(0xFF1565C0)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tab,
                    children: [
                      _tabProfile(),
                      _tabCls(),
                      _tabIcd(),
                      _tabNotes(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
