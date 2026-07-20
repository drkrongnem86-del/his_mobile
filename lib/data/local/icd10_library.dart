// ICD-10 codes thường gặp tại BVĐK Ninh Thuận - ICU/Cấp cứu.
// Dùng cho "Xem bệnh án" + ICD picker trong phiếu khám.
class Icd10Entry {
  final String code;
  final String nameVi;
  final String? nameEn;
  final String category;
  const Icd10Entry(this.code, this.nameVi, {this.nameEn, this.category = 'Khác'});

  @override
  String toString() => '$code  -  $nameVi';
}

/// ~80 ICD-10 codes thông dụng theo danh mục
class Icd10Library {
  static const List<Icd10Entry> common = [
    // === TIM MẠCH ===
    Icd10Entry('I10', 'Tăng huyết áp vô căn', nameEn: 'Essential hypertension', category: 'Tim mạch'),
    Icd10Entry('I11', 'Tăng huyết áp có bệnh tim', category: 'Tim mạch'),
    Icd10Entry('I20', 'Cơn đau thắt ngực', category: 'Tim mạch'),
    Icd10Entry('I21', 'Nhồi máu cơ tim cấp', nameEn: 'Acute MI', category: 'Tim mạch'),
    Icd10Entry('I21.0', 'NMCT cấp thành trước', category: 'Tim mạch'),
    Icd10Entry('I21.1', 'NMCT cấp thành dưới', category: 'Tim mạch'),
    Icd10Entry('I21.4', 'NMCT cấp không đặc hiệu', category: 'Tim mạch'),
    Icd10Entry('I25', 'Bệnh tim thiếu máu cục bộ mạn', category: 'Tim mạch'),
    Icd10Entry('I48', 'Rung nhĩ', nameEn: 'Atrial fibrillation', category: 'Tim mạch'),
    Icd10Entry('I50', 'Suy tim', nameEn: 'Heart failure', category: 'Tim mạch'),
    Icd10Entry('I50.0', 'Suy tim sung huyết', category: 'Tim mạch'),
    Icd10Entry('I63', 'Nhồi máu não', nameEn: 'Cerebral infarction', category: 'Tim mạch'),
    Icd10Entry('I64', 'Đột quỵ không phân biệt', nameEn: 'Stroke', category: 'Tim mạch'),
    Icd10Entry('I67', 'Bệnh mạch máu não khác', category: 'Tim mạch'),

    // === HÔ HẤP ===
    Icd10Entry('J12', 'Viêm phổi do virus', category: 'Hô hấp'),
    Icd10Entry('J13', 'Viêm phổi do Streptococcus pneumoniae', category: 'Hô hấp'),
    Icd10Entry('J15', 'Viêm phổi do vi khuẩn khác', category: 'Hô hấp'),
    Icd10Entry('J18', 'Viêm phổi, không đặc hiệu', nameEn: 'Pneumonia NOS', category: 'Hô hấp'),
    Icd10Entry('J18.9', 'Viêm phổi không đặc hiệu', category: 'Hô hấp'),
    Icd10Entry('J20', 'Viêm phế quản cấp', category: 'Hô hấp'),
    Icd10Entry('J21', 'Viêm tiểu phế quản cấp', category: 'Hô hấp'),
    Icd10Entry('J22', 'Nhiễm trùng hô hấp dưới cấp không đặc hiệu', category: 'Hô hấp'),
    Icd10Entry('J44', 'Bệnh phổi tắc nghẽn mạn - COPD', category: 'Hô hấp'),
    Icd10Entry('J44.1', 'Đợt cấp COPD', category: 'Hô hấp'),
    Icd10Entry('J45', 'Hen', nameEn: 'Asthma', category: 'Hô hấp'),
    Icd10Entry('J45.0', 'Hen chủ yếu dị ứng', category: 'Hô hấp'),
    Icd10Entry('J45.1', 'Hen không dị ứng', category: 'Hô hấp'),
    Icd10Entry('J45.9', 'Hen không đặc hiệu', category: 'Hô hấp'),
    Icd10Entry('J46', 'Trạng thái hen (status asthmaticus)', category: 'Hô hấp'),
    Icd10Entry('J90', 'Tràn dịch màng phổi', category: 'Hô hấp'),
    Icd10Entry('J96', 'Suy hô hấp', nameEn: 'Respiratory failure', category: 'Hô hấp'),
    Icd10Entry('J96.0', 'Suy hô hấp cấp', category: 'Hô hấp'),
    Icd10Entry('J96.1', 'Suy hô hấp mạn', category: 'Hô hấp'),
    Icd10Entry('J96.9', 'Suy hô hấp không đặc hiệu', category: 'Hô hấp'),

    // === TIÊU HÓA ===
    Icd10Entry('K29', 'Viêm dạ dày - tá tràng', nameEn: 'Gastritis', category: 'Tiêu hóa'),
    Icd10Entry('K29.7', 'Viêm dạ dày không đặc hiệu', category: 'Tiêu hóa'),
    Icd10Entry('K35', 'Viêm ruột thừa cấp', nameEn: 'Appendicitis', category: 'Tiêu hóa'),
    Icd10Entry('K35.8', 'Viêm ruột thừa cấp khác', category: 'Tiêu hóa'),
    Icd10Entry('K52', 'Viêm dạ dày - ruột không nhiễm trùng', category: 'Tiêu hóa'),
    Icd10Entry('K70', 'Bệnh gan do rượu', category: 'Tiêu hóa'),
    Icd10Entry('K74', 'Xơ gan', nameEn: 'Cirrhosis', category: 'Tiêu hóa'),
    Icd10Entry('K80', 'Sỏi mật', nameEn: 'Cholelithiasis', category: 'Tiêu hóa'),
    Icd10Entry('K92', 'Bệnh khác của hệ tiêu hóa', category: 'Tiêu hóa'),
    Icd10Entry('K92.2', 'Xuất huyết tiêu hóa không đặc hiệu', category: 'Tiêu hóa'),

    // === THẦN KINH ===
    Icd10Entry('G40', 'Động kinh', nameEn: 'Epilepsy', category: 'Thần kinh'),
    Icd10Entry('G40.9', 'Động kinh không đặc hiệu', category: 'Thần kinh'),
    Icd10Entry('G41', 'Trạng thái động kinh (status epilepticus)', category: 'Thần kinh'),
    Icd10Entry('G45', 'Cơn thiếu máu não thoáng qua (TIA)', category: 'Thần kinh'),
    Icd10Entry('G51', 'Liệt dây thần kinh mặt', category: 'Thần kinh'),
    Icd10Entry('G81', 'Liệt nửa người', nameEn: 'Hemiplegia', category: 'Thần kinh'),
    Icd10Entry('G82', 'Liệt hai chi dưới', category: 'Thần kinh'),

    // === NỘI TIẾT ===
    Icd10Entry('E10', 'Đái tháo đường typ 1', nameEn: 'Type 1 DM', category: 'Nội tiết'),
    Icd10Entry('E11', 'Đái tháo đường typ 2', nameEn: 'Type 2 DM', category: 'Nội tiết'),
    Icd10Entry('E11.5', 'ĐTĐ typ 2 có biến chứng mạch máu', category: 'Nội tiết'),
    Icd10Entry('E11.9', 'ĐTĐ typ 2 không biến chứng', category: 'Nội tiết'),
    Icd10Entry('E14', 'ĐTĐ không đặc hiệu', category: 'Nội tiết'),
    Icd10Entry('E15', 'Hạ đường huyết không do đái tháo đường', category: 'Nội tiết'),
    Icd10Entry('E16', 'Rối loạn tuyến tụy nội tiết', category: 'Nội tiết'),
    Icd10Entry('E78', 'Rối loạn lipoprotein máu', category: 'Nội tiết'),

    // === THẬN - TIẾT NIỆU ===
    Icd10Entry('N17', 'Suy thận cấp', nameEn: 'Acute renal failure', category: 'Thận'),
    Icd10Entry('N17.9', 'Suy thận cấp không đặc hiệu', category: 'Thận'),
    Icd10Entry('N18', 'Suy thận mạn', nameEn: 'Chronic renal failure', category: 'Thận'),
    Icd10Entry('N18.9', 'Suy thận mạn không đặc hiệu', category: 'Thận'),
    Icd10Entry('N19', 'Suy thận không đặc hiệu', category: 'Thận'),
    Icd10Entry('N20', 'Sỏi thận', nameEn: 'Kidney calculus', category: 'Thận'),
    Icd10Entry('N39', 'Rối loạn khác của hệ tiết niệu', category: 'Thận'),
    Icd10Entry('N40', 'Tăng sản tuyến tiền liệt', category: 'Thận'),

    // === NGOẠI KHOA / CHẤN THƯƠNG ===
    Icd10Entry('S00', 'Chấn thương nông vùng đầu', category: 'Ngoại'),
    Icd10Entry('S06', 'Chấn thương sọ não', nameEn: 'Intracranial injury', category: 'Ngoại'),
    Icd10Entry('S06.0', 'Chấn động não', category: 'Ngoại'),
    Icd10Entry('S06.5', 'Xuất huyết nội sọ do chấn thương', category: 'Ngoại'),
    Icd10Entry('S22', 'Gãy xương sườn', category: 'Ngoại'),
    Icd10Entry('S27', 'Chấn thương cơ quan ngực khác', category: 'Ngoại'),
    Icd10Entry('S32', 'Gãy cột sống thắt lưng', category: 'Ngoại'),
    Icd10Entry('S42', 'Gãy xương vai và cánh tay', category: 'Ngoại'),
    Icd10Entry('S52', 'Gãy xương cẳng tay', category: 'Ngoại'),
    Icd10Entry('S72', 'Gãy xương đùi', nameEn: 'Femur fracture', category: 'Ngoại'),
    Icd10Entry('S82', 'Gãy xương cẳng chân', category: 'Ngoại'),
    Icd10Entry('T07', 'Đa chấn thương không đặc hiệu', category: 'Ngoại'),
    Icd10Entry('T78', 'Tác dụng phụ không xếp loại khác', category: 'Ngoại'),
    Icd10Entry('T78.2', 'Sốc phản vệ', nameEn: 'Anaphylactic shock', category: 'Ngoại'),
    Icd10Entry('T81', 'Biến chứng của thủ thuật', category: 'Ngoại'),

    // === TRUYỀN NHIỄM ===
    Icd10Entry('A09', 'Tiêu chảy và viêm dạ dày - ruột nghi ngờ nhiễm trùng', category: 'Truyền nhiễm'),
    Icd10Entry('A41', 'Nhiễm trùng huyết', nameEn: 'Sepsis', category: 'Truyền nhiễm'),
    Icd10Entry('A41.9', 'Nhiễm trùng huyết không đặc hiệu', category: 'Truyền nhiễm'),
    Icd10Entry('A48', 'Bệnh do vi khuẩn khác không xếp loại', category: 'Truyền nhiễm'),
    Icd10Entry('A90', 'Sốt xuất huyết Dengue', nameEn: 'Dengue fever', category: 'Truyền nhiễm'),
    Icd10Entry('A91', 'Sốt xuất huyết Dengue có biến chứng', category: 'Truyền nhiễm'),
    Icd10Entry('B19', 'Viêm gan virus không đặc hiệu', category: 'Truyền nhiễm'),
    Icd10Entry('B49', 'Bệnh nấm không đặc hiệu', category: 'Truyền nhiễm'),

    // === SẢN - PHỤ KHOA ===
    Icd10Entry('O80', 'Đẻ đơn thuận', category: 'Sản phụ'),
    Icd10Entry('O82', 'Đẻ bằng phẫu thuật lấy thai', category: 'Sản phụ'),
    Icd10Entry('O90', 'Biến chứng sau đẻ', category: 'Sản phụ'),

    // === UNG THƯ ===
    Icd10Entry('C50', 'Ung thư vú', nameEn: 'Breast cancer', category: 'Ung bướu'),
    Icd10Entry('C34', 'Ung thư phế quản-phổi', category: 'Ung bướu'),
    Icd10Entry('C61', 'Ung thư tuyến tiền liệt', category: 'Ung bướu'),
    Icd10Entry('C80', 'Ung thư không đặc hiệu', nameEn: 'Cancer NOS', category: 'Ung bướu'),

    // === MẮT / TAI MŨI HỌNG / DA LIỄU ===
    Icd10Entry('H10', 'Viêm kết mạc', nameEn: 'Conjunctivitis', category: 'Mắt'),
    Icd10Entry('J00', 'Viêm mũi họng cấp (cảm lạnh)', category: 'Tai Mũi Họng'),
    Icd10Entry('J03', 'Viêm amidan cấp', category: 'Tai Mũi Họng'),
    Icd10Entry('J06', 'Nhiễm trùng đường hô hấp trên cấp', category: 'Tai Mũi Họng'),
    Icd10Entry('L03', 'Viêm quầng/cellulitis', category: 'Da liễu'),

    // === NHI KHOA ===
    Icd10Entry('P21', 'Ngạt khi sinh', category: 'Nhi'),
    Icd10Entry('P22', 'Hội chứng suy hô hấp sơ sinh', category: 'Nhi'),
    Icd10Entry('P59', 'Vàng da sơ sinh', category: 'Nhi'),
  ];

  /// Lọc ICD theo từ khoá tiếng Việt (không dấu hoặc có dấu)
  static List<Icd10Entry> search(String query) {
    if (query.isEmpty) return common;
    final q = query.toLowerCase().trim();
    return common.where((e) {
      final code = e.code.toLowerCase();
      final nameVi = _removeDiacritics(e.nameVi.toLowerCase());
      final nameEn = _removeDiacritics((e.nameEn ?? '').toLowerCase());
      final category = _removeDiacritics(e.category.toLowerCase());
      final qWithoutDiacritics = _removeDiacritics(q);
      return code.contains(qWithoutDiacritics) ||
          nameVi.contains(qWithoutDiacritics) ||
          nameEn.contains(qWithoutDiacritics) ||
          category.contains(qWithoutDiacritics);
    }).toList();
  }

  static String _removeDiacritics(String s) {
    const map = {
      'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ắ': 'a', 'ằ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
      'â': 'a', 'ấ': 'a', 'ầ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'đ': 'd',
      'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ế': 'e', 'ề': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ố': 'o', 'ồ': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ớ': 'o', 'ờ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ứ': 'u', 'ừ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
    };
    final buf = StringBuffer();
    for (final c in s.runes) {
      final ch = String.fromCharCode(c);
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }
}
