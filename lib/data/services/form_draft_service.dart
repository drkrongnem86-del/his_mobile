// FormDraftService.dart v2.57.0
// Lưu draft (state đang nhập) cho mỗi form phiếu → mở app lại vẫn còn
//
// Key: draft_${phieuCode}_${patientCode}
// Value: JSON { key: value, key_text: text, ... }

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FormDraftService {
  static final FormDraftService instance = FormDraftService._();
  FormDraftService._();

  static const _kPrefix = 'form_draft_v1_';

  String _key(String phieuCode, String patientCode) =>
      '$_kPrefix${phieuCode}_$patientCode';

  /// Save form state
  Future<void> saveDraft(
    String phieuCode,
    String patientCode,
    Map<String, dynamic> values,
    Map<String, List<dynamic>> listValues,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'values': values,
        'listValues': listValues,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_key(phieuCode, patientCode), json.encode(data));
    } catch (_) {}
  }

  /// Load form state nếu có
  Future<({Map<String, dynamic>? values, Map<String, List<dynamic>>? listValues, DateTime? savedAt})?>
      loadDraft(String phieuCode, String patientCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(phieuCode, patientCode));
      if (raw == null) return null;
      final data = json.decode(raw) as Map<String, dynamic>;
      return (
        values: (data['values'] as Map?)?.cast<String, dynamic>() ?? {},
        listValues: (data['listValues'] as Map?)?.map((k, v) =>
            MapEntry(k.toString(), (v as List).toList())) ??
            {},
        savedAt: data['savedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(data['savedAt'])
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Xóa draft sau khi submit thành công
  Future<void> clearDraft(String phieuCode, String patientCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(phieuCode, patientCode));
    } catch (_) {}
  }
}
