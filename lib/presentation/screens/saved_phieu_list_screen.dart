// SavedPhieuListScreen v3.0.0 - Xem tất cả phiếu đã lưu của 1 BN
// Gồm 2 nguồn:
//   1. Local: ClinicalFormsStore (phiếu lưu local trên app)
//   2. EMR: HisProVpnService.getDocuments() (phiếu đã đẩy EMR thật qua HIS Pro)
//
// Phân loại 3 trạng thái (theo BS yêu cầu 14/07/2026):
//   - Lưu local: chỉ lưu app, chưa đẩy EMR
//   - Lưu chưa ký: đã đẩy EMR nhưng IsFinishSign=false (BS ký sau trên HIS Pro)
//   - Lưu ký: đã đẩy EMR + ký số (IsFinishSign=true)
//
// Click từng dòng → mở PDF viewer (nếu local có file) hoặc mở EMR portal (nếu đã đẩy)
import 'package:flutter/material.dart';
import 'package:his_mobile/data/services/clinical_forms_store.dart';
import 'package:his_mobile/data/services/his_pro_vpn_service.dart';
import 'package:his_mobile/presentation/screens/his_webview_screen.dart';
import 'package:his_mobile/presentation/screens/xem_benh_an_screen.dart';
import 'dart:io';

class SavedPhieuListScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  const SavedPhieuListScreen({super.key, required this.patient});

  @override
  State<SavedPhieuListScreen> createState() => _SavedPhieuListScreenState();
}

