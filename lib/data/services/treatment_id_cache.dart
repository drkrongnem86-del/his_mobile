// TreatmentIdCache v3.0.3 - Cache mapping treatment_code → treatment_id
// Lưu trong SharedPreferences, share giữa các lần mở app
// Mục đích: BS không cần fetch từ HIS Pro mỗi lần (chậm, dễ fail 401)
//
// Cache key: "treatment_id_cache_v1"
// Value: JSON { "000002126215": 12345, "000002120047": 67890, ... }

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TreatmentIdCache {
  static const String _key = 'treatment_id_cache_v1';
  static TreatmentIdCache? _instance;
  static TreatmentIdCache get instance => _instance ??= TreatmentIdCache();

  final Map<String, int> _cache = {};
  bool _loaded = false;

  /// Lấy treatment_id từ cache (null nếu chưa có)
  int? get(String treatmentCode) {
    if (treatmentCode.isEmpty) return null;
    return _cache[treatmentCode];
  }

  /// Lưu mapping
  Future<void> set(String treatmentCode, int treatmentId) async {
    if (treatmentCode.isEmpty || treatmentId <= 0) return;
    _cache[treatmentCode] = treatmentId;
    await _save();
  }

  /// Lưu nhiều mapping cùng lúc
  Future<void> setAll(Map<String, int> mappings) async {
    _cache.addAll(mappings);
    await _save();
  }

  /// Xóa 1 mapping
  Future<void> remove(String treatmentCode) async {
    _cache.remove(treatmentCode);
    await _save();
  }

  /// Xóa tất cả
  Future<void> clear() async {
    _cache.clear();
    await _save();
  }

  /// Lấy tất cả mapping
  Map<String, int> get all => Map.unmodifiable(_cache);

  /// Load từ SharedPreferences
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _cache.clear();
        map.forEach((k, v) {
          if (v is int) {
            _cache[k] = v;
          } else if (v is String) {
            final i = int.tryParse(v);
            if (i != null) _cache[k] = i;
          }
        });
      }
    } catch (e) {
      _cache.clear();
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_cache));
    } catch (_) {}
  }
}
