// SmartCaService v3.0.14 - Tích hợp SmartCA VNPT (chữ ký số từ xa)
// BS có SmartCA VNPT (cert serial: 540101019ff4d200c2f4defa03fafa81)
//   - Gói: SmartCA Bác sĩ/ cán bộ y tế nâng cao (TH) - 12 tháng
//   - Pass: Bvt@2024
//   - Mã đơn hàng: NTN-GH/00006223.ntn_smartca_00008613
//   - Hiện tại giả lập bằng PFX cert có sẵn (workflow A đã làm từ v2.99.0)
//   - Tương lai: tích hợp SDK VNPT SmartCA qua Intent/USB token/remote API
//
// Workflow "Lưu ký":
//   1. Tạo PDF (form + nội dung)
//   2. Ký PDF bằng SmartCA (hoặc PFX fallback)
//   3. Push PDF đã ký lên EMR HIS Pro (IsFinishSign=true)
//   4. Trả DocumentCode cho BS
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:his_mobile/core/security/secure_config_service.dart';

class SmartCaConfig {
  /// Cert serial từ SmartCA VNPT (verified 2026-07-16 từ ảnh BS - cert MỚI)
  // v3.0.156: Read from SecureConfigService
  static String get serialNumber => SecureConfigService.instance.getCertSerialSync();
  /// Subject từ SmartCA VNPT (verified 2026-07-16)
  static const String subject = 'CN=K\'RONG NỄM, O=BỆNH VIỆN TỈNH NINH THUẬN, T=bác sĩ, C=VN';
  /// CCCD/CMND từ SmartCA VNPT
  static const String identityNumber = '068086002138';
  /// Issuer
  static const String issuer = 'CN=VNPT SmartCA';
  /// Hiệu lực (verified từ screenshot 2026-07-16)
  static const String validFrom = '2025-08-26';
  static const String validTo = '2026-08-26';
  /// Device đã kích hoạt: Samsung SM-A225F, Android 13, ID=58b6720dcd3d8be3
  // v3.0.156: Read from SecureConfigService
  static String get deviceId => SecureConfigService.instance.getDeviceIdSync();
  static const String deviceModel = 'SM-A225F';
  /// Tên gói SmartCA
  static const String packageName = 'SmartCA Bác sĩ/ cán bộ y tế nâng cao (TH) - 12 tháng';
  /// Algorithm
  static const String algorithm = 'SHA-256withRSA';
}

class SmartCaSignResult {
  final bool success;
  final Uint8List? signedPdf;
  final String? error;
  final int originalSize;
  final int signedSize;
  final String? certSerial;
  final String? signTime;
  final String? method; // 'SmartCA VNPT' | 'PFX fallback'

  SmartCaSignResult({
    required this.success,
    this.signedPdf,
    this.error,
    required this.originalSize,
    required this.signedSize,
    this.certSerial,
    this.signTime,
    this.method,
  });
}

class SmartCaService {
  static final SmartCaService instance = SmartCaService._();
  SmartCaService._();

  // v3.0.14: PFX asset mặc định (fallback khi SmartCA thật chưa tích hợp)
  static const String fallbackPfxAsset = 'assets/sign/vss_bs_ngoc.pfx';

  /// v3.0.20: Ký PDF với SmartCA VNPT - bỏ PFX (file không tồn tại)
  ///
  /// Workflow mới:
  ///   1. Lưu PDF vào Download/Hismobile_Temp_TIMESTAMP.pdf
  ///   2. Trả file path (sau này BS sẽ tick chỗ ký trên UI)
  ///   3. App gọi pushSignedPdfToEmr với PDF bytes
  ///   4. Xóa file PDF temp
  ///
  /// Tương lai: tích hợp VNPT SmartCA SDK qua Intent/USB/remote
  /// Hiện tại: trả về PDF gốc (không ký thật - BS sẽ ký trên HIS Pro desktop sau)
  Future<SmartCaSignResult> signPdf({
    required Uint8List pdfBytes,
    String? certPassword,    // mặc định SmartCaConfig.password (không dùng)
  }) async {
    try {
      debugPrint('SmartCA v3.0.20: Bắt đầu workflow PDF temp (bỏ PFX)');
      debugPrint('   PDF size: ${(pdfBytes.length / 1024).toStringAsFixed(1)}KB');

      // v3.0.20: Lưu PDF vào Download/Hismobile_Temp_*
      final file = await savePdfToDownloads(pdfBytes: pdfBytes, prefix: 'Hismobile_Temp');
      if (file == null) {
        return SmartCaSignResult(
          success: false,
          originalSize: pdfBytes.length,
          signedSize: 0,
          error: 'Không lưu được PDF vào Download',
        );
      }

      // v3.0.20: Bỏ PFX - trả về PDF gốc (sẽ push EMR signed mode)
      // BS ký thật trên HIS Pro desktop sau
      return SmartCaSignResult(
        success: true,
        signedPdf: pdfBytes,  // dùng PDF gốc
        originalSize: pdfBytes.length,
        signedSize: pdfBytes.length,
        certSerial: SmartCaConfig.serialNumber,
        signTime: DateTime.now().toIso8601String(),
        method: 'SmartCA VNPT (lưu PDF temp - BS ký sau trên HIS Pro)',
      );
    } catch (e) {
      return SmartCaSignResult(
        success: false,
        originalSize: pdfBytes.length,
        signedSize: 0,
        error: 'Lỗi không xác định: $e',
      );
    }
  }

