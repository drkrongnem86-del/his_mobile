// HisConfigScreen v2.75.1 → v3.0.63
// Màn hình "Cấu hình HIS" - giống app v0.3.0 (team BS)
// - 3 nút chọn nhanh: "Public VPN" / "LAN nội bộ" / "Proxy qua PC" (v3.0.49)
// - 3 URL chính: BVBM (login), HIS EMR (fallback), HIS MOS (ICD)
// - Tài khoản, Mã khoa (mặc định 22), Tên khoa
// - Nút Lưu cấu hình + Test kết nối
// v3.0.63:
//   + Thêm 7 thongke URL fields (collapsible section "Thongke public")
//   + Thêm "Thời gian chờ API" (giây) - default 5s, configurable
//   + Ẩn KCB test button (không dùng nữa)
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:his_mobile/core/services/his_config_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/api/emr_push_service.dart';
import 'package:http/http.dart' as http;

class HisConfigScreen extends StatefulWidget {
  const HisConfigScreen({super.key});

  @override
  State<HisConfigScreen> createState() => _HisConfigScreenState();
}

class _HisConfigScreenState extends State<HisConfigScreen> {
  late TextEditingController _bvbmCtrl;
  late TextEditingController _emrCtrl;
  late TextEditingController _mosCtrl;
  late TextEditingController _loginCtrl;
  late TextEditingController _deptIdCtrl;
  late TextEditingController _deptNameCtrl;
  // v3.0.63: 7 thongke controllers
  late TextEditingController _thongkeBaseCtrl;
  late TextEditingController _thongkeLoginCtrl;
  late TextEditingController _thongkeHomeCtrl;
  late TextEditingController _thongkeInsuranceCheckCtrl;
  late TextEditingController _thongkeInsuranceSearchCtrl;
  late TextEditingController _thongkeEmrIndexCtrl;
  late TextEditingController _thongkeEmrSearchCtrl;
  // v3.0.63: Timeout (giây) - default 5
  late TextEditingController _apiTimeoutCtrl;
  // v3.0.63: Ẩn KCB section (không dùng nữa)
  bool _useKcb = true;
  late String _mode;
  // v3.0.11: Bearer tùy chỉnh (paste từ app Y tế số)
  late TextEditingController _bearerCtrl;
  String _bearerSource = '';

  bool _testing = false;
  String? _testResult;
  // v3.0.63: Collapsible state cho Thongke section
  bool _showThongke = false;

  @override
  void initState() {
    super.initState();
    final c = HisConfigService.instance.config;
    _bvbmCtrl = TextEditingController(text: c.bvbmUrl);
    _emrCtrl = TextEditingController(text: c.emrUrl);
    _mosCtrl = TextEditingController(text: c.mosUrl);
    _loginCtrl = TextEditingController(text: c.loginName);
    _deptIdCtrl = TextEditingController(text: c.defaultDeptId.toString());
    _deptNameCtrl = TextEditingController(text: c.defaultDeptName);
    // v3.0.63: Init 7 thongke controllers
    _thongkeBaseCtrl = TextEditingController(text: c.thongkeBaseUrl);
    _thongkeLoginCtrl = TextEditingController(text: c.thongkeLoginUrl);
    _thongkeHomeCtrl = TextEditingController(text: c.thongkeHomeUrl);
    _thongkeInsuranceCheckCtrl = TextEditingController(text: c.thongkeInsuranceCheckUrl);
    _thongkeInsuranceSearchCtrl = TextEditingController(text: c.thongkeInsuranceSearchUrl);
    _thongkeEmrIndexCtrl = TextEditingController(text: c.thongkeEmrIndexUrl);
    _thongkeEmrSearchCtrl = TextEditingController(text: c.thongkeEmrSearchUrl);
    // v3.0.63: Init timeout
    _apiTimeoutCtrl = TextEditingController(text: '5');
    _useKcb = c.useKcbForEmr;
    _mode = c.mode;
    // v3.0.11: Init bearer controller
    _bearerCtrl = TextEditingController();
    _loadBearer();
  }

