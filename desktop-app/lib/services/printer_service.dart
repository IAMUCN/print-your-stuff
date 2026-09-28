import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'storage_service.dart';

enum PrinterConnectionStatus { online, offline, checking }

enum SpoolerState {
  spooling,
  printing,
  completed,
  cancelled,
  error,
  paperOut,
  jammed,
  userIntervention,
  unknown,
}

class SpoolerJobStatus {
  final int id;
  final SpoolerState state;
  final String rawStatus;
  final int pagesPrinted;
  final int totalPages;
  final String? message;

  const SpoolerJobStatus({
    required this.id,
    required this.state,
    required this.rawStatus,
    required this.pagesPrinted,
    required this.totalPages,
    this.message,
  });

  bool get isTerminal =>
      state == SpoolerState.completed ||
      state == SpoolerState.cancelled ||
      state == SpoolerState.error ||
      state == SpoolerState.jammed;
}

class PrinterDiagnostics {
  final int dpiX;
  final int dpiY;
  final int horzRes;
  final int vertRes;
  final int physWidth;
  final int physHeight;
  final int offsetX;
  final int offsetY;
  final String quality;
  final String colorMode;
  final bool isDraft;
  final bool is300Dpi;
  final String? error;

  const PrinterDiagnostics({
    required this.dpiX,
    required this.dpiY,
    required this.horzRes,
    required this.vertRes,
    required this.physWidth,
    required this.physHeight,
    required this.offsetX,
    required this.offsetY,
    required this.quality,
    required this.colorMode,
    required this.isDraft,
    required this.is300Dpi,
    this.error,
  });

  String get summary =>
      '${dpiX}x$dpiY DPI · Quality: $quality · Color: $colorMode · Canvas: ${horzRes}x$vertRes px';
}

class PrinterService {
  static String _sanitizeForPs(String input) => input.replaceAll("'", "''");

