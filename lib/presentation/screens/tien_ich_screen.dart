// TienIchScreen v2.38.9 - Tiện ích (sử dụng PatientSearchField dùng chung)
// v2.38.9: Thêm 6 tile danh mục từ Data Public (Thuốc/CLS/Vật tư/Nhân viên/Khoa-Giường/TB + ICD + DVKT)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/data/patient_dataset.dart';
import 'package:his_mobile/presentation/screens/qr_scanner_screen.dart';
import 'package:his_mobile/presentation/screens/bhyt_check_screen.dart';
import 'package:his_mobile/presentation/screens/tra_thuoc_screen.dart';
import 'package:his_mobile/presentation/screens/benh_an_cu_screen.dart';
import 'package:his_mobile/presentation/screens/eric_calculators.dart';
import 'package:his_mobile/presentation/screens/catalog_browser_screen.dart';
import 'package:his_mobile/presentation/screens/phong_tt_kcc_screen.dart';
import 'package:his_mobile/presentation/widgets/local_patient_search_field.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class TienIchScreen extends StatelessWidget {
  const TienIchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
        title: const Text('Tiện ích', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Quét QR BN',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(compact: true),
          // v2.98.6: Dùng LocalPatientSearchField - filter LOCAL (giống DepartmentPatientsScreen)
          // Bỏ dropdown gợi ý → chỉ filter đơn giản
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: LocalPatientSearchField(
              hintText: 'Tìm BN (gõ để lọc, bấm dòng để mở chi tiết)',
              onPatientTap: (p) => _openPatientDetail(context, p),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: const Row(children: [
              Icon(Icons.apps, size: 16, color: Colors.indigo),
              SizedBox(width: 4),
              Text('TIỆN ÍCH THAO TÁC NHANH',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo, letterSpacing: 0.8)),
            ]),
          ),
          Expanded(child: _buildGrid(context)),
        ],
      ),
    );
  }

  void _openPatientDetail(BuildContext context, Map<String, dynamic> p) {
    final username = DataService.instance.user?.userName ?? 'nemk';
    context.push('/patient-detail', extra: {
      'patient': p,
      'department': {
        'name': (p['DEPARTMENT_NAME'] ?? '').toString(),
        'id': p['DEPARTMENT_ID'],
        'code': p['DEPARTMENT_CODE'] ?? '',
      },
      'username': username,
    });
  }

  Widget _buildGrid(BuildContext context) {
    final items = <_TI>[
      _TI('QR BN', Icons.qr_code_scanner, const Color(0xFF00838F), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
      }),
      _TI('Kiểm tra BHYT', Icons.credit_card, const Color(0xFF00838F), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BHYTCheckScreen()));
      }),
      _TI('Tra cứu thuốc', Icons.medication, const Color(0xFF7B1FA2), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TraThuocScreen()));
      }),
      _TI('Bệnh án cũ', Icons.history, const Color(0xFF5D4037), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BenhAnCuScreen()));
      }),
      _TI('GCS', Icons.psychology, const Color(0xFF1976D2), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const GCSCalculator()));
      }),
      _TI('qSOFA', Icons.monitor_heart, const Color(0xFFE65100), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const QSOFACalculator()));
      }),
      _TI('NEWS2', Icons.favorite, const Color(0xFFD32F2F), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const NEWS2Calculator()));
      }),
      _TI('BMI', Icons.monitor_weight, const Color(0xFF388E3C), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BMICalculator()));
      }),
      _TI('CrCl (C-G)', Icons.water_drop, const Color(0xFF0288D1), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CrClCalculator()));
      }),
      _TI('Truyền dịch', Icons.local_drink, const Color(0xFF00ACC1), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const FluidCalculator()));
      }),
      _TI('Bỏng (Parkland)', Icons.local_fire_department, const Color(0xFFE65100), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BurnCalculator()));
      }),
      _TI('Sedation/Anesthesia', Icons.airline_seat_individual_suite, const Color(0xFF7B1FA2), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SedationCalculator()));
      }),
      // v2.38.9: Danh mục từ Data Public (113.163.187.3:8080)
      _TI('DM Thuốc', Icons.medication_liquid, const Color(0xFFAD1457), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.medicine)));
      }),
      _TI('DM CLS', Icons.medical_services, const Color(0xFF00695C), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.cls)));
      }),
      _TI('DM Vật tư', Icons.inventory_2, const Color(0xFFE65100), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.supply)));
      }),
      _TI('DM Nhân viên', Icons.badge, const Color(0xFF1565C0), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.staff)));
      }),
      _TI('DM Khoa-Giường', Icons.hotel, const Color(0xFF2E7D32), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.deptBed)));
      }),
      _TI('DM Thiết bị', Icons.precision_manufacturing, const Color(0xFF6A1B9A), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.equipment)));
      }),
      _TI('ICD-10', Icons.assignment, const Color(0xFF455A64), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.icd)));
      }),
      _TI('DVKT 30 ngày', Icons.medical_information, const Color(0xFFC62828), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.dvkt)));
      }),
      // v3.0.98: Điều trị tăng/hạ Kali máu
      _TI('Tăng K+ máu', Icons.arrow_upward, const Color(0xFFB71C1C), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TangKaiMauScreen()));
      }),
      _TI('Hạ K+ máu', Icons.arrow_downward, const Color(0xFF1565C0), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const HaKaiMauScreen()));
      }),
      // v3.0.100: Phòng TT khoa cấp cứu - danh sách BN + ECG PDF
      _TI('Phòng TT KCC', Icons.medical_services, const Color(0xFFB71C1C), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PhongTTKccScreen()));
      }),
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.95, crossAxisSpacing: 6, mainAxisSpacing: 6),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _buildTile(items[i]),
    );
  }

  Widget _buildTile(_TI item) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedback.lightImpact();
        item.onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: item.color.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: item.color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Icon(item.icon, color: item.color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(item.label, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _TI {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _TI(this.label, this.icon, this.color, this.onTap);
}

// === GCS Calculator (extracted) ===
class GCSCalculator extends StatefulWidget {
  const GCSCalculator({super.key});
  @override
  State<GCSCalculator> createState() => _GCSCalculatorState();
}

class _GCSCalculatorState extends State<GCSCalculator> {
  int eye = 4, verbal = 5, motor = 6;
  int get total => eye + verbal + motor;
  String get severity {
    if (total >= 13) return 'Nhẹ';
    if (total >= 9) return 'Trung bình';
    if (total >= 3) return 'Nặng';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    Widget scale(String label, int v, int max, void Function(int) onChange) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: List.generate(max + 1, (i) => ChoiceChip(
              label: Text('$i'),
              selected: i == v,
              onSelected: (_) => onChange(i),
              selectedColor: Colors.indigo,
              labelStyle: TextStyle(color: i == v ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
            )),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white, title: const Text('Máy tính GCS')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.calculate, color: Colors.indigo, size: 32),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tổng điểm GCS', style: TextStyle(color: Colors.indigo.shade700, fontSize: 12)),
                      Text('$total/15', style: TextStyle(color: Colors.indigo.shade700, fontSize: 32, fontWeight: FontWeight.bold)),
                      Text(severity, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            scale('Mắt (E) - max 4', eye, 4, (v) => setState(() => eye = v)),
            const SizedBox(height: 12),
            scale('Lời nói (V) - max 5', verbal, 5, (v) => setState(() => verbal = v)),
            const SizedBox(height: 12),
            scale('Vận động (M) - max 6', motor, 6, (v) => setState(() => motor = v)),
            const SizedBox(height: 24),
            const Text('Thang đánh giá: 13-15 nhẹ, 9-12 trung bình, 3-8 nặng', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

// === v3.0.98: Điều trị tăng Kali máu (Hyperkalemia) ===
class TangKaiMauScreen extends StatelessWidget {
  const TangKaiMauScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
        title: const Text('Điều trị tăng Kali máu'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: const Color(0xFFFFEBEE),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.warning, color: Color(0xFFB71C1C), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: const Text('Mức K+ máu & biểu hiện',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFB71C1C))),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _kLevel('5.0 - 5.5 mEq/L', 'Nhẹ', Colors.orange),
                  _kLevel('5.5 - 6.5 mEq/L', 'Trung bình - có thể có triệu chứng cơ', Colors.deepOrange),
                  _kLevel('6.5 - 7.0 mEq/L', 'Nặng - EKG thay đổi (sóng T cao nhọn)', Colors.red),
                  _kLevel('> 7.0 mEq/L', 'RẤT NẶNG - nguy cơ rung thất, ngừng tim', const Color(0xFFB71C1C)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _kStep(
            '1️⃣ ỔN ĐỊNH TIM MẠCH (nếu có thay đổi EKG)',
            'Calcium gluconate 10% - 10-20ml (1-2 ống 10ml) pha trong NaCl 0.9%, truyền TM trong 2-5 phút',
            const [
              '⚡ Tác dụng trong 1-3 phút, kéo dài 30-60 phút',
              '⚠️ KHÔNG trộn với bicarbonate (kết tủa CaCO3)',
              '⚠️ Thận trọng nếu đang dùng digoxin (gây ngừng tim)',
              '🔄 Có thể lặp lại sau 5-10 phút nếu EKG không cải thiện',
            ],
            const Color(0xFFB71C1C),
          ),
          const SizedBox(height: 8),
          _kStep(
            '2️⃣ ĐẨY K+ VÀO TRONG TẾ BÀO (30-60 phút)',
            'Insulin Regular + Glucose (truyền TM 30 phút):',
            const [
              '💉 Insulin Regular: 10 UI pha trong 50ml Glucose 50%',
              '🩸 Nếu đường huyết < 250 mg/dL: truyền thêm Glucose 50% 50ml trước/sau',
              '⏱️ Tác dụng trong 10-20 phút, đỉnh 30-60 phút, kéo dài 4-6 giờ',
              '📉 Hạ K+ được 0.6-1.0 mEq/L',
              '🔍 Theo dõi đường huyết mỗi 1 giờ trong 6 giờ đầu (nguy cơ hạ đường huyết)',
            ],
            const Color(0xFFE65100),
          ),
          const SizedBox(height: 8),
          _kStep(
            '3️⃣ TĂNG THẢI K+ RA NGOÀI (kéo dài hơn)',
            'Các biện pháp thải trừ:',
            const [
              '💊 Kayexalate (Polystyrene sulfonate) 15-30g uống + sorbitol 20g',
              '   → Tác dụng 1-2 giờ, có thể dùng qua sonde dạ dày (rectal cũng OK)',
              '   ⚠️ Cẩn thận nguy cơ hoại tử ruột, tránh dùng sau phẫu thuật ruột',
              '💧 Lợi tiểu: Furosemide 40-80mg TM (nếu chức năng thận còn)',
              '🏥 LỌC MÁU cấp cứu nếu: K+ > 6.5 dai dẳng, EKG không cải thiện, suy thận, toan chuyển hóa nặng',
              '🧪 Sodium bicarbonate 50-100 mEq TM (CHỈ khi pH < 7.2, toan chuyển hóa)',
            ],
            const Color(0xFF1565C0),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFFFF3E0),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(children: [
                    Icon(Icons.monitor_heart, color: Color(0xFFE65100)),
                    SizedBox(width: 8),
                    Text('Theo dõi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                  SizedBox(height: 6),
                  Text('• EKG liên tục cho đến khi K+ < 6.0 và ổn định', style: TextStyle(fontSize: 12)),
                  Text('• K+ máu mỗi 1-2 giờ trong 6 giờ đầu, sau đó mỗi 4-6 giờ', style: TextStyle(fontSize: 12)),
                  Text('• Đường huyết mỗi 1 giờ (sau dùng insulin) trong 6 giờ', style: TextStyle(fontSize: 12)),
                  Text('• Ngưng thuốc tăng K+: ACEi, ARB, K-sparing diuretic, NSAIDs, TMP-SMX, heparin', style: TextStyle(fontSize: 12)),
                  Text('• Chế độ ăn GIẢM K+ (tránh chuối, cam, cà chua, khoai, rau lá xanh)', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.grey.shade50,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                '⚠️ Ghi chú: Liều Insulin/Glucose ở trên dành cho người lớn. Trẻ em dùng liều 0.1 UI/kg insulin + 2 ml/kg glucose 25%. Luôn tham khảo BS Nhi khoa.\n\n'
                '📚 Tham khảo: Uptodate 2026, Tintinalli Emergency Medicine 9th ed.',
                style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// === v3.0.98: Helper widgets dùng chung cho 2 screen Kali máu ===
Widget _kLevel(String k, String label, Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          TextSpan(text: label, style: TextStyle(color: color, fontSize: 12)),
        ])),
      ),
    ]),
  );
}

Widget _kStep(String title, String subtitle, List<String> bullets, Color color) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          ...bullets.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Text(b, style: const TextStyle(fontSize: 11, height: 1.4)),
          )),
        ],
      ),
    ),
  );
}

