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
    final username = DataService.instance.user?.userName ?? 'admin';
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