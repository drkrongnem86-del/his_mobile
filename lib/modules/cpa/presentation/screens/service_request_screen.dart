import 'package:flutter/material.dart';
import 'package:his_mobile/core/theme/app_theme.dart';

class ServiceRequestScreen extends StatelessWidget {
  final String treatmentId;

  const ServiceRequestScreen({super.key, required this.treatmentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yêu cầu dịch vụ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {},
          ),
        ],
      ),
      body: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            // Tab Bar
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Xét nghiệm'),
                Tab(text: 'CĐHA'),
                Tab(text: 'Khám CK'),
                Tab(text: 'Khác'),
              ],
            ),
            // Tab Content
            Expanded(
              child: TabBarView(
                children: [
                  _LabTestTab(),
                  _ImagingTab(),
                  _SpecialistTab(),
                  _OtherTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabTestTab extends StatelessWidget {
  final List<_LabTest> _tests = [
    _LabTest(code: 'CBC', name: 'Công thức máu', price: 50000),
    _LabTest(code: 'GLU', name: 'Glucose', price: 30000),
    _LabTest(code: 'UREA', name: 'Urea', price: 40000),
    _LabTest(code: 'CRE', name: 'Creatinin', price: 45000),
    _LabTest(code: 'AST', name: 'AST/GOT', price: 40000),
    _LabTest(code: 'ALT', name: 'ALT/GPT', price: 40000),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Tìm kiếm xét nghiệm...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        // Test List
        Expanded(
          child: ListView.builder(
            itemCount: _tests.length,
            itemBuilder: (context, index) {
              final test = _tests[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryLight,
                    child: Text(test.code.substring(0, 2)),
                  ),
                  title: Text(test.name),
                  subtitle: Text('${test.price} VNĐ'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle, color: AppTheme.primaryColor),
                    onPressed: () {},
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LabTest {
  final String code;
  final String name;
  final int price;

  _LabTest({required this.code, required this.name, required this.price});
}

class _ImagingTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Chẩn đoán hình ảnh'));
  }
}

class _SpecialistTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Khám chuyên khoa'));
  }
}

class _OtherTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Dịch vụ khác'));
  }
}
