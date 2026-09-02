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
  ///
  /// v3.0.166: Bổ sung - thử TẤT CẢ field (không chỉ 1 field) vì:
  /// - HIS Pro: TDL_PATIENT_NAME (có dấu) vs TDL_PATIENT_UNSIGNED_NAME (không dấu)
  /// - Data 3000: patientName (camelCase, có dấu)
  /// - Public 8080 Laravel: hoten, fullName, name
  /// → Tìm tên có dấu đầu tiên trong tất cả các field
  static String getName(Map<String, dynamic> patient) {
    final primary = _getByField(patient, HisConfigService.instance.config.nameField);

    // Nếu primary có dấu tiếng Việt và không bị lỗi font → return ngay
    if (primary.isNotEmpty && !_hasBrokenChars(primary)) {
      if (_hasVietnameseDiacritics(primary) || _looksLikeForeignName(primary)) {
        return primary;
      }
    }

    // Fallback chain (đảm bảo luôn trả về tên nếu có)
    // v3.0.166: Ưu tiên các field thường CÓ DẤU trước
    final fallbacks = <NameField>[
      NameField.tdlPatientName,        // CÓ DẤU - ưu tiên #1
      NameField.virPatientName,        // HIS Pro field khác
      NameField.tenBenhNhan,           // VN-style field
      NameField.hotenbn,               // HIS cũ
      NameField.tdlPatientUnsignedName, // KHÔNG DẤU - ưu tiên cuối
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

    // v3.0.166: Last-resort fallback - check các field lẻ từ các API khác
    // (Data 3000 camelCase, Public 8080 Laravel)
    const extraFields = [
      'patientName', 'PATIENT_NAME', 'PatientName',
      'virPatientName', 'VIRPatientName',
      'hoten', 'HoTen', 'fullName', 'name', 'nameBN',
      'TEN', 'ten',
    ];
    for (final f in extraFields) {
      final v = patient[f]?.toString() ?? '';
      if (v.isNotEmpty && v != 'null' && v != '-' && !_hasBrokenChars(v)) {
        if (_hasVietnameseDiacritics(v) || _looksLikeForeignName(v)) {
          return v;
        }
        bestUnsignedName ??= v;
      }
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

  /// Lấy 1 field cụ thể - thử cả UPPERCASE và lowercase (port 1425 vs 1429)
  static String _getByField(Map<String, dynamic> p, NameField field) {
    final candidates = _candidatesFor(field);
    for (final c in candidates) {
      // Thử đúng case trước
      var v = p[c]?.toString() ?? '';
      if (v.isNotEmpty && v != 'null' && v != '-') return v;
      // Thử lowercase
      v = p[c.toLowerCase()]?.toString() ?? '';
      if (v.isNotEmpty && v != 'null' && v != '-') return v;
      // Thử UPPERCASE
      v = p[c.toUpperCase()]?.toString() ?? '';
      if (v.isNotEmpty && v != 'null' && v != '-') return v;
    }
    return '';
  }

  /// Tất cả field name có thể có cho 1 NameField
  /// v3.0.166: Mở rộng - thêm field từ Data 3000, Public API (camelCase, snake_case,...)
  /// vì procedure room có thể dùng HIS Pro (1408), Data 3000 (3000), hoặc Public (8080)
  static List<String> _candidatesFor(NameField field) {
    switch (field) {
      case NameField.tdlPatientName:
        return [
          // HIS Pro
          'TDL_PATIENT_NAME', 'tdl_patient_name',
          // Data 3000 / Public (camelCase)
          'patientName', 'PATIENT_NAME', 'PatientName',
          // Public Laravel
          'hoten', 'HoTen', 'fullName', 'name',
        ];
      case NameField.tdlPatientUnsignedName:
        return [
          'TDL_PATIENT_UNSIGNED_NAME', 'tdl_patient_unsigned_name',
          'patientUnsignedName', 'PATIENT_UNSIGNED_NAME',
        ];
      case NameField.virPatientName:
        return [
          'VIR_PATIENT_NAME', 'vir_patient_name',
          'virPatientName', 'VIRPatientName',
        ];
      case NameField.tenBenhNhan:
        return [
          'TEN_BENH_NHAN', 'ten_benh_nhan', 'TEN_BN', 'ten_bn',
          'tenBenhNhan', 'TenBenhNhan',
        ];
      case NameField.hotenbn:
        return [
          'HOTENBN', 'hotenbn', 'HoTenBN', 'hotenBN',
        ];
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
