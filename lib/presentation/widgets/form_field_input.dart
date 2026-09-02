// Widgets nhập liệu cho phiếu (FormField)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/icd10_library.dart';
import '../../data/models/clinical_forms_def.dart';
import '../../data/services/his_service_catalog.dart';
import 'searchable_picker.dart';

class FormFieldInput extends StatefulWidget {
  final FormFieldDef def;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final Map<String, dynamic>? patientContext; // BN data để auto-fill
  final bool readOnly;

  const FormFieldInput({
    super.key,
    required this.def,
    required this.value,
    required this.onChanged,
    this.patientContext,
    this.readOnly = false,
  });

  @override
  State<FormFieldInput> createState() => _FormFieldInputState();
}

class _FormFieldInputState extends State<FormFieldInput> {
  late TextEditingController _ctrl;
  late FocusNode _focus;
  bool _autoFilled = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _valueToString(widget.value));
    _focus = FocusNode();
    // Auto-fill từ patient context (nếu value null)
    if (widget.value == null && widget.patientContext != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryAutoFill();
      });
    }
  }

  @override
  void didUpdateWidget(FormFieldInput old) {
    super.didUpdateWidget(old);
    final newStr = _valueToString(widget.value);
    if (newStr != _ctrl.text) {
      _ctrl.text = newStr;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _valueToString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num) return v.toString();
    if (v is DateTime) return v.toIso8601String();
    return v.toString();
  }

  void _tryAutoFill() {
    if (_autoFilled) return;
    if (widget.patientContext == null) return;
    final ctx = widget.patientContext!;
    String? autoVal;
    switch (widget.def.key) {
      case 'PATIENT_NAME':
      case 'VIR_PATIENT_NAME':
        autoVal = ctx['VIR_PATIENT_NAME'] ?? ctx['patientName'];
        break;
      case 'PATIENT_CODE':
      case 'TREATMENT_CODE':
        autoVal = ctx['PATIENT_CODE'] ?? ctx['patientCode'];
        break;
      case 'PATIENT_DOB':
      case 'DOB':
        autoVal = ctx['DOB'] ?? ctx['dob'];
        break;
      case 'TDL_PATIENT_GENDER_NAME':
      case 'GENDER_NAME':
        autoVal = ctx['GENDER_NAME'] ?? ctx['genderName'];
        break;
      case 'BED_NAME':
        autoVal = ctx['BED_NAME'] ?? ctx['bedName'];
        break;
      case 'ROOM_NAME':
        autoVal = ctx['ROOM_NAME'] ?? ctx['roomName'];
        break;
      case 'DEPARTMENT_NAME':
        autoVal = ctx['DEPARTMENT_NAME'] ?? ctx['departmentName'];
        break;
      case 'PHONE':
        autoVal = ctx['PHONE'] ?? ctx['phone'];
        break;
      case 'VIR_ADDRESS':
        autoVal = ctx['VIR_ADDRESS'] ?? ctx['address'];
        break;
      case 'HEIN_CARD_NUMBER':
        autoVal = ctx['HEIN_CARD_NUMBER'] ?? ctx['heinCard'];
        break;
    }
    if (autoVal != null && autoVal.toString().isNotEmpty) {
      _autoFilled = true;
      _ctrl.text = autoVal.toString();
      widget.onChanged(autoVal.toString());
      setState(() {});
    }
  }

  Future<void> _pickDate() async {
    final v = widget.value;
    DateTime? init;
    if (v is String) init = DateTime.tryParse(v);
    init ??= DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null) {
      widget.onChanged(picked.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _pickTime() async {
    final v = widget.value;
    TimeOfDay? init;
    if (v is String) {
      try {
        final parts = v.split(':');
        if (parts.length >= 2) {
          init = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      } catch (_) {}
    }
    init ??= TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked != null) {
      widget.onChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('vi', 'VN'),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    widget.onChanged(dt.toIso8601String());
  }

  Future<void> _pickIcd() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _IcdPickerSheet(initial: widget.value?.toString() ?? ''),
    );
    if (code != null && code.isNotEmpty) {
      // Find name
      final entry = Icd10Library.common.where((e) => e.code == code).firstOrNull;
      widget.onChanged(code);
      // Auto-set ICD_NAME via callback
      if (entry != null) {
        // We use a separate key callback
        widget.onChanged({'code': code, 'name': entry.nameVi});
      }
    }
  }

  Future<void> _pickService() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ServicePickerSheet(initial: widget.value?.toString() ?? ''),
    );
    if (code != null && code.isNotEmpty) {
      widget.onChanged(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final ro = widget.readOnly;

    Widget input;

    switch (def.type) {
      case FormFieldType.text:
        input = TextField(
          controller: _ctrl,
          focusNode: _focus,
          readOnly: ro,
          maxLength: def.maxLength,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: def.hint.isNotEmpty ? def.hint : 'Nhập ${def.label.toLowerCase()}',
            suffixText: def.unit,
            counterText: '',
          ),
          onChanged: (v) => widget.onChanged(v),
        );
        break;

      case FormFieldType.paragraph:
      case FormFieldType.multiline:
        input = TextField(
          controller: _ctrl,
          focusNode: _focus,
          readOnly: ro,
          maxLines: def.rows ?? 3,
          minLines: def.rows ?? 3,
          maxLength: def.maxLength,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: def.hint.isNotEmpty ? def.hint : 'Nhập ${def.label.toLowerCase()}',
            alignLabelWithHint: true,
            counterText: def.maxLength != null ? null : '',
          ),
          onChanged: (v) => widget.onChanged(v),
        );
        break;

      case FormFieldType.number:
      case FormFieldType.decimal:
        input = TextField(
          controller: _ctrl,
          focusNode: _focus,
          readOnly: ro,
          keyboardType: TextInputType.numberWithOptions(decimal: def.type == FormFieldType.decimal),
          inputFormatters: def.type == FormFieldType.decimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[\d\.\-]'))]
              : [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            suffixText: def.unit,
            hintText: def.hint,
          ),
          onChanged: (v) {
            if (v.isEmpty) {
              widget.onChanged(null);
              return;
            }
            if (def.type == FormFieldType.decimal) {
              widget.onChanged(double.tryParse(v));
            } else {
              widget.onChanged(int.tryParse(v));
            }
          },
        );
        break;

      case FormFieldType.date:
        input = InkWell(
          onTap: ro ? null : _pickDate,
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'Chọn ngày',
              suffixIcon: const Icon(Icons.calendar_today, size: 18),
            ),
            child: Text(
              _formatDate(widget.value),
              style: TextStyle(
                color: widget.value == null ? Colors.grey : Colors.black,
              ),
            ),
          ),
        );
        break;

      case FormFieldType.time:
        input = InkWell(
          onTap: ro ? null : _pickTime,
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'Chọn giờ',
              suffixIcon: const Icon(Icons.access_time, size: 18),
            ),
            child: Text(
              widget.value?.toString() ?? '',
              style: TextStyle(
                color: widget.value == null ? Colors.grey : Colors.black,
              ),
            ),
          ),
        );
        break;

      case FormFieldType.datetime:
        input = InkWell(
          onTap: ro ? null : _pickDateTime,
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'Chọn ngày giờ',
              suffixIcon: const Icon(Icons.event, size: 18),
            ),
            child: Text(
              _formatDateTime(widget.value),
              style: TextStyle(
                color: widget.value == null ? Colors.grey : Colors.black,
              ),
            ),
          ),
        );
        break;

      case FormFieldType.select:
        input = DropdownButtonFormField<String>(
          initialValue: widget.value?.toString(),
          isDense: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: def.options
              .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
              .toList(),
          onChanged: ro ? null : (v) => widget.onChanged(v),
        );
        break;

      case FormFieldType.icd:
        input = InkWell(
          onTap: ro ? null : _pickIcd,
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'Chọn ICD-10',
              suffixIcon: Icon(Icons.search, size: 18),
            ),
            child: Text(
              _formatIcdDisplay(widget.value),
              style: TextStyle(
                color: widget.value == null ? Colors.grey : Colors.black,
                fontSize: 14,
              ),
            ),
          ),
        );
        break;

      case FormFieldType.service:
        input = InkWell(
          onTap: ro ? null : _pickService,
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'Chọn dịch vụ BHYT',
              suffixIcon: Icon(Icons.medical_services, size: 18),
            ),
            child: Text(
              _formatServiceDisplay(widget.value),
              style: TextStyle(
                color: widget.value == null ? Colors.grey : Colors.black,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
        break;

      case FormFieldType.checkbox:
        input = CheckboxListTile(
          value: widget.value == true,
          onChanged: ro ? null : (v) => widget.onChanged(v),
          title: Text(def.label),
          contentPadding: EdgeInsets.zero,
          dense: true,
        );
        // No separate label needed
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: input,
        );

      case FormFieldType.bp:
        // Special: HA tâm thu / tâm trương side-by-side
        input = _BpInput(
          def: def,
          value: widget.value,
          onChanged: widget.onChanged,
          readOnly: ro,
        );
        break;

      case FormFieldType.signature:
        input = TextField(
          controller: _ctrl,
          focusNode: _focus,
          readOnly: ro,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: 'Nhập họ tên để ký',
            prefixIcon: const Icon(Icons.edit, size: 18),
          ),
          style: const TextStyle(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
          ),
          onChanged: (v) => widget.onChanged(v),
        );
        break;
    }

    if (def.type == FormFieldType.checkbox) {
      return input; // already wrapped
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                def.label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              if (def.required) ...[
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(color: Colors.red, fontSize: 14)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          input,
        ],
      ),
    );
  }

  String _formatDate(dynamic v) {
    if (v == null) return '';
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      return v;
    }
    if (v is DateTime) {
      return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
    }
    return v.toString();
  }

  String _formatDateTime(dynamic v) {
    if (v == null) return '';
    DateTime? d;
    if (v is String) d = DateTime.tryParse(v);
    if (v is DateTime) d = v;
    if (d == null) return v.toString();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatIcdDisplay(dynamic v) {
    if (v == null) return '';
    if (v is Map) {
      return '${v['code']} - ${v['name']}';
    }
    if (v is String) {
      final entry = Icd10Library.common.where((e) => e.code == v).firstOrNull;
      if (entry != null) return '${entry.code} - ${entry.nameVi}';
    }
    return v.toString();
  }

  String _formatServiceDisplay(dynamic v) {
    if (v == null) return '';
    if (v is String) {
      final entry = HisServiceCatalog.lookup(v);
      if (entry != null) return '${entry.code} - ${entry.name}';
    }
    return v.toString();
  }
}

