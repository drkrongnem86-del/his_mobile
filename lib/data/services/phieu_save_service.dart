// v3.0.22: Service thống nhất cho "Lưu" / "Lưu ký" phiếu.
//
// Trước đây có 3 workflow khác nhau ở 4 màn:
//   - phieu_kham: dùng pushImageToEmr (cũ, không tạo PDF)
//   - phieu_form: dùng hisPro.post MPS Save (cũ, có mojibake)
//   - scan_phieu: PDF temp + pushPdfToEmrUnsigned/pushSignedPdfToEmr (chuẩn)
//   - y_te_so_form: 3 hàm duplicate (_saveLocal, _pushEmrUnsigned, _signAndPush)
//
// v3.0.22: Gộp tất cả thành 1 service duy nhất, 1 entry point, 1 error handling.
//
// Workflow PDF temp chuẩn:
//   1. Validate
//   2. Lưu local (ScannedFormsService / YTeSoStore / ClinicalFormsStore / FormDraftService)
//   3. Build PDF (SmartCaService.buildSimplePdf / convertImageToPdf)
//   4. Lưu PDF vào Download/Hismobile_Temp_TIMESTAMP.pdf
//   5. Push EMR (signed → IsFinishSign=true / unsigned → IsFinishSign=false)
//   6. Xóa PDF temp (nếu push OK)
//   7. Trả PhiếuSaveResult cho UI

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/data/api/emr_push_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/services/emr_upload_queue.dart';
import 'package:his_mobile/data/services/image_pdf_service.dart';
import 'package:his_mobile/data/services/smart_ca_service.dart';
import 'package:his_mobile/data/services/vnpt_signature_service.dart';

/// Mode lưu phiếu - 3 mode thống nhất
enum PhieuSaveMode {
  localOnly,  // Chỉ lưu local, không đẩy EMR
  unsigned,   // Lưu local + đẩy EMR (chưa ký - IsFinishSign=false, BS ký trên HIS Pro sau)
  signed,     // Lưu local + đẩy EMR (đã ký - IsFinishSign=true, BS đã ký tay trong app)
}

/// Stage fail (để UI hiển thị thông báo chính xác)
enum PhieuSaveStage {
  none,
  validate,
  saveLocal,
  buildPdf,
  saveDownload,
  pushEmr,
  cleanup,
}

/// Input cho việc lưu phiếu
class PhieuSaveInput {
  final Map<String, dynamic> patient;
  final String formName;
  final Map<String, dynamic> formData;

  /// Optional - DocumentTypeId EMR (nếu biết). Nếu null, sẽ auto-detect từ kind/phieuLabel.
  final int? documentTypeId;
  final EmrDocumentKind? kind;
  final String? phieuLabel;

  /// Optional - ảnh gốc (cho scan phiếu) - nếu có sẽ convert sang PDF
  final String? imagePath;

  /// Optional - signature PNG từ user vẽ tay (cho mode=signed)
  final String? signaturePath;

  /// Optional - ảnh/PDF gốc đã có sẵn (cho trường hợp đặc biệt)
  final Uint8List? prebuiltPdfBytes;

  /// v3.0.145: PNG image bytes đã render sẵn (font trên EMR sẽ không garble)
  /// Ưu tiên hơn prebuiltPdfBytes - nếu có PNG thì push PNG thay vì PDF
  final Uint8List? prebuiltPngBytes;

  /// Optional - department/room
  final String? departmentCode;
  final String? roomCode;
  final String? roomTypeCode;
  final String? workingDeptName;

  /// Optional - ghi chú
  final String? note;

  /// v3.0.24: Dùng VNPT SmartCA để ký PKCS#7 thật (thay vì mark IsFinishSign=true thông thường)
  /// Chỉ có tác dụng khi mode = signed
  final bool useVnptSignature;

  const PhieuSaveInput({
    required this.patient,
    required this.formName,
    required this.formData,
    this.documentTypeId,
    this.kind,
    this.phieuLabel,
    this.imagePath,
    this.signaturePath,
    this.prebuiltPdfBytes,
    this.prebuiltPngBytes,
    this.departmentCode,
    this.roomCode,
    this.roomTypeCode,
    this.workingDeptName,
    this.note,
    this.useVnptSignature = false,
  });
}

