// v3.0.39: MockEmrServer - Mô phỏng HIS Pro EMR trong app (test offline)
//
// Khi BS bật "Mock server":
// - Tất cả push EMR sẽ lưu local (không gọi server thật)
// - Trả DocumentCode giả (theo format 000033xxxxxx)
// - GetView trả list phiếu đã push trong mock
// - Lưu SharedPreferences, persist qua kill app
//
// Path lưu: <app docs>/mock_emr/000033xxxxxx.pdf
// Lưu list: SharedPreferences key "mock_emr_documents_v1"
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockEmrDocument {
  final String documentCode;
  final String documentName;
  final int documentTypeId;
  final String treatmentCode;
  final String user;
  final DateTime createdAt;
  final bool isSigned;
  final String? filePath;
  final int? fileSize;

  MockEmrDocument({
    required this.documentCode,
    required this.documentName,
    required this.documentTypeId,
    required this.treatmentCode,
    required this.user,
    required this.createdAt,
    this.isSigned = false,
    this.filePath,
    this.fileSize,
  });

  Map<String, dynamic> toJson() => {
        'documentCode': documentCode,
        'documentName': documentName,
        'documentTypeId': documentTypeId,
        'treatmentCode': treatmentCode,
        'user': user,
        'createdAt': createdAt.toIso8601String(),
        'isSigned': isSigned,
        'filePath': filePath,
        'fileSize': fileSize,
      };

  factory MockEmrDocument.fromJson(Map<String, dynamic> j) => MockEmrDocument(
        documentCode: j['documentCode'] as String,
        documentName: j['documentName'] as String,
        documentTypeId: (j['documentTypeId'] as num).toInt(),
        treatmentCode: j['treatmentCode'] as String,
        user: j['user'] as String? ?? 'unknown',
        createdAt: DateTime.parse(j['createdAt'] as String),
        isSigned: j['isSigned'] as bool? ?? false,
        filePath: j['filePath'] as String?,
        fileSize: (j['fileSize'] as num?)?.toInt(),
      );
}

class MockEmrResponse {
  final bool success;
  final String? documentCode;
  final int? documentId;
  final String? error;
  final String? message;

  MockEmrResponse({
    required this.success,
    this.documentCode,
    this.documentId,
    this.error,
    this.message,
  });
}

class MockEmrServer {
  static final MockEmrServer instance = MockEmrServer._();
  MockEmrServer._();

  static const _kDocsKey = 'mock_emr_documents_v1';
  static const _kCounterKey = 'mock_emr_counter_v1';
  static const _kEnabledKey = 'mock_emr_enabled_v1';

  // ============================================================
  // Enable/Disable
  // ============================================================
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, enabled);
    debugPrint('MockEmrServer: enabled=$enabled');
  }

  // ============================================================
  // Push document (giả lập POST CreateByTdo)
  // ============================================================
  Future<MockEmrResponse> createDocument({
    required String documentName,
    required int documentTypeId,
    required String treatmentCode,
    required String user,
    bool isSigned = false,
    String? filePath,
    int? fileSize,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docs = await getAllDocuments();
      // Generate DocumentCode 12 chars: 000033xxxxxx
      int counter = prefs.getInt(_kCounterKey) ?? 3348000;
      counter += 1;
      await prefs.setInt(_kCounterKey, counter);
      final docCode = counter.toString().padLeft(12, '0');
      // Lưu file PDF nếu có
      String? savedFilePath;
      int? savedFileSize;
      if (filePath != null) {
        try {
          final src = File(filePath);
          if (await src.exists()) {
            final mockDir = await _getMockDir();
            if (!await mockDir.exists()) {
              await mockDir.create(recursive: true);
            }
            final dst = File('${mockDir.path}/$docCode.pdf');
            await src.copy(dst.path);
            savedFilePath = dst.path;
            savedFileSize = await dst.length();
          }
        } catch (e) {
          debugPrint('MockEmrServer: copy file error: $e');
        }
      }
      final doc = MockEmrDocument(
        documentCode: docCode,
        documentName: documentName,
        documentTypeId: documentTypeId,
        treatmentCode: treatmentCode,
        user: user,
        createdAt: DateTime.now(),
        isSigned: isSigned,
        filePath: savedFilePath,
        fileSize: savedFileSize,
      );
      docs.add(doc);
      await _saveDocuments(docs);
      debugPrint('MockEmrServer: created $docCode (${documentName})');
      return MockEmrResponse(
        success: true,
        documentCode: docCode,
        documentId: docs.length,
        message: 'Mock server: saved locally',
      );
    } catch (e) {
      debugPrint('MockEmrServer.createDocument error: $e');
      return MockEmrResponse(
        success: false,
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Get documents
  // ============================================================
  Future<List<MockEmrDocument>> getAllDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDocsKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => MockEmrDocument.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Lấy list phiếu theo treatmentCode
  Future<List<MockEmrDocument>> getDocumentsByTreatment(String treatmentCode) async {
    final all = await getAllDocuments();
    return all.where((d) => d.treatmentCode == treatmentCode).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Lấy 1 phiếu theo DocumentCode
  Future<MockEmrDocument?> getDocument(String documentCode) async {
    final all = await getAllDocuments();
    try {
      return all.firstWhere((d) => d.documentCode == documentCode);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // Reset
  // ============================================================
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDocsKey);
    await prefs.remove(_kCounterKey);
    try {
      final dir = await _getMockDir();
      if (await dir.exists()) {
        await for (final f in dir.list()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('MockEmrServer.reset error: $e');
    }
    debugPrint('MockEmrServer: reset all');
  }

  Future<int> count() async => (await getAllDocuments()).length;

  // ============================================================
  // File PDF
  // ============================================================
  Future<File?> getDocumentFile(String documentCode) async {
    final doc = await getDocument(documentCode);
    if (doc?.filePath == null) return null;
    final f = File(doc!.filePath!);
    if (!await f.exists()) return null;
    return f;
  }

  // ============================================================
  // Internal
  // ============================================================
  Future<void> _saveDocuments(List<MockEmrDocument> docs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(docs.map((d) => d.toJson()).toList());
    await prefs.setString(_kDocsKey, raw);
  }

  Future<Directory> _getMockDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/mock_emr');
  }
}
