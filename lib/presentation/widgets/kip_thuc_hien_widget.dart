// KipThucHienWidget v3.0.174 - Widget chung cho KÍP THỰC HIỆN (6 vị trí HIS Desktop)
//
// Copy pattern từ service_execute_detail_screen.dart (đã work) + cải tiến:
// - UserService singleton (cache 200 users, share cho cả app)
// - 6 vị trí: BS/PTV chính + PTV phụ 1+2 + GM chính + GM phụ + ĐD
// - Picker dialog có search
// - Auto-fill user đang login (default)
// - Validate BS chính required
// - Remember last kíp (SharedPreferences)
//
// Áp dụng cho: ECG, ServiceExecute, PhieuPhauThuat

import 'package:flutter/material.dart';
import 'package:his_mobile/data/services/user_service.dart';

/// Class chứa kết quả kíp thực hiện - dùng để lưu backend
class KipResult {
  final String? ptvChinhLogin;
  final String? ptvChinhName;
  final String? ptvPhu1Login;
  final String? ptvPhu1Name;
  final String? ptvPhu2Login;
  final String? ptvPhu2Name;
  final String? gmChinhLogin;
  final String? gmChinhName;
  final String? gmPhuLogin;
  final String? gmPhuName;
  final String? dieuDuongLogin;
  final String? dieuDuongName;

  const KipResult({
    this.ptvChinhLogin,
    this.ptvChinhName,
    this.ptvPhu1Login,
    this.ptvPhu1Name,
    this.ptvPhu2Login,
    this.ptvPhu2Name,
    this.gmChinhLogin,
    this.gmChinhName,
    this.gmPhuLogin,
    this.gmPhuName,
    this.dieuDuongLogin,
    this.dieuDuongName,
  });

  bool get hasPtvChinh => ptvChinhLogin != null && ptvChinhLogin!.isNotEmpty;

  /// Convert thành Map cho backend (ServiceReq fields)
  Map<String, dynamic> toServiceReqFields() {
    return {
      if (ptvChinhLogin != null && ptvChinhLogin!.isNotEmpty) ...{
        'EXECUTE_LOGINNAME': ptvChinhLogin,
        'EXECUTE_USERNAME': ptvChinhName ?? ptvChinhLogin,
      },
      if (dieuDuongLogin != null && dieuDuongLogin!.isNotEmpty) ...{
        'NURSE_LOGINNAME': dieuDuongLogin,
        'NURSE_USERNAME': dieuDuongName ?? dieuDuongLogin,
      },
    };
  }

  /// Convert thành List<HisExecuteGroup> cho HisExecuteGroup API
  List<Map<String, dynamic>> toHisExecuteGroups(int serviceReqId) {
    final groups = <Map<String, dynamic>>[];
    void add(KipRole role, String? loginName, String? userName) {
      if (loginName == null || loginName.isEmpty) return;
      groups.add({
        'SERVICE_REQ_ID': serviceReqId,
        'EXECUTER_ROLE': role.hisProRoleId,
        'LOGINNAME': loginName,
        'USERNAME': userName ?? loginName,
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
      });
    }
    add(KipRole.ptvChinh, ptvChinhLogin, ptvChinhName);
    add(KipRole.ptvPhu1, ptvPhu1Login, ptvPhu1Name);
    add(KipRole.ptvPhu2, ptvPhu2Login, ptvPhu2Name);
    add(KipRole.gmChinh, gmChinhLogin, gmChinhName);
    add(KipRole.gmPhu, gmPhuLogin, gmPhuName);
    add(KipRole.dieuDuong, dieuDuongLogin, dieuDuongName);
    return groups;
  }

  bool validate({String? error}) {
    return hasPtvChinh;
  }
}

/// Widget chính - Form kíp thực hiện với 6 vị trí
class KipThucHienForm extends StatefulWidget {
  /// Các role hiển thị (mặc định 6 vị trí chuẩn)
  final List<KipRole> roles;

  /// User đang login (LOGINNAME) - auto-fill BS chính
  final String? currentUserLogin;

