/// Patient data hardcode SẴN TRONG APP (không gọi Thongke) - theo yêu cầu BS.
/// Dữ liệu dựa trên HIS Pro logs + Thongke sample names + tên Việt Nam phổ biến.
/// Mỗi khoa có 5-30 BN mẫu với thông tin y tế thực tế.
///
/// v2.15: Thay vì gọi API Thongke, tất cả patient list LẤY TỪ APP CODE này
/// → rõ ràng, không phụ thuộc server, không cần internet, không cần login.
class PatientSeed {
  PatientSeed._();

  /// Họ phổ biến Việt Nam
  static const _hoList = [
    'NGUYỄN', 'TRẦN', 'LÊ', 'PHẠM', 'HOÀNG', 'HUỲNH', 'VÕ', 'PHAN',
    'VŨ', 'ĐẶNG', 'BÙI', 'ĐỖ', 'HỒ', 'NGÔ', 'DƯƠNG', 'LÝ',
    'MAI', 'TRƯƠNG', 'ĐINH', 'ĐOÀN', 'LƯU', 'TRỊNH', 'CHU', 'TÔ',
  ];

  /// Đệm + Tên phổ biến
  static const _tenList = [
    'Văn A', 'Thị B', 'Văn C', 'Thị D', 'Văn E', 'Thị F',
    'Minh', 'Hương', 'Hùng', 'Lan', 'Hải', 'Hoa', 'Bình', 'Yến',
    'Khánh', 'Linh', 'Tú', 'Mai', 'Trang', 'Phương', 'Quang', 'Hà',
    'Sơn', 'Tùng', 'Lâm', 'Vy', 'Ngân', 'Tâm', 'Phúc', 'Thảo',
    'Ngọc', 'Anh', 'Diệu', 'Hiếu', 'Trinh', 'Khoa', 'Phú', 'Cường',
    'Tiến', 'Duy', 'Long', 'Khanh', 'Toàn', 'Thắng', 'Sang', 'Bảo',
    'Thư', 'Uyên', 'Quyên', 'Chi', 'Giang', 'Nhung', 'Thủy', 'Hà',
  ];

  /// ICD codes thường gặp tại BVĐK Ninh Thuận - ICU/Cấp cứu
  static const _icdList = [
    ('I10', 'Tăng huyết áp'),
    ('I21', 'Nhồi máu cơ tim cấp'),
    ('I50', 'Suy tim'),
    ('I63', 'Nhồi máu não'),
    ('J18', 'Viêm phổi'),
    ('J44', 'COPD đợt cấp'),
    ('J96', 'Suy hô hấp'),
    ('K29', 'Viêm dạ dày'),
    ('K92', 'Xuất huyết tiêu hóa'),
    ('A09', 'Tiêu chảy nhiễm trùng'),
    ('A90', 'Sốt xuất huyết Dengue'),
    ('S06', 'Chấn thương sọ não'),
    ('S22', 'Gãy xương sườn'),
    ('S72', 'Gãy xương đùi'),
    ('T78', 'Sốc phản vệ'),
    ('E11', 'Đái tháo đường typ 2'),
    ('N17', 'Suy thận cấp'),
    ('N18', 'Suy thận mạn'),
    ('E10', 'Đái tháo đường typ 1'),
    ('G40', 'Động kinh'),
  ];

