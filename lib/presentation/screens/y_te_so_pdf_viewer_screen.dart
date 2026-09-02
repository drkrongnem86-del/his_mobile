// v3.0.84: YTeSoPdfViewerScreen - PDF viewer với toolbar đầy đủ
// v3.0.91: Thêm prev/next DOC navigation (mũi tên chuyển phiếu)
//
// Tính năng (giống XemBenhAnScreen fullscreen):
//   - Hiển thị PDF/ảnh bằng syncfusion_flutter_pdfviewer
//   - Toolbar: Back, Title, Counter, < > PDF page, < > DOC, Fullscreen, Download, Share
//   - Download: lưu vào /storage/emulated/0/Download
//   - Share: qua Printing.sharePdf
//   - Ảnh: dùng InteractiveViewer với zoom

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// v3.0.91: Minimal doc info để chuyển phiếu (chỉ cần path)
class YTeSoDocItem {
  final int id;
  final String code;
  final String name;
  final String fileType;
  final String filePath;
  final String treatmentCode;
  YTeSoDocItem({
    required this.id,
    required this.code,
    required this.name,
    required this.fileType,
    required this.filePath,
    required this.treatmentCode,
  });
}

class YTeSoPdfViewerScreen extends StatefulWidget {
  /// Đường dẫn file local (PDF hoặc ảnh)
  final String filePath;
  /// Tên tài liệu (hiển thị trên toolbar)
  final String title;
  /// Mã tài liệu
  final String docCode;
  /// Loại file: PDF, JPG, PNG
  final String fileType;
  /// Tên bệnh nhân
  final String? patientName;
  /// Mã điều trị (dùng cho tên file khi download)
  final String? treatmentCode;

  /// v3.0.91: List tất cả phiếu + callback để mở phiếu khác
  /// Nếu null → không có nút prev/next doc
  final List<YTeSoDocItem>? allDocs;
  final int? currentDocIndex;
  /// Callback async trả về YTeSoDocItem mới (file mới đã download xong)
  /// Nếu null → dùng path trong allDocs (đã có sẵn)
  final Future<YTeSoDocItem?> Function(YTeSoDocItem doc)? onLoadDoc;

  const YTeSoPdfViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
    required this.docCode,
    this.fileType = 'PDF',
    this.patientName,
    this.treatmentCode,
    this.allDocs,
    this.currentDocIndex,
    this.onLoadDoc,
  });

  @override
  State<YTeSoPdfViewerScreen> createState() => _YTeSoPdfViewerScreenState();
}

