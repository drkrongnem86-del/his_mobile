// v3.0.9: YTeSoStore - lưu các form Y tế số vào local (SharedPreferences + files)
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class YTeSoStore {
  static final YTeSoStore instance = YTeSoStore._();
  YTeSoStore._();

  static const _kKeyPrefix = 'y_te_so_v1_';

  /// Lưu form data vào SharedPreferences
  Future<void> save({
    required String featureId,
    required String patientCode,
    required String treatmentCode,
    required Map<String, dynamic> data,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _makeKey(featureId, treatmentCode, patientCode);
    final existing = prefs.getStringList(_kKeyPrefix + 'index') ?? [];
    if (!existing.contains(key)) {
      existing.add(key);
      await prefs.setStringList(_kKeyPrefix + 'index', existing);
    }
    final record = {
      'featureId': featureId,
      'patientCode': patientCode,
      'treatmentCode': treatmentCode,
      'data': data,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(key, jsonEncode(record));
  }

  /// Lấy tất cả records (theo treatmentCode)
  Future<List<Map<String, dynamic>>> listByTreatment(String treatmentCode) async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_kKeyPrefix + 'index') ?? [];
    final results = <Map<String, dynamic>>[];
    for (final k in index) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      try {
        final r = jsonDecode(raw) as Map<String, dynamic>;
        if (r['treatmentCode'] == treatmentCode) {
          results.add({
            'key': k,
            ...r,
          });
        }
      } catch (_) {}
    }
    // Sort mới nhất trước
    results.sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
    return results;
  }

  /// Lưu text content vào file tạm (cho EMR push)
  Future<File?> saveToTempFile({
    required String featureId,
    required String patientCode,
    required String content,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/y_te_so_${featureId}_${patientCode}_$timestamp.txt');
      await file.writeAsString(content, encoding: utf8);
      return file;
    } catch (_) {
      return null;
    }
  }

  String _makeKey(String featureId, String treatmentCode, String patientCode) {
    return _kKeyPrefix + '${featureId}_${treatmentCode}_${patientCode}_${DateTime.now().millisecondsSinceEpoch}';
  }
}
