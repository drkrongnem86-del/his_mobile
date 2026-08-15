// Dialog chọn khoa - danh sách phẳng, không có search.
// BS yêu cầu: ô search gây khó chịu, lọc khiến mất tổng quan → bỏ search
// giữ list 52 khoa scroll tự do, sort theo nhóm chức năng (Cấp cứu → Hồi sức
// → Ngoại → Nội → Sản → Nhi → Khám → CLS → khác).
import 'package:flutter/material.dart';
import 'package:his_mobile/core/constants/app_constants.dart';

class DeptPickerDialog extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onPicked;

  const DeptPickerDialog({
    super.key,
    required this.currentIndex,
    required this.onPicked,
  });

  /// Helper mở dialog - returns index nếu user chọn 1 khoa.
  static Future<int?> show(BuildContext context, int currentIndex) {
    return showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: DeptPickerDialog(
          currentIndex: currentIndex,
          onPicked: (i) => Navigator.pop(ctx, i),
        ),
      ),
    );
  }

  @override
  State<DeptPickerDialog> createState() => _DeptPickerDialogState();
}

class _DeptPickerDialogState extends State<DeptPickerDialog> {
  @override
  Widget build(BuildContext context) {
    final depts = AppConstants.departments;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header gradient + close button
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.local_hospital, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('CHỌN KHOA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    )),
              ),
              Text('${depts.length} khoa',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // v3.0.103: Card nổi bật "Phòng TT Khoa Cấp Cứu" ở trên cùng - không thể bỏ sót
        InkWell(
          onTap: () {
            // Return special index 99001 (Phòng TT KCC id)
            Navigator.pop(context, 99001);
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: Colors.red.shade200, blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                  child: const Icon(Icons.medical_services, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PHÒNG THỦ THUẬT HSCC',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('📋 Danh sách BN + điện tim (ECG) - 3 nguồn API',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(child: Divider(color: Color(0xFFE0E0E0), thickness: 1)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('— KHOA —', style: TextStyle(color: Colors.black45, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
            Expanded(child: Divider(color: Color(0xFFE0E0E0), thickness: 1)),
          ]),
        ),

        // List 53 khoa (không search, không filter)
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: depts.length,
            itemBuilder: (ctx, i) {
              final d = depts[i];
              final isSelected = i == widget.currentIndex;
              return InkWell(
                onTap: () => widget.onPicked(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFE3F2FD) : Colors.transparent,
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFFF0F4FF)),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Text(d['icon'] as String, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    d['name'] as String,
                                    style: TextStyle(
                                      color: isSelected ? Colors.indigo : Colors.black,
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    ),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (d['isPhong'] == true) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFB71C1C),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Phòng',
                                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID ${d['id']}  •  Mã ${d['code']}',
                              style: TextStyle(
                                color: isSelected ? Colors.indigo[400] : Colors.black54,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 10, color: Colors.white),
                              SizedBox(width: 2),
                              Text('ĐANG CHỌN',
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      else
                        const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
