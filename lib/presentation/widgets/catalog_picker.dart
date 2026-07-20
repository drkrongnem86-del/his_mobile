// CatalogPicker v2.65.0 - Refactor dùng SearchablePicker
// CLS (33k) / Thuốc (32k) / Vật tư (9k) / ICD (174+)
// Pattern đồng nhất với picker 38 loại phiếu EMR (ScanPhieuScreen)

import 'package:flutter/material.dart';
import 'package:his_mobile/data/api/his_catalog_service.dart';
import 'package:his_mobile/presentation/widgets/searchable_picker.dart';

enum CatalogPickerType { service, medicine, material, icd }

/// v2.65.0: Picker ná»™i bá»™ - dùng SearchablePicker
class _CatalogPickerBody extends StatefulWidget {
  final CatalogPickerType type;
  final String title;
  final String? hintText;
  final List<CatalogItem> selected;
  final ValueChanged<List<CatalogItem>> onChanged;
  final int? serviceTypeId;
  final bool multiSelect;
  final int maxSelect;

  const _CatalogPickerBody({
    required this.type,
    required this.title,
    required this.selected,
    required this.onChanged,
    this.hintText,
    this.serviceTypeId,
    this.multiSelect = true,
    this.maxSelect = 50,
  });

  @override
  State<_CatalogPickerBody> createState() => _CatalogPickerBodyState();
}

class _CatalogPickerBodyState extends State<_CatalogPickerBody> {
  String _query = '';

  List<CatalogItem> _searchCatalog(String q) {
    switch (widget.type) {
      case CatalogPickerType.service:
        return HisCatalogService.instance.searchServices(q, typeId: widget.serviceTypeId, limit: 200);
      case CatalogPickerType.medicine:
        return HisCatalogService.instance.searchMedicines(q, limit: 200);
      case CatalogPickerType.material:
        return HisCatalogService.instance.searchMaterials(q, limit: 200);
      case CatalogPickerType.icd:
        return HisCatalogService.instance.searchIcd(q, limit: 200);
    }
  }

  void _toggle(CatalogItem item) {
    final list = List<CatalogItem>.from(widget.selected);
    if (list.any((s) => s.code == item.code)) {
      list.removeWhere((s) => s.code == item.code);
    } else {
      if (!widget.multiSelect) list.clear();
      if (list.length >= widget.maxSelect) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tối đa ${widget.maxSelect} items'), backgroundColor: Colors.orange),
        );
        return;
      }
      list.add(item);
    }
    widget.onChanged(list);
  }

  String _formatPrice(double p) {
    if (p >= 1000000) return '${(p / 1000000).toStringAsFixed(1)}tr';
    if (p >= 1000) return '${(p / 1000).toStringAsFixed(0)}k';
    return p.toStringAsFixed(0);
  }

  Color _colorFor() {
    switch (widget.type) {
      case CatalogPickerType.service: return Colors.indigo;
      case CatalogPickerType.medicine: return Colors.teal;
      case CatalogPickerType.material: return Colors.brown;
      case CatalogPickerType.icd: return Colors.red.shade700;
    }
  }

  IconData _iconFor() {
    switch (widget.type) {
      case CatalogPickerType.service: return Icons.medical_services;
      case CatalogPickerType.medicine: return Icons.medication;
      case CatalogPickerType.material: return Icons.inventory_2;
      case CatalogPickerType.icd: return Icons.assignment;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor();
    final icon = _iconFor();
    final results = _searchCatalog(_query);

    final items = results.map((item) => PickerItem(
      id: item.code,
      code: item.code,
      name: item.name,
      subtitle: [
        if (item.typeName != null) item.typeName!,
        if (item.price != null && item.price! > 0) _formatPrice(item.price!),
      ].join(' • '),
      badge: item.code,
      raw: {'catalogItem': item},
    )).toList();

    final selectedIds = widget.selected.map((s) => s.code).toList();

    return SearchablePicker(
      items: items,
      title: '${widget.title} (${results.length}+)',
      hintText: widget.hintText ?? 'Tìm ${widget.title.toLowerCase()}...',
      multiSelect: widget.multiSelect,
      selectedIds: selectedIds,
      onSelected: (result) {
        if (result is PickerItem && result.raw != null) {
          final item = result.raw!['catalogItem'] as CatalogItem;
          if (!widget.multiSelect) {
            // Single-select: Đóng ngay
            widget.onChanged([item]);
            Navigator.pop(context, [item]);
          } else {
            _toggle(item);
          }
        }
      },
    );
  }
}

