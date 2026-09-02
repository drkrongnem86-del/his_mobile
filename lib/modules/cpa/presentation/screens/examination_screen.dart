import 'package:flutter/material.dart';
import 'package:his_mobile/core/theme/app_theme.dart';

class ExaminationScreen extends StatelessWidget {
  final String treatmentId;

  const ExaminationScreen({super.key, required this.treatmentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khám bệnh'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _saveExamination(context),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            // Patient Info Header
            _PatientHeader(),
            // Tab Bar
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Lâm sàng'),
                Tab(text: 'Chẩn đoán'),
                Tab(text: 'Yêu cầu'),
                Tab(text: 'Đơn thuốc'),
              ],
            ),
            // Tab Content
            Expanded(
              child: TabBarView(
                children: [
                  _ClinicalTab(),
                  _DiagnosisTab(),
                  _ServiceRequestTab(),
                  _PrescriptionTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(),
    );
  }

  void _saveExamination(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu thông tin khám')),
    );
  }
}

class _PatientHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.primaryLight.withOpacity(0.1),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.warningColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Đang khám',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClinicalTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vital Signs
          _SectionTitle('Sinh hiệu'),
          _VitalSignsCard(),
          const SizedBox(height: 16),

          // Symptoms
          _SectionTitle('Triệu chứng'),
          _SymptomsCard(),
          const SizedBox(height: 16),

          // Medical History
          _SectionTitle('Tiền sử'),
          _MedicalHistoryCard(),
        ],
      ),
    );
  }
}

class _DiagnosisTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Chẩn đoán chính'),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Mã ICD',
              hintText: 'Nhập mã ICD...',
              suffixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Tên chẩn đoán',
            ),
          ),
          const SizedBox(height: 16),

          _SectionTitle('Chẩn đoán phụ'),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Thêm chẩn đoán phụ'),
          ),
        ],
      ),
    );
  }
}

class _ServiceRequestTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Yêu cầu dịch vụ'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ServiceChip(icon: Icons.science, label: 'Xét nghiệm', onTap: () {}),
              _ServiceChip(icon: Icons.image, label: 'CĐHA', onTap: () {}),
              _ServiceChip(icon: Icons.medical_services, label: 'Khám CK', onTap: () {}),
              _ServiceChip(icon: Icons.monitor_heart, label: 'Chức năng', onTap: () {}),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Thêm yêu cầu'),
          ),
        ],
      ),
    );
  }
}

class _PrescriptionTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Đơn thuốc'),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Thêm thuốc'),
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

class _VitalSignsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _VitalSignInput(label: 'Mạch', unit: 'lần/phút')),
              Expanded(child: _VitalSignInput(label: 'Nhiệt độ', unit: '°C')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _VitalSignInput(label: 'Huyết áp', unit: 'mmHg')),
              Expanded(child: _VitalSignInput(label: 'SpO2', unit: '%')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _VitalSignInput(label: 'Nhịp thở', unit: 'lần/phút')),
              Expanded(child: _VitalSignInput(label: 'Cân nặng', unit: 'kg')),
            ],
          ),
        ],
      ),
    );
  }
}

class _VitalSignInput extends StatelessWidget {
  final String label;
  final String unit;

  const _VitalSignInput({required this.label, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextFormField(
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          isDense: true,
        ),
        keyboardType: TextInputType.number,
      ),
    );
  }
}

class _SymptomsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Mô tả triệu chứng',
              hintText: 'Nhập mô tả...',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicalHistoryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          _CheckboxRow(label: 'Tiền sử dị ứng'),
          _CheckboxRow(label: 'Tiền sử bệnh tim mạch'),
          _CheckboxRow(label: 'Tiền sử bệnh gan/thận'),
          _CheckboxRow(label: 'Phẫu thuật trước đây'),
          TextFormField(
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Ghi chú tiền sử khác',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  final String label;

  const _CheckboxRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: false, onChanged: (v) {}),
        Text(label),
      ],
    );
  }
}

class _ServiceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ServiceChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: AppTheme.primaryColor)),
          ],
        ),
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
              child: const Text('Hoàn thành khám'),
            ),
          ),
        ],
      ),
    );
  }
}
