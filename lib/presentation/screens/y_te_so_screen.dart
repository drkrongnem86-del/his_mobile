// v3.0.87: YTeSoScreen - Xem bệnh án Y Tế Số (Bộ Y tế) - UI match XemBenhAn
//
// v3.0.87 changes (theo feedback user):
//   - UI match XemBenhAn:
//     * Header xanh navy + patient name + treatmentCode
//     * List trái với folder-style sub-groups (icon folder + count badge)
//     * Items có check xanh nếu signed, spinner nếu đang load
//     * Background xanh nhạt cho phiếu đang chọn (isSelected)
//     * PDF viewer phải với 4 nút tròn (fullscreen, download, print, share)
//     * Note input + save dưới list
//     * "Phiếu (N) ← vuốt" header
//     * Bottom: "N nhóm • N phiếu"
//   - Lazy load: không auto-select phiếu đầu tiên, show "Chọn phiếu bên trái"
//   - Download all docs parallel sau khi load list xong (background)
//
// v3.0.85-86 cũ:
//   - List documents theo treatmentCode (grouped by DOCUMENT_TYPE)
//   - Auto-login silent (qua main login)

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:his_mobile/data/api/y_te_so_service.dart';
import 'package:his_mobile/presentation/screens/y_te_so_pdf_viewer_screen.dart';

class YTeSoScreen extends StatefulWidget {
  /// Mã điều trị (treatmentCode)
  final String treatmentCode;
  final String? treatmentId;
  final String? patientName;
  final String? patientCode;

  const YTeSoScreen({
    super.key,
    required this.treatmentCode,
    this.treatmentId,
    this.patientName,
    this.patientCode,
  });

  @override
  State<YTeSoScreen> createState() => _YTeSoScreenState();
}

class _YTeSoScreenState extends State<YTeSoScreen> {
  final _service = YTeSoService.instance;
  bool _loading = true;
  String? _error;
  List<YTeSoDocumentGroup> _groups = [];
  YTeSoDocument? _selected;
  /// v3.0.87: Map id -> filePath (cached on disk)
  final Map<int, String> _docFilePaths = {};
  /// v3.0.87: Map id -> true nếu đang download
  final Set<int> _downloading = {};
  /// v3.0.89: Fullscreen mode (PageView swipe giữa các phiếu) - match XemBenhAn
  bool _fullscreen = false;
  final PageController _pageController = PageController();
  /// v3.0.87: Map id -> true nếu đã có bytes sẵn
  final Set<int> _docLoaded = {};
  bool _savingPdf = false;
  String? _viewerError;
  final PdfViewerController _pdfController = PdfViewerController();
  final Map<int, TextEditingController> _noteCtrls = {};
  final Map<int, GlobalKey> _docKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Flat list tất cả documents (cho navigation prev/next)
  List<YTeSoDocument> get _flatDocs =>
      _groups.expand((g) => g.items).toList();

