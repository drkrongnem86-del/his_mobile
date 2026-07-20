// ERICU Calculators - các máy tính y khoa cho ER/ICU
// v2.38.2: Fix bug "kéo slider không cập nhật kết quả" - bỏ StatefulBuilder,
// dùng setState của state class, _SliderItem là StatelessWidget thật
import 'package:flutter/material.dart';

/// qSOFA Score (quick Sepsis-related Organ Failure Assessment)
class QSOFACalculator extends StatefulWidget {
  const QSOFACalculator({super.key});
  @override
  State<QSOFACalculator> createState() => _QSOFACalculatorState();
}

class _QSOFACalculatorState extends State<QSOFACalculator> {
  int rr = 16;
  int sbp = 120;
  int gcs = 15;
  int get score {
    int s = 0;
    if (rr >= 22) s++;
    if (sbp <= 100) s++;
    if (gcs < 15) s++;
    return s;
  }
  String get severity {
    if (score >= 2) return '⚠️ Nghi ngờ nhiễm trùng huyết - cần đánh giá thêm SOFA + xử trí';
    return 'Nguy cơ thấp';
  }

  @override
  Widget build(BuildContext context) => _calcScaffold(
    title: 'qSOFA Score',
    description: 'Đánh giá nhanh nguy cơ nhiễm trùng huyết',
    items: [
      _SliderItem(
        label: 'Nhịp thở (/phút)',
        value: rr.toDouble(),
        min: 5, max: 50,
        hint: '≥ 22 = +1',
        onChanged: (v) => setState(() => rr = v.round()),
      ),
      _SliderItem(
        label: 'Huyết áp tâm thu (mmHg)',
        value: sbp.toDouble(),
        min: 50, max: 200,
        hint: '≤ 100 = +1',
        onChanged: (v) => setState(() => sbp = v.round()),
      ),
      _SliderItem(
        label: 'Điểm Glasgow (GCS)',
        value: gcs.toDouble(),
        min: 3, max: 15,
        hint: '< 15 = +1',
        onChanged: (v) => setState(() => gcs = v.round()),
      ),
    ],
    total: '$score',
    severity: severity,
    color: Colors.deepOrange,
  );
}

/// NEWS2 Score (National Early Warning Score 2)
class NEWS2Calculator extends StatefulWidget {
  const NEWS2Calculator({super.key});
  @override
  State<NEWS2Calculator> createState() => _NEWS2CalculatorState();
}

class _NEWS2CalculatorState extends State<NEWS2Calculator> {
  int rr = 18, spo2 = 96, sbp = 120, hr = 75, temp = 37, conscious = 0;
  int get score => (rrScore + spo2Score + sbpScore + hrScore + tempScore + conscious);

  int get rrScore => rr <= 8 ? 3 : rr <= 11 ? 1 : rr <= 20 ? 0 : rr <= 24 ? 2 : 3;
  int get spo2Score => spo2 <= 91 ? 3 : spo2 <= 93 ? 2 : spo2 <= 95 ? 1 : 0;
  int get sbpScore => sbp <= 90 ? 3 : sbp <= 100 ? 2 : sbp <= 110 ? 1 : sbp <= 219 ? 0 : 3;
  int get hrScore => hr <= 40 ? 3 : hr <= 50 ? 1 : hr <= 90 ? 0 : hr <= 110 ? 1 : hr <= 130 ? 2 : 3;
  int get tempScore => temp <= 35 ? 3 : temp <= 36 ? 1 : temp <= 38 ? 0 : temp <= 39 ? 1 : 2;

  String get severity {
    if (score >= 7) return '🚨 NGUY KỊCH - Gọi cấp cứu ngay';
    if (score >= 5) return '⚠️ Nặng - Cần can thiệp khẩn cấp';
    if (score >= 3) return 'Cảnh báo - Theo dõi sát';
    return 'Bình thường';
  }

  @override
  Widget build(BuildContext context) => _calcScaffold(
    title: 'NEWS2 Score',
    description: 'National Early Warning Score 2 - đánh giá sớm bệnh nhân nặng',
    items: [
      _SliderItem(label: 'Nhịp thở (/phút)', value: rr.toDouble(), min: 5, max: 50, onChanged: (v) => setState(() => rr = v.round())),
      _SliderItem(label: 'SpO₂ (%)', value: spo2.toDouble(), min: 70, max: 100, onChanged: (v) => setState(() => spo2 = v.round())),
      _SliderItem(label: 'HA tâm thu (mmHg)', value: sbp.toDouble(), min: 50, max: 220, onChanged: (v) => setState(() => sbp = v.round())),
      _SliderItem(label: 'Mạch (/phút)', value: hr.toDouble(), min: 30, max: 200, onChanged: (v) => setState(() => hr = v.round())),
      _SliderItem(label: 'Nhiệt độ (°C)', value: temp.toDouble(), min: 32, max: 42, onChanged: (v) => setState(() => temp = v.round())),
    ],
    extra: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Text('Tri giác:', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Tỉnh'), selected: conscious == 0, onSelected: (_) => setState(() => conscious = 0)),
          const SizedBox(width: 4),
          ChoiceChip(label: const Text('Lơ mơ'), selected: conscious == 1, onSelected: (_) => setState(() => conscious = 1)),
          const SizedBox(width: 4),
          ChoiceChip(label: const Text('Hôn mê'), selected: conscious == 3, onSelected: (_) => setState(() => conscious = 3)),
        ]),
      ),
    ],
    total: '$score',
    severity: severity,
    color: Colors.red,
  );
}

