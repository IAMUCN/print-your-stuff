import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class LibreOfficeService {
  // Global notifiers for UI live status banner
  static final ValueNotifier<bool> isConverting = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> currentConvertingFile = ValueNotifier<String?>(null);

  /// Converts a Word document (DOC/DOCX) to PDF using headless LibreOffice
  static Future<File> convertDocToPdf(File inputFile) async {
    String libreOfficePath = await StorageService.getLibreOfficePath();
    final filename = inputFile.uri.pathSegments.last;

    if (!await File(libreOfficePath).exists()) {
      const fallbackPaths = [
        r'C:\Program Files\LibreOffice\program\soffice.exe',
        r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
      ];
      String? detected;
      for (final p in fallbackPaths) {
        if (await File(p).exists()) {
          detected = p;
          break;
        }
      }
      if (detected != null) {
        libreOfficePath = detected;
        await StorageService.setLibreOfficePath(detected);
      } else {
        throw Exception(
          'LibreOffice was not found at "$libreOfficePath". Please install LibreOffice or save your document as a PDF before uploading.',
        );
      }
    }

    // Set live conversion state
    isConverting.value = true;
    currentConvertingFile.value = filename;

    try {
      final tempDir = await getTemporaryDirectory();
      final outDir = Directory('${tempDir.path}\\hostel_print_converted');
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }

      final result = await Process.run(
        libreOfficePath,
        [
          '--headless',
          '--convert-to',
          'pdf',
          '--outdir',
          outDir.path,
          inputFile.path,
        ],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        throw Exception(
          'LibreOffice conversion failed (exit code ${result.exitCode}):\n${result.stderr}',
        );
      }

      // Converted file has the same base name with .pdf extension
      final baseName = filename.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final expectedPdfPath = '${outDir.path}\\$baseName.pdf';
      final pdfFile = File(expectedPdfPath);

      if (!await pdfFile.exists()) {
        throw Exception('Converted PDF not found at: $expectedPdfPath');
      }

      return pdfFile;
    } finally {
      isConverting.value = false;
      currentConvertingFile.value = null;
    }
  }
}
