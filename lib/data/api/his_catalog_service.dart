// HisCatalogService.dart v2.53.0
// Load danh mục CLS (dịch vụ), thuốc, vật tư từ HIS Pro thật (port 1408)
// Replace hardcoded 65-item ClsCatalog với data thật từ BV (~33k services)
//
// Cache local: SharedPreferences (JSON encoded list) - load lần đầu, refresh sau 24h
// Search: filter by code/name/group
//
// Endpoints dùng:
//   api/HisService/Get     -> CLS (SERVICE_TYPE_ID: 1=Kham, 2=XN, 3=CDHA, 4=TT, 5=TDCN, 6=Thuoc, 7=VT, 8=Giuong, ...)
//   api/HisMedicine/Get    -> Thuốc (ACTIVE_INGR_BHYT_NAME, MEDICINE_TYPE_NAME)
//   api/HisMaterial/Get    -> Vật tư
//   api/HisIcd/Get         -> ICD (mã bệnh) - 174+ items
//   api/HisServiceType/Get -> Loại dịch vụ (lookup)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'thongke_auth_service.dart';

class CatalogItem {
  final int id;
  final String code;
  final String name;
  final int? typeId;          // SERVICE_TYPE_ID / MEDICINE_TYPE_ID
  final String? typeCode;     // SERVICE_TYPE_CODE / MEDICINE_TYPE_CODE
  final String? typeName;     // SERVICE_TYPE_NAME
  final String? heinCode;     // HEIN_SERVICE_BHYT_CODE
  final double? price;        // PRICE
  final String? unit;         // SERVICE_UNIT_NAME
  final String? packing;      // PACKAGE_NUMBER / SPECIAL_PACKAGE

  const CatalogItem({
    required this.id,
    required this.code,
    required this.name,
    this.typeId,
    this.typeCode,
    this.typeName,
    this.heinCode,
    this.price,
    this.unit,
    this.packing,
  });

  factory CatalogItem.fromService(Map<String, dynamic> j) => CatalogItem(
        id: (j['ID'] ?? 0) as int,
        code: (j['SERVICE_CODE'] ?? '').toString(),
        name: (j['SERVICE_NAME'] ?? '').toString(),
        typeId: (j['SERVICE_TYPE_ID'] is int)
            ? j['SERVICE_TYPE_ID']
            : int.tryParse(j['SERVICE_TYPE_ID']?.toString() ?? ''),
        heinCode: j['HEIN_SERVICE_BHYT_CODE']?.toString(),
        price: _toDouble(j['PACS_PRICE'] ?? j['PRICE'] ?? j['VAT_SERVICE_PRICE']),
        unit: j['SERVICE_UNIT_NAME']?.toString(),
      );

  factory CatalogItem.fromMedicine(Map<String, dynamic> j) => CatalogItem(
        id: (j['ID'] ?? 0) as int,
        code: (j['MEDICINE_TYPE_CODE'] ?? '').toString(),
        name: (j['MEDICINE_TYPE_NAME'] ?? '').toString(),
        typeId: (j['MEDICINE_TYPE_ID'] is int)
            ? j['MEDICINE_TYPE_ID']
            : int.tryParse(j['MEDICINE_TYPE_ID']?.toString() ?? ''),
        unit: j['SERVICE_UNIT_NAME']?.toString(),
        packing: j['PACKAGE_NUMBER']?.toString(),
        price: _toDouble(j['IMP_PRICE'] ?? j['IMP_VAT_PRICE']),
      );

  factory CatalogItem.fromMaterial(Map<String, dynamic> j) => CatalogItem(
        id: (j['ID'] ?? 0) as int,
        code: (j['MATERIAL_TYPE_CODE'] ?? '').toString(),
        name: (j['MATERIAL_TYPE_NAME'] ?? '').toString(),
        typeId: (j['MATERIAL_TYPE_ID'] is int)
            ? j['MATERIAL_TYPE_ID']
            : int.tryParse(j['MATERIAL_TYPE_ID']?.toString() ?? ''),
        unit: j['SERVICE_UNIT_NAME']?.toString(),
        packing: j['PACKING_TYPE_NAME']?.toString(),
        price: _toDouble(j['IMP_PRICE']),
      );

