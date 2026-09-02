// v3.0.81: AttachDocumentService — Đính kèm tài liệu (ảnh/file) vào EMR BN
// v3.0.80: Refactor — dùng EmrPushService.pushPdfToEmrUnsigned (đã verify work)
//   thay vì gọi thẳng EmrDocument/CreateWithFile (trả 500 trên server này).
// v3.0.81: Thêm "Lưu ký" - hỗ trợ ký tay (hand-drawn signature) embed vào PDF
//   rồi push qua EmrPushService.pushSignedPdfToEmr (IsFinishSign=true).
//   Workflow giống Scan phiếu / Phiếu khám - user vẽ chữ ký trên dialog,
//   chữ ký overlay lên PDF góc dưới phải + tên user → push signed EMR.
// Flow theo log HIS.exe 10/08 + scan_phieu đã work:
//   1. Đọc ảnh/file từ local (camera/gallery)
//   2. Convert → PDF (SmartCaService.convertImageToPdf) - embed chữ ký nếu có
//   3. POST EmrDocument/CreateByTdo với SDO đầy đủ + base64 (useFss=false)
//      - Unsigned: IsFinishSign=false, IsSignElectronic=false, Signs=[]
//      - Signed:   IsFinishSign=true,  IsSignElectronic=true,  Signs=[{...}], SignedImageData=base64PDF
//   4. Trả DocumentCode
//
// Auth: HIS Pro TokenCode + ApplicationCode + ClientIpAddress (qua EmrPushService)

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/data/api/emr_push_service.dart';
import 'package:his_mobile/data/services/smart_ca_service.dart';

class AttachResult {
  final bool success;
  final String? error;
  final int? httpStatus;
  final String? documentCode;
  final bool isSigned;  // v3.0.81: true nếu push signed
  final Map<String, dynamic>? data;

  const AttachResult({
    required this.success,
    this.error,
    this.httpStatus,
    this.documentCode,
    this.isSigned = false,
    this.data,
  });
}

class AttachDocumentService {
  static final AttachDocumentService instance = AttachDocumentService._();
  AttachDocumentService._();

  String get _emrBase => ConnectionService.instance.emrUrl.replaceAll(RegExp(r'/$'), '');

  /// v3.0.81: Upload file (image/PDF) lên EMR - hỗ trợ cả unsigned và signed (ký tay)
  /// - treatmentCode: mã điều trị (vd "000002164424")
  /// - documentTypeId: ID loại văn bản (mặc định 20 = Phiếu khác)
  /// - documentName: tên file hiển thị (vd "ĐIỆN TIM")
  /// - filePath: đường dẫn file local (ảnh chụp từ camera hoặc chọn từ thư viện)
  /// - signaturePath: v3.0.81 - optional PNG chữ ký tay (nếu user chọn "Lưu ký")
  /// - workingDeptName: tên khoa (mặc định "Khoa Cấp Cứu")
  /// - departmentCode: mã khoa (mặc định "HSCC")
  /// - roomCode: mã phòng (mặc định "PKCC")
  /// - signerName: tên user ký (lấy từ HisProApiService.session.userName)
  /// Returns: AttachResult với success + httpStatus + documentCode + isSigned
  Future<AttachResult> attachFile({
    required String treatmentCode,
    required int documentTypeId,
    required String documentName,
    required String filePath,
    String? signaturePath,  // v3.0.81: optional
    String? documentGroupCode,
    String? workingDeptName,
    String? departmentCode,
    String? roomCode,
    String? signerName,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return AttachResult(
          success: false,
          error: 'File không tồn tại: $filePath',
        );
      }

      final isSigned = signaturePath != null && signaturePath.isNotEmpty;
      debugPrint('📎 AttachDocument: $filePath (${(await file.length() / 1024).toStringAsFixed(1)}KB) signed=$isSigned');
      debugPrint('  Treatment=$treatmentCode DocTypeId=$documentTypeId Name="$documentName"');

      // Step 1: Convert → PDF (và embed chữ ký nếu có)
      Uint8List? pdfBytes;
      final ext = filePath.toLowerCase();
      if (ext.endsWith('.pdf')) {
        // File đã là PDF - không embed chữ ký (PDF có thể đã có hoặc không)
        // v3.0.81: Nếu cần ký PDF có sẵn, sẽ cần dùng pdf package để overlay
        // (chưa support - chỉ ký với ảnh)
        if (isSigned) {
          return const AttachResult(
            success: false,
            error: 'PDF có sẵn chưa hỗ trợ ký tay. Vui lòng chọn ảnh (camera/gallery).',
          );
        }
        pdfBytes = await file.readAsBytes();
        debugPrint('  PDF trực tiếp: ${(pdfBytes.length / 1024).toStringAsFixed(1)}KB');
      } else {
        // Ảnh → PDF (v3.0.81: embed chữ ký nếu có)
        final converted = await SmartCaService.instance.convertImageToPdf(
          imagePath: filePath,
          documentName: documentName,
          signerName: signerName ?? workingDeptName ?? 'Khoa Cấp Cứu',
          signaturePath: signaturePath,  // null nếu unsigned
        );
        if (converted == null) {
          return const AttachResult(
            success: false,
            error: 'Convert ảnh → PDF thất bại',
          );
        }
        pdfBytes = converted;
        debugPrint('  Converted → PDF: ${(pdfBytes.length / 1024).toStringAsFixed(1)}KB (signed=$isSigned)');
      }

      // Step 2: Push lên EMR
      if (isSigned) {
        // v3.0.81: Signed mode - IsFinishSign=true + SignedImageData
        final result = await EmrPushService.instance.pushSignedPdfToEmrWithApi(
          signedPdfBytes: pdfBytes,
          treatmentCode: treatmentCode,
          documentName: documentName,
          documentTypeId: documentTypeId,
          workingDeptName: workingDeptName,
          departmentCode: departmentCode,
          roomCode: roomCode,
        );
        debugPrint('  EMR push SIGNED result: success=${result.success} docCode=${result.documentCode} err=${result.error}');
        return AttachResult(
          success: result.success,
          error: result.error,
          documentCode: result.documentCode,
          isSigned: true,
          data: result.success ? {'documentCode': result.documentCode, 'isSigned': true} : null,
        );
      } else {
        // Unsigned mode - IsFinishSign=false (work 100% verified)
        final result = await EmrPushService.instance.pushPdfToEmrUnsigned(
          pdfBytes: pdfBytes,
          treatmentCode: treatmentCode,
          documentName: documentName,
          documentTypeId: documentTypeId,
          workingDeptName: workingDeptName,
          departmentCode: departmentCode,
          roomCode: roomCode,
          useFss: false,  // v3.0.10: base64 work 100% (FSS port 1405 đôi khi 404)
        );
        debugPrint('  EMR push UNSIGNED result: success=${result.success} docCode=${result.documentCode} err=${result.error}');
        return AttachResult(
          success: result.success,
          error: result.error,
          documentCode: result.documentCode,
          isSigned: false,
          data: result.success ? {'documentCode': result.documentCode, 'isSigned': false} : null,
        );
      }
    } catch (e) {
      debugPrint('❌ AttachDocument error: $e');
      return AttachResult(success: false, error: 'Lỗi: $e');
    }
  }

  /// Lấy danh sách DocumentType (loại văn bản) từ EMR
  Future<List<Map<String, dynamic>>> fetchDocumentTypes() async {
    return EmrPushService.instance.getDocumentTypes()
        .then((types) => types.map((t) => {
              'id': t.id,
              'code': t.code,
              'name': t.name,
              'numOrder': t.numOrder,
            }).toList());
  }
}
