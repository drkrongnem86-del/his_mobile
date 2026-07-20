// v3.0.59: Network Discovery Service
// Tự động scan subnet tìm HIS Pro server (thay vì hardcode IP)
// - Scan các subnet phổ biến: 171.15.0.x, 172.16.0.x, 192.168.0.x
// - Mỗi IP thử gọi /api/AcsToken/Authorize hoặc /health endpoint
// - Trả về danh sách IP có thể là HIS Pro server

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';

class DiscoveredServer {
  final String ip;
  final int responseTimeMs;
  final String? serverVersion;
  final String? serviceTag;  // 'ACS' / 'EMR' / 'FSS' / 'unknown'

  DiscoveredServer({
    required this.ip,
    required this.responseTimeMs,
    this.serverVersion,
    this.serviceTag,
  });

  @override
  String toString() => '$ip (${responseTimeMs}ms)';
}

class NetworkDiscoveryService {
  static final NetworkDiscoveryService instance = NetworkDiscoveryService._();
  NetworkDiscoveryService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: const Duration(seconds: 2),
    headers: {'User-Agent': 'HIS-Mobile-Discovery/3.0.59'},
  ));

  /// Subnet prefixes để scan (BV Ninh Thuận dùng 171.15.x và 172.16.x)
  static const List<String> _subnetPrefixes = [
    '171.15.0.',
    '171.15.128.',
    '172.16.0.',
    '172.16.9.',
    '172.16.1.',
    '192.168.1.',
    '192.168.0.',
  ];

  /// Scan 1 IP với 1 port - trả về DiscoveredServer nếu thành công, null nếu fail
  Future<DiscoveredServer?> _probeIp(String ip, int port, {Duration? timeout}) async {
    final sw = Stopwatch()..start();
    try {
      final response = await _dio.get(
        'http://$ip:$port/',
        options: Options(
          validateStatus: (s) => s != null && s < 500,  // Accept 2xx, 3xx, 4xx (server alive)
        ),
      );
      sw.stop();
      final body = response.data?.toString() ?? '';
      // Check HIS Pro signature (HTML title, version string, etc.)
      String? version;
      String tag = 'unknown';
      if (body.contains('HIS') || body.contains('Inventec')) {
        tag = 'HIS';
      }
      if (body.contains('1.55.0') || body.contains('2.406.0') || body.contains('1.164.0')) {
        version = body.contains('1.164.0') ? 'EMR 1.164.0' : 'HIS 2.406.0';
      }
      return DiscoveredServer(
        ip: '$ip:$port',
        responseTimeMs: sw.elapsedMilliseconds,
        serverVersion: version,
        serviceTag: tag,
      );
    } catch (e) {
      // Timeout, connection refused, etc. - server not alive on this IP
      return null;
    }
  }

  /// Scan 1 subnet prefix - thử 254 host × 1 port (chậm - dùng parallel)
  Future<List<DiscoveredServer>> scanSubnet(String prefix, {int port = 1401, int concurrency = 20}) async {
    debugPrint('[Discovery] Scanning $prefix* port $port ...');
    final results = <DiscoveredServer>[];
    final batch = <Future<DiscoveredServer?>>[];

    for (int i = 1; i < 255; i++) {
      final ip = '$prefix$i';
      batch.add(_probeIp(ip, port));
      // Process batch when reach concurrency limit
      if (batch.length >= concurrency) {
        final probed = await Future.wait(batch);
        for (final r in probed) {
          if (r != null) results.add(r);
        }
        batch.clear();
      }
    }
    // Process remaining
    if (batch.isNotEmpty) {
      final probed = await Future.wait(batch);
      for (final r in probed) {
        if (r != null) results.add(r);
      }
    }
    debugPrint('[Discovery] Found ${results.length} servers in $prefix*');
    return results;
  }

  /// Scan tất cả subnet prefixes - parallel
  /// Trả về list DiscoveredServer sắp xếp theo response time (nhanh nhất trước)
  Future<List<DiscoveredServer>> scanAll({int port = 1401}) async {
    final all = await Future.wait(
      _subnetPrefixes.map((p) => scanSubnet(p, port: port)),
    );
    final flat = <DiscoveredServer>[];
    for (final list in all) {
      flat.addAll(list);
    }
    flat.sort((a, b) => a.responseTimeMs.compareTo(b.responseTimeMs));
    return flat;
  }

  /// Quick check 1 IP - dùng để verify trước khi lưu
  Future<bool> quickCheck(String host, {int port = 1401}) async {
    final result = await _probeIp(host, port);
    return result != null;
  }
}
