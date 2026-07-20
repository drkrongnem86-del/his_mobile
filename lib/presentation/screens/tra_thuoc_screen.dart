// TraThuocScreen v2.37.1 - Tra cứu thuốc trong BV
// Tìm trong HIS_MEDICINE (cached từ SQLite) hoặc gọi API HIS
import 'package:flutter/material.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class TraThuocScreen extends StatefulWidget {
  const TraThuocScreen({super.key});

  @override
  State<TraThuocScreen> createState() => _TraThuocScreenState();
}

class _TraThuocScreenState extends State<TraThuocScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  // Danh sách thuốc BV phổ biến (sample - sẽ thay bằng API sau)
  final List<Map<String, dynamic>> _sampleMeds = [
    {'code': 'PN001', 'name': 'Paracetamol 500mg', 'group': 'Giảm đau - Hạ sốt', 'price': '500đ/viên'},
    {'code': 'PN002', 'name': 'Paracetamol 650mg', 'group': 'Giảm đau - Hạ sốt', 'price': '800đ/viên'},
    {'code': 'AM001', 'name': 'Amoxicillin 500mg', 'group': 'Kháng sinh', 'price': '1.500đ/viên'},
    {'code': 'AM002', 'name': 'Amoxicillin 250mg/5ml', 'group': 'Kháng sinh', 'price': '25.000đ/lọ'},
    {'code': 'AZ001', 'name': 'Azithromycin 500mg', 'group': 'Kháng sinh', 'price': '5.000đ/viên'},
    {'code': 'IB001', 'name': 'Ibuprofen 400mg', 'group': 'NSAID', 'price': '1.000đ/viên'},
    {'code': 'DI001', 'name': 'Diclofenac 50mg', 'group': 'NSAID', 'price': '1.200đ/viên'},
    {'code': 'OM001', 'name': 'Omeprazole 20mg', 'group': 'Dạ dày', 'price': '2.000đ/viên'},
    {'code': 'PA001', 'name': 'Pantoprazole 40mg', 'group': 'Dạ dày', 'price': '3.500đ/viên'},
    {'code': 'AT001', 'name': 'Atorvastatin 20mg', 'group': 'Mỡ máu', 'price': '4.000đ/viên'},
    {'code': 'AM101', 'name': 'Amlodipine 5mg', 'group': 'Tim mạch', 'price': '1.500đ/viên'},
    {'code': 'LO001', 'name': 'Losartan 50mg', 'group': 'Tim mạch', 'price': '2.500đ/viên'},
    {'code': 'ME001', 'name': 'Metformin 500mg', 'group': 'Đái tháo đường', 'price': '800đ/viên'},
    {'code': 'IN001', 'name': 'Insulin NPH', 'group': 'Đái tháo đường', 'price': '120.000đ/lọ'},
    {'code': 'SA001', 'name': 'Salbutamol 4mg', 'group': 'Hô hấp', 'price': '600đ/viên'},
    {'code': 'DE001', 'name': 'Dexamethasone 4mg', 'group': 'Corticoid', 'price': '1.200đ/viên'},
    {'code': 'PR001', 'name': 'Prednisolone 5mg', 'group': 'Corticoid', 'price': '800đ/viên'},
    {'code': 'CE001', 'name': 'Ceftriaxone 1g', 'group': 'Kháng sinh', 'price': '45.000đ/lọ'},
    {'code': 'NA001', 'name': 'Natri clorua 0.9%', 'group': 'Dịch truyền', 'price': '12.000đ/chai'},
    {'code': 'GL001', 'name': 'Glucose 5%', 'group': 'Dịch truyền', 'price': '12.000đ/chai'},
    {'code': 'RI001', 'name': 'Ringer Lactat', 'group': 'Dịch truyền', 'price': '15.000đ/chai'},
  ];

  void _search(String q) {
    q = q.trim().toLowerCase();
    if (q.isEmpty) {
      // v2.98.6: Khi rỗng → hiện top 10 thuốc phổ biến (giúp BS thấy list ngay)
      setState(() => _results = _sampleMeds.take(10).toList());
      return;
    }
    final filtered = _sampleMeds.where((m) {
      return (m['name'] as String).toLowerCase().contains(q) || (m['code'] as String).toLowerCase().contains(q) || (m['group'] as String).toLowerCase().contains(q);
    }).toList();
    setState(() => _results = filtered);
  }

  @override
  void initState() {
    super.initState();
    // v2.98.6: Auto-load top 10 thuốc phổ biến khi mở màn hình
    _results = _sampleMeds.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        title: const Text('Tra cứu thuốc', style: TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(compact: true),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _ctrl,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Tìm thuốc theo tên, mã, nhóm...',
                prefixIcon: const Icon(Icons.search, color: Colors.purple),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Colors.black54),
                        onPressed: () {
                          _ctrl.clear();
                          _search('');
                        },
                      ),
              ),
            ),
          ),
          // v2.98.6: Hiện "Top thuốc phổ biến" khi search rỗng
          if (_ctrl.text.isEmpty && _results.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Text(
                'Top ${_results.length} thuốc phổ biến (gõ để lọc thêm)',
                style: TextStyle(color: Colors.purple.shade400, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.medication, size: 64, color: Colors.black26),
                        const SizedBox(height: 12),
                        Text(_ctrl.text.isEmpty ? 'Nhập tên thuốc để tra cứu' : 'Không tìm thấy thuốc "${_ctrl.text}"', style: const TextStyle(color: Colors.black45)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) => _buildMedCard(_results[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedCard(Map<String, dynamic> m) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: false,
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.medication, color: Color(0xFF7B1FA2), size: 22),
        ),
        title: Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          'Mã: ${m['code']}',
          m['group'],
          m['price'],
        ].where((s) => s != null && s.toString().isNotEmpty).join(' • ')),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}