  int get _selectedIndex {
    if (_selected == null) return -1;
    return _flatDocs.indexWhere((d) => d.id == _selected!.id);
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // v3.0.87: Chỉ gọi login nếu cần
    if (!_service.isLoggedIn) {
      final r = await _service.login();
      if (!r.success) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error =
              'Chưa đăng nhập Y Tế Số. Đăng nhập lại ở màn hình chính.\n\n${r.message}';
        });
        return;
      }
    }
    final r = await _service.listDocuments(
      treatmentCode: widget.treatmentCode,
      treatmentId: widget.treatmentId,
      force: force,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success) {
        _groups = r.groups;
        _error = null;
      } else {
        _error = r.message;
      }
    });
    // v3.0.90: Sau khi list load xong, tự động download phiếu đầu + 2 phiếu tiếp theo
    // (background, không block UI) → user tap là PDF sẵn sàng
    if (r.success && _flatDocs.isNotEmpty) {
      unawaited(_preloadFirst(3));
    }
  }

  /// v3.0.90: Preload N phiếu đầu (background, parallel)
  Future<void> _preloadFirst(int count) async {
    final toLoad = _flatDocs.take(count).toList();
    for (final doc in toLoad) {
      if (_docFilePaths.containsKey(doc.id)) continue;
      if (_downloading.contains(doc.id)) continue;
      // Fire-and-forget (parallel)
      unawaited(_downloadDoc(doc));
      // Yield để tránh block UI
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// v3.0.91: Mở fullscreen viewer với danh sách tất cả phiếu
  /// - Tap list item → mở YTeSoPdfViewerScreen (giống v3.0.85)
  /// - Viewer có prev/next doc navigation (mũi tên)
  Future<void> _selectDoc(YTeSoDocument doc) async {
    final idx = _flatDocs.indexWhere((d) => d.id == doc.id);
    // Đảm bảo file đã download
    if (!_docFilePaths.containsKey(doc.id) || !File(_docFilePaths[doc.id]!).existsSync()) {
      await _downloadDoc(doc);
    }
    if (!mounted) return;
    final filePath = _docFilePaths[doc.id];
    if (filePath == null || !File(filePath).existsSync()) {
      _snack('Không tải được phiếu', isError: true);
      return;
    }
    final allDocs = _flatDocs
        .map((d) => YTeSoDocItem(
              id: d.id,
              code: d.code,
              name: d.name,
              fileType: d.fileType,
              filePath: _docFilePaths[d.id] ?? '',
              treatmentCode: widget.treatmentCode,
            ))
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => YTeSoPdfViewerScreen(
          filePath: filePath,
          title: doc.name,
          docCode: doc.code,
          fileType: doc.fileType,
          treatmentCode: widget.treatmentCode,
          allDocs: allDocs,
          currentDocIndex: idx >= 0 ? idx : 0,
          onLoadDoc: (target) async {
            // Download file cho doc mới nếu chưa có
            if (!_docFilePaths.containsKey(target.id) ||
                !File(_docFilePaths[target.id]!).existsSync()) {
              await _downloadDoc(_flatDocs.firstWhere((d) => d.id == target.id));
            }
            final p = _docFilePaths[target.id];
            if (p == null || !File(p).existsSync()) return null;
            return YTeSoDocItem(
              id: target.id,
              code: target.code,
              name: target.name,
              fileType: target.fileType,
              filePath: p,
              treatmentCode: target.treatmentCode,
            );
          },
        ),
      ),
    ).then((_) {
      // Khi quay lại, refresh lại state
      if (mounted) setState(() => _selected = null);
    });
  }

  /// v3.0.87: Download PDF/ảnh cho 1 phiếu
  Future<void> _downloadDoc(YTeSoDocument doc) async {
    if (_downloading.contains(doc.id)) return;
    setState(() => _downloading.add(doc.id));
    final r = await _service.downloadDocument(
      documentId: doc.id,
      treatmentCode: doc.treatmentCode,
      treatmentId: doc.treatmentId.toString(),
    );
    if (!mounted) return;
    setState(() => _downloading.remove(doc.id));
    if (r.success && r.filePath != null) {
      setState(() {
        _docFilePaths[doc.id] = r.filePath!;
        _docLoaded.add(doc.id);
        _viewerError = null;
      });
    } else {
      // v3.0.87: Nếu 401 thì login lại
      if (r.message != null && r.message!.contains('401')) {
        final ok = await _service.ensureLoggedIn();
        if (ok) {
          await _downloadDoc(doc);
          return;
        }
      }
      setState(() => _viewerError = r.message ?? 'Lỗi tải phiếu');
    }
  }

  /// v3.0.87: Preload tất cả phiếu (parallel) - chạy background
  void _preloadAll() {
    for (final doc in _flatDocs) {
      if (!_docFilePaths.containsKey(doc.id) && !_downloading.contains(doc.id)) {
        // Fire-and-forget, mỗi cái 1 lần
        _downloadDoc(doc);
      }
    }
  }

  /// v3.0.87: Lưu PDF vào /storage/emulated/0/Download
  Future<void> _downloadSelected() async {
    if (_selected == null || _savingPdf) return;
    final doc = _selected!;
    final path = _docFilePaths[doc.id];
    if (path == null) return;
    setState(() => _savingPdf = true);
    try {
      final bytes = await File(path).readAsBytes();
      Directory? targetDir;
      try {
        targetDir = Directory('/storage/emulated/0/Download');
        if (!await targetDir.exists()) {
          targetDir = await getExternalStorageDirectory();
        }
      } catch (_) {
        targetDir = null;
      }
      targetDir ??= await getApplicationDocumentsDirectory();
      final ext = doc.fileType.toLowerCase().isEmpty
          ? 'pdf'
          : doc.fileType.toLowerCase();
      final filename = 'BA_${widget.treatmentCode}_${doc.code}.$ext';
      final file = File('${targetDir.path}/$filename');
      await file.writeAsBytes(bytes);
      _snack('Đã lưu: ${file.path}');
    } catch (e) {
      _snack('Lỗi lưu: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  /// v3.0.87: In PDF (dùng Printing.layoutPdf)
  Future<void> _printSelected() async {
    if (_selected == null) return;
    final path = _docFilePaths[_selected!.id];
    if (path == null) {
      _snack('Chưa tải xong file', isError: true);
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      _snack('Lỗi in: $e', isError: true);
    }
  }

  /// v3.0.87: Chia sẻ PDF
  Future<void> _shareSelected() async {
    if (_selected == null || _savingPdf) return;
    final path = _docFilePaths[_selected!.id];
    if (path == null) return;
    setState(() => _savingPdf = true);
    try {
      final bytes = await File(path).readAsBytes();
      final ext = _selected!.fileType.toLowerCase().isEmpty
          ? 'pdf'
          : _selected!.fileType.toLowerCase();
      final filename = 'BA_${widget.treatmentCode}_${_selected!.code}.$ext';
      try {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } catch (_) {
        _snack('Đã lưu, dùng file manager để chia sẻ');
      }
    } catch (e) {
      _snack('Lỗi chia sẻ: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  /// v3.0.89: Mở fullscreen PageView (giống XemBenhAn) - swipe giữa các phiếu
  void _goFullscreen() {
    if (_selected == null) return;
    if (_flatDocs.isEmpty) return;
    setState(() {
      _fullscreen = true;
      // Animate PageController tới currentIndex
      final idx = _selectedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && idx >= 0) {
          _pageController.jumpToPage(idx);
        }
      });
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// v3.0.89: Navigate to specific doc index in fullscreen PageView
  void _goToDocFs(int idx) {
    if (idx < 0 || idx >= _flatDocs.length) return;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        idx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _exitFullscreen() {
    setState(() => _fullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 12)),
      backgroundColor: isError ? Colors.red[700] : Colors.green[700],
      duration: const Duration(seconds: 2),
    ));
  }

  /// v3.0.90: Token status badge - hiện trên header
  /// Màu sắc: xanh lá = OK, cam = sắp hết hạn, đỏ = hết hạn/missing
  Widget _buildTokenBadge() {
    final hasToken = _service.isLoggedIn;
    if (!hasToken) {
      return Tooltip(
        message: 'Chưa có Y Tế Số JWT. Bấm để lấy tự động.',
        child: InkWell(
          onTap: _autoLoginSilently,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.no_encryption, color: Colors.white, size: 10),
                SizedBox(width: 2),
                Text('No token',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    }
    // Có token - check expiry
    final exp = _service.tokenExpiresAt;
    if (exp == null) {
      return Tooltip(
        message: 'Token OK (không rõ expiry)',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.green.shade400,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 10),
              SizedBox(width: 2),
              Text('OK',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }
    final remaining = exp.difference(DateTime.now());
    Color color;
    String text;
    IconData icon;
    if (remaining.isNegative) {
      color = Colors.red.shade400;
      text = 'Hết hạn';
      icon = Icons.error;
    } else if (remaining.inMinutes < 5) {
      color = Colors.orange.shade400;
      text = 'Còn ${remaining.inMinutes}p';
      icon = Icons.warning_amber;
    } else {
      color = Colors.green.shade400;
      text = 'Còn ${remaining.inMinutes}p';
      icon = Icons.check_circle;
    }
    return Tooltip(
      message: 'JWT expires: $exp\nRemaining: ${remaining.inMinutes} phút',
      child: InkWell(
        onTap: _autoLoginSilently,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 10),
              const SizedBox(width: 2),
              Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  /// v3.0.90: Auto-login silent - gọi từ token badge khi user bấm
  Future<void> _autoLoginSilently() async {
    _snack('Đang lấy Y Tế Số JWT...');
    final r = await _service.login();
    if (!mounted) return;
    if (r.success) {
      _snack('Đã lấy JWT thành công');
      _load(force: true);
    } else {
      _snack('Lấy JWT thất bại: ${r.message}', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // v3.0.89: Fullscreen PageView (giống XemBenhAn)
    if (_fullscreen && _selected != null && _flatDocs.isNotEmpty) {
      return _buildFullscreen();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Y tế số - Xem bệnh án',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.patientName != null
                        ? '${widget.patientName ?? ""} • ${widget.treatmentCode}'
                        : widget.treatmentCode,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // v3.0.90: Token status indicator
                _buildTokenBadge(),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: _loading ? null : () => _load(force: true),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('Chưa có tài liệu nào trong bệnh án này'),
          ],
        ),
      );
    }

    // v3.0.87: Luôn show split-view 40/60 (kể cả mobile portrait Samsung A17)
    return LayoutBuilder(builder: (ctx, constraints) {
      if (constraints.maxWidth < 400) {
        // Quá hẹp → chỉ list
        return _buildLeftPanel();
      }
      final listW = (constraints.maxWidth * 0.4).clamp(150.0, constraints.maxWidth * 0.5);
      return Row(
        children: [
          SizedBox(width: listW, child: _buildLeftPanel()),
          VerticalDivider(width: 1, color: Colors.grey[300]),
          Expanded(child: _buildRightPanel()),
        ],
      );
    });
  }

  /// v3.0.87: Left panel - giống XemBenhAn (folder-style groups + items với check + note)
  Widget _buildLeftPanel() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Patient info card (giống XemBenhAn)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            color: const Color(0xFF0D47A1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.patientName ?? 'Bệnh nhân',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.patientCode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.patientCode!,
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),

          // Header "Phiếu (N) ← vuốt"
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 13, color: Color(0xFF0D47A1)),
                const SizedBox(width: 4),
                Text('Phiếu (${_flatDocs.length})',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D47A1))),
                const Spacer(),
                GestureDetector(
                  onTap: _preloadAll,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_download, size: 11, color: Colors.black45),
                      SizedBox(width: 2),
                      Text('Tải hết', style: TextStyle(fontSize: 9, color: Colors.black45)),
                      SizedBox(width: 6),
                      Text('← vuốt', style: TextStyle(fontSize: 9, color: Colors.black45)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // List groups (folder style)
          Expanded(child: _buildGroupedList()),

          // Note input cho phiếu đang chọn
          if (_selected != null) _buildNoteField(_selected!),
        ],
      ),
    );
  }

  /// v3.0.87: Folder-style grouped list (giống XemBenhAn)
  Widget _buildGroupedList() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final group in _groups) ...[
          // Group header (folder icon + name + count badge)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: Colors.indigo.shade50,
            child: Row(
              children: [
                const Icon(Icons.folder, size: 12, color: Colors.indigo),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    group.typeName,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.indigo,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('${group.items.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          // Items
          for (final doc in group.items) _buildDocTile(doc),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  /// v3.0.87: Item tile với check xanh (signed) + spinner (loading) + selected highlight
  Widget _buildDocTile(YTeSoDocument doc) {
    final isSelected = _selected?.id == doc.id;
    final isSigned = doc.signer.isNotEmpty;
    final isLoading = _downloading.contains(doc.id);
    final isLoaded = _docLoaded.contains(doc.id);

    return InkWell(
      onTap: () => _selectDoc(doc),
      child: Container(
        key: _docKeys.putIfAbsent(doc.id, () => GlobalKey()),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE3F2FD) : Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
            left: BorderSide(
              color: isSelected ? const Color(0xFF0D47A1) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Check icon xanh nếu signed
            if (isSigned)
              const Padding(
                padding: EdgeInsets.only(top: 1, right: 4),
                child: Icon(Icons.check_circle, size: 13, color: Colors.green),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 1, right: 4),
                child: Icon(Icons.description_outlined, size: 13, color: Colors.indigo),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (doc.code.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        doc.code,
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            // Loading spinner hoặc image icon (nếu đã load)
            if (isLoading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            else if (isLoaded)
              const Icon(Icons.image, size: 12, color: Colors.green)
            else
              const Icon(Icons.image_outlined, size: 12, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  /// v3.0.87: Note input cho phiếu đang chọn
  Widget _buildNoteField(YTeSoDocument doc) {
    final ctrl = _noteCtrls.putIfAbsent(doc.id, () => TextEditingController());
    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.edit_note, size: 14, color: Colors.amber),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: 1,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Ghi chú nhanh cho phiếu này...',
                hintStyle: TextStyle(fontSize: 11, color: Colors.black38),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () {
              _snack('Đã lưu ghi chú (chưa sync)');
            },
          ),
        ],
      ),
    );
  }

  /// v3.0.87: Right panel - PDF viewer với 4 nút tròn
  Widget _buildRightPanel() {
    return Container(
      color: const Color(0xFFEEEEEE),
      child: Column(
        children: [
          // Header phiếu đang chọn
          if (_selected != null) _buildViewerHeader(_selected!),
          // Content
          Expanded(child: _buildViewerContent()),
          // Bottom counter
          Container(
            color: const Color(0xFFE3F2FD),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.folder, size: 12, color: Color(0xFF0D47A1)),
                const SizedBox(width: 4),
                Text(
                  '${_groups.length} nhóm • ${_flatDocs.length} phiếu'
                  '${_downloading.isNotEmpty ? "  •  ⏳ ${_downloading.length}" : ""}'
                  '${_docLoaded.isNotEmpty ? "  •  ✓ ${_docLoaded.length}/${_flatDocs.length}" : ""}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF0D47A1)),
                ),
                const Spacer(),
                if (_service.accessToken != null)
                  Text(
                    '🔑${_service.accessToken!.substring(0, _service.accessToken!.length < 12 ? _service.accessToken!.length : 12)}...',
                    style: const TextStyle(fontSize: 9, color: Color(0xFF0D47A1)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewerHeader(YTeSoDocument doc) {
    final isLoaded = _docLoaded.contains(doc.id);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.name,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Text(doc.code,
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey[600])),
                    if (doc.fileType.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(doc.fileType,
                            style: const TextStyle(
                                fontSize: 9, color: Color(0xFF0D47A1))),
                      ),
                    ],
                    if (isLoaded) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check_circle, size: 10, color: Colors.green),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Pagination
          if (_selectedIndex > 0)
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 18),
              tooltip: 'Phiếu trước',
              onPressed: () =>
                  _selectDoc(_flatDocs[_selectedIndex - 1]),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          Text('${_selectedIndex + 1}/${_flatDocs.length}',
              style: const TextStyle(fontSize: 10)),
          if (_selectedIndex < _flatDocs.length - 1)
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 18),
              tooltip: 'Phiếu sau',
              onPressed: () =>
                  _selectDoc(_flatDocs[_selectedIndex + 1]),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  /// v3.0.87: Viewer content với 4 nút tròn (fullscreen, download, print, share)
  Widget _buildViewerContent() {
    if (_selected == null) {
      return Container(
        color: const Color(0xFFFAFAFA),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'Chọn 1 phiếu bên trái để xem',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '(${_flatDocs.length} phiếu • bấm "Tải hết" để xem offline)',
                style: TextStyle(color: Colors.grey[500], fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final doc = _selected!;
    final filePath = _docFilePaths[doc.id];

    if (_viewerError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Lỗi: $_viewerError',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: () => _downloadDoc(doc),
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    if (filePath == null || !File(filePath).existsSync()) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 8),
            Text('Đang tải ${doc.name}...',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // PDF hoặc ảnh
        Center(
          child: doc.fileType.toUpperCase() == 'PDF'
              ? SfPdfViewer.file(File(filePath), controller: _pdfController)
              : InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Center(
                      child: Image.file(File(filePath), fit: BoxFit.contain)),
                ),
        ),

        // v3.0.87: 4 nút tròn (fullscreen, download, print, share) - giống XemBenhAn
        Positioned(
          right: 8,
          bottom: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _circleBtn(Icons.fullscreen, _goFullscreen, tooltip: 'Toàn màn hình'),
              const SizedBox(height: 6),
              _circleBtn(
                Icons.download,
                _savingPdf ? null : _downloadSelected,
                loading: _savingPdf,
                tooltip: 'Tải xuống',
              ),
              const SizedBox(height: 6),
              _circleBtn(Icons.print, _printSelected, tooltip: 'In'),
              const SizedBox(height: 6),
              _circleBtn(Icons.share, _shareSelected, tooltip: 'Chia sẻ'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback? onTap,
      {bool loading = false, String tooltip = ''}) {
    final btn = Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 18, color: const Color(0xFF0D47A1)),
        ),
      ),
    );
    return Tooltip(message: tooltip, child: btn);
  }

  /// v3.0.89: Fullscreen PageView - swipe giữa các phiếu (giống XemBenhAn)
  Widget _buildFullscreen() {
    final currentIndex = _selectedIndex >= 0 ? _selectedIndex : 0;
    final canPrev = currentIndex > 0;
    final canNext = currentIndex < _flatDocs.length - 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // PageView cho phép vuốt trái/phải giữa các phiếu
          PageView.builder(
            controller: _pageController,
            itemCount: _flatDocs.length,
            onPageChanged: (idx) {
              if (idx >= 0 && idx < _flatDocs.length) {
                final newDoc = _flatDocs[idx];
                setState(() => _selected = newDoc);
                // Auto-download nếu chưa có bytes
                if (!_docFilePaths.containsKey(newDoc.id)) {
                  _downloadDoc(newDoc);
                }
              }
            },
            itemBuilder: (ctx, idx) {
              final doc = _flatDocs[idx];
              final filePath = _docFilePaths[doc.id];
              if (filePath == null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 12),
                      Text(
                        'Đang tải ${doc.name}...',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }
              final isImage = doc.fileType.toUpperCase() != 'PDF';
              if (isImage) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Center(
                      child: Image.file(File(filePath), fit: BoxFit.contain)),
                );
              }
              return SfPdfViewer.file(File(filePath));
            },
          ),

          // Top bar: back, title, counter, < >, download
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _exitFullscreen,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selected?.name ?? '',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_flatDocs.isNotEmpty)
                            Text(
                              '${currentIndex + 1} / ${_flatDocs.length}  •  Vuốt trái/phải để chuyển',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: canPrev ? () => _goToDocFs(currentIndex - 1) : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white),
                      onPressed: canNext ? () => _goToDocFs(currentIndex + 1) : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.white),
                      onPressed:
                          _savingPdf ? null : () => _downloadSelected(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
