// api_source_notifier.dart v3.1.09
// Single source of truth cho API connection source trong app
// - Trước đây: mỗi screen (HomeScreen, DepartmentPatientPage, ProcedureRoomScreen) có
//   enum API source riêng (PatientApiSource, DeptPatientApiSource, ProcedureApiSource)
//   → 2-3 chỗ hiển thị selector chồng chéo
// - v3.1.09: Gộp về 1 enum AppApiSource + ValueNotifier global
//   - HomeScreen top pill ghi vào notifier
//   - ProcedureRoomScreen (embedded) đọc từ notifier
//   - DepartmentPatientPage (embedded) đọc từ notifier
//   - Mỗi screen vẫn có selector riêng nếu cần, nhưng thay đổi ở chỗ nào thì chỗ khác tự cập nhật
//
// Singleton: AppApiSourceNotifier.instance.value = AppApiSource.dataRoom;
//
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// AppApiSource - nguồn API dùng chung cho toàn app
/// 4 options giống PatientApiSource / DeptPatientApiSource cũ
enum AppApiSource {
  dataRoom,  // Data 3000 buồng bệnh (mặc định - nhanh nhất)
  dataDept,  // Data 3000 toàn khoa (fallback khi dataRoom fail)
  hisPro,    // HIS Pro 1408 (qua VPN/LAN)
  public,    // Public 113.163.187.3:8080 (Internet)
}

extension AppApiSourceX on AppApiSource {
  /// Label ngắn cho SegmentedButton
  String get shortLabel {
    switch (this) {
      case AppApiSource.dataRoom: return '🌐 API 2';
      case AppApiSource.dataDept: return '📋 Data';
      case AppApiSource.hisPro:   return '🏥 API 1';
      case AppApiSource.public:   return '🌍 Public';
    }
  }
  /// Label đầy đủ cho menu
  String get fullLabel {
    switch (this) {
      case AppApiSource.dataRoom: return 'API 2 - Data 3000 (buồng bệnh)';
      case AppApiSource.dataDept: return 'API - Data 3000 (toàn khoa)';
      case AppApiSource.hisPro:   return 'API 1 - HIS Pro 1408 (qua VPN)';
      case AppApiSource.public:   return 'API Public - 113.163.187.3:8080';
    }
  }
  /// Sub label cho procedure room chips
  String get subLabel {
    switch (this) {
      case AppApiSource.dataRoom: return 'Data 3000';
      case AppApiSource.dataDept: return 'Data 3000';
      case AppApiSource.hisPro:   return 'LAN/VPN';
      case AppApiSource.public:   return 'Internet';
    }
  }
  /// Màu cho chip/button
  Color get color {
    switch (this) {
      case AppApiSource.dataRoom: return const Color(0xFF00838F);
      case AppApiSource.dataDept: return const Color(0xFF00ACC1);
      case AppApiSource.hisPro:   return const Color(0xFF6A1B9A);
      case AppApiSource.public:   return const Color(0xFF0277BD);
    }
  }
  /// URL mô tả
  String get url {
    switch (this) {
      case AppApiSource.dataRoom: return 'POST /v1/patient/benh-nhan-buong-benh';
      case AppApiSource.dataDept: return 'POST /v1/patient/benh-nhan-khoa';
      case AppApiSource.hisPro:   return 'POST /api/HisTreatment/GetView?param=BASE64';
      case AppApiSource.public:   return 'GET /emr/index (Data public)';
    }
  }
}

/// Singleton notifier - ai cũng đọc/ghi được
class AppApiSourceNotifier {
  AppApiSourceNotifier._();
  static final AppApiSourceNotifier instance = AppApiSourceNotifier._();

  // v3.1.14: Đổi default sang hisPro (API 1) - để align với HIS Desktop data
  // Fallback tự động chuyển sang dataRoom/public nếu HIS Pro không truy cập được
  final ValueNotifier<AppApiSource> notifier = ValueNotifier<AppApiSource>(AppApiSource.hisPro);

  AppApiSource get value => notifier.value;
  set value(AppApiSource src) {
    if (notifier.value != src) {
      notifier.value = src;
    }
  }

  /// Cycle qua các API sources (cho ←/→ button)
  AppApiSource next() {
    final values = AppApiSource.values;
    final idx = values.indexOf(notifier.value);
    final nextIdx = (idx + 1) >= values.length ? 0 : idx + 1;
    notifier.value = values[nextIdx];
    return notifier.value;
  }
  AppApiSource prev() {
    final values = AppApiSource.values;
    final idx = values.indexOf(notifier.value);
    final prevIdx = (idx - 1) < 0 ? values.length - 1 : idx - 1;
    notifier.value = values[prevIdx];
    return notifier.value;
  }
}
