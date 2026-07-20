// DeptPicker v2.66.0 - Chọn khoa với search
// Lấy list từ DepartmentService (ưu tiên API HisDepartment/Get - 81 khoa thật)
// Fallback: AppConstants.departments (52 khoa hardcode)
import 'package:flutter/material.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/department_service.dart';
import 'package:his_mobile/presentation/widgets/searchable_picker.dart';

class DeptPicker extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<Map<String, dynamic>?> onSelected;

  const DeptPicker({
    super.key,
    required this.initialQuery,
    required this.onSelected,
  });

  @override
  State<DeptPicker> createState() => _DeptPickerState();
}

class _DeptPickerState extends State<DeptPicker> {
  late TextEditingController _searchCtrl;
  List<Map<String, dynamic>> _filteredDepts = [];

  // v2.66.0: Lấy từ DepartmentService (ưu tiên) hoặc fallback AppConstants
  List<Map<String, dynamic>> get _allDepartments =>
      DepartmentService.instance.departments.isNotEmpty
          ? DepartmentService.instance.departments
          : AppConstants.departments;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.initialQuery);
    _filter();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredDepts = q.isEmpty
          ? _allDepartments
          : _allDepartments.where((d) =>
              d['name'].toString().toLowerCase().contains(q) ||
              d['code'].toString().toLowerCase().contains(q) ||
              d['id'].toString().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredDepts.map((d) => PickerItem(
      id: d['id'].toString(),
      code: d['code'].toString(),
      name: d['name'].toString(),
      subtitle: 'ID: ${d['id']}',
      raw: d,
    )).toList();

    return SearchablePicker<Map<String, dynamic>>(
      items: items,
      title: 'Chọn khoa (${_allDepartments.length} khoa)',
      hintText: 'Tìm theo tên khoa / mã / ID...',
      multiSelect: false,
      onSelected: (item) {
        if (item is PickerItem) {
          widget.onSelected(item.raw);
        }
      },
    );
  }
}