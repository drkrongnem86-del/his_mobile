import 'package:flutter/material.dart';
import 'package:his_mobile/core/theme/app_theme.dart';

class PatientDetailScreen extends StatelessWidget {
  final String patientId;

  const PatientDetailScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông tin bệnh nhân'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient Header Card
            _PatientHeaderCard(),
            const SizedBox(height: 16),
            
            // Basic Info
            _SectionCard(
              title: 'Thông tin cơ bản',
              icon: Icons.person,
              children: [
                _InfoRow('Mã BN', 'BN001234'),
                _InfoRow('Họ tên', 'Nguyễn Văn A'),
                _InfoRow('Giới tính', 'Nam'),
                _InfoRow('Ngày sinh', '15/01/1985'),
                _InfoRow('Tuổi', '41 tuổi'),
                _InfoRow('Điện thoại', '0912 345 678'),
              ],
            ),
            const SizedBox(height: 16),
            
            // Address
            _SectionCard(
              title: 'Địa chỉ',
              icon: Icons.location_on,
              children: [
                _InfoRow('Địa chỉ', '123 Đường ABC, Phường XYZ, Quận 1, TP.HCM'),
              ],
            ),
            const SizedBox(height: 16),
            
            // BHYT Info
            _SectionCard(
              title: 'Thẻ BHYT',
              icon: Icons.badge,
              children: [
                _InfoRow('Số thẻ', 'DN XXXXXXXX'),
                _InfoRow('Mức hưởng', '100%'),
                _InfoRow('Nơi ĐK KCB', 'Bệnh viện Đa khoa tỉnh'),
                _InfoRow('Hạn thẻ', '31/12/2026'),
              ],
            ),
            const SizedBox(height: 16),
            
            // History
            _SectionCard(
              title: 'Lịch sử khám',
              icon: Icons.history,
              children: [
                _HistoryItem(
                  date: '01/07/2026',
                  reason: 'Khám định kỳ',
                  result: 'Bình thường',
                ),
                _HistoryItem(
                  date: '15/06/2026',
                  reason: 'Đau bụng',
                  result: 'Viêm dạ dày',
                ),
                _HistoryItem(
                  date: '20/05/2026',
                  reason: 'Khám tổng quát',
                  result: 'Khỏe tốt',
                ),
              ],
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _BottomActionBar(patientId: patientId),
    );
  }
}

class _PatientHeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white,
            child: Text(
              'A',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nguyễn Văn A',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'BN001234 • Nam • 41 tuổi',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'BHYT 100%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTextStyles.subtitle1.copyWith(
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.body2,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final String date;
  final String reason;
  final String result;

  const _HistoryItem({
    required this.date,
    required this.reason,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              date,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.primaryDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reason, style: AppTextStyles.subtitle2),
                Text(result, style: AppTextStyles.caption),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppTheme.textHint,
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final String patientId;

  const _BottomActionBar({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.history),
              label: const Text('Lịch sử'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () {
                // Start examination
              },
              icon: const Icon(Icons.medical_services),
              label: const Text('Bắt đầu khám'),
            ),
          ),
        ],
      ),
    );
  }
}