class _BpInput extends StatelessWidget {
  final FormFieldDef def;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final bool readOnly;
  const _BpInput({required this.def, required this.value, required this.onChanged, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    int? maxV, minV;
    if (value is Map) {
      maxV = value['max'] as int?;
      minV = value['min'] as int?;
    }
    return Row(
      children: [
        Expanded(
          child: TextField(
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            controller: TextEditingController(text: maxV?.toString() ?? ''),
            readOnly: readOnly,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Tâm thu',
              suffixText: 'mmHg',
            ),
            onChanged: (v) {
              onChanged({
                'max': int.tryParse(v),
                'min': minV,
              });
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('/', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: TextField(
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            controller: TextEditingController(text: minV?.toString() ?? ''),
            readOnly: readOnly,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Tâm trương',
              suffixText: 'mmHg',
            ),
            onChanged: (v) {
              onChanged({
                'max': maxV,
                'min': int.tryParse(v),
              });
            },
          ),
        ),
      ],
    );
  }
}

class _IcdPickerSheet extends StatefulWidget {
  final String initial;
  const _IcdPickerSheet({required this.initial});
  @override
  State<_IcdPickerSheet> createState() => _IcdPickerSheetState();
}

class _IcdPickerSheetState extends State<_IcdPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = _query.isEmpty
        ? Icd10Library.common
        : Icd10Library.common
            .where((e) => e.code.toLowerCase().contains(q) || e.nameVi.toLowerCase().contains(q))
            .toList();
    final items = filtered.map((e) => PickerItem(
      id: e.code,
      code: e.code,
      name: e.nameVi,
      subtitle: e.category,
      badge: e.code,
      raw: {'entry': e},
    )).toList();
    return SearchablePicker(
      items: items,
      title: 'Chọn ICD-10 (${filtered.length} mã)',
      hintText: 'Tìm ICD-10 (mã hoặc tên)',
      onSelected: (result) {
        if (result is PickerItem) {
          Navigator.pop(context, (result.raw!['entry'] as Icd10Entry).code);
        }
      },
    );
  }
}

