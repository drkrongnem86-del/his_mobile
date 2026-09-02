import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/data/patient_dataset.dart' show PatientSeed;
import 'package:his_mobile/presentation/screens/patient_detail_screen.dart';

/// v2.36.2: QR Scanner (tính năng hay từ Y Tế Số)
/// - Scan QR trên thẻ BHYT, wristband BN, mã barcode giường
/// - Auto-extract Mã ĐT (treatment_code) hoặc Mã BN (patient_code)
/// - Tìm trong cache local trước, nếu không có thì query Data API
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
    ],
  );
  bool _processing = false;
  bool _permissionDenied = false;
  String? _lastScan;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isDenied) {
      final result = await Permission.camera.request();
      if (!mounted) return;
      setState(() => _permissionDenied = !result.isGranted);
    } else if (status.isPermanentlyDenied) {
      if (!mounted) return;
      setState(() => _permissionDenied = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    // Tránh scan trùng trong 2s
    if (_lastScan == raw && _lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!).inSeconds < 2) {
      return;
    }
    _lastScan = raw;
    _lastScanTime = DateTime.now();

    setState(() => _processing = true);
    await _controller.stop();

    try {
      final parsed = _parseQr(raw);
      if (parsed == null) {
        _showError('Không nhận diện được QR', 'QR không chứa mã hợp lệ:\n$raw');
        return;
      }

      final type = parsed['type'] as String;
      final code = parsed['code'] as String;

      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Expanded(child: Text('Đang tra cứu BN...')),
            ],
          ),
        ),
      );

      // Tìm BN: ưu tiên cache local (PatientSeed), fallback Data API
      Map<String, dynamic>? patient = _findInSeed(type, code);

      patient ??= await _findInData(type, code);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (patient == null) {
        _showError('Không tìm thấy BN',
            'Mã $type: $code\n\nKhông có trong hệ thống. Vui lòng kiểm tra lại QR hoặc đồng bộ Data.');
        return;
      }

      // Mở patient detail
      if (!mounted) return;
      final p = patient;
      final username = DataService.instance.user?.userName ?? '';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PatientDetailScreen(
            patient: p,
            department: {'name': (p['DEPARTMENT_NAME'] ?? p['department_name'] ?? '').toString()},
            username: username,
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Lỗi', e.toString());
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        await _controller.start();
      }
    }
  }

  /// Parse QR content thành {type, code}
  /// Các dạng QR BV hay dùng:
  ///  - Raw số: "2117335" (treatment_code) hoặc "6002422" (patient_code)
  ///  - URL: "http://.../treatment/2117335"
  ///  - JSON: {"treatment_code":"2117335"}
  Map<String, dynamic>? _parseQr(String raw) {
    final trimmed = raw.trim();
    // Raw số - ưu tiên treatment_code (7-8 số) hơn patient_code (10+ số)
    if (RegExp(r'^\d{6,15}$').hasMatch(trimmed)) {
      if (trimmed.length <= 8) {
        return {'type': 'treatment_code', 'code': trimmed};
      }
      return {'type': 'patient_code', 'code': trimmed};
    }
    // URL
    final urlMatch = RegExp(r'treatment[=:]/(\d+)', caseSensitive: false).firstMatch(trimmed);
    if (urlMatch != null) {
      return {'type': 'treatment_code', 'code': urlMatch.group(1)!};
    }
    final pidMatch = RegExp(r'patient[=:]/(\d+)', caseSensitive: false).firstMatch(trimmed);
    if (pidMatch != null) {
      return {'type': 'patient_code', 'code': pidMatch.group(1)!};
    }
    // JSON
    if (trimmed.startsWith('{')) {
      try {
        final m = <String, String>{};
        for (final p in trimmed.substring(1, trimmed.length - 1).split(',')) {
          final kv = p.split(':');
          if (kv.length == 2) {
            m[kv[0].trim().replaceAll('"', '')] = kv[1].trim().replaceAll('"', '');
          }
        }
        if (m['treatment_code'] != null) return {'type': 'treatment_code', 'code': m['treatment_code'].toString()};
        if (m['patient_code'] != null) return {'type': 'patient_code', 'code': m['patient_code'].toString()};
        if (m['TREATMENT_CODE'] != null) return {'type': 'treatment_code', 'code': m['TREATMENT_CODE'].toString()};
        if (m['PATIENT_CODE'] != null) return {'type': 'patient_code', 'code': m['PATIENT_CODE'].toString()};
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic>? _findInSeed(String type, String code) {
    // PatientSeed.getByDepartment chỉ trả theo khoa - cần tìm tất cả
    final List<Map<String, dynamic>> seeds = [];
    final depts = ['HSCC', 'CCS', 'DTYC', 'DVNTK', 'DVTMCT', 'HSTC', 'NTK', 'NTTN', 'KM', 'NGCT', 'NGTH', 'KN', 'NTM', 'KNTH', 'KPS', 'KTNT', 'PTGMHS', 'KRHM', 'KTMH', 'KTN', 'KYHCT', 'KKB', 'KUB', 'KSNK', 'HSCCL', 'CCSVL', 'DTCCLuu'];
    for (final d in depts) {
      seeds.addAll(PatientSeed.getByDepartment(d));
    }
    for (final p in seeds) {
      if (type == 'treatment_code' && p['TDL_TREATMENT_CODE'] == code) return p;
      if (type == 'patient_code' && p['TDL_PATIENT_CODE'] == code) return p;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _findInData(String type, String code) async {
    // v2.36.2: Data API chưa có endpoint tra cứu BN theo mã ĐT
    // → fallback: báo user vào danh sách khoa để tìm
    return null;
  }

  void _showError(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _processing = false);
              _controller.start();
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Quét lại'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Quét QR BN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Đèn flash',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Đổi camera',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: _permissionDenied
          ? _buildPermissionDenied()
          : Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) => _buildError(error),
                ),
                // Overlay vùng scan
                _buildScanOverlay(),
                // Hướng dẫn
                Positioned(
                  left: 0, right: 0, bottom: 60,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Đưa QR vào khung hình\nHỗ trợ: QR, Barcode BHYT, Mã ĐT',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_processing)
                        const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildScanOverlay() {
    return Center(
      child: Container(
        width: 260, height: 260,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.greenAccent, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Cần quyền truy cập Camera',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Để quét QR, vui lòng cấp quyền Camera cho app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Mở Cài đặt'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(MobileScannerException error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              'Lỗi camera: ${error.errorCode.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _controller.start(),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}