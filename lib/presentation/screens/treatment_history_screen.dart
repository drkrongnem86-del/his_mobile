// v3.0.82: TreatmentHistoryScreen — Lịch sử điều trị (tất cả các lần khám của BN)
// Layout 3-pane giống HIS desktop:
//   ┌────────────────────────────────────────────────┐
//   │ Top: List các lần khám (grid)                  │
//   ├──────────────┬─────────────────────────────────┤
//   │ Bottom-Left  │ Bottom-Right                    │
//   │ Khoa ĐT      │ Dịch vụ + thuốc (tree)         │
//   └──────────────┴─────────────────────────────────┘
//
// v3.0.79: Error handling chuẩn - phân biệt 401/token/timeout/no-data
// v3.0.82: Auto-fetch token từ local proxy (his_proxy_server.py) khi gặp 401
//          - Hiển thị nút "Lấy token tự động" trong banner lỗi
//          - Hiển thị token age (phút/giờ) từ log HIS.exe
//   - 401 → "Paste token" button (mở dialog paste d856... từ log HIS.exe)
//   - Timeout/Connection → "Kiểm tra mạng/VPN"
//   - 0 data → "BN chưa có lần khám nào trên HIS Pro"
// v3.0.93: Đơn giản hóa - bỏ EmrScanApp UI (rườm rà). Chỉ giữ HIS Proxy + manual.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:his_mobile/core/services/vpn_benh_vien_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/api/treatment_history_service.dart';
import 'package:his_mobile/data/services/his_proxy_token_service.dart';

class TreatmentHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> patient;

  const TreatmentHistoryScreen({super.key, required this.patient});

  @override
  State<TreatmentHistoryScreen> createState() => _TreatmentHistoryScreenState();
}

class _TreatmentHistoryScreenState extends State<TreatmentHistoryScreen> {
  final _svc = TreatmentHistoryService.instance;

  String get _patientCode {
    final p = widget.patient;
    return (p['TDL_PATIENT_CODE'] ??
            p['tdl_patient_code'] ??
            p['PATIENT_CODE'] ??
            p['patient_code'] ??
            '')
        .toString();
  }

  String get _patientName {
    final p = widget.patient;
    return (p['TDL_PATIENT_NAME'] ??
            p['TDL_PATIENT_UNSIGNED_NAME'] ??
            p['tdl_patient_name'] ??
            '')
        .toString();
  }

