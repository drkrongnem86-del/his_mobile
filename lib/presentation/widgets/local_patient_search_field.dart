// LocalPatientSearchField v2.98.6
// Widget search BN dạng FILTER LOCAL (giống DepartmentPatientsScreen v2.98.0)
// - KHÔNG có dropdown gợi ý (khác PatientSearchField)
// - Gõ → filter LOCAL ngay trên list BN đã load
// - Enter hoặc bấm nút search → gọi onSearch
// - Bấm dòng gợi ý trong list → gọi onPatientTap
//
// Dùng cho: Tiện ích (TienIchScreen), Bệnh án cũ, các màn hình khác cần filter LOCAL
import 'package:flutter/material.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';

typedef LocalPatientTapCallback = void Function(Map<String, dynamic> patient);

class LocalPatientSearchField extends StatefulWidget {
  final String hintText;
  final List<Map<String, dynamic>> patients;
  final LocalPatientTapCallback? onPatientTap;
  final ValueChanged<String>? onSearch;  // gọi khi user bấm Enter / bấm nút search
  final IconData? prefixIcon;
  final Color? iconColor;
  final int maxHeight;

  const LocalPatientSearchField({
    super.key,
    this.hintText = 'Tìm BN (gõ để lọc trong danh sách)...',
    this.patients = const [],
    this.onPatientTap,
    this.onSearch,
    this.prefixIcon,
    this.iconColor,
    this.maxHeight = 400,
  });

  @override
  State<LocalPatientSearchField> createState() => _LocalPatientSearchFieldState();
}

class _LocalPatientSearchFieldState extends State<LocalPatientSearchField> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _query = '';
  bool _showList = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        setState(() => _showList = false);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Filter LOCAL trên widget.patients (giống DepartmentPatientsScreen v2.98.0)
  List<Map<String, dynamic>> _getFiltered() {
    if (_query.trim().isEmpty) return widget.patients;
    final q = _query.trim().toLowerCase();
    return widget.patients.where((p) {
      final name = (p['TDL_PATIENT_NAME'] ?? p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_name'] ?? p['TEN_BENH_NHAN'] ?? p['HOTENBN'] ?? '').toString().toLowerCase();
      final code = (p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? p['MABN'] ?? '').toString().toLowerCase();
      final reqCode = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? p['MADT'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || reqCode.contains(q);
    }).toList();
  }

  void _onChanged(String v) {
    setState(() {
      _query = v;
      _showList = v.trim().isNotEmpty;
    });
  }

  void _onSubmit(String v) {
    setState(() => _query = v);
    widget.onSearch?.call(v.trim());
  }

  void _clear() {
    _ctrl.clear();
    setState(() {
      _query = '';
      _showList = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFiltered();
    final showDropdown = _showList && _focus.hasFocus && filtered.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onChanged,
          onSubmitted: _onSubmit,
          decoration: InputDecoration(
            prefixIcon: Icon(
              widget.prefixIcon ?? Icons.search,
              size: 20,
              color: widget.iconColor ?? Colors.indigo,
            ),
            hintText: widget.hintText,
            hintStyle: const TextStyle(fontSize: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _clear,
                  ),
          ),
        ),
        if (showDropdown)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: BoxConstraints(maxHeight: widget.maxHeight.toDouble()),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.indigo.shade200),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final p = filtered[i];
                final name = fixVietnameseMojibake(
                  PatientNameHelper.getName(p),
                );
                final tcode = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? p['MADT'] ?? '').toString();
                final pcode = (p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? p['MABN'] ?? '').toString();
                final dept = (p['DEPARTMENT_NAME'] ?? p['department_name'] ?? p['TEN_KHOA'] ?? '').toString();
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.indigo.shade100,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(color: Colors.indigo.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    [
                      if (tcode.isNotEmpty) 'ĐT: $tcode',
                      if (pcode.isNotEmpty) 'BN: $pcode',
                      if (dept.isNotEmpty) dept,
                    ].where((s) => s.isNotEmpty).join(' • '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    _ctrl.text = name;
                    _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: name.length));
                    setState(() {
                      _showList = false;
                      _query = name;
                    });
                    FocusScope.of(context).unfocus();
                    widget.onPatientTap?.call(p);
                  },
                );
              },
            ),
          )
        else if (_showList && filtered.isEmpty && _query.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Không tìm thấy "${_query.trim()}"',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
