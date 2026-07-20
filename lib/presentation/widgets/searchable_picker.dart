// SearchablePicker v2.63.0 - Widget chung cho tất cả picker có search
// Dùng cho: 37 loại phiếu EMR, ICD (174+), CLS (33k), thuốc (32k), Khoa (52)
// Pattern copy từ picker 37 loại phiếu (v2.62.0 - BS thích)
import 'package:flutter/material.dart';

/// Item cho SearchablePicker
class PickerItem {
  final String id;
  final String code;        // mã ngắn (hiển thị trong circle badge)
  final String name;        // tên đầy đủ
  final String? subtitle;   // mô tả phụ (vd: ICD_CODE, SERVICE_CODE, ID)
  final String? badge;      // badge text (vd: "I10", "XN", "KH")
  final Map<String, dynamic>? raw;  // raw data nếu cần trả về

  const PickerItem({
    required this.id,
    required this.code,
    required this.name,
    this.subtitle,
    this.badge,
    this.raw,
  });
}

/// SearchablePicker - Bottom sheet với search box + scroll list + check chọn
class SearchablePicker<T> extends StatefulWidget {
  /// Danh sách items để hiển thị
  final List<PickerItem> items;

  /// Tiêu đề sheet (vd: "Chọn ICD")
  final String title;

  /// Hint cho ô search
  final String hintText;

  /// Search provider custom (vd search ICD theo code + name)
  /// Default: search theo name.toLowerCase().contains(query)
  final bool Function(PickerItem item, String query)? customFilter;

  /// Multi-select hay single-select
  final bool multiSelect;

  /// Selected IDs (cho multi-select)
  final List<String> selectedIds;

  /// Callback khi chọn (single-select trả về 1 item, multi-select trả về list IDs)
  final void Function(dynamic result) onSelected;

  /// Show selected count badge
  final bool showCount;

  /// Empty state text
  final String? emptyText;

  const SearchablePicker({
    super.key,
    required this.items,
    required this.title,
    required this.onSelected,
    this.hintText = 'Tìm kiếm...',
    this.customFilter,
    this.multiSelect = false,
    this.selectedIds = const [],
    this.showCount = true,
    this.emptyText,
  });

  /// Helper: show as bottom sheet, trả về dynamic (single: PickerItem, multi: List<String>)
  static Future<dynamic> show({
    required BuildContext context,
    required List<PickerItem> items,
    required String title,
    String hintText = 'Tìm kiếm...',
    bool Function(PickerItem item, String query)? customFilter,
    bool multiSelect = false,
    List<String> selectedIds = const [],
    bool showCount = true,
    String? emptyText,
  }) async {
    return showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,  // v2.83.0: tránh màn đen xám khi focus TextField
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchablePicker<dynamic>(
        items: items,
        title: title,
        hintText: hintText,
        customFilter: customFilter,
        multiSelect: multiSelect,
        selectedIds: selectedIds,
        showCount: showCount,
        emptyText: emptyText,
        onSelected: (result) => Navigator.pop(ctx, result),
      ),
    );
  }

  @override
  State<SearchablePicker<T>> createState() => _SearchablePickerState<T>();
}

class _SearchablePickerState<T> extends State<SearchablePicker<T>> {
  final _searchCtrl = TextEditingController();
  late Set<String> _selectedSet;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedSet = Set<String>.from(widget.selectedIds);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<PickerItem> get _filtered {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return widget.items.where((item) {
      if (widget.customFilter != null) {
        return widget.customFilter!(item, q);
      }
      return item.name.toLowerCase().contains(q) ||
          item.code.toLowerCase().contains(q) ||
          (item.subtitle?.toLowerCase().contains(q) ?? false) ||
          (item.badge?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.assignment, color: Colors.indigo, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (widget.showCount) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              widget.multiSelect
                                  ? '${_selectedSet.length}/${filtered.length}'
                                  : '${filtered.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (widget.multiSelect && _selectedSet.isNotEmpty)
                          TextButton.icon(
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Xong', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 32),
                            ),
                            onPressed: () {
                              widget.onSelected(_selectedSet.toList());
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Search box
                    TextField(
                      controller: _searchCtrl,
                      autofocus: false,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: widget.hintText,
                        hintStyle: const TextStyle(fontSize: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              // List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                widget.emptyText ?? 'Không tìm thấy',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (ctx, i) {
                          final item = filtered[i];
                          final isSelected = _selectedSet.contains(item.id);
                          return ListTile(
                            dense: true,
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.indigo.shade100 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: item.badge != null
                                    ? Text(
                                        item.badge!,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.indigo.shade900 : Colors.grey.shade700,
                                        ),
                                        textAlign: TextAlign.center,
                                      )
                                    : Text(
                                        item.code,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.indigo.shade900 : Colors.grey.shade700,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                              ),
                            ),
                            subtitle: item.subtitle != null
                                ? Text(
                                    item.subtitle!,
                                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                                  )
                                : null,
                            trailing: isSelected
                                ? Icon(
                                    widget.multiSelect ? Icons.check_box : Icons.check_circle,
                                    color: Colors.indigo,
                                    size: 20,
                                  )
                                : null,
                            onTap: () {
                              if (widget.multiSelect) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedSet.remove(item.id);
                                  } else {
                                    _selectedSet.add(item.id);
                                  }
                                });
                              } else {
                                widget.onSelected(item);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}