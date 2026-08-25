// TienIchScreen v3.0.164 - Tiá»‡n Ã­ch (sá»­ dá»¥ng PatientSearchField dÃ¹ng chung)
// v3.0.164: Gá»˜P 2 tile phÃ²ng thÃ nh 1 - "PhÃ²ng tá»§ thuáº­t HSCC (ECG + DSBN)" - room 36
//          BS yÃªu cáº§u: Bá»Ž "PhÃ²ng thá»­ thuáº­t HSCC ID 9999" - chá»‰ giá»¯ 1 tile thá»‘ng nháº¥t
//          PhÃ²ng 36 chá»©a ECG + BN chá» thá»§ thuáº­t nhá» + DSBN Ä‘ang chá»
// v2.38.9: ThÃªm 6 tile danh má»¥c tá»« Data Public (Thuá»‘c/CLS/Váº­t tÆ°/NhÃ¢n viÃªn/Khoa-GiÆ°á»ng/TB + ICD + DVKT)
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
import 'package:his_mobile/presentation/screens/procedure_room_screen.dart';
import 'package:his_mobile/core/security/credentials.dart';
import 'package:his_mobile/core/constants/app_constants.dart';  // v3.0.162

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
        title: const Text('Tiá»‡n Ã­ch', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'QuÃ©t QR BN',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(compact: true),
          // v2.98.6: DÃ¹ng LocalPatientSearchField - filter LOCAL (giá»‘ng DepartmentPatientsScreen)
          // Bá» dropdown gá»£i Ã½ â†’ chá»‰ filter Ä‘Æ¡n giáº£n
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: LocalPatientSearchField(
              hintText: 'TÃ¬m BN (gÃµ Ä‘á»ƒ lá»c, báº¥m dÃ²ng Ä‘á»ƒ má»Ÿ chi tiáº¿t)',
              onPatientTap: (p) => _openPatientDetail(context, p),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: const Row(children: [
              Icon(Icons.apps, size: 16, color: Colors.indigo),
              SizedBox(width: 4),
              Text('TIá»†N ÃCH THAO TÃC NHANH',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo, letterSpacing: 0.8)),
            ]),
          ),
          Expanded(child: _buildGrid(context)),
        ],
      ),
    );
  }

  void _openPatientDetail(BuildContext context, Map<String, dynamic> p) {
    final username = DataService.instance.user?.userName ?? Credentials.defaultNemkLogin;
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
      // v3.0.164: Gá»˜P 2 phÃ²ng thÃ nh 1 - "PhÃ²ng tá»§ thuáº­t HSCC (ECG + DSBN)" - dÃ¹ng room 36
      // BS yÃªu cáº§u: Bá»Ž "PhÃ²ng thá»­ thuáº­t HSCC ID 9999", chá»‰ giá»¯ 1 tile thá»‘ng nháº¥t
      // - PhÃ²ng 36 (PhÃ²ng khÃ¡m cáº¥p cá»©u / Tá»§ thuáº­t nhá») chá»©a ECG + BN chá» thá»§ thuáº­t nhá»
      // - Hiá»ƒn thá»‹: DS BN Ä‘ang chá» (1 BN cÃ³ thá»ƒ cÃ³ ECG + KhÃ¡m + Thá»§ thuáº­t) + ECG screen
      // - Token sync vá»›i procedure room screen (paste 1 nÆ¡i â†’ all dÃ¹ng token Ä‘Ã³)
      _TI('PhÃ²ng tá»§ thuáº­t HSCC\n(ECG + DSBN)', Icons.medical_services, const Color(0xFFD32F2F), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProcedureRoomScreen(
          executeRoomId: AppConstants.ROOM_ID_TU_THUAT_HSCC,
        )));
      }),
      _TI('QR BN', Icons.qr_code_scanner, const Color(0xFF00838F), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
      }),
      _TI('Kiá»ƒm tra BHYT', Icons.credit_card, const Color(0xFF00838F), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BHYTCheckScreen()));
      }),
      _TI('Tra cá»©u thuá»‘c', Icons.medication, const Color(0xFF7B1FA2), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TraThuocScreen()));
      }),
      _TI('Bá»‡nh Ã¡n cÅ©', Icons.history, const Color(0xFF5D4037), () {
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
      _TI('Truyá»n dá»‹ch', Icons.local_drink, const Color(0xFF00ACC1), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const FluidCalculator()));
      }),
      _TI('Bá»ng (Parkland)', Icons.local_fire_department, const Color(0xFFE65100), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BurnCalculator()));
      }),
      _TI('Sedation/Anesthesia', Icons.airline_seat_individual_suite, const Color(0xFF7B1FA2), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SedationCalculator()));
      }),
      // v2.38.9: Danh má»¥c tá»« Data Public (113.163.187.3:8080)
      _TI('DM Thuá»‘c', Icons.medication_liquid, const Color(0xFFAD1457), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.medicine)));
      }),
      _TI('DM CLS', Icons.medical_services, const Color(0xFF00695C), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.cls)));
      }),
      _TI('DM Váº­t tÆ°', Icons.inventory_2, const Color(0xFFE65100), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.supply)));
      }),
      _TI('DM NhÃ¢n viÃªn', Icons.badge, const Color(0xFF1565C0), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.staff)));
      }),
      _TI('DM Khoa-GiÆ°á»ng', Icons.hotel, const Color(0xFF2E7D32), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.deptBed)));
      }),
      _TI('DM Thiáº¿t bá»‹', Icons.precision_manufacturing, const Color(0xFF6A1B9A), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.equipment)));
      }),
      _TI('ICD-10', Icons.assignment, const Color(0xFF455A64), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.icd)));
      }),
      _TI('DVKT 30 ngÃ y', Icons.medical_information, const Color(0xFFC62828), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogBrowserScreen(type: CatalogType.dvkt)));
      }),
      // v3.0.98: Äiá»u trá»‹ tÄƒng/háº¡ Kali mÃ¡u
      _TI('TÄƒng K+ mÃ¡u', Icons.arrow_upward, const Color(0xFFB71C1C), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TangKaiMauScreen()));
      }),
      _TI('Háº¡ K+ mÃ¡u', Icons.arrow_downward, const Color(0xFF1565C0), () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const HaKaiMauScreen()));
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
    if (total >= 13) return 'Nháº¹';
    if (total >= 9) return 'Trung bÃ¬nh';
    if (total >= 3) return 'Náº·ng';
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
      appBar: AppBar(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white, title: const Text('MÃ¡y tÃ­nh GCS')),
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
                      Text('Tá»•ng Ä‘iá»ƒm GCS', style: TextStyle(color: Colors.indigo.shade700, fontSize: 12)),
                      Text('$total/15', style: TextStyle(color: Colors.indigo.shade700, fontSize: 32, fontWeight: FontWeight.bold)),
                      Text(severity, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            scale('Máº¯t (E) - max 4', eye, 4, (v) => setState(() => eye = v)),
            const SizedBox(height: 12),
            scale('Lá»i nÃ³i (V) - max 5', verbal, 5, (v) => setState(() => verbal = v)),
            const SizedBox(height: 12),
            scale('Váº­n Ä‘á»™ng (M) - max 6', motor, 6, (v) => setState(() => motor = v)),
            const SizedBox(height: 24),
            const Text('Thang Ä‘Ã¡nh giÃ¡: 13-15 nháº¹, 9-12 trung bÃ¬nh, 3-8 náº·ng', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

// === v3.0.98: Äiá»u trá»‹ tÄƒng Kali mÃ¡u (Hyperkalemia) ===
class TangKaiMauScreen extends StatelessWidget {
  const TangKaiMauScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
        title: const Text('Äiá»u trá»‹ tÄƒng Kali mÃ¡u'),
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
                      child: const Text('Má»©c K+ mÃ¡u & biá»ƒu hiá»‡n',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFB71C1C))),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _kLevel('5.0 - 5.5 mEq/L', 'Nháº¹', Colors.orange),
                  _kLevel('5.5 - 6.5 mEq/L', 'Trung bÃ¬nh - cÃ³ thá»ƒ cÃ³ triá»‡u chá»©ng cÆ¡', Colors.deepOrange),
                  _kLevel('6.5 - 7.0 mEq/L', 'Náº·ng - EKG thay Ä‘á»•i (sÃ³ng T cao nhá»n)', Colors.red),
                  _kLevel('> 7.0 mEq/L', 'Ráº¤T Náº¶NG - nguy cÆ¡ rung tháº¥t, ngá»«ng tim', const Color(0xFFB71C1C)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _kStep(
            '1ï¸âƒ£ á»”N Äá»ŠNH TIM Máº CH (náº¿u cÃ³ thay Ä‘á»•i EKG)',
            'Calcium gluconate 10% - 10-20ml (1-2 á»‘ng 10ml) pha trong NaCl 0.9%, truyá»n TM trong 2-5 phÃºt',
            const [
              'âš¡ TÃ¡c dá»¥ng trong 1-3 phÃºt, kÃ©o dÃ i 30-60 phÃºt',
              'âš ï¸ KHÃ”NG trá»™n vá»›i bicarbonate (káº¿t tá»§a CaCO3)',
              'âš ï¸ Tháº­n trá»ng náº¿u Ä‘ang dÃ¹ng digoxin (gÃ¢y ngá»«ng tim)',
              'ðŸ”„ CÃ³ thá»ƒ láº·p láº¡i sau 5-10 phÃºt náº¿u EKG khÃ´ng cáº£i thiá»‡n',
            ],
            const Color(0xFFB71C1C),
          ),
          const SizedBox(height: 8),
          _kStep(
            '2ï¸âƒ£ Äáº¨Y K+ VÃ€O TRONG Táº¾ BÃ€O (30-60 phÃºt)',
            'Insulin Regular + Glucose (truyá»n TM 30 phÃºt):',
            const [
              'ðŸ’‰ Insulin Regular: 10 UI pha trong 50ml Glucose 50%',
              'ðŸ©¸ Náº¿u Ä‘Æ°á»ng huyáº¿t < 250 mg/dL: truyá»n thÃªm Glucose 50% 50ml trÆ°á»›c/sau',
              'â±ï¸ TÃ¡c dá»¥ng trong 10-20 phÃºt, Ä‘á»‰nh 30-60 phÃºt, kÃ©o dÃ i 4-6 giá»',
              'ðŸ“‰ Háº¡ K+ Ä‘Æ°á»£c 0.6-1.0 mEq/L',
              'ðŸ” Theo dÃµi Ä‘Æ°á»ng huyáº¿t má»—i 1 giá» trong 6 giá» Ä‘áº§u (nguy cÆ¡ háº¡ Ä‘Æ°á»ng huyáº¿t)',
            ],
            const Color(0xFFE65100),
          ),
          const SizedBox(height: 8),
          _kStep(
            '3ï¸âƒ£ TÄ‚NG THáº¢I K+ RA NGOÃ€I (kÃ©o dÃ i hÆ¡n)',
            'CÃ¡c biá»‡n phÃ¡p tháº£i trá»«:',
            const [
              'ðŸ’Š Kayexalate (Polystyrene sulfonate) 15-30g uá»‘ng + sorbitol 20g',
              '   â†’ TÃ¡c dá»¥ng 1-2 giá», cÃ³ thá»ƒ dÃ¹ng qua sonde dáº¡ dÃ y (rectal cÅ©ng OK)',
              '   âš ï¸ Cáº©n tháº­n nguy cÆ¡ hoáº¡i tá»­ ruá»™t, trÃ¡nh dÃ¹ng sau pháº«u thuáº­t ruá»™t',
              'ðŸ’§ Lá»£i tiá»ƒu: Furosemide 40-80mg TM (náº¿u chá»©c nÄƒng tháº­n cÃ²n)',
              'ðŸ¥ Lá»ŒC MÃU cáº¥p cá»©u náº¿u: K+ > 6.5 dai dáº³ng, EKG khÃ´ng cáº£i thiá»‡n, suy tháº­n, toan chuyá»ƒn hÃ³a náº·ng',
              'ðŸ§ª Sodium bicarbonate 50-100 mEq TM (CHá»ˆ khi pH < 7.2, toan chuyá»ƒn hÃ³a)',
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
                    Text('Theo dÃµi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                  SizedBox(height: 6),
                  Text('â€¢ EKG liÃªn tá»¥c cho Ä‘áº¿n khi K+ < 6.0 vÃ  á»•n Ä‘á»‹nh', style: TextStyle(fontSize: 12)),
                  Text('â€¢ K+ mÃ¡u má»—i 1-2 giá» trong 6 giá» Ä‘áº§u, sau Ä‘Ã³ má»—i 4-6 giá»', style: TextStyle(fontSize: 12)),
                  Text('â€¢ ÄÆ°á»ng huyáº¿t má»—i 1 giá» (sau dÃ¹ng insulin) trong 6 giá»', style: TextStyle(fontSize: 12)),
                  Text('â€¢ NgÆ°ng thuá»‘c tÄƒng K+: ACEi, ARB, K-sparing diuretic, NSAIDs, TMP-SMX, heparin', style: TextStyle(fontSize: 12)),
                  Text('â€¢ Cháº¿ Ä‘á»™ Äƒn GIáº¢M K+ (trÃ¡nh chuá»‘i, cam, cÃ  chua, khoai, rau lÃ¡ xanh)', style: TextStyle(fontSize: 12)),
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
                'âš ï¸ Ghi chÃº: Liá»u Insulin/Glucose á»Ÿ trÃªn dÃ nh cho ngÆ°á»i lá»›n. Tráº» em dÃ¹ng liá»u 0.1 UI/kg insulin + 2 ml/kg glucose 25%. LuÃ´n tham kháº£o BS Nhi khoa.\n\n'
                'ðŸ“š Tham kháº£o: Uptodate 2026, Tintinalli Emergency Medicine 9th ed.',
                style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// === v3.0.98: Helper widgets dÃ¹ng chung cho 2 screen Kali mÃ¡u ===
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

// === v3.0.98: Äiá»u trá»‹ háº¡ Kali mÃ¡u (Hypokalemia) ===
class HaKaiMauScreen extends StatelessWidget {
  const HaKaiMauScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Äiá»u trá»‹ háº¡ Kali mÃ¡u'),
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
                      child: const Text('Má»©c K+ mÃ¡u & biá»ƒu hiá»‡n',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1565C0))),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _kLevel('3.5 - 3.0 mEq/L', 'Nháº¹ - thÆ°á»ng khÃ´ng triá»‡u chá»©ng', Colors.blue),
                  _kLevel('3.0 - 2.5 mEq/L', 'Trung bÃ¬nh - yáº¿u cÆ¡, má»‡t má»i, chuá»™t rÃºt', Colors.indigo),
                  _kLevel('< 2.5 mEq/L', 'Náº·ng - liá»‡t cÆ¡, loáº¡n nhá»‹p tim, nguy cÆ¡ tá»­ vong', Colors.deepPurple),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _kStep(
            '1ï¸âƒ£ Bá»” SUNG ÄÆ¯á»œNG Uá»NG (Æ°u tiÃªn)',
            'DÃ¹ng cho K+ > 3.0 vÃ  khÃ´ng cÃ³ triá»‡u chá»©ng náº·ng:',
            const [
              'ðŸ’Š KCl viÃªn uá»‘ng: 600-1200 mg/láº§n Ã— 2-3 láº§n/ngÃ y (8-12 mEq/liá»u)',
              '   â†’ Má»—i 600mg KCl = ~8 mEq K+',
              'ðŸŠ NÃªn uá»‘ng vá»›i nÆ°á»›c cam hoáº·c nÆ°á»›c nhiá»u (trÃ¡nh kÃ­ch á»©ng dáº¡ dÃ y)',
              'ðŸ• Uá»‘ng SAU Ä‚N (giáº£m nguy cÆ¡ viÃªm loÃ©t dáº¡ dÃ y)',
              'ðŸ“ˆ BÃ¹ 40-60 mEq K+ má»—i 24h Ä‘á»ƒ tÄƒng K+ mÃ¡u ~0.25 mEq/L/ngÃ y',
            ],
            const Color(0xFF1565C0),
          ),
          const SizedBox(height: 8),
          _kStep(
            '2ï¸âƒ£ TRUYá»€N TÄ¨NH Máº CH (khi K+ < 3.0 hoáº·c cÃ³ triá»‡u chá»©ng)',
            'KCl truyá»n TM - Cáº¨N THáº¬N nguy cÆ¡ loáº¡n nhá»‹p:',
            const [
              'ðŸ’‰ Liá»u khá»Ÿi Ä‘áº§u: 20-40 mEq KCl trong 1L NaCl 0.9%, truyá»n 4-6 giá»',
              '   â†’ Tá»‘c Ä‘á»™: KHÃ”NG quÃ¡ 10-20 mEq/giá» qua TM ngoáº¡i vi',
              '   â†’ TM trung tÃ¢m (CVC): max 20-40 mEq/giá» (cÃ³ monitor tim liÃªn tá»¥c)',
              'âš ï¸ TUYá»†T Äá»I KHÃ”NG:',
              '   âŒ TiÃªm KCl bolus TM (gÃ¢y ngá»«ng tim tá»©c thÃ¬)',
              '   âŒ Pha KCl vá»›i Glucose 5% hoáº·c Ringer Lactat (Ca2+ + K+ gÃ¢y tá»§a)',
              'âŒ Truyá»n > 20 mEq/giá» qua TM ngoáº¡i vi (gÃ¢y Ä‘au, viÃªm tÄ©nh máº¡ch)',
              'ðŸ” MONITOR: EKG liÃªn tá»¥c + K+ mÃ¡u má»—i 4-6 giá»',
            ],
            const Color(0xFFD32F2F),
          ),
          const SizedBox(height: 8),
          _kStep(
            '3ï¸âƒ£ Má»¤C TIÃŠU BÃ™ K+',
            'TÃ­nh toÃ¡n nhanh:',
            const [
              'ðŸ“Š Thiáº¿u há»¥t K+ (mEq) â‰ˆ 0.4 Ã— cÃ¢n náº·ng (kg) Ã— (K+ bÃ¬nh thÆ°á»ng - K+ hiá»‡n táº¡i)',
              '   â†’ VÃ­ dá»¥: BN 60kg, K+ = 2.5: thiáº¿u â‰ˆ 0.4 Ã— 60 Ã— (4 - 2.5) = 36 mEq',
              'ðŸŽ¯ Má»¥c tiÃªu: K+ â‰¥ 3.5 mEq/L (an toÃ n cho pháº«u thuáº­t, digoxin)',
              'â±ï¸ Tá»‘c Ä‘á»™ bÃ¹ tá»‘i Ä‘a 20 mEq/giá» (TM ngoáº¡i vi) / 40 mEq/giá» (TM trung tÃ¢m)',
              'ðŸ“ˆ Má»—i 20 mEq KCl tÄƒng K+ mÃ¡u ~0.25 mEq/L (trung bÃ¬nh)',
              'âš ï¸ KHÃ”NG cá»‘ bÃ¹ nhanh - cÆ¡ thá»ƒ cáº§n 12-24h Ä‘á»ƒ cÃ¢n báº±ng K+ ná»™i bÃ o',
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
                    Text('TÃ¬m nguyÃªn nhÃ¢n gá»‘c (quan trá»ng!)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                  SizedBox(height: 6),
                  Text('â€¢ Máº¥t qua tháº­n: lá»£i tiá»ƒu (Furosemide, Thiazide), corticosteroid', style: TextStyle(fontSize: 12)),
                  Text('â€¢ Máº¥t qua tiÃªu hÃ³a: nÃ´n, tiÃªu cháº£y, sonde dáº¡ dÃ y, lá»— rÃ²', style: TextStyle(fontSize: 12)),
                  Text('â€¢ VÃ o ná»™i bÃ o: insulin, beta-agonist (salbutamol), toan kiá»m', style: TextStyle(fontSize: 12)),
                  Text('â€¢ Ä‚n uá»‘ng kÃ©m: nghiá»‡n rÆ°á»£u, Äƒn chay, suy dinh dÆ°á»¡ng', style: TextStyle(fontSize: 12)),
                  Text('â€¢ Bá»‡nh lÃ½: cÆ°á»ng Aldosteron, h/c Cushing, Bartter, Gitelman', style: TextStyle(fontSize: 12)),
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
                'âš ï¸ Ghi chÃº: KHÃ”NG dÃ¹ng Salbutamol trong cÆ¡n hen cáº¥p náº¿u K+ < 3.0 (lÃ m háº¡ K+ thÃªm, nguy cÆ¡ loáº¡n nhá»‹p). BÃ¹ K+ trÆ°á»›c khi dÃ¹ng Insulin cho bá»‡nh nhÃ¢n ÄTÄ cÃ³ K+ tháº¥p.\n\n'
                'ðŸ“š Tham kháº£o: Uptodate 2026, Harrison 21st ed.',
                style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}