  factory CatalogItem.fromIcd(Map<String, dynamic> j) => CatalogItem(
        id: (j['ID'] ?? 0) as int,
        code: (j['ICD_CODE'] ?? '').toString(),
        name: (j['ICD_NAME'] ?? '').toString(),
        unit: j['BHYT_NAME']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'typeId': typeId,
        'typeCode': typeCode,
        'typeName': typeName,
        'heinCode': heinCode,
        'price': price,
        'unit': unit,
        'packing': packing,
      };

  factory CatalogItem.fromJson(Map<String, dynamic> j) => CatalogItem(
        id: (j['id'] ?? 0) as int,
        code: (j['code'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        typeId: j['typeId'] is int ? j['typeId'] : int.tryParse(j['typeId']?.toString() ?? ''),
        typeCode: j['typeCode']?.toString(),
        typeName: j['typeName']?.toString(),
        heinCode: j['heinCode']?.toString(),
        price: _toDouble(j['price']),
        unit: j['unit']?.toString(),
        packing: j['packing']?.toString(),
      );

  @override
  String toString() => '$code - $name';

  /// Hiển thị cho SearchableDropdown
  String get displayLabel {
    final p = price != null && price! > 0 ? ' · ${_formatPrice(price!)}' : '';
    return '$code · $name$p';
  }

  String _formatPrice(double p) {
    if (p >= 1000000) return '${(p / 1000000).toStringAsFixed(1)}tr';
    if (p >= 1000) return '${(p / 1000).toStringAsFixed(0)}k';
    return p.toStringAsFixed(0);
  }
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class HisCatalogService {
  static final HisCatalogService instance = HisCatalogService._();
  HisCatalogService._();

  // Service-Type lookup (ID -> Code/Name)
  static const Map<int, (String, String)> serviceTypeNames = {
    1: ('KH', 'Khám'),
    2: ('XN', 'Xét nghiệm'),
    3: ('HA', 'Chẩn đoán hình ảnh'),
    4: ('TT', 'Thủ thuật'),
    5: ('CN', 'Thăm dò chức năng'),
    6: ('TH', 'Thuốc'),
    7: ('VT', 'Vật tư'),
    8: ('GI', 'Giường'),
    9: ('NS', 'Nội soi'),
    10: ('SA', 'Siêu âm'),
    11: ('PT', 'Phẫu thuật'),
    12: ('CL', 'Khác'),
    13: ('PH', 'Phục hồi chức năng'),
    14: ('MA', 'Máu'),
    15: ('GB', 'Giải phẫu bệnh lý'),
    16: ('AN', 'Suất ăn'),
    17: ('CG', 'Cấp giấy tờ'),
  };

  static String typeName(int id) {
    final t = serviceTypeNames[id];
    return t != null ? t.$2 : 'Khác';
  }

  static String typeCode(int id) {
    final t = serviceTypeNames[id];
    return t != null ? t.$1 : 'CL';
  }

  // ============ Cache keys ============
  static const String _kServiceCache = 'cat_services_v1';
  static const String _kMedicineCache = 'cat_medicines_v1';
  static const String _kMaterialCache = 'cat_materials_v1';
  static const String _kIcdCache = 'cat_icd_v1';
  static const String _kLastUpdate = 'cat_last_update_v1';
  static const int _kMaxCacheAgeMs = 24 * 60 * 60 * 1000; // 24 giờ

  late Dio _dio;
  bool _initialized = false;

  // ============ In-memory cache ============
  List<CatalogItem> _services = [];
  List<CatalogItem> _medicines = [];
  List<CatalogItem> _materials = [];
  List<CatalogItem> _icds = [];

  List<CatalogItem> get services => _services;
  List<CatalogItem> get medicines => _medicines;
  List<CatalogItem> get materials => _materials;
  List<CatalogItem> get icds => _icds;

  /// CLS trong khoa Cấp Cứu (Type: Khám 1, XN 2, CDHA 3, TT 4, TDCN 5, SA 10, NS 9)
  List<CatalogItem> get clinicalServices => _services
      .where((s) => [1, 2, 3, 4, 5, 9, 10].contains(s.typeId))
      .toList();

  Future<void> init() async {
    if (_initialized) return;
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'User-Agent': 'HIS-Mobile/2.14.1',
        '___ipAddress': '127.0.0.1',
      },
    ));
    _initialized = true;
    await _loadCache();
    if (_shouldRefresh()) {
      // Background refresh - không block UI
      unawaited(refreshAll().catchError((e) {
        debugPrint('Catalog refresh error: $e');
      }));
    }
  }