  @override
  void dispose() {
    _bvbmCtrl.dispose();
    _emrCtrl.dispose();
    _mosCtrl.dispose();
    _loginCtrl.dispose();
    _deptIdCtrl.dispose();
    _deptNameCtrl.dispose();
    _thongkeBaseCtrl.dispose();
    _thongkeLoginCtrl.dispose();
    _thongkeHomeCtrl.dispose();
    _thongkeInsuranceCheckCtrl.dispose();
    _thongkeInsuranceSearchCtrl.dispose();
    _thongkeEmrIndexCtrl.dispose();
    _thongkeEmrSearchCtrl.dispose();
    _apiTimeoutCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(HisConfigPreset preset) {
    setState(() {
      if (preset == HisConfigService.presetLan) {
        _mode = 'lan';
      } else if (preset == HisConfigService.presetProxyPc) {
        _mode = 'proxy';
      } else {
        _mode = 'public_vpn';
      }
      _bvbmCtrl.text = preset.bvbmUrl;
      _emrCtrl.text = preset.emrUrl;
      _mosCtrl.text = preset.mosUrl;
      // v3.0.62: Thongke cũng apply theo preset (mặc định là thongke public)
      _thongkeBaseCtrl.text = preset.thongkeBaseUrl;
      _thongkeLoginCtrl.text = preset.thongkeLoginUrl;
      _thongkeHomeCtrl.text = preset.thongkeHomeUrl;
      _thongkeInsuranceCheckCtrl.text = preset.thongkeInsuranceCheckUrl;
      _thongkeInsuranceSearchCtrl.text = preset.thongkeInsuranceSearchUrl;
      _thongkeEmrIndexCtrl.text = preset.thongkeEmrIndexUrl;
      _thongkeEmrSearchCtrl.text = preset.thongkeEmrSearchUrl;
    });
  }

  Future<void> _save() async {
    final prev = HisConfigService.instance.config;
    final c = HisConfig(
      mode: _mode,
      bvbmUrl: _bvbmCtrl.text.trim(),
      acsUrl: prev.acsUrl,
      emrUrl: _emrCtrl.text.trim(),
      mosUrl: _mosCtrl.text.trim(),
      sarUrl: prev.sarUrl,
      sdaUrl: prev.sdaUrl,
      fssUrl: prev.fssUrl,
      lisUrl: prev.lisUrl,
      ocrUrl: prev.ocrUrl,
      dmsUrl: prev.dmsUrl,
      emrWebUrl: prev.emrWebUrl,
      redisUrl: prev.redisUrl,
      vvaUrl: prev.vvaUrl,
      // v3.0.62/63: Lưu 7 thongke fields
      thongkeBaseUrl: _thongkeBaseCtrl.text.trim(),
      thongkeLoginUrl: _thongkeLoginCtrl.text.trim(),
      thongkeHomeUrl: _thongkeHomeCtrl.text.trim(),
      thongkeInsuranceCheckUrl: _thongkeInsuranceCheckCtrl.text.trim(),
      thongkeInsuranceSearchUrl: _thongkeInsuranceSearchCtrl.text.trim(),
      thongkeEmrIndexUrl: _thongkeEmrIndexCtrl.text.trim(),
      thongkeEmrSearchUrl: _thongkeEmrSearchCtrl.text.trim(),
      kcbBaseUrl: prev.kcbBaseUrl,
      kcbToken: prev.kcbToken,
      kcbHospitalCode: prev.kcbHospitalCode,
      useKcbForEmr: _useKcb,
      loginName: _loginCtrl.text.trim(),
      password: prev.password,
      defaultDeptId: int.tryParse(_deptIdCtrl.text.trim()) ?? 22,
      defaultDeptName: _deptNameCtrl.text.trim(),
      nameField: prev.nameField,
    );
    await HisConfigService.instance.save(c);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Đã lưu cấu hình'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.pop(context, true);
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    // v3.0.63: Timeout configurable theo _apiTimeoutCtrl
    final timeoutSec = int.tryParse(_apiTimeoutCtrl.text.trim()) ?? 5;
    final apiTimeout = Duration(seconds: timeoutSec.clamp(2, 60));
    final urls = <String, String>{
      'BVBM': _bvbmCtrl.text.trim(),
      'EMR': _emrCtrl.text.trim(),
      'MOS': _mosCtrl.text.trim(),
      'Thongke': _thongkeBaseCtrl.text.trim() + _thongkeHomeCtrl.text.trim(),
    };
    final results = <String>[];
    for (final entry in urls.entries) {
      try {
        final r = await http
            .get(Uri.parse(entry.value))
            .timeout(apiTimeout);
        results.add('${entry.key}: ${r.statusCode} ✅ (${apiTimeout.inSeconds}s timeout)');
      } catch (e) {
        final errShort = e.toString().split('\n').first;
        results.add('${entry.key}: ❌ $errShort');
      }
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = results.join('\n');
    });
  }

