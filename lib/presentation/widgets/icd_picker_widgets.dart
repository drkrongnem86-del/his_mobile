// IcdPicker v2.63.0 - Chọn ICD với search + edit name
// Thay thế _IcdSinglePickerSheet + _IcdSuggestSheet trong phieu_form_screen
// Dùng SearchablePicker (BS thích pattern search của picker 37 loại EMR)
import 'package:flutter/material.dart';
import 'package:his_mobile/data/api/his_catalog_service.dart';
import 'package:his_mobile/presentation/widgets/searchable_picker.dart';

/// v2.63.0: Picker ICD với search realtime + edit name
class IcdSinglePicker extends StatefulWidget {
  /// ICD đã chọn trước đó (text hiển thị)
  final String initial;

  /// Callback trả về String ICD đã chọn (vd "I10 - Tăng HA")
  final ValueChanged<String> onSelected;

  const IcdSinglePicker({
    super.key,
    required this.initial,
    required this.onSelected,
  });

  @override
  State<IcdSinglePicker> createState() => _IcdSinglePickerState();
}

class _IcdSinglePickerState extends State<IcdSinglePicker> {
  final _searchCtrl = TextEditingController();
  final _valueCtrl = TextEditingController(text: '');
  List<CatalogItem> _results = [];
  String _picked = '';
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _valueCtrl.text = widget.initial;
    _picked = widget.initial;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim();
    setState(() {
      _results = q.isEmpty
          ? []
          : HisCatalogService.instance.searchIcd(q, limit: 80);
      _showResults = q.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Icon(Icons.medical_services, color: Colors.indigo, size: 22),
                        SizedBox(width: 8),
                        Text('Chọn ICD (174+ mã)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: 'Tìm theo mã (I10, S01, J18) hoặc tên (Tăng HA...)',
                        hintStyle: const TextStyle(fontSize: 13),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _results = [];
                                    _showResults = false;
                                  });
                                },
                              )
                            : null,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Đã chọn (chip)
              if (_picked.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.indigo, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Đã chọn: $_picked',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text('Sửa', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setState(() {
                            _valueCtrl.text = _picked;
                          });
                          showDialog(
                            context: ctx,
                            builder: (dctx) => AlertDialog(
                              title: const Text('Sửa tên ICD'),
                              content: TextField(
                                controller: _valueCtrl,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'vd: I10 - Tăng huyết áp',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dctx),
                                  child: const Text('Hủy'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    setState(() => _picked = _valueCtrl.text);
                                    Navigator.pop(dctx);
                                  },
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _picked = '';
                            _valueCtrl.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              // Hint hoặc Results
              Expanded(
                child: !_showResults
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                'Gõ mã ICD (I10, J18) hoặc tên bệnh để tìm',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '174+ mã ICD từ HIS Pro',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              'Không tìm thấy. Thử mã khác (I10, J18, S01)',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                            itemBuilder: (ctx, i) {
                              final item = _results[i];
                              final txt = '${item.code} - ${item.name}';
                              final isPicked = _picked == txt;
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: isPicked ? Colors.indigo.shade100 : Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Center(
                                    child: Text(
                                      item.code,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: isPicked ? Colors.indigo.shade900 : Colors.indigo.shade700,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  item.code,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.indigo,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  item.name,
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: isPicked
                                    ? const Icon(Icons.check_circle, color: Colors.indigo, size: 20)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _picked = txt;
                                    _valueCtrl.text = txt;
                                  });
                                },
                              );
                            },
                          ),
              ),
              // Bottom: Xong button (visible khi đã chọn)
              if (_picked.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: Text('Dùng ICD: $_picked'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        widget.onSelected(_picked);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// v2.63.0: Picker ICD gợi ý multi-select + edit name (cho icdSuggest)
class IcdSuggestPicker extends StatefulWidget {
  /// List ICD đã chọn (text hiển thị)
  final List<String> initial;
  final ValueChanged<List<String>> onSelected;

  const IcdSuggestPicker({
    super.key,
    required this.initial,
    required this.onSelected,
  });

  @override
  State<IcdSuggestPicker> createState() => _IcdSuggestPickerState();
}

class _IcdSuggestPickerState extends State<IcdSuggestPicker> {
  final _searchCtrl = TextEditingController();
  List<CatalogItem> _results = [];
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initial);
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim();
    setState(() {
      _results = q.isEmpty
          ? []
          : HisCatalogService.instance.searchIcd(q, limit: 80);
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.medical_services, color: Colors.indigo, size: 22),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Chọn nhiều ICD (gợi ý)',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                          child: Text('${_selected.length}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Xong', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                          onPressed: () {
                            widget.onSelected(_selected);
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: 'Tìm ICD để thêm vào danh sách...',
                        hintStyle: const TextStyle(fontSize: 13),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => _searchCtrl.clear())
                            : null,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Chips đã chọn
              if (_selected.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  width: double.infinity,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selected.map((icd) {
                      return Chip(
                        label: Text(icd, style: const TextStyle(fontSize: 11)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () {
                          setState(() => _selected.remove(icd));
                        },
                        backgroundColor: Colors.indigo.shade50,
                        side: BorderSide(color: Colors.indigo.shade200),
                      );
                    }).toList(),
                  ),
                ),
              // Results
              Expanded(
                child: _searchCtrl.text.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text('Gõ để tìm ICD để thêm vào',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            ],
                          ),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Text('Không tìm thấy',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                            itemBuilder: (ctx, i) {
                              final item = _results[i];
                              final txt = '${item.code} - ${item.name}';
                              final isSelected = _selected.contains(txt);
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.indigo.shade100 : Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Center(
                                    child: Text(item.code,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.indigo.shade900 : Colors.indigo.shade700,
                                        )),
                                  ),
                                ),
                                title: Text(item.code,
                                    style: const TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.bold)),
                                subtitle: Text(item.name,
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                                trailing: isSelected
                                    ? const Icon(Icons.check_box, color: Colors.indigo, size: 20)
                                    : const Icon(Icons.add_box_outlined, color: Colors.grey, size: 20),
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selected.remove(txt);
                                    } else {
                                      _selected.add(txt);
                                    }
                                  });
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