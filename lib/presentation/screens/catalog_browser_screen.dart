// CatalogBrowserScreen v2.38.9 - Duyệt danh mục từ Data Public API
// Dùng chung cho 6 catalog: Thuốc / CLS / Vật tư / Nhăn viên / Khoa-Giường / Thiết bị / ICD / DVKT
// v3.0.96: Credentials lấy từ Credentials (XOR-encoded) - không có plaintext
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:his_mobile/core/security/credentials.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/presentation/screens/department_patients_screen.dart';
import 'package:his_mobile/presentation/screens/icd10_webview_screen.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';

enum CatalogType {
  medicine,    // Thuốc BHYT (4924 items)
  cls,         // Dịch vụ CLS (8393 items)
  supply,      // Vật tư y tế (1142 items)
  staff,       // Nhăn viên y tế (762 items)
  deptBed,     // Khoa - Giường (49 items)
  equipment,   // Thiết bị y tế (1094 items)
  dvkt,        // DVKT Đã dùng (7535 records)
  icd,         // ICD-10 codes
}

extension CatalogTypeX on CatalogType {
  String get title {
    switch (this) {
      case CatalogType.medicine:  return 'Danh mục Thuốc BHYT';
      case CatalogType.cls:       return 'Danh mục CLS';
      case CatalogType.supply:    return 'Danh mục Vật tư';
      case CatalogType.staff:     return 'Danh mục Nhăn viên';
      case CatalogType.deptBed:   return 'Danh mục Khoa - Giường';
      case CatalogType.equipment: return 'Danh mục Thiết bị';
      case CatalogType.dvkt:      return 'DVKT Đã dùng';
      case CatalogType.icd:       return 'ICD-10';
    }
  }
  IconData get icon {
    switch (this) {
      case CatalogType.medicine:  return Icons.medication;
      case CatalogType.cls:       return Icons.medical_services;
      case CatalogType.supply:    return Icons.inventory_2;
      case CatalogType.staff:     return Icons.badge;
      case CatalogType.deptBed:   return Icons.hotel;
      case CatalogType.equipment: return Icons.precision_manufacturing;
      case CatalogType.dvkt:      return Icons.medical_information;
      case CatalogType.icd:       return Icons.assignment;
    }
  }
  Color get color {
    switch (this) {
      case CatalogType.medicine:  return const Color(0xFF7B1FA2);
      case CatalogType.cls:       return const Color(0xFF00838F);
      case CatalogType.supply:    return const Color(0xFFE65100);
      case CatalogType.staff:     return const Color(0xFF1976D2);
      case CatalogType.deptBed:   return const Color(0xFF388E3C);
      case CatalogType.equipment: return const Color(0xFF6A1B9A);
      case CatalogType.dvkt:      return const Color(0xFFD32F2F);
      case CatalogType.icd:       return const Color(0xFF455A64);
    }
  }
  // Tên các trường hiển thị
  List<String> get displayFields {
    switch (this) {
      case CatalogType.medicine:
        return ['ten_thuoc', 'ma_thuoc', 'ten_hoat_chat', 'don_vi_tinh', 'ham_luong', 'duong_dung', 'don_gia'];
      case CatalogType.cls:
        return ['ten_dich_vu', 'ma_dich_vu', 'don_gia', 'quy_trinh', 'cskcb_cls'];
      case CatalogType.supply:
        return ['ten_vat_tu', 'ma_vat_tu', 'nhom_vat_tu', 'don_vi_tinh', 'hang_sx', 'don_gia'];
      case CatalogType.staff:
        return ['ho_ten', 'ma_bhxh', 'ten_khoa', 'macchn', 'ngaycap_cchn'];
      case CatalogType.deptBed:
        return ['ten_khoa', 'ma_khoa', 'ban_kham', 'giuong_pd', 'giuong_hscc'];
      case CatalogType.equipment:
        return ['ten_tb', 'ky_hieu', 'congty_sx', 'nuoc_sx', 'nam_sx', 'ma_may'];
      case CatalogType.dvkt:
        return ['tdl_patient_name', 'tdl_treatment_code', 'tdl_service_name', 'execute_room_name', 'amount', 'price'];
      case CatalogType.icd:
        return ['text', 'id'];
    }
  }
  // Field chính dùng lĂ m title
  String get primaryField {
    switch (this) {
      case CatalogType.medicine:  return 'ten_thuoc';
      case CatalogType.cls:       return 'ten_dich_vu';
      case CatalogType.supply:    return 'ten_vat_tu';
      case CatalogType.staff:     return 'ho_ten';
      case CatalogType.deptBed:   return 'ten_khoa';
      case CatalogType.equipment: return 'ten_tb';
      case CatalogType.dvkt:      return 'tdl_patient_name';
      case CatalogType.icd:       return 'text';
    }
  }
}

class CatalogBrowserScreen extends StatefulWidget {
  final CatalogType type;
  const CatalogBrowserScreen({super.key, required this.type});

  @override
  State<CatalogBrowserScreen> createState() => _CatalogBrowserScreenState();
}

