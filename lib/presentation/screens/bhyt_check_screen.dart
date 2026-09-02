// BHYTCheckScreen v2.37.1 - Kiểm tra thẻ BHYT
// Gọi Data API: POST /v1/insurance/check
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class BHYTCheckScreen extends StatefulWidget {
  const BHYTCheckScreen({super.key});

  @override
  State<BHYTCheckScreen> createState() => _BHYTCheckScreenState();
}

class _BHYTCheckScreenState extends State<BHYTCheckScreen> {
  final _cardCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _check() async {
    final card = _cardCtrl.text.trim();
    if (card.isEmpty) {
      _snack('Vui lòng nhập số thẻ BHYT');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final dio = Dio(BaseOptions(baseUrl: DataService.instance.baseUrl, connectTimeout: const Duration(seconds: 10)));
      final r = await dio.post('/v1/insurance/check', data: {
        'cardNumber': card,
        if (_nameCtrl.text.isNotEmpty) 'patientName': _nameCtrl.text.trim(),
        if (_dobCtrl.text.isNotEmpty) 'dob': _dobCtrl.text.trim(),
      });
      if (r.statusCode == 200 && r.data is Map) {
        setState(() {
          _result = Map<String, dynamic>.from(r.data as Map);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'API trả về HTTP ${r.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Lỗi: ${e.toString().split("\n").first}';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
        title: const Text('Kiểm tra BHYT', style: TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(compact: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Form nhập
                  TextField(
                    controller: _cardCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số thẻ BHYT *',
                      hintText: 'VD: 2746040123',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.credit_card),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Họ tên (tùy chọn)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _dobCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ngày sinh (dd/MM/yyyy)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.cake),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _check,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00838F),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _loading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.search),
                    label: Text(_loading ? 'Đang kiểm tra...' : 'Kiểm tra BHYT', style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(height: 16),
                  // Kết quả
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.error, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                      ]),
                    ),
                  if (_result != null) _buildResult(_result!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(Map<String, dynamic> r) {
    final ok = r['valid'] == true || r['isValid'] == true || r['status'] == 'active';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ok ? Colors.green : Colors.orange),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(ok ? Icons.check_circle : Icons.warning, color: ok ? Colors.green : Colors.orange, size: 28),
            const SizedBox(width: 8),
            Text(ok ? 'Thẻ BHYT hợp lệ' : 'Thẻ BHYT không hợp lệ / hết hạn',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ok ? Colors.green.shade700 : Colors.orange.shade700)),
          ]),
          const SizedBox(height: 8),
          for (final entry in r.entries) ...[
            if (entry.value != null && entry.value.toString().isNotEmpty && entry.key != 'valid' && entry.key != 'isValid')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 100, child: Text(entry.key, style: const TextStyle(color: Colors.black54, fontSize: 12))),
                    Expanded(child: Text('${entry.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}