/// v2.65.0: Show CatalogPicker as bottom sheet (pattern giống ScanPhieuScreen picker)
/// Returns null nếu user hễy, hoặc List<CatalogItem> Đã chọn
Future<List<CatalogItem>?> showCatalogPicker({
  required BuildContext context,
  required CatalogPickerType type,
  required String title,
  String? hintText,
  List<CatalogItem> selected = const [],
  int? serviceTypeId,
  bool multiSelect = false,
  int maxSelect = 50,
}) async {
  return showModalBottomSheet<List<CatalogItem>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    barrierColor: Colors.black.withOpacity(0.25),
    builder: (ctx) {
      return _CatalogPickerBody(
        type: type,
        title: title,
        hintText: hintText,
        selected: selected,
        serviceTypeId: serviceTypeId,
        multiSelect: multiSelect,
        maxSelect: maxSelect,
        onChanged: (list) {
          if (!multiSelect) {
            Navigator.pop(ctx, list);
          }
        },
      );
    },
  );
}

/// v2.65.0: CatalogPickerWidget (legacy - cho tương thích ngược vá»›i code cé)
/// Hiển thị inline (không phải modal) - dùng khi cần nhứng trong form
class CatalogPicker extends StatefulWidget {
  final CatalogPickerType type;
  final String title;
  final String? hintText;
  final List<CatalogItem> selected;
  final ValueChanged<List<CatalogItem>> onChanged;
  final int? serviceTypeId;
  final bool multiSelect;
  final int maxSelect;

  const CatalogPicker({
    super.key,
    required this.type,
    required this.title,
    required this.selected,
    required this.onChanged,
    this.hintText,
    this.serviceTypeId,
    this.multiSelect = true,
    this.maxSelect = 50,
  });

  @override
  State<CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<CatalogPicker> {
  String _query = '';

  List<CatalogItem> _searchCatalog(String q) {
    switch (widget.type) {
      case CatalogPickerType.service:
        return HisCatalogService.instance.searchServices(q, typeId: widget.serviceTypeId, limit: 200);
      case CatalogPickerType.medicine:
        return HisCatalogService.instance.searchMedicines(q, limit: 200);
      case CatalogPickerType.material:
        return HisCatalogService.instance.searchMaterials(q, limit: 200);
      case CatalogPickerType.icd:
        return HisCatalogService.instance.searchIcd(q, limit: 200);
    }
  }

  void _toggle(CatalogItem item) {
    final list = List<CatalogItem>.from(widget.selected);
    if (list.any((s) => s.code == item.code)) {
      list.removeWhere((s) => s.code == item.code);
    } else {
      if (!widget.multiSelect) list.clear();
      if (list.length >= widget.maxSelect) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tối đa ${widget.maxSelect} items'), backgroundColor: Colors.orange),
        );
        return;
      }
      list.add(item);
    }
    widget.onChanged(list);
  }

  String _formatPrice(double p) {
    if (p >= 1000000) return '${(p / 1000000).toStringAsFixed(1)}tr';
    if (p >= 1000) return '${(p / 1000).toStringAsFixed(0)}k';
    return p.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor();
    final results = _searchCatalog(_query);

    final items = results.map((item) => PickerItem(
      id: item.code,
      code: item.code,
      name: item.name,
      subtitle: [
        if (item.typeName != null) item.typeName!,
        if (item.price != null && item.price! > 0) _formatPrice(item.price!),
      ].join(' • '),
      badge: item.code,
      raw: {'catalogItem': item},
    )).toList();

    final selectedIds = widget.selected.map((s) => s.code).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: SearchablePicker(
        items: items,
        title: '${widget.title} (${results.length}+)',
        hintText: widget.hintText ?? 'Tìm ${widget.title.toLowerCase()}...',
        multiSelect: widget.multiSelect,
        selectedIds: selectedIds,
        onSelected: (result) {
          if (result is PickerItem && result.raw != null) {
            final item = result.raw!['catalogItem'] as CatalogItem;
            _toggle(item);
          }
        },
      ),
    );
  }

  Color _colorFor() {
    switch (widget.type) {
      case CatalogPickerType.service: return Colors.indigo;
      case CatalogPickerType.medicine: return Colors.teal;
      case CatalogPickerType.material: return Colors.brown;
      case CatalogPickerType.icd: return Colors.red.shade700;
    }
  }
}