class _SavedPhieuListScreenState extends State<SavedPhieuListScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<SavedForm> _localForms = [];
  List<HisProDocument> _emrDocuments = [];
  bool _loading = true;
  String? _emrError;

  String get _patientCode => (widget.patient['TDL_PATIENT_CODE'] ??
          widget.patient['tdl_patient_code'] ??
          '')
      .toString();
  String get _treatmentCode => (widget.patient['TDL_TREATMENT_CODE'] ??
          widget.patient['treatment_code'] ??
          '')
      .toString();
  String get _patientName => (widget.patient['TDL_PATIENT_UNSIGNED_NAME'] ??
          widget.patient['TDL_PATIENT_NAME'] ??
          'BN')
      .toString();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _emrError = null;
    });
    // 1. Load local
    try {
      await ClinicalFormsStore.instance.load();
      _localForms = ClinicalFormsStore.instance.byPatient(_patientCode);
    } catch (e) {
      debugPrint('Load local error: $e');
    }
    // 2. Load EMR
    if (_treatmentCode.isNotEmpty) {
      try {
        final docs = await HisProVpnService.instance.getDocuments(_treatmentCode);
        _emrDocuments = docs ?? [];
      } catch (e) {
        _emrError = e.toString();
        debugPrint('Load EMR error: $e');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Phân loại phiếu local theo 3 trạng thái
  List<SavedForm> _localByStatus(String status) {
    if (status == 'local') {
      // Chỉ lưu local (chưa sync)
      return _localForms.where((f) => f.syncStatus == 'local' && !f.signed).toList();
    } else if (status == 'unsigned') {
      // Lưu chưa ký (syncStatus = queued/synced, chưa ký)
      return _localForms.where((f) =>
          (f.syncStatus == 'queued' || f.syncStatus == 'synced') && !f.signed).toList();
    } else {
      // Lưu ký (signed=true)
      return _localForms.where((f) => f.signed).toList();
    }
  }

  /// Phân loại EMR documents theo 3 trạng thái
  List<HisProDocument> _emrByStatus(String status) {
    if (status == 'local') return [];
    if (status == 'unsigned') {
      // EMR có document nhưng chưa ký (IsFinishSign=false)
      return _emrDocuments.where((d) => !d.isSigned).toList();
    } else {
      return _emrDocuments.where((d) => d.isSigned).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Phiếu đã lưu', style: TextStyle(fontSize: 16)),
            Text(
              '$_patientName • MĐT: $_treatmentCode',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1565C0),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: 'Tải lại',
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Lưu local (${_localByStatus("local").length})'),
            Tab(text: 'Lưu chưa ký (${_localByStatus("unsigned").length + _emrByStatus("unsigned").length})'),
            Tab(text: 'Lưu ký (${_localByStatus("signed").length + _emrByStatus("signed").length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildLocalList('local'),
                _buildUnsignedList(),
                _buildSignedList(),
              ],
            ),
    );
  }

  Widget _buildLocalList(String status) {
    final forms = _localByStatus(status);
    if (forms.isEmpty) {
      return _emptyState('Chưa có phiếu lưu local nào', Icons.save_outlined);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: forms.length,
      itemBuilder: (ctx, i) {
        final f = forms[i];
        return _LocalPhieuCard(form: f);
      },
    );
  }

  Widget _buildUnsignedList() {
    final local = _localByStatus('unsigned');
    final emr = _emrByStatus('unsigned');
    if (local.isEmpty && emr.isEmpty) {
      return _emptyState('Chưa có phiếu lưu chưa ký nào', Icons.cloud_upload_outlined);
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (emr.isNotEmpty) ...[
          _sectionLabel('📤 EMR HIS Pro (${emr.length})', Colors.orange.shade700),
          ...emr.map((d) => _EmrPhieuCard(doc: d, status: 'unsigned')),
        ],
        if (local.isNotEmpty) ...[
          _sectionLabel('💾 Local (${local.length})', Colors.indigo),
          ...local.map((f) => _LocalPhieuCard(form: f)),
        ],
      ],
    );
  }

  Widget _buildSignedList() {
    final local = _localByStatus('signed');
    final emr = _emrByStatus('signed');
    if (local.isEmpty && emr.isEmpty) {
      return _emptyState('Chưa có phiếu lưu ký nào', Icons.draw);
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (emr.isNotEmpty) ...[
          _sectionLabel('✅ EMR HIS Pro (${emr.length})', Colors.green.shade700),
          ...emr.map((d) => _EmrPhieuCard(doc: d, status: 'signed')),
        ],
        if (local.isNotEmpty) ...[
          _sectionLabel('💾 Local (${local.length})', Colors.indigo),
          ...local.map((f) => _LocalPhieuCard(form: f)),
        ],
      ],
    );
  }

  Widget _emptyState(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          if (_emrError != null) ...[
            const SizedBox(height: 12),
            Text('Lỗi EMR: $_emrError',
                style: const TextStyle(fontSize: 11, color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

/// Card hiển thị 1 phiếu local
class _LocalPhieuCard extends StatelessWidget {
  final SavedForm form;
  const _LocalPhieuCard({required this.form});

  @override
  Widget build(BuildContext context) {
    final color = form.signed
        ? Colors.green.shade700
        : (form.syncStatus == 'local' ? Colors.indigo : Colors.orange.shade700);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(
            form.signed ? Icons.draw : Icons.save_outlined,
            color: color,
            size: 20,
          ),
        ),
        title: Text('Phiếu ${form.formId}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tạo: ${_fmtDate(form.createdAt)}',
                style: const TextStyle(fontSize: 11)),
            Text('Trạng thái: ${_statusLabel()}',
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
            if (form.signedBy != null)
              Text('Ký bởi: ${form.signedBy}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            if (form.syncError != null)
              Text('Lỗi sync: ${form.syncError}',
                  style: const TextStyle(fontSize: 11, color: Colors.red)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (v) {
            if (v == 'delete') {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Xóa phiếu?'),
                  content: const Text('Xóa vĩnh viễn phiếu này khỏi local.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                    TextButton(
                      onPressed: () async {
                        await ClinicalFormsStore.instance.remove(form.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã xóa phiếu local')),
                          );
                          // Trigger parent refresh
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('Xóa', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'delete', child: Text('Xóa')),
          ],
        ),
        onTap: () {
          // TODO: mở PDF preview nếu có
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Phiếu ${form.formId} - xem chi tiết TODO')),
          );
        },
      ),
    );
  }

  String _statusLabel() {
    if (form.signed) return 'Đã ký';
    if (form.syncStatus == 'local') return 'Lưu local';
    if (form.syncStatus == 'queued') return 'Đang sync...';
    if (form.syncStatus == 'synced') return 'Đã sync EMR (chưa ký)';
    if (form.syncStatus == 'error') return 'Lỗi sync';
    return form.syncStatus;
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year} '
        '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
  }
}

/// Card hiển thị 1 phiếu EMR
class _EmrPhieuCard extends StatelessWidget {
  final HisProDocument doc;
  final String status; // 'unsigned' hoặc 'signed'
  const _EmrPhieuCard({required this.doc, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'signed' ? Colors.green.shade700 : Colors.orange.shade700;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(
            status == 'signed' ? Icons.verified : Icons.cloud_upload,
            color: color,
            size: 20,
          ),
        ),
        title: Text(doc.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${doc.type} • Mã: ${doc.documentCode}',
                style: const TextStyle(fontSize: 11)),
            Text(
              status == 'signed'
                  ? '✅ Đã ký số' + (doc.requestUsername != null ? ' bởi ${doc.requestUsername}' : '')
                  : '⚠ Chưa ký số (BS ký trên HIS Pro)',
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
            ),
            if (doc.documentDate != null)
              Text('Ngày tạo: ${_fmtDate(doc.documentDate!)}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Mở EMR portal để xem PDF
          if (doc.lastVersionUrl != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HisWebviewScreen(
                  customUrl: doc.lastVersionUrl!,
                  screenTitle: doc.name,
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không có URL PDF')),
            );
          }
        },
      ),
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}';
  }
}