class _YTeSoPdfViewerScreenState extends State<YTeSoPdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  bool _saving = false;
  bool _immersive = false;
  int _currentPage = 1;
  int _totalPages = 0;
  // v3.0.91: Track current doc for prev/next nav
  late YTeSoDocItem _currentDoc;
  late int _docIndex;
  bool _loadingDoc = false;

  @override
  void initState() {
    super.initState();
    _setImmersive(false);
    _currentDoc = YTeSoDocItem(
      id: 0,
      code: widget.docCode,
      name: widget.title,
      fileType: widget.fileType,
      filePath: widget.filePath,
      treatmentCode: widget.treatmentCode ?? '',
    );
    _docIndex = widget.currentDocIndex ?? 0;
  }

  @override
  void dispose() {
    _setImmersive(false);
    super.dispose();
  }

  void _setImmersive(bool on) {
    if (on != _immersive) {
      _immersive = on;
      SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  bool get _isImage =>
      ['JPG', 'JPEG', 'PNG'].contains(_currentDoc.fileType.toUpperCase());

  Future<Uint8List?> _readBytes() async {
    try {
      final f = File(_currentDoc.filePath);
      if (await f.exists()) {
        return await f.readAsBytes();
      }
    } catch (e) {
      debugPrint('YTeSoPdfViewer: read error: $e');
    }
    return null;
  }

  /// v3.0.91: Build subtitle showing doc counter + page counter
  String _buildSubtitle() {
    final parts = <String>[];
    if (widget.allDocs != null && widget.allDocs!.isNotEmpty) {
      parts.add('${_docIndex + 1}/${widget.allDocs!.length}');
    }
    parts.add(_currentDoc.code);
    if (_totalPages > 0) {
      parts.add('Trang $_currentPage/$_totalPages');
    }
    return parts.join('  •  ');
  }

  bool _hasPrevDoc() =>
      widget.allDocs != null &&
      widget.allDocs!.isNotEmpty &&
      _docIndex > 0;

  bool _hasNextDoc() =>
      widget.allDocs != null &&
      widget.allDocs!.isNotEmpty &&
      _docIndex < widget.allDocs!.length - 1;

  /// v3.0.91: Navigate to prev/next doc
  Future<void> _goToDoc(int newIndex) async {
    if (widget.allDocs == null) return;
    if (newIndex < 0 || newIndex >= widget.allDocs!.length) return;
    final target = widget.allDocs![newIndex];
    setState(() {
      _loadingDoc = true;
      _docIndex = newIndex;
    });

    YTeSoDocItem finalDoc = target;
    // Nếu có callback (YTeSoScreen.downloadDoc) → download file trước
    if (widget.onLoadDoc != null) {
      try {
        final loaded = await widget.onLoadDoc!(target);
        if (loaded != null) {
          finalDoc = loaded;
        }
      } catch (e) {
        debugPrint('YTeSoPdfViewer: onLoadDoc error: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _currentDoc = finalDoc;
      _currentPage = 1;
      _totalPages = 0;
      _loadingDoc = false;
    });
    // Reset PDF controller bằng cách thay key (dùng id làm key)
  }

  Future<void> _goToPrevDoc() => _goToDoc(_docIndex - 1);
  Future<void> _goToNextDoc() => _goToDoc(_docIndex + 1);

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _readBytes();
      if (bytes == null) {
        _snack('Không đọc được file', isError: true);
        return;
      }
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
      final ext = _isImage
          ? _currentDoc.fileType.toLowerCase()
          : (_currentDoc.fileType.isEmpty
              ? 'pdf'
              : _currentDoc.fileType.toLowerCase());
      final code = _currentDoc.code.isNotEmpty ? _currentDoc.code : 'yte_so';
      final tc = _currentDoc.treatmentCode;
      final filename = tc.isNotEmpty
          ? 'BA_${tc}_$code.$ext'
          : 'BA_$code.$ext';
      final file = File('${targetDir.path}/$filename');
      await file.writeAsBytes(bytes);
      _snack('Đã lưu: ${file.path}');
    } catch (e) {
      _snack('Lỗi lưu: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _readBytes();
      if (bytes == null) {
        _snack('Không đọc được file', isError: true);
        return;
      }
      final ext = _isImage
          ? _currentDoc.fileType.toLowerCase()
          : (_currentDoc.fileType.isEmpty
              ? 'pdf'
              : _currentDoc.fileType.toLowerCase());
      final code = _currentDoc.code.isNotEmpty ? _currentDoc.code : 'yte_so';
      final filename = 'BA_$code.$ext';
      try {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } catch (_) {
        _snack('Đã lưu, dùng file manager để chia sẻ');
      }
    } catch (e) {
      _snack('Lỗi chia sẻ: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _immersive
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_currentDoc.name,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    _buildSubtitle(),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
              actions: [
                // v3.0.92: Toolbar < > đồng bộ với ⏮ ⏭ - cả 2 đều chuyển phiếu
                if (_hasPrevDoc())
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Phiếu trước (←)',
                    onPressed: _loadingDoc ? null : _goToPrevDoc,
                  )
                else
                  const IconButton(
                    icon: Icon(Icons.chevron_left, color: Colors.white24),
                    onPressed: null,
                    tooltip: 'Phiếu trước',
                  ),
                if (_hasNextDoc())
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Phiếu sau (→)',
                    onPressed: _loadingDoc ? null : _goToNextDoc,
                  )
                else
                  const IconButton(
                    icon: Icon(Icons.chevron_right, color: Colors.white24),
                    onPressed: null,
                    tooltip: 'Phiếu sau',
                  ),
                // v3.0.92: ⏮ ⏭ - skip to first/last doc
                if (_hasPrevDoc())
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    tooltip: 'Phiếu đầu',
                    onPressed: _loadingDoc ? null : () => _goToDoc(0),
                  )
                else
                  const IconButton(
                    icon: Icon(Icons.skip_previous, color: Colors.white24),
                    onPressed: null,
                    tooltip: 'Phiếu đầu',
                  ),
                if (_hasNextDoc())
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    tooltip: 'Phiếu cuối',
                    onPressed:
                        _loadingDoc ? null : () => _goToDoc(widget.allDocs!.length - 1),
                  )
                else
                  const IconButton(
                    icon: Icon(Icons.skip_next, color: Colors.white24),
                    onPressed: null,
                    tooltip: 'Phiếu cuối',
                  ),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'Toàn màn hình',
                  onPressed: () => setState(() => _setImmersive(true)),
                ),
                _saving
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download),
                        tooltip: 'Tải xuống',
                        onPressed: _download,
                      ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Chia sẻ',
                  onPressed: _share,
                ),
              ],
            ),
      body: GestureDetector(
        // v3.0.92: Vuốt trái/phải để chuyển phiếu (cùng chức năng với < > ⏮ ⏭)
        onHorizontalDragEnd: (details) {
          if (_loadingDoc) return;
          final v = details.primaryVelocity ?? 0;
          // Vuốt trái (v < -300) → phiếu sau
          if (v < -300 && _hasNextDoc()) {
            _goToNextDoc();
          }
          // Vuốt phải (v > 300) → phiếu trước
          else if (v > 300 && _hasPrevDoc()) {
            _goToPrevDoc();
          }
        },
        child: Stack(
          children: [
            // v3.0.91: Show loading khi đang chuyển doc
            if (_loadingDoc)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text('Đang tải phiếu...',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              )
            else
              Center(
                // v3.0.91: Key based on doc id để force rebuild khi chuyển doc
                key: ValueKey('pdf-${_currentDoc.id}'),
                child: _isImage
                    ? FutureBuilder<Uint8List?>(
                        future: _readBytes(),
                        builder: (ctx, snap) {
                          if (!snap.hasData) {
                            return const CircularProgressIndicator(
                                color: Colors.white);
                          }
                          return InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 5.0,
                            child: Image.memory(snap.data!, fit: BoxFit.contain),
                          );
                        },
                      )
                    : SfPdfViewer.file(
                        File(_currentDoc.filePath),
                        key: ValueKey('sfpdf-${_currentDoc.id}'),
                        controller: _pdfController,
                        onPageChanged: (details) {
                          if (mounted) {
                            setState(() {
                              _currentPage = details.newPageNumber;
                            });
                          }
                        },
                        onDocumentLoaded: (details) {
                          if (mounted) {
                            setState(() {
                              _totalPages = details.document.pages.count;
                            });
                          }
                        },
                      ),
              ),
            // Nút thoát fullscreen
            if (_immersive)
              Positioned(
                top: 16,
                right: 16,
                child: SafeArea(
                  child: Material(
                    color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                    tooltip: 'Thoát toàn màn hình',
                    onPressed: () => setState(() => _setImmersive(false)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
