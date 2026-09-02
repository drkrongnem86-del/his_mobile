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
import 'package:his_mobile/data/api/his_api_service.dart';  // v3.0.162: kết quả Xquang
import 'package:his_mobile/data/services/his_proxy_token_service.dart';
import 'package:his_mobile/data/services/auto_token_service.dart';  // v3.0.160: tự cập nhật token
import 'package:his_mobile/data/services/token_sync_service.dart';  // v3.0.165: token hub

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
    // v3.0.160: Tự cập nhật token trước khi load (không cần user paste)
    _autoUpdateTokenThenLoad();
  }

  /// v3.0.165: Tự động lấy token mới rồi load dữ liệu
  /// - Nếu TokenSyncService đã có token còn hạn → load thẳng
  /// - Nếu không có / token hết hạn → gọi autoFetchToken() tự động
  /// - Apply cho TẤT CẢ services (HisApi + HisProApi + Thongke)
  Future<void> _autoUpdateTokenThenLoad() async {
    _refreshTokenAge();
    try {
      // v3.0.165: Dùng TokenSyncService thay vì gọi AutoTokenService trực tiếp
      // TokenSyncService sẽ apply cho HisApi + HisProApi + broadcast
      if (!TokenSyncService.instance.hasToken) {
        debugPrint('🔄 [TreatmentHistory] No cached token, auto-fetching...');
        final event = await TokenSyncService.instance.autoFetchToken(force: false);
        if (event.token != null) {
          // v3.0.165: Apply cho ThongkeAuthService (nếu còn dùng ở đâu đó)
          await ThongkeAuthService.instance.setHisProToken(
            event.token!,
            source: event.source ?? 'auto',
          );
          await ThongkeAuthService.instance.loadHisProToken();
          debugPrint('✅ [TreatmentHistory] Auto-fetched token from ${event.source}');
        } else {
          debugPrint('⚠️ [TreatmentHistory] Auto-fetch failed: ${event.message}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [TreatmentHistory] Auto-update token error: $e');
    }
    if (mounted) _load();
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
              '💡 Cách 1 (tự động): Bấm nút "🔄 Tự lấy token" bên dưới\n'
              '   App sẽ thử login API → renew → hardcoded\n\n'
              '💡 Cách 2 (thủ công): Mở D:\\Nem\\HISPRO_THAT\\Logs\\LogSystem.txt\n'
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
            child: const Text('🔄 Tự lấy token',
                style: TextStyle(
                    color: Color(0xFF1565C0), fontWeight: FontWeight.bold)),
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

  /// v3.0.160: Auto-fetch token từ AutoTokenService (login API → renew → hardcoded)
  /// Returns true nếu thành công, false nếu fail
  Future<bool> _autoFetchToken(BuildContext dialogContext) async {
    final messenger = ScaffoldMessenger.of(dialogContext);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 10),
          Text('Đang tự lấy token...'),
        ]),
        duration: Duration(seconds: 2),
      ),
    );
    final newToken = await HisProxyTokenService.instance.fetchAndSaveToken();
    if (newToken == null) {
      if (!mounted) return false;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('❌ Không lấy được token. Vui lòng paste thủ công.'),
          duration: Duration(seconds: 3),
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
        content: Text('✅ Đã lấy token tự động (${newToken.length} ký tự)'),
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
              // v3.0.161: Trạng thái (Đang khám / Ra viện / Xin về / Chuyển viện)
              final outTimeVal = t['OUT_TIME'];
              final isActive = t['IS_ACTIVE'];
              final isOpen = outTimeVal == null && (isActive == null || isActive == 1 || isActive == 0);
              // isOpen = true → đang khám
              String statusText;
              Color statusColor;
              if (isOpen) {
                statusText = '🟢 Đang khám';
                statusColor = const Color(0xFF2E7D32);
              } else if (endType.isNotEmpty) {
                statusText = '🔵 $endType';
                statusColor = const Color(0xFF1565C0);
              } else {
                statusText = '⚪ Đã đóng';
                statusColor = const Color(0xFF757575);
              }
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
                              if (endType.isNotEmpty || isOpen) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
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
              final outTime = _fmtDate(d['DEPARTMENT_OUT_TIME']);
              final prevName = _g(d, 'PREVIOUS_DEPARTMENT_NAME');
              final nextName = _g(d, 'DEPARTMENT_NAME_AFTER');
              // v3.0.161: Trạng thái khoa - nếu không có outTime là đang ở đây
              final outTimeRaw = d['DEPARTMENT_OUT_TIME'];
              final isCurrentDept = outTimeRaw == null;
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
                      if (inTime.isNotEmpty || prevName.isNotEmpty || outTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 18),
                          child: Text(
                            '${inTime.isEmpty ? '' : 'Vào: $inTime'}${prevName.isNotEmpty ? '  (từ $prevName)' : ''}${outTime.isEmpty ? (nextName.isNotEmpty ? '  •  Qua: $nextName' : '') : '  •  Ra: $outTime'}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF616161)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (isCurrentDept)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 18),
                          child: Row(
                            children: const [
                              Icon(Icons.fiber_manual_record, size: 8, color: Color(0xFF2E7D32)),
                              SizedBox(width: 4),
                              Text(
                                '🟢 Đang điều trị tại khoa này',
                                style: TextStyle(fontSize: 10, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                              ),
                            ],
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

  /// v3.0.164: Show kết quả CLS khi user tap 1 service item (Xquang/Siêu âm/XN/ECG)
  /// Auto-detect service type và gọi API phù hợp:
  /// - type 3 (XN) → LIS
  /// - type 4/5 (CĐHA/Thủ thuật) → SAR / SubclinicalResult / HisSereServExt fallback
  Future<void> _showServiceResult(Map<String, dynamic> s) async {
    final sereServId = s['SERE_SERV_ID'] ?? s['ID'];
    final serviceReqId = s['SERVICE_REQ_ID'] ?? s['TDL_SERVICE_REQ_ID'] ?? s['SERVICE_REQ_ID'];
    final name = s['SERVICE_NAME'] ?? s['TDL_SERVICE_NAME'] ?? 'DV';
    final typeId = s['TDL_SERVICE_TYPE_ID'] ?? s['SERVICE_TYPE_ID'];
    if (sereServId == null && serviceReqId == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final api = HisApiService.instance;
      HisResult r;
      // v3.0.164: Ưu tiên dùng SERVICE_REQ_ID (vì nhiều sere_serv có thể cùng 1 service_req)
      if (serviceReqId != null) {
        r = await api.getServiceResultByType(
          serviceReqId: int.tryParse(serviceReqId.toString()) ?? 0,
          sereServId: sereServId != null ? int.tryParse(sereServId.toString()) : null,
          serviceTypeId: int.tryParse(typeId?.toString() ?? ''),
        );
      } else {
        r = await api.getSereServExtResult(int.tryParse(sereServId.toString()) ?? 0);
      }
      if (!mounted) return;
      Navigator.pop(context); // close loading
      if (!r.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: ${r.message ?? "Không rõ"}')),
        );
        return;
      }
      // Show dialog với kết quả
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(_getServiceTypeIcon(typeId), color: const Color(0xFF1565C0), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kết quả: $name',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: _buildServiceResultContent(r.data, typeId),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: $e')),
        );
      }
    }
  }

  /// v3.0.164: Icon theo loại DV
  IconData _getServiceTypeIcon(dynamic typeId) {
    final t = int.tryParse(typeId?.toString() ?? '') ?? 0;
    switch (t) {
      case 3: return Icons.science; // XN
      case 4: return Icons.medical_services; // CĐHA
      case 5: return Icons.medical_services; // Thủ thuật
      default: return Icons.description;
    }
  }

  /// v3.0.166: Render nội dung kết quả theo service type
  /// - Thêm hiển thị "serviceName" + "source" để user biết đang dùng API nào
  /// - Empty list (results: []) → "Chưa có kết quả" thay vì báo lỗi
  Widget _buildServiceResultContent(dynamic data, dynamic typeId) {
    if (data == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Chưa có kết quả (DV có thể chưa thực hiện hoặc đang chờ kết quả)',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      );
    }
    // Nếu data là wrapper {serviceType, serviceTypeName, source, serviceName, results}
    if (data is Map && data.containsKey('results') && data['serviceTypeName'] != null) {
      final t = data['serviceType'] is int ? data['serviceType'] as int : int.tryParse(data['serviceType'].toString()) ?? 0;
      final source = data['source']?.toString() ?? '';
      final serviceName = data['serviceName']?.toString() ?? '';
      final results = data['results'];
      // v3.0.166: Empty results → "Chưa có kết quả" thay vì báo lỗi "Chưa hỗ trợ loại DV này"
      if (results == null || (results is List && results.isEmpty) || (results is Map && (results['Data'] == null || (results['Data'] is List && (results['Data'] as List).isEmpty)))) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⏳ Chưa có kết quả',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFFFA000)),
              ),
              const SizedBox(height: 6),
              Text(
                'DV này có thể chưa thực hiện hoặc đang chờ kết quả từ khoa CĐHA/XN.',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              if (serviceName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'DV: $serviceName',
                    style: const TextStyle(fontSize: 10, color: Colors.black45, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        );
      }
      // type 3 = XN - dùng format LIS
      if (t == 3) {
        return _buildLabResultContent(results, source);
      }
      // type 4/5 = CĐHA/Thủ thuật - dùng format SAR/Subclinical/HisSereServExt
      return _buildImagingResultContent(results, source);
    }
    // Fallback cũ: list các SereServExt
    if (data is List) {
      if (data.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '⏳ Chưa có kết quả',
            style: TextStyle(fontSize: 13, color: Color(0xFFFFA000)),
          ),
        );
      }
      return _buildImagingResultContent({'Data': data}, '');
    }
    // Single result map
    if (data is Map) {
      return _buildImagingResultContent(data, '');
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        '⏳ Chưa có kết quả',
        style: TextStyle(fontSize: 13, color: Color(0xFFFFA000)),
      ),
    );
  }

  /// v3.0.164: Hiển thị kết quả CĐHA (Siêu âm/Xquang) - format giống HIS Desktop
  Widget _buildImagingResultContent(dynamic data, String source) {
    List<dynamic> results = [];
    if (data is Map && data['Data'] is List) {
      results = data['Data'] as List;
    } else if (data is Map && data['Data'] is Map) {
      results = [data['Data']];
    } else if (data is List) {
      results = data;
    }
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Chưa có kết quả', style: TextStyle(fontSize: 12, color: Colors.black54)),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: results.map<Widget>((item) {
        Map? ext;
        Map? ss;
        if (item is Map) {
          // Nếu wrapped trong {SERE_SERV_EXT, SERE_SERV} (từ getServiceReqResult cũ)
          ext = item['SERE_SERV_EXT'] as Map?;
          ss = item['SERE_SERV'] as Map?;
          // Nếu là SAR result trực tiếp
          if (ext == null) {
            ext = item;
          }
        }
        if (ext == null) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Không có dữ liệu mở rộng', style: TextStyle(fontSize: 11)),
          );
        }
        final conclude = ext['CONCLUDE']?.toString() ?? '';
        final description = ext['DESCRIPTION']?.toString() ?? '';
        final machineCode = ext['MACHINE_CODE']?.toString() ?? '';
        final note = ext['NOTE']?.toString() ?? '';
        final numFilm = ext['NUMBER_OF_FILM'];
        final beginTime = ext['BEGIN_TIME'];
        final endTime = ext['END_TIME'];
        final subclinicalNurse = ext['SUBCLINICAL_NURSE_USERNAME']?.toString() ?? '';
        final subclinicalResult = ext['SUBCLINICAL_RESULT_USERNAME']?.toString() ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (conclude.isNotEmpty) ...[
                const Text('🩺 KẾT LUẬN:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                const SizedBox(height: 2),
                Text(conclude, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
              ],
              if (description.isNotEmpty) ...[
                const Text('📝 MÔ TẢ:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
              ],
              if (note.isNotEmpty) ...[
                const Text('📌 GHI CHÚ:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                const SizedBox(height: 2),
                Text(note, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  if (machineCode.isNotEmpty)
                    Expanded(
                      child: Text('Máy: $machineCode', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    ),
                  if (numFilm != null && numFilm is num && numFilm > 0)
                    Text('Số film: $numFilm', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ],
              ),
              if (beginTime != null || endTime != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '⏱ ${beginTime ?? '?'} → ${endTime ?? '?'}',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ),
              if (subclinicalNurse.isNotEmpty || subclinicalResult.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '👤 ${subclinicalNurse.isNotEmpty ? "KTV: $subclinicalNurse" : ""}${subclinicalResult.isNotEmpty ? "  •  BS đọc: $subclinicalResult" : ""}',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ),
              if (ss != null && (ss['SERVICE_REQ_CODE'] != null))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Mã YL: ${ss['SERVICE_REQ_CODE']}',
                    style: const TextStyle(fontSize: 9, color: Colors.black45),
                  ),
                ),
              if (source.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Nguồn: $source',
                    style: const TextStyle(fontSize: 9, color: Colors.black45, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// v3.0.164: Hiển thị kết quả Xét nghiệm - format giống HIS Desktop
  /// (Mã XN, Tên chỉ số, Kết quả, Đơn vị, Bình thường, H/L cảnh báo)
  Widget _buildLabResultContent(dynamic data, String source) {
    List<dynamic> results = [];
    if (data is Map && data['Data'] is List) {
      results = data['Data'] as List;
    } else if (data is List) {
      results = data;
    } else if (data is Map && data['Data'] is Map) {
      results = [data['Data']];
    }
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Chưa có kết quả XN', style: TextStyle(fontSize: 12, color: Colors.black54)),
      );
    }
    // Tìm các field cho kết quả XN - thường là: TEST_CODE, TEST_NAME, VALUE, UNIT, NORMAL_RANGE, ALERT
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Nguồn: $source', style: const TextStyle(fontSize: 9, color: Colors.black45)),
          ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: const Color(0xFF1565C0),
                child: const Row(children: [
                  Expanded(flex: 2, child: Text('Mã', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))),
                  Expanded(flex: 5, child: Text('Chỉ số', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text('KQ', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                  Expanded(flex: 2, child: Text('Đơn vị', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))),
                  Expanded(flex: 3, child: Text('Bình thường', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                ]),
              ),
              ...results.asMap().entries.map((e) {
                final item = e.value;
                if (item is! Map) return const SizedBox.shrink();
                final code = (item['TEST_CODE'] ?? item['SHORT_NAME'] ?? item['MA_XN'] ?? '').toString();
                final testName = (item['TEST_NAME'] ?? item['SERVICE_NAME'] ?? item['TEN_CHI_SO'] ?? code).toString();
                final value = (item['VALUE'] ?? item['RESULT'] ?? item['KET_QUA'] ?? '').toString();
                final unit = (item['UNIT'] ?? item['UNIT_NAME'] ?? item['DON_VI'] ?? '').toString();
                final normalRange = (item['NORMAL_RANGE'] ?? item['REF_RANGE'] ?? item['GIA_TRI_BT'] ?? '').toString();
                // alert: H (high) / L (low) / HL
                final alert = (item['ALERT'] ?? item['IS_HIGH'] == true ? 'H' : (item['IS_LOW'] == true ? 'L' : '')).toString();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  color: e.value % 2 == 0 ? Colors.white : const Color(0xFFF5F5F5),
                  child: Row(children: [
                    Expanded(flex: 2, child: Text(code, style: const TextStyle(fontSize: 9, color: Color(0xFF6A1B9A)))),
                    Expanded(flex: 5, child: Text(testName, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (alert == 'H' || alert == 'HL')
                            const Padding(padding: EdgeInsets.only(right: 2), child: Text('H', style: TextStyle(fontSize: 9, color: Color(0xFFD32F2F), fontWeight: FontWeight.bold))),
                          if (alert == 'L' || alert == 'HL')
                            const Padding(padding: EdgeInsets.only(right: 2), child: Text('L', style: TextStyle(fontSize: 9, color: Color(0xFF1976D2), fontWeight: FontWeight.bold))),
                          Flexible(child: Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                    Expanded(flex: 2, child: Text(unit, style: const TextStyle(fontSize: 9, color: Colors.black54), overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 3, child: Text(normalRange, style: const TextStyle(fontSize: 9, color: Colors.black54), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
                  ]),
                );
              }),
            ],
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
    // v3.0.161: HIS Pro GetDHisSereServ2 returns fields without TDL_ prefix
    // Real fields: SERVICE_CODE, SERVICE_NAME, TDL_SERVICE_TYPE_ID, AMOUNT, PRICE,
    //               TUTORIAL (instruction note), REQUEST_DEPARTMENT_NAME, etc.
    // Group by TDL_SERVICE_TYPE_ID → map to name
    final typeName = <int, String>{
      1: 'Khám', 2: 'Ngừng', 3: 'Xét nghiệm', 4: 'CĐHA', 5: 'Thủ thuật',
      6: 'Thuốc', 7: 'Máu', 8: 'Vật tư', 9: 'Giường', 10: 'Phẫu thuật',
      11: 'Khám ngoại trú', 14: 'Thuốc (YTế Số)', 15: 'CLS', 16: 'Phẫu thuật (PTTT)',
    };
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in _sereServs) {
      final typeId = s['TDL_SERVICE_TYPE_ID'];
      final type = typeName[typeId is int ? typeId : (typeId is num ? typeId.toInt() : -1)] ?? 'Khác (loại $typeId)';
      groups.putIfAbsent(type, () => []).add(s);
    }
    // Sort groups: Thuốc/CLS/Thủ thuật trước
    final order = ['Khám', 'CĐHA', 'Xét nghiệm', 'Thủ thuật', 'Phẫu thuật (PTTT)', 'Thuốc', 'Vật tư', 'Máu', 'Giường', 'CLS', 'Khác'];
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        return (ia < 0 ? 999 : ia).compareTo(ib < 0 ? 999 : ib);
      });
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
            children: sortedKeys.map((k) {
              final e = MapEntry(k, groups[k]!);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                    color: const Color(0xFFE3F2FD),
                    child: Row(
                      children: [
                        Text(
                          '${e.key}',
                          style: const TextStyle(
                            color: Color(0xFF0D47A1),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${e.value.length} món',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF1565C0)),
                        ),
                      ],
                    ),
                  ),
                  ...e.value.map((s) {
                    // v3.0.161: Field names from HIS Pro GetDHisSereServ2
                    final name = _g(s, 'SERVICE_NAME');
                    final code = _g(s, 'SERVICE_CODE');
                    final amount = s['AMOUNT'];
                    final price = s['PRICE'];
                    final unit = _g(s, 'SERVICE_UNIT_NAME');
                    final tutorial = _g(s, 'TUTORIAL');
                    final reqDept = _g(s, 'REQUEST_DEPARTMENT_NAME');
                    final reqUser = _g(s, 'REQUEST_USERNAME');
                    final sttId = s['SERVICE_REQ_STT_ID'];
                    // Stt: 1=mới, 2=đang xử lý, 3=đang thực hiện, 4-6=hoàn thành
                    final sttColor = sttId == null || sttId <= 2
                        ? const Color(0xFFD32F2F)
                        : sttId == 3
                            ? const Color(0xFFFFA000)
                            : const Color(0xFF2E7D32);
                    final sttText = sttId == null || sttId <= 2
                        ? 'Mới'
                        : sttId == 3
                            ? 'Đang làm'
                            : 'Xong';
                    return InkWell(
                      onTap: () => _showServiceResult(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty ? code : name,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (code.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 1),
                                        child: Text(
                                          '$code${unit.isNotEmpty ? ' • $unit' : ''}',
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (amount != null)
                                    Text(
                                      '×$amount',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0), fontWeight: FontWeight.bold),
                                    ),
                                  if (price != null && (price is num) && price > 0)
                                    Text(
                                      '${(price is num ? price : 0).toStringAsFixed(0)}đ',
                                      style: const TextStyle(fontSize: 9, color: Color(0xFF616161)),
                                    ),
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: sttColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      sttText,
                                      style: TextStyle(fontSize: 9, color: sttColor, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (tutorial.isNotEmpty || reqDept.isNotEmpty || reqUser.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (reqDept.isNotEmpty) 'YC: $reqDept',
                                if (reqUser.isNotEmpty) '• BS: $reqUser',
                                if (tutorial.isNotEmpty) '• $tutorial',
                              ].join(' '),
                              style: const TextStyle(fontSize: 9, color: Color(0xFF757575), fontStyle: FontStyle.italic),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                  })
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
