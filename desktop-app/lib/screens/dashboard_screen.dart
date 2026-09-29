import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../models/job.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
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
import '../widgets/logs_panel_dialog.dart';
import '../widgets/settings_dialog.dart';
import 'login_screen.dart';

enum DashboardTab { activeQueue, completedJobs }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WindowListener {
  DashboardTab _currentTab = DashboardTab.activeQueue;
  List<PrintJob> _queue = [];
  List<PrintJob> _history = [];
  PrintJob? _selectedJob;
  bool _loading = true;
  String _searchQuery = '';
  PrinterConnectionStatus _printerStatus = PrinterConnectionStatus.checking;
  Timer? _pollingTimer;
  bool _isPrinting = false;

  bool _isMaximized = false;
  bool _isFullScreen = false;
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _queueScrollController = ScrollController();
  final ScrollController _detailScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindowState();
    _initialLoad();
    _startPolling();
  }

  Future<void> _initWindowState() async {
    try {
      final isMax = await windowManager.isMaximized();
      final isFull = await windowManager.isFullScreen();
      if (mounted) {
        setState(() {
          _isMaximized = isMax;
          _isFullScreen = isFull;
        });
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    _initWindowState();
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (e) {
      debugPrint('Error toggling maximize: $e');
    }
  }

  Future<void> _toggleFullScreen() async {
    try {
      final isFull = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFull);
      if (mounted) {
        setState(() => _isFullScreen = !isFull);
      }
    } catch (e) {
      debugPrint('Error toggling fullscreen: $e');
    }
  }

  Future<void> _minimizeWindow() async {
    try {
      await windowManager.minimize();
    } catch (e) {
      debugPrint('Error minimizing: $e');
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isControlPressed = HardwareKeyboard.instance.isControlPressed;

    // F11: Toggle Fullscreen
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullScreen();
      return;
    }

    // F5 or Ctrl + R: Refresh
    if (event.logicalKey == LogicalKeyboardKey.f5 ||
        (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyR)) {
      _initialLoad();
      return;
    }

    // Ctrl + F: Focus search
    if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocusNode.requestFocus();
      return;
    }

    // Ctrl + D: Driver Diagnostics
    if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyD) {
      DriverDiagnosticsDialog.show(context);
      return;
    }

    // Ctrl + , : Settings Dialog
    if (isControlPressed && event.logicalKey == LogicalKeyboardKey.comma) {
      SettingsDialog.show(context);
      return;
    }

    // Ctrl + L: System Logs & Error Diagnostics
    if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyL) {
      LogsPanelDialog.show(context);
      return;
    }

    // Escape: clear search or unfocus
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_searchFocusNode.hasFocus) {
        _searchController.clear();
        setState(() => _searchQuery = '');
        _searchFocusNode.unfocus();
      } else if (_isFullScreen) {
        _toggleFullScreen();
      }
      return;
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _queueScrollController.dispose();
    _detailScrollController.dispose();
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
        final title = _queue.isNotEmpty
            ? 'Hostel Print Manager (${_queue.length} Pending Job${_queue.length > 1 ? "s" : ""})'
            : 'Hostel Print Manager';
        windowManager.setTitle(title);
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

  Future<Directory> _getDownloadsDir() async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}

    if (dir == null || !dir.existsSync()) {
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      dir = Directory(p.join(userProfile, 'Downloads'));
    }

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _sanitizeFilename(String name) {
    var clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (clean.isEmpty) clean = 'document.pdf';
    return clean;
  }

  Future<void> _downloadFile(JobFile file) async {
    if (_selectedJob == null) return;
    final job = _selectedJob!;

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

      Uint8List bytes;
      String targetFilename = file.filename;

      if (file.inputType == 'IMAGE') {
        LoggerService.instance.info(
          'Downloading Composed PDF',
          'Fetching composed PDF for image job #${job.jobCode}',
          category: LogCategory.download,
          jobCode: '${job.jobCode ?? ''}',
        );
        try {
          bytes = await ApiService.downloadComposedPdfBytes(job.id);
          targetFilename = 'Job_${job.jobCode ?? 'images'}_composed.pdf';
        } catch (_) {
          bytes = await _generateFallbackImagePdf(job);
          targetFilename = 'Job_${job.jobCode ?? 'images'}_fallback.pdf';
        }
      } else {
        LoggerService.instance.info(
          'Downloading File',
          'Fetching "${file.filename}" for job #${job.jobCode}',
          category: LogCategory.download,
          jobCode: '${job.jobCode ?? ''}',
        );
        bytes = await ApiService.downloadFileBytes(job.id, file.id);
      }

      final downloadsDir = await _getDownloadsDir();
      final cleanName = _sanitizeFilename(targetFilename);
      final dotIdx = cleanName.lastIndexOf('.');
      final fileBase = dotIdx != -1 ? cleanName.substring(0, dotIdx) : cleanName;
      final ext = dotIdx != -1 ? cleanName.substring(dotIdx) : '';

      String savePath = p.join(downloadsDir.path, cleanName);
      int counter = 1;
      while (await File(savePath).exists()) {
        savePath = p.join(downloadsDir.path, '${fileBase}_$counter$ext');
        counter++;
      }

      final savedFile = File(savePath);
      await savedFile.writeAsBytes(bytes, flush: true);

      LoggerService.instance.success(
        'File Downloaded',
        'Saved "${savedFile.uri.pathSegments.last}" (${(bytes.length / 1024).toStringAsFixed(1)} KB)',
        details: 'Saved to: ${savedFile.path}',
        category: LogCategory.download,
        jobCode: '${job.jobCode ?? ''}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💾 Saved "${savedFile.uri.pathSegments.last}" to Downloads!'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OPEN FILE',
            textColor: Colors.greenAccent,
            onPressed: () {
              Process.run('explorer.exe', [savedFile.path]);
            },
          ),
        ),
      );
    } catch (e, st) {
      LoggerService.instance.error(
        'Download Failed',
        'Failed to download "${file.filename}": $e',
        details: '$st',
        category: LogCategory.download,
        jobCode: '${job.jobCode ?? ''}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download file: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'VIEW LOGS',
              textColor: Colors.white,
              onPressed: () => LogsPanelDialog.show(context),
            ),
          ),
        );
      }
    }
  }

  Future<void> _downloadJob(PrintJob job) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏳ Downloading files for Job #${job.jobCode}...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      final downloadsDir = await _getDownloadsDir();

      // Case 1: Job has images -> Download composed PDF
      final hasImages = job.files.any((f) => f.inputType == 'IMAGE');
      if (hasImages) {
        Uint8List pdfBytes;
        try {
          pdfBytes = await ApiService.downloadComposedPdfBytes(job.id);
        } catch (_) {
          pdfBytes = await _generateFallbackImagePdf(job);
        }

        final cleanName = _sanitizeFilename('Job_${job.jobCode ?? 'images'}_composed.pdf');
        final savedFile = File(p.join(downloadsDir.path, cleanName));
        await savedFile.writeAsBytes(pdfBytes, flush: true);

        LoggerService.instance.success(
          'Job PDF Downloaded',
          'Saved composed PDF for Job #${job.jobCode}',
          details: 'Saved to: ${savedFile.path}',
          category: LogCategory.download,
          jobCode: '${job.jobCode ?? ''}',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('💾 Saved "${savedFile.uri.pathSegments.last}" to Downloads!'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'OPEN FILE',
              textColor: Colors.greenAccent,
              onPressed: () => Process.run('explorer.exe', [savedFile.path]),
            ),
          ),
        );
        return;
      }

      // Case 2: Single PDF
      if (job.files.length == 1) {
        await _downloadFile(job.files.first);
        return;
      }

      // Case 3: Multiple files -> create dedicated subfolder
      final folderName = _sanitizeFilename('Job_${job.jobCode ?? 'print'}_${job.studentName}');
      final jobFolder = Directory(p.join(downloadsDir.path, folderName));
      if (!await jobFolder.exists()) {
        await jobFolder.create(recursive: true);
      }

      int downloadedCount = 0;
      for (final file in job.files) {
        final bytes = await ApiService.downloadFileBytes(job.id, file.id);
        final safeName = _sanitizeFilename(file.filename);
        final fileDest = File(p.join(jobFolder.path, safeName));
        await fileDest.writeAsBytes(bytes, flush: true);
        downloadedCount++;
      }

      LoggerService.instance.success(
        'All Job Files Downloaded',
        'Saved $downloadedCount file(s) for Job #${job.jobCode} into folder "$folderName"',
        details: 'Folder: ${jobFolder.path}',
        category: LogCategory.download,
        jobCode: '${job.jobCode ?? ''}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💾 Downloaded $downloadedCount files to "$folderName"!'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OPEN FOLDER',
            textColor: Colors.greenAccent,
            onPressed: () => Process.run('explorer.exe', [jobFolder.path]),
          ),
        ),
      );
    } catch (e, st) {
      LoggerService.instance.error(
        'Job Download Failed',
        'Failed to download files for Job #${job.jobCode}: $e',
        details: '$st',
        category: LogCategory.download,
        jobCode: '${job.jobCode ?? ''}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download job: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'VIEW LOGS',
              textColor: Colors.white,
              onPressed: () => LogsPanelDialog.show(context),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteJob(PrintJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
            const SizedBox(width: 10),
            Text('Delete Job #${job.jobCode ?? '---'}?'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete job #${job.jobCode} for "${job.studentName}"?\n\nThis will remove the job and all associated files from the completed history.',
          style: TextStyle(color: Colors.grey[300], fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteJob(job.id);
      LoggerService.instance.info(
        'Job Deleted',
        'Permanently deleted completed job #${job.jobCode} (${job.studentName})',
        category: LogCategory.system,
        jobCode: '${job.jobCode ?? ''}',
      );

      if (!mounted) return;
      setState(() {
        _history.removeWhere((j) => j.id == job.id);
        _queue.removeWhere((j) => j.id == job.id);
        if (_selectedJob?.id == job.id) {
          final currentList = _currentTab == DashboardTab.activeQueue ? _filteredQueue : _filteredHistory;
          _selectedJob = currentList.isNotEmpty ? currentList.first : null;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ Job #${job.jobCode ?? '---'} deleted.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, st) {
      LoggerService.instance.error(
        'Failed to Delete Job',
        'Error deleting job #${job.jobCode}: $e',
        details: '$st',
        category: LogCategory.network,
        jobCode: '${job.jobCode ?? ''}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete job: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _clearAllCompletedJobs() async {
    if (_history.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 22),
            SizedBox(width: 10),
            Text('Clear All Completed Jobs?'),
          ],
        ),
        content: Text(
          'This will permanently delete all ${_history.length} completed, failed, and cancelled jobs from history.\n\nActive pending jobs in the queue will NOT be affected.',
          style: TextStyle(color: Colors.grey[300], fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final count = await ApiService.clearAllCompletedJobs();
      LoggerService.instance.info(
        'History Cleared',
        'Purged $count completed jobs from history',
        category: LogCategory.system,
      );

      if (!mounted) return;
      setState(() {
        _history.clear();
        if (_currentTab == DashboardTab.completedJobs) {
          _selectedJob = null;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🧹 Cleared $count completed jobs from history.'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e, st) {
      LoggerService.instance.error(
        'Failed to Clear History',
        'Error purging completed jobs: $e',
        details: '$st',
        category: LogCategory.network,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to clear completed jobs: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _updateLocalFileStatus(String fileId, String status, {String? errorMessage}) {
    if (!mounted || _selectedJob == null) return;
    setState(() {
      final updatedFiles = _selectedJob!.files.map((f) {
        if (f.id == fileId) {
          return f.copyWith(
            status: status,
            errorMessage: errorMessage,
            printedAt: status == 'PRINTED' ? DateTime.now() : f.printedAt,
          );
        }
        return f;
      }).toList();

      _selectedJob = PrintJob(
        id: _selectedJob!.id,
        jobCode: _selectedJob!.jobCode,
        studentName: _selectedJob!.studentName,
        status: _selectedJob!.status,
        createdAt: _selectedJob!.createdAt,
        updatedAt: _selectedJob!.updatedAt,
        expiresAt: _selectedJob!.expiresAt,
        fileCount: _selectedJob!.fileCount,
        totalSheetsEst: _selectedJob!.totalSheetsEst,
        files: updatedFiles,
      );

      _queue = _queue.map((j) {
        if (j.id == _selectedJob!.id) {
          return PrintJob(
            id: j.id,
            jobCode: j.jobCode,
            studentName: j.studentName,
            status: j.status,
            createdAt: j.createdAt,
            updatedAt: j.updatedAt,
            expiresAt: j.expiresAt,
            fileCount: j.fileCount,
            totalSheetsEst: j.totalSheetsEst,
            files: updatedFiles,
          );
        }
        return j;
      }).toList();

      _history = _history.map((j) {
        if (j.id == _selectedJob!.id) {
          return PrintJob(
            id: j.id,
            jobCode: j.jobCode,
            studentName: j.studentName,
            status: j.status,
            createdAt: j.createdAt,
            updatedAt: j.updatedAt,
            expiresAt: j.expiresAt,
            fileCount: j.fileCount,
            totalSheetsEst: j.totalSheetsEst,
            files: updatedFiles,
          );
        }
        return j;
      }).toList();
    });
  }

  Future<void> _printSingleFile(JobFile file, {bool useDialog = false}) async {
    if (_selectedJob == null) return;
    final job = _selectedJob!;

    final globalQuality = await StorageService.getGlobalQuality();
    final globalDpi = await StorageService.getGlobalDpi();

    try {
      _updateLocalFileStatus(file.id, 'PRINTING');
      await ApiService.updateFileStatus(job.id, file.id, 'PRINTING');

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
        _updateLocalFileStatus(file.id, 'FAILED', errorMessage: 'Spooler rejected');
        await ApiService.updateFileStatus(job.id, file.id, 'FAILED', errorMessage: 'Spooler rejected');
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
          _updateLocalFileStatus(file.id, 'FAILED', errorMessage: 'Print cancelled at printer');
          await ApiService.updateFileStatus(job.id, file.id, 'FAILED', errorMessage: 'Print cancelled at printer');
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
          final errMsg = spoolerStatus.message ?? 'Printer hardware error occurred';
          _updateLocalFileStatus(file.id, 'FAILED', errorMessage: errMsg);
          await ApiService.updateFileStatus(job.id, file.id, 'FAILED', errorMessage: errMsg);
          throw Exception(errMsg);
        }
      }

      _updateLocalFileStatus(file.id, 'PRINTED');
      await ApiService.updateFileStatus(job.id, file.id, 'PRINTED');

      // Check if all files in the current job are now printed
      final currentFiles = _selectedJob?.files ?? [];
      final allPrinted = currentFiles.isNotEmpty && currentFiles.every((f) => f.id == file.id || f.status == 'PRINTED');
      if (allPrinted) {
        final targetPrinterName = await StorageService.getPrinterName();
        await ApiService.updateStatus(job.id, 'PRINTED', printerName: targetPrinterName);
        await _refreshAll(silent: true);
      }

      LoggerService.instance.success(
        'File Printed',
        'Successfully spooled and completed "${file.filename}" for Job #${job.jobCode}',
        category: LogCategory.print,
        jobCode: '${job.jobCode ?? ''}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Successfully printed "${file.filename}"!')),
        );
      }
    } catch (e, st) {
      LoggerService.instance.error(
        'Print File Failed',
        'Failed to print "${file.filename}" for Job #${job.jobCode}: $e',
        details: '$st',
        category: LogCategory.print,
        jobCode: '${job.jobCode ?? ''}',
      );
      _updateLocalFileStatus(file.id, 'FAILED', errorMessage: e.toString());
      await ApiService.updateFileStatus(job.id, file.id, 'FAILED', errorMessage: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing file: $e'),
            backgroundColor: Colors.redAccent,
            action: SnackBarAction(
              label: 'VIEW LOGS',
              textColor: Colors.white,
              onPressed: () => LogsPanelDialog.show(context),
            ),
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
        _updateLocalFileStatus(file.id, 'PRINTING');
        await ApiService.updateFileStatus(job.id, file.id, 'PRINTING');

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
            _updateLocalFileStatus(file.id, 'PRINTED');
            await ApiService.updateFileStatus(job.id, file.id, 'PRINTED');
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
          _updateLocalFileStatus(file.id, 'FAILED', errorMessage: 'Spooler rejected');
          await ApiService.updateFileStatus(job.id, file.id, 'FAILED', errorMessage: 'Spooler rejected');
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
            _updateLocalFileStatus(file.id, 'FAILED', errorMessage: 'Print cancelled at printer');
            await ApiService.updateFileStatus(job.id, file.id, 'FAILED', errorMessage: 'Print cancelled at printer');
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
            final errMsg = spoolerStatus.message ?? 'Printer hardware error occurred during printing';
            _updateLocalFileStatus(file.id, 'FAILED', errorMessage: errMsg);
            await ApiService.updateFileStatus(job.id, file.id, 'FAILED', errorMessage: errMsg);
            throw Exception(errMsg);
          }
        }

        _updateLocalFileStatus(file.id, 'PRINTED');
        await ApiService.updateFileStatus(job.id, file.id, 'PRINTED');
      }

      final printerName = await StorageService.getPrinterName();
      await ApiService.updateStatus(job.id, 'PRINTED', printerName: printerName);
      LoggerService.instance.success(
        'Print Job Completed',
        'Job #${job.jobCode} for ${job.studentName} (${job.files.length} file(s)) printed successfully.',
        category: LogCategory.print,
        jobCode: '${job.jobCode ?? ''}',
      );
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
    } catch (e, st) {
      LoggerService.instance.error(
        'Print Job Failed',
        'Print failed for Job #${job.jobCode}: $e',
        details: '$st',
        category: LogCategory.print,
        jobCode: '${job.jobCode ?? ''}',
      );
      await ApiService.updateStatus(job.id, 'FAILED', errorMessage: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'VIEW LOGS',
              textColor: Colors.white,
              onPressed: () => LogsPanelDialog.show(context),
            ),
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
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _toggleMaximize,
            child: Row(
              children: [
                const Icon(Icons.print_rounded, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'HOSTEL PRINT MANAGER',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 270,
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Search #Code or Name (Ctrl+F)...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _initialLoad(),
              tooltip: 'Refresh Queue & Printer (Ctrl+R / F5)',
            ),
            const SizedBox(width: 6),
            PrinterStatusChip(
              status: _printerStatus,
              isPrinting: _isPrinting,
              currentJobCode: _selectedJob?.jobCode,
              onRefresh: _checkPrinter,
            ),
            const SizedBox(width: 6),
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
            const SizedBox(width: 6),
            ListenableBuilder(
              listenable: LoggerService.instance,
              builder: (context, _) {
                final unreadErrors = LoggerService.instance.unreadErrorCount;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        unreadErrors > 0 ? Icons.error_outline : Icons.receipt_long_outlined,
                        color: unreadErrors > 0 ? Colors.redAccent : null,
                      ),
                      onPressed: () => LogsPanelDialog.show(context),
                      tooltip: unreadErrors > 0
                          ? '$unreadErrors System Error(s) - Click to inspect (Ctrl+L)'
                          : 'System Activity & Error Logs (Ctrl+L)',
                    ),
                    if (unreadErrors > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            unreadErrors > 99 ? '99+' : '$unreadErrors',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => SettingsDialog.show(context),
              tooltip: 'Settings (Ctrl+,)',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: 'Logout',
            ),
            Container(
              height: 24,
              width: 1,
              color: AppTheme.border,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              onPressed: _minimizeWindow,
              tooltip: 'Minimize Window',
            ),
            IconButton(
              icon: Icon(_isMaximized ? Icons.filter_none : Icons.crop_square, size: 16),
              onPressed: _toggleMaximize,
              tooltip: _isMaximized ? 'Restore Window' : 'Maximize Window',
            ),
            IconButton(
              icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 20),
              onPressed: _toggleFullScreen,
              tooltip: _isFullScreen ? 'Exit Fullscreen (F11)' : 'Fullscreen (F11)',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            const ConversionBanner(),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth >= 1200;
                  final queueWidth = isWide ? 380.0 : (constraints.maxWidth >= 960 ? 320.0 : 280.0);

                  return Row(
                    children: [
                      // Left Panel: Queue & Completed Tabs
                      SizedBox(
                        width: queueWidth,
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
                                                  'Active (${_queue.length})',
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
                                                  'Done (${_history.length})',
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
                              if (_currentTab == DashboardTab.completedJobs && _history.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  color: AppTheme.surfaceElevated,
                                  child: Row(
                                    children: [
                                      Text(
                                        '${_history.length} completed jobs',
                                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                      ),
                                      const Spacer(),
                                      TextButton.icon(
                                        icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.redAccent),
                                        label: const Text(
                                          'Clear All',
                                          style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: _clearAllCompletedJobs,
                                      ),
                                    ],
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
                                    : Scrollbar(
                                        controller: _queueScrollController,
                                        thumbVisibility: true,
                                        interactive: true,
                                        child: ListView.builder(
                                          controller: _queueScrollController,
                                          itemCount: _currentList.length,
                                          itemBuilder: (ctx, i) {
                                            final job = _currentList[i];
                                            final isSelected = _selectedJob?.id == job.id;
                                            return _buildQueueTile(job, isSelected);
                                          },
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Right Panel: Job Detail
                      Expanded(
                        child: _selectedJob == null
                            ? const Center(
                                child: Text('Select a job from the queue to inspect', style: TextStyle(color: AppTheme.textSecondary)),
                              )
                            : _buildJobDetailPanel(_selectedJob!),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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

  void _showJobContextMenu(Offset position, PrintJob job) async {
    setState(() => _selectedJob = job);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        const PopupMenuItem(
          value: 'print',
          child: Row(
            children: [
              Icon(Icons.print, size: 18),
              SizedBox(width: 8),
              Text('Print Job'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'print_dialog',
          child: Row(
            children: [
              Icon(Icons.print_outlined, size: 18),
              SizedBox(width: 8),
              Text('Print via Dialog...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download_outlined, size: 18),
              SizedBox(width: 8),
              Text('Download PDF(s)'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_code',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('Copy Job Code'),
            ],
          ),
        ),
        if (job.status == 'WAITING' || job.status == 'PRINTING') ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'cancel',
            child: Row(
              children: [
                Icon(Icons.cancel_outlined, size: 18, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Cancel Job', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
        ],
        if (_currentTab == DashboardTab.completedJobs) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Delete Job', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
        ],
      ],
    );

    if (!mounted || selected == null) return;

    if (selected == 'print') {
      _printJob(useDialog: false);
    } else if (selected == 'print_dialog') {
      _printJob(useDialog: true);
    } else if (selected == 'download') {
      _downloadJob(job);
    } else if (selected == 'delete') {
      _deleteJob(job);
    } else if (selected == 'copy_code') {
      if (job.jobCode != null) {
        Clipboard.setData(ClipboardData(text: '#${job.jobCode}'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📋 Copied Job Code #${job.jobCode} to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else if (selected == 'cancel') {
      _cancelJob();
    }
  }

  Widget _buildQueueTile(PrintJob job, bool isSelected) {
    final statusColor = _getStatusColor(job.status);

    return GestureDetector(
      onSecondaryTapUp: (details) => _showJobContextMenu(details.globalPosition, job),
      child: InkWell(
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
              if (_currentTab == DashboardTab.completedJobs) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                  hoverColor: Colors.redAccent.withValues(alpha: 0.15),
                  splashRadius: 14,
                  tooltip: 'Delete completed job',
                  onPressed: () => _deleteJob(job),
                ),
              ],
            ],
          ),
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
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: Text(job.files.length > 1 ? 'Download All (${job.files.length})' : 'Download PDF'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _downloadJob(job),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (job.status == 'FAILED')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: Colors.redAccent.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'This print job encountered a failure. You can download the PDF to print manually or inspect diagnostic error logs.',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w500),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.receipt_long_outlined, size: 14, color: Colors.redAccent),
                  label: const Text('View Logs', style: TextStyle(color: Colors.redAccent)),
                  onPressed: () => LogsPanelDialog.show(context),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download_outlined, size: 14),
                  label: const Text('Download PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _downloadJob(job),
                ),
              ],
            ),
          ),

        // Files List
        Expanded(
          child: Scrollbar(
            controller: _detailScrollController,
            thumbVisibility: true,
            interactive: true,
            child: ListView.separated(
              controller: _detailScrollController,
              padding: const EdgeInsets.all(24),
              itemCount: job.files.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (ctx, i) {
                final file = job.files[i];
                return _buildFileCard(file, allowEdit: !isCompletedTab);
              },
            ),
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
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.replay, size: 18),
                          label: const Text('Move to Active Queue'),
                          onPressed: () => _moveToActiveQueue(job),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: Text(job.files.length > 1 ? 'Download All' : 'Download PDF'),
                          onPressed: () => _downloadJob(job),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          label: const Text('Delete Job', style: TextStyle(color: Colors.redAccent)),
                          onPressed: () => _deleteJob(job),
                        ),
                      ],
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
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.redAccent),
                          label: const Text('Cancel Job', style: TextStyle(color: Colors.redAccent)),
                          onPressed: _cancelJob,
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: Text(job.files.length > 1 ? 'Download All' : 'Download PDF'),
                          onPressed: () => _downloadJob(job),
                        ),
                      ],
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
                const SizedBox(width: 8),
                _buildFileStatusBadge(file.status),
              ],
            ),
            if (file.errorMessage != null && file.errorMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file.errorMessage!,
                        style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => LogsPanelDialog.show(context),
                      child: const Text(
                        'VIEW LOGS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                  label: Text(file.inputType == 'IMAGE' ? 'Download PDF' : 'Download'),
                  onPressed: () => _downloadFile(file),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Preview'),
                  onPressed: () => _previewFile(file),
                ),
                OutlinedButton.icon(
                  icon: Icon(
                    file.status == 'PRINTING' ? Icons.hourglass_top : Icons.print_outlined,
                    size: 16,
                  ),
                  label: Text(
                    file.status == 'PRINTING'
                        ? 'Printing...'
                        : (file.status == 'PRINTED' ? 'Reprint File' : 'Print This File'),
                  ),
                  onPressed: file.status == 'PRINTING' ? null : () => _printSingleFile(file),
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

  Widget _buildFileStatusBadge(String status) {
    Color color;
    IconData icon;
    String label;

    switch (status.toUpperCase()) {
      case 'PRINTED':
        color = Colors.greenAccent;
        icon = Icons.check_circle_outline;
        label = 'PRINTED';
        break;
      case 'PRINTING':
        color = Colors.cyanAccent;
        icon = Icons.print;
        label = 'PRINTING...';
        break;
      case 'FAILED':
        color = Colors.redAccent;
        icon = Icons.error_outline;
        label = 'FAILED';
        break;
      case 'PENDING':
      default:
        color = Colors.amberAccent;
        icon = Icons.hourglass_bottom;
        label = 'QUEUED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
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
