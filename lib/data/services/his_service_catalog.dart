// HIS Pro service code catalog - mapping mã chỉ định sang template
// Theo mã BHYT trong HIS Pro (chapter.section.subsection.code):
//   18.xxxxx = Chẩn đoán hình ảnh (X-quang, CT, MRI, DSA, PET)
//   19.xxxxx = Siêu âm
//   20.xxxxx = Nội soi
//   21.xxxxx = Xét nghiệm
//   22.xxxxx = Thăm dò chức năng
//   23.xxxxx = Phẫu thuật
//   24.xxxxx = Thủ thuật
//   25.xxxxx = Dịch vụ kỹ thuật ngoài danh mục
// Trong BVĐK Ninh Thuận, một số dịch vụ phổ biến BS hay chỉ định:
//   18.0119.0028 = X-quang ngực thẳng (kỹ thuật số)
//   18.0119.0029 = X-quang ngực nghiêng
//   19.0001.0001 = Siêu âm bụng tổng quát
//   19.0003.0001 = Siêu âm Doppler tim
//   20.0001.0001 = CT scanner đầu không thuốc
//   21.0001.0001 = Xét nghiệm công thức máu (CTM)
//   21.0005.0001 = Xét nghiệm đường huyết
//   21.0006.0001 = Xét nghiệm chức năng gan
//   21.0007.0001 = Xét nghiệm chức năng thận

class HisServiceEntry {
  final String code;        // Mã BHYT
  final String name;        // Tên dịch vụ
  final String chapter;     // Nhóm: 'CDHA', 'SieuAm', 'NoiSoi', 'XetNghiem', 'TDCS', 'PhauThuat', 'ThuThuat'
  final String template;    // Mps template file to use
  final String templateId;   // FormId for our app
  final String icdPrefix;   // ICD code prefix commonly associated
  final double defaultPrice;

  const HisServiceEntry({
    required this.code,
    required this.name,
    required this.chapter,
    required this.template,
    required this.templateId,
    required this.icdPrefix,
    required this.defaultPrice,
  });
}