/// BMI Calculator
class BMICalculator extends StatefulWidget {
  const BMICalculator({super.key});
  @override
  State<BMICalculator> createState() => _BMICalculatorState();
}

class _BMICalculatorState extends State<BMICalculator> {
  double height = 170;
  double weight = 65;
  double get bmi => weight / ((height / 100) * (height / 100));
  String get cat {
    if (bmi < 18.5) return 'Gầy';
    if (bmi < 25) return 'Bình thường';
    if (bmi < 30) return 'Thừu cân';
    if (bmi < 35) return 'Béo phì độ I';
    return 'Béo phì độ II+';
  }

  @override
  Widget build(BuildContext context) => _calcScaffold(
    title: 'BMI Calculator',
    description: 'Chỉ số khối cơ thể',
    items: [
      _SliderItem(label: 'Chiều cao (cm)', value: height, min: 100, max: 220, onChanged: (v) => setState(() => height = v)),
      _SliderItem(label: 'Cân nặng (kg)', value: weight, min: 20, max: 200, onChanged: (v) => setState(() => weight = v)),
    ],
    total: bmi.toStringAsFixed(1),
    severity: cat,
    color: Colors.green,
  );
}

/// Creatinine Clearance (Cockcroft-Gault)
class CrClCalculator extends StatefulWidget {
  const CrClCalculator({super.key});
  @override
  State<CrClCalculator> createState() => _CrClCalculatorState();
}

class _CrClCalculatorState extends State<CrClCalculator> {
  double age = 60, weight = 65, creatinine = 1.0;
  int isMale = 1; // 1=nam, 0=nữ
  double get crcl => ((140 - age) * weight * isMale) / (72 * creatinine);
  String get severity {
    final v = crcl;
    if (v >= 90) return 'Bình thường';
    if (v >= 60) return 'Suy thận nhẹ (G1-G2)';
    if (v >= 30) return 'Suy thận TB (G3)';
    if (v >= 15) return 'Suy thận nặng (G4)';
    return 'Suy thận giai đoạn cuối (G5)';
  }

  @override
  Widget build(BuildContext context) => _calcScaffold(
    title: 'Creatinine Clearance',
    description: 'Cockcroft-Gault - chức năng thận',
    items: [
      _SliderItem(label: 'Tuổi', value: age, min: 1, max: 120, onChanged: (v) => setState(() => age = v)),
      _SliderItem(label: 'Cân nặng (kg)', value: weight, min: 20, max: 200, onChanged: (v) => setState(() => weight = v)),
      _SliderItem(label: 'Creatinine (mg/dL)', value: creatinine, min: 0.1, max: 10, divisions: 100, onChanged: (v) => setState(() => creatinine = v)),
    ],
    extra: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Text('Giới tính:', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Nam'), selected: isMale == 1, onSelected: (_) => setState(() => isMale = 1)),
          const SizedBox(width: 4),
          ChoiceChip(label: const Text('Nữ'), selected: isMale == 0, onSelected: (_) => setState(() => isMale = 0)),
        ]),
      ),
    ],
    total: '${crcl.toStringAsFixed(1)} mL/min',
    severity: severity,
    color: Colors.indigo,
  );
}

/// Dịch truyền / Bù dịch tính
class FluidCalculator extends StatefulWidget {
  const FluidCalculator({super.key});
  @override
  State<FluidCalculator> createState() => _FluidCalculatorState();
}

class _FluidCalculatorState extends State<FluidCalculator> {
  double weight = 60;
  int hours = 24;
  // Công thức Holliday-Segar: 4-2-1 cho trẻ em
  // Người lớn: 30-40 mL/kg/ngày
  double get totalMl => weight * 35;
  double get perHour => totalMl / hours;

  @override
  Widget build(BuildContext context) => _calcScaffold(
    title: 'Tính dịch truyền',
    description: 'Công thức người lớn: 30-40 mL/kg/24h',
    items: [
      _SliderItem(label: 'Cân nặng (kg)', value: weight, min: 20, max: 150, onChanged: (v) => setState(() => weight = v)),
      _SliderItem(label: 'Thời gian truyền (giờ)', value: hours.toDouble(), min: 1, max: 48, onChanged: (v) => setState(() => hours = v.round())),
    ],
    total: '${totalMl.toStringAsFixed(0)} mL',
    severity: '≈ ${perHour.toStringAsFixed(0)} mL/giờ  •  ${(perHour / 60 * 20).toStringAsFixed(0)} gtt/ph (20gtt/mL)',
    color: Colors.cyan,
  );
}

