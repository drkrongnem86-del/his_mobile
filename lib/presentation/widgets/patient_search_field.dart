// SearchSuggestionField v2.38.0 - Widget dùng chung cho tìm BN có gợi ý
// - Gõ 1 chữ → dropdown gợi ý BN ngay dưới
// - Ranking: chính xác 100 > bắt đầu 80 > chứa 60 > mã ĐT/BN
// - Tìm kiếm từ: tên, mã BN, mã ĐT (diacritic-insensitive)
import 'package:flutter/material.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'package:his_mobile/data/patient_dataset.dart';

typedef PatientTapCallback = void Function(Map<String, dynamic> patient);

class PatientSearchField extends StatefulWidget {
  final String hintText;
  final List<Map<String, dynamic>> extraPatients;
  final PatientTapCallback? onPatientTap;
  final ValueChanged<String>? onChanged; // callback gõ (filter ngoài)
  final int maxSuggestions;
  final double maxDropdownHeight;
  /// v2.38.4: Nếu set, CHỈ search BN trong khoa này (DepartmentCode).
  /// null = search tất cả khoa (mặc định cho Bệnh nhân / Tiện ích).
  final String? filterDepartmentCode;

  const PatientSearchField({
    super.key,
    this.hintText = 'Tìm BN theo tên / mã ĐT / mã BN...',
    this.extraPatients = const [],
    this.onPatientTap,
    this.onChanged,
    this.maxSuggestions = 15,
    this.maxDropdownHeight = 280,
    this.filterDepartmentCode,
  });

  @override
  State<PatientSearchField> createState() => _PatientSearchFieldState();
}

class _PatientSearchFieldState extends State<PatientSearchField> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _show) {
        setState(() => _show = false);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _update(String q) {
    q = q.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestions = [];
        _show = false;
      });
      widget.onChanged?.call('');
      return;
    }
    final lower = q.toLowerCase();
    final noDiacritics = removeDiacritics(lower);
    final all = <Map<String, dynamic>>[...widget.extraPatients];
    // v2.38.4: Nếu filterDepartmentCode set → chỉ search BN trong khoa đó
    final List<String> deptsToSearch = widget.filterDepartmentCode != null
        ? [widget.filterDepartmentCode!]
        : [
            'HSCC', 'CCS', 'DTYC', 'DVNTK', 'DVTMCT', 'HSTC', 'NTK', 'NTTN',
            'KM', 'NGCT', 'NGTH', 'KN', 'NTM', 'KNTH', 'KPS', 'KTNT',
            'PTGMHS', 'KRHM', 'KTMH', 'KTN', 'KYHCT', 'KKB', 'KUB', 'KSNK',
            'HSCCL', 'CCSVL', 'DTCCLuu'
          ];
    for (final d in deptsToSearch) {
      all.addAll(PatientSeed.getByDepartment(d));
    }
    // Dedup by treatment_code
    final seen = <String>{};
    final uniq = <Map<String, dynamic>>[];
    for (final p in all) {
      final tcode = (p['TDL_TREATMENT_CODE'] ?? p['MADT'] ?? p['treatment_code'] ?? '').toString();
      if (tcode.isEmpty || !seen.contains(tcode)) {
        if (tcode.isNotEmpty) seen.add(tcode);
        uniq.add(p);
      }
    }
    final scored = <Map<String, dynamic>>[];
    for (final p in uniq) {
      final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['TEN_BENH_NHAN'] ?? p['tdl_patient_name'] ?? '').toString();
      final code = (p['TDL_PATIENT_CODE'] ?? p['MABN'] ?? p['patient_code'] ?? '').toString();
      final tcode = (p['TDL_TREATMENT_CODE'] ?? p['MADT'] ?? p['treatment_code'] ?? '').toString();
      final hein = (p['TDL_HEIN_CARD_NUMBER'] ?? p['BHYT'] ?? '').toString();
      final nameLow = removeDiacritics(name.toLowerCase());
      int score = 0;
      if (nameLow == noDiacritics) score = 100;
      else if (nameLow.startsWith(noDiacritics)) score = 80;
      else if (nameLow.contains(noDiacritics)) score = 60;
      if (code == q) score = score > 95 ? score : 95;
      else if (code.startsWith(q)) score = score > 70 ? score : 70;
      else if (code.contains(q)) score = score > 50 ? score : 50;
      if (tcode == q) score = score > 90 ? score : 90;
      else if (tcode.startsWith(q)) score = score > 65 ? score : 65;
      if (hein == q) score = score > 85 ? score : 85;
      else if (hein.contains(q)) score = score > 45 ? score : 45;
      if (score > 0) scored.add({...p, '_score': score});
    }
    scored.sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));
    setState(() {
      _suggestions = scored.take(widget.maxSuggestions).toList();
      _show = true;
    });
    widget.onChanged?.call(q);
  }

  void _pick(Map<String, dynamic> p) {
    final name = capitalizeVietnameseName(
        (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['TEN_BENH_NHAN'] ?? p['tdl_patient_name'] ?? 'BN').toString());
    _ctrl.text = name;
    _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: name.length));
    setState(() {
      _show = false;
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
    widget.onPatientTap?.call(p);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _update,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: widget.hintText,
            hintStyle: const TextStyle(fontSize: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _ctrl.clear();
                      _update('');
                    },
                  ),
          ),
        ),
        if (_show && _suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: BoxConstraints(maxHeight: widget.maxDropdownHeight),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.indigo.shade200),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final p = _suggestions[i];
                final name = capitalizeVietnameseName(
                    (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['TEN_BENH_NHAN'] ?? p['tdl_patient_name'] ?? 'BN').toString());
                final tcode = (p['TDL_TREATMENT_CODE'] ?? p['MADT'] ?? p['treatment_code'] ?? '').toString();
                final pcode = (p['TDL_PATIENT_CODE'] ?? p['MABN'] ?? p['patient_code'] ?? '').toString();
                final dept = (p['DEPARTMENT_NAME'] ?? p['department_name'] ?? '').toString();
                return ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.indigo,
                    child: Icon(Icons.person, color: Colors.white, size: 14),
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
                  onTap: () => _pick(p),
                );
              },
            ),
          ),
      ],
    );
  }
}