  // === State ===
  bool _loading = false;
  String? _error;
  String? _errorCode; // THistoryErr.*
  List<Map<String, dynamic>> _treatments = [];
  int? _selectedTreatmentId;
  String? _selectedTreatmentCode;
  bool _loadingDept = false;
  List<Map<String, dynamic>> _departments = [];
  int? _selectedDeptTranId;
  bool _loadingSere = false;
  List<Map<String, dynamic>> _sereServs = [];
  // v3.0.90: Token age text (refresh khi navigate back từ Settings)
  String _tokenAgeText = '';

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTokenAge();
  }

  /// v3.0.90: Load lại thông tin token (gọi khi init + sau khi user paste token)
  Future<void> _refreshTokenAge() async {
    final text = await ThongkeAuthService.instance.hisProTokenAgeText();
    final expired = await ThongkeAuthService.instance.isHisProTokenExpired();
    if (!mounted) return;
    setState(() {
      _tokenAgeText = expired && text != 'chưa rõ' ? '⚠️ $text' : text;
    });
  }

  Future<void> _load() async {
    if (_patientCode.isEmpty) {
      setState(() {
        _error = 'Bệnh nhân chưa có mã BN (TDL_PATIENT_CODE)';
        _errorCode = THistoryErr.unknown;
        _treatments = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorCode = null;
      _treatments = [];
      _departments = [];
      _sereServs = [];
      _selectedTreatmentId = null;
      _selectedDeptTranId = null;
    });
    final r = await _svc.getTreatmentHistory(_patientCode);
    if (!mounted) return;
    setState(() {
      _treatments = r.data;
      _loading = false;
      if (!r.isOk) {
        _error = r.errorMessage;
        _errorCode = r.errorCode;
      } else if (r.data.isEmpty) {
        _error = 'Bệnh nhân chưa có lần khám nào trên HIS Pro';
        _errorCode = 'NO_DATA';
      }
    });
  }

  Future<void> _loadDepartments(int treatmentId, String treatmentCode) async {
    setState(() {
      _loadingDept = true;
      _departments = [];
      _sereServs = [];
      _selectedTreatmentId = treatmentId;
      _selectedTreatmentCode = treatmentCode;
      _selectedDeptTranId = null;
    });
    final r = await _svc.getDepartmentTrans(treatmentId);
    if (!mounted) return;
    setState(() {
      _departments = r.data;
      _loadingDept = false;
    });
    if (!r.isOk && r.errorCode != THistoryErr.httpError) {
      _snack(r.errorMessage);
    }
  }

  Future<void> _loadSereServs(int treatmentId, int departmentTranId, int intructionDate) async {
    setState(() {
      _loadingSere = true;
      _sereServs = [];
      _selectedDeptTranId = departmentTranId;
    });
    final r = await _svc.getSereServs(treatmentId, intructionDate: intructionDate);
    if (!mounted) return;
    setState(() {
      _sereServs = r.data;
      _loadingSere = false;
    });
    if (!r.isOk && r.errorCode != THistoryErr.httpError) {
      _snack(r.errorMessage);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _g(Map m, String k) => (m[k] ?? '').toString();

  /// Parse HIS date int (20250908000000) hoặc string → dd/MM/yyyy HH:mm
  String _fmtDate(dynamic v, {bool withTime = true}) {
    if (v == null) return '';
    int ymd = 0;
    if (v is int) {
      ymd = v;
    } else if (v is String) {
      ymd = int.tryParse(v) ?? 0;
    }
    if (ymd <= 0) return v.toString();
    final s = ymd.toString().padLeft(14, '0');
    try {
      final y = s.substring(0, 4);
      final mo = s.substring(4, 6);
      final d = s.substring(6, 8);
      final h = s.substring(8, 10);
      final mi = s.substring(10, 12);
      if (withTime) {
        return '$d/$mo/$y $h:$mi';
      }
      return '$d/$mo/$y';
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử điều trị'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // === HEADER BN ===
          _buildPatientHeader(),
          if (_error != null) _buildErrorBanner(),
          // === TOP: LIST CÁC LẦN KHÁM ===
          Expanded(
            flex: 4,
            child: _buildTreatmentList(),
          ),
          const Divider(height: 1, color: Color(0xFFE0E0E0)),
          // === BOTTOM: KHOA + DỊCH VỤ ===
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Expanded(flex: 4, child: _buildDepartmentList()),
                const VerticalDivider(width: 1, color: Color(0xFFE0E0E0)),
                Expanded(flex: 6, child: _buildSereServList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientHeader() {
    final vpn = VpnBenhVienService.instance;
    final hasVpn = vpn.isConnected;
    final hasToken = ThongkeAuthService.instance.hasHisProToken;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        const Icon(Icons.person, color: Color(0xFF1565C0), size: 20),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _patientName.isEmpty ? 'BN' : _patientName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Mã BN: ${_patientCode.isEmpty ? '—' : _patientCode}'
                '${hasVpn ? ' • 🟢 VPN' : ' • 🔴 No VPN'}'
                '${hasToken ? ' • 🔑 Có token${_tokenAgeText.isNotEmpty ? " (${_tokenAgeText})" : ""}' : ' • 🔒 No token'}',
                style: TextStyle(
                    fontSize: 11,
                    color: hasToken && _tokenAgeText.startsWith('⚠️')
                        ? const Color(0xFFC62828)
                        : const Color(0xFF1565C0)),
              ),
            ],
          ),
        ),
        if (_treatments.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_treatments.length} lần khám',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
      ]),
    );
  }

  /// v3.0.79: Error banner phân biệt các loại lỗi với icon + button phù hợp
  Widget _buildErrorBanner() {
    final isAuth = _errorCode == THistoryErr.tokenExpired || _errorCode == THistoryErr.noToken;
    final isConn = _errorCode == THistoryErr.noConnection || _errorCode == THistoryErr.timeout;
    final isNoData = _errorCode == 'NO_DATA';
    final isUnknown = !isAuth && !isConn && !isNoData;

    Color bg = const Color(0xFFFFE0B2);
    Color border = const Color(0xFFE65100);
    IconData icon = Icons.warning_amber;
    if (isAuth) {
      bg = const Color(0xFFFFCDD2);
      border = const Color(0xFFC62828);
      icon = Icons.lock_outline;
    } else if (isConn) {
      bg = const Color(0xFFFFF9C4);
      border = const Color(0xFFF57F17);
      icon = Icons.wifi_off;
    } else if (isNoData) {
      bg = const Color(0xFFE3F2FD);
      border = const Color(0xFF1565C0);
      icon = Icons.info_outline;
    } else if (isUnknown) {
      bg = const Color(0xFFFFE0B2);
      border = const Color(0xFFE65100);
      icon = Icons.error_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: border, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error!,
                style: TextStyle(color: border, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
              ),
              if (isAuth) ...[
                const SizedBox(height: 2),
                Text(
                  '💡 Vào Cài đặt → EMR Sync → paste token mới (lấy từ log D:\\Soft\\HISPRO_THAT\\Logs\\LogSystem.txt)',
                  style: TextStyle(color: border, fontSize: 10, height: 1.3),
                ),
              ],
              if (isConn) ...[
                const SizedBox(height: 2),
                Text(
                  '💡 Bật VPN BV nội bộ (172.16.9.6) hoặc kết nối WiFi BV',
                  style: TextStyle(color: border, fontSize: 10, height: 1.3),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (isAuth) ...[
          TextButton.icon(
            onPressed: () => _showPasteTokenDialog(),
            icon: const Icon(Icons.vpn_key, size: 16),
            label: const Text('Cập nhật token'),
            style: TextButton.styleFrom(foregroundColor: border, padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Đóng', style: TextStyle(color: border)),
          ),
        ] else
          TextButton(
            onPressed: _loading ? null : _load,
            child: Text('Thử lại', style: TextStyle(color: border)),
          ),
      ]),
    );
  }

  /// v3.0.79: Dialog paste HIS Pro token mới (lấy từ log HIS.exe `___dti:`)
  /// Flow: user mở D:\Soft\HISPRO_THAT\Logs\LogSystem.txt → Ctrl+F "___dti:" →
  /// copy phần TOKEN (64 hex chars giữa 2 dấu | thứ 3 và 4) → paste vào đây
  /// v3.0.82: Thêm nút "Lấy tự động" - gọi proxy server (his_proxy_server.py)
  /// v3.0.93: Bỏ nút EmrScanApp (đơn giản hóa)
  Future<void> _showPasteTokenDialog() async {
    final controller = TextEditingController(
      text: ThongkeAuthService.instance.hisProToken ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.vpn_key, color: Color(0xFFC62828), size: 20),
          SizedBox(width: 8),
          Text('Cập nhật HIS Pro token'),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Token HIS Pro (64 ký tự hex) đã hết hạn. Paste token mới:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            const Text(
              '💡 Cách 1 (tự động): HIS Proxy - đọc log HIS.exe\n'
              '   Chạy: python tools/his_proxy_server.py\n'
              '   trên PC cùng WiFi (cần mở port 9999)\n\n'
              '💡 Cách 2 (thủ công): Mở D:\\Soft\\HISPRO_THAT\\Logs\\LogSystem.txt\n'
              '   Ctrl+F "___dti:" → copy phần giữa dấu | thứ 3 và thứ 4',
              style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '64 ký tự hex (0-9, a-f)',
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => _autoFetchToken(ctx),
            child: const Text('Lấy từ HIS Proxy',
                style: TextStyle(
                    color: Color(0xFF455A64), fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: '1ee41ae967caa75e7c2891a3d9612259d70b4645c67852ab0e5f07546c2f3dfb'));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Đã copy token d856... vào clipboard. Dán vào ô trên.')),
              );
            },
            child: const Text('Copy d856...'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isEmpty || t.length < 60) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Token phải có ít nhất 60 ký tự hex')),
                );
                return;
              }
              Navigator.pop(ctx, t);
            },
            child: const Text('Lưu & Tải lại'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await ThongkeAuthService.instance.setHisProToken(result);
      if (!mounted) return;
      // v3.0.90: Refresh token age display ngay
      await _refreshTokenAge();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Đã lưu token mới')),
      );
      _load();
    }
  }

  /// v3.0.82: Auto-fetch token từ local proxy (his_proxy_server.py)
  /// Returns true nếu thành công, false nếu fail
  Future<bool> _autoFetchToken(BuildContext dialogContext) async {
    final messenger = ScaffoldMessenger.of(dialogContext);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 10),
          Text('Đang gọi proxy server...'),
        ]),
        duration: Duration(seconds: 2),
      ),
    );
    final newToken = await HisProxyTokenService.instance.fetchAndSaveToken();
    if (newToken == null) {
      if (!mounted) return false;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('❌ Không kết nối được proxy. Hãy chạy:\npython tools/his_proxy_server.py\ntrên PC cùng WiFi.'),
          duration: Duration(seconds: 5),
          backgroundColor: Color(0xFFC62828),
        ),
      );
      return false;
    }
    // Đóng dialog paste
    if (dialogContext.mounted) Navigator.pop(dialogContext, newToken);
    if (!mounted) return true;
    // v3.0.90: Refresh token age display
    await _refreshTokenAge();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Đã lấy token tự động từ HIS desktop (${newToken.length} ký tự)'),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 2),
      ),
    );
    _load();
    return true;
  }

  Widget _buildTreatmentList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_treatments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, size: 48, color: Color(0xFFBDBDBD)),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Chưa có dữ liệu',
              style: const TextStyle(color: Color(0xFF757575), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: const Color(0xFFF5F5F5),
          child: const Text(
            '📋 Các lần khám (chạm để xem chi tiết)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF424242)),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _treatments.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
            itemBuilder: (ctx, i) {
              final t = _treatments[i];
              final id = (t['ID'] ?? t['TREATMENT_ID'] ?? 0) as int;
              final code = _g(t, 'TREATMENT_CODE');
              final inTime = _fmtDate(t['IN_TIME'], withTime: false);
              final outTime = _fmtDate(t['OUT_TIME'], withTime: false);
              final icd = _g(t, 'ICD_NAME');
              final icdCode = _g(t, 'ICD_CODE');
              final endType = _g(t, 'TREATMENT_END_TYPE_NAME');
              final isSelected = id == _selectedTreatmentId;
              return InkWell(
                onTap: () => _loadDepartments(id, code),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: isSelected ? const Color(0xFFE3F2FD) : null,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF1565C0) : const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF616161),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(
                                code.isEmpty ? '#$id' : code,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              if (endType.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    endType,
                                    style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 9),
                                  ),
                                ),
                              ],
                            ]),
                            if (icd.isNotEmpty || inTime.isNotEmpty)
                              Text(
                                '${inTime.isEmpty ? '' : 'Vào: $inTime'}${outTime.isEmpty ? '' : '  •  Ra: $outTime'}',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF616161)),
                              ),
                            if (icd.isNotEmpty)
                              Text(
                                '${icdCode.isEmpty ? '' : '[$icdCode] '}$icd',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFFBDBDBD), size: 18),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDepartmentList() {
    if (_selectedTreatmentId == null) {
      return const _EmptyPane(
        icon: Icons.local_hospital,
        text: 'Chọn 1 lần khám ở trên\nđể xem khoa điều trị',
      );
    }
    if (_loadingDept) return const Center(child: CircularProgressIndicator());
    if (_departments.isEmpty) {
      return const _EmptyPane(icon: Icons.local_hospital_outlined, text: 'Không có dữ liệu khoa');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: const Color(0xFFF5F5F5),
          child: Text(
            '🏥 Khoa đã điều trị — ĐT: ${_selectedTreatmentCode ?? ''}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF424242)),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _departments.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
            itemBuilder: (ctx, i) {
              final d = _departments[i];
              final id = (d['ID'] ?? 0) as int;
              final name = _g(d, 'DEPARTMENT_NAME');
              final code = _g(d, 'DEPARTMENT_CODE');
              final inTime = _fmtDate(d['DEPARTMENT_IN_TIME']);
              final prevName = _g(d, 'PREVIOUS_DEPARTMENT_NAME');
              final isSelected = id == _selectedDeptTranId;
              return InkWell(
                onTap: () {
                  // INTRUCTION_DATE = DEPARTMENT_IN_TIME (lấy phần ngày)
                  final dt = d['DEPARTMENT_IN_TIME'] is int ? d['DEPARTMENT_IN_TIME'] as int : 0;
                  final intructionDate = dt > 0 ? (dt ~/ 1000000) * 1000000 : 0;
                  _loadSereServs(_selectedTreatmentId!, id, intructionDate);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: isSelected ? const Color(0xFFE3F2FD) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.local_hospital, size: 14, color: Color(0xFF1565C0)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            name.isEmpty ? code : name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (code.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E0E0),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              code,
                              style: const TextStyle(fontSize: 9, color: Color(0xFF616161)),
                            ),
                          ),
                      ]),
                      if (inTime.isNotEmpty || prevName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 18),
                          child: Text(
                            'Vào: $inTime${prevName.isNotEmpty ? '  (từ $prevName)' : ''}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF616161)),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSereServList() {
    if (_selectedDeptTranId == null) {
      return const _EmptyPane(
        icon: Icons.medication,
        text: 'Chọn 1 khoa bên trái\nđể xem dịch vụ + thuốc',
      );
    }
    if (_loadingSere) return const Center(child: CircularProgressIndicator());
    if (_sereServs.isEmpty) {
      return const _EmptyPane(icon: Icons.medication_outlined, text: 'Khoa này chưa có DV/thuốc');
    }
    // Group by SERVICE_TYPE_NAME
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in _sereServs) {
      final type = _g(s, 'TDL_SERVICE_TYPE_NAME').isEmpty
          ? 'Khác'
          : _g(s, 'TDL_SERVICE_TYPE_NAME');
      groups.putIfAbsent(type, () => []).add(s);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: const Color(0xFFF5F5F5),
          child: Text(
            '💊 Dịch vụ + thuốc — ${_sereServs.length} món',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF424242)),
          ),
        ),
        Expanded(
          child: ListView(
            children: groups.entries.map((e) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                    color: const Color(0xFFE3F2FD),
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        color: Color(0xFF0D47A1),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...e.value.map((s) {
                    final name = _g(s, 'TDL_SERVICE_NAME').isEmpty
                        ? _g(s, 'SERVICE_NAME')
                        : _g(s, 'TDL_SERVICE_NAME');
                    final code = _g(s, 'TDL_SERVICE_CODE');
                    final amount = s['AMOUNT'];
                    final price = s['PRICE'];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(Icons.circle, size: 6, color: Color(0xFF1565C0)),
                      title: Text(
                        name,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: code.isNotEmpty
                          ? Text(
                              code,
                              style: const TextStyle(fontSize: 9, color: Color(0xFF9E9E9E)),
                            )
                          : null,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (amount != null)
                            Text(
                              '×$amount',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0), fontWeight: FontWeight.bold),
                            ),
                          if (price != null)
                            Text(
                              '${(price is num ? price : 0).toStringAsFixed(0)}đ',
                              style: const TextStyle(fontSize: 9, color: Color(0xFF616161)),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _EmptyPane extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyPane({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: const Color(0xFFBDBDBD)),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF757575), fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