/// Burn Calculator (Rule of 9s + Parkland)
class BurnCalculator extends StatefulWidget {
  const BurnCalculator({super.key});
  @override
  State<BurnCalculator> createState() => _BurnCalculatorState();
}

class _BurnCalculatorState extends State<BurnCalculator> {
  double weight = 60;
  int burnPct = 20; // % diện tích bỏng
  double get tbsa => burnPct.toDouble();
  double get parkland => 4 * weight * burnPct; // 4mL x kg x %TBSA = mL trong 24h đầu
  double get first8h => parkland / 2;
  double get next16h => parkland / 2;

  @override
  Widget build(BuildContext context) => _calcScaffold(
    title: 'Tính dịch bỏng (Parkland)',
    description: 'Rule of 9s + công thức Parkland (trẻ em: 4-2-1)',
    items: [
      _SliderItem(label: 'Cân nặng (kg)', value: weight, min: 5, max: 150, onChanged: (v) => setState(() => weight = v)),
      _SliderItem(label: 'Diện tích bỏng (% TBSA)', value: burnPct.toDouble(), min: 1, max: 100, onChanged: (v) => setState(() => burnPct = v.round())),
    ],
    total: '${parkland.toStringAsFixed(0)} mL/24h',
    severity: '8h đầu: ${first8h.toStringAsFixed(0)} mL  •  16h sau: ${next16h.toStringAsFixed(0)} mL',
    color: Colors.deepOrange,
  );
}

/// Anesthesia / Sedation calculator
class SedationCalculator extends StatefulWidget {
  const SedationCalculator({super.key});
  @override
  State<SedationCalculator> createState() => _SedationCalculatorState();
}

class _SedationCalculatorState extends State<SedationCalculator> {
  double weight = 60;
  // Propofol: 1-2 mg/kg bolus, 5-10 mcg/kg/min duy trì
  // Midazolam: 0.05-0.1 mg/kg bolus, 0.5-2 mcg/kg/min
  // Fentanyl: 1-2 mcg/kg bolus, 0.5-2 mcg/kg/min
  double get propofolBolus => 1.5 * weight;
  double get propofolInfusion => 7 * weight; // mcg/kg/min → mg/h
  double get midazolamBolus => 0.075 * weight;
  double get fentanylBolus => 0.0015 * weight; // mg

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Sedation Calculator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SliderItem(
            label: 'Cân nặng (kg)',
            value: weight,
            min: 20, max: 150,
            onChanged: (v) => setState(() => weight = v),
          ),
          const SizedBox(height: 16),
          _drugCard('Propofol', 'Liều bolus', '${propofolBolus.toStringAsFixed(0)} mg', 'Truyền duy trì', '${propofolInfusion.toStringAsFixed(0)} mg/h', Colors.purple),
          const SizedBox(height: 12),
          _drugCard('Midazolam', 'Liều bolus', '${midazolamBolus.toStringAsFixed(1)} mg', '', '', Colors.indigo),
          const SizedBox(height: 12),
          _drugCard('Fentanyl', 'Liều bolus', '${(fentanylBolus * 1000).toStringAsFixed(0)} mcg', '', '', Colors.red),
        ],
      ),
    );
  }

  Widget _drugCard(String name, String l1, String v1, String l2, String v2, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 6, height: 24, color: color),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text('$l1: ', style: const TextStyle(color: Colors.black54)),
              Text(v1, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            if (l2.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                Text('$l2: ', style: const TextStyle(color: Colors.black54)),
                Text(v2, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Common helpers - v2.38.2: StatelessWidget thật, dùng onChanged callback
class _SliderItem extends StatelessWidget {
  final String label;
  final double value;
  final double min, max;
  final String hint;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _SliderItem({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.hint = '',
    this.divisions = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
            Text(value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
            if (hint.isNotEmpty) const SizedBox(width: 8),
            if (hint.isNotEmpty) Text(hint, style: const TextStyle(fontSize: 11, color: Colors.black45)),
          ]),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

Widget _calcScaffold({
  required String title,
  required String description,
  required List<Widget> items,
  required String total,
  required String severity,
  required Color color,
  List<Widget> extra = const [],
}) {
  return Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: color,
      foregroundColor: Colors.white,
      title: Text(title),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: color.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 6, height: 32, color: color),
                  const SizedBox(width: 12),
                  const Text('Kết quả', style: TextStyle(color: Colors.black87)),
                  const SizedBox(width: 8),
                  Text(total, style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                Text(severity, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 16),
        ...items,
        ...extra,
      ],
    ),
  );
}