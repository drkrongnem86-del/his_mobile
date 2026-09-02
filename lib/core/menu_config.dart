import 'package:flutter/material.dart';

/// Menu items từ app AEquitas gốc
class MenuItem {
  final String title;
  final IconData icon;
  final String apiEndpoint;
  final String baseUrl;
  final Map<String, dynamic> filter;
  final String description;

  MenuItem({
    required this.title,
    required this.icon,
    required this.apiEndpoint,
    required this.baseUrl,
    required this.filter,
    this.description = '',
  });
}

class AequitasMenu {
  static const int ROOM_ID_CAP_CUU = 39;
  static const int DEPARTMENT_ID_CAP_CUU = 22;

  static List<MenuItem> getAll() {
    final today = DateTime.now();
    final dateLong = today.year * 10000000000 +
        today.month * 100000000 +
        today.day * 1000000;

    return [
      // Bảng điều khiển
      MenuItem(
        title: 'Thực hiện y lệnh',
        icon: Icons.assignment_turned_in,
        apiEndpoint: 'api/HisServiceReq/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {
          'EXECUTE_ROOM_ID': ROOM_ID_CAP_CUU,
          'INTRUCTION_DATE__EQUAL': dateLong,
          'SERVICE_REQ_STT_IDs': [1, 2],
          'LIMIT': 50,
        },
        description: 'Danh sách y lệnh đang chờ thực hiện',
      ),
      MenuItem(
        title: 'Lịch sử quét Barcode',
        icon: Icons.qr_code_scanner,
        apiEndpoint: 'api/HisSereServ/BarcodeHistory',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Lịch sử quét mã vạch',
      ),
      MenuItem(
        title: 'Phiếu thực hiện thuốc',
        icon: Icons.medication,
        apiEndpoint: 'api/HisExpMest/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 50, 'IS_ACTIVE': 1},
        description: 'Phiếu xuất thuốc',
      ),
      MenuItem(
        title: 'Danh sách phiếu điều dưỡng',
        icon: Icons.list_alt,
        apiEndpoint: 'api/HisCare/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 50},
        description: 'Phiếu chăm sóc điều dưỡng',
      ),
      MenuItem(
        title: 'Phiếu chăm sóc',
        icon: Icons.medical_services,
        apiEndpoint: 'api/HisCareDetail/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Chi tiết phiếu chăm sóc',
      ),
      MenuItem(
        title: 'Danh sách thu hồi thuốc',
        icon: Icons.undo,
        apiEndpoint: 'api/HisImpMest/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30, 'IS_ACTIVE': 1},
        description: 'Phiếu thu hồi thuốc',
      ),
      MenuItem(
        title: 'Phiếu bàn giao bệnh nhân chuyển khoa',
        icon: Icons.swap_horiz,
        apiEndpoint: 'api/HisTreatmentLog/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Lịch sử chuyển khoa',
      ),
      MenuItem(
        title: 'Bàn giao thuốc',
        icon: Icons.swap_horizontal_circle,
        apiEndpoint: 'api/HisMestShift/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Bàn giao ca thuốc',
      ),
      MenuItem(
        title: 'Bàn giao bệnh nhân',
        icon: Icons.people,
        apiEndpoint: 'api/HisTreatmentBed/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30, 'IS_ACTIVE': 1},
        description: 'Bàn giao ca bệnh nhân',
      ),

      // Theo dõi
      MenuItem(
        title: 'Chỉ số sinh tồn',
        icon: Icons.favorite,
        apiEndpoint: 'api/HisDhst/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {
          'EXECUTE_ROOM_ID': ROOM_ID_CAP_CUU,
          'EXECUTE_DATE__EQUAL': dateLong,
          'LIMIT': 50,
        },
        description: 'Theo dõi sinh hiệu bệnh nhân',
      ),
      MenuItem(
        title: 'Truyền dịch',
        icon: Icons.water_drop,
        apiEndpoint: 'api/HisInfusion/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Theo dõi truyền dịch',
      ),
      MenuItem(
        title: 'Theo dõi sau mổ',
        icon: Icons.healing,
        apiEndpoint: 'api/HisSurgPost/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Theo dõi sau phẫu thuật',
      ),
      MenuItem(
        title: 'Phiếu sàng lọc dinh dưỡng',
        icon: Icons.restaurant_menu,
        apiEndpoint: 'api/HisNutritionScreening/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Sàng lọc dinh dưỡng',
      ),
      MenuItem(
        title: 'Phiếu đánh giá dinh dưỡng',
        icon: Icons.assessment,
        apiEndpoint: 'api/HisNutrition/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Đánh giá dinh dưỡng',
      ),
      MenuItem(
        title: 'Bảng kê tổng hợp',
        icon: Icons.summarize,
        apiEndpoint: 'api/HisTreatment/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {
          'DEPARTMENT_ID': DEPARTMENT_ID_CAP_CUU,
          'LIMIT': 50,
        },
        description: 'Bảng kê tổng hợp bệnh nhân',
      ),
      MenuItem(
        title: 'Phiếu công khai thuốc',
        icon: Icons.fact_check,
        apiEndpoint: 'api/HisMedicinePublic/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Công khai thuốc sử dụng',
      ),

      // Điều dưỡng
      MenuItem(
        title: 'Tạo phiếu đi buồng',
        icon: Icons.directions_walk,
        apiEndpoint: 'api/HisTracking/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Phiếu đi buồng',
      ),
      MenuItem(
        title: 'Chuyển khoa',
        icon: Icons.compare_arrows,
        apiEndpoint: 'api/HisDepartment/Get',
        baseUrl: 'http://172.16.9.6:1429',  // v3.0.62: 1408 → 1429 (theo HIS_ICU v2.35.13)
        filter: {'IS_ACTIVE': 1, 'LIMIT': 50},
        description: 'Danh sách khoa phòng',
      ),
      MenuItem(
        title: 'Tiền sử dị ứng',
        icon: Icons.warning,
        apiEndpoint: 'api/HisAllergenic/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 50},
        description: 'Tiền sử dị ứng bệnh nhân',
      ),

      // Bệnh án
      MenuItem(
        title: 'Chỉ định dịch vụ',
        icon: Icons.medical_information,
        apiEndpoint: 'api/HisServiceReq/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {
          'REQUEST_DEPARTMENT_ID': DEPARTMENT_ID_CAP_CUU,
          'LIMIT': 30,
        },
        description: 'Danh sách chỉ định dịch vụ',
      ),
      MenuItem(
        title: 'Kê đơn dược',
        icon: Icons.receipt_long,
        apiEndpoint: 'api/HisPrescription/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Đơn thuốc',
      ),
      MenuItem(
        title: 'Xem bệnh án',
        icon: Icons.folder_shared,
        apiEndpoint: 'api/HisEmr/Get',
        baseUrl: 'http://172.16.9.6:1417',
        filter: {'IS_ACTIVE': 1, 'LIMIT': 30},
        description: 'Bệnh án điện tử',
      ),
      MenuItem(
        title: 'Scan tài liệu',
        icon: Icons.document_scanner,
        apiEndpoint: 'api/HisDocument/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Tài liệu scan',
      ),

      // Văn bản
      MenuItem(
        title: 'Văn bản chờ ký',
        icon: Icons.draw,
        apiEndpoint: 'api/HisDocumentSigned/Get',
        baseUrl: 'http://172.16.9.6:1429',
        filter: {'LIMIT': 30},
        description: 'Văn bản chờ ký duyệt',
      ),
    ];
  }
}
