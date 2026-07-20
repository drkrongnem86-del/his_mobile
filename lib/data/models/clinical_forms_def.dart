// Định nghĩa các loại phiếu trong hệ thống HIS Pro
// Mapping với file Mps template gốc từ D:\Soft\HISPRO_THAT\Tmp\Mps
// Mỗi form được render bằng cách fill placeholders <#FIELD;> vào file xlsx
import 'package:flutter/material.dart';

enum FormFieldType {
  text,        // text ngắn
  paragraph,   // text dài, multi-line
  number,      // số
  decimal,     // số thập phân
  date,        // ngày
  time,        // giờ
  datetime,    // ngày + giờ
  select,      // chọn từ danh sách
  icd,         // chọn ICD-10
  service,     // mã dịch vụ BHYT
  bp,          // huyết áp (max/min)
  checkbox,    // check
  signature,   // chữ ký số (tên BS)
  multiline,   // multi-line
}

class FormFieldDef {
  final String key;          // key lưu trữ
  final String label;        // label hiển thị
  final String hint;         // placeholder
  final FormFieldType type;
  final bool required;
  final List<String> options; // for select
  final String? unit;        // đơn vị (mmHg, °C, etc.)
  final double? minVal;
  final double? maxVal;
  final String? icdChapter;  // for ICD
  final int? maxLength;
  final int? rows;           // for paragraph/multiline

  const FormFieldDef({
    required this.key,
    required this.label,
    this.hint = '',
    required this.type,
    this.required = false,
    this.options = const [],
    this.unit,
    this.minVal,
    this.maxVal,
    this.icdChapter,
    this.maxLength,
    this.rows,
  });
}

class FormDef {
  final String id;            // form_id unique
  final String name;          // tên hiển thị
  final String shortName;     // tên ngắn cho tab
  final String mpsFile;       // file Mps template gốc
  final int iconCodePoint;    // Flutter icon code point
  final int colorValue;       // màu sắc
  final String category;      // nhóm: 'tiep_nhan', 'chi_dinh', 'dieu_tri', 'theo_doi', 'hoi_chuan', 'ky'
  final List<FormFieldDef> fields;
  final String description;

  const FormDef({
    required this.id,
    required this.name,
    required this.shortName,
    required this.mpsFile,
    required this.iconCodePoint,
    required this.colorValue,
    required this.category,
    required this.fields,
    required this.description,
  });
}

// Use placeholder IconData (just a marker; real mapping in screen)
// We'll use a real IconData subclass workaround via static constants.
// (In Flutter, IconData can't be const-constructed cleanly across files,
// so we keep the iconCodePoint + fontFamily approach.)

