import 'package:flutter/material.dart';
import 'package:his_mobile/core/theme/app_theme.dart';

/// Màn hình cấp cứu - Emergency Module
/// Kết nối trực tiếp với HIS Pro Backend

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo dõi Cấp cứu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {},
          ),
        ],
      ),
      body: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            // Tabs theo mức độ cấp cứu
            Container(
              color: AppTheme.primaryColor,
              child: const TabBar(
                isScrollable: true,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: '🔴 Cấp cứu 1'),
                  Tab(text: '🟠 Cấp cứu 2'),
                  Tab(text: '🟡 Cấp cứu 3'),
                  Tab(text: '🟢 Cấp cứu 4'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _EmergencyLevelList(level: 1),
                  _EmergencyLevelList(level: 2),
                  _EmergencyLevelList(level: 3),
                  _EmergencyLevelList(level: 4),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Tiếp nhận cấp cứu mới
          _showRegisterDialog(context);
        },
        icon: const Icon(Icons.add),
        label: const Text('Tiếp nhận mới'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showRegisterDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _RegisterEmergencySheet(),
    );
  }
}

class _EmergencyLevelList extends StatelessWidget {
  final int level;

  const _EmergencyLevelList({required this.level});

  @override
  Widget build(BuildContext context) {
    // Demo data - sau này sẽ load từ API
    final patients = _getPatients(level);

    if (patients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              'Không có bệnh nhân cấp cứu mức $level',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => await Future.delayed(const Duration(seconds: 1)),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: patients.length,
        itemBuilder: (context, index) {
          final p = patients[index];
          return _EmergencyPatientCard(patient: p);
        },
      ),
    );
  }

  List<_PatientData> _getPatients(int level) {
    // Demo data - sẽ thay bằng API call
    if (level == 1) {
      return [
        _PatientData(
          name: 'Nguyễn Văn A',
          code: 'DT001234',
          age: 45,
          gender: 'Nam',
          diagnosis: 'Nhồi máu cơ tim cấp',
          inTime: DateTime.now().subtract(const Duration(hours: 1)),
          level: 1,
        ),
      ];
    } else if (level == 2) {
      return [
        _PatientData(
          name: 'Trần Thị B',
          code: 'DT001235',
          age: 62,
          gender: 'Nữ',
          diagnosis: 'Đột quỵ não',
          inTime: DateTime.now().subtract(const Duration(hours: 2)),
          level: 2,
        ),
      ];
    }
    return [];
  }
}

class _PatientData {
  final String name;
  final String code;
  final int age;
  final String gender;
  final String diagnosis;
  final DateTime inTime;
  final int level;

  _PatientData({
    required this.name,
    required this.code,
    required this.age,
    required this.gender,
    required this.diagnosis,
    required this.inTime,
    required this.level,
  });
}

class _EmergencyPatientCard extends StatelessWidget {
  final _PatientData patient;

  const _EmergencyPatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // Navigate to detail
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _UrgencyBadge(level: patient.level),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(patient.name, style: AppTextStyles.subtitle1),
                        Text(
                          '${patient.code} • ${patient.age} tuổi • ${patient.gender}',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatTime(patient.inTime),
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  const Icon(Icons.medical_information, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      patient.diagnosis,
                      style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.monitor_heart, size: 16),
                      label: const Text('Theo dõi'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Xử lý'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}p trước';
    if (diff.inHours < 24) return '${diff.inHours}h trước';
    return '${diff.inDays}d trước';
  }
}

class _UrgencyBadge extends StatelessWidget {
  final int level;

  const _UrgencyBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (level) {
      case 1:
        color = Colors.red;
        label = 'Cấp 1';
        break;
      case 2:
        color = Colors.orange;
        label = 'Cấp 2';
        break;
      case 3:
        color = Colors.yellow[700]!;
        label = 'Cấp 3';
        break;
      default:
        color = Colors.green;
        label = 'Cấp 4';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

class _RegisterEmergencySheet extends StatelessWidget {
  const _RegisterEmergencySheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tiếp nhận cấp cứu', style: AppTextStyles.headline3),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Mã bệnh nhân / Số CMND',
              hintText: 'Quét mã hoặc nhập tay',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Quét mã'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.person_add),
                  label: const Text('Bệnh nhân mới'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '⚠️ Lưu ý: Cần kết nối VPN để truy cập dữ liệu HIS Pro',
            style: TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