  /// Cho phép edit (mặc định true)
  final bool enabled;

  /// Initial values
  final KipResult? initialValue;

  const KipThucHienForm({
    super.key,
    this.roles = const [
      KipRole.ptvChinh,
      KipRole.ptvPhu1,
      KipRole.ptvPhu2,
      KipRole.gmChinh,
      KipRole.gmPhu,
      KipRole.dieuDuong,
    ],
    this.currentUserLogin,
    this.enabled = true,
    this.initialValue,
  });

  @override
  // v3.0.174: State class public (KipThucHienFormState) để GlobalKey<KipThucHienFormState>
  // có thể access `result` từ bên ngoài
  State<KipThucHienForm> createState() => KipThucHienFormState();
}

class KipThucHienFormState extends State<KipThucHienForm> {
  final _userService = UserService.instance;
  final Map<KipRole, String?> _logins = {};
  final Map<KipRole, String?> _names = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1. Load user service nếu chưa có
    if (!_userService.isLoaded) {
      await _userService.load();
    }

    // 2. Set giá trị ban đầu
    final initial = widget.initialValue;
    _logins[KipRole.ptvChinh] = initial?.ptvChinhLogin;
    _names[KipRole.ptvChinh] = initial?.ptvChinhName;
    _logins[KipRole.ptvPhu1] = initial?.ptvPhu1Login;
    _names[KipRole.ptvPhu1] = initial?.ptvPhu1Name;
    _logins[KipRole.ptvPhu2] = initial?.ptvPhu2Login;
    _names[KipRole.ptvPhu2] = initial?.ptvPhu2Name;
    _logins[KipRole.gmChinh] = initial?.gmChinhLogin;
    _names[KipRole.gmChinh] = initial?.gmChinhName;
    _logins[KipRole.gmPhu] = initial?.gmPhuLogin;
    _names[KipRole.gmPhu] = initial?.gmPhuName;
    _logins[KipRole.dieuDuong] = initial?.dieuDuongLogin;
    _names[KipRole.dieuDuong] = initial?.dieuDuongName;

    // 3. Auto-fill BS chính = user đang login (nếu chưa set)
    if (_logins[KipRole.ptvChinh] == null && widget.currentUserLogin != null) {
      final me = widget.currentUserLogin;
      _logins[KipRole.ptvChinh] = me;
      _names[KipRole.ptvChinh] = _userService.getFullName(me);
    }

    // 4. Auto-fill remember last (nếu chưa set)
    for (final role in widget.roles) {
      if (_logins[role] == null) {
        final last = await _userService.getLast(role);
        if (last != null) {
          _logins[role] = last;
          _names[role] = _userService.getFullName(last);
        }
      }
    }