  /// Sinh một map BN mẫu với format đầy đủ
  static Map<String, dynamic> _makePatient({
    required int id,
    required String name,
    required String code,
    required String treatmentCode,
    required String dob,
    required String gender,
    required String deptCode,
    required String deptName,
    required String icdCode,
    required String icdName,
    required String bed,
    required String room,
    String heinCard = '',
    String phone = '',
    String address = 'Ninh Thuận',
    String inTime = '04/07/2026',
    bool isBHYT = true,
  }) {
    return {
      'ID': id,
      'id': id,  // v2.79.0: lowercase cho consistency
      'TDL_PATIENT_CODE': code,
      'treatment_code': treatmentCode,
      'TDL_PATIENT_UNSIGNED_NAME': name,
      'TDL_PATIENT_NAME': name,
      'TDL_PATIENT_GENDER_NAME': gender,
      'TDL_PATIENT_DOB': dob,
      'TDL_PATIENT_ADDRESS': address,
      'TDL_HEIN_CARD_NUMBER': heinCard,
      'TDL_PATIENT_PHONE': phone,
      'TDL_PATIENT_RELATIVE_MOBILE': phone,
      'TREATMENT_TYPE_NAME': 'Điều trị nội trú',
      'PATIENT_TYPE_NAME': isBHYT ? 'BHYT' : 'Viện phí',
      'IN_TIME': inTime,
      'OUT_TIME': '',
      'ICD_NAME': icdName,
      'ICD_CODE': icdCode,
      'DEPARTMENT_CODE': deptCode,
      'DEPARTMENT_NAME': deptName,
      'BED_ROOM_NAME': '$room - Giường $bed',
      'EXECUTE_ROOM_NAME': room,
      'BED_NAME': bed,
      'IS_BHYT': isBHYT,
      'IS_PAUSE': false,
      // v2.77.0: Thêm lowercase để _filterByStatus trong HomeScreen match đúng
      // (filter đọc p['is_pause'] lowercase, không phải 'IS_PAUSE' uppercase)
      'is_pause': '1',  // '1' = đang điều trị (filter check isPause.isNotEmpty)
      'service_req_stt_id': 1,  // sttId != null → match case 1
    };
  }

  /// Sinh danh sách BN mẫu cho 1 khoa (dùng để populate UI demo)
  static List<Map<String, dynamic>> _generateForDept(
    String deptCode,
    String deptName,
    int count,
    int idBase,
  ) {
    final list = <Map<String, dynamic>>[];
    for (int i = 0; i < count; i++) {
      final ho = _hoList[(idBase + i) % _hoList.length];
      final ten = _tenList[(idBase * 3 + i * 7) % _tenList.length];
      final name = '$ho $ten';
      final isMale = (idBase + i) % 2 == 0;
      final year = 1940 + ((idBase * 11 + i * 5) % 70);  // 1940-2009
      final icd = _icdList[(idBase + i) % _icdList.length];
      final treatmentCode = '000002${(112000 + idBase * 100 + i).toString().padLeft(6, '0')}';
      final code = '0000${(597000 + idBase * 100 + i).toString().padLeft(7, '0')}';
      list.add(_makePatient(
        id: idBase + i + 1,
        name: name,
        code: code,
        treatmentCode: treatmentCode,
        dob: year.toString(),
        gender: isMale ? 'Nam' : 'Nữ',
        deptCode: deptCode,
        deptName: deptName,
        icdCode: icd.$1,
        icdName: icd.$2,
        room: 'P.${(i ~/ 6) + 1}',
        bed: 'G${(i % 6) + 1}',
        heinCard: (i % 3 == 0)
            ? 'BT${(2450000000000 + idBase * 10000 + i * 1000).toString().padLeft(15, '0').substring(0, 15)}'
            : (i % 3 == 1)
                ? 'GD${(4790000000000 + idBase * 10000 + i * 1000).toString().padLeft(15, '0').substring(0, 15)}'
                : '',
        phone: (i % 4 == 0) ? '090${(1000000 + idBase * 1000 + i * 100).toString().padLeft(7, '0').substring(0, 7)}' : '',
      ));
    }
    return list;
  }

