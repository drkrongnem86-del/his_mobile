// Widget UserHeader - hiển thị tên user đăng nhập + role + dept + trạng thái kết nối.
// Dùng làm "nền" (persistent) trên mọi màn hình quan trọng theo yêu cầu của BS:
// "user ai đăng nhập hiện tên người đó trên nền luôn".
// v2.35.9: Online status lấy từ DataService (login thật qua Data, không qua Thongke).
import 'package:flutter/material.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/services/data_service.dart';

class UserHeader extends StatelessWidget {
  final String? username;
  final String? role;          // 'Bác sĩ', 'Điều dưỡng', ...
  final String? department;    // 'HSCC', 'HSTC', ...
  final bool compact;
  final bool showStatus;       // show Online/Offline pill

  const UserHeader({
    super.key,
    this.username,
    this.role,
    this.department,
    this.compact = false,
    this.showStatus = true,
  });

  /// Lấy user hiện tại từ DataService (preferred) hoặc ThongkeAuthService
  static UserHeader fromAuth({
    Key? key,
    String? department,
    bool compact = false,
  }) {
    // Ưu tiên Data (singleton) - user login thật ở đây
    final data = DataService.instance;
    final dataUser = data.user;
    if (dataUser != null && data.userName != null) {
      // Pick first role name
      String? roleName;
      if (dataUser.roles.isNotEmpty) {
        roleName = dataUser.roles.first.name;
      } else {
        roleName = 'Bác sĩ';
      }
      return UserHeader(
        key: key,
        username: dataUser.userName,
        role: roleName,
        department: department,
        compact: compact,
      );
    }
    // Fallback: ThongkeAuthService (HIS Pro VPN)
    final auth = ThongkeAuthService();
    final username = auth.currentUsername ?? 'Chưa đăng nhập';
    return UserHeader(
      key: key,
      username: username,
      role: 'Bác sĩ',
      department: department,
      compact: compact,
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Màu avatar dựa vào tên (deterministic)
  Color _avatarColor(String name) {
    final hash = name.codeUnits.fold(0, (a, b) => a + b);
    const palette = [
      Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFF00838F),
      Color(0xFFC62828), Color(0xFFAD1457), Color(0xFF2E7D32),
      Color(0xFFE65100), Color(0xFF5E35B1), Color(0xFF4527A0),
      Color(0xFF00695C), Color(0xFF283593), Color(0xFFD84315),
    ];
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final name = username ?? 'Khách';
    final isLoggedIn = name != 'Chưa đăng nhập' && name.isNotEmpty;
    // Online = DataService đang có accessToken (login thật qua Data)
    final isOnline = DataService.instance.isAuthenticated ||
        ThongkeAuthService().currentUsername != null;

    if (compact) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: isLoggedIn
                ? [_avatarColor(name).withOpacity(0.92), _avatarColor(name).withOpacity(0.65)]
                : [Colors.grey.shade700, Colors.grey.shade500],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.white24,
              child: Text(_initials(name), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isLoggedIn ? 'BS. $name' : name,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  if (department != null && department!.isNotEmpty)
                    Text('🏥 $department', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ),
            if (showStatus)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isOnline ? Colors.greenAccent.shade400 : Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.amber.shade900,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(isOnline ? 'Online' : 'Offline',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: isLoggedIn
              ? [_avatarColor(name), _avatarColor(name).withOpacity(0.78)]
              : [Colors.grey.shade700, Colors.grey.shade500],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          // Avatar lớn - in chữ cái đầu của tên
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white54, width: 2),
            ),
            child: Center(
              child: Text(
                _initials(name),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Thông tin user
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLoggedIn ? 'BS. $name' : name,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 4, runSpacing: 2,
                  children: [
                    if ((role ?? '').isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
                        child: Text(role!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    if ((department ?? '').isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
                        child: Text('🏥 $department', style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Status pill
          if (showStatus)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isOnline ? Colors.greenAccent.shade400 : Colors.amber.shade700,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isOnline ? Icons.cloud_done : Icons.cloud_off, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text(isOnline ? 'Data' : 'Offline',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
