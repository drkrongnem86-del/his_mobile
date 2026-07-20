// =============================================================================
// PatientCard — card hiển thị 1 bệnh nhân (đầy đủ info theo spec BS)
// v2.90.0: Restore full layout (Checkbox + 14pt 2 dòng) + thêm "tuổi (age)"
// v2.88.0: Từng refactor gọn (avatar + 16pt) nhưng BS thích layout đầy đủ
// v2.76.2: TDL_PATIENT_UNSIGNED_NAME đầu tiên (không dấu, app Y tế số)
// v2.73.0: Compact — tên 14pt để thấy nhiều BN
// v2.64.0: 1 tap = mở thao tác (giống app Y tế số)
// - Tap 1 lần vào tên/card: mở PatientActionsSheet (thao tác BN)
// - Tick checkbox: chọn nhiều BN (multi-select)
// - Tap icon ✚: cũng mở thao tác
// =============================================================================

import 'package:flutter/material.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';

class PatientCard extends StatefulWidget {
  final Map<String, dynamic> patient;
  final VoidCallback onActions;
  final bool isSelected;
  final ValueChanged<bool>? onSelectedChanged;

  const PatientCard({
    super.key,
    required this.patient,
    required this.onActions,
    this.isSelected = false,
    this.onSelectedChanged,
  });

  @override
  State<PatientCard> createState() => _PatientCardState();
}

class _PatientCardState extends State<PatientCard> {
  /// Helper: lấy field từ nhiều key khác nhau (Dashboard + HIS Pro)
  /// v3.0.57: Hỗ trợ tối đa 6 keys (tăng từ 3) để cover thêm field HIS Pro
  String _get(String key1, [String? key2, String? key3, String? key4, String? key5, String? key6]) {
    final p = widget.patient;
    return (p[key1] ?? p[key2 ?? ''] ?? p[key3 ?? ''] ?? p[key4 ?? ''] ?? p[key5 ?? ''] ?? p[key6 ?? ''] ?? '').toString();
  }

  /// v3.0.57: Helper lấy chẩn đoán ICD từ nhiều field của HIS Pro
  /// - Trước đó chỉ check icd_name/ICD_NAME/ICD_BENH_NHAN_FULL → nhiều ca hiển thị "đang tải"
  /// - Thêm ICD_TEXT, LAST_ICD_NAME, SUBCLINICAL_ICD_NAME, HEIN_ICD_NAME (HIS Pro có nhiều field)
  /// - Trả về chuỗi đầu tiên không rỗng
  String _getIcdName() {
    // _get chỉ support tối đa 6 keys, cần chain 2 lần
    final first = _get('icd_name', 'ICD_NAME', 'ICD_BENH_NHAN_FULL', 'icd_text', 'ICD_TEXT', 'LAST_ICD_NAME');
    if (first.isNotEmpty) return first;
    return _get('SUBCLINICAL_ICD_NAME', 'HEIN_ICD_NAME');
  }

  String _getIcdCode() {
    final first = _get('icd_code', 'ICD_CODE', 'MA_ICD', 'LAST_ICD_CODE', 'icd_sub_codes');
    return first;
  }

