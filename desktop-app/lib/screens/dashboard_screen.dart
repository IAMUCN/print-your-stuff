import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/job.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../services/storage_service.dart';
import '../services/libreoffice_service.dart';
import '../theme/app_theme.dart';
import '../widgets/printer_status_chip.dart';
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../widgets/conversion_banner.dart';
import '../widgets/libreoffice_approval_dialog.dart';
import '../widgets/pdf_preview_dialog.dart';
import '../widgets/image_preview_dialog.dart';
import '../widgets/driver_diagnostics_dialog.dart';
import '../widgets/settings_dialog.dart';
import 'login_screen.dart';

enum DashboardTab { activeQueue, completedJobs }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardTab _currentTab = DashboardTab.activeQueue;
  List<PrintJob> _queue = [];
  List<PrintJob> _history = [];
  PrintJob? _selectedJob;
  bool _loading = true;
  String _searchQuery = '';
  PrinterConnectionStatus _printerStatus = PrinterConnectionStatus.checking;
  Timer? _pollingTimer;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _initialLoad();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    await Future.wait([
      _fetchQueue(),
      _fetchHistory(),
      _checkPrinter(),
    ]);
  }

  void _startPolling() async {
    final interval = await StorageService.getPollingInterval();
    _pollingTimer = Timer.periodic(Duration(seconds: interval), (_) {
      if (_isPrinting) return; // Never desync UI mid-print
      _fetchQueue(silent: true);
      _fetchHistory(silent: true);
      _checkPrinter();
    });
  }

  Future<void> _checkPrinter() async {
    final status = await PrinterService.checkPrinterStatus();
    if (mounted) setState(() => _printerStatus = status);
  }

  Future<void> _fetchQueue({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final queue = await ApiService.getQueue();
      if (mounted) {
        setState(() {
          _queue = queue;
          _loading = false;
          if (_currentTab == DashboardTab.activeQueue) {
            if (_selectedJob != null) {
              final inQueue = _queue.any((j) => j.id == _selectedJob!.id);
              if (inQueue) {
                _selectedJob = _queue.firstWhere((j) => j.id == _selectedJob!.id);
              } else if (_queue.isNotEmpty) {
                _selectedJob = _queue.first;
              } else {
                _selectedJob = null;
              }
            } else if (_queue.isNotEmpty) {
              _selectedJob = _queue.first;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load queue: $e')),
          );
        }
      }
    }
  }

  Future<void> _fetchHistory({bool silent = false}) async {
    try {
      final history = await ApiService.getHistory();
      if (mounted) {
        setState(() {
          _history = history;
          if (_currentTab == DashboardTab.completedJobs) {
            if (_selectedJob != null) {
              final inHistory = _history.any((j) => j.id == _selectedJob!.id);
              if (inHistory) {
                _selectedJob = _history.firstWhere((j) => j.id == _selectedJob!.id);
              } else if (_history.isNotEmpty) {
                _selectedJob = _history.first;
              } else {
                _selectedJob = null;
              }
            } else if (_history.isNotEmpty) {
              _selectedJob = _history.first;
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshAll({bool silent = false}) async {
    await Future.wait([
      _fetchQueue(silent: silent),
      _fetchHistory(silent: silent),
      _checkPrinter(),
    ]);
  }

  List<PrintJob> get _filteredQueue {
    if (_searchQuery.trim().isEmpty) return _queue;
    final rawQ = _searchQuery.trim().toLowerCase();
    final cleanCodeQ = rawQ.replaceFirst('#', '').trim();
    return _queue.where((job) {
      final codeStr = job.jobCode?.toString() ?? '';
      final codeMatch = codeStr.contains(rawQ) || (cleanCodeQ.isNotEmpty && codeStr.contains(cleanCodeQ));
      final nameMatch = job.studentName.toLowerCase().contains(rawQ);
      return codeMatch || nameMatch;
    }).toList();
  }

  List<PrintJob> get _filteredHistory {
    if (_searchQuery.trim().isEmpty) return _history;
    final rawQ = _searchQuery.trim().toLowerCase();
    final cleanCodeQ = rawQ.replaceFirst('#', '').trim();
    return _history.where((job) {
      final codeStr = job.jobCode?.toString() ?? '';
      final codeMatch = codeStr.contains(rawQ) || (cleanCodeQ.isNotEmpty && codeStr.contains(cleanCodeQ));
      final nameMatch = job.studentName.toLowerCase().contains(rawQ);
      return codeMatch || nameMatch;
    }).toList();
  }

  List<PrintJob> get _currentList =>
      _currentTab == DashboardTab.activeQueue ? _filteredQueue : _filteredHistory;

  // --- Job Actions ---

  Future<void> _previewFile(JobFile file) async {
    if (_selectedJob == null) return;
    try {
      if (file.inputType == 'IMAGE') {
        final imageBytes = await ApiService.downloadFileBytes(_selectedJob!.id, file.id);
        if (!mounted) return;
        await ImagePreviewDialog.show(
          context,
          imageBytes,
          file.filename,
          onViewPrintLayout: () => _previewComposedPdf(),
        );
        return;
      }

      if (file.inputType == 'DOCX' || file.inputType == 'DOC') {
        await _convertDocx(file);
        return;
      }

      final bytes = await ApiService.downloadFileBytes(_selectedJob!.id, file.id);
      if (!mounted) return;
      await PdfPreviewDialog.show(context, bytes, file.filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not preview file: $e')),
        );
      }
    }
  }

  Future<void> _previewComposedPdf() async {
    if (_selectedJob == null) return;
    try {
      Uint8List pdfBytes;
      try {
        pdfBytes = await ApiService.downloadComposedPdfBytes(_selectedJob!.id);
      } catch (_) {
        pdfBytes = await _generateFallbackImagePdf(_selectedJob!);
      }
      if (!mounted) return;
      await PdfPreviewDialog.show(context, pdfBytes, 'Print Layout (#${_selectedJob!.jobCode})');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate print preview: $e')),
        );
      }
    }
  }

  Future<Uint8List> _generateFallbackImagePdf(PrintJob job) async {
    final pdf = pw.Document();
    final imageFiles = job.files.where((f) => f.inputType == 'IMAGE').toList();
    for (final imgFile in imageFiles) {
      final imgBytes = await ApiService.downloadFileBytes(job.id, imgFile.id);
      final image = pw.MemoryImage(imgBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }
    return await pdf.save();
  }

  Future<Uint8List> _convertPdfToGrayscalePdf(Uint8List pdfBytes) async {
    try {
      final doc = pw.Document();
      await for (final page in Printing.raster(pdfBytes, dpi: 300)) {
        final imageBytes = await page.toPng();
        final decoded = img.decodeImage(imageBytes);
        if (decoded != null) {
          final grayscale = img.grayscale(decoded);
          final grayscalePng = Uint8List.fromList(img.encodePng(grayscale));
          final pwImage = pw.MemoryImage(grayscalePng);

          final widthPt = (page.width * 72.0) / 300.0;
          final heightPt = (page.height * 72.0) / 300.0;

          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(
                widthPt,
                heightPt,
                marginTop: 0,
                marginBottom: 0,
                marginLeft: 0,
                marginRight: 0,
              ),
              margin: pw.EdgeInsets.zero,
              build: (pw.Context context) {
                return pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Image(pwImage, fit: pw.BoxFit.fill),
                );
              },
            ),
          );
        }
      }
      return await doc.save();
    } catch (e) {
      debugPrint('Error converting PDF to grayscale: $e');
      return pdfBytes;
    }
  }

  Future<void> _convertDocx(JobFile file) async {
    if (_selectedJob == null) return;

    final askApproval = await StorageService.getAskApprovalBeforeConversion();
    if (askApproval) {
      if (!mounted) return;
      final approved = await LibreOfficeApprovalDialog.show(context, file.filename);
      if (!approved) return;
    }

    try {
      final bytes = await ApiService.downloadFileBytes(_selectedJob!.id, file.id);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}\\${file.filename}');
      await tempFile.writeAsBytes(bytes);

      final pdfFile = await LibreOfficeService.convertDocToPdf(tempFile);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Successfully converted "${file.filename}" to PDF!')),
      );
      final pdfBytes = await pdfFile.readAsBytes();
      if (!mounted) return;
      await PdfPreviewDialog.show(context, pdfBytes, '${file.filename} (Converted)');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conversion error: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile(JobFile file) async {
    if (_selectedJob == null) return;
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏳ Downloading "${file.filename}"...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      final bytes = await ApiService.downloadFileBytes(_selectedJob!.id, file.id);
      Directory? downloadsDir;
      try {
        downloadsDir = await getDownloadsDirectory();
      } catch (_) {}
      downloadsDir ??= Directory('${Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default'}\\Downloads');

      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      String savePath = '${downloadsDir.path}\\${file.filename}';
      int counter = 1;
      final dotIdx = file.filename.lastIndexOf('.');
      final fileBase = dotIdx != -1 ? file.filename.substring(0, dotIdx) : file.filename;
      final ext = dotIdx != -1 ? file.filename.substring(dotIdx) : '';

      while (await File(savePath).exists()) {
        savePath = '${downloadsDir.path}\\${fileBase}_$counter$ext';
        counter++;
      }

      final savedFile = File(savePath);
      await savedFile.writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💾 Saved "${savedFile.uri.pathSegments.last}" to Downloads!'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OPEN FOLDER',
            onPressed: () {
              Process.run('explorer.exe', ['/select,', savedFile.path]);
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _printSingleFile(JobFile file, {bool useDialog = false}) async {
    if (_selectedJob == null) return;
    final job = _selectedJob!;

    final globalQuality = await StorageService.getGlobalQuality();
    final globalDpi = await StorageService.getGlobalDpi();

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🖨️ Preparing "${file.filename}" for printing...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      Uint8List pdfBytes;
      if (file.inputType == 'IMAGE') {
        try {
          pdfBytes = await ApiService.downloadComposedPdfBytes(job.id);
        } catch (_) {
          pdfBytes = await _generateFallbackImagePdf(job);
        }
      } else if (file.inputType == 'DOCX' || file.inputType == 'DOC') {
        final rawBytes = await ApiService.downloadFileBytes(job.id, file.id);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}\\${file.filename}');
        await tempFile.writeAsBytes(rawBytes);
        final convertedPdf = await LibreOfficeService.convertDocToPdf(tempFile);
        pdfBytes = await convertedPdf.readAsBytes();
      } else {
        pdfBytes = await ApiService.downloadFileBytes(job.id, file.id);
      }

      final effectiveColorMode = file.settings.colorMode;
      Uint8List printableBytes = pdfBytes;
      if (effectiveColorMode.toUpperCase() == 'BW' && file.inputType == 'IMAGE') {
        printableBytes = await _convertPdfToGrayscalePdf(pdfBytes);
      }

      final docJobName = 'Job_${job.jobCode}_${file.filename}';
      final bool success;

      if (useDialog) {
        success = await PrinterService.printWithDialog(
          pdfBytes: printableBytes,
          jobName: docJobName,
          colorMode: effectiveColorMode,
          quality: globalQuality,
          dpi: globalDpi,
        );
      } else {
        success = await PrinterService.printPdfBytes(
          pdfBytes: printableBytes,
          jobName: docJobName,
          copies: file.settings.copies,
          colorMode: effectiveColorMode,
          quality: globalQuality,
          dpi: globalDpi,
        );
      }

      if (!success) {
        throw Exception('Windows print spooler rejected or cancelled ${file.filename}');
      }

      if (!useDialog) {
        final targetPrinterName = await StorageService.getPrinterName();
        final spoolerStatus = await PrinterService.trackJobCompletion(
          printerName: targetPrinterName,
          docPattern: 'Job_${job.jobCode}',
          onProgress: (status) {
            if (mounted && status.message != null) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('🖨️ ${status.message}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        );

        if (spoolerStatus.state == SpoolerState.cancelled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ Print of "${file.filename}" was CANCELLED at printer.'),
                backgroundColor: Colors.orangeAccent.shade700,
              ),
            );
          }
          return;
        }

        if (spoolerStatus.state == SpoolerState.error || spoolerStatus.state == SpoolerState.jammed) {
          throw Exception(spoolerStatus.message ?? 'Printer hardware error occurred');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Successfully printed "${file.filename}"!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _editFileSettings(JobFile file) async {
    if (_selectedJob == null) return;

    int copies = file.settings.copies;
    String colorMode = file.settings.colorMode;
    String pageRange = file.settings.pageRange ?? '';
    String orientation = file.settings.orientation;
    String imageLayout = file.settings.imageLayout;
    final isImage = file.inputType == 'IMAGE';

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text('Edit Settings: ${file.filename}', style: const TextStyle(fontSize: 16)),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Copies:'),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: copies > 1 ? () => setModalState(() => copies--) : null,
                            ),
                            Text('$copies', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: copies < 50 ? () => setModalState(() => copies++) : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Color Mode:'),
                        DropdownButton<String>(
                          value: colorMode,
                          items: const [
                            DropdownMenuItem(value: 'BW', child: Text('Black & White')),
                            DropdownMenuItem(value: 'COLOR', child: Text('Full Color')),
                          ],
                          onChanged: (val) {
                            if (val != null) setModalState(() => colorMode = val);
                          },
                        ),
                      ],
                    ),
                    if (isImage) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Orientation:'),
                          DropdownButton<String>(
                            value: orientation == 'LANDSCAPE' ? 'LANDSCAPE' : 'PORTRAIT',
                            items: const [
                              DropdownMenuItem(value: 'PORTRAIT', child: Text('📱 Portrait')),
                              DropdownMenuItem(value: 'LANDSCAPE', child: Text('🔄 Landscape')),
                            ],
                            onChanged: (val) {
                              if (val != null) setModalState(() => orientation = val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Layout:'),
                          DropdownButton<String>(
                            value: imageLayout == 'TWO_PER_PAGE' ? 'TWO_PER_PAGE' : 'ONE_PER_PAGE',
                            items: const [
                              DropdownMenuItem(value: 'ONE_PER_PAGE', child: Text('1 Image / Page')),
                              DropdownMenuItem(value: 'TWO_PER_PAGE', child: Text('2 Images / Page')),
                            ],
                            onChanged: (val) {
                              if (val != null) setModalState(() => imageLayout = val);
                            },
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: TextEditingController(text: pageRange),
                        decoration: const InputDecoration(
                          labelText: 'Page Range (optional)',
                          hintText: 'e.g. 1-5, or leave blank for all',
                        ),
                        onChanged: (v) => pageRange = v,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      final newSettings = file.settings.copyWith(
        copies: copies,
        colorMode: colorMode,
        pageRange: pageRange.trim().isEmpty ? null : pageRange.trim(),
        orientation: orientation,
        imageLayout: imageLayout,
      );

      try {
        await ApiService.updateSettings(_selectedJob!.id, file.id, newSettings);
        await _fetchQueue(silent: true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update settings: $e')),
          );
        }
      }
    }
  }

  Future<void> _printJob({bool useDialog = false}) async {
    if (_selectedJob == null) return;
    final job = _selectedJob!;

    final globalQuality = await StorageService.getGlobalQuality();
    final globalDpi = await StorageService.getGlobalDpi();

    if (!useDialog) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.print, size: 22),
              const SizedBox(width: 10),
              Text('Confirm Print: #${job.jobCode ?? 'Pending'}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Student: ${job.studentName}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Files: ${job.files.length} file(s) · Est. ${job.totalSheetsEst} output sheets'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tune, size: 16, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Driver Config: Quality: $globalQuality · $globalDpi DPI · Color as requested',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      _printerStatus == PrinterConnectionStatus.online ? Icons.check_circle : Icons.warning,
                      size: 16,
                      color: _printerStatus == PrinterConnectionStatus.online ? Colors.greenAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _printerStatus == PrinterConnectionStatus.online
                            ? 'Target printer is ONLINE & ready.'
                            : 'Printer is OFFLINE! Verify power and USB cable.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Back')),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('CONFIRM PRINT'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    try {
      setState(() => _isPrinting = true);
      await ApiService.updateStatus(job.id, 'PRINTING');
      await _refreshAll(silent: true);

      bool composedImagePrinted = false;

      // Print each file in the job sequentially
      for (int fIdx = 0; fIdx < job.files.length; fIdx++) {
        final file = job.files[fIdx];

        // Give the Windows Print Spooler and physical USB port 2.5 seconds to settle between documents
        if (fIdx > 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⏳ Preparing document ${fIdx + 1} of ${job.files.length}: ${file.filename}...'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          await Future.delayed(const Duration(milliseconds: 2500));
        }
        Uint8List pdfBytes;
        if (file.inputType == 'IMAGE') {
          if (composedImagePrinted) {
            continue; // Prevent printing composed images multiple times
          }
          composedImagePrinted = true;
          try {
            pdfBytes = await ApiService.downloadComposedPdfBytes(job.id);
          } catch (_) {
            pdfBytes = await _generateFallbackImagePdf(job);
          }
        } else if (file.inputType == 'DOCX' || file.inputType == 'DOC') {
          final rawBytes = await ApiService.downloadFileBytes(job.id, file.id);
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}\\${file.filename}');
          await tempFile.writeAsBytes(rawBytes);
          final convertedPdf = await LibreOfficeService.convertDocToPdf(tempFile);
          pdfBytes = await convertedPdf.readAsBytes();
        } else {
          pdfBytes = await ApiService.downloadFileBytes(job.id, file.id);
        }

        // Strictly respect the file's submitted color mode
        final effectiveColorMode = file.settings.colorMode;

        // If Black & White image, convert to pure grayscale to ensure the printer driver receives only R=G=B pixels
        // (Vector PDFs are natively handled in grayscale by driver via Set-PrintConfiguration -Color:0)
        Uint8List printableBytes = pdfBytes;
        if (effectiveColorMode.toUpperCase() == 'BW' && file.inputType == 'IMAGE') {
          printableBytes = await _convertPdfToGrayscalePdf(pdfBytes);
        }

        final bool success;
        final docJobName = 'Job_${job.jobCode}_${file.filename}';

        if (useDialog) {
          success = await PrinterService.printWithDialog(
            pdfBytes: printableBytes,
            jobName: docJobName,
            colorMode: effectiveColorMode,
            quality: globalQuality,
            dpi: globalDpi,
          );
        } else {
          success = await PrinterService.printPdfBytes(
            pdfBytes: printableBytes,
            jobName: docJobName,
            copies: file.settings.copies,
            colorMode: effectiveColorMode,
            quality: globalQuality,
            dpi: globalDpi,
          );
        }

        if (!success) {
          throw Exception('Windows print spooler rejected or cancelled ${file.filename}');
        }

        if (!useDialog) {
          final targetPrinterName = await StorageService.getPrinterName();
          // Real-time tracking of the physical printer and spooler job lifecycle
          final spoolerStatus = await PrinterService.trackJobCompletion(
            printerName: targetPrinterName,
            docPattern: 'Job_${job.jobCode}',
            onProgress: (status) {
              if (mounted && status.message != null) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🖨️ ${status.message}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          );

          if (spoolerStatus.state == SpoolerState.cancelled) {
            await ApiService.updateStatus(job.id, 'CANCELLED', errorMessage: 'Print job cancelled at printer');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚠️ Job #${job.jobCode} was CANCELLED on the printer.'),
                  backgroundColor: Colors.orangeAccent.shade700,
                  duration: const Duration(seconds: 6),
                ),
              );
            }
            await _refreshAll(silent: true);
            return;
          }

          if (spoolerStatus.state == SpoolerState.error || spoolerStatus.state == SpoolerState.jammed) {
            throw Exception(spoolerStatus.message ?? 'Printer hardware error occurred during printing');
          }
        }
      }

      final printerName = await StorageService.getPrinterName();
      await ApiService.updateStatus(job.id, 'PRINTED', printerName: printerName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Job #${job.jobCode} printed successfully!')),
        );
      }
      await _refreshAll(silent: true);
      if (mounted) {
        setState(() {
          if (_queue.isEmpty && _history.isNotEmpty) {
            _currentTab = DashboardTab.completedJobs;
            _selectedJob = _history.firstWhere(
              (j) => j.id == job.id,
              orElse: () => _history.first,
            );
          } else if (_queue.isNotEmpty) {
            _selectedJob = _queue.first;
          } else {
            _selectedJob = null;
          }
        });
      }
    } catch (e) {
      await ApiService.updateStatus(job.id, 'FAILED', errorMessage: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e'),
            duration: const Duration(seconds: 8),
            action: !useDialog
                ? SnackBarAction(
                    label: 'Open Dialog',
                    textColor: Colors.yellowAccent,
                    onPressed: () => _printJob(useDialog: true),
                  )
                : null,
          ),
        );
      }
      await _refreshAll(silent: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _moveToActiveQueue(PrintJob job) async {
    try {
      await ApiService.updateStatus(job.id, 'WAITING');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Job #${job.jobCode} moved back to Active Queue')),
        );
      }
      await _refreshAll(silent: true);
      setState(() {
        _currentTab = DashboardTab.activeQueue;
        _selectedJob = _queue.firstWhere((j) => j.id == job.id, orElse: () => job);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to re-queue job: $e')),
        );
      }
    }
  }

  Future<void> _cancelJob() async {
    if (_selectedJob == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel Job #${_selectedJob!.jobCode}?'),
        content: const Text('Are you sure you want to cancel and remove this print job?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel Job'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ApiService.updateStatus(_selectedJob!.id, 'CANCELLED');
      await _refreshAll();
    }
  }

  void _logout() async {
    await StorageService.setToken(null);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.print_rounded, size: 22),
            const SizedBox(width: 10),
            const Text(
              'HOSTEL PRINT MANAGER',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(width: 30),
            SizedBox(
              width: 260,
              height: 38,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search #Code or Name...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _initialLoad(),
            tooltip: 'Refresh Queue & Printer',
          ),
          const SizedBox(width: 8),
          PrinterStatusChip(
            status: _printerStatus,
            isPrinting: _isPrinting,
            currentJobCode: _selectedJob?.jobCode,
            onRefresh: _checkPrinter,
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => DriverDiagnosticsDialog.show(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 14, color: AppTheme.accent),
                  SizedBox(width: 6),
                  Text(
                    '300 DPI · DRAFT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => SettingsDialog.show(context),
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          const ConversionBanner(),
          Expanded(
            child: Row(
              children: [
                // Left Panel: Queue & Completed Tabs (38% width)
                SizedBox(
                  width: 380,
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: AppTheme.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tab Selector
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _currentTab = DashboardTab.activeQueue;
                                        _selectedJob = _filteredQueue.isNotEmpty
                                            ? _filteredQueue.first
                                            : null;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _currentTab == DashboardTab.activeQueue
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      alignment: Alignment.center,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.queue_play_next,
                                            size: 14,
                                            color: _currentTab == DashboardTab.activeQueue
                                                ? Colors.black
                                                : AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Active Queue (${_queue.length})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _currentTab == DashboardTab.activeQueue
                                                  ? Colors.black
                                                  : AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _currentTab = DashboardTab.completedJobs;
                                        _selectedJob = _filteredHistory.isNotEmpty
                                            ? _filteredHistory.first
                                            : null;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _currentTab == DashboardTab.completedJobs
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      alignment: Alignment.center,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.history,
                                            size: 14,
                                            color: _currentTab == DashboardTab.completedJobs
                                                ? Colors.black
                                                : AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Completed (${_history.length})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _currentTab == DashboardTab.completedJobs
                                                  ? Colors.black
                                                  : AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              color: Colors.white,
                            ),
                          ),
                        const Divider(height: 1),
                        Expanded(
                          child: _currentList.isEmpty
                              ? Center(
                                  child: Text(
                                    _searchQuery.isEmpty
                                        ? (_currentTab == DashboardTab.activeQueue
                                            ? 'No print jobs waiting'
                                            : 'No completed jobs recorded')
                                        : 'No jobs match search',
                                    style: const TextStyle(color: AppTheme.textSecondary),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _currentList.length,
                                  itemBuilder: (ctx, i) {
                                    final job = _currentList[i];
                                    final isSelected = _selectedJob?.id == job.id;
                                    return _buildQueueTile(job, isSelected);
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Right Panel: Job Detail (62% width)
                Expanded(
                  child: _selectedJob == null
                      ? const Center(
                          child: Text('Select a job from the queue to inspect', style: TextStyle(color: AppTheme.textSecondary)),
                        )
                      : _buildJobDetailPanel(_selectedJob!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PRINTED':
        return Colors.greenAccent;
      case 'PRINTING':
        return Colors.blueAccent;
      case 'FAILED':
        return Colors.redAccent;
      case 'CANCELLED':
        return Colors.orangeAccent;
      default:
        return AppTheme.textSecondary;
    }
  }

  Widget _buildQueueTile(PrintJob job, bool isSelected) {
    final statusColor = _getStatusColor(job.status);

    return InkWell(
      onTap: () => setState(() => _selectedJob = job),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.surfaceElevated : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 3,
            ),
            bottom: const BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '#${job.jobCode ?? '---'}',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.studentName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${job.fileCount} file(s) · Est. ${job.totalSheetsEst} sheets',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                job.status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobDetailPanel(PrintJob job) {
    final dateFormat = DateFormat('h:mm a · MMM d');
    final isCompletedTab = _currentTab == DashboardTab.completedJobs;
    final statusColor = _getStatusColor(job.status);

    return Column(
      children: [
        // Top Info Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${job.jobCode ?? 'Pending'}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        job.studentName,
                        style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          job.status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Submitted: ${dateFormat.format(job.createdAt.toLocal())}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      if (job.updatedAt != null && job.status != 'WAITING') ...[
                        const SizedBox(width: 16),
                        Text(
                          'Updated: ${dateFormat.format(job.updatedAt!.toLocal())}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      'TOTAL EST. SHEETS: ${job.totalSheetsEst}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Files List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: job.files.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (ctx, i) {
              final file = job.files[i];
              return _buildFileCard(file, allowEdit: !isCompletedTab);
            },
          ),
        ),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: isCompletedTab
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('Move to Active Queue'),
                      onPressed: () => _moveToActiveQueue(job),
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('Reprint via Dialog'),
                          onPressed: () => _printJob(useDialog: true),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('REPRINT JOB'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          ),
                          onPressed: () => _printJob(useDialog: false),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.redAccent),
                      label: const Text('Cancel Job', style: TextStyle(color: Colors.redAccent)),
                      onPressed: _cancelJob,
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('Print via Dialog'),
                          onPressed: () => _printJob(useDialog: true),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('PRINT JOB'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          ),
                          onPressed: () => _printJob(useDialog: false),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFileCard(JobFile file, {bool allowEdit = true}) {
    final s = file.settings;
    final isDocx = file.inputType == 'DOCX' || file.inputType == 'DOC';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  file.inputType == 'IMAGE'
                      ? Icons.image
                      : (isDocx ? Icons.description : Icons.picture_as_pdf),
                  size: 24,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.filename,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${file.inputType} · ${(file.sizeBytes / 1024).toStringAsFixed(1)} KB ${file.pageCount != null ? '· ${file.pageCount} pages' : ''}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildSettingBadge('${s.copies} Copies'),
                _buildSettingBadge(s.colorMode == 'COLOR' ? 'Color' : 'B&W'),
                if (s.pageRange != null) _buildSettingBadge('Pages: ${s.pageRange}'),
                if (file.inputType == 'IMAGE') ...[
                  _buildSettingBadge(s.orientation == 'LANDSCAPE' ? '🔄 Landscape' : '📱 Portrait'),
                  _buildSettingBadge(s.imageLayout == 'TWO_PER_PAGE' ? '2 Images/Page' : '1 Image/Page'),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isDocx && allowEdit) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.transform, size: 16),
                    label: const Text('Convert to PDF'),
                    onPressed: () => _convertDocx(file),
                  ),
                ],
                OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Download'),
                  onPressed: () => _downloadFile(file),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Preview'),
                  onPressed: () => _previewFile(file),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text('Print This File'),
                  onPressed: () => _printSingleFile(file),
                ),
                if (allowEdit) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Settings'),
                    onPressed: () => _editFileSettings(file),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
    );
  }
}
