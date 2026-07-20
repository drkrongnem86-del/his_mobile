import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:his_mobile/core/theme/app_theme.dart';
import 'package:his_mobile/modules/auth/presentation/blocs/auth_bloc.dart';
import 'package:his_mobile/modules/auth/data/user_model.dart';

class PrescriptionScreen extends StatelessWidget {
  final String treatmentId;

  const PrescriptionScreen({super.key, required this.treatmentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kê đơn thuốc'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _savePrescription(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient Info
            _PatientInfoCard(),
            const SizedBox(height: 16),

            // Medicine List
            _SectionTitle('Danh sách thuốc'),
            _MedicineList(),
            const SizedBox(height: 16),

            // Add Medicine Button
            OutlinedButton.icon(
              onPressed: () => _showAddMedicineDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Thêm thuốc'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 16),

            // Usage Instructions
            _SectionTitle('Hướng dẫn sử dụng'),
            TextFormField(
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Nhập hướng dẫn sử dụng...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            // Note
            _SectionTitle('Ghi chú'),
            TextFormField(
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Nhập ghi chú...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),

            // Summary
            _SummaryCard(),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(),
    );
  }

  void _savePrescription(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu đơn thuốc')),
    );
  }

  void _showAddMedicineDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _AddMedicineSheet(),
    );
  }
}

class _PatientInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primaryColor,
            child: const Text('A', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nguyễn Văn A', style: AppTextStyles.subtitle1),
                Text('BN001234 • Nam • 41 tuổi', style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: AppTextStyles.subtitle1),
    );
  }
}

class _Medicine {
  final String name;
  final String dosage;
  final int quantity;
  final String unit;
  final String usage;

  _Medicine({
    required this.name,
    required this.dosage,
    required this.quantity,
    required this.unit,
    required this.usage,
  });
}

class _MedicineList extends StatelessWidget {
  final List<_Medicine> _medicines = [
    _Medicine(name: 'Paracetamol 500mg', dosage: '500mg', quantity: 2, unit: 'viên', usage: 'Ngày 3 lần'),
    _Medicine(name: 'Amoxicillin 500mg', dosage: '500mg', quantity: 1, unit: 'viên', usage: 'Ngày 2 lần'),
    _Medicine(name: 'Vitamin C 1000mg', dosage: '1000mg', quantity: 1, unit: 'viên', usage: 'Ngày 1 lần'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _medicines.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final med = _medicines[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.successColor.withOpacity(0.1),
              child: const Icon(Icons.medication, color: AppTheme.successColor),
            ),
            title: Text(med.name, style: AppTextStyles.subtitle2),
            subtitle: Text('${med.quantity} ${med.unit} x ${med.usage}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () {},
            ),
          );
        },
      ),
    );
  }
}

class _AddMedicineSheet extends StatelessWidget {
  const _AddMedicineSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Thêm thuốc', style: AppTextStyles.headline3),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm kiếm thuốc...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Kết quả tìm kiếm:', style: AppTextStyles.body2),
            const SizedBox(height: 8),
            ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: const Text('Paracetamol 500mg'),
                  subtitle: const Text('Hộp 10 vỉ x 10 viên'),
                  onTap: () {},
                ),
                ListTile(
                  title: const Text('Amoxicillin 500mg'),
                  subtitle: const Text('Hộp 2 vỉ x 10 viên'),
                  onTap: () {},
                ),
                ListTile(
                  title: const Text('Vitamin C 1000mg'),
                  subtitle: const Text('Hộp 30 viên'),
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('Thêm'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Số thuốc:'),
              const Text('3 loại', style: AppTextStyles.subtitle2),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tổng số lượng:'),
              const Text('4 viên', style: AppTextStyles.subtitle2),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tổng tiền (ước tính):'),
              Text(
                '150.000 VNĐ',
                style: AppTextStyles.subtitle1.copyWith(color: AppTheme.primaryColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {},
              child: const Text('Lưu nháp'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Kê đơn'),
            ),
          ),
        ],
      ),
    );
  }
}
