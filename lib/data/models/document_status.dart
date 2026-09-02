// DocumentStatus v3.0.37 - State machine cho upload queue
// - draft: mới scan, chưa push EMR
// - uploaded: đã push EMR unsigned, chưa ký
// - signed: đã ký (PKCS#7 hoặc IsFinishSign=true)
// - signedReal: có PKCS#7 thật (qua SmartCA/PFX)
// - failed: push EMR thất bại (network/auth) - cho phép retry
// - pendingRetry: đang chờ retry (mất VPN, timeout) - sẽ tự động retry khi có mạng
//
// State machine (theo spec BS 2026-07-17):
//   draft → uploaded → signed → signedReal
//     ↓         ↓         ↓
//   failed   failed    failed
//     ↓         ↓         ↓
//  pendingRetry ← ← ← ← (auto-retry khi VPN OK)
enum DocumentStatus {
  draft,
  uploaded,
  signed,
  signedReal,
  failed,
  pendingRetry,
}

extension DocumentStatusX on DocumentStatus {
  String get label {
    switch (this) {
      case DocumentStatus.draft:
        return 'Nháp (chưa upload)';
      case DocumentStatus.uploaded:
        return 'Đã upload (chưa ký)';
      case DocumentStatus.signed:
        return 'Đã ký (chưa có PKCS#7)';
      case DocumentStatus.signedReal:
        return 'Đã ký số (có PKCS#7)';
      case DocumentStatus.failed:
        return 'Lỗi (chưa upload được)';
      case DocumentStatus.pendingRetry:
        return 'Chờ retry (mất mạng/VPN)';
    }
  }

  String get shortLabel {
    switch (this) {
      case DocumentStatus.draft:
        return 'Nháp';
      case DocumentStatus.uploaded:
        return 'Uploaded';
      case DocumentStatus.signed:
        return 'Signed';
      case DocumentStatus.signedReal:
        return 'Signed PKCS#7';
      case DocumentStatus.failed:
        return 'Failed';
      case DocumentStatus.pendingRetry:
        return 'PendingRetry';
    }
  }

  /// Parse từ string (lưu SharedPreferences)
  static DocumentStatus fromString(String? s) {
    switch (s) {
      case 'draft': return DocumentStatus.draft;
      case 'uploaded': return DocumentStatus.uploaded;
      case 'signed': return DocumentStatus.signed;
      case 'signed_real': return DocumentStatus.signedReal;
      case 'failed': return DocumentStatus.failed;
      case 'pending_retry': return DocumentStatus.pendingRetry;
      default: return DocumentStatus.draft;
    }
  }

  /// Có thể retry không
  bool get canRetry =>
      this == DocumentStatus.failed || this == DocumentStatus.pendingRetry;

  /// Có thể xóa khỏi queue không
  bool get canRemove =>
      this == DocumentStatus.failed ||
      this == DocumentStatus.pendingRetry ||
      this == DocumentStatus.draft;
}