  bool _shouldRefresh() {
    if (_services.isEmpty && _medicines.isEmpty && _icds.isEmpty) return true;
    // Check timestamp from SharedPreferences
    // Always refresh if catalog empty or stale
    return DateTime.now().millisecondsSinceEpoch - _lastUpdate > _kMaxCacheAgeMs;
  }

  int _lastUpdate = 0;

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastUpdate = prefs.getInt(_kLastUpdate) ?? 0;

      _services = _decodeCache(prefs.getString(_kServiceCache));
      _medicines = _decodeCache(prefs.getString(_kMedicineCache));
      _materials = _decodeCache(prefs.getString(_kMaterialCache));
      _icds = _decodeCache(prefs.getString(_kIcdCache));

      debugPrint('Catalog cache: services=${_services.length} '
          'medicines=${_medicines.length} '
          'materials=${_materials.length} '
          'icds=${_icds.length}');
    } catch (e) {
      debugPrint('Load cache error: $e');
    }
  }

  List<CatalogItem> _decodeCache(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = json.decode(jsonStr) as List<dynamic>;
      return list.map((e) => CatalogItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCache(String key, List<CatalogItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final list = items.map((e) => e.toJson()).toList();
    await prefs.setString(key, json.encode(list));
  }

  /// Refresh tất cả catalog từ HIS Pro. Có thể lâu (30-60s), background-only.
  Future<void> refreshAll() async {
    final token = ThongkeAuthService.instance.hisProToken;
    if ((token ?? '').isEmpty) {
      debugPrint('Cannot refresh catalog: missing HIS Pro token');
      return;
    }
    await _loadFromApi('api/HisService/Get', _kServiceCache, CatalogItem.fromService);
    await _loadFromApi('api/HisMedicine/Get', _kMedicineCache, CatalogItem.fromMedicine);
    await _loadFromApi('api/HisMaterial/Get', _kMaterialCache, CatalogItem.fromMaterial);
    await _loadFromApi('api/HisIcd/Get', _kIcdCache, CatalogItem.fromIcd);

    _lastUpdate = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastUpdate, _lastUpdate);
    debugPrint('✅ Catalog refreshed: services=${_services.length} medicines=${_medicines.length} icds=${_icds.length}');
  }

  /// Load 1 endpoint với pagination (limit=500 để nhanh)
  Future<void> _loadFromApi(
      String endpoint, String cacheKey, CatalogItem Function(Map<String, dynamic>) parse) async {
    final token = ThongkeAuthService.instance.hisProToken;
    final all = <CatalogItem>[];
    int start = 0;
    const int limit = 500;
    bool hasMore = true;
    while (hasMore) {
      try {
        final body = {
          'CommonParam': {'LanguageCode': 'VI', 'Start': start, 'Limit': limit},
          'ApiData': {'IS_ACTIVE': 1}
        };
        final encoded = base64.encode(utf8.encode(json.encode(body)));
        final resp = await _dio.get(
          '${ThongkeAuthService.hisProBaseUrl}/$endpoint?param=$encoded',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        if (resp.statusCode != 200) break;
        final d = resp.data is Map ? resp.data as Map : null;
        if (d == null) break;
        final success = d['Success'];
        if (success != true) break;
        final data = d['Data'] as List?;
        if (data == null || data.isEmpty) break;
        for (final item in data) {
          if (item is Map) {
            try {
              all.add(parse(Map<String, dynamic>.from(item)));
            } catch (_) {}
          }
        }
        if (data.length < limit) {
          hasMore = false;
        } else {
          start += limit;
        }
        // Cap at 5000 items to avoid memory bloat
        if (all.length >= 5000) hasMore = false;
      } catch (e) {
        debugPrint('Catalog $endpoint error: $e');
        hasMore = false;
      }
    }
    if (all.isNotEmpty) {
      await _saveCache(cacheKey, all);
      if (cacheKey == _kServiceCache) _services = all;
      if (cacheKey == _kMedicineCache) _medicines = all;
      if (cacheKey == _kMaterialCache) _materials = all;
      if (cacheKey == _kIcdCache) _icds = all;
    }
  }

  /// v3.0.32: Check nếu tất cả catalog trống
  bool isEmpty() {
    return _services.isEmpty && _medicines.isEmpty && _materials.isEmpty && _icds.isEmpty;
  }

  // ============ Search ============
  List<CatalogItem> searchServices(String query, {int? typeId, int limit = 200}) {
    final q = query.trim().toLowerCase();
    final filtered = _services.where((s) {
      if (typeId != null && s.typeId != typeId) return false;
      if (q.isEmpty) return true;
      return s.code.toLowerCase().contains(q) ||
          s.name.toLowerCase().contains(q) ||
          (s.heinCode ?? '').toLowerCase().contains(q);
    }).toList();
    filtered.sort((a, b) => a.code.compareTo(b.code));
    return filtered.take(limit).toList();
  }

  List<CatalogItem> searchMedicines(String query, {int limit = 200}) {
    final q = query.trim().toLowerCase();
    final filtered = _medicines.where((s) {
      if (q.isEmpty) return true;
      return s.code.toLowerCase().contains(q) ||
          s.name.toLowerCase().contains(q);
    }).toList();
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered.take(limit).toList();
  }

  List<CatalogItem> searchMaterials(String query, {int limit = 200}) {
    final q = query.trim().toLowerCase();
    final filtered = _materials.where((s) {
      if (q.isEmpty) return true;
      return s.code.toLowerCase().contains(q) ||
          s.name.toLowerCase().contains(q);
    }).toList();
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered.take(limit).toList();
  }

  List<CatalogItem> searchIcd(String query, {int limit = 200}) {
    final q = query.trim();
    // v2.75.5: Diacritic-insensitive search (gõ "tang ha" match "Tăng huyết áp")
    final noDiacritics = removeDiacritics(q.toLowerCase());
    final filtered = _icds.where((s) {
      if (q.isEmpty) return true;
      // Match exact (case-insensitive) hoặc diacritic-insensitive
      if (s.code.toLowerCase().contains(q.toLowerCase())) return true;
      if (s.name.toLowerCase().contains(q.toLowerCase())) return true;
      if (noDiacritics.isNotEmpty) {
        final nameNoDiac = removeDiacritics(s.name.toLowerCase());
        if (nameNoDiac.contains(noDiacritics)) return true;
      }
      return false;
    }).toList();
    // Sắp xếp: exact match trước, sau đó theo code
    filtered.sort((a, b) {
      final aExact = a.code.toLowerCase() == q.toLowerCase() ||
          a.name.toLowerCase().startsWith(q.toLowerCase());
      final bExact = b.code.toLowerCase() == q.toLowerCase() ||
          b.name.toLowerCase().startsWith(q.toLowerCase());
      if (aExact != bExact) return aExact ? -1 : 1;
      return a.code.compareTo(b.code);
    });
    return filtered.take(limit).toList();
  }
}
