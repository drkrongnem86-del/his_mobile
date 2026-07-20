// PatientNameHelper v2.76.3
// Helper lấy tên BN theo config user đã chọn (NameField trong Settings)
//
// Thay vì hardcode `'TDL_PATIENT_UNSIGNED_NAME' ?? 'TDL_PATIENT_NAME' ?? ...`,
// dùng helper này để:
// 1. Lấy field ưu tiên theo NameField config (vd: unsigned_name)
// 2. Fallback tự động qua các field khác nếu rỗng
// 3. Áp dụng nhất quán cho MỌI widget hiển thị tên
//
// v2.95.0: Thông minh hơn - ưu tiên tên có dấu tiếng Việt trên tên không dấu
import 'package:his_mobile/core/services/his_config_service.dart';

class PatientNameHelper {
  /// Lấy tên BN ưu tiên theo NameField đã chọn, fallback các field khác
  ///
  /// v2.95.0: Nếu primary là tên không dấu (vd "Tran Thi Chieu"), thử các field
  /// khác trước khi return. Ưu tiên tên có dấu tiếng Việt.
  static String getName(Map<String, dynamic> patient) {
    final primary = _getByField(patient, HisConfigService.instance.config.nameField);

    // Nếu primary có dấu tiếng Việt và không bị lỗi font → return
    if (primary.isNotEmpty && !_hasBrokenChars(primary)) {
      if (_hasVietnameseDiacritics(primary) || _looksLikeForeignName(primary)) {
        return primary;
      }
    }

    // Fallback chain (đảm bảo luôn trả về tên nếu có)
    // v2.95.0: Sắp xếp lại - ưu tiên tên có dấu trước
    final fallbacks = <NameField>[
      NameField.tdlPatientName,        // CÓ DẤU - ưu tiên #1
      NameField.virPatientName,
      NameField.tdlPatientUnsignedName, // KHÔNG DẤU - ưu tiên #3
      NameField.tenBenhNhan,
      NameField.hotenbn,
    ];

    String? bestUnsignedName;
    for (final f in fallbacks) {
      final v = _getByField(patient, f);
      if (v.isEmpty || _hasBrokenChars(v)) continue;
      // Ưu tiên tên có dấu
      if (_hasVietnameseDiacritics(v) || _looksLikeForeignName(v)) {
        return v;
      }
      // Lưu lại tên không dấu đầu tiên tìm được (cuối cùng mới dùng)
      bestUnsignedName ??= v;
    }

    // Nếu có tên không dấu → dùng
    if (bestUnsignedName != null) return bestUnsignedName;

    // v2.84.0: Tất cả field đều lỗi font - trả "BN {treatment_code}" thay vì "BN"
    final tc = (patient['treatment_code'] ?? patient['TDL_TREATMENT_CODE'] ?? '').toString();
    if (tc.isNotEmpty) return 'BN $tc';
    return 'BN';
  }

  /// v2.95.0: Check tên có dấu tiếng Việt không
  static bool _hasVietnameseDiacritics(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạằắẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]').hasMatch(s);
  }

  /// v2.95.0: Check tên có phải tên nước ngoài không (giữ nguyên không dấu)
  /// Tên nước ngoài đặc trưng: có chữ cái không phải tiếng Việt như 'w', 'z', 'f', 'j', 'ng' cuối, 'ph' ở đầu
  static bool _looksLikeForeignName(String s) {
    // Chứa các ký tự đặc trưng tên nước ngoài
    return s.contains(RegExp(r'[wzjWZFJ]')) ||
           s.contains(RegExp(r'\bph[a-z]+', caseSensitive: false)) ||
           s.contains(RegExp(r'\bch[a-z]+', caseSensitive: false));
  }

  /// v2.84.0: Detect ký tự bị lỗi font/mojibake
  /// Các ký tự '!', '?', '�' xuất hiện giữa từ tiếng Việt = response bị corrupt
  static bool _hasBrokenChars(String s) {
    if (s.isEmpty) return false;
    // '!', '?', '�' (U+FFFD) - ký tự thay thế cho byte không đọc được
    if (s.contains('�') || s.contains('!') || s.contains('?')) {
      // Chỉ coi là lỗi nếu ký tự đặc biệt xuất hiện ở giữa (không phải cuối từ)
      // Và có ký tự tiếng Việt xung quanh (chữ hoa ở đầu, chữ thường sau)
      if (RegExp(r'[A-ZÀ-Ỹ][!?�][a-zà-ỹ]').hasMatch(s)) {
        return true;
      }
    }
    return false;
  }

  /// Lấy 1 field cụ thể
  static String _getByField(Map<String, dynamic> p, NameField field) {
    final candidates = _candidatesFor(field);
    for (final c in candidates) {
      final v = p[c]?.toString() ?? '';
      if (v.isNotEmpty && v != 'null' && v != '-') return v;
    }
    return '';
  }

  /// Tất cả field name có thể có cho 1 NameField
  static List<String> _candidatesFor(NameField field) {
    switch (field) {
      case NameField.tdlPatientName:
        return ['TDL_PATIENT_NAME', 'tdl_patient_name'];
      case NameField.tdlPatientUnsignedName:
        return ['TDL_PATIENT_UNSIGNED_NAME', 'tdl_patient_unsigned_name'];
      case NameField.virPatientName:
        return ['VIR_PATIENT_NAME', 'vir_patient_name'];
      case NameField.tenBenhNhan:
        return ['TEN_BENH_NHAN', 'ten_benh_nhan', 'TEN_BN'];
      case NameField.hotenbn:
        return ['HOTENBN', 'hotenbn'];
    }
  }

  /// Trả về Map các giá trị name cho debug/log
  static Map<String, String> debugAll(Map<String, dynamic> patient) {
    final result = <String, String>{};
    for (final f in NameField.values) {
      final v = _getByField(patient, f);
      if (v.isNotEmpty) result[f.key] = v;
    }
    return result;
  }
}
