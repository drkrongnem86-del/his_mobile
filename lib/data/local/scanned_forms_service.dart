// ScannedFormsService v2.41.0 - Local storage cho scanned forms
// Luu anh vao app dir + metadata vao SharedPreferences
// Hien thi trong Xem benh an khi load BN
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScannedForm {
  final String id;                  // UUID
  final String treatmentCode;       // FK to BN
  final String patientName;
  final String formName;            // Tên phiếu
  final String imagePath;           // Path to image file
  final String? signaturePath;      // Path to signature file (optional)
  final String signedBy;            // Username
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool uploaded;              // True if uploaded to EMR (TODO)
  final String? note;

  ScannedForm({
    required this.id,
    required this.treatmentCode,
    required this.patientName,
    required this.formName,
    required this.imagePath,
    this.signaturePath,
    required this.signedBy,
    required this.createdAt,
    required this.updatedAt,
    this.uploaded = false,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'treatment_code': treatmentCode,
    'patient_name': patientName,
    'form_name': formName,
    'image_path': imagePath,
    'signature_path': signaturePath,
    'signed_by': signedBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'uploaded': uploaded,
    'note': note,
  };

  factory ScannedForm.fromJson(Map<String, dynamic> j) => ScannedForm(
    id: j['id'] as String,
    treatmentCode: j['treatment_code'] as String,
    patientName: j['patient_name'] as String,
    formName: j['form_name'] as String,
    imagePath: j['image_path'] as String,
    signaturePath: j['signature_path'] as String?,
    signedBy: j['signed_by'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String),
    uploaded: j['uploaded'] as bool? ?? false,
    note: j['note'] as String?,
  );
}

class ScannedFormsService {
  static final ScannedFormsService instance = ScannedFormsService._();
  ScannedFormsService._();

  static const String _kFormsList = 'scanned_forms_list_v1';

  Future<String> getImageDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final imgDir = Directory('${dir.path}/scanned_forms');
    if (!await imgDir.exists()) {
      await imgDir.create(recursive: true);
    }
    return imgDir.path;
  }

  Future<List<ScannedForm>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kFormsList) ?? [];
    final list = raw.map((s) {
      try {
        return ScannedForm.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) { return null; }
    }).whereType<ScannedForm>().toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<List<ScannedForm>> getForPatient(String treatmentCode) async {
    final all = await getAll();
    return all.where((f) => f.treatmentCode == treatmentCode).toList();
  }

  Future<void> save(ScannedForm form) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kFormsList) ?? [];
    raw.removeWhere((s) {
      try {
        return ScannedForm.fromJson(jsonDecode(s) as Map<String, dynamic>).id == form.id;
      } catch (_) { return false; }
    });
    raw.add(jsonEncode(form.toJson()));
    await prefs.setStringList(_kFormsList, raw);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kFormsList) ?? [];
    final keep = <String>[];
    ScannedForm? toDelete;
    for (final s in raw) {
      try {
        final f = ScannedForm.fromJson(jsonDecode(s) as Map<String, dynamic>);
        if (f.id == id) {
          toDelete = f;
          continue;
        }
      } catch (_) {}
      keep.add(s);
    }
    await prefs.setStringList(_kFormsList, keep);
    if (toDelete != null) {
      try {
        final f = File(toDelete.imagePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (toDelete.signaturePath != null) {
        try {
          final f = File(toDelete.signaturePath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }
}