  /// v2.90.0: Tính tuổi từ DOB
  /// Hỗ trợ format: "yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "dd/MM/yyyy"
  /// Return: số tuổi (int) hoặc null nếu không parse được
  int? _calcAge(String dob) {
    if (dob.isEmpty || dob == '-' || dob == 'null') return null;
    try {
      DateTime? birth;
      if (dob.contains('/')) {
        // dd/MM/yyyy
        final parts = dob.split('/');
        if (parts.length >= 3) {
          birth = DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      } else if (dob.contains('-')) {
        // yyyy-MM-dd hoặc yyyy-MM-dd HH:mm:ss
        final datePart = dob.split(' ')[0];
        birth = DateTime.tryParse(datePart);
      } else {
        // Thử format yyyyMMdd
        if (dob.length == 8) {
          birth = DateTime(
            int.parse(dob.substring(0, 4)),
            int.parse(dob.substring(4, 6)),
            int.parse(dob.substring(6, 8)),
          );
        }
      }
      if (birth == null) return null;
      final now = DateTime.now();
      var age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      if (age < 0 || age > 150) return null;
      return age;
    } catch (_) {
      return null;
    }
  }

  /// v2.47.0: Nếu ICD rỗng + có HIS Pro token → auto-load ICD từ HIS Pro
  /// (gọi api/HisTreatment/GetView4 port 1408 - đã verify work)
  /// setState sẽ rebuild card với ICD mới
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadIcd());
  }

  @override
  void didUpdateWidget(covariant PatientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patient != widget.patient) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadIcd());
    }
  }

  void _maybeLoadIcd() async {
    if (!mounted) return;
    final p = widget.patient;
    final code = _get('treatment_code', 'TDL_TREATMENT_CODE', 'MA_DIEU_TRI');
    if (code.isEmpty) return;
    // v3.0.57: Check thêm nhiều field ICD fallback
    final hasIcd = _getIcdName().isNotEmpty || _getIcdCode().isNotEmpty;
    if (hasIcd) return; // đã có ICD
    final thongke = ThongkeAuthService.instance;
    if (!thongke.hasHisProToken) return;
    final icd = await thongke.fetchHisProIcd(code);
    if (!mounted || icd == null) return;
    setState(() {
      p['icd_code'] = icd['icd_code'];
      p['icd_name'] = icd['icd_name'];
      p['icd_text'] = icd['icd_text'];
      p['icd_sub_codes'] = icd['icd_sub_codes'];
      p['DEPARTMENT_NAME'] = p['DEPARTMENT_NAME'] ?? icd['department_name'] ?? '';
      p['TDL_PATIENT_GENDER_NAME'] = p['TDL_PATIENT_GENDER_NAME'] ?? icd['patient_gender'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    // Hỗ trợ cả lowercase (API Data/Thongke) và UPPERCASE (HIS Pro/PatientSeed) keys
    // v2.76.3: Dùng PatientNameHelper - ưu tiên field theo config (NameField)
    final name = capitalizeVietnameseName(PatientNameHelper.getName(p));
    final code = _get('tdl_patient_code', 'TDL_PATIENT_CODE', 'MA_BENH_NHAN');
    final reqCode = _get('treatment_code', 'TDL_TREATMENT_CODE', 'MA_DIEU_TRI');
    final heinCard = _get('tdl_hein_card_number', 'TDL_HEIN_CARD_NUMBER', 'SO_BHYT');
    final reqStt = _get('service_req_stt_name', 'SERVICE_REQ_STT_NAME', 'TEN_TRANG_THAI');
    final reqSttId = p['service_req_stt_id'] ?? p['SERVICE_REQ_STT_ID'] ?? p['TRANG_THAI_YL_ID'];
    final reqTypeName = _get('service_req_type_name', 'SERVICE_REQ_TYPE_NAME', 'LOAI_YL');
    // v3.0.57: Mở rộng fallback cho ICD fields
    final icdName = _getIcdName();
    final icdCode = _getIcdCode();
    final gender = _get('tdl_patient_gender_name', 'TDL_PATIENT_GENDER_NAME', 'GIOI_TINH');
    final dob = _get('tdl_patient_dob', 'TDL_PATIENT_DOB', 'NGAY_SINH');
    final age = _calcAge(dob);
    final room = _get('execute_room_name', 'EXECUTE_ROOM_NAME', 'PHONG');
    final bed = _get('bed_name', 'BED_NAME', 'GIUONG');
    final priority = _get('priority_name', 'PRIORITY_NAME', 'DO_UU_TIEN');
    final dept = _get('department_name', 'DEPARTMENT_NAME', 'KHOA_DIEU_TRI');

    return GestureDetector(
      onDoubleTap: widget.onActions,  // v2.64.0: keep double-tap as backup
      child: Card(
        color: widget.isSelected ? const Color(0xFFFFF8E1) : Colors.white,
        margin: const EdgeInsets.only(bottom: 8),
        elevation: widget.isSelected ? 3 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: widget.isSelected ? Colors.amber.shade700 : Colors.grey.shade300,
            width: widget.isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          // v2.64.0: 1 tap = mở thao tác (giống app Y tế số)
          onTap: widget.onActions,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // v2.93.0: Hàng 1 = Tên BN (Stack với checkbox overlay góc trên trái) + Nút thao tác
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tên BN + các thông tin chính (Stack để overlay checkbox ở góc trên trái)
                    Expanded(
                      child: Stack(
                        children: [
                          // Layer 1: Padding trái để tránh checkbox che tên
                          Padding(
                            padding: const EdgeInsets.only(left: 30, top: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Tên BN - 14pt, 2 dòng
                                Text(
                                  name.isNotEmpty ? name : 'BN',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                // Badge trạng thái + verify marker
                                Row(
                                  children: [
                                    _admissionStatusBadge(p),
                                    const SizedBox(width: 4),
                                    _verifyBadge(reqCode),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Mã BN • Giới tính • Ngày sinh
                                Text(
                                  [
                                    if (code.isNotEmpty) 'Mã BN: $code',
                                    if (gender.isNotEmpty) gender,
                                    if (dob.isNotEmpty) dob.length > 10 ? dob.substring(0, 10) : dob,
                                  ].join(' • '),
                                  style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                // Mã điều trị + loại y lệnh
                                if (reqCode.isNotEmpty || reqTypeName.isNotEmpty)
                                  Text(
                                    [
                                      if (reqCode.isNotEmpty) '📋 ĐT: $reqCode',
                                      if (reqTypeName.isNotEmpty) reqTypeName,
                                    ].join(' • '),
                                    style: const TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                              ],
                            ),
                          ),
                          // Layer 2: Checkbox overlay ở góc trên trái
                          Positioned(
                            left: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () {
                                if (widget.onSelectedChanged != null) {
                                  widget.onSelectedChanged!(!widget.isSelected);
                                }
                              },
                              child: Container(
                                width: 24, height: 24,
                                decoration: BoxDecoration(
                                  color: widget.isSelected ? Colors.amber.shade700 : Colors.white,
                                  border: Border.all(
                                    color: widget.isSelected ? Colors.amber.shade700 : Colors.grey.shade400,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: widget.isSelected ? [
                                    BoxShadow(color: Colors.amber.shade200, blurRadius: 4, spreadRadius: 1),
                                  ] : null,
                                ),
                                child: widget.isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Nút thao tác
                    IconButton(
                      icon: const Icon(Icons.medical_services, color: Colors.indigo, size: 22),
                      tooltip: 'Thao tác',
                      onPressed: widget.onActions,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Chẩn đoán - luôn hiển thị (có/không có ICD)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (icdCode.isNotEmpty || icdName.isNotEmpty)
                        ? const Color(0xFFFFF3E0)
                        : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (icdCode.isNotEmpty || icdName.isNotEmpty)
                            ? Icons.healing
                            : Icons.medical_information,
                        size: 12,
                        color: (icdCode.isNotEmpty || icdName.isNotEmpty)
                            ? Colors.orange.shade700
                            : Colors.blue.shade700,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          (icdCode.isNotEmpty || icdName.isNotEmpty)
                              ? (icdCode.isNotEmpty && icdName.isNotEmpty
                                  ? '🔍 $icdCode - $icdName'
                                  : icdName.isNotEmpty ? icdName : icdCode)
                              : '⏳ Chẩn đoán đang tải... (mở HIS Pro BV để có mặt bệnh)',
                          style: TextStyle(
                            color: (icdCode.isNotEmpty || icdName.isNotEmpty)
                                ? Colors.black87
                                : Colors.blue.shade700,
                            fontSize: 11,
                            fontStyle: (icdCode.isNotEmpty || icdName.isNotEmpty)
                                ? FontStyle.italic
                                : FontStyle.normal,
                            fontWeight: (icdCode.isNotEmpty || icdName.isNotEmpty)
                                ? FontWeight.normal
                                : FontWeight.w500,
                          ),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // Khoa + BHYT + Phòng + Ưu tiên + Tuổi (age) [v2.90.0: thêm tuổi]
                Wrap(
                  spacing: 6, runSpacing: 4,
                  children: [
                    if (dept.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.indigo.shade200, width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_hospital, size: 11, color: Colors.indigo),
                            const SizedBox(width: 3),
                            Text(dept,
                                style: const TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    if (heinCard.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.credit_card, size: 11, color: Colors.black54),
                          const SizedBox(width: 3),
                          Text(heinCard,
                              style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    if (room.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bed, size: 11, color: Colors.black54),
                          const SizedBox(width: 3),
                          Text(room,
                              style: const TextStyle(color: Colors.black87, fontSize: 11)),
                        ],
                      ),
                    // v2.90.0: Tuổi (age) - tính từ DOB
                    if (age != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cake, size: 11, color: Colors.deepOrange),
                          const SizedBox(width: 3),
                          Text('${age}T',
                              style: const TextStyle(color: Colors.deepOrange, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                  ],
                ),

                if (priority.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.flag, size: 11, color: Colors.red),
                      const SizedBox(width: 3),
                      Text('Ưu tiên: $priority',
                          style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],

                // v2.64.0: Hint - 1 tap để mở thao tác
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, size: 10, color: Colors.indigo),
                      SizedBox(width: 3),
                      Text('Bấm 1 lần → Thao tác • Tick để chọn nhiều',
                          style: TextStyle(color: Colors.indigo, fontSize: 9, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(dynamic sttId) {
    if (sttId == null) return Colors.grey;
    switch (sttId.toString()) {
      case '1': return Colors.blue;
      case '2': return Colors.orange;
      case '3': return Colors.green;
      case '4': return Colors.red;
      default: return Colors.grey;
    }
  }

  /// Trạng thái điều trị theo gợi ý BS Nểm (clone Y Tế Số / HIS Pro):
  /// - Trắng ("Mới")      = BN chưa khám
  /// - Cam  ("Đang ĐT")  = BN đang được điều trị (out_time trống HOẶC trong hôm nay / hôm qua)
  /// - Đen  ("Ra viện")  = BN đã ra viện / chuyển khoa (out_time > 24h trước)
  ///
  /// Logic: HIS Pro ghi `out_time` ngay khi khoá viện phí, không phải lúc ra viện thật.
  /// BS cho biết nhiều ca HSTC đã ghi out_time nhưng BS vẫn đang điều trị → giữ cam
  /// nếu out_time trong vòng 24h. Sau 24h thì chắc chắn BN đã ra.
  Widget _admissionStatusBadge(Map<String, dynamic> p) {
    final isPause = (p['is_pause']?.toString() ?? '').trim();
    final outTime = (p['out_time']?.toString() ?? '').trim();
    final sttId = p['service_req_stt_id'] ?? p['SERVICE_REQ_STT_ID'];

    // Parse out_time "dd/MM/yyyy HH:mm" hoặc "yyyy-MM-dd HH:mm:ss"
    DateTime? outDt;
    if (outTime.isNotEmpty && outTime != '-' && outTime != 'null') {
      try {
        if (outTime.contains('/')) {
          // dd/MM/yyyy HH:mm (HIS VN format)
          final parts = outTime.split(' ');
          final date = parts[0].split('/');
          final time = parts.length > 1 ? parts[1].split(':') : ['0','0'];
          outDt = DateTime(
            int.parse(date[2]),
            int.parse(date[1]),
            int.parse(date[0]),
            int.parse(time[0]),
            int.parse(time[1]),
          );
        } else {
          outDt = DateTime.tryParse(outTime);
        }
      } catch (_) {
        outDt = null;
      }
    }

    final hasOutTime = outDt != null;
    final now = DateTime.now();
    final recentlyDischarged = hasOutTime
        ? now.difference(outDt!) < const Duration(hours: 24)
        : false;
    final isFinished = isPause == '1' && hasOutTime && !recentlyDischarged;

    Color bg, fg;
    String label;
    IconData icon;
    if (isFinished) {
      // Đen: BN đã ra viện / chuyển khoa / kết thúc hoàn toàn
      bg = const Color(0xFF263238); fg = const Color(0xFFECEFF1);
      label = 'Đã ra viện';
      icon = Icons.check_circle;
    } else if (!hasOutTime || sttId == null) {
      // Trắng: BN mới vào, chưa có y lệnh khám
      bg = const Color(0xFFFAFAFA); fg = const Color(0xFF455A64);
      label = 'Mới nhập viện';
      icon = Icons.fiber_new;
    } else {
      // Cam: Đang điều trị — out_time trống HOẶC trong 24h HOẶC is_pause=0
      bg = const Color(0xFFFFE0B2); fg = const Color(0xFFE65100);
      label = recentlyDischarged ? 'Vừa hoàn tất' : 'Đang điều trị';
      icon = Icons.healing;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: fg),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// Verify badge — xanh = dữ liệu thật, vàng = mẫu
  Widget _verifyBadge(String reqCode) {
    final isReal = reqCode.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isReal ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isReal ? Colors.green.shade700 : Colors.amber.shade700,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReal ? Icons.cloud_done : Icons.bookmark,
            size: 9,
            color: isReal ? Colors.green.shade700 : Colors.amber.shade700,
          ),
          const SizedBox(width: 2),
          Text(
            isReal ? 'Thật' : 'Mẫu',
            style: TextStyle(
              color: isReal ? Colors.green.shade700 : Colors.amber.shade700,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
