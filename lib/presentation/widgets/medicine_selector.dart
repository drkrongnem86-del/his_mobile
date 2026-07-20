// MedicineSelector.dart v2.55.0
// Chọn thuốc từ HisCatalogService (32k+) + nhập liều/cách dùng
// Cho phép thêm nhiều thuốc, mỗi thuốc có dosage (số lần/ngày) + instruction

import 'package:flutter/material.dart';
import 'package:his_mobile/data/api/his_catalog_service.dart';

class PrescriptionItem {
  final CatalogItem medicine;
  final double amountPerDose;  // e.g. 1 viên, 2ml
  final int timesPerDay;       // e.g. 2, 3, 4 lần/ngày
  final int totalDays;         // e.g. 5, 7 ngày
  final String route;          // uống, tiêm, bôi, ...
  final String note;           // ghi chú

  PrescriptionItem({
    required this.medicine,
    this.amountPerDose = 1,
    this.timesPerDay = 2,
    this.totalDays = 5,
    this.route = 'Uống',
    this.note = '',
  });

  PrescriptionItem copyWith({
    double? amountPerDose,
    int? timesPerDay,
    int? totalDays,
    String? route,
    String? note,
  }) =>
      PrescriptionItem(
        medicine: medicine,
        amountPerDose: amountPerDose ?? this.amountPerDose,
        timesPerDay: timesPerDay ?? this.timesPerDay,
        totalDays: totalDays ?? this.totalDays,
        route: route ?? this.route,
        note: note ?? this.note,
      );

  int get totalQuantity =>
      (amountPerDose * timesPerDay * totalDays).round();

  String get displaySummary =>
      '${amountPerDose.toStringAsFixed(amountPerDose % 1 == 0 ? 0 : 1)} $route × ${timesPerDay} lần/ngày × $totalDays ngày (= $totalQuantity ${medicine.unit ?? ''})';

  @override
  String toString() => '${medicine.code} - ${medicine.name}\n  $displaySummary${note.isNotEmpty ? '\n  Ghi chú: $note' : ''}';
}

class MedicineSelector extends StatefulWidget {
  final List<PrescriptionItem> items;
  final ValueChanged<List<PrescriptionItem>> onChanged;

  const MedicineSelector({
    super.key,
    required this.items,
    required this.onChanged,
  });

  @override
  State<MedicineSelector> createState() => _MedicineSelectorState();
}

class _MedicineSelectorState extends State<MedicineSelector> {
  final _searchCtrl = TextEditingController();
  List<CatalogItem> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _search('');
  }

  void _onSearch() => _search(_searchCtrl.text);

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    final results = HisCatalogService.instance.searchMedicines(q, limit: 50);
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  void _addMedicine(CatalogItem m) {
    setState(() {
      widget.onChanged([...widget.items, PrescriptionItem(medicine: m)]);
      _searchCtrl.clear();
      _search('');
    });
  }

  void _removeItem(int idx) {
    setState(() {
      final list = [...widget.items];
      list.removeAt(idx);
      widget.onChanged(list);
    });
  }

  Future<void> _editItem(int idx) async {
    final item = widget.items[idx];
    final result = await showModalBottomSheet<PrescriptionItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => _MedicineEditSheet(item: item),
    );
    if (result != null) {
      setState(() {
        final list = [...widget.items];
        list[idx] = result;
        widget.onChanged(list);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.fold<double>(0, (sum, it) {
      // Approximate price = totalQuantity * unit price (if available)
      return sum;
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.medication, color: Colors.teal, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Đơn thuốc',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                if (widget.items.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${widget.items.length} thuốc',
                        style: const TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          // Selected items
          if (widget.items.isNotEmpty) ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final it = widget.items[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.withOpacity(0.15),
                    child: const Icon(Icons.medication, color: Colors.teal, size: 18),
                  ),
                  title: Text(it.medicine.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(it.displaySummary,
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: Colors.indigo),
                        onPressed: () => _editItem(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                        onPressed: () => _removeItem(i),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 8),
          ],
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm thuốc (Paracetamol, Amoxicillin...)',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          // Search results
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_searchResults.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Chưa có dữ liệu thuốc. Bấm "Tải lại" ở dưới.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final item = _searchResults[i];
                  final already = widget.items.any((p) => p.medicine.code == item.code);
                  return ListTile(
                    dense: true,
                    title: Text(item.code, style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold)),
                    subtitle: Text(item.name,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    trailing: already
                        ? const Icon(Icons.check_circle, color: Colors.teal)
                        : const Icon(Icons.add_circle_outline, color: Colors.indigo),
                    onTap: already ? null : () => _addMedicine(item),
                  );
                },
              ),
            ),
          // Footer
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text('Tổng: ${widget.items.length} thuốc',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await HisCatalogService.instance.refreshAll();
                    _search(_searchCtrl.text);
                  },
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Tải lại'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}

class _MedicineEditSheet extends StatefulWidget {
  final PrescriptionItem item;
  const _MedicineEditSheet({required this.item});

  @override
  State<_MedicineEditSheet> createState() => _MedicineEditSheetState();
}

class _MedicineEditSheetState extends State<_MedicineEditSheet> {
  late TextEditingController _amountCtrl;
  late TextEditingController _timesCtrl;
  late TextEditingController _daysCtrl;
  late TextEditingController _routeCtrl;
  late TextEditingController _noteCtrl;

  static const _commonRoutes = ['Uống', 'Tiêm bắp', 'Tiêm TM', 'Tiêm SC', 'Bôi ngoài da', 'Nhỏ mắt', 'Xông hít', 'Đặt hậu môn'];

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.item.amountPerDose.toString());
    _timesCtrl = TextEditingController(text: widget.item.timesPerDay.toString());
    _daysCtrl = TextEditingController(text: widget.item.totalDays.toString());
    _routeCtrl = TextEditingController(text: widget.item.route);
    _noteCtrl = TextEditingController(text: widget.item.note);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item.medicine.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text(widget.item.medicine.code,
              style: const TextStyle(fontSize: 12, color: Colors.teal)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Liều/lần',
                    hintText: '1',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _timesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Lần/ngày',
                    hintText: '2',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _daysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số ngày',
                    hintText: '5',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _routeCtrl,
            decoration: const InputDecoration(
              labelText: 'Cách dùng',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final r in _commonRoutes)
                ActionChip(
                  label: Text(r, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _routeCtrl.text = r;
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Ghi chú (tùy chọn)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    final newItem = widget.item.copyWith(
                      amountPerDose: double.tryParse(_amountCtrl.text) ?? 1,
                      timesPerDay: int.tryParse(_timesCtrl.text) ?? 2,
                      totalDays: int.tryParse(_daysCtrl.text) ?? 5,
                      route: _routeCtrl.text.isNotEmpty ? _routeCtrl.text : 'Uống',
                      note: _noteCtrl.text,
                    );
                    Navigator.pop(context, newItem);
                  },
                  child: const Text('Lưu'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _timesCtrl.dispose();
    _daysCtrl.dispose();
    _routeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }
}