class HisServiceCatalog {
  /// Danh sách các dịch vụ phổ biến hay chỉ định tại BVĐK Ninh Thuận
  /// Mapping: code → HisServiceEntry
  static const Map<String, HisServiceEntry> _services = {
    // === 18.xx Chẩn đoán hình ảnh (X-quang) ===
    '18.0119.0028': HisServiceEntry(
      code: '18.0119.0028',
      name: 'X-quang ngực thẳng (số hóa)',
      chapter: 'CDHA',
      template: 'Mps000017__BieuMauPhieuYeuCauInKetQuaChieuChupXQuang___001.xlsx',
      templateId: 'xq_chest',
      icdPrefix: 'J18',
      defaultPrice: 85000,
    ),
    '18.0119.0029': HisServiceEntry(
      code: '18.0119.0029',
      name: 'X-quang ngực nghiêng (số hóa)',
      chapter: 'CDHA',
      template: 'Mps000017__BieuMauPhieuYeuCauInKetQuaChieuChupXQuang___001.xlsx',
      templateId: 'xq_chest',
      icdPrefix: 'J18',
      defaultPrice: 95000,
    ),
    '18.0118.0010': HisServiceEntry(
      code: '18.0118.0010',
      name: 'X-quang xương đùi thẳng nghiêng',
      chapter: 'CDHA',
      template: 'Mps000017__BieuMauPhieuYeuCauInKetQuaChieuChupXQuang___001.xlsx',
      templateId: 'xq_bone',
      icdPrefix: 'S72',
      defaultPrice: 110000,
    ),
    '18.0118.0011': HisServiceEntry(
      code: '18.0118.0011',
      name: 'X-quang cổ tay thẳng nghiêng',
      chapter: 'CDHA',
      template: 'Mps000017__BieuMauPhieuYeuCauInKetQuaChieuChupXQuang___001.xlsx',
      templateId: 'xq_bone',
      icdPrefix: 'S62',
      defaultPrice: 110000,
    ),
    '18.0120.0001': HisServiceEntry(
      code: '18.0120.0001',
      name: 'X-quang cột sống cổ thẳng nghiêng',
      chapter: 'CDHA',
      template: 'Mps000017__BieuMauPhieuYeuCauInKetQuaChieuChupXQuang___001.xlsx',
      templateId: 'xq_spine',
      icdPrefix: 'M54',
      defaultPrice: 130000,
    ),
    '18.0121.0001': HisServiceEntry(
      code: '18.0121.0001',
      name: 'X-quang bụng không chuẩn bị',
      chapter: 'CDHA',
      template: 'Mps000017__BieuMauPhieuYeuCauInKetQuaChieuChupXQuang___001.xlsx',
      templateId: 'xq_abdomen',
      icdPrefix: 'R10',
      defaultPrice: 100000,
    ),

    // === 18.xx CT Scanner ===
    '20.0001.0001': HisServiceEntry(
      code: '20.0001.0001',
      name: 'CT scanner đầu không thuốc',
      chapter: 'CDHA',
      template: 'Mps000018__BieuMauPhieuYeuCauInKetQuaChieuChupXQuangCacDichVu___001.xlsx',
      templateId: 'ct_head',
      icdPrefix: 'S06',
      defaultPrice: 850000,
    ),
    '20.0001.0002': HisServiceEntry(
      code: '20.0001.0002',
      name: 'CT scanner đầu có thuốc cản quang',
      chapter: 'CDHA',
      template: 'Mps000018__BieuMauPhieuYeuCauInKetQuaChieuChupXQuangCacDichVu___001.xlsx',
      templateId: 'ct_head_cq',
      icdPrefix: 'S06',
      defaultPrice: 1450000,
    ),
    '20.0003.0001': HisServiceEntry(
      code: '20.0003.0001',
      name: 'CT scanner ngực',
      chapter: 'CDHA',
      template: 'Mps000018__BieuMauPhieuYeuCauInKetQuaChieuChupXQuangCacDichVu___001.xlsx',
      templateId: 'ct_chest',
      icdPrefix: 'J44',
      defaultPrice: 1500000,
    ),
    '20.0004.0001': HisServiceEntry(
      code: '20.0004.0001',
      name: 'CT scanner bụng',
      chapter: 'CDHA',
      template: 'Mps000018__BieuMauPhieuYeuCauInKetQuaChieuChupXQuangCacDichVu___001.xlsx',
      templateId: 'ct_abdomen',
      icdPrefix: 'K35',
      defaultPrice: 1700000,
    ),

    // === 19.xx Siêu âm ===
    '19.0001.0001': HisServiceEntry(
      code: '19.0001.0001',
      name: 'Siêu âm bụng tổng quát',
      chapter: 'SieuAm',
      template: 'Mps000030__BieuMauPhieuYeuCauSieuAm___001.xlsx',
      templateId: 'sa_bung',
      icdPrefix: 'R10',
      defaultPrice: 220000,
    ),
    '19.0001.0002': HisServiceEntry(
      code: '19.0001.0002',
      name: 'Siêu âm bụng có doppler',
      chapter: 'SieuAm',
      template: 'Mps000030__BieuMauPhieuYeuCauSieuAm___001.xlsx',
      templateId: 'sa_bung_doppler',
      icdPrefix: 'R10',
      defaultPrice: 380000,
    ),
    '19.0003.0001': HisServiceEntry(
      code: '19.0003.0001',
      name: 'Siêu âm Doppler tim',
      chapter: 'SieuAm',
      template: 'Mps000030__BieuMauPhieuYeuCauSieuAm___001.xlsx',
      templateId: 'sa_tim',
      icdPrefix: 'I50',
      defaultPrice: 450000,
    ),
    '19.0005.0001': HisServiceEntry(
      code: '19.0005.0001',
      name: 'Siêu âm thai (sản)',
      chapter: 'SieuAm',
      template: 'Mps000030__BieuMauPhieuYeuCauSieuAm___001.xlsx',
      templateId: 'sa_thai',
      icdPrefix: 'O26',
      defaultPrice: 280000,
    ),

    // === 20.xx Nội soi ===
    '20.0010.0001': HisServiceEntry(
      code: '20.0010.0001',
      name: 'Nội soi dạ dày - tá tràng',
      chapter: 'NoiSoi',
      template: 'Mps000029__BieuMauPhieuYeuCauNoiSoi___001.xlsx',
      templateId: 'ns_daday',
      icdPrefix: 'K29',
      defaultPrice: 850000,
    ),
    '20.0011.0001': HisServiceEntry(
      code: '20.0011.0001',
      name: 'Nội soi đại tràng',
      chapter: 'NoiSoi',
      template: 'Mps000029__BieuMauPhieuYeuCauNoiSoi___001.xlsx',
      templateId: 'ns_daitrang',
      icdPrefix: 'K51',
      defaultPrice: 950000,
    ),

    // === 21.xx Xét nghiệm ===
    '21.0001.0001': HisServiceEntry(
      code: '21.0001.0001',
      name: 'Công thức máu (CTM) - 18 thông số',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_ctm',
      icdPrefix: 'D50',
      defaultPrice: 110000,
    ),
    '21.0005.0001': HisServiceEntry(
      code: '21.0005.0001',
      name: 'Đường huyết lúc đói',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_glucose',
      icdPrefix: 'E11',
      defaultPrice: 35000,
    ),
    '21.0006.0001': HisServiceEntry(
      code: '21.0006.0001',
      name: 'Chức năng gan (AST, ALT, GGT, Bilirubin)',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_gan',
      icdPrefix: 'K76',
      defaultPrice: 180000,
    ),
    '21.0007.0001': HisServiceEntry(
      code: '21.0007.0001',
      name: 'Chức năng thận (Urea, Creatinin)',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_than',
      icdPrefix: 'N18',
      defaultPrice: 85000,
    ),
    '21.0008.0001': HisServiceEntry(
      code: '21.0008.0001',
      name: 'Điện giải đồ (Na, K, Cl)',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_dien_giai',
      icdPrefix: 'E87',
      defaultPrice: 95000,
    ),
    '21.0009.0001': HisServiceEntry(
      code: '21.0009.0001',
      name: 'Tổng phân tích nước tiểu',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_nuoc_tieu',
      icdPrefix: 'N39',
      defaultPrice: 45000,
    ),
    '21.0010.0001': HisServiceEntry(
      code: '21.0010.0001',
      name: 'CRP (C-reactive protein)',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_crp',
      icdPrefix: 'R50',
      defaultPrice: 110000,
    ),
    '21.0011.0001': HisServiceEntry(
      code: '21.0011.0001',
      name: 'Procalcitonin (PCT)',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_pct',
      icdPrefix: 'A41',
      defaultPrice: 280000,
    ),
    '21.0012.0001': HisServiceEntry(
      code: '21.0012.0001',
      name: 'D-dimer',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_ddimer',
      icdPrefix: 'I26',
      defaultPrice: 220000,
    ),
    '21.0013.0001': HisServiceEntry(
      code: '21.0013.0001',
      name: 'Troponin I/T',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_troponin',
      icdPrefix: 'I21',
      defaultPrice: 180000,
    ),
    '21.0014.0001': HisServiceEntry(
      code: '21.0014.0001',
      name: 'D-dimer khẩn',
      chapter: 'XetNghiem',
      template: 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx',
      templateId: 'xn_ddimer_khan',
      icdPrefix: 'I26',
      defaultPrice: 280000,
    ),

    // === 22.xx Thăm dò chức năng ===
    '22.0001.0001': HisServiceEntry(
      code: '22.0001.0001',
      name: 'Điện tâm đồ',
      chapter: 'TDCS',
      template: 'Mps000038__BieuMauPhieuYeuCauThamDoChucNang___001.xlsx',
      templateId: 'tdcs_ecg',
      icdPrefix: 'I20',
      defaultPrice: 75000,
    ),
    '22.0002.0001': HisServiceEntry(
      code: '22.0002.0001',
      name: 'Điện não đồ',
      chapter: 'TDCS',
      template: 'Mps000038__BieuMauPhieuYeuCauThamDoChucNang___PHIEUDIENNAO.xlsx',
      templateId: 'tdcs_eeg',
      icdPrefix: 'G40',
      defaultPrice: 220000,
    ),
    '22.0003.0001': HisServiceEntry(
      code: '22.0003.0001',
      name: 'Holter điện tâm đồ 24h',
      chapter: 'TDCS',
      template: 'Mps000038__BieuMauPhieuYeuCauThamDoChucNang___001.xlsx',
      templateId: 'tdcs_holter',
      icdPrefix: 'I48',
      defaultPrice: 480000,
    ),

    // === 23.xx Phẫu thuật ===
    '23.0001.0001': HisServiceEntry(
      code: '23.0001.0001',
      name: 'Phẫu thuật nội soi cắt ruột thừa viêm',
      chapter: 'PhauThuat',
      template: 'Mps000033__BieuMauPhieuYeuCauPhauThuat___001.xlsx',
      templateId: 'pt_ruot_thua',
      icdPrefix: 'K35',
      defaultPrice: 3500000,
    ),
    '23.0002.0001': HisServiceEntry(
      code: '23.0002.0001',
      name: 'Phẫu thuật thoát vị bẹn',
      chapter: 'PhauThuat',
      template: 'Mps000033__BieuMauPhieuYeuCauPhauThuat___001.xlsx',
      templateId: 'pt_thoat_vi_ben',
      icdPrefix: 'K40',
      defaultPrice: 2800000,
    ),
    '23.0003.0001': HisServiceEntry(
      code: '23.0003.0001',
      name: 'Phẫu thuật cắt túi mật nội soi',
      chapter: 'PhauThuat',
      template: 'Mps000033__BieuMauPhieuYeuCauPhauThuat___001.xlsx',
      templateId: 'pt_tui_mat',
      icdPrefix: 'K80',
      defaultPrice: 4200000,
    ),
  };