  // v3.0.63: Đã bỏ _testKcb() - Cục KCB không dùng nữa

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        title: const Text('Cấu hình', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section: URL Backend (chọn nhanh)
            const Text(
              'URL Backend (chọn nhanh)',
              style: TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 160,
                  child: _presetButton(
                    label: 'Public VPN',
                    icon: Icons.public,
                    active: _mode == 'public_vpn',
                    onTap: () => _applyPreset(HisConfigService.presetPublicVpn),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: _presetButton(
                    label: 'LAN nội bộ',
                    icon: Icons.business,
                    active: _mode == 'lan',
                    onTap: () => _applyPreset(HisConfigService.presetLan),
                  ),
                ),
                // v3.0.50: ẨN nút "Proxy qua PC" - BS không cần (theo yêu cầu 19/7)
                // Giữ code presetProxyPc + ConnectionService.isProxy để dùng lại sau
                // SizedBox(
                //   width: 160,
                //   child: _presetButton(
                //     label: 'Proxy qua PC',
                //     icon: Icons.computer,
                //     active: _mode == 'proxy',
                //     onTap: () => _applyPreset(HisConfigService.presetProxyPc),
                //   ),
                // ),
              ],
            ),
            const SizedBox(height: 20),

            // URL BVBM
            _urlField(
              label: 'URL BVBM (login + DS BN)',
              controller: _bvbmCtrl,
              icon: Icons.cloud,
            ),
            const SizedBox(height: 12),
            // URL HIS EMR
            _urlField(
              label: 'URL HIS EMR (fallback)',
              controller: _emrCtrl,
              icon: Icons.medical_services,
            ),
            const SizedBox(height: 12),
            // URL HIS MOS
            _urlField(
              label: 'URL HIS MOS (ICD)',
              controller: _mosCtrl,
              icon: Icons.list_alt,
            ),
            const SizedBox(height: 20),

