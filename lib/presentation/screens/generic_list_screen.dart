import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:his_mobile/core/menu_config.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:his_mobile/data/api/his_api_service.dart';

/// Generic list screen - hiển thị danh sách từ bất kỳ API + back button
class GenericListScreen extends StatefulWidget {
  final MenuItem menu;

  const GenericListScreen({super.key, required this.menu});

  @override
  State<GenericListScreen> createState() => _GenericListScreenState();
}

class _GenericListScreenState extends State<GenericListScreen> {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _encode(Map<String, dynamic> apiData) {
    final param = jsonEncode({
      'CommonParam': {
        'Messages': <dynamic>[],
        'BugCodes': <dynamic>[],
        'MessageCodes': <dynamic>[],
        'Start': 0,
        'Limit': 100,
        'LanguageCode': 'VI',
        'Now': 0,
        'HasException': false,
      },
      'ApiData': apiData,
    });
    return base64Encode(utf8.encode(param));
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final param = _encode(widget.menu.filter);

      final response = await _dio.get(
        '${widget.menu.baseUrl}/${widget.menu.apiEndpoint}',
        queryParameters: {'param': param},
        options: Options(
          receiveTimeout: Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = {};
        if (response.data is Map) {
          data = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try { data = jsonDecode(response.data); } catch (e) {}
        }

        if (data['Success'] == true && data['Data'] is List) {
          _items = List<Map<String, dynamic>>.from(data['Data']);
        } else {
          _error = 'API không trả dữ liệu';
        }
      } else {
        _error = 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      _error = e.toString().substring(0, e.toString().length.clamp(0, 100));
    }

    setState(() {
      _loading = false;
    });
  }

  String _formatValue(dynamic v) {
    if (v == null) return '';
    if (v is bool) return v ? 'Có' : 'Không';
    if (v is List) return v.map((e) => e.toString()).join(', ');
    return v.toString();
  }

  List<MapEntry<String, String>> _getDisplayFields(Map<String, dynamic> item) {
    final priority = [
      'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME', 'PATIENT_NAME', 'VIR_PATIENT_NAME',
      'TDL_TREATMENT_CODE', 'TREATMENT_CODE', 'SERVICE_REQ_CODE',
      'MEDICINE_TYPE_NAME', 'DRUG_NAME',
      'TDL_PATIENT_CODE', 'TDL_HEIN_CARD_NUMBER',
      'INTRUCTION_TIME', 'CREATE_TIME', 'MODIFY_TIME',
      'TDL_PATIENT_DOB', 'DEPARTMENT_NAME', 'ROOM_NAME',
      'CODE', 'NAME', 'TITLE',
    ];

    final fields = <MapEntry<String, String>>[];
    for (final key in priority) {
      final value = item[key];
      if (value != null && value.toString().isNotEmpty && value.toString() != 'null') {
        fields.add(MapEntry(key, _formatValue(value)));
      }
      if (fields.length >= 3) break;
    }

    return fields;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.safePop(),
          tooltip: 'Quay lại',
        ),
        title: Row(
          children: [
            Icon(widget.menu.icon, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.menu.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Làm mới', onPressed: _loadData),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 12),
              Text('Lỗi: $_error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Text('Endpoint: ${widget.menu.apiEndpoint}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 60, color: Colors.grey),
            SizedBox(height: 12),
            Text('Chưa có dữ liệu', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          final fields = _getDisplayFields(item);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.indigo.shade100,
                child: Icon(widget.menu.icon, size: 16, color: Colors.indigo.shade700),
              ),
              title: fields.isNotEmpty
                  ? Text(fields.first.value,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis)
                  : Text('ID: ${item['ID']?.toString() ?? "N/A"}',
                      style: const TextStyle(fontSize: 12)),
              subtitle: fields.length > 1
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: fields.skip(1).take(2).map((e) {
                        return Text('${_labelFormat(e.key)}: ${e.value}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11));
                      }).toList(),
                    )
                  : null,
              trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
              dense: true,
            ),
          );
        },
      ),
    );
  }

  String _labelFormat(String key) {
    return key.replaceAll('TDL_', '').replaceAll('_', ' ').toLowerCase();
  }
}