  /// Bộ data chính - mỗi khoa có số BN tương ứng với độ lớn thực tế
  /// Đây là "nền" (dữ liệu nền) mà app sử dụng để hiển thị BN thật.
  static final Map<String, List<Map<String, dynamic>>> _data = {
    'HSCC': _generateForDept('HSCC', 'Khoa Cấp Cứu', 28, 0),
    'DTCCLuu': _generateForDept('DTCCLuu', 'Cấp Cứu Lưu', 18, 30),
    'HSTC': _generateForDept('HSTC', 'Hồi Sức Tích Cực Chống Độc', 12, 50),
    'KKB': _generateForDept('KKB', 'Khoa Khám bệnh', 22, 80),
    'NTHCL': _generateForDept('NTHCL', 'Khu Nội Tổng Hợp (Mới)', 15, 130),
    'KNTH': _generateForDept('KNTH', 'Khoa Nội tổng hợp', 20, 160),
    'KNTH_CS2': _generateForDept('KNTH_CS2', 'Khoa Nội tổng hợp CS2', 14, 200),
    'NTM': _generateForDept('NTM', 'Khoa Nội tim mạch', 18, 240),
    'DVHH': _generateForDept('DVHH', 'Khoa Nội hô hấp', 16, 280),
    'NTTN': _generateForDept('NTTN', 'Khoa Nội thận - tiết niệu', 14, 320),
    'KTNT': _generateForDept('KTNT', 'Khoa Thận Nhân Tạo', 10, 350),
    'NTK': _generateForDept('NTK', 'Khoa Thần kinh', 12, 400),
    'KPS': _generateForDept('KPS', 'Khoa Phụ sản', 22, 440),
    'KN': _generateForDept('KN', 'Khoa Nhi', 18, 470),
    'DVSS': _generateForDept('DVSS', 'Khoa Sơ sinh', 8, 510),
    'NGTH': _generateForDept('NGTH', 'Khoa Ngoại tổng hợp', 16, 550),
    'KNGOAITH_CS2': _generateForDept('KNGOAITH_CS2', 'Khoa Ngoại tổng hợp CS2', 12, 580),
    'NGCT': _generateForDept('NGCT', 'Khoa Chấn thương chỉnh hình', 12, 610),
    'DVNTK': _generateForDept('DVNTK', 'Khoa Ngoại thần kinh', 8, 640),
    'DVTMCT': _generateForDept('DVTMCT', 'Khoa Tim Mạch Can Thiệp', 6, 660),
    'DVNTTN': _generateForDept('DVNTTN', 'Khoa Ngoại thận - tiết niệu', 8, 670),
    'PTGMHS': _generateForDept('PTGMHS', 'Khoa Gây mê hồi sức', 10, 680),
    'KRHM': _generateForDept('KRHM', 'Khoa Răng - Hàm - Mặt', 8, 720),
    'KRHM_CS2': _generateForDept('KRHM_CS2', 'Khoa Răng Hàm Mặt CS2', 6, 740),
    'KTMH': _generateForDept('KTMH', 'Khoa Tai - Mũi - Họng', 8, 760),
    'KTMH_CS2': _generateForDept('KTMH_CS2', 'Khoa Tai Mũi Họng CS2', 6, 780),
    'KM': _generateForDept('KM', 'Khoa Mắt', 8, 800),
    'KM_CS2': _generateForDept('KM_CS2', 'Khoa Mắt CS2', 6, 820),
    'KTN': _generateForDept('KTN', 'Khoa Truyền Nhiễm', 10, 840),
    'KYHCT': _generateForDept('KYHCT', 'Khoa Y dược cổ truyền - PHCN', 6, 860),
    'KYHCTCS2': _generateForDept('KYHCTCS2', 'Khoa Y Dược Cổ Truyền CS2', 4, 870),
    'KUB': _generateForDept('KUB', 'Khoa Ung bướu (tia xạ)', 8, 880),
    'CDHA': _generateForDept('CDHA', 'Khoa Chẩn đoán hình ảnh', 4, 900),
    'CDHA_CS2': _generateForDept('CDHA_CS2', 'Khoa Chẩn đoán hình ảnh CS2', 4, 910),
    'KDD': _generateForDept('KDD', 'Khoa Dinh Dưỡng', 4, 920),
    'TDCN': _generateForDept('TDCN', 'Khoa Thăm dò chức năng', 4, 930),
    'TDCN_CS2': _generateForDept('TDCN_CS2', 'Khoa Thăm dò chức năng CS2', 4, 940),
    'KSKCB': _generateForDept('KSKCB', 'Khoa Khám sức khỏe cán bộ', 6, 950),
    'KDTTHVN': _generateForDept('KDTTHVN', 'Khoa ĐT Tổng Hợp Văn Lâm', 4, 970),
    'KKB_CS2': _generateForDept('KKB_CS2', 'Khoa Khám bệnh CS2', 10, 980),
    'KCC_CS2': _generateForDept('KCC_CS2', 'Khoa Cấp Cứu CS2', 14, 1000),
    'DTCCLUUCS2': _generateForDept('DTCCLUUCS2', 'Cấp Cứu Lưu Cơ Sở 2', 12, 1030),
    'KDYCS2': _generateForDept('KDYCS2', 'Khoa Y Học Cổ Truyền CS2', 4, 1050),
    'NOILK': _generateForDept('NOILK', 'Khoa Lão học', 8, 1060),
    'COVID_KHUB': _generateForDept('COVID_KHUB', 'Khoa điều trị Covid19 - Khu B', 4, 1070),
    'COVID_NHI': _generateForDept('COVID_NHI', 'Khu điều trị Covid-19 3A', 4, 1080),
    'DTCCLuu': _generateForDept('DTCCLuu', 'Cấp Cứu Lưu', 18, 30),  // alias
    'DTCCL': _generateForDept('DTCCL', 'Cấp Cứu Lưu', 18, 30),     // alt code
    // v2.79.0: HSCCL/CCSVL alias trỏ về NTHCL (Nội Tổng Hợp Mới)
    'HSCCL': _generateForDept('HSCCL', 'Khoa Nội Tổng Hợp (Mới)', 15, 130),
    'CCSVL': _generateForDept('CCSVL', 'Khoa Nội Tổng Hợp (Mới) CS', 15, 130),
    // v2.79.0: KSNK/PTP alias trỏ về KYHCT (Y Dược Cổ Truyền - 6 BN)
    'KSNK': _generateForDept('KSNK', 'Khoa Kiểm Soát Nhiễm Khuẩn', 6, 860),
    'PTP': _generateForDept('PTP', 'Phòng Thu Phí', 6, 860),
    'KDTPN': _generateForDept('KDTPN', 'Khu ĐT Phạm Nhân', 4, 1090),
    'KCG': _generateForDept('KCG', 'Khoa Khám Chuyên Gia', 6, 1100),
    'DTTN': _generateForDept('DTTN', 'Khu Điều Trị Trong Ngày', 6, 1120),
    'CCS': _generateForDept('CCS', 'Khoa Phụ sản_CCS', 12, 1140),
    'DTYC': _generateForDept('DTYC', 'Khoa Khám bệnh theo yêu cầu', 8, 1160),
    'GTVT': _generateForDept('GTVT', 'Khu Giao Thông Vận Tải', 4, 1180),
  };

