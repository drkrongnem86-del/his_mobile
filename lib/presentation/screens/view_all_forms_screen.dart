// ViewAllFormsScreen - màn hình "Xem tất cả phiếu của BN" y như Y Tế Số:
// - Timeline view tất cả phiếu đã ghi cho BN, sắp xếp MỚI NHẤT
// - Filter chip theo clinical note type
// - Tap để xem chi tiết từng phiếu
// - Group header theo ngày (Hôm nay / Hôm qua / dd/MM/yyyy)
// - Pull-to-refresh
// - Empty state với CTA "Tạo phiếu đầu tiên"
import 'package:flutter/material.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/local/clinical_notes_service.dart';
import 'package:his_mobile/presentation/widgets/clinical_note_screen.dart';
import 'package:his_mobile/presentation/widgets/patient_header.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class ViewAllFormsScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;

  const ViewAllFormsScreen({
    super.key,
    required this.patient,
    required this.department,
  });

  @override
  State<ViewAllFormsScreen> createState() => _ViewAllFormsScreenState();
}

class _ViewAllFormsScreenState extends State<ViewAllFormsScreen> {
  final _notes = ClinicalNotesService.instance;
  final _auth = ThongkeAuthService();

  final Map<ClinicalNoteType, bool> _filterTypes = {};
  List<ClinicalNote> _allNotes = [];
  bool _loading = true;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  String _g(String k1, [String? k2, String? k3]) =>
      (widget.patient[k1] ?? widget.patient[k2 ?? ''] ?? widget.patient[k3 ?? ''] ?? '').toString();

  String get _patientCode {
    final c = _g('TDL_TREATMENT_CODE', 'treatment_code');
    if (c.isNotEmpty) return c;
    return _g('TDL_PATIENT_CODE', 'tdl_patient_code');
  }

  String get _patientName => _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME');

  String get _createdBy => _auth.currentUsername ?? 'admin';

  @override
  void initState() {
    super.initState();
    // All filter on by default
    for (final t in ClinicalNoteType.values) {
      _filterTypes[t] = true;
    }
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _notes.getNotesForPatient(_createdBy, _patientCode);
    if (mounted) setState(() {
      _allNotes = list;
      _loading = false;
    });
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
  }

  String _formatDayHeader(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final noteDay = DateTime(t.year, t.month, t.day);
    String two(int n) => n.toString().padLeft(2, '0');
    if (noteDay == today) return '🕐 HÔM NAY  •  ${two(t.hour)}:${two(t.minute)}';
    if (noteDay == yesterday) return 'HÔM QUA  •  ${two(t.day)}/${two(t.month)}';
    return '${two(t.day)}/${two(t.month)}/${t.year}';
  }

  /// Lấy giá trị hiển thị ngắn gọn (80 chars) từ data map
  String _preview(ClinicalNote n) {
    final entries = n.data.entries.where((e) {
      final v = e.value;
      if (v == null) return false;
      if (v is String && v.trim().isEmpty) return false;
      if (v is List && v.isEmpty) return false;
      return true;
    }).take(3);
    final buffer = StringBuffer();
    for (final e in entries) {
      final v = e.value;
      String val;
      if (v is List) {
        val = v.join(', ');
      } else {
        val = v.toString();
      }
      final keyHuman = _humanKey(e.key);
      buffer.writeln('• $keyHuman: ${val.length > 60 ? val.substring(0, 60) : val}');
    }
    return buffer.toString().trim();
  }

  String _humanKey(String key) {
    const map = {
      'tenthuoc': 'Tên thuốc', 'soluong': 'SL', 'tomtat': 'Tóm tắt',
      'chandoan': 'Chẩn đoán', 'huongdieutri': 'Hướng ĐT',
      'mach': 'Mạch', 'huyetap_tamthu': 'HA tâm thu', 'huyetap_tamtruong': 'HA tâm trương',
      'nhietdo': 'NĐ', 'spo2': 'SpO2', 'nhiptho': 'NT',
      'lydo': 'Lý do', 'ketqua': 'Kết quả', 'nguon_thong_tin': 'Nguồn',
    };
    return map[key] ?? key;
  }

