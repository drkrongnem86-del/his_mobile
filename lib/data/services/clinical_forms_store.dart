// Phiếu đã lập — lưu local, sẵn sàng sync lên cổng EMR
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SavedForm {
  final String id;            // UUID
  final String formId;        // form_id từ FormDef
  final String patientCode;   // mã BN
  final String patientName;   // tên BN (snapshot)
  final String departmentId;  // khoa
  final String createdBy;     // username
  final String createdByName; // họ tên BS
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> data;       // form fields
  final bool signed;          // đã ký
  final String? signedBy;     // tên ký
  final DateTime? signedAt;
  final String syncStatus;    // 'local', 'queued', 'synced', 'error'
  final String? syncError;
  final String? externalId;   // ID từ Data EMR portal

  const SavedForm({
    required this.id,
    required this.formId,
    required this.patientCode,
    required this.patientName,
    required this.departmentId,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    required this.data,
    this.signed = false,
    this.signedBy,
    this.signedAt,
    this.syncStatus = 'local',
    this.syncError,
    this.externalId,
  });

  SavedForm copyWith({
    String? id,
    String? formId,
    String? patientCode,
    String? patientName,
    String? departmentId,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? data,
    bool? signed,
    String? signedBy,
    DateTime? signedAt,
    String? syncStatus,
    String? syncError,
    String? externalId,
  }) => SavedForm(
        id: id ?? this.id,
        formId: formId ?? this.formId,
        patientCode: patientCode ?? this.patientCode,
        patientName: patientName ?? this.patientName,
        departmentId: departmentId ?? this.departmentId,
        createdBy: createdBy ?? this.createdBy,
        createdByName: createdByName ?? this.createdByName,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        data: data ?? this.data,
        signed: signed ?? this.signed,
        signedBy: signedBy ?? this.signedBy,
        signedAt: signedAt ?? this.signedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        syncError: syncError,
        externalId: externalId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'formId': formId,
        'patientCode': patientCode,
        'patientName': patientName,
        'departmentId': departmentId,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'data': data,
        'signed': signed,
        'signedBy': signedBy,
        'signedAt': signedAt?.toIso8601String(),
        'syncStatus': syncStatus,
        'syncError': syncError,
        'externalId': externalId,
      };

  factory SavedForm.fromJson(Map<String, dynamic> j) => SavedForm(
        id: j['id'] as String,
        formId: j['formId'] as String,
        patientCode: j['patientCode'] as String? ?? '',
        patientName: j['patientName'] as String? ?? '',
        departmentId: j['departmentId'] as String? ?? '',
        createdBy: j['createdBy'] as String? ?? '',
        createdByName: j['createdByName'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? {},
        signed: j['signed'] as bool? ?? false,
        signedBy: j['signedBy'] as String?,
        signedAt: j['signedAt'] != null ? DateTime.tryParse(j['signedAt'] as String) : null,
        syncStatus: j['syncStatus'] as String? ?? 'local',
        syncError: j['syncError'] as String?,
        externalId: j['externalId'] as String?,
      );
}

class ClinicalFormsStore {
  static const String _key = 'saved_forms_v1';
  static ClinicalFormsStore? _instance;
  List<SavedForm> _items = [];
  bool _loaded = false;

  static ClinicalFormsStore get instance => _instance ??= ClinicalFormsStore();

  List<SavedForm> get all => List.unmodifiable(_items);

  List<SavedForm> byPatient(String patientCode) =>
      _items.where((f) => f.patientCode == patientCode).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<SavedForm> byForm(String formId) =>
      _items.where((f) => f.formId == formId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<SavedForm> bySyncStatus(String status) =>
      _items.where((f) => f.syncStatus == status).toList();

  SavedForm? byId(String id) {
    for (final f in _items) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _items = list.map(SavedForm.fromJson).toList();
      }
    } catch (e) {
      _items = [];
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_items.map((f) => f.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<SavedForm> add(SavedForm form) async {
    _items.add(form);
    await _save();
    return form;
  }

  Future<void> update(SavedForm form) async {
    final i = _items.indexWhere((f) => f.id == form.id);
    if (i >= 0) {
      _items[i] = form;
      await _save();
    }
  }

  Future<void> remove(String id) async {
    _items.removeWhere((f) => f.id == id);
    await _save();
  }

  Future<void> markSigned(String id, String signedBy) async {
    final i = _items.indexWhere((f) => f.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(
      signed: true,
      signedBy: signedBy,
      signedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _save();
  }

  Future<void> updateSyncStatus(String id, String status, {String? error, String? externalId}) async {
    final i = _items.indexWhere((f) => f.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(
      syncStatus: status,
      syncError: error,
      externalId: externalId,
      updatedAt: DateTime.now(),
    );
    await _save();
  }

  int get count => _items.length;
  int get countByPatient =>
      _items.where((f) => f.patientCode.isNotEmpty).length;
  int get countSigned => _items.where((f) => f.signed).length;
  int get countPendingSync => _items.where((f) => f.signed && f.syncStatus != 'synced').length;
}