class FormDefRegistry {
  /// 7 phiếu chính trong workflow ICU
  static const List<FormDef> all = [
    // ============================================================
    // 1. PHIẾU KHÁM VÀO VIỆN (Admission note)
    // Source: Mps000007 BieuMauPhieuYeuCauKhamBenhVaoVien
    // ============================================================
    FormDef(
      id: 'phieu_kham_vao_vien',
      name: 'Phiếu khám vào viện',
      shortName: 'Khám vào viện',
      mpsFile: 'Mps000007__BieuMauPhieuYeuCauKhamBenhVaoVien___.xlsx',
      iconCodePoint: 0xe1b7, // Icons.assignment_ind
      colorValue: 0xFF1A73E8,
      category: 'tiep_nhan',
      description: 'Phiếu khám ban đầu khi nhập viện - khai thác tiền sử, khám lâm sàng, chẩn đoán sơ bộ',
      fields: [
        FormFieldDef(key: 'PATIENT_NAME', label: 'Họ tên bệnh nhân', type: FormFieldType.text, required: true, maxLength: 100),
        FormFieldDef(key: 'PATIENT_CODE', label: 'Mã BN', type: FormFieldType.text, hint: 'Mã hồ sơ', maxLength: 30),
        FormFieldDef(key: 'PATIENT_DOB', label: 'Ngày sinh', type: FormFieldType.date, required: true),
        FormFieldDef(key: 'TDL_PATIENT_GENDER_NAME', label: 'Giới tính', type: FormFieldType.select, required: true, options: ['Nam', 'Nữ', 'Khác']),
        FormFieldDef(key: 'CAREER_CODE', label: 'Nghề nghiệp (mã)', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'PATIENT_CAREER_NAME', label: 'Nghề nghiệp', type: FormFieldType.text, maxLength: 100),
        FormFieldDef(key: 'NATIONAL_CODE', label: 'Mã dân tộc', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'NATIONAL_NAME', label: 'Dân tộc', type: FormFieldType.text, maxLength: 50),
        FormFieldDef(key: 'ETHNIC_CODE', label: 'Mã quốc tịch', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'ETHNIC_NAME', label: 'Quốc tịch', type: FormFieldType.text, maxLength: 50),
        FormFieldDef(key: 'PROVINCE_CODE', label: 'Mã tỉnh/TP', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'PROVINCE_NAME', label: 'Tỉnh/TP', type: FormFieldType.text, maxLength: 50),
        FormFieldDef(key: 'DISTRICT_CODE', label: 'Mã huyện/Q', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'DISTRICT_NAME', label: 'Huyện/Quận', type: FormFieldType.text, maxLength: 50),
        FormFieldDef(key: 'COMMUNE_NAME', label: 'Xã/Phường', type: FormFieldType.text, maxLength: 50),
        FormFieldDef(key: 'VIR_ADDRESS', label: 'Địa chỉ', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'RELATIVE_NAME', label: 'Người thân', type: FormFieldType.text, maxLength: 100),
        FormFieldDef(key: 'RELATIVE_TYPE', label: 'Quan hệ', type: FormFieldType.text, hint: 'VD: Con trai, Vợ', maxLength: 50),
        FormFieldDef(key: 'RELATIVE_PHONE', label: 'SĐT người thân', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'PHONE', label: 'SĐT bệnh nhân', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'HEIN_CARD_NUMBER', label: 'Số thẻ BHYT', type: FormFieldType.text, maxLength: 30),
        FormFieldDef(key: 'STR_HEIN_CARD_FROM_TIME', label: 'BHYT từ', type: FormFieldType.date),
        FormFieldDef(key: 'STR_HEIN_CARD_TO_TIME', label: 'BHYT đến', type: FormFieldType.date),
        FormFieldDef(key: 'HEIN_MEDI_ORG_CODE', label: 'Mã KCB', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'PATIENT_TYPE_NAME', label: 'Đối tượng', type: FormFieldType.text, maxLength: 100),
        FormFieldDef(key: 'WORK_PLACE_NAME', label: 'Nơi làm việc', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'HOSPITALIZATION_REASON', label: 'Lý do nhập viện', type: FormFieldType.paragraph, required: true, rows: 3),
        FormFieldDef(key: 'PATHOLOGICAL_HISTORY', label: 'Tiền sử bệnh', type: FormFieldType.paragraph, rows: 4),
        FormFieldDef(key: 'PATHOLOGICAL_HISTORY_FAMILY', label: 'Tiền sử gia đình', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'PATHOLOGICAL_PROCESS', label: 'Quá trình bệnh lý', type: FormFieldType.paragraph, required: true, rows: 4),
        FormFieldDef(key: 'FULL_EXAM', label: 'Khám toàn thân', type: FormFieldType.paragraph, rows: 4),
        FormFieldDef(key: 'PART_EXAM', label: 'Khám bộ phận', type: FormFieldType.paragraph, rows: 4),
        FormFieldDef(key: 'TEMPERATURE', label: 'Nhiệt độ', type: FormFieldType.decimal, unit: '°C', minVal: 30, maxVal: 45),
        FormFieldDef(key: 'PULSE', label: 'Mạch', type: FormFieldType.number, unit: 'lần/ph', minVal: 0, maxVal: 250),
        FormFieldDef(key: 'BREATH_RATE', label: 'Nhịp thở', type: FormFieldType.number, unit: 'lần/ph', minVal: 0, maxVal: 80),
        FormFieldDef(key: 'WEIGHT', label: 'Cân nặng', type: FormFieldType.decimal, unit: 'kg', minVal: 0, maxVal: 500),
        FormFieldDef(key: 'HEIGHT', label: 'Chiều cao', type: FormFieldType.decimal, unit: 'cm', minVal: 0, maxVal: 250),
        FormFieldDef(key: 'BLOOD_PRESSURE_MAX', label: 'HA tâm thu', type: FormFieldType.number, unit: 'mmHg', minVal: 0, maxVal: 300),
        FormFieldDef(key: 'BLOOD_PRESSURE_MIN', label: 'HA tâm trương', type: FormFieldType.number, unit: 'mmHg', minVal: 0, maxVal: 200),
        FormFieldDef(key: 'SPO2', label: 'SpO2', type: FormFieldType.number, unit: '%', minVal: 0, maxVal: 100),
        FormFieldDef(key: 'SUBCLINICAL', label: 'Cận lâm sàng', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'CLS_NAMES', label: 'Tên CLS đã làm', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'DHST_NOTE', label: 'Ghi chú DHST', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'ICD_CODE', label: 'Mã ICD-10', type: FormFieldType.icd, icdChapter: 'all', required: true),
        FormFieldDef(key: 'ICD_NAME', label: 'Tên bệnh', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'IN_CODE', label: 'Mã vào viện', type: FormFieldType.text, maxLength: 30),
        FormFieldDef(key: 'IN_ICD_SUB_CODE', label: 'Mã phụ', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'IN_ICD_TEXT', label: 'Chẩn đoán vào viện', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'TRANSFER_IN_ICD_CODE', label: 'Mã ICD chuyển đến', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'TRANSFER_IN_ICD_NAME', label: 'Tên ICD chuyển đến', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'NEXT_DEPARTMENT_NAME', label: 'Khoa điều trị', type: FormFieldType.text, maxLength: 100),
        FormFieldDef(key: 'TREATMENT_INSTRUCTION', label: 'Hướng điều trị', type: FormFieldType.paragraph, rows: 4),
        FormFieldDef(key: 'TREATMENT_ORDER', label: 'Y lệnh', type: FormFieldType.paragraph, rows: 4),
        FormFieldDef(key: 'NOTE', label: 'Ghi chú', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'SERVICE_REQ__NOTE', label: 'Ghi chú CLS', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'IN_USERNAME', label: 'Bác sĩ khám', type: FormFieldType.signature, required: true),
        FormFieldDef(key: 'CLINICAL_IN_TIME', label: 'Giờ vào khám', type: FormFieldType.datetime),
        FormFieldDef(key: 'FINISH_TIME', label: 'Giờ kết thúc', type: FormFieldType.datetime),
        FormFieldDef(key: 'CREATE_TIME_TRAN', label: 'Ngày tạo', type: FormFieldType.datetime),
      ],
    ),

    // ============================================================
    // 2. PHIẾU CHỈ ĐỊNH (Service request) - theo mã dịch vụ
    // Source: Mps000037 PhieuYeuCauChiDinhTongHop
    // ============================================================
    FormDef(
      id: 'phieu_chi_dinh',
      name: 'Phiếu chỉ định dịch vụ',
      shortName: 'Chỉ định',
      mpsFile: 'MPS000037__PhieuYeuCauChiDinhTongHop___A4D_001.xlsx',
      iconCodePoint: 0xe3ab, // Icons.assignment
      colorValue: 0xFFEA4335,
      category: 'chi_dinh',
      description: 'Phiếu yêu cầu CLS - chọn dịch vụ, nhập chỉ định lâm sàng',
      fields: [
        FormFieldDef(key: 'service_code', label: 'Mã dịch vụ BHYT', type: FormFieldType.service, required: true, maxLength: 20),
        FormFieldDef(key: 'service_name', label: 'Tên dịch vụ', type: FormFieldType.text, required: true, maxLength: 200),
        FormFieldDef(key: 'clinical_indication', label: 'Chỉ định lâm sàng', type: FormFieldType.paragraph, required: true, rows: 3),
        FormFieldDef(key: 'icd_code', label: 'Mã ICD liên quan', type: FormFieldType.icd, icdChapter: 'all'),
        FormFieldDef(key: 'priority', label: 'Mức độ ưu tiên', type: FormFieldType.select, options: ['Thường', 'Cấp cứu', 'Ưu tiên cao']),
        FormFieldDef(key: 'is_bhyt', label: 'Áp dụng BHYT', type: FormFieldType.checkbox),
        FormFieldDef(key: 'note', label: 'Ghi chú', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'request_username', label: 'Bác sĩ chỉ định', type: FormFieldType.signature, required: true),
        FormFieldDef(key: 'request_time', label: 'Thời gian chỉ định', type: FormFieldType.datetime),
      ],
    ),

    // ============================================================
    // 3. TỜ ĐIỀU TRỊ (Treatment sheet)
    // Source: Mps000072 BieuMauPhieuYeuCauInToDieuTriTongHop_V2
    // ============================================================
    FormDef(
      id: 'to_dieu_tri',
      name: 'Tờ điều trị',
      shortName: 'Tờ ĐT',
      mpsFile: 'Mps000072__BieuMauPhieuYeuCauInToDieuTriTongHop___001_V2.xlsx',
      iconCodePoint: 0xe558, // Icons.assignment_turned_in
      colorValue: 0xFF34A853,
      category: 'dieu_tri',
      description: 'Tờ điều trị tổng hợp - theo dõi y lệnh, chẩn đoán, DHST hàng ngày',
      fields: [
        FormFieldDef(key: 'TREATMENT_CODE', label: 'Mã ĐT', type: FormFieldType.text, maxLength: 30),
        FormFieldDef(key: 'ICD_NAME', label: 'Bệnh chính', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'ICD_CODE', label: 'Mã ICD', type: FormFieldType.icd),
        FormFieldDef(key: 'ICD_TEXT', label: 'Chẩn đoán đầy đủ', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'ICD_MAIN_TEXT', label: 'Chẩn đoán chính', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'TEMPERATURE', label: 'Nhiệt độ', type: FormFieldType.decimal, unit: '°C'),
        FormFieldDef(key: 'PULSE', label: 'Mạch', type: FormFieldType.number, unit: 'lần/ph'),
        FormFieldDef(key: 'BREATH_RATE', label: 'Nhịp thở', type: FormFieldType.number, unit: 'lần/ph'),
        FormFieldDef(key: 'BLOOD_PRESSURE_MAX', label: 'HA tâm thu', type: FormFieldType.number, unit: 'mmHg'),
        FormFieldDef(key: 'BLOOD_PRESSURE_MIN', label: 'HA tâm trương', type: FormFieldType.number, unit: 'mmHg'),
        FormFieldDef(key: 'WEIGHT', label: 'Cân nặng', type: FormFieldType.decimal, unit: 'kg'),
        FormFieldDef(key: 'MEDICAL_INSTRUCTION', label: 'Y lệnh điều trị', type: FormFieldType.paragraph, rows: 5, required: true),
        FormFieldDef(key: 'CONTENT', label: 'Nội dung theo dõi', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'TRACKING_TIME_STR', label: 'Ngày theo dõi', type: FormFieldType.date),
        FormFieldDef(key: 'BED_NAME', label: 'Giường', type: FormFieldType.text, maxLength: 50),
        FormFieldDef(key: 'PRES_NAME', label: 'Thuốc', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'PRES_DETAIL', label: 'Chi tiết thuốc', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'MISU_NAME', label: 'Y lệnh CS', type: FormFieldType.text, maxLength: 100),
        FormFieldDef(key: 'MISU_DETAIL', label: 'Chi tiết CS', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'OTHER_NAME', label: 'Khác', type: FormFieldType.text, maxLength: 100),
        FormFieldDef(key: 'OTHER_DETAIL', label: 'Chi tiết khác', type: FormFieldType.paragraph, rows: 2),
      ],
    ),

    // ============================================================
    // 4. PHIẾU CHẸ SÓC (Care sheet)
    // Source: Mps000069 BieuMauPhieuYeuCauKetQuaChamSoc
    // ============================================================
    FormDef(
      id: 'phieu_cham_soc',
      name: 'Phiếu chăm sóc',
      shortName: 'Chăm sóc',
      mpsFile: 'Mps000069__BieuMauPhieuYeuCauKetQuaChamSoc___001.xlsx',
      iconCodePoint: 0xe138, // Icons.healing
      colorValue: 0xFFFBBC04,
      category: 'theo_doi',
      description: 'Phiếu chăm sóc hàng ngày - 6 ca, theo dõi bệnh nhân chi tiết',
      fields: [
        FormFieldDef(key: 'care_date', label: 'Ngày chăm sóc', type: FormFieldType.date, required: true),
        FormFieldDef(key: 'shift', label: 'Ca trực', type: FormFieldType.select, required: true, options: ['Sáng (6h-14h)', 'Chiều (14h-22h)', 'Đêm (22h-6h)']),
        FormFieldDef(key: 'CARE_DETAIL', label: 'Mô tả chăm sóc ca 1', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'CARE_1', label: 'Chăm sóc ca 1 (sáng)', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'CARE_TITLE1', label: 'Tiêu đề ca 1', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'CARE_DETAIL_1', label: 'Chi tiết ca 1', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'CARE_2', label: 'Chăm sóc ca 2 (chiều)', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'CARE_TITLE2', label: 'Tiêu đề ca 2', type: FormFieldType.text, maxLength: 200),
        FormFieldDef(key: 'CARE_DETAIL_2', label: 'Chi tiết ca 2', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'CARE_3', label: 'Chăm sóc ca 3 (đêm)', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'CARE_DETAIL_3', label: 'Chi tiết ca 3', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'CARE_4', label: 'Chăm sóc thêm 1', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'CARE_DETAIL_4', label: 'Chi tiết thêm 1', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'CARE_5', label: 'Chăm sóc thêm 2', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'CARE_DETAIL_5', label: 'Chi tiết thêm 2', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'CARE_6', label: 'Chăm sóc thêm 3', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'CARE_DETAIL_6', label: 'Chi tiết thêm 3', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'nurse_signature', label: 'Điều dưỡng ký', type: FormFieldType.signature, required: true),
        FormFieldDef(key: 'care_note', label: 'Ghi chú', type: FormFieldType.paragraph, rows: 2),
      ],
    ),

    // ============================================================
    // 5. PHIẾU THEO DÕI SINH HIỆU (Vital signs monitoring)
    // Source: Mps000293 Mps000287 PhieuTheoDoiChucNangSong
    // ============================================================
    FormDef(
      id: 'phieu_theo_doi_sh',
      name: 'Phiếu theo dõi sinh hiệu',
      shortName: 'Theo dõi SH',
      mpsFile: 'Mps000293__Mps000287_PhieuTheoDoiChucNangSong.xlsx',
      iconCodePoint: 0xe87d, // Icons.favorite
      colorValue: 0xFF9334E6,
      category: 'theo_doi',
      description: 'Theo dõi chức năng sống - Mạch, HA, SpO2, nhiệt, tri giác, nước tiểu/24h',
      fields: [
        FormFieldDef(key: 'monitoring_date', label: 'Ngày theo dõi', type: FormFieldType.date, required: true),
        FormFieldDef(key: 'monitoring_time', label: 'Giờ đo', type: FormFieldType.time, required: true),
        FormFieldDef(key: 'pulse', label: 'Mạch', type: FormFieldType.number, unit: 'lần/ph', minVal: 0, maxVal: 250),
        FormFieldDef(key: 'bp_max', label: 'HA tâm thu', type: FormFieldType.number, unit: 'mmHg', minVal: 0, maxVal: 300),
        FormFieldDef(key: 'bp_min', label: 'HA tâm trương', type: FormFieldType.number, unit: 'mmHg', minVal: 0, maxVal: 200),
        FormFieldDef(key: 'temperature', label: 'Nhiệt độ', type: FormFieldType.decimal, unit: '°C', minVal: 30, maxVal: 45),
        FormFieldDef(key: 'spo2', label: 'SpO2', type: FormFieldType.number, unit: '%', minVal: 0, maxVal: 100),
        FormFieldDef(key: 'breath_rate', label: 'Nhịp thở', type: FormFieldType.number, unit: 'lần/ph', minVal: 0, maxVal: 80),
        FormFieldDef(key: 'consciousness', label: 'Tri giác', type: FormFieldType.select, options: ['Tỉnh', 'Lơ mơ', 'Gọi hỏi đáp được', 'Kích thích đau', 'Hôn mê']),
        FormFieldDef(key: 'gcs_score', label: 'GCS', type: FormFieldType.number, minVal: 3, maxVal: 15),
        FormFieldDef(key: 'pupil_left', label: 'Đồng tử (T)', type: FormFieldType.text, hint: 'mm + phản xạ', maxLength: 50),
        FormFieldDef(key: 'pupil_right', label: 'Đồng tử (P)', type: FormFieldType.text, hint: 'mm + phản xạ', maxLength: 50),
        FormFieldDef(key: 'urine_24h', label: 'Nước tiểu 24h', type: FormFieldType.number, unit: 'ml'),
        FormFieldDef(key: 'fluid_in_24h', label: 'Dịch vào 24h', type: FormFieldType.number, unit: 'ml'),
        FormFieldDef(key: 'fluid_out_24h', label: 'Dịch ra 24h', type: FormFieldType.number, unit: 'ml'),
        FormFieldDef(key: 'note', label: 'Ghi chú', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'nurse_signature', label: 'Điều dưỡng ký', type: FormFieldType.signature, required: true),
      ],
    ),

    // ============================================================
    // 6. PHIẾU BÀN GIAO (Handover)
    // Source: Mps000326 Mps000326_PhieuBanGiaoGiayTo
    // ============================================================
    FormDef(
      id: 'phieu_ban_giao',
      name: 'Phiếu bàn giao',
      shortName: 'Bàn giao',
      mpsFile: 'Mps000326__Mps000326_PhieuBanGiaoGiayTo.xlsx',
      iconCodePoint: 0xe8d5, // Icons.swap_horiz
      colorValue: 0xFFFF6D00,
      category: 'ky',
      description: 'Bàn giao giấy tờ / bệnh nhân giữa các ca trực',
      fields: [
        FormFieldDef(key: 'handover_date', label: 'Ngày bàn giao', type: FormFieldType.date, required: true),
        FormFieldDef(key: 'shift_from', label: 'Từ ca', type: FormFieldType.select, required: true, options: ['Sáng', 'Chiều', 'Đêm']),
        FormFieldDef(key: 'shift_to', label: 'Đến ca', type: FormFieldType.select, required: true, options: ['Sáng', 'Chiều', 'Đêm']),
        FormFieldDef(key: 'SEND_DEPARTMENT_NAME', label: 'Khoa gửi', type: FormFieldType.text, maxLength: 100),
        FormFieldDef(key: 'SEND_USERNAME', label: 'Người gửi', type: FormFieldType.signature, required: true),
        FormFieldDef(key: 'RECEIVE_USERNAME', label: 'Người nhận', type: FormFieldType.signature, required: true),
        FormFieldDef(key: 'Description', label: 'Mô tả hồ sơ bàn giao', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'documents', label: 'Hồ sơ kèm theo', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'note', label: 'Ghi chú', type: FormFieldType.paragraph, rows: 2),
      ],
    ),

    // ============================================================
    // 7. BIÊN BẢN HỘI CHẨN (Consultation)
    // Source: Mps000019 HC_BienBanHoiChan__PHAU_THUAT
    // ============================================================
    FormDef(
      id: 'bien_ban_hoi_chan',
      name: 'Biên bản hội chẩn',
      shortName: 'Hội chẩn',
      mpsFile: 'Mps000019__HC_BienBanHoiChan__PHAU_THUAT.xlsx',
      iconCodePoint: 0xe7ef, // Icons.group
      colorValue: 0xFF9C27B0,
      category: 'hoi_chuan',
      description: 'Biên bản hội chẩn liên khoa - trước phẫu thuật / ca khó',
      fields: [
        FormFieldDef(key: 'LOCATION', label: 'Địa điểm', type: FormFieldType.text, required: true, maxLength: 200),
        FormFieldDef(key: 'DEBATE_TIME', label: 'Thời gian bắt đầu', type: FormFieldType.datetime, required: true),
        FormFieldDef(key: 'DEBATE_TIME_STR', label: 'Giờ hội chẩn', type: FormFieldType.text, hint: 'HH:mm', maxLength: 20),
        FormFieldDef(key: 'OPEN_TIME_SEPARATE_STR', label: 'Giờ mở', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'CLOSE_TIME_SEPARATE_STR', label: 'Giờ kết thúc', type: FormFieldType.text, maxLength: 20),
        FormFieldDef(key: 'HOSPITALIZATION_STATE', label: 'Tình trạng nhập viện', type: FormFieldType.text, maxLength: 100),
        FormFieldDef(key: 'TREATMENT_FROM_TIME', label: 'Ngày ĐT', type: FormFieldType.date),
        FormFieldDef(key: 'PATHOLOGICAL_HISTORY', label: 'Tiền sử', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'BEFORE_DIAGNOSTIC', label: 'CĐ trước hội chẩn', type: FormFieldType.paragraph, rows: 2),
        FormFieldDef(key: 'DIAGNOSTIC', label: 'Chẩn đoán xác định', type: FormFieldType.paragraph, required: true, rows: 3),
        FormFieldDef(key: 'CONCLUSION', label: 'Kết luận hội chẩn', type: FormFieldType.paragraph, required: true, rows: 5),
        FormFieldDef(key: 'TREATMENT_TRACKING', label: 'Hướng xử trí', type: FormFieldType.paragraph, required: true, rows: 4),
        FormFieldDef(key: 'USERNAME_PRESIDENT', label: 'Chủ tọa', type: FormFieldType.signature, required: true),
        FormFieldDef(key: 'USERNAME_SECRETARY', label: 'Thư ký', type: FormFieldType.signature, required: true),
        FormFieldDef(key: 'Participants.USERNAME', label: 'Thành viên tham gia', type: FormFieldType.paragraph, rows: 3),
        FormFieldDef(key: 'Participants.DESCRIPTION', label: 'Vai trò TV', type: FormFieldType.paragraph, rows: 2),
      ],
    ),
  ];

  static FormDef? byId(String id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }

  static List<FormDef> byCategory(String category) =>
      all.where((f) => f.category == category).toList();
}