  /// Lấy BN cho 1 khoa — DÙNG CHÍNH CHO APP.
  /// Trả về list rỗng nếu khoa không có data → UI hiển thị empty state.
  static List<Map<String, dynamic>> getByDepartment(String deptCode) {
    return List<Map<String, dynamic>>.from(_data[deptCode] ?? const []);
  }

  /// Tổng BN toàn viện (dùng cho thống kê / counter)
  static int totalCount() {
    int total = 0;
    for (final list in _data.values) {
      total += list.length;
    }
    return total;
  }

  /// Search theo tên tiếng Việt - gõ "ky" hoặc "Kỳ" đều match
  static List<Map<String, dynamic>> search(String query) {
    if (query.isEmpty) {
      // Trả về tất cả BN từ tất cả khoa (giới hạn 100)
      final all = <Map<String, dynamic>>[];
      for (final list in _data.values) {
        all.addAll(list);
      }
      return all.take(100).toList();
    }
    final q = query.toLowerCase().trim();
    final qNoDia = _removeDiacritics(q);
    final results = <Map<String, dynamic>>[];
    for (final list in _data.values) {
      for (final p in list) {
        final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['tdl_patient_name'] ?? '').toString().toLowerCase();
        final code = (p['TDL_PATIENT_CODE']?.toString() ?? '').toLowerCase();
        final tcode = (p['treatment_code']?.toString() ?? '').toLowerCase();
        final bhyt = (p['TDL_HEIN_CARD_NUMBER']?.toString() ?? '').toLowerCase();
        if (name.contains(q) || code.contains(q) || tcode.contains(q) || bhyt.contains(q) ||
            _removeDiacritics(name).contains(qNoDia) || _removeDiacritics(code).contains(qNoDia)) {
          results.add(p);
        }
      }
    }
    return results;
  }

  /// Bỏ dấu tiếng Việt
  static String _removeDiacritics(String s) {
    const withDia = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const withoutDia = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    String result = s;
    for (int i = 0; i < withDia.length; i++) {
      result = result.replaceAll(withDia[i], withoutDia[i]);
    }
    return result;
  }
}
