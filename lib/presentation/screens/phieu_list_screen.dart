import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/data/models/phieu.dart';
import 'package:his_mobile/data/models/phieu_catalog.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';
import 'phieu_form_screen.dart';

/// Màn hình danh sách các loại phiếu y tế
class PhieuListScreen extends StatelessWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;

  const PhieuListScreen({
    super.key,
    required this.patient,
    required this.department,
  });

  String get _patientName {
    String _g(String k1, [String? k2, String? k3]) =>
        (patient[k1] ?? patient[k2 ?? ''] ?? patient[k3 ?? ''] ?? '').toString();
    return _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME');
  }

  String get _treatmentCode {
    String _g(String k1, [String? k2, String? k3]) =>
        (patient[k1] ?? patient[k2 ?? ''] ?? patient[k3 ?? ''] ?? '').toString();
    final c = _g('TDL_TREATMENT_CODE', 'treatment_code');
    return c.isNotEmpty ? c : _g('TDL_PATIENT_CODE', 'tdl_patient_code');
  }

  @override
  Widget build(BuildContext context) {
    final grouped = PhieuCatalog.groupedByCategory();
    final hasPatient = _patientName.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        title: const Text('Lập phiếu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(compact: true, department: department['name']?.toString()),
          // Header BN
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _patientName.isEmpty ? '?' : _patientName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPatient ? _patientName : 'Chưa chọn bệnh nhân',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _treatmentCode.isEmpty ? 'Mã ĐT: chưa có' : 'Mã ĐT: $_treatmentCode',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Cảnh báo nếu chưa có BN
          if (!hasPatient)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Vui lòng chọn bệnh nhân trước khi lập phiếu',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          // Phiếu list theo category
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: grouped.entries.map((entry) {
                return _buildCategorySection(context, entry.key, entry.value, hasPatient);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(BuildContext context, PhieuCategory cat, List<Phieu> phieus, bool hasPatient) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              Icon(cat.icon, size: 16, color: Colors.indigo),
              const SizedBox(width: 6),
              Text(
                cat.label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.indigo,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('${phieus.length}', style: TextStyle(color: Colors.indigo.shade700, fontSize: 10)),
              ),
            ],
          ),
        ),
        // Grid 2 cols
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: phieus.length,
          itemBuilder: (ctx, i) {
            return _buildPhieuTile(ctx, phieus[i], hasPatient);
          },
        ),
      ],
    );
  }

  Widget _buildPhieuTile(BuildContext context, Phieu p, bool hasPatient) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: hasPatient
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhieuFormScreen(
                    phieu: p,
                    patient: patient,
                    department: department,
                  ),
                ),
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hasPatient ? Colors.white : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.color.withOpacity(0.4), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: p.color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Icon(p.icon, color: p.color, size: 16),
                ),
                const Spacer(),
                if (p.canSignEmr)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_note, size: 10, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text('Ký', style: TextStyle(fontSize: 9, color: Colors.amber.shade900, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text('Lưu', style: TextStyle(fontSize: 9, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              p.name,
              style: TextStyle(
                color: hasPatient ? Colors.black87 : Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              p.description,
              style: TextStyle(color: hasPatient ? Colors.black54 : Colors.black38, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3)),
                  child: Text(
                    p.code,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                if (hasPatient)
                  Icon(Icons.arrow_forward_ios, size: 10, color: Colors.grey.shade400),
              ],
            ),
          ],
        ),
      ),
    );
  }
}