            // Tài khoản
            TextField(
              controller: _loginCtrl,
              decoration: const InputDecoration(
                labelText: 'Tài khoản',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Mã khoa
            TextField(
              controller: _deptIdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Mã khoa (mặc định 22)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Tên khoa
            TextField(
              controller: _deptNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên khoa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // v3.0.63: Thời gian chờ API (timeout 5s mặc định)
            // Nếu 1 link API quá timeout, tự fallback về link tốt nhất (HIS Pro primary)
            TextField(
              controller: _apiTimeoutCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Thời gian chờ API (giây, mặc định 5)',
                prefixIcon: Icon(Icons.timer, color: Color(0xFF1976D2)),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 20),

            // v3.0.63: Thongke public - collapsible section (7 endpoints)
            InkWell(
              onTap: () => setState(() => _showThongke = !_showThongke),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1976D2).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bar_chart, color: Color(0xFF1976D2), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Thongke public (7 endpoints)',
                        style: TextStyle(
                          color: Color(0xFF1976D2),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      _showThongke ? Icons.expand_less : Icons.expand_more,
                      color: const Color(0xFF1976D2),
                    ),
                  ],
                ),
              ),
            ),
            if (_showThongke) ...[
              const SizedBox(height: 12),
              _urlField(
                label: 'Thongke Base URL',
                controller: _thongkeBaseCtrl,
                icon: Icons.cloud,
              ),
              const SizedBox(height: 12),
              _urlField(
                label: 'Thongke Login (/login)',
                controller: _thongkeLoginCtrl,
                icon: Icons.login,
              ),
              const SizedBox(height: 12),
              _urlField(
                label: 'Thongke Home (/home)',
                controller: _thongkeHomeCtrl,
                icon: Icons.home,
              ),
              const SizedBox(height: 12),
              _urlField(
                label: 'Thongke Insurance Check (/insurance/check-card)',
                controller: _thongkeInsuranceCheckCtrl,
                icon: Icons.health_and_safety,
              ),
              const SizedBox(height: 12),
              _urlField(
                label: 'Thongke Insurance Search (/insurance/medicine-search)',
                controller: _thongkeInsuranceSearchCtrl,
                icon: Icons.search,
              ),
              const SizedBox(height: 12),
              _urlField(
                label: 'Thongke EMR Index (/emr/index)',
                controller: _thongkeEmrIndexCtrl,
                icon: Icons.folder_shared,
              ),
              const SizedBox(height: 12),
              _urlField(
                label: 'Thongke EMR Search (/emr/index/search)',
                controller: _thongkeEmrSearchCtrl,
                icon: Icons.search,
              ),
            ],
            const SizedBox(height: 20),

            // Test result
            if (_testResult != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                ),
                child: Text(
                  _testResult!,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),

