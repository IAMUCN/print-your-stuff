import 'dart:io';
import 'dart:typed_data';
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

  /// Injects Color Mode (Grayscale vs Color), Quality (Draft/Normal/High), and DPI (300/600/1200)
  /// directly into the Windows Print Spooler and HP PrintTicket driver settings.
  static Future<void> applyPrinterConfiguration({
    required String printerName,
    required String colorMode,
    String? quality,
    int? dpi,
  }) async {
    if (!Platform.isWindows) return;
    try {
      final effectiveQuality = quality ?? await StorageService.getGlobalQuality();
      final effectiveDpi = dpi ?? await StorageService.getGlobalDpi();

      final isColor = colorMode.toUpperCase() == 'COLOR';
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
      final dmColor = isColor ? 2 : 1; // Win32 DEVMODE: 1=Monochrome, 2=Color
      final colorOption = isColor ? 'psk:Color' : 'psk:Grayscale';
      final sanitizedName = _sanitizeForPs(printerName);

      // We update BOTH the legacy Win32 DEVMODE structure (which Win32 GDI & PDFium CreateDC use)
      // AND the modern V4 PrintTicket XML (which Windows XPS filter pipeline uses).
      final script = '''
\$name = '$sanitizedName';

# 1. Update Win32 DEVMODE via SetPrinter Level 9 (ensures CreateDC picks up exact DPI & Monochrome)
try {
  \$typeDef = @'
using System;
using System.Runtime.InteropServices;
public class Win32DevModeHelper {
    [DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int DocumentProperties(IntPtr hwnd, IntPtr hPrinter, string pDeviceName, IntPtr pDevModeOutput, IntPtr pDevModeInput, int fMode);
    [DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, ref PRINTER_DEFAULTS pDefault);
    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool SetPrinter(IntPtr hPrinter, int Level, IntPtr pPrinter, int Command);

    [StructLayout(LayoutKind.Sequential)]
    public struct PRINTER_DEFAULTS {
        public IntPtr pDatatype;
        public IntPtr pDevMode;
        public int DesiredAccess;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public short dmOrientation;
        public short dmPaperSize;
        public short dmPaperLength;
        public short dmPaperWidth;
        public short dmScale;
        public short dmCopies;
        public short dmDefaultSource;
        public short dmPrintQuality;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PRINTER_INFO_9 {
        public IntPtr pDevMode;
    }

    public static bool Apply(string printerName, short dpi, short colorMode) {
        PRINTER_DEFAULTS def = new PRINTER_DEFAULTS();
        def.DesiredAccess = 0xF000C; // PRINTER_ALL_ACCESS
        IntPtr hPrinter;
        if (!OpenPrinter(printerName, out hPrinter, ref def)) {
            def.DesiredAccess = 0x00020000;
            if (!OpenPrinter(printerName, out hPrinter, ref def)) return false;
        }
        int size = DocumentProperties(IntPtr.Zero, hPrinter, printerName, IntPtr.Zero, IntPtr.Zero, 0);
        if (size <= 0) { ClosePrinter(hPrinter); return false; }
        IntPtr buffer = Marshal.AllocHGlobal(size);
        if (DocumentProperties(IntPtr.Zero, hPrinter, printerName, buffer, IntPtr.Zero, 2) < 0) {
            Marshal.FreeHGlobal(buffer);
            ClosePrinter(hPrinter);
            return false;
        }
        DEVMODE dm = (DEVMODE)Marshal.PtrToStructure(buffer, typeof(DEVMODE));
        dm.dmPrintQuality = dpi;
        dm.dmYResolution = dpi;
        dm.dmColor = colorMode;
        dm.dmFields |= (0x00000400 | 0x00002000 | 0x00000800); // DM_PRINTQUALITY | DM_YRESOLUTION | DM_COLOR
        Marshal.StructureToPtr(dm, buffer, false);
        DocumentProperties(IntPtr.Zero, hPrinter, printerName, buffer, buffer, 10); // DM_IN_BUFFER | DM_OUT_BUFFER
        PRINTER_INFO_9 pi9 = new PRINTER_INFO_9();
        pi9.pDevMode = buffer;
        IntPtr pPi9 = Marshal.AllocHGlobal(Marshal.SizeOf(pi9));
        Marshal.StructureToPtr(pi9, pPi9, false);
        SetPrinter(hPrinter, 9, pPi9, 0);
        Marshal.FreeHGlobal(pPi9);
        Marshal.FreeHGlobal(buffer);
        ClosePrinter(hPrinter);
        return true;
    }
}
'@
  if (-not ([System.Management.Automation.PSTypeName]'Win32DevModeHelper').Type) {
    Add-Type -TypeDefinition \$typeDef -ErrorAction SilentlyContinue
  }
  [Win32DevModeHelper]::Apply(\$name, [short]$effectiveDpi, [short]$dmColor)
} catch {}

# 2. Update V4 PrintTicket XML via Set-PrintConfiguration
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
    } catch (_) {}
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

    // Give spooler a brief moment to ensure driver configuration is flushed
    await Future.delayed(const Duration(milliseconds: 500));

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
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
      if (!success) return false;
    }

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