/// Output kết quả lưu phiếu
class PhieuSaveResult {
  final bool success;             // local save OK
  final bool emrPushed;           // EMR push thành công
  final bool vnptSigned;          // v3.0.29: VNPT SmartCA ký thật (PKCS#7) thành công
  final String? documentCode;     // mã EMR (nếu push OK)
  final String? tempPdfPath;      // path PDF temp (nếu còn giữ lại để debug)
  final String? error;            // error message
  final String? warning;          // v3.0.29: warning (VD: VNPT fail → fallback)
  final PhieuSaveStage failedAt;  // step nào fail
  final int? elapsedMs;           // tổng thời gian (ms)

  const PhieuSaveResult({
    required this.success,
    this.emrPushed = false,
    this.vnptSigned = false,
    this.documentCode,
    this.tempPdfPath,
    this.error,
    this.warning,
    this.failedAt = PhieuSaveStage.none,
    this.elapsedMs,
  });

  /// Trả về message thân thiện cho UI
  String get displayMessage {
    if (success && emrPushed) {
      final tag = vnptSigned ? '✅ Lưu + Ký VNPT + đẩy EMR' : '✅ Lưu + đẩy EMR';
      return '$tag thành công\nDocumentCode: $documentCode';
    } else if (success && !emrPushed) {
      if (error != null) {
        return '⚠️ Đã lưu local. EMR fail: $error\nPDF giữ tại: $tempPdfPath';
      }
      return '✅ Đã lưu local (không đẩy EMR)';
    } else {
      return '❌ Lỗi: $error';
    }
  }
}

/// Hook lưu local - UI implement để quyết định lưu vào store nào
typedef PhieuSaveLocalHook = Future<bool> Function(PhieuSaveInput input);

/// PhieuSaveService - service thống nhất cho Lưu/Lưu ký
class PhieuSaveService {
  static final PhieuSaveService instance = PhieuSaveService._();
  PhieuSaveService._();