// === v3.0.98: Điều trị hạ Kali máu (Hypokalemia) ===
class HaKaiMauScreen extends StatelessWidget {
  const HaKaiMauScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Điều trị hạ Kali máu'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: const Color(0xFFE3F2FD),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info, color: Color(0xFF1565C0), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: const Text('Mức K+ máu & biểu hiện',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1565C0))),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _kLevel('3.5 - 3.0 mEq/L', 'Nhẹ - thường không triệu chứng', Colors.blue),
                  _kLevel('3.0 - 2.5 mEq/L', 'Trung bình - yếu cơ, mệt mỏi, chuột rút', Colors.indigo),
                  _kLevel('< 2.5 mEq/L', 'Nặng - liệt cơ, loạn nhịp tim, nguy cơ tử vong', Colors.deepPurple),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _kStep(
            '1️⃣ BỔ SUNG ĐƯỜNG UỐNG (ưu tiên)',
            'Dùng cho K+ > 3.0 và không có triệu chứng nặng:',
            const [
              '💊 KCl viên uống: 600-1200 mg/lần × 2-3 lần/ngày (8-12 mEq/liều)',
              '   → Mỗi 600mg KCl = ~8 mEq K+',
              '🍊 Nên uống với nước cam hoặc nước nhiều (tránh kích ứng dạ dày)',
              '🕐 Uống SAU ĂN (giảm nguy cơ viêm loét dạ dày)',
              '📈 Bù 40-60 mEq K+ mỗi 24h để tăng K+ máu ~0.25 mEq/L/ngày',
            ],
            const Color(0xFF1565C0),
          ),
          const SizedBox(height: 8),
          _kStep(
            '2️⃣ TRUYỀN TĨNH MẠCH (khi K+ < 3.0 hoặc có triệu chứng)',
            'KCl truyền TM - CẨN THẬN nguy cơ loạn nhịp:',
            const [
              '💉 Liều khởi đầu: 20-40 mEq KCl trong 1L NaCl 0.9%, truyền 4-6 giờ',
              '   → Tốc độ: KHÔNG quá 10-20 mEq/giờ qua TM ngoại vi',
              '   → TM trung tâm (CVC): max 20-40 mEq/giờ (có monitor tim liên tục)',
              '⚠️ TUYỆT ĐỐI KHÔNG:',
              '   ❌ Tiêm KCl bolus TM (gây ngừng tim tức thì)',
              '   ❌ Pha KCl với Glucose 5% hoặc Ringer Lactat (Ca2+ + K+ gây tủa)',
              '❌ Truyền > 20 mEq/giờ qua TM ngoại vi (gây đau, viêm tĩnh mạch)',
              '🔍 MONITOR: EKG liên tục + K+ máu mỗi 4-6 giờ',
            ],
            const Color(0xFFD32F2F),
          ),
          const SizedBox(height: 8),
          _kStep(
            '3️⃣ MỤC TIÊU BÙ K+',
            'Tính toán nhanh:',
            const [
              '📊 Thiếu hụt K+ (mEq) ≈ 0.4 × cân nặng (kg) × (K+ bình thường - K+ hiện tại)',
              '   → Ví dụ: BN 60kg, K+ = 2.5: thiếu ≈ 0.4 × 60 × (4 - 2.5) = 36 mEq',
              '🎯 Mục tiêu: K+ ≥ 3.5 mEq/L (an toàn cho phẫu thuật, digoxin)',
              '⏱️ Tốc độ bù tối đa 20 mEq/giờ (TM ngoại vi) / 40 mEq/giờ (TM trung tâm)',
              '📈 Mỗi 20 mEq KCl tăng K+ máu ~0.25 mEq/L (trung bình)',
              '⚠️ KHÔNG cố bù nhanh - cơ thể cần 12-24h để cân bằng K+ nội bào',
            ],
            const Color(0xFF388E3C),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFFFF3E0),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(children: [
                    Icon(Icons.search, color: Color(0xFFE65100)),
                    SizedBox(width: 8),
                    Text('Tìm nguyên nhân gốc (quan trọng!)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                  SizedBox(height: 6),
                  Text('• Mất qua thận: lợi tiểu (Furosemide, Thiazide), corticosteroid', style: TextStyle(fontSize: 12)),
                  Text('• Mất qua tiêu hóa: nôn, tiêu chảy, sonde dạ dày, lỗ rò', style: TextStyle(fontSize: 12)),
                  Text('• Vào nội bào: insulin, beta-agonist (salbutamol), toan kiềm', style: TextStyle(fontSize: 12)),
                  Text('• Ăn uống kém: nghiện rượu, ăn chay, suy dinh dưỡng', style: TextStyle(fontSize: 12)),
                  Text('• Bệnh lý: cường Aldosteron, h/c Cushing, Bartter, Gitelman', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.grey.shade50,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                '⚠️ Ghi chú: KHÔNG dùng Salbutamol trong cơn hen cấp nếu K+ < 3.0 (làm hạ K+ thêm, nguy cơ loạn nhịp). Bù K+ trước khi dùng Insulin cho bệnh nhân ĐTĐ có K+ thấp.\n\n'
                '📚 Tham khảo: Uptodate 2026, Harrison 21st ed.',
                style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}