class _ServicePickerSheet extends StatefulWidget {
  final String initial;
  const _ServicePickerSheet({required this.initial});
  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  String _query = '';
  String? _chapter;

  String _formatPrice(double p) {
    if (p >= 1000000) return '${(p / 1000000).toStringAsFixed(1)} triệu';
    if (p >= 1000) return '${(p / 1000).toStringAsFixed(0)}k';
    return p.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    var list = HisServiceCatalog.search(_query);
    if (_chapter != null) {
      list = list.where((e) => e.chapter == _chapter).toList();
    }
    final items = list.map((e) => PickerItem(
      id: e.code,
      code: e.code,
      name: e.name,
      subtitle: '${e.chapter} • ${_formatPrice(e.defaultPrice)} VNĐ',
      badge: e.code,
      raw: {'entry': e},
    )).toList();

    // Hiển thị thêm filter chips cho chapters phía trên SearchablePicker
    return SearchablePicker(
      items: items,
      title: 'Chọn dịch vụ BHYT (${list.length}+)',
      hintText: _chapter != null ? 'Tìm trong ${_chapter}...' : 'Tìm mã hoặc tên dịch vụ',
      onSelected: (result) {
        if (result is PickerItem) {
          Navigator.pop(context, (result.raw!['entry'] as HisServiceEntry).code);
        }
      },
    );
  }
}
