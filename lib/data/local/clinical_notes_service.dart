// Local storage cho clinical notes (sinh hiệu, đơn thuốc, tờ điều trị, CLS, bàn giao, phiếu chăm sóc).
// Tất cả data lưu trong SharedPreferences 1 key JSON array, keyed theo username để multi-user.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Loại clinical note (key ngắn cho dễ filter)
enum ClinicalNoteType {
  vitalSigns('vitals', 'Phiếu theo dõi sinh hiệu', '❤️', 0xFFE53935),
  prescription('prescription', 'Cho thuốc / Đơn thuốc', '💊', 0xFFC62828),
  treatmentSheet('treatment_sheet', 'Tờ điều trị', '📝', 0xFF1565C0),
  paraclinical('paraclinical', 'Chỉ định / Kết quả CLS', '🧪', 0xFF7B1FA2),
  handoff('handoff', 'Bàn giao ca / Bàn giao BN', '🌙', 0xFF283593),
  careSheet('care_sheet', 'Phiếu chăm sóc', '💗', 0xFFD81B60),
  infusion('infusion', 'Phiếu truyền dịch', '💧', 0xFF0277BD),
  procedure('procedure', 'Chỉ định thủ thuật/PT', '🩺', 0xFF2E7D32),
  consult('consult', 'Phiếu khám / Hội chẩn', '📋', 0xFF455A64),
  pharmacyDisclosure('pharmacy_disc', 'Phiếu công khai thuốc', '🏷️', 0xFFAD1457),
  medNotDone('med_not_done', 'Tổng hợp thuốc không thực hiện', '❌', 0xFF6A1B9A),
  orderExecution('order_exec', 'Thực hiện y lệnh', '✅', 0xFF00838F),
  allergyHistory('allergy', 'Tiền sử dị ứng', '🚫', 0xFFD84315),
  wardRounds('ward_rounds', 'Đi buồng (BS)', '🩺', 0xFF1B5E20),
  headNurseRounds('head_nurse_rounds', 'ĐD trưởng đi buồng', '👩‍⚕️', 0xFFC2185B),
  postOp('post_op', 'Theo dõi sau mổ', '📄', 0xFF5E35B1),
  nutritionScreening('nutri_screen', 'Sàng lọc dinh dưỡng', '🥗', 0xFFE65100),
  nutritionAssessment('nutri_assess', 'Đánh giá dinh dưỡng', '🍱', 0xFFEF6C00),
  barcodeHistory('barcode_log', 'Lịch sử quét Barcode', '📊', 0xFF455A64),
  medExecution('med_exec', 'Phiếu thực hiện thuốc', '⬇', 0xFF00695C);

  final String key;
  final String label;
  final String icon;
  final int colorValue;
  const ClinicalNoteType(this.key, this.label, this.icon, this.colorValue);

  static ClinicalNoteType fromKey(String k) =>
      ClinicalNoteType.values.firstWhere((t) => t.key == k, orElse: () => ClinicalNoteType.treatmentSheet);
}

/// 1 phiếu ghi nhận lâm sàng
class ClinicalNote {
  final String id;
  final ClinicalNoteType type;
  final String patientCode;
  final String patientName;
  final String departmentCode;
  final String departmentName;
  final Map<String, dynamic> data;
  final String note;
  final String createdBy;
  final DateTime createdAt;

  ClinicalNote({
    required this.id,
    required this.type,
    required this.patientCode,
    required this.patientName,
    required this.departmentCode,
    required this.departmentName,
    required this.data,
    required this.note,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.key,
        'patientCode': patientCode,
        'patientName': patientName,
        'departmentCode': departmentCode,
        'departmentName': departmentName,
        'data': data,
        'note': note,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ClinicalNote.fromJson(Map j) => ClinicalNote(
        id: j['id'] as String,
        type: ClinicalNoteType.fromKey(j['type'] as String? ?? 'treatment_sheet'),
        patientCode: j['patientCode'] as String? ?? '',
        patientName: j['patientName'] as String? ?? '',
        departmentCode: j['departmentCode'] as String? ?? '',
        departmentName: j['departmentName'] as String? ?? '',
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
        note: j['note'] as String? ?? '',
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Service lưu/đọc clinical notes. Mỗi user có 1 danh sách riêng (key theo username).
class ClinicalNotesService {
  static final ClinicalNotesService instance = ClinicalNotesService._();
  ClinicalNotesService._();

  static const _keyPrefix = 'clinical_notes_v1_';

  String _userKey(String username) => '$_keyPrefix${username.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "_")}';

  Future<List<ClinicalNote>> _readAll(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey(username));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((j) => ClinicalNote.fromJson(j as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(String username, List<ClinicalNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(notes.map((n) => n.toJson()).toList());
    await prefs.setString(_userKey(username), raw);
  }

  /// Lưu 1 note mới
  Future<void> addNote(String username, ClinicalNote note) async {
    final all = await _readAll(username);
    all.insert(0, note); // newest first
    await _writeAll(username, all);
  }

  /// Lấy tất cả notes của 1 BN (theo patientCode)
  Future<List<ClinicalNote>> getNotesForPatient(String username, String patientCode) async {
    final all = await _readAll(username);
    return all.where((n) => n.patientCode == patientCode).toList();
  }

  /// Lấy notes của 1 BN, lọc theo type
  Future<List<ClinicalNote>> getNotesForPatientAndType(
      String username, String patientCode, ClinicalNoteType type) async {
    final all = await _readAll(username);
    return all.where((n) => n.patientCode == patientCode && n.type == type).toList();
  }

  /// Lấy notes theo type, all BN
  Future<List<ClinicalNote>> getNotesByType(String username, ClinicalNoteType type) async {
    final all = await _readAll(username);
    return all.where((n) => n.type == type).toList();
  }

  /// Đếm notes theo type cho 1 BN
  Future<int> countForPatientAndType(
      String username, String patientCode, ClinicalNoteType type) async {
    final all = await _readAll(username);
    return all.where((n) => n.patientCode == patientCode && n.type == type).length;
  }

  /// Xoá 1 note theo id
  Future<void> deleteNote(String username, String id) async {
    final all = await _readAll(username);
    all.removeWhere((n) => n.id == id);
    await _writeAll(username, all);
  }

  /// Tổng số notes của 1 user (cho badge counter)
  Future<int> totalCount(String username) async {
    final all = await _readAll(username);
    return all.length;
  }
}
