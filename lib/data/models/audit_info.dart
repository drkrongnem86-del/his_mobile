// AuditInfo v3.0.34 - Thông tin audit cho mỗi document push EMR
// Lưu cùng với local document, gửi kèm trong request EMR (nếu backend hỗ trợ)
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';

class AuditInfo {
  // v3.0.34: Bổ sung fields theo đề xuất BS (16/07)
  final String? deviceId;          // SSAID / identifierForVendor
  final String? deviceModel;        // "Samsung SM-A175F" / "iPhone 15"
  final String? osVersion;          // "Android 14" / "iOS 17.2"
  final String? appVersion;         // "3.0.34"

  final String? uploadedBy;          // login name BS (vd: "nemk")
  final DateTime? uploadedAt;       // thời điểm upload
  final String? ipAddress;          // local IP (172.16.x.x)

  // v3.0.34: Thêm fields theo đề xuất BS
  final String? documentCode;       // 000033472416
  final String? treatmentCode;       // 000002128160
  final String? signatureProvider;  // "VNPT" / "HSM" / "USB" / null

  // v3.0.34: Trạng thái + error
  final String? status;              // "SUCCESS" / "FAILED" / "RETRY"
  final String? errorMessage;        // chi tiết lỗi nếu FAILED

  AuditInfo({
    this.deviceId,
    this.deviceModel,
    this.osVersion,
    this.appVersion,
    this.uploadedBy,
    this.uploadedAt,
    this.ipAddress,
    this.documentCode,
    this.treatmentCode,
    this.signatureProvider,
    this.status,
    this.errorMessage,
  });

  /// Auto-detect device info + app version + user
  static Future<AuditInfo> capture({
    String? documentCode,
    String? treatmentCode,
    String? signatureProvider,
  }) async {
    String? deviceId;
    String? deviceModel;
    String? osVersion;
    try {
      if (Platform.isAndroid) {
        final android = await DeviceInfoPlugin().androidInfo;
        deviceId = android.id;  // SSAID
        deviceModel = '${android.brand} ${android.model}';
        osVersion = 'Android ${android.version.release} (SDK ${android.version.sdkInt})';
      } else if (Platform.isIOS) {
        final ios = await DeviceInfoPlugin().iosInfo;
        deviceId = ios.identifierForVendor ?? 'unknown';
        deviceModel = '${ios.name} ${ios.model}';
        osVersion = 'iOS ${ios.systemVersion}';
      }
    } catch (e) {
      // ignore
    }

    String? uploadedBy;
    try {
      final api = HisProApiService.instance;
      uploadedBy = api.loginName ?? api.session?.loginName;
    } catch (_) {}

    return AuditInfo(
      deviceId: deviceId,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: AppConstants.appVersion,
      uploadedBy: uploadedBy,
      uploadedAt: DateTime.now(),
      documentCode: documentCode,
      treatmentCode: treatmentCode,
      signatureProvider: signatureProvider,
    );
  }

  /// Mark as success
  AuditInfo markSuccess({required String documentCode}) {
    return AuditInfo(
      deviceId: deviceId,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: appVersion,
      uploadedBy: uploadedBy,
      uploadedAt: uploadedAt ?? DateTime.now(),
      ipAddress: ipAddress,
      documentCode: documentCode,
      treatmentCode: treatmentCode,
      signatureProvider: signatureProvider,
      status: 'SUCCESS',
    );
  }

  /// Mark as failed
  AuditInfo markFailed({required String error}) {
    return AuditInfo(
      deviceId: deviceId,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: appVersion,
      uploadedBy: uploadedBy,
      uploadedAt: uploadedAt ?? DateTime.now(),
      ipAddress: ipAddress,
      documentCode: documentCode,
      treatmentCode: treatmentCode,
      signatureProvider: signatureProvider,
      status: 'FAILED',
      errorMessage: error,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'osVersion': osVersion,
        'appVersion': appVersion,
        'uploadedBy': uploadedBy,
        'uploadedAt': uploadedAt?.toIso8601String(),
        'ipAddress': ipAddress,
        'documentCode': documentCode,
        'treatmentCode': treatmentCode,
        'signatureProvider': signatureProvider,
        'status': status,
        'errorMessage': errorMessage,
      };

  @override
  String toString() {
    final lines = <String>[
      '  Device: ${deviceModel ?? "?"} (${osVersion ?? "?"})',
      '  Device ID: ${deviceId ?? "?"}',
      '  App: ${appVersion ?? "?"}',
      '  Uploaded by: ${uploadedBy ?? "?"}',
      '  Timestamp: ${uploadedAt?.toIso8601String() ?? "?"}',
      if (treatmentCode != null) '  TreatmentCode: $treatmentCode',
      if (documentCode != null) '  DocumentCode: $documentCode',
      if (signatureProvider != null) '  Signature: $signatureProvider',
      if (status != null) '  Status: $status',
      if (errorMessage != null) '  Error: $errorMessage',
    ];
    return lines.join('\n');
  }
}