            // Lưu cấu hình
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Lưu cấu hình',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Test kết nối
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_testing ? 'Đang test...' : 'Test kết nối',
                    style: const TextStyle(fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  side: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// v3.0.11: Load Bearer custom từ SharedPreferences
  Future<void> _loadBearer() async {
    final bearer = await HisProApiService.instance.getCustomBearer();
    if (mounted) {
      setState(() {
        _bearerCtrl.text = bearer ?? '';
        _bearerSource = HisProApiService.instance.getEffectiveTokenSource();
      });
    }
  }

  /// v3.0.11: Lưu Bearer custom
  Future<void> _saveBearer() async {
    final token = _bearerCtrl.text.trim();
    if (token.isEmpty) {
      _snack('Vui lòng nhập Bearer token', Colors.red);
      return;
    }
    if (token.length < 32) {
      _snack('Bearer token quá ngắn (tối thiểu 32 chars)', Colors.red);
      return;
    }
    await HisProApiService.instance.setCustomBearer(token);
    if (mounted) {
      setState(() {
        _bearerSource = HisProApiService.instance.getEffectiveTokenSource();
      });
      _snack('✅ Đã lưu Bearer custom. App sẽ dùng token mới ngay.', Colors.green);
    }
  }

  /// v3.0.11: Xóa Bearer custom (fallback về hardcode)
  Future<void> _clearBearer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning, color: Colors.orange),
          SizedBox(width: 8),
          Text('Xóa Bearer custom?'),
        ]),
        content: const Text(
          'App sẽ fallback về Bearer hardcode từ app Y tế số thật.\n\n'
          'Nếu hardcode cũng hết hạn, bạn cần nhập Bearer mới.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await HisProApiService.instance.clearCustomBearer();
    _bearerCtrl.clear();
    if (mounted) {
      setState(() {
        _bearerSource = HisProApiService.instance.getEffectiveTokenSource();
      });
      _snack('Đã xóa Bearer custom. App dùng hardcode.', Colors.orange);
    }
  }

  /// v3.0.11: Test Bearer mới có work không
  Future<void> _testBearer() async {
    final token = _bearerCtrl.text.trim();
    if (token.isEmpty) {
      _snack('Nhập Bearer trước khi test', Colors.red);
      return;
    }
    setState(() => _testing = true);
    try {
      // Test với 3 endpoint chính
      final api = HisProApiService.instance;
      // Tạm thời set bearer mới để test
      await api.setCustomBearer(token);
      await api.getCustomBearer(); // refresh cache
      final results = <String>[];
      // v3.0.32: Thêm test push (quan trọng nhất - verify WRITE permission)
      results.add('--- Test PUSH (CreateByTdo) ---');
      try {
        final pushResult = await EmrPushService.instance.pushPdfToEmrUnsigned(
          pdfBytes: _makeTestPdf(),
          treatmentCode: '000002128160',
          documentName: 'TEST_BEARER_${DateTime.now().millisecondsSinceEpoch}',
          documentTypeId: 8,  // phieu cham soc
          roomCode: 'PKCC',
          roomTypeCode: 'XL',
          departmentCode: 'HSCC',
          workingDeptName: 'Khoa Cấp Cứu',
          useFss: false,  // base64 mode - không cần FSS
        );
        if (pushResult.success) {
          results.add('✅ CreateByTdo: OK${pushResult.documentCode != null ? " (${pushResult.documentCode})" : ""}');
        } else {
          results.add('❌ CreateByTdo: ${pushResult.error}');
        }
      } catch (e) {
        results.add('❌ CreateByTdo exception: $e');
      }
      results.add('--- Test READ (Get endpoints) ---');
      final t1 = await api.getEmrTreatment(limit: 10);
      results.add('EmrTreatment/Get: ${t1.success ? "✅ ${_count(t1.data)} records" : "❌ ${t1.message}"}');
      final t2 = await api.getHisTreatment(limit: 10);
      results.add('HisTreatment/Get: ${t2.success ? "✅ ${_count(t2.data)} records" : "❌ ${t2.message}"}');
      final t3 = await api.get(
        '${api.getEmrBaseUrlSync()}api/EmrSigner/Get',
        const <String, dynamic>{},
        limit: 10,
      );
      results.add('EmrSigner/Get: ${t3.success ? "✅ ${_count(t3.data)} records" : "❌ ${t3.message}"}');
      // v3.0.32: Test thử GetView (endpoint Xem bệnh án)
      results.add('--- Test READ (Xem bệnh án) ---');
      final t4 = await api.getEmrDocumentView(treatmentCode: '000002128160', limit: 10);
      results.add('EmrDocument/GetView: ${t4.success ? "✅ ${_count(t4.data)} records" : "❌ ${t4.message}"}');
      // Clear bearer vừa set nếu user chưa bấm Lưu
      // (giữ lại để user bấm Lưu sau)
      if (mounted) {
        setState(() => _bearerSource = api.getEffectiveTokenSource());
        _showTestResult(results);
      }
    } catch (e) {
      _snack('Lỗi test: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// v3.0.32: Tạo PDF test nhỏ (~300 bytes)
  Uint8List _makeTestPdf() {
    final pdf = '%PDF-1.4\n'
        '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
        '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
        '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 100 100]>>endobj\n'
        'xref\n0 4\n0000000000 65535 f\n0000000010 00000 n\n0000000053 00000 n\n0000000100 00000 n\n'
        'trailer<</Size 4/Root 1 0 R>>\nstartxref\n149\n%%EOF\n';
    return Uint8List.fromList(pdf.codeUnits);
  }

  int _count(dynamic data) {
    if (data is Map && data['Data'] is List) return (data['Data'] as List).length;
    if (data is List) return data.length;
    return 0;
  }

  void _showTestResult(List<String> results) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.health_and_safety, color: Colors.green),
          SizedBox(width: 8),
          Text('Test Bearer mới'),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: results
                .map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(r, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _presetButton({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1976D2) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? const Color(0xFF1976D2) : Colors.black26,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.white : const Color(0xFF1976D2), size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF1976D2),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _urlField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1976D2)),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
    );
  }
}
