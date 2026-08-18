// image_pdf_service.dart v3.0.145
//
// Convert PNG/JPEG bytes → PDF bytes (image-only, no text).
// The resulting PDF contains ONLY the image → no font rendering on EMR server.
//
// This is used when we have a pre-rendered PNG of the form
// (via PdfToImageService or widget screenshot) and want to push to EMR
// without any text that could garble on the server's PDF viewer.

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Convert image bytes (PNG/JPEG) → PDF bytes containing just that image.
/// The PDF has NO text elements - only the image embedded.
/// This ensures EMR server displays the form correctly regardless of fonts.
Future<Uint8List?> imageBytesToPdf(Uint8List imageBytes, {
  PdfPageFormat pageFormat = PdfPageFormat.a4,
  String? documentName,
}) async {
  try {
    final doc = pw.Document();
    final image = pw.MemoryImage(imageBytes);

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          return pw.Center(
            child: pw.Image(
              image,
              fit: pw.BoxFit.contain,
              // A4 at 1x = 595x842 points
              // Image will scale to fit page while maintaining aspect ratio
            ),
          );
        },
      ),
    );

    return doc.save();
  } catch (e) {
    return null;
  }
}
