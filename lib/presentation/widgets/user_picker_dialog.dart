// UserPickerDialog v3.0.171 - Shared dialog chọn user từ HIS Pro
//
// Được dùng chung bởi:
// - service_execute_detail_screen.dart (Phòng thủ thuật HSCC - Xử lý yêu cầu)
// - ecg_execute_screen.dart (Thực hiện ECG)
//
// Trước đây: _UserPickerDialog chỉ ở service_execute_detail_screen.dart
// v3.0.171: Extract ra shared widget để ECG cũng dùng chung (search filter)
//
// Flow:
// - Load danh sách user theo role + department (api/HisExecuteRoleUser/Get)
// - Search theo tên / loginname (substring, case-insensitive)
// - Trả về (username, fullName) cho callback

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:his_mobile/data/api/his_api_service.dart';

/// Kết quả trả về khi user chọn
class UserPickResult {
  final String loginName;   // LOGINNAME (dùng cho backend)
  final String fullName;    // USERNAME (tên đầy đủ Tiếng Việt)
  final String? department; // Optional - tên khoa

  const UserPickResult({
    required this.loginName,
    required this.fullName,
    this.department,
  });
}

class UserPickerDialog extends StatefulWidget {
  final HisApiService api;
  final int departmentId;
  final String title;
  final String? defaultLoginName;  // pre-select user (optional)
  final void Function(UserPickResult result) onSelected;

  const UserPickerDialog({
    super.key,
    required this.api,
    required this.departmentId,
    required this.title,
    required this.onSelected,
    this.defaultLoginName,
  });

  @override
  State<UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends State<UserPickerDialog> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Load users từ api/AcsUser/Get (port 1401) - giống ECG dropdown
  /// v3.0.175: Chuyển từ getExecuteRoleUsers (port 1425 MCH, trả 0 user) sang getAcsUsers
  ///   Lý do: getExecuteRoleUsers gọi api/HisExecuteUser/GetView ở OCR port 1425
  ///   → cho HSCC dept=22 trả 0 user (HIS Pro MCH không có mapping role/execute)
  ///   → getAcsUsers gọi api/AcsUser/Get ở ACS port 1401
  ///   → trả đúng 200 user thuộc HSCC (đã verify với ECG dropdown)
  /// Filter theo department (mặc định 22 = HSCC)
  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAcsUsers(departmentId: widget.departmentId, limit: 200);
      if (res.success && res.data is List) {
        _users = List<Map<String, dynamic>>.from(res.data);
      } else if (res.success && res.data is Map && (res.data as Map)['Data'] is List) {
        _users = List<Map<String, dynamic>>.from((res.data as Map)['Data']);
      }
      debugPrint('👥 [UserPicker] getAcsUsers loaded ${_users.length} users for dept ${widget.departmentId}');
    } catch (e) {
      debugPrint('❌ [UserPicker] getAcsUsers _loadUsers error: $e');
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? _users
        : _users.where((u) {
            final name = (u['USERNAME'] ?? u['LOGINNAME'] ?? u['username'] ?? '').toString().toLowerCase();
            final login = (u['LOGINNAME'] ?? u['loginname'] ?? '').toString().toLowerCase();
            final q = _search.toLowerCase();
            return name.contains(q) || login.contains(q);
          }).toList();

    return Dialog(
      child: Container(
        width: 420,
        height: 520,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.person_search, color: Color(0xFF6A1B9A)),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Tìm theo tên hoặc loginname...',
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(
              child: Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            )
          else if (filtered.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _search.isEmpty ? 'Không có user' : 'Không tìm thấy "${_search}"',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final u = filtered[i];
                  final login = (u['LOGINNAME'] ?? u['USERNAME'] ?? u['username'] ?? u['loginname'] ?? '').toString();
                  final full = (u['USERNAME'] ?? u['username'] ?? u['fullName'] ?? login).toString();
                  final dept = (u['DEPARTMENT_NAME'] ?? u['department_name'] ?? '').toString();
                  final isSelected = widget.defaultLoginName != null && login == widget.defaultLoginName;
                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                      child: Text(
                        login.isNotEmpty ? login[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6A1B9A), fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(full, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '$login${dept.isNotEmpty ? " • $dept" : ""}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF6A1B9A)) : null,
                    onTap: () {
                      widget.onSelected(UserPickResult(
                        loginName: login,
                        fullName: full,
                        department: dept.isEmpty ? null : dept,
                      ));
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Tổng: ${filtered.length} user',
              style: const TextStyle(fontSize: 10, color: Colors.black45),
            ),
          ),
        ]),
      ),
    );
  }
}