  /// Group notes by date
  Map<DateTime, List<ClinicalNote>> _groupByDate(List<ClinicalNote> notes) {
    final grouped = <DateTime, List<ClinicalNote>>{};
    for (final n in notes) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      grouped.putIfAbsent(d, () => []).add(n);
    }
    // Sort dates DESC
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in keys) k: grouped[k]!};
  }

  /// Card hiển thị 1 note trong timeline
  Widget _noteCard(ClinicalNote n) {
    final accent = Color(n.type.colorValue);
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openNote(n),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time rail
                Column(
                  children: [
                    Container(
                      width: 38,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${n.createdAt.hour.toString().padLeft(2, '0')}:${n.createdAt.minute.toString().padLeft(2, '0')}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 2,
                      height: 30,
                      color: accent.withOpacity(0.4),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(n.type.icon, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              n.type.label,
                              style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text('${n.createdBy.substring(0, n.createdBy.length > 8 ? 8 : n.createdBy.length)}',
                              style: const TextStyle(color: Colors.black38, fontSize: 9)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (_preview(n).isNotEmpty)
                        Text(
                          _preview(n),
                          style: const TextStyle(color: Colors.black87, fontSize: 11, height: 1.3),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (n.note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.shade100),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.sticky_note_2, size: 11, color: Colors.amber),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    n.note,
                                    style: const TextStyle(color: Colors.black87, fontSize: 10, fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Icon xem chi tiết
                Icon(Icons.chevron_right, color: Colors.black26, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openNote(ClinicalNote n) {
    // Mở ClinicalNoteScreen ở chế độ xem (không cho save) - dùng dialog đơn giản
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(n.type.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Expanded(child: Text(n.type.label, style: TextStyle(color: Color(n.type.colorValue), fontSize: 15))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatTime(n.createdAt),
                  style: const TextStyle(color: Colors.black54, fontSize: 11, fontStyle: FontStyle.italic)),
              const Divider(height: 16),
              ...n.data.entries.where((e) {
                final v = e.value;
                if (v == null) return false;
                if (v is String && v.trim().isEmpty) return false;
                if (v is List && v.isEmpty) return false;
                return true;
              }).map((e) {
                final v = e.value;
                final val = v is List ? v.join(', ') : v.toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text('${_humanKey(e.key)}:',
                            style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text(val, style: const TextStyle(color: Colors.black, fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }),
              if (n.note.isNotEmpty) ...[
                const Divider(),
                Text('Ghi chú: ${n.note}',
                    style: const TextStyle(color: Colors.black87, fontSize: 12, fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Mở phiếu mới cùng loại
              Navigator.push(context, MaterialPageRoute(builder: (_) =>
                ClinicalNoteScreen(
                  type: n.type,
                  patient: widget.patient,
                  department: widget.department,
                  fields: const [],  // Empty - user sẽ thấy form rỗng cho loại này
                ),
              )).then((_) => _load());
            },
            child: const Text('Tạo phiếu mới cùng loại'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    final activeTypes = ClinicalNoteType.values
        .where((t) => _allNotes.any((n) => n.type == t))
        .toList();
    if (activeTypes.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        border: Border(bottom: BorderSide(color: Color(0xFFE0E5F0))),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: const Text('Tất cả', style: TextStyle(fontSize: 11)),
              selected: _filterTypes.values.every((v) => v) || _filterTypes.values.where((v) => v).length == activeTypes.length,
              onSelected: (v) => setState(() {
                for (final t in activeTypes) {
                  _filterTypes[t] = v;
                }
              }),
              backgroundColor: Colors.white,
              selectedColor: Colors.indigo,
              checkmarkColor: Colors.white,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            for (final t in activeTypes) ...[
              const SizedBox(width: 4),
              FilterChip(
                label: Text('${t.icon} ${t.label}', style: const TextStyle(fontSize: 10)),
                selected: _filterTypes[t] ?? false,
                onSelected: (v) => setState(() => _filterTypes[t] = v),
                backgroundColor: Colors.white,
                selectedColor: Color(t.colorValue),
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  fontSize: 10,
                  color: (_filterTypes[t] ?? false) ? Colors.white : Colors.black87,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              'Chưa có phiếu nào của BN $_patientName',
              style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Mở [Thao tác] ở menu BN → chọn tác vụ → Lưu phiếu.\nTất cả phiếu sẽ hiện ở đây.',
              style: TextStyle(color: Colors.black54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Text(
                '${ClinicalNoteType.values.length} loại phiếu có sẵn trên app',
                style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: Colors.black, fontSize: 13),
        cursorColor: Colors.indigo,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          hintText: 'Tìm trong các phiếu (tên thuốc, Mã ICD, nội dung...)',
          hintStyle: const TextStyle(color: Colors.black45, fontSize: 12),
          prefixIcon: const Icon(Icons.search, color: Colors.indigo, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: Colors.black54),
                  onPressed: () => setState(() {
                    _searchQuery = '';
                    _searchCtrl.clear();
                  }),
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFE3F2FD),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.indigo, width: 1.5),
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
      ),
    );
  }

  bool _matchSearch(ClinicalNote n) {
    if (_searchQuery.isEmpty) return true;
    // Search in display name + note + data values
    final fields = [
      n.patientName,
      n.departmentName,
      n.note,
      ...n.data.values.map((v) => v is List ? v.join(' ') : v.toString()),
    ];
    return fields.any((f) => matchesVietnamese(f.toString(), _searchQuery));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allNotes
        .where((n) => (_filterTypes[n.type] ?? false) && _matchSearch(n))
        .toList();
    final grouped = _groupByDate(filtered);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Text('📋 Tất cả phiếu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
              child: Text('${filtered.length}/${_allNotes.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Làm mới'),
        ],
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(department: widget.department['name']?.toString()),
          PatientHeader(patient: widget.patient, department: widget.department, accent: Colors.indigo),
          _searchBar(),
          _filterChips(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _allNotes.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            for (final entry in grouped.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _formatDayHeader(entry.key.add(const Duration(hours: 12))),
                                        style: TextStyle(
                                          color: Colors.indigo.shade900,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        height: 1,
                                        color: Colors.indigo.shade100,
                                      ),
                                    ),
                                    Text('${entry.value.length} phiếu',
                                        style: const TextStyle(color: Colors.black45, fontSize: 10)),
                                  ],
                                ),
                              ),
                              for (final n in entry.value) _noteCard(n),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
