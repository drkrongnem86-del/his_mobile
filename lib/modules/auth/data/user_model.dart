import 'package:equatable/equatable.dart';

/// User model - Người dùng HIS Pro
class User extends Equatable {
  final String id;
  final String loginName;
  final String userName;
  final String? email;
  final String? phone;
  final String? departmentId;
  final String? departmentName;
  final String? roomId;
  final String? roomName;
  final String? position;
  final List<String> roles;
  final List<String> permissions;
  final bool isActive;

  const User({
    required this.id,
    required this.loginName,
    required this.userName,
    this.email,
    this.phone,
    this.departmentId,
    this.departmentName,
    this.roomId,
    this.roomName,
    this.position,
    this.roles = const [],
    this.permissions = const [],
    this.isActive = true,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['ID']?.toString() ?? json['id']?.toString() ?? '',
      loginName: json['LOGINNAME'] ?? json['loginName'] ?? json['username'] ?? '',
      userName: json['USERNAME'] ?? json['userName'] ?? json['name'] ?? '',
      email: json['EMAIL'] ?? json['email'],
      phone: json['PHONE'] ?? json['phone'],
      departmentId: json['DEPARTMENT_ID']?.toString() ?? json['departmentId']?.toString(),
      departmentName: json['DEPARTMENT_NAME'] ?? json['departmentName'],
      roomId: json['ROOM_ID']?.toString() ?? json['roomId']?.toString(),
      roomName: json['ROOM_NAME'] ?? json['roomName'],
      position: json['POSITION'] ?? json['position'],
      roles: _parseList(json['ROLES'] ?? json['roles']),
      permissions: _parseList(json['PERMISSIONS'] ?? json['permissions']),
      isActive: json['IS_ACTIVE'] == '1' || json['IS_ACTIVE'] == 1 || json['isActive'] == true,
    );
  }

  static List<String> _parseList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String) return value.split(',').where((s) => s.isNotEmpty).toList();
    return [];
  }

  Map<String, dynamic> toJson() => {
    'ID': id,
    'LOGINNAME': loginName,
    'USERNAME': userName,
    'EMAIL': email,
    'PHONE': phone,
    'DEPARTMENT_ID': departmentId,
    'DEPARTMENT_NAME': departmentName,
    'ROOM_ID': roomId,
    'ROOM_NAME': roomName,
    'POSITION': position,
    'ROLES': roles.join(','),
    'IS_ACTIVE': isActive ? '1' : '0',
  };

  @override
  List<Object?> get props => [id, loginName, userName, departmentId];
}

/// Login Request
class LoginRequest {
  final String loginName;
  final String password;
  final String? deviceId;
  final String? deviceName;

  LoginRequest({required this.loginName, required this.password, this.deviceId, this.deviceName});

  Map<String, dynamic> toJson() => {
    'LOGINNAME': loginName,
    'PASSWORD': password,
    'DEVICE_ID': deviceId,
    'DEVICE_NAME': deviceName,
  };
}

/// Login Response
class LoginResponse {
  final String? token;
  final String? refreshToken;
  final User? user;
  final String? message;
  final bool success;

  LoginResponse({this.token, this.refreshToken, this.user, this.message, this.success = false});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['TOKEN'] ?? json['token'],
      refreshToken: json['REFRESH_TOKEN'] ?? json['refreshToken'],
      user: json['USER_DATA'] != null ? User.fromJson(json['USER_DATA'])
           : json['user'] != null ? User.fromJson(json['user']) : null,
      message: json['MESSAGE'] ?? json['message'],
      success: json['SUCCESS'] == true || json['success'] == true || json['SUCCESS'] == 'true',
    );
  }
}