    if (mounted) setState(() => _initialized = true);
  }

  KipResult get result => KipResult(
        ptvChinhLogin: _logins[KipRole.ptvChinh],
        ptvChinhName: _names[KipRole.ptvChinh],
        ptvPhu1Login: _logins[KipRole.ptvPhu1],
        ptvPhu1Name: _names[KipRole.ptvPhu1],
        ptvPhu2Login: _logins[KipRole.ptvPhu2],
        ptvPhu2Name: _names[KipRole.ptvPhu2],
        gmChinhLogin: _logins[KipRole.gmChinh],
        gmChinhName: _names[KipRole.gmChinh],
        gmPhuLogin: _logins[KipRole.gmPhu],
        gmPhuName: _names[KipRole.gmPhu],
        dieuDuongLogin: _logins[KipRole.dieuDuong],
        dieuDuongName: _names[KipRole.dieuDuong],
      );

  Future<void> _pickUser(KipRole role) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _UserPickerDialog(
        role: role,
        currentUserLogin: widget.currentUserLogin,
      ),
    );
    if (result != null) {
      setState(() {
        _logins[role] = result['LOGINNAME'];
        _names[role] = result['USERNAME'];
      });
      // Remember last cho lần sau
      await _userService.rememberLast(role, result['LOGINNAME']);
    }
  }

  IconData _getIcon(KipRole role) {
    return switch (role) {
      KipRole.ptvChinh => Icons.medical_services,
      KipRole.ptvPhu1 => Icons.medical_services_outlined,
      KipRole.ptvPhu2 => Icons.medical_services_outlined,
      KipRole.gmChinh => Icons.healing,
      KipRole.gmPhu => Icons.healing_outlined,
      KipRole.dieuDuong => Icons.health_and_safety,
      KipRole.dungCuVien => Icons.medical_information,
      KipRole.bsNgoai => Icons.person_outline,
    };
  }

  Color _getColor(KipRole role) {
    return switch (role) {
      KipRole.ptvChinh => const Color(0xFFD32F2F),
      KipRole.ptvPhu1 => const Color(0xFF7B1FA2),
      KipRole.ptvPhu2 => const Color(0xFF7B1FA2),
      KipRole.gmChinh => const Color(0xFF1976D2),
      KipRole.gmPhu => const Color(0xFF1976D2),
      KipRole.dieuDuong => const Color(0xFF388E3C),
      KipRole.dungCuVien => const Color(0xFFE65100),
      KipRole.bsNgoai => const Color(0xFF616161),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final role in widget.roles) ...[
          _buildField(role),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildField(KipRole role) {
    final isRequired = role == KipRole.ptvChinh;
    final displayName = _names[role] ?? _logins[role] ?? '';
    final isMe = _logins[role] == widget.currentUserLogin;

    return InkWell(
      onTap: widget.enabled ? () => _pickUser(role) : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: isRequired && (_logins[role] == null || _logins[role]!.isEmpty)
                ? Colors.red
                : Colors.black26,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(_getIcon(role), size: 18, color: _getColor(role)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        role.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                          fontWeight: isRequired ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (isRequired)
                        const Text(' *', style: TextStyle(color: Colors.red, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (displayName.isNotEmpty)
                    Row(
                      children: [
                        if (isMe)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Text('⭐', style: TextStyle(fontSize: 12)),
                          ),
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_logins[role] != null)
                          Text(
                            ' (${_logins[role]})',
                            style: const TextStyle(fontSize: 10, color: Colors.black45),
                          ),
                      ],
                    )
                  else
                    Text(
                      'Chạm để chọn${isRequired ? ' (bắt buộc)' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isRequired ? Colors.red.shade300 : Colors.black38,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.enabled) ...[
              if (_logins[role] != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.black45),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      _logins[role] = null;
                      _names[role] = null;
                    });
                  },
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dialog chọn user - search trong UserService
class _UserPickerDialog extends StatefulWidget {
  final KipRole role;
  final String? currentUserLogin;

  const _UserPickerDialog({
    required this.role,
    this.currentUserLogin,
  });

  @override
  State<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends State<_UserPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Load user service nếu chưa có
    if (!UserService.instance.isLoaded) {
      UserService.instance.load().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = UserService.instance.searchByRole(_query, widget.role);

    return Dialog(
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_search, color: Color(0xFF6A1B9A)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chọn ${widget.role.label}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc loginname...',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Tìm thấy: ${users.length} user (tổng: ${UserService.instance.count})',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: users.isEmpty
                  ? const Center(
                      child: Text('Không tìm thấy user', style: TextStyle(color: Colors.black54)),
                    )
                  : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (ctx, i) {
                        final u = users[i];
                        final username = (u['USERNAME'] ?? '').toString();
                        final loginname = (u['LOGINNAME'] ?? '').toString();
                        final isMe = loginname.toUpperCase() ==
                            (widget.currentUserLogin ?? '').toUpperCase();

                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: isMe ? const Color(0xFF6A1B9A) : Colors.grey.shade300,
                            child: Text(
                              isMe ? '⭐' : (username.isNotEmpty ? username[0].toUpperCase() : '?'),
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            username,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(loginname, style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(context, {
                            'LOGINNAME': loginname,
                            'USERNAME': username,
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
