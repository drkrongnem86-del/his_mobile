import 'package:equatable/equatable.dart';

/// Patient model - Bệnh nhân trong HIS Pro
class Patient extends Equatable {
  final String id;
  final String patientCode;
  final String heinCardNumber;
  final String patientName;
  final int? gender;
  final DateTime? dob;
  final String? address;
  final String? phone;
  final String? ethnicity;
  final String? nationality;
  final String? occupation;
  final String? workplace;
  final String? guardianName;
  final String? guardianPhone;
  final DateTime? createTime;

  const Patient({
    required this.id,
    required this.patientCode,
    required this.heinCardNumber,
    required this.patientName,
    this.gender,
    this.dob,
    this.address,
    this.phone,
    this.ethnicity,
    this.nationality,
    this.occupation,
    this.workplace,
    this.guardianName,
    this.guardianPhone,
    this.createTime,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['ID']?.toString() ?? '',
      patientCode: json['PATIENT_CODE'] ?? json['patientCode'] ?? '',
      heinCardNumber: json['HEIN_CARD_NUMBER'] ?? json['heinCardNumber'] ?? '',
      patientName: json['PATIENT_NAME'] ?? json['patientName'] ?? '',
      gender: json['GENDER'] ?? json['gender'],
      dob: _parseDate(json['DOB'] ?? json['dob']),
      address: json['ADDRESS'] ?? json['address'],
      phone: json['PHONE'] ?? json['phone'],
      ethnicity: json['ETHNICITY_CODE'] ?? json['ethnicity'],
      nationality: json['NATIONALITY_NAME'] ?? json['nationality'],
      occupation: json['WORK_PLACE'] ?? json['occupation'],
      workplace: json['WORK_PLACE'] ?? json['workplace'],
      guardianName: json['GUARDIAN_NAME'] ?? json['guardianName'],
      guardianPhone: json['GUARDIAN_PHONE'] ?? json['guardianPhone'],
      createTime: _parseDate(json['CREATE_TIME'] ?? json['createTime']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try { return DateTime.parse(value); } catch (_) { return null; }
    }
    return null;
  }

  int? get age {
    if (dob == null) return null;
    final now = DateTime.now();
    int age = now.year - dob!.year;
    if (now.month < dob!.month || (now.month == dob!.month && now.day < dob!.day)) age--;
    return age;
  }

  String get genderName {
    if (gender == 1) return 'Nam';
    if (gender == 2) return 'Nữ';
    return 'Khác';
  }

  @override
  List<Object?> get props => [id, patientCode, patientName];
}

/// Treatment - Phiên điều trị
class Treatment extends Equatable {
  final String id;
  final String treatmentCode;
  final DateTime? inTime;
  final DateTime? outTime;
  final int? treatmentTypeId;
  final String? treatmentTypeName;
  final String? icdCode;
  final String? icdName;
  final String? departmentId;
  final String? departmentName;
  final String? doctorUsername;
  final String? doctorName;
  final Patient? patient;

  const Treatment({
    required this.id,
    required this.treatmentCode,
    this.inTime,
    this.outTime,
    this.treatmentTypeId,
    this.treatmentTypeName,
    this.icdCode,
    this.icdName,
    this.departmentId,
    this.departmentName,
    this.doctorUsername,
    this.doctorName,
    this.patient,
  });

  factory Treatment.fromJson(Map<String, dynamic> json) {
    return Treatment(
      id: json['ID']?.toString() ?? '',
      treatmentCode: json['TREATMENT_CODE'] ?? json['treatmentCode'] ?? '',
      inTime: _parseDate(json['IN_TIME'] ?? json['inTime']),
      outTime: _parseDate(json['OUT_TIME'] ?? json['outTime']),
      treatmentTypeId: json['TREATMENT_TYPE_ID'],
      treatmentTypeName: json['TREATMENT_TYPE_NAME'] ?? json['treatmentTypeName'],
      icdCode: json['ICD_CODE'] ?? json['icdCode'],
      icdName: json['ICD_NAME'] ?? json['icdName'],
      departmentId: json['DEPARTMENT_ID']?.toString(),
      departmentName: json['DEPARTMENT_NAME'] ?? json['departmentName'],
      doctorUsername: json['DOCTOR_USERNAME'] ?? json['doctorUsername'],
      doctorName: json['DOCTOR_NAME'] ?? json['doctorName'],
      patient: json['PATIENT'] != null ? Patient.fromJson(json['PATIENT']) : null,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try { return DateTime.parse(value); } catch (_) { return null; }
    }
    return null;
  }

  String get status {
    if (outTime != null) return 'Đã ra viện';
    if (inTime != null) return 'Đang điều trị';
    return 'Chờ tiếp nhận';
  }

  @override
  List<Object?> get props => [id, treatmentCode];
}

/// Vital Signs - Sinh hiệu
class VitalSign extends Equatable {
  final String id;
  final String treatmentId;
  final DateTime? measuredTime;
  final double? pulse;
  final double? temperature;
  final double? systolicBp;
  final double? diastolicBp;
  final double? spo2;
  final double? respiratoryRate;
  final double? weight;
  final double? height;

  const VitalSign({
    required this.id,
    required this.treatmentId,
    this.measuredTime,
    this.pulse,
    this.temperature,
    this.systolicBp,
    this.diastolicBp,
    this.spo2,
    this.respiratoryRate,
    this.weight,
    this.height,
  });

  factory VitalSign.fromJson(Map<String, dynamic> json) {
    return VitalSign(
      id: json['ID']?.toString() ?? '',
      treatmentId: json['TREATMENT_ID']?.toString() ?? '',
      measuredTime: _parseDate(json['MEASURED_TIME'] ?? json['measuredTime']),
      pulse: _parseDouble(json['PULSE'] ?? json['pulse']),
      temperature: _parseDouble(json['TEMPERATURE'] ?? json['temperature']),
      systolicBp: _parseDouble(json['SYSTOLIC_BP'] ?? json['systolicBp']),
      diastolicBp: _parseDouble(json['DIASTOLIC_BP'] ?? json['diastolicBp']),
      spo2: _parseDouble(json['SPO2'] ?? json['spo2']),
      respiratoryRate: _parseDouble(json['RESPIRATORY_RATE'] ?? json['respiratoryRate']),
      weight: _parseDouble(json['WEIGHT'] ?? json['weight']),
      height: _parseDouble(json['HEIGHT'] ?? json['height']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try { return DateTime.parse(value); } catch (_) { return null; }
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String get bloodPressure => '${systolicBp?.toInt() ?? '-'}/${diastolicBp?.toInt() ?? '-'}';

  @override
  List<Object?> get props => [id, treatmentId, measuredTime];
}
