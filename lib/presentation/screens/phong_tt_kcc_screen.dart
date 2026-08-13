// PhongTTKccScreen v3.0.100 - "Phòng TT khoa cấp cứu"
// v3.0.100: Tạo mới theo yêu cầu BS Nem - dạng như desktop HIS
//   - Danh sách BN trong phòng (API getServiceRequests)
//   - Filter tên BN
//   - Card BN hiển thị: Tên, Mã BN, BHYT, Mã ĐT, Mã YL, TT
//   - Bấm BN → bottom sheet 2 tab: Thông tin / ECG (PDF scan)

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/api/y_te_so_service.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// Màn hình Phòng TT khoa cấp cứu
/// v3.0.100: tạo mới theo yêu cầu BS
class PhongTTKccScreen extends StatefulWidget {
  /// Room ID để query BN (mặc định 39 = Phòng Khám Cấp Cứu)
  /// User có thể đổi trong tương lai qua config
  final int roomId;

  /// Tên phòng hiển thị
  final String roomName;

  const PhongTTKccScreen({
    super.key,
    this.roomId = 39, // ROOM_ID_KHAM_CAP_CUU - có thể đổi
    this.roomName = 'Phòng TT Khoa Cấp Cứu',
  });

  @override
  State<PhongTTKccScreen> createState() => _PhongTTKccScreenState();
}

class _PhongTTKccScreenState extends State<PhongTTKccScreen> {
  final HisApiService _api = HisApiService();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _allPatients = [];
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _api.getServiceRequests(
        executeRoomId: widget.roomId,
        limit: 100,
      );

      if (mounted) {
        setState(() {
          if (result.success && result.data is Map) {
            final data = result.data as Map;
            if (data['Success'] == true && data['Data'] is List) {
              _allPatients = List<Map<String, dynamic>>.from(data['Data']);
            } else if (data['Data'] == null) {
              _allPatients = [];
            } else {
              _error = 'Không có dữ liệu';
            }
          } else {
            _error = result.message ?? 'Lỗi kết nối HIS Pro';
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter BN theo tên
    final q = _searchQuery.toLowerCase().trim();
    final filtered = q.isEmpty
        ? _allPatients
        : _allPatients.where((p) {
            final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ??
                    p['TDL_PATIENT_NAME'] ??
                    p['VIR_PATIENT_NAME'] ??
                    '')
                .toString()
                .toLowerCase();
            final code = (p['TDL_PATIENT_CODE'] ?? '').toString().toLowerCase();
            final tcode = (p['TDL_TREATMENT_CODE'] ?? '').toString().toLowerCase();
            return name.contains(q) || code.contains(q) || tcode.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFB71C1C), // đỏ - phòng cấp cứu
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.safePop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.medical_services, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.roomName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('Room ID: ${widget.roomId}',
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'Tải lại'),
        ],
      ),
      body: Column(
        children: [
          // Header gradient
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BỆNH NHÂN TRONG PHÒNG',
                          style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('${filtered.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          Text('/ ${_allPatients.length} ca',
                              style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.people, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),

          // Error banner
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('⚠️ $_error', style: TextStyle(color: Colors.red.shade700, fontSize: 11))),
                ],
              ),
            ),

