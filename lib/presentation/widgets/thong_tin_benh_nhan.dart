// Widget thong_tin_benh_nhan.dart - Hiển thị thông tin bệnh nhân theo style Y Tế Số
// Layout: name + age/gender | ID/HSCC | ICD | bed | room
import 'package:flutter/material.dart';
class ThongTinBenhNhan extends StatelessWidget {
  final Map<String, dynamic> patient;
  final String treatmentCode;
  final Map<String, dynamic>? department;
  final Map<String, dynamic>? room;

  const ThongTinBenhNhan({
    super.key,
    required this.patient,
    required this.treatmentCode,
    this.department,
    this.room,
  });

  String _g(List<String> keys, {String fallback = ''}) {
    for (final k in keys) {
      final v = patient[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final name = _g(['TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME', 'tdl_patient_name', 'VIR_PATIENT_NAME', 'HOTENBN', 'TEN_BENH_NHAN']);
    final dob = _g(['TDL_PATIENT_DOB', 'tdl_patient_dob', 'NGAYSINH', 'DOB']);
    final gender = _g(['TDL_PATIENT_GENDER_NAME', 'tdl_patient_gender_name', 'GENDER_NAME', 'GIOITINH']);
    final patientCode = _g(['TDL_PATIENT_CODE', 'tdl_patient_code', 'MABN', 'PATIENT_CODE']);
    final icdCode = _g(['ICD_CODE', 'icd_code']);
    final icdName = _g(['ICD_NAME', 'ICD_TEXT', 'icd_name']);
    final bedName = _g(['TENGIUONG', 'BED_NAME']);
    final roomName = room?['RoomName']?.toString() ?? department?['name']?.toString() ?? '';
    final roomCode = room?['RoomCode']?.toString() ?? department?['code']?.toString() ?? '';

    // Tuổi tính từ DOB (format yyyymmddhhmmss)
    String ageText = '';
    if (dob.isNotEmpty && dob.length >= 4) {
      try {
        final year = int.parse(dob.substring(0, 4));
        final age = DateTime.now().year - year;
        ageText = '$age tuổi';
      } catch (_) {}
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header xanh dương - tên BN
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'Bệnh nhân',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (ageText.isNotEmpty || gender.isNotEmpty)
                        Text(
                          '$ageText${ageText.isNotEmpty && gender.isNotEmpty ? " - " : ""}$gender',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (roomCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      roomCode,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          // Body - thông tin chi tiết
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (patientCode.isNotEmpty)
                  _row(Icons.badge, 'Mã BN', patientCode),
                if (treatmentCode.isNotEmpty)
                  _row(Icons.medical_information, 'Mã ĐT', treatmentCode),
                if (roomName.isNotEmpty)
                  _row(Icons.bed, 'Phòng', roomName),
                if (bedName.isNotEmpty)
                  _row(Icons.airline_seat_individual_suite, 'Giường', bedName),
                if (icdCode.isNotEmpty || icdName.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFFFB74D), width: 0.5),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.medical_services, color: Color(0xFFE65100), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (icdCode.isNotEmpty)
                                Text(
                                  icdCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                              if (icdName.isNotEmpty)
                                Text(
                                  icdName,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF6D4C41)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF607D8B)),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: Color(0xFF455A64))),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF263238)),
            ),
          ),
        ],
      ),
    );
  }
}
