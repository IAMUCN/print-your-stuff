import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../theme/app_theme.dart';

class PdfPreviewDialog extends StatelessWidget {
  final Uint8List pdfBytes;
  final String title;

  const PdfPreviewDialog({
    super.key,
    required this.pdfBytes,
    required this.title,
  });

  static Future<void> show(BuildContext context, Uint8List pdfBytes, String title) async {
    await showDialog(
      context: context,
      builder: (ctx) => PdfPreviewDialog(pdfBytes: pdfBytes, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf, size: 20, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Preview: $title',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close Preview',
                ),
              ],
            ),
          ),
          // PDF Viewer
          Expanded(
            child: PdfPreview(
              build: (PdfPageFormat format) async => pdfBytes,
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowPrinting: false,
              allowSharing: true,
              canDebug: false,
              pdfFileName: '$title.pdf',
            ),
          ),
        ],
      ),
    );
  }
}
