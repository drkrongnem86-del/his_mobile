// Widget header hiển thị thông tin BN + khoa, dùng chung cho tất cả clinical note screens.
import 'package:flutter/material.dart';

class PatientHeader extends StatelessWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;
  final Color accent;

  const PatientHeader({
    super.key,
    required this.patient,
    required this.department,
    this.accent = const Color(0xFF1565C0),
  });

  String _g(String k1, [String? k2, String? k3]) =>
      (patient[k1] ?? patient[k2 ?? ''] ?? patient[k3 ?? ''] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final name = _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME');
    if (name.isEmpty) return const SizedBox.shrink();
    final code = _g('TDL_PATIENT_CODE', 'tdl_patient_code');
    final reqCode = _g('TDL_TREATMENT_CODE', 'treatment_code');
    final dob = _g('TDL_PATIENT_DOB', 'tdl_patient_dob');
    final sex = _g('TDL_PATIENT_GENDER_NAME', 'tdl_patient_gender');
    final icd = _g('ICD_NAME', 'icd_name', 'ICD_CODE');
    final room = _g('BED_ROOM_NAME', 'room_name');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withOpacity(0.78)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hàng 1: Khoa + giường
          Row(
            children: [
              const Icon(Icons.local_hospital, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${department['icon'] ?? '🏥'}  ${department['name'] ?? ''}  (${department['code'] ?? ''})',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (room.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                  child: Text('🛏 $room', style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Hàng 2: Tên BN
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4, runSpacing: 2,
                      children: [
                        if (code.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
                            child: Text('Mã: $code', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        if (reqCode.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
                            child: Text('ĐT: $reqCode', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        if (dob.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
                            child: Text('NS: ${dob.length > 10 ? dob.substring(0, 10) : dob}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        if (sex.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
                            child: Text('GT: $sex', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                      ],
                    ),
                    if (icd.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'ICD: $icd',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontStyle: FontStyle.italic),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
