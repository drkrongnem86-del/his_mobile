/// Phiếu (Form) Model - định nghĩa các loại phiếu y tế trong HIS Pro
/// Mỗi phiếu có:
///   - id (Mps code) - định danh template
///   - name - tên phiếu
///   - category - nhóm (KBVV, điều trị, chẩn đoán, hành chính)
///   - saveType - Lưu (HIS only) / LưuKý (HIS + EMR + ký số)
library;
import 'package:flutter/material.dart';

/// Loại phiếu (phân loại chức năng)
enum PhieuCategory {
  khamBenh('Khám bệnh', Icons.medical_information_outlined),
  dieuTri('Điều trị', Icons.monitor_heart_outlined),
  chanDoan('Chẩn đoán / CLS', Icons.science_outlined),
  hoiChan('Hội chẩn', Icons.groups_outlined),
  banGiao('Bàn giao', Icons.swap_horiz_outlined),
  hanhChinh('Hành chính', Icons.assignment_outlined),
  donThuoc('Đơn thuốc', Icons.medication_outlined),
  thuPhi('Thu phí', Icons.account_balance_wallet_outlined);

  final String label;
  final IconData icon;
  const PhieuCategory(this.label, this.icon);
}

/// Loại save của phiếu
enum PhieuSaveType {
  /// Chỉ lưu HIS - không qua EMR
  hisOnly,

  /// Lưu + ký số + đẩy lên EMR portal (EmrSignNow)
  hisAndSignEmr,
}

/// Loại field input
enum PhieuFieldType {
  text,           // Text ngắn
  textLong,       // Text dài (textarea)
  number,         // Số
  date,           // Ngày (YYYY-MM-DD)
  dateTime,       // Ngày giờ
  select,         // Dropdown (static options)
  deptSelect,     // v2.56.0: Dropdown chọn khoa từ AppConstants.departments
  bool_,          // Checkbox
  icd,            // Mã ICD (search + edit name)
  icdSuggest,     // v2.56.0: Mã ICD gợi ý multi-select + edit name
  icdText,        // v2.57.0: 2 phần - ICD (search) + text mô tả chẩn đoán tuỳ ý
  medicine,       // Đơn thuốc (list nhiều dòng)
  service,        // Dịch vụ CLS (search 33k items)
  signature,      // Ký số
}

/// Field của phiếu (input form)
class PhieuField {
  final String key;          // Token trong template: <#KEY;>
  final String label;        // Label hiển thị
  final PhieuFieldType type;
  final bool required;
  final List<String>? options;
  final String? defaultValue;
  final String? helpText;     // Gợi ý nhập
  final String? unit;         // v2.56.0: đơn vị (vd "mmHg", "lần/ngày")

  const PhieuField({
    required this.key,
    required this.label,
    this.type = PhieuFieldType.text,
    this.required = false,
    this.options,
    this.defaultValue,
    this.helpText,
    this.unit,
  });
}

/// Phiếu definition
class Phieu {
  final String id;              // Mps000062
  final String code;            // 062
  final String name;            // Tờ điều trị
  final String description;     // Mô tả
  final PhieuCategory category;
  final PhieuSaveType saveType;
  final IconData icon;
  final Color color;
  final List<PhieuField> fields;
  final String? templateUrl;    // URL template gốc

  const Phieu({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.category,
    required this.saveType,
    required this.icon,
    required this.color,
    this.fields = const [],
    this.templateUrl,
  });

  /// Có cần ký số không?
  bool get canSignEmr => saveType == PhieuSaveType.hisAndSignEmr;

  /// Số button save
  int get saveButtonCount => canSignEmr ? 2 : 1;
}