  /// Resolve a service code to its entry
  static HisServiceEntry? lookup(String code) {
    final normalized = code.trim();
    return _services[normalized];
  }

  /// Resolve by templateId
  static List<HisServiceEntry> byTemplate(String templateId) {
    return _services.values.where((e) => e.templateId == templateId).toList();
  }

  /// Resolve by chapter prefix
  static List<HisServiceEntry> byChapter(String chapter) {
    return _services.values.where((e) => e.chapter == chapter).toList();
  }

  /// Search by name/code fragment
  static List<HisServiceEntry> search(String query) {
    if (query.trim().isEmpty) return _services.values.toList();
    final q = query.toLowerCase().trim();
    return _services.values
        .where((e) =>
            e.code.toLowerCase().contains(q) ||
            e.name.toLowerCase().contains(q) ||
            e.chapter.toLowerCase().contains(q))
        .toList();
  }

  /// All services by chapter
  static Map<String, List<HisServiceEntry>> byChapterGrouped() {
    final map = <String, List<HisServiceEntry>>{};
    for (final e in _services.values) {
      map.putIfAbsent(e.chapter, () => []).add(e);
    }
    return map;
  }

  /// Get all chapters
  static List<String> get chapters => byChapterGrouped().keys.toList()..sort();

  /// Get the appropriate Mps template file for a service code
  /// - Looks up service entry, returns its template
  /// - Falls back to Mps000037 (combined order template) if unknown code
  static String templateForCode(String code) {
    final entry = lookup(code);
    if (entry != null) return entry.template;
    // Default by chapter prefix
    if (code.startsWith('18.') || code.startsWith('20.')) {
      return 'Mps000017__BieuMauPhieuYeuCauInKetQuaChieuChupXQuang___001.xlsx';
    }
    if (code.startsWith('19.')) {
      return 'Mps000030__BieuMauPhieuYeuCauSieuAm___001.xlsx';
    }
    if (code.startsWith('21.')) {
      return 'Mps000014__BieuMauPhieuYeuCauInKetQuaXetNghiem___KetQuaXetNghiem.xlsx';
    }
    if (code.startsWith('22.')) {
      return 'Mps000038__BieuMauPhieuYeuCauThamDoChucNang___001.xlsx';
    }
    if (code.startsWith('23.') || code.startsWith('24.')) {
      return 'Mps000033__BieuMauPhieuYeuCauPhauThuat___001.xlsx';
    }
    return 'MPS000037__PhieuYeuCauChiDinhTongHop___A4D_001.xlsx';
  }

  /// Total service count
  static int get totalServices => _services.length;
}