  /// Checks if the printer is ready via Windows Print Spooler (USB cable or Wi-Fi)
  /// or directly reachable via local network JetDirect port 9100.
  static Future<PrinterConnectionStatus> checkPrinterStatus() async {
    final targetPrinterName = await StorageService.getPrinterName();
    final sanitized = _sanitizeForPs(targetPrinterName);

    // 1. Check Windows Print Spooler status (works reliably for USB cable & Wi-Fi driver)
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "(Get-Printer -Name '$sanitized' -ErrorAction SilentlyContinue).PrinterStatus",
        ],
        runInShell: true,
      );

      final output = result.stdout.toString().trim().toLowerCase();
      // Handle Normal, Idle, or WMI numeric codes (3 = Idle, 0 = Ready/Normal)
      if (output == 'normal' || output == 'idle' || output == '0' || output == '3') {
        return PrinterConnectionStatus.online;
      }
    } catch (_) {}

    // 2. Check network port 9100 on the configured printer IP (Wi-Fi check)
    final ip = await StorageService.getPrinterIp();
    if (ip.isNotEmpty) {
      try {
        final socket = await Socket.connect(ip, 9100, timeout: const Duration(milliseconds: 1200));
        socket.destroy();
        return PrinterConnectionStatus.online;
      } catch (_) {}
    }

    // 3. Fallback: check if printer exists in Windows installed printers
    try {
      final printers = await Printing.listPrinters();
      final target = targetPrinterName.trim().toLowerCase();
      final matched = printers.any((p) => p.name.trim().toLowerCase() == target);
      if (matched) {
        return PrinterConnectionStatus.online;
      }
    } catch (_) {}

    return PrinterConnectionStatus.offline;
  }

  /// Lists all printers installed in Windows
  static Future<List<Printer>> listInstalledPrinters() async {
    try {
      return await Printing.listPrinters();
    } catch (e) {
      return [];
    }
  }

  /// Finds the target printer using exact matching first to avoid accidental
  /// substring matches (e.g. matching "TCS (HP Smart Tank...)" when "HP Smart Tank..." was selected)
  static Future<Printer?> findTargetPrinter(String targetPrinterName) async {
    final installedPrinters = await Printing.listPrinters();
    if (installedPrinters.isEmpty) return null;

    final target = targetPrinterName.trim().toLowerCase();

    // 1. Exact match (case-insensitive) - MUST BE FIRST
    for (final p in installedPrinters) {
      if (p.name.trim().toLowerCase() == target) {
        return p;
      }
    }

    // 2. Exact prefix match
    for (final p in installedPrinters) {
      if (p.name.trim().toLowerCase().startsWith(target)) {
        return p;
      }
    }

    // 3. Fallback contains match only if neither exact nor prefix matched
    for (final p in installedPrinters) {
      if (p.name.toLowerCase().contains(target)) {
        return p;
      }
    }

    // 4. Default printer if set
    return installedPrinters.firstWhere(
      (p) => p.isDefault,
      orElse: () => installedPrinters.isNotEmpty
          ? installedPrinters.first
          : const Printer(url: 'default', name: 'Default'),
    );
  }

  static String? _cachedHelperPath;
  static String? _findHelperExe() {
    if (_cachedHelperPath != null && File(_cachedHelperPath!).existsSync()) {
      return _cachedHelperPath;
    }
    final candidatePaths = [
      '${Platform.resolvedExecutable}\\..\\printer_config_helper.exe',
      '${Directory.current.path}\\windows\\tools\\printer_config_helper.exe',
      'windows\\tools\\printer_config_helper.exe',
      'build\\windows\\x64\\runner\\Debug\\printer_config_helper.exe',
    ];
    for (final p in candidatePaths) {
      if (File(p).existsSync()) {
        _cachedHelperPath = p;
        return p;
      }
    }
    return null;
  }

  /// Queries the live Windows GDI DC capabilities and print driver resolution
  static Future<PrinterDiagnostics> getDriverDiagnostics(String printerName) async {
    final quality = await StorageService.getGlobalQuality();
    final globalDpi = await StorageService.getGlobalDpi();

    final helper = _findHelperExe();
    if (helper != null) {
      try {
        final res = await Process.run(helper, ['check', printerName]);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          final data = jsonDecode(out) as Map<String, dynamic>;
          if (data.containsKey('dpiX')) {
            final dpiX = data['dpiX'] as int;
            final dpiY = data['dpiY'] as int;
            final horzRes = data['horzRes'] as int;
            final vertRes = data['vertRes'] as int;
            final physWidth = data['physWidth'] as int;
            final physHeight = data['physHeight'] as int;
            final offsetX = data['offsetX'] as int;
            final offsetY = data['offsetY'] as int;

            final diag = PrinterDiagnostics(
              dpiX: dpiX,
              dpiY: dpiY,
              horzRes: horzRes,
              vertRes: vertRes,
              physWidth: physWidth,
              physHeight: physHeight,
              offsetX: offsetX,
              offsetY: offsetY,
              quality: quality,
              colorMode: 'Grayscale (BW)',
              isDraft: quality.toUpperCase() == 'DRAFT' || dpiX <= 300,
              is300Dpi: dpiX <= 300,
            );
            debugPrint('🔍 [Printer Diagnostics] Live Driver DC State:');
            debugPrint('   DPI: ${diag.dpiX} x ${diag.dpiY}');
            debugPrint('   Printable Canvas: ${diag.horzRes} x ${diag.vertRes}');
            debugPrint('   Physical Paper: ${diag.physWidth} x ${diag.physHeight}');
            debugPrint('   Quality Setting: ${diag.quality}');
            debugPrint('   Draft Mode Active: ${diag.isDraft}');
            return diag;
          }
        }
      } catch (e) {
        debugPrint('Error running printer diagnostics: $e');
      }
    }

    return PrinterDiagnostics(
      dpiX: globalDpi,
      dpiY: globalDpi,
      horzRes: 2410,
      vertRes: 3438,
      physWidth: 2480,
      physHeight: 3508,
      offsetX: 35,
      offsetY: 35,
      quality: quality,
      colorMode: 'Grayscale (BW)',
      isDraft: quality.toUpperCase() == 'DRAFT' || globalDpi <= 300,
      is300Dpi: globalDpi <= 300,
    );
  }

  static String? _lastConfiguredPrinter;
  static String? _lastConfiguredColorMode;
  static String? _lastConfiguredQuality;
  static int? _lastConfiguredDpi;

  /// Injects Color Mode (Grayscale vs Color), Quality (Draft/Normal/High), and DPI (300/600/1200)
  /// directly into the Windows Print Spooler and HP PrintTicket driver settings.
  static Future<void> applyPrinterConfiguration({
    required String printerName,
    required String colorMode,
    String? quality,
    int? dpi,
    bool force = false,
  }) async {
    if (!Platform.isWindows) return;
    try {
      final effectiveQuality = quality ?? await StorageService.getGlobalQuality();
      final effectiveDpi = dpi ?? await StorageService.getGlobalDpi();

      // Fast-path: if already configured with these exact parameters, return immediately (0 ms overhead!)
      if (!force &&
          _lastConfiguredPrinter == printerName &&
          _lastConfiguredColorMode == colorMode &&
          _lastConfiguredQuality == effectiveQuality &&
          _lastConfiguredDpi == effectiveDpi) {
        debugPrint('⚡ [Printer Config] Already active for $printerName: $effectiveQuality, ${effectiveDpi}DPI');
        return;
      }

      final sw = Stopwatch()..start();
      final isColor = colorMode.toUpperCase() == 'COLOR';
      final dmColor = isColor ? 2 : 1; // 1=Monochrome, 2=Color

      // 1. Fast Win32 DEVMODE update via native helper executable (<80ms)
      final helper = _findHelperExe();
      if (helper != null) {
        try {
          await Process.run(helper, ['apply', printerName, effectiveDpi.toString(), dmColor.toString()]);
        } catch (_) {}
      }

      // 2. Fast V4 PrintTicket XML update via PowerShell (no compilation needed!)
      final qualityOption = switch (effectiveQuality.toUpperCase()) {
        'DRAFT' => 'psk:Draft',
        'BEST' => 'psk:High',
        _ => 'psk:Normal',
      };
      final hpQualityOption = switch (effectiveQuality.toUpperCase()) {
        'DRAFT' => 'ns0000:Draft',
        'BEST' => 'ns0000:High',
        _ => 'ns0000:Normal',
      };
      final dpiOption = switch (effectiveDpi) {
        300 => 'ns0000:_300dpi',
        1200 => 'ns0000:_1200dpi',
        _ => 'ns0000:_600dpi',
      };
      final colorFlag = isColor ? '1' : '0';
      final colorOption = isColor ? 'psk:Color' : 'psk:Grayscale';
      final sanitizedName = _sanitizeForPs(printerName);

      final script = '''
\$name = '$sanitizedName';
\$cfg = Get-PrintConfiguration -PrinterName \$name -ErrorAction SilentlyContinue;
if (\$cfg) {
  [xml]\$ticket = \$cfg.PrintTicketXML;
  if (\$ticket) {
    foreach (\$f in \$ticket.GetElementsByTagName('psf:Feature')) {
      if (\$f.name -eq 'psk:PageOutputQuality') { \$f.Option.name = '$qualityOption' };
      if (\$f.name -eq 'ns0000:JobOutputQualityPrev') { \$f.Option.name = '$hpQualityOption' };
      if (\$f.name -eq 'psk:PageResolution') {
        \$f.Option.name = '$dpiOption';
        foreach (\$sp in \$f.Option.GetElementsByTagName('psf:ScoredProperty')) {
          if (\$sp.name -eq 'psk:ResolutionX' -or \$sp.name -eq 'psk:ResolutionY') {
            \$sp.Value.InnerText = '$effectiveDpi';
          }
        }
      };
      if (\$f.name -eq 'psk:PageOutputColor') { \$f.Option.name = '$colorOption' };
    };
    Set-PrintConfiguration -PrinterName \$name -PrintTicketXml \$ticket.OuterXml -Color:$colorFlag -ErrorAction SilentlyContinue;
  } else {
    Set-PrintConfiguration -PrinterName \$name -Color:$colorFlag -ErrorAction SilentlyContinue;
  }
}
''';

      await Process.run(
        'powershell',
        ['-NoProfile', '-Command', script],
        runInShell: true,
      );

      _lastConfiguredPrinter = printerName;
      _lastConfiguredColorMode = colorMode;
      _lastConfiguredQuality = effectiveQuality;
      _lastConfiguredDpi = effectiveDpi;

      debugPrint('✅ [Printer Config] Successfully configured $printerName in ${sw.elapsedMilliseconds}ms: $effectiveQuality · ${effectiveDpi}DPI · ${isColor ? "Color" : "BW"}');
    } catch (e) {
      debugPrint('⚠️ [Printer Config] Error configuring printer: $e');
    }
  }

  /// Monitors the real-time lifecycle of a submitted print job in the Windows Print Spooler.
  /// Reports spooling -> active printing (with page counts) -> completed, or detects if the user
  /// pressed the physical "Cancel" button on the printer (JOB_STATUS_DELETING), paper out, or errors.
  static Future<SpoolerJobStatus> trackJobCompletion({
    required String printerName,
    required String docPattern,
    Duration timeout = const Duration(minutes: 5),
    Function(SpoolerJobStatus status)? onProgress,
  }) async {
    final sanitizedPrinter = _sanitizeForPs(printerName);
    final sanitizedDoc = _sanitizeForPs(docPattern);
    final stopwatch = Stopwatch()..start();

    bool hasEverSeenJob = false;
    int consecutiveNoneCount = 0;

    while (stopwatch.elapsed < timeout) {
      await Future.delayed(const Duration(milliseconds: 700));

      final script = '''
\$jobs = Get-PrintJob -PrinterName '$sanitizedPrinter' -ErrorAction SilentlyContinue | Where-Object { \$_.DocumentName -like '*$sanitizedDoc*' };
if (\$jobs) {
    \$first = \$jobs[0];
    \$status = [int]\$first.JobStatus;
    Write-Output "\$(\$first.Id)|\$status|\$(\$first.PagesPrinted)|\$(\$first.TotalPages)"
} else {
    Write-Output "NONE"
}
''';

      try {
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-Command', script],
          runInShell: true,
        );

        final out = result.stdout.toString().trim();
        if (out == 'NONE' || out.isEmpty) {
          consecutiveNoneCount++;
          if (hasEverSeenJob) {
            // Spooler buffer has flushed to the printer. Check if physical hardware is actively printing:
            final hwCheck = await Process.run(
              'powershell',
              [
                '-NoProfile',
                '-Command',
                "\$p = Get-CimInstance Win32_Printer -Filter \"Name='$sanitizedPrinter'\" -ErrorAction SilentlyContinue; if (\$p) { Write-Output \"\$(\$p.PrinterStatus)|\$(\$p.ExtendedPrinterStatus)|\$(\$p.PrinterState)\" } else { Write-Output '3|2|0' }"
              ],
              runInShell: true,
            );
            final hwOut = hwCheck.stdout.toString().trim();
            final hwParts = hwOut.split('|');
            final pStatus = hwParts.isNotEmpty ? int.tryParse(hwParts[0]) : null;
            final extStatus = hwParts.length > 1 ? int.tryParse(hwParts[1]) : null;

            // Win32_Printer: PrinterStatus 4 = Printing, ExtendedPrinterStatus 11 = Printing
            if (pStatus == 4 || extStatus == 11) {
              onProgress?.call(
                const SpoolerJobStatus(
                  id: 0,
                  state: SpoolerState.printing,
                  rawStatus: 'Printing',
                  pagesPrinted: 1,
                  totalPages: 1,
                  message: 'Printing in progress at the printer...',
                ),
              );
              await Future.delayed(const Duration(seconds: 1));
              continue;
            }

            final finishedStatus = const SpoolerJobStatus(
              id: 0,
              state: SpoolerState.completed,
              rawStatus: 'Completed',
              pagesPrinted: 1,
              totalPages: 1,
              message: 'Print finished successfully.',
            );
            onProgress?.call(finishedStatus);
            return finishedStatus;
          } else if (consecutiveNoneCount >= 6) {
            final finishedStatus = const SpoolerJobStatus(
              id: 0,
              state: SpoolerState.completed,
              rawStatus: 'Completed',
              pagesPrinted: 1,
              totalPages: 1,
              message: 'Print finished successfully.',
            );
            onProgress?.call(finishedStatus);
            return finishedStatus;
          }
          continue;
        }

        hasEverSeenJob = true;
        consecutiveNoneCount = 0;

        final parts = out.split('|');
        if (parts.length >= 4) {
          final id = int.tryParse(parts[0]) ?? 0;
          final statusInt = int.tryParse(parts[1]) ?? 0;
          final pagesPrinted = int.tryParse(parts[2]) ?? 0;
          final totalPages = int.tryParse(parts[3]) ?? 0;

          // Bitwise evaluations per Win32 Print Spooler documentation:
          // 4 = Deleting, 256 = Deleted -> Cancelled on printer panel or in Windows
          final isDeleting = (statusInt & 4) != 0 || (statusInt & 256) != 0;
          // 64 = Paper Out, 1024 = User Intervention
          final isPaperOut = (statusInt & 64) != 0;
          // 2 = Error, 512 = Blocked
          final isError = (statusInt & 2) != 0 || (statusInt & 512) != 0;
          // 16 = Printing
          final isPrinting = (statusInt & 16) != 0;
          // 4096 = Completed, 128 = Printed
          final isCompleted = (statusInt & 4096) != 0 || (statusInt & 128) != 0;

          if (isDeleting) {
            final status = SpoolerJobStatus(
              id: id,
              state: SpoolerState.cancelled,
              rawStatus: 'Deleting/Cancelled',
              pagesPrinted: pagesPrinted,
              totalPages: totalPages,
              message: 'Print job was cancelled at the printer.',
            );
            onProgress?.call(status);
            return status;
          }

          if (isPaperOut) {
            final status = SpoolerJobStatus(
              id: id,
              state: SpoolerState.paperOut,
              rawStatus: 'PaperOut',
              pagesPrinted: pagesPrinted,
              totalPages: totalPages,
              message: 'Printer is out of paper. Please insert paper into the tray.',
            );
            onProgress?.call(status);
            continue;
          }

          if (isError) {
            final status = SpoolerJobStatus(
              id: id,
              state: SpoolerState.error,
              rawStatus: 'Error',
              pagesPrinted: pagesPrinted,
              totalPages: totalPages,
              message: 'Printer reported a hardware error.',
            );
            onProgress?.call(status);
            return status;
          }

          if (isCompleted) {
            final status = SpoolerJobStatus(
              id: id,
              state: SpoolerState.completed,
              rawStatus: 'Completed',
              pagesPrinted: pagesPrinted > 0 ? pagesPrinted : totalPages,
              totalPages: totalPages,
              message: 'Print finished successfully.',
            );
            onProgress?.call(status);
            return status;
          }

          // Active printing / spooling
          final liveStatus = SpoolerJobStatus(
            id: id,
            state: isPrinting ? SpoolerState.printing : SpoolerState.spooling,
            rawStatus: isPrinting ? 'Printing' : 'Spooling',
            pagesPrinted: pagesPrinted,
            totalPages: totalPages,
            message: isPrinting
                ? 'Printing page $pagesPrinted of $totalPages...'
                : 'Spooling document to printer...',
          );
          onProgress?.call(liveStatus);
        }
      } catch (_) {}
    }

    return const SpoolerJobStatus(
      id: 0,
      state: SpoolerState.completed,
      rawStatus: 'TimedOut',
      pagesPrinted: 1,
      totalPages: 1,
    );
  }

  /// Dispatches PDF bytes directly to the target Windows Print Spooler queue
  static Future<bool> printPdfBytes({
    required Uint8List pdfBytes,
    required String jobName,
    int copies = 1,
    String colorMode = 'BW',
    String? quality,
    int? dpi,
  }) async {
    final targetPrinterName = await StorageService.getPrinterName();
    final selectedPrinter = await findTargetPrinter(targetPrinterName);

    if (selectedPrinter == null) {
      return false;
    }

    // Apply driver PrintTicket configuration before spooling
    await applyPrinterConfiguration(
      printerName: selectedPrinter.name,
      colorMode: colorMode,
      quality: quality,
      dpi: dpi,
    );

    final sw = Stopwatch()..start();
    debugPrint('🖨️ [Print Dispatch] Sending "$jobName" to "${selectedPrinter.name}" | Copies: $copies | Mode: $colorMode | Quality: $quality | DPI: $dpi');

    for (int i = 0; i < copies; i++) {
      bool success = false;
      // Retry up to 3 times in case the Windows printer port or spooler handle is momentarily busy
      for (int attempt = 1; attempt <= 3; attempt++) {
        success = await Printing.directPrintPdf(
          printer: selectedPrinter,
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: '${jobName}_copy_${i + 1}',
          format: PdfPageFormat.a4,
          usePrinterSettings: true,
        );
        if (success) break;
        if (attempt < 3) {
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
      if (!success) return false;
    }

    debugPrint('🏁 [Print Dispatch] Successfully submitted "$jobName" to Windows Spooler in ${sw.elapsedMilliseconds}ms');
    return true;
  }

  /// Opens the native Windows Print Dialog / Preview for 100% guaranteed driver rendering
  static Future<bool> printWithDialog({
    required Uint8List pdfBytes,
    required String jobName,
    String colorMode = 'BW',
    String? quality,
    int? dpi,
  }) async {
    final targetPrinterName = await StorageService.getPrinterName();
    await applyPrinterConfiguration(
      printerName: targetPrinterName,
      colorMode: colorMode,
      quality: quality,
      dpi: dpi,
    );

    return await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: jobName,
      format: PdfPageFormat.a4,
      usePrinterSettings: true,
    );
  }

  /// Checks if Windows Print Spooler logged a print processor crash (0x6BE) in the last few seconds
  static Future<String?> checkRecentSpoolerError() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PrintService/Operational'; StartTime=(Get-Date).AddSeconds(-8)} -MaxEvents 5 -ErrorAction SilentlyContinue | ForEach-Object { if (\$_.Id -eq 842 -and \$_.Message -like '*0x6BE*') { 'CRASH_0x6BE' } }",
        ],
        runInShell: true,
      );
      final out = result.stdout.toString().trim();
      if (out.contains('CRASH_0x6BE')) {
        return 'HP Driver filter crashed in Windows Spooler (0x6BE). Please use "Reprint via Dialog" to print with native Windows rendering.';
      }
    } catch (_) {}
    return null;
  }
}