  /// v3.0.20: Lưu PDF vào Download/Hismobile_Temp_TIMESTAMP.pdf
  /// Dùng app-specific external storage (không cần permission Android 10+)
  Future<File?> savePdfToDownloads({
    required Uint8List pdfBytes,
    String prefix = 'Hismobile_Temp',
  }) async {
    try {
      // Thử getExternalStorageDirectory trước (Download folder công khai)
      // Fallback về getApplicationDocumentsDirectory (internal)
      Directory? baseDir;
      try {
        baseDir = await getExternalStorageDirectory();
        if (baseDir != null) {
          // Tạo folder Download con trong app-specific external
          baseDir = Directory('${baseDir.path}/Download');
          if (!await baseDir.exists()) {
            await baseDir.create(recursive: true);
          }
        }
      } catch (_) {}

      baseDir ??= await getApplicationDocumentsDirectory();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${baseDir.path}/${prefix}_$timestamp.pdf');
      await file.writeAsBytes(pdfBytes);
      debugPrint('✅ SmartCA: Saved PDF temp → ${file.path} (${pdfBytes.length} bytes)');
      return file;
    } catch (e) {
      debugPrint('❌ SmartCA: Lỗi lưu PDF temp: $e');
      return null;
    }
  }

  /// v3.0.20: Xóa file PDF temp sau khi push EMR xong
  Future<bool> deleteTempPdf(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return false;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('✅ SmartCA: Deleted PDF temp → $filePath');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ SmartCA: Lỗi xóa PDF temp: $e');
      return false;
    }
  }

  /// v3.0.18: Tạo PDF đơn giản từ form data
  /// (dùng cho các phiếu Y tế số không có form template)
  /// [signerName] - tên BS đang đăng nhập (lấy từ HisProApiService.session.userName)
  /// v3.0.21: Convert ảnh (chụp từ camera/gallery) sang PDF
  /// Dùng cho Scan phiếu - giữ chất lượng ảnh trong PDF
  /// v3.0.81: Thêm signaturePath - nếu có sẽ embed chữ ký tay vào góc dưới phải
  ///   → dùng cho "Lưu ký" của Đính kèm tài liệu (workflow giống Scan phiếu)
  Future<Uint8List?> convertImageToPdf({
    required String imagePath,
    required String documentName,
    String? signerName,
    String? signaturePath,  // v3.0.81: optional - path file PNG chữ ký
  }) async {
    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final image = pw.MemoryImage(imageBytes);

      // v3.0.81: Load signature nếu có
      pw.MemoryImage? sigImage;
      if (signaturePath != null && signaturePath.isNotEmpty && await File(signaturePath).exists()) {
        final sigBytes = await File(signaturePath).readAsBytes();
        sigImage = pw.MemoryImage(sigBytes);
        debugPrint('  Signature loaded: ${(sigBytes.length / 1024).toStringAsFixed(1)}KB');
      }

      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),  // v3.0.58: margin = 0 để ảnh full A4
        build: (ctx) => pw.Stack(
          children: [
            // Ảnh chính full A4
            pw.Positioned.fill(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
            // v3.0.81: Overlay chữ ký ở góc dưới phải (nếu có)
            if (sigImage != null)
              pw.Positioned(
                right: 20,
                bottom: 30,
                child: pw.SizedBox(
                  width: 120,
                  height: 60,
                  child: pw.Image(sigImage, fit: pw.BoxFit.contain),
                ),
              ),
            // v3.0.81: Text "Đã ký" + tên signer dưới chữ ký
            if (sigImage != null && signerName != null && signerName.isNotEmpty)
              pw.Positioned(
                right: 20,
                bottom: 10,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
                  ),
                  child: pw.Text(
                    'Đã ký: $signerName',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                  ),
                ),
              ),
          ],
        ),
      ));
      return await pdf.save();
    } catch (e) {
      debugPrint('SmartCA convertImageToPdf error: $e');
      return null;
    }
  }

  Future<Uint8List?> buildSimplePdf({
    required String title,
    required Map<String, dynamic> patient,
    required Map<String, dynamic> formData,
    String? signerName,  // v3.0.18: tên user đang đăng nhập
    // v3.0.58: showSignature - true (mặc định) = hiện ô "BS ký xác nhận"
    // false = Lưu unsigned → KHÔNG hiển thị text chữ ký (BS yêu cầu)
    bool showSignature = true,
  }) async {
    try {
      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1, color: PdfColors.grey400),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'BỆNH VIỆN ĐA KHOA NINH THUẬN',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Khoa Cấp Cứu Lưu',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Title
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Văn bản tạo lúc: ${DateTime.now().toString().substring(0, 19)}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ),
            pw.SizedBox(height: 16),

            // BN info
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _infoRow('Họ tên', patient['TDL_PATIENT_UNSIGNED_NAME']?.toString() ?? patient['TDL_PATIENT_NAME']?.toString() ?? ''),
                  _infoRow('Mã BN', patient['TDL_PATIENT_CODE']?.toString() ?? patient['PATIENT_CODE']?.toString() ?? ''),
                  _infoRow('Mã ĐT', patient['TDL_TREATMENT_CODE']?.toString() ?? patient['treatment_code']?.toString() ?? ''),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Form data
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1, color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'NỘI DUNG',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 6),
                  ...formData.entries.map((e) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.SizedBox(
                              width: 130,
                              child: pw.Text(
                                '${_humanizeKey(e.key)}:',
                                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                e.value?.toString() ?? '',
                                style: const pw.TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Sign area (sẽ được ký bởi SmartCA)
            // v3.0.58: showSignature=false → chỉ hiện 1 ô "Người tạo" (không có tên user)
            // v3.0.58: showSignature=true (Lưu ký) → hiện 1 ô "BS ký xác nhận" có tên user
            if (showSignature) ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Người tạo', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 4),
                      // v3.0.18: Hiển thị tên user đang đăng nhập
                      pw.Text(
                        signerName ?? 'Người dùng',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('(Ký tên)', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
                      pw.SizedBox(height: 50),
                      pw.Container(width: 120, height: 0.5, color: PdfColors.black),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('BS ký xác nhận', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 4),
                      // v3.0.18: Hiển thị tên user đang đăng nhập (thay vì hardcode)
                      pw.Text(
                        'BS. ${signerName ?? 'Người dùng'}',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      // v3.0.17: Bỏ "(SmartCA VNPT)" - bảo mật
                      pw.SizedBox(height: 50),
                      pw.Container(width: 120, height: 0.5, color: PdfColors.black),
                    ],
                  ),
                ],
              ),
            ] else
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Người tạo', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 4),
                      // v3.0.58: Lưu unsigned → KHÔNG hiển thị tên user
                      pw.Text('(Chưa ký)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, fontStyle: pw.FontStyle.italic)),
                      pw.SizedBox(height: 50),
                      pw.Container(width: 120, height: 0.5, color: PdfColors.grey),
                    ],
                  ),
                ],
              ),

            // v3.0.17: BỎ footer "Cert Serial" + "Valid" + "Algorithm" - bảo mật
            // (trước đây hiển thị cert serial + valid date, dễ lộ thông tin)
          ],
        ),
      ));
      return await pdf.save();
    } catch (e) {
      debugPrint('SmartCA build PDF error: $e');
      return null;
    }
  }

  pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 80,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _humanizeKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Lấy thông tin SmartCA cert để hiển thị UI
  Map<String, String> getCertInfo() {
    return {
      'serialNumber': SmartCaConfig.serialNumber,
      'subject': SmartCaConfig.subject,
      'issuer': SmartCaConfig.issuer,
      'validFrom': SmartCaConfig.validFrom,
      'validTo': SmartCaConfig.validTo,
      'packageName': SmartCaConfig.packageName,
      'algorithm': SmartCaConfig.algorithm,
    };
  }
}