class _CatalogBrowserScreenState extends State<CatalogBrowserScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _start = 0;
  static const int _pageSize = 50;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // v2.98.4: ICD dùng webview riêng - KHÔNG load API local (vì data rỗng)
    if (widget.type != CatalogType.icd) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _start = 0;
    });

    try {
      final auth = ThongkeAuthService.instance;
      // v3.0.96: Credentials từ Credentials (XOR-encoded) - không hardcode
      final email = Credentials.thongkeDefaultEmail;
      final password = Credentials.thongkeDefaultPassword;

      CatalogFetchResult result;
      switch (widget.type) {
        case CatalogType.medicine:
          result = await auth.fetchMedicineCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query, start: 0, length: _pageSize,
          );
          break;
        case CatalogType.cls:
          result = await auth.fetchClsCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query, start: 0, length: _pageSize,
          );
          break;
        case CatalogType.supply:
          result = await auth.fetchMedicalSupplyCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query, start: 0, length: _pageSize,
          );
          break;
        case CatalogType.staff:
          result = await auth.fetchMedicalStaffCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query, start: 0, length: _pageSize,
          );
          break;
        case CatalogType.deptBed:
          result = await auth.fetchDepartmentBedCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query, start: 0, length: _pageSize,
          );
          break;
        case CatalogType.equipment:
          result = await auth.fetchEquipmentCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query, start: 0, length: _pageSize,
          );
          break;
        case CatalogType.dvkt:
          // DVKT default: 30 ngĂ y gần nhất
          final today = DateTime.now();
          final from = today.subtract(const Duration(days: 30));
          String two(int n) => n.toString().padLeft(2, '0');
          String fmt(DateTime dt) => '${dt.year}-${two(dt.month)}-${two(dt.day)}';
          result = await auth.fetchDvktCatalogPublic(
            email: email, password: password,
            dateFrom: fmt(from), dateTo: fmt(today),
            search: _query.isEmpty ? null : _query, start: 0, length: _pageSize,
          );
          break;
        case CatalogType.icd:
          final list = await auth.fetchIcdCodesPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query,
          );
          result = CatalogFetchResult(items: list, total: list.length);
          break;
      }

      if (!mounted) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _error = result.error;
        _loading = false;
        _start = _items.length;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    if (_items.length >= _total) return;
    if (widget.type == CatalogType.icd) return;  // ICD dùng local filter

    setState(() => _loadingMore = true);
    try {
      final auth = ThongkeAuthService.instance;
      // v3.0.96: Credentials từ Credentials (XOR-encoded) - không hardcode
      final email = Credentials.thongkeDefaultEmail;
      final password = Credentials.thongkeDefaultPassword;

      CatalogFetchResult result;
      switch (widget.type) {
        case CatalogType.medicine:
          result = await auth.fetchMedicineCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query,
            start: _start, length: _pageSize,
          );
          break;
        case CatalogType.cls:
          result = await auth.fetchClsCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query,
            start: _start, length: _pageSize,
          );
          break;
        case CatalogType.supply:
          result = await auth.fetchMedicalSupplyCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query,
            start: _start, length: _pageSize,
          );
          break;
        case CatalogType.staff:
          result = await auth.fetchMedicalStaffCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query,
            start: _start, length: _pageSize,
          );
          break;
        case CatalogType.deptBed:
          result = await auth.fetchDepartmentBedCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query,
            start: _start, length: _pageSize,
          );
          break;
        case CatalogType.equipment:
          result = await auth.fetchEquipmentCatalogPublic(
            email: email, password: password,
            search: _query.isEmpty ? null : _query,
            start: _start, length: _pageSize,
          );
          break;
        case CatalogType.dvkt:
          final today = DateTime.now();
          final from = today.subtract(const Duration(days: 30));
          String two(int n) => n.toString().padLeft(2, '0');
          String fmt(DateTime dt) => '${dt.year}-${two(dt.month)}-${two(dt.day)}';
          result = await auth.fetchDvktCatalogPublic(
            email: email, password: password,
            dateFrom: fmt(from), dateTo: fmt(today),
            search: _query.isEmpty ? null : _query,
            start: _start, length: _pageSize,
          );
          break;
        case CatalogType.icd:
          return;
      }

      if (!mounted) return;
      setState(() {
        _items = [..._items, ...result.items];
        _start = _items.length;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onSearch() {
    HapticFeedback.selectionClick();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: type.color,
        foregroundColor: Colors.white,
        title: Text(type.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          // v2.98.4: ICD-10 mở webview tra cứu online
          if (type == CatalogType.icd)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Mở web tra cứu ICD-10',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const Icd10WebViewScreen(allowReturnCode: false),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _searchHint(type),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      suffixIcon: _query.isEmpty ? null : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                          _load();
                        },
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) {
                      setState(() => _query = v);
                      _onSearch();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _onSearch,
                  style: FilledButton.styleFrom(
                    backgroundColor: type.color,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text('Tìm'),
                ),
              ],
            ),
          ),
          // Total + pagination info
          if (_items.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Hiện ${_items.length}/$_total ${_searchHint(type)}',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          // Body
          Expanded(child: _buildBody(type)),
        ],
      ),
    );
  }

  String _searchHint(CatalogType type) {
    switch (type) {
      case CatalogType.medicine:  return 'Tìm theo tên thuốc / hoạt chất / mã';
      case CatalogType.cls:       return 'Tìm theo tên dịch vụ / mã CLS';
      case CatalogType.supply:    return 'Tìm theo tên vật tư / nhóm';
      case CatalogType.staff:     return 'Tìm theo họ tên / mã BHXH';
      case CatalogType.deptBed:   return 'Tìm theo tên khoa / mã';
      case CatalogType.equipment: return 'Tìm theo tên TB / ký hiệu';
      case CatalogType.dvkt:      return 'Tìm theo tên BN / mã ĐT / dịch vụ';
      case CatalogType.icd:       return 'Tìm ICD (vd: A40, viêm phổi)';
    }
  }

  Widget _buildBody(CatalogType type) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              // v3.0.77: Hiển thị thông báo thân thiện hơn
              if (_error == 'No response')
                const Text(
                  'Server không phản hồi.\nVui lòng kiểm tra mạng hoặc VPN.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red, fontSize: 13),
                )
              else
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      // v2.98.4: ICD-10 → mở webview tra cứu thay vì list rỗng
      if (type == CatalogType.icd) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(type.icon, size: 64, color: const Color(0xFF455A64)),
                const SizedBox(height: 16),
                Text(
                  'Tra cứu ICD-10 trực tuyến',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 8),
                Text(
                  'ICD-10 2026 TT06/QĐ1849 (PL1-PL5, thuốc PL3)\nCập nhật từ Bộ Y tế - có 12.000+ mã',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const Icd10WebViewScreen(allowReturnCode: false),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Mở web tra cứu ICD-10'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF455A64),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'https://tracuu-icd10.web.app/',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Chưa có dữ liệu', style: TextStyle(color: Colors.grey.shade600)),
            if (_query.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Thử từ khóa khác', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildItemCard(_items[i], type);
      },
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, CatalogType type) {
    final fields = type.displayFields;
    final primary = (item[type.primaryField] ?? '').toString();
    final primaryFixed = fixVietnameseMojibake(primary);

    Widget cardContent = Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      child: InkWell(
        onTap: () => _showItemDetail(item, type),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(type.icon, size: 16, color: type.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      primaryFixed.isEmpty ? '(không tên)' : primaryFixed,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (type == CatalogType.deptBed) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.swipe_left, size: 14, color: Colors.green),
                    const SizedBox(width: 2),
                    Text(
                      'vuốt → BN',
                      style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
              if (fields.length > 1) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: fields.skip(1).take(4).map((f) {
                    final v = (item[f] ?? '').toString();
                    if (v.isEmpty || v == 'null') return const SizedBox.shrink();
                    final vFixed = fixVietnameseMojibake(v);
                    return Text(
                      '$f: $vFixed',
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // v2.40.2: For deptBed catalog, wrap with swipe-left to view patients
    // Try multiple field names for ID (id, ma_khoa, etc.)
    if (type == CatalogType.deptBed) {
      // Try to parse id from various fields (id might be string or int)
      String idStr = (item['id'] ?? item['ma_khoa'] ?? item['department_id'] ?? '').toString();
      final deptId = int.tryParse(idStr);
      final deptName = (item['ten_khoa'] ?? item['department_name'] ?? '').toString();
      final hasValidId = deptId != null && deptId > 0;

      if (hasValidId) {
        // Standard: swipe-left to open
        return Dismissible(
          key: ValueKey('dept-$deptId-${item.hashCode}'),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Xem BN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              ],
            ),
          ),
          confirmDismiss: (_) async => false,
          onDismissed: (_) {},
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -200) {
                _openDepartmentPatients(deptId, deptName, item);
              }
            },
            child: cardContent,
          ),
        );
      } else {
        // v2.40.2: Fallback - row without valid ID. Tap to show detail (no swipe).
        return cardContent;
      }
    }

    return cardContent;
  }

  /// v2.40.1: Mở mĂ n hình BN cễa 1 khoa khi user vuốt sang trái
  void _openDepartmentPatients(int deptId, String deptName, Map<String, dynamic> item) {
    HapticFeedback.mediumImpact();
    final code = (item['ma_khoa'] ?? item['department_code'] ?? '').toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DepartmentPatientsScreen(
          departmentId: deptId,
          departmentName: deptName,
          departmentCode: code.isEmpty ? null : code,
        ),
      ),
    );
  }

  void _showItemDetail(Map<String, dynamic> item, CatalogType type) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Icon(type.icon, color: type.color, size: 22),
                    const SizedBox(width: 8),
                    Text(type.title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  children: item.entries.map((e) {
                    final v = e.value?.toString() ?? 'null';
                    final vFixed = fixVietnameseMojibake(v);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          SelectableText(
                            vFixed,
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