          // Filter tên BN
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '🔍 Lọc tên BN / mã BN / mã điều trị...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox, size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text('Chưa có bệnh nhân',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(q.isEmpty
                                ? 'Phòng này hiện không có BN'
                                : 'Không tìm thấy BN phù hợp với "$q"',
                                style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) => _buildPatientCard(filtered[i], i),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Card BN - Row API data
  Widget _buildPatientCard(Map<String, dynamic> p, int index) {
    final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ??
            p['TDL_PATIENT_NAME'] ??
            p['VIR_PATIENT_NAME'] ??
            'N/A')
        .toString();
    final code = (p['TDL_PATIENT_CODE'] ?? p['PATIENT_CODE'] ?? '').toString();
    final gender = (p['TDL_PATIENT_GENDER_NAME'] ?? '').toString();
    final dob = p['TDL_PATIENT_DOB'];
    final age = _age(dob);
    final stt = p['SERVICE_REQ_STT_ID'] ?? 1;
    final sttName = stt == 1 ? 'CHỜ' : stt == 2 ? 'ĐANG' : 'XONG';
    final sttColor = stt == 1
        ? Colors.red.shade600
        : stt == 2
            ? Colors.orange.shade600
            : Colors.green.shade600;
    final heinCard = (p['TDL_HEIN_CARD_NUMBER'] ?? '').toString();
    final treatmentCode = (p['TDL_TREATMENT_CODE'] ?? '').toString();
    final serviceCode = (p['SERVICE_REQ_CODE'] ?? '').toString();
    final reqDeptName = (p['REQUEST_DEPARTMENT_NAME'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: sttColor.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showPatientSheet(p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: STT + Tên + trạng thái
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: sttColor, borderRadius: BorderRadius.circular(6)),
                    child: Text('${index + 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Icon(gender.contains('Nữ') ? Icons.female : Icons.male, color: Colors.pink.shade300, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: sttColor, borderRadius: BorderRadius.circular(8)),
                    child: Text(sttName,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Row 2: Mã BN • Giới tính • Tuổi
              Text('$code  •  $gender  •  ${age}Y',
                  style: const TextStyle(color: Colors.black87, fontSize: 12)),
              const SizedBox(height: 8),
              // Row 3: API data
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    if (heinCard.isNotEmpty) _apiRow('BHYT', heinCard, Icons.credit_card),
                    if (treatmentCode.isNotEmpty) _apiRow('Mã ĐT', treatmentCode, Icons.medical_information),
                    if (serviceCode.isNotEmpty) _apiRow('Mã YL', serviceCode, Icons.assignment),
                    if (reqDeptName.isNotEmpty) _apiRow('Khoa YC', reqDeptName, Icons.local_hospital),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _apiRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 11, color: const Color(0xFFB71C1C)),
          const SizedBox(width: 4),
          SizedBox(
            width: 50,
            child: Text('$label:',
                style: const TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  int _age(dynamic dob) {
    if (dob == null) return 0;
    try {
      final y = int.parse(dob.toString().substring(0, 4));
      if (y < 1900 || y > 2100) return 0;
      return DateTime.now().year - y;
    } catch (_) {
      return 0;
    }
  }

  /// Bottom sheet chi tiết BN với 2 tab: Thông tin / ECG
  Future<void> _showPatientSheet(Map<String, dynamic> p) async {
    final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['VIR_PATIENT_NAME'] ?? 'N/A').toString();
    final code = (p['TDL_PATIENT_CODE'] ?? '').toString();
    final treatmentCode = (p['TDL_TREATMENT_CODE'] ?? '').toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  decoration: const BoxDecoration(
                    color: Color(0xFFB71C1C),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('Mã BN: $code', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                if (treatmentCode.isNotEmpty)
                                  Text('Mã ĐT: $treatmentCode', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const TabBar(
                        indicatorColor: Colors.white,
                        indicatorWeight: 2,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white60,
                        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        tabs: [
                          Tab(icon: Icon(Icons.person, size: 16), text: 'Thông tin'),
                          Tab(icon: Icon(Icons.monitor_heart, size: 16), text: 'Điện tim'),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _infoTab(p),
                      _ecgTab(treatmentCode, name),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tab Thông tin - hiển thị chi tiết
  Widget _infoTab(Map<String, dynamic> p) {
    final fields = <MapEntry<String, String>>[
      MapEntry('Mã BN', (p['TDL_PATIENT_CODE'] ?? '').toString()),
      MapEntry('Tên BN', (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? '').toString()),
      MapEntry('Giới tính', (p['TDL_PATIENT_GENDER_NAME'] ?? '').toString()),
      MapEntry('Năm sinh', (p['TDL_PATIENT_DOB'] ?? '').toString()),
      MapEntry('Tuổi', _age(p['TDL_PATIENT_DOB']).toString()),
      MapEntry('BHYT', (p['TDL_HEIN_CARD_NUMBER'] ?? '').toString()),
      MapEntry('Mã điều trị', (p['TDL_TREATMENT_CODE'] ?? '').toString()),
      MapEntry('Mã y lệnh', (p['SERVICE_REQ_CODE'] ?? '').toString()),
      MapEntry('Trạng thái', (p['SERVICE_REQ_STT_ID'] ?? '').toString()),
      MapEntry('Khoa YC', (p['REQUEST_DEPARTMENT_NAME'] ?? '').toString()),
      MapEntry('Phòng YC', (p['REQUEST_ROOM_NAME'] ?? '').toString()),
      MapEntry('Phòng thực hiện', (p['EXECUTE_ROOM_NAME'] ?? '').toString()),
      MapEntry('ICD', (p['ICDS_TEXT'] ?? p['TDL_ICD_CODE'] ?? '').toString()),
      MapEntry('Chẩn đoán', (p['TDL_ICD_NAME'] ?? '').toString()),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: fields.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final f = fields[i];
        if (f.value.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(f.key,
                    style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
              Expanded(
                child: Text(f.value,
                    style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Tab ECG - load danh sách phiếu điện tim từ YTeSo API
  Widget _ecgTab(String treatmentCode, String patientName) {
    if (treatmentCode.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: Colors.black26, size: 64),
              SizedBox(height: 12),
              Text('BN chưa có mã điều trị', style: TextStyle(color: Colors.black54, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return _EcgViewer(treatmentCode: treatmentCode, patientName: patientName);
  }
}

/// Widget load và hiển thị file PDF điện tim từ YTeSo API
class _EcgViewer extends StatefulWidget {
  final String treatmentCode;
  final String patientName;
  const _EcgViewer({required this.treatmentCode, required this.patientName});

  @override
  State<_EcgViewer> createState() => _EcgViewerState();
}

class _EcgViewerState extends State<_EcgViewer> {
  final YTeSoService _yTeSo = YTeSoService();
  bool _loading = true;
  String? _error;
  List<YTeSoDocument> _docs = [];
  String? _loadedDocPath;
  int? _loadedDocId;
  YTeSoDocument? _loadedDoc;
  final PdfViewerController _pdfCtrl = PdfViewerController();

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  @override
  void dispose() {
    _pdfCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _yTeSo.listDocuments(treatmentCode: widget.treatmentCode);
      if (res.success && res.groups != null) {
        // Tìm các doc điện tim (type id 160 hoặc tên chứa "điện tim")
        final all = <YTeSoDocument>[];
        for (final g in res.groups!) {
          final isEcgType = g.id == 160 ||
              g.typeCode == '65' ||
              g.typeName.toLowerCase().contains('điện tim');
          for (final item in g.items) {
            if (isEcgType || item.name.toLowerCase().contains('điện tim')) {
              all.add(item);
            }
          }
        }
        _docs = all;
      } else {
        _error = res.message ?? 'Lỗi tải danh sách';
      }
    } catch (e) {
      _error = e.toString();
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadPdf(YTeSoDocument doc) async {
    setState(() {
      _loading = true;
      _error = null;
      _loadedDocPath = null;
    });

    try {
      // Download file từ YTeSo API (đã save vào temp)
      final res = await _yTeSo.downloadDocument(
        documentId: doc.id,
        treatmentCode: widget.treatmentCode,
      );
      if (!res.success || res.filePath == null) {
        _error = res.message ?? 'Không tải được file';
        return;
      }

      if (mounted) {
        setState(() {
          _loadedDocPath = res.filePath;
          _loadedDocId = doc.id;
          _loadedDoc = doc;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade300, size: 64),
              const SizedBox(height: 12),
              Text('Lỗi: $_error', style: const TextStyle(color: Colors.black54, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadDocs,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loadedDocPath != null) {
      // Đang hiển thị PDF
      return Column(
        children: [
          // Header doc đang xem
          Container(
            color: const Color(0xFFFFF3E0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Color(0xFFD32F2F), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loadedDoc?.name ?? 'Điện tim',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() {
                    _loadedDocPath = null;
                    _loadedDocId = null;
                    _loadedDoc = null;
                  }),
                  tooltip: 'Đóng',
                ),
              ],
            ),
          ),
          Expanded(
            child: SfPdfViewer.file(
              File(_loadedDocPath!),
              controller: _pdfCtrl,
              canShowScrollHead: false,
              canShowScrollStatus: true,
            ),
          ),
        ],
      );
    }

    if (_docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monitor_heart, color: Colors.grey.shade300, size: 80),
              const SizedBox(height: 12),
              const Text('Chưa có phiếu điện tim',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Mã ĐT: ${widget.treatmentCode}',
                  style: const TextStyle(color: Colors.black54, fontSize: 11)),
              const SizedBox(height: 8),
              const Text('(Phiếu điện tim phải được đẩy lên EMR trước)',
                  style: TextStyle(color: Colors.black45, fontSize: 11), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    // List phiếu điện tim
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (ctx, i) {
        final d = _docs[i];
        return Card(
          color: const Color(0xFFFFF3E0),
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.monitor_heart, color: Color(0xFFD32F2F), size: 20),
            ),
            title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.signer.isNotEmpty) Text('👨‍⚕️ ${d.signer}', style: const TextStyle(fontSize: 11)),
                if (d.documentTime.isNotEmpty) Text('🕐 ${_formatDocTime(d.documentTime)}', style: const TextStyle(fontSize: 11)),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () => _loadPdf(d),
          ),
        );
      },
    );
  }

  /// Format yyyyMMddHHmmss → dd/MM/yyyy HH:mm
  String _formatDocTime(String t) {
    if (t.length < 12) return t;
    try {
      return '${t.substring(6, 8)}/${t.substring(4, 6)}/${t.substring(0, 4)} ${t.substring(8, 10)}:${t.substring(10, 12)}';
    } catch (_) {
      return t;
    }
  }
}