  /// Lưu phiếu theo mode.
  ///
  /// [saveLocalHook]: callback UI để lưu local (ScannedFormsService / YTeSoStore / ClinicalFormsStore / FormDraftService).
  ///   Nếu null → bỏ qua bước lưu local.
  /// [validateHook]: callback validate trước khi lưu (kiểm tra required fields).
  ///   Nếu trả về String != null → fail validate, message trả về là error.
  Future<PhieuSaveResult> save({
    required PhieuSaveMode mode,
    required PhieuSaveInput input,
    PhieuSaveLocalHook? saveLocalHook,
    Future<String?> Function(PhieuSaveInput input)? validateHook,
  }) async {
    final sw = Stopwatch()..start();
    String? tempPdfPath;

    try {
      // 0. Validate (nếu có hook)
      if (validateHook != null) {
        final err = await validateHook(input);
        if (err != null) {
          return _fail(PhieuSaveStage.validate, err, sw);
        }
      }

      // 1. Lưu local (chỉ với mode != localOnly? actually: luôn lưu local nếu có hook)
      if (saveLocalHook != null) {
        debugPrint('[PhieuSave] Bước 1: Lưu local (mode=$mode)');
        try {
          final ok = await saveLocalHook(input);
          if (!ok) {
            return _fail(PhieuSaveStage.saveLocal, 'Lưu local thất bại', sw);
          }
        } catch (e) {
          debugPrint('[PhieuSave] saveLocalHook error: $e');
          return _fail(PhieuSaveStage.saveLocal, 'Lỗi lưu local: $e', sw);
        }
      }

      // 2. Nếu chỉ local thì xong
      if (mode == PhieuSaveMode.localOnly) {
        sw.stop();
        return PhieuSaveResult(
          success: true,
          emrPushed: false,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }

      // 3. Build PDF
      debugPrint('[PhieuSave] Bước 2: Build PDF');
      Uint8List? pdfBytes = input.prebuiltPdfBytes;
      // v3.0.145: Nếu có PNG bytes (đã render sẵn) → convert PNG → PDF (image-only)
      // PDF này chỉ chứa ảnh, không có text → EMR server hiển thị đúng font
      if (pdfBytes == null && input.prebuiltPngBytes != null) {
        debugPrint('[PhieuSave] Converting PNG → PDF (image-only, no text)');
        pdfBytes = await imageBytesToPdf(input.prebuiltPngBytes!);
        if (pdfBytes == null) {
          return _fail(PhieuSaveStage.buildPdf, 'Lỗi convert PNG → PDF', sw);
        }
        debugPrint('[PhieuSave] PNG → PDF done: ${pdfBytes.length} bytes');
      }
      if (pdfBytes == null) {
        try {
          final signerName = _getSignerName();
          // v3.0.58: Lưu unsigned → KHÔNG hiển thị text chữ ký tên user
          // Lưu ký / Ký CA → hiển thị 1 ô "BS ký xác nhận" + tên user
          final showSignature = mode == PhieuSaveMode.signed;
          if (input.imagePath != null && input.imagePath!.isNotEmpty) {
            // Convert ảnh → PDF (cho scan phiếu)
            pdfBytes = await SmartCaService.instance.convertImageToPdf(
              imagePath: input.imagePath!,
              documentName: input.formName,
              signerName: signerName,
            );
          } else {
            // Build PDF từ formData (cho các màn khác)
            pdfBytes = await SmartCaService.instance.buildSimplePdf(
              title: input.formName,
              patient: input.patient,
              formData: input.formData,
              signerName: signerName,
              showSignature: showSignature,
            );
          }
        } catch (e) {
          debugPrint('[PhieuSave] buildPdf error: $e');
          return _fail(PhieuSaveStage.buildPdf, 'Lỗi tạo PDF: $e', sw);
        }
      }
      if (pdfBytes == null || pdfBytes.isEmpty) {
        return _fail(PhieuSaveStage.buildPdf, 'PDF rỗng', sw);
      }
      debugPrint('[PhieuSave] PDF size: ${(pdfBytes.length / 1024).toStringAsFixed(1)}KB');

      // 4. Lưu PDF vào Download
      debugPrint('[PhieuSave] Bước 3: Lưu PDF temp vào Download');
      File? tempFile;
      try {
        tempFile = await SmartCaService.instance.savePdfToDownloads(
          pdfBytes: pdfBytes,
          prefix: 'Hismobile_Temp',
        );
        if (tempFile == null) {
          return _fail(PhieuSaveStage.saveDownload, 'Lưu PDF temp thất bại', sw);
        }
        tempPdfPath = tempFile.path;
      } catch (e) {
        debugPrint('[PhieuSave] savePdfToDownloads error: $e');
        return _fail(PhieuSaveStage.saveDownload, 'Lỗi lưu PDF temp: $e', sw, tempPdfPath: tempPdfPath);
      }

      // 5. Push EMR
      final treatmentCode = input.patient['TDL_TREATMENT_CODE']?.toString()
          ?? input.patient['treatment_code']?.toString()
          ?? '';
      if (treatmentCode.isEmpty) {
        return _fail(PhieuSaveStage.pushEmr, 'Không có treatmentCode (BN chưa vào viện?)', sw, tempPdfPath: tempPdfPath);
      }

      EmrPushResult emrResult;
      String? vnptWarning;
      bool vnptSignedOk = false;
      try {
        if (mode == PhieuSaveMode.signed) {
          // v3.0.24: Nếu useVnptSignature = true → ký bằng VNPT SmartCA thật
          if (input.useVnptSignature) {
            debugPrint('[PhieuSave] Bước 4a: Ký PDF bằng VNPT SmartCA');
            final vnptResult = await VnptSignatureService.instance.signPdf(pdfBytes);
            if (vnptResult.success && vnptResult.signedPdfBytes != null) {
              debugPrint('[PhieuSave] VNPT ký OK - tranId=${vnptResult.tranId}');
              pdfBytes = vnptResult.signedPdfBytes!;
              vnptSignedOk = true;
            } else {
              // v3.0.29: VNPT fail (placeholder URL / no backend / network)
              // → KHÔNG fail cả workflow, vẫn push EMR signed (IsFinishSign=true) với PDF gốc
              // → Lưu warning để UI hiển thị
              debugPrint('[PhieuSave] VNPT fail (sẽ fallback): ${vnptResult.error}');
              vnptWarning = 'VNPT SmartCA chưa sẵn sàng: ${vnptResult.error}\n'
                  '→ Tự động đẩy EMR với IsFinishSign=true (BS ký trên HIS Pro desktop sau)';
              // pdfBytes giữ nguyên (PDF gốc) → vẫn push EMR signed mode OK
            }
          }
          debugPrint('[PhieuSave] Bước 4b: Push SIGNED (IsFinishSign=true)');
          emrResult = await EmrPushService.instance.pushSignedPdfToEmrWithApi(
            signedPdfBytes: pdfBytes,
            treatmentCode: treatmentCode,
            documentName: input.formName,
            documentTypeId: input.documentTypeId,
            kind: input.kind,
            phieuLabel: input.phieuLabel,
            roomCode: input.roomCode,
            roomTypeCode: input.roomTypeCode ?? 'XL',
            workingDeptName: input.workingDeptName,
            departmentCode: input.departmentCode,
            certSerial: SmartCaConfig.serialNumber,
          );
        } else {
          debugPrint('[PhieuSave] Bước 4: Push UNSIGNED (IsFinishSign=false)');
          emrResult = await EmrPushService.instance.pushPdfToEmrUnsignedWithApi(
            pdfBytes: pdfBytes,
            treatmentCode: treatmentCode,
            documentName: input.formName,
            documentTypeId: input.documentTypeId,
            kind: input.kind,
            phieuLabel: input.phieuLabel,
            roomCode: input.roomCode,
            roomTypeCode: input.roomTypeCode ?? 'XL',
            workingDeptName: input.workingDeptName,
            departmentCode: input.departmentCode,
            useFss: false,  // v3.0.13: dùng base64 trực tiếp
          );
        }
      } catch (e) {
        debugPrint('[PhieuSave] pushEmr error: $e');
        return _fail(PhieuSaveStage.pushEmr, 'Lỗi đẩy EMR: $e', sw, tempPdfPath: tempPdfPath);
      }

      // 6. Cleanup: xóa PDF temp nếu push OK
      if (emrResult.success) {
        try {
          await SmartCaService.instance.deleteTempPdf(tempPdfPath);
        } catch (e) {
          debugPrint('[PhieuSave] deleteTempPdf warning: $e');
        }
        sw.stop();
        return PhieuSaveResult(
          success: true,
          emrPushed: true,
          vnptSigned: vnptSignedOk,  // v3.0.29: VNPT có ký thật hay không
          documentCode: emrResult.documentCode,
          tempPdfPath: null,
          warning: vnptWarning,       // v3.0.29: warning nếu VNPT fail nhưng EMR OK
          elapsedMs: sw.elapsedMilliseconds,
        );
      } else {
        // EMR fail - giữ PDF temp để BS xem/debug
        sw.stop();
        // v3.0.37: Nếu lỗi network (retryable) → enqueue pendingRetry
        // Lỗi auth/permission/server → return failed bình thường
        if (emrResult.errorType == 'network' && tempPdfPath != null) {
          try {
            final file = File(tempPdfPath);
            final fileSize = await file.exists() ? await file.length() : 0;
            final pending = PendingUpload(
              docId: '${DateTime.now().millisecondsSinceEpoch}',
              treatmentCode: treatmentCode,
              documentName: input.formName,
              documentTypeId: input.documentTypeId ?? 20,
              pdfPath: tempPdfPath,
              enqueuedAt: DateTime.now(),
              nextRetryAt: DateTime.now().add(const Duration(seconds: 30)),
              lastError: emrResult.error,
              fileSize: fileSize,
            );
            await EmrUploadQueue.instance.enqueue(pending);
            debugPrint('[PhieuSave] enqueue pendingRetry: ${pending.docId}');
            return PhieuSaveResult(
              success: true,
              emrPushed: false,
              vnptSigned: vnptSignedOk,
              warning: '${vnptWarning ?? ""}\n⏳ Mất mạng - đã lưu vào hàng đợi, tự động retry khi có mạng',
              documentCode: null,
              tempPdfPath: tempPdfPath,
              error: emrResult.error,
              failedAt: PhieuSaveStage.pushEmr,
              elapsedMs: sw.elapsedMilliseconds,
            );
          } catch (e) {
            debugPrint('[PhieuSave] enqueue error: $e');
          }
        }
        return PhieuSaveResult(
          success: true,
          emrPushed: false,
          vnptSigned: vnptSignedOk,
          warning: vnptWarning,
          documentCode: null,
          tempPdfPath: tempPdfPath,
          error: emrResult.error,
          failedAt: PhieuSaveStage.pushEmr,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }
    } catch (e, st) {
      debugPrint('[PhieuSave] unexpected error: $e\n$st');
      return _fail(PhieuSaveStage.none, 'Lỗi không xác định: $e', sw, tempPdfPath: tempPdfPath);
    }
  }

  PhieuSaveResult _fail(PhieuSaveStage stage, String error, Stopwatch sw, {String? tempPdfPath}) {
    sw.stop();
    return PhieuSaveResult(
      success: false,
      emrPushed: false,
      error: error,
      failedAt: stage,
      tempPdfPath: tempPdfPath,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  /// Lấy tên BS đang đăng nhập (ưu tiên session.userName > loginName > fallback)
  String _getSignerName() {
    try {
      final api = HisProApiService.instance;
      return api.session?.userName
          ?? api.loginName
          ?? HisProHardcoded.loginName;
    } catch (_) {
      return HisProHardcoded.loginName;
